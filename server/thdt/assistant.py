"""Edge Inference & Routing Agent: answers residents' typed or spoken requests.

Routing, cheapest first (Edge + Green AI):
  1. Local rules: device commands and status questions, answered instantly.
  2. The local small language model (Ollama) on the home server.
  3. Escalation to the cloud LLM, only through the AHDT Escalation Gateway.
Commands found here are executed as the resident's own commands, so they pass
through the same Thriftogentic AI guardrails as a tap in the app.
"""

import json
import re
import threading
import urllib.error
import urllib.request

ROOM_WORDS = {
    "sitting": "sitting_room", "living": "sitting_room", "lounge": "sitting_room", "parlour": "sitting_room",
    "kitchen": "kitchen", "bedroom": "bedroom", "bed room": "bedroom", "bathroom": "bathroom",
    "toilet": "bathroom", "entrance": "entrance", "porch": "entrance", "compound": "compound",
    "garden": "compound", "outside": "compound",
}


class LocalSLM:
    def __init__(self, cfg: dict, status: dict):
        o = cfg.get("ollama", {})
        self.enabled = bool(o.get("enabled", True))
        self.url = o.get("url", "http://localhost:11434").rstrip("/")
        self.model = o.get("model", "llama3.2")
        self.status = status

    def check(self) -> bool:
        if not self.enabled:
            self.status.update(available=False, last_error="disabled in config.json")
            return False
        try:
            with urllib.request.urlopen(f"{self.url}/api/tags", timeout=3) as r:
                names = [m.get("name", "") for m in json.loads(r.read()).get("models", [])]
            ok = any(n == self.model or n.startswith(self.model + ":") for n in names)
            self.status.update(available=ok, last_error="" if ok else f"model {self.model} not pulled")
            return ok
        except (OSError, ValueError, urllib.error.URLError) as e:
            self.status.update(available=False, last_error=f"Ollama not reachable ({e.__class__.__name__})")
            return False

    def generate(self, prompt: str, timeout: float = 90) -> str | None:
        body = json.dumps({"model": self.model, "prompt": prompt, "stream": False,
                           "options": {"num_predict": 160, "temperature": 0.3}}).encode()
        req = urllib.request.Request(f"{self.url}/api/generate", body, {"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read()).get("response", "").strip() or None
        except (OSError, ValueError, urllib.error.URLError) as e:
            self.status.update(last_error=f"generate failed ({e.__class__.__name__})")
            return None


class Assistant:
    def __init__(self, home, slm: LocalSLM, deliver):
        self.home = home
        self.slm = slm
        self.deliver = deliver          # callback(answer_dict), run on the main loop

    def handle(self, qid: str, text: str):
        """Called on the main loop. Rules answer now; the SLM answers on a thread."""
        home = self.home
        home.log("ARDT", "ASK", text[:120])
        answer = self._rules(text)
        if answer:
            self.deliver({"id": qid, "question": text, "answer": answer, "source": "local rules"})
            return
        if self.slm.status.get("available"):
            prompt = self._prompt(text)
            threading.Thread(target=self._slm_answer, args=(qid, text, prompt), daemon=True).start()
            return
        self.deliver({"id": qid, "question": text, "answer": home.ahdt.cloud_escalate(text),
                      "source": "cloud escalation (stub)"})

    def _slm_answer(self, qid, text, prompt):
        reply = self.slm.generate(prompt)
        if reply:
            self.deliver({"id": qid, "question": text, "answer": reply, "source": f"local SLM ({self.slm.model})"})
        else:
            self.deliver({"id": qid, "question": text, "answer": None, "source": "escalate"})

    # ------------------------------------------------------------------

    def _rules(self, text: str) -> str | None:
        t = " " + text.lower().strip() + " "
        home, env = self.home, self.home.env

        room = next((rid for w, rid in ROOM_WORDS.items() if w in t), None)
        off = bool(re.search(r"\b(off|stop)\b", t))
        on = not off and bool(re.search(r"\b(on|start)\b", t))

        def run(device_id, want_on):
            return home.ahdt.manual(device_id, want_on)

        if ("light" in t or "lamp" in t) and (on or off):
            rooms = [room] if room else (["sitting_room"] if "lamp" in t else None)
            if re.search(r"\ball\b", t):
                rooms = [d.room for d in home.devices.values() if d.kind == "light"]
            if not rooms:
                return "Which room? For example: 'turn on the kitchen light'."
            done = [run(f"light_{r}", on) for r in rooms if f"light_{r}" in home.devices]
            return "; ".join(done) or "There is no light in that room."
        if re.search(r"\b(ac|a\.c\.?|air ?con|air-con|air conditioner)\b", t) and (on or off):
            r = room or "sitting_room"
            if f"ac_{r}" not in home.devices:
                return "Only the sitting room and bedroom have air conditioners."
            return run(f"ac_{r}", on)
        if "door" in t and ("lock" in t or "unlock" in t):
            which = "lock_back" if "back" in t else "lock_front"
            return run(which, "unlock" not in t)
        if "pump" in t and (on or off):
            return run("borehole_pump", on)
        if "distil" in t:
            return home.ahdt.distill()
        if re.match(r"\s*(why|how come|how do|how can|explain|should|what if|could|can you|tell me why)\b", t):
            return None   # reasoning questions go to the language model

        if "battery" in t or "power" in t or "solar" in t or "grid" in t or "nepa" in t or "light bill" in t:
            g = " The generator is running." if env.gen_running else ""
            return (f"The house is on {env.source.lower()} power. Grid is {'on' if env.grid_up else 'off'}, "
                    f"battery {env.battery_soc:.0f}%, solar {env.solar_w:.0f} W, load {env.load_w:.0f} W.{g}")
        if "generator" in t or "fuel" in t or "gen " in t:
            return (f"Generator {'running' if env.gen_running else 'off'}, {env.gen_fuel_l:.1f} L fuel, "
                    f"{env.gen_runtime_today_h:.1f} h today, CO {env.gen_co:.0f} ppm.")
        if "water" in t or "tank" in t:
            return (f"Tank at {home.tank_pct():.0f}% ({env.tank_l:.0f} L). Borehole pump "
                    f"{'on' if home.devices['borehole_pump'].on else 'off'}. Quality {env.turbidity:.1f} NTU."
                    + (" A leak is being reported!" if env.leak else ""))
        if "temperature" in t or "hot" in t or "cold" in t or "temp" in t:
            return " ".join(f"{home.room_name(r)} {v:.1f} Â°C." for r, v in env.temps.items())
        if "door" in t or "secure" in t or "lock" in t:
            return home.twins["AA&SDT"].summary() + "."
        if "status" in t or "how is the house" in t or "everything ok" in t or "summary" in t:
            alerts = ", ".join(a["title"] for a in home.alerts.values()) or "no alerts"
            return " ".join(f"{tw.name}: {tw.summary()}." for tw in home.twins.values()) + f" Alerts: {alerts}."
        return None

    def _prompt(self, question: str) -> str:
        home = self.home
        state = " ".join(f"{t.name}: {t.summary()}." for t in home.twins.values())
        alerts = ", ".join(a["title"] for a in home.alerts.values()) or "none"
        return ("You are the resident liaison of a smart home in Lagos, Nigeria, running on the home's "
                "own server. Answer in at most three short sentences, plainly, for a non-technical "
                "resident. Never claim to have switched anything: only the app's controls do that.\n"
                f"Time {home.env.clock}. Home state: {state} Active alerts: {alerts}.\n"
                f"Resident: {question}\nAnswer:")
