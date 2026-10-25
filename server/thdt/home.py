"""Whole-home state shared by the AHDT and every subsystem twin.

This is the AHDT's Spatial & Equipment Registry and Global State: every room,
every device (real or simulated) with its functional/on-off state, where each
resident is, the active alerts, and the snapshot published to the app.
"""

import json
import subprocess
import threading
import time
from pathlib import Path

from . import VERSION
from .audit import AuditLog
from .environment import ROOMS, SITTING, Environment, build_devices
from .thriftogentic import ThriftogenticLayer

ESP_FRESH_S = 180     # the lamp counts as linked if it spoke within 3 minutes


class Home:
    def __init__(self, cfg: dict, data_dir: Path, publish=None):
        from .ahdt import AHDT
        from .twins import ALL_TWINS

        self.cfg = cfg
        self.data_dir = data_dir
        self.publish = publish or (lambda topic, payload, retain=False: None)
        self.env = Environment(cfg.get("start_time", "18:00"), cfg.get("sim_speed", 60))
        self.devices = build_devices()
        self.rooms = {r.id: r for r in ROOMS}
        self.residents = [{"id": r["id"], "name": r["name"], "location": SITTING, "prefs": {"temp": 23.0}}
                          for r in cfg.get("residents", [])] or [
            {"id": "r1", "name": "Resident", "location": SITTING, "prefs": {"temp": 23.0}}]
        self.pending = []
        self.alerts: dict[str, dict] = {}
        self.messages: list[dict] = []
        self.answers: list[dict] = []
        self.audit = AuditLog(data_dir / "thdt_audit.db")
        self.thriftogentic = ThriftogenticLayer(self)
        self.esp = {"last_seen": 0.0, "mode": None, "status": None, "motion": False, "dark": None,
                    "ip": None, "ssid": None}
        self.slm_status = {"available": False, "model": cfg.get("ollama", {}).get("model", ""), "last_error": ""}
        saved = self._load_graduation()
        self.twins = {}
        for cls in ALL_TWINS:
            self.twins[cls.code] = cls(self, saved.get(cls.code))
        self.ahdt = AHDT(self)
        ok, n, bad = self.audit.verify()
        self.log("AHDT", "BOOT", f"THDT home server {VERSION} started. Every twin in MANUAL (fail-safe "
                 f"default). Audit chain {'intact' if ok else f'BROKEN at #{bad}'} ({n} entries).")

    # --- logging, alerts, messages -------------------------------------------

    def log(self, twin: str, typ: str, detail: str) -> dict:
        return self.audit.log(twin, typ, detail, self.env.clock)

    def alert_if(self, cond: bool, aid: str, severity: str, twin: str, title: str, detail: str,
                 room: str | None = None, resettable: bool = True):
        if cond:
            if aid not in self.alerts:
                self.alerts[aid] = {"id": aid, "severity": severity, "twin": twin, "title": title,
                                    "detail": detail, "room": room, "resettable": resettable,
                                    "ts": time.time(), "sim": self.env.clock}
                self.log(twin, "ALERT", f"{title}: {detail}")
            else:
                a = self.alerts[aid]
                if a["title"] != title:
                    self.log(twin, "ALERT", f"{title}: {detail}")
                a.update(title=title, detail=detail, severity=severity)
        elif aid in self.alerts and self.alerts[aid]["resettable"]:
            self.clear_alert(aid)

    def clear_alert(self, aid: str):
        a = self.alerts.pop(aid, None)
        if a:
            self.log(a["twin"], "CLEARED", a["title"])

    def message(self, text: str, resident: str | None = None, speak: bool = True):
        self.messages.insert(0, {"ts": time.time(), "sim": self.env.clock, "text": text, "resident": resident})
        del self.messages[20:]
        self.log("ARDT", "MESSAGE", text)
        if speak and self.cfg.get("laptop_voice"):
            _speak(text)

    # --- people and places ---------------------------------------------------

    def resident(self, rid: str) -> dict:
        return next(r for r in self.residents if r["id"] == rid)

    def move_resident(self, rid: str, room: str | None):
        r = self.resident(rid)
        if r["location"] != room:
            r["location"] = room
            where = self.room_name(room) if room else "away from home"
            self.log("AHDT", "PRESENCE", f"{r['name']} is now in {where}" if room else f"{r['name']} is {where}")

    def occupied_rooms(self) -> set[str]:
        rooms = {r["location"] for r in self.residents if r["location"]}
        if self.esp_linked() and self.esp["motion"]:
            rooms.add(SITTING)
        return rooms

    def room_name(self, room_id: str | None) -> str:
        return self.rooms[room_id].name if room_id in self.rooms else (room_id or "")

    def tank_pct(self) -> float:
        return 100.0 * self.env.tank_l / self.env.tank_cap_l

    def observe_presence(self):
        occ = self.occupied_rooms()
        for r in self.rooms:
            d = self.devices[f"presence_{r}"]
            d.value = d.on = r in occ

    # --- the real ESP32 lamp ---------------------------------------------------

    def esp_linked(self) -> bool:
        return time.time() - self.esp["last_seen"] < ESP_FRESH_S

    def esp_command(self, on: bool):
        self.publish("home/light/cmd", "LIGHT_ON" if on else "LIGHT_OFF")

    # --- graduation persistence ------------------------------------------------

    def _load_graduation(self) -> dict:
        try:
            return json.loads((self.data_dir / "graduation.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}

    def save_graduation(self):
        data = {code: t.graduation.save() for code, t in self.twins.items()}
        (self.data_dir / "graduation.json").write_text(json.dumps(data, indent=1), encoding="utf-8")

    # --- snapshot for the app ---------------------------------------------------

    def snapshot(self) -> dict:
        env = self.env
        ok, n, bad = self.audit_status
        return {
            "server": VERSION, "ts": time.time(), "sim_time": env.clock, "sim_speed": env.speed,
            "dark": env.is_dark, "outdoor_temp": round(env.outdoor_temp, 1),
            "connectivity": {"lan": True, "broadband": env.broadband_up, "cellular": env.cellular_up,
                             "cloud_llm": "stub"},
            "slm": self.slm_status,
            "energy": {"source": env.source, "grid": env.grid_up, "solar_w": round(env.solar_w),
                       "load_w": round(env.load_w), "battery_soc": round(env.battery_soc, 1),
                       "power_ok": env.power_ok, "generator": {
                           "running": env.gen_running, "fuel_l": round(env.gen_fuel_l, 1),
                           "co_ppm": round(env.gen_co, 1), "runtime_h": round(env.gen_runtime_today_h, 2)},
                       "circuits": env.circuits},
            "water": {"tank_pct": round(self.tank_pct(), 1), "tank_l": round(env.tank_l),
                      "leak": env.leak, "turbidity": round(env.turbidity, 1), "raining": env.raining},
            "security": {"armed": env.armed, "at_door": env.at_door, "visitor": env.visitor_at_door,
                         "intruder": env.intruder},
            "rooms": [dict(r.to_dict(), occupied=(r.id in self.occupied_rooms()),
                           temp=(round(env.temps[r.id], 1) if r.id in env.temps else None),
                           humidity=(round(env.humidity[r.id]) if r.id in env.humidity else None),
                           powered=env.circuits.get(r.id, True))
                      for r in self.rooms.values()],
            "devices": [d.to_dict() for d in self.devices.values()],
            "residents": [{"id": r["id"], "name": r["name"], "location": r["location"]} for r in self.residents],
            "ahdt": self.ahdt.to_dict(),
            "twins": [t.to_dict() for t in self.twins.values()],
            "pending": [p.to_dict() for p in self.pending],
            "alerts": sorted(self.alerts.values(), key=lambda a: (a["severity"] != "CRITICAL", -a["ts"])),
            "messages": self.messages[:10],
            "events": self.audit.recent(40),
            "audit": {"count": n, "verified": ok, "broken_at": bad},
            "esp32": {"linked": self.esp_linked(),
                      "last_seen_s": (round(time.time() - self.esp["last_seen"]) if self.esp["last_seen"] else None),
                      "mode": self.esp["mode"], "status": self.esp["status"], "ip": self.esp["ip"],
                      "ssid": self.esp["ssid"]},
        }

    @property
    def audit_status(self):
        # Re-verifying the whole chain every second would be wasteful: cache it.
        now = time.time()
        if now - getattr(self, "_audit_checked", 0) > 30:
            self._audit_cache = self.audit.verify()
            self._audit_checked = now
        ok, _, bad = self._audit_cache
        return ok, self.audit.count, bad


def _speak(text: str):
    """Resident Liaison voice on the laptop, using Windows' offline speech engine."""
    def run():
        safe = text.replace("'", "''")
        try:
            subprocess.run(["powershell", "-NoProfile", "-Command",
                            "Add-Type -AssemblyName System.Speech; "
                            f"(New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('{safe}')"],
                           timeout=60, capture_output=True,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        except (OSError, subprocess.SubprocessError):
            pass
    threading.Thread(target=run, daemon=True).start()
