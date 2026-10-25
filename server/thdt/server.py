"""Runs the home server: MQTT link, ESP32 bridge, app commands, main loop.

Topics (all JSON):
  thdt/state   retained   whole-home snapshot, about once a second
  thdt/cmd     app -> server commands (see _handle_command)
  thdt/answer  server -> app answers to assistant questions
  thdt/ack     server -> app result of a command, for a short confirmation
  home/#       the existing ESP32 lamp contract, unchanged
"""

import json
import queue
import threading
import time
import uuid

import paho.mqtt.client as mqtt

from .assistant import Assistant, LocalSLM
from .home import Home
from .model import MODES

SNAPSHOT_EVERY_S = 1.0
TICK_S = 0.25


class Server:
    def __init__(self, cfg: dict, data_dir):
        self.cfg = cfg
        self.inbox: queue.Queue = queue.Queue()
        self.client = None
        self.connected = False
        self.home = Home(cfg, data_dir, publish=self.publish)
        self.slm = LocalSLM(cfg, self.home.slm_status)
        self.assistant = Assistant(self.home, self.slm, lambda ans: self.inbox.put(("answer", ans)))
        self._esp_log_seen: set[int] = set()
        self._running = True

    # ------------------------------------------------------------------ MQTT

    def connect(self):
        b = self.cfg["broker"]
        c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"thdt-server-{uuid.uuid4().hex[:6]}")
        if b.get("username"):
            c.username_pw_set(b["username"], b.get("password", ""))
        c.on_connect = self._on_connect
        c.on_disconnect = self._on_disconnect
        c.on_message = lambda _c, _u, m: self.inbox.put(("mqtt", m.topic, m.payload.decode("utf-8", "replace"),
                                                        m.retain))
        c.reconnect_delay_set(1, 10)
        self.client = c
        try:
            c.connect_async(b["host"], int(b.get("port", 1883)), keepalive=30)
        except (OSError, ValueError) as e:
            print(f"server: cannot reach broker {b['host']}: {e}")
        c.loop_start()

    def _on_connect(self, client, _u, _flags, reason, _props=None):
        if reason.is_failure:
            print(f"server: broker refused the connection ({reason}). Check username/password in config.json.")
            return
        self.connected = True
        print("server: connected to the broker")
        client.subscribe([("thdt/cmd", 1), ("home/#", 0)])

    def _on_disconnect(self, *_a):
        self.connected = False
        print("server: lost the broker, retrying...")

    def publish(self, topic: str, payload, retain: bool = False):
        if self.client is None:
            return
        if not isinstance(payload, str):
            payload = json.dumps(payload, separators=(",", ":"))
        self.client.publish(topic, payload, qos=0 if topic == "thdt/state" else 1, retain=retain)

    # -------------------------------------------------------------- main loop

    def run(self):
        self.connect()
        threading.Thread(target=self._slm_watch, daemon=True).start()
        last, last_snap = time.monotonic(), 0.0
        home = self.home
        try:
            while self._running:
                now = time.monotonic()
                sim_dt = home.env.advance(now - last)
                last = now
                self._drain_inbox()
                self.step(sim_dt)
                if now - last_snap >= SNAPSHOT_EVERY_S:
                    last_snap = now
                    self.publish("thdt/state", home.snapshot(), retain=True)
                time.sleep(TICK_S)
        except KeyboardInterrupt:
            print("\nserver: stopping")
        finally:
            home.log("AHDT", "SHUTDOWN", "Home server stopped.")
            if self.client:
                self.client.loop_stop()
                self.client.disconnect()
            home.audit.close()

    def step(self, sim_dt: float):
        """One tick of the whole home. Also called directly by the tests."""
        home = self.home
        home.observe_presence()
        home.env.step(sim_dt, home.devices, home.occupied_rooms())
        for twin in home.twins.values():
            twin.observe()
        for twin in home.twins.values():
            for p in twin.decide():
                home.ahdt.submit(p)
        home.ahdt.tick()

    def _slm_watch(self):
        while self._running:
            self.slm.check()
            time.sleep(60)

    def _drain_inbox(self):
        while True:
            try:
                item = self.inbox.get_nowait()
            except queue.Empty:
                return
            try:
                if item[0] == "mqtt":
                    _, topic, payload, retained = item
                    if topic == "thdt/cmd":
                        self._handle_command(payload)
                    elif topic.startswith("home/"):
                        self._handle_esp(topic, payload, retained)
                elif item[0] == "answer":
                    self._deliver_answer(item[1])
            except Exception as e:   # a bad message must never stop the house
                print(f"server: error handling {item[:2]}: {e!r}")

    # ---------------------------------------------------------- ESP32 bridge

    def _handle_esp(self, topic: str, payload: str, retained: bool):
        home, esp = self.home, self.home.esp
        if not retained:
            esp["last_seen"] = time.time()
        if topic == "home/light/state":
            home.devices["light_sitting_room"].on = payload.strip() == "ON"
        elif topic == "home/sensors/motion":
            esp["motion"] = payload.strip() == "TRUE"
        elif topic == "home/sensors/light":
            esp["dark"] = json.loads(payload).get("level") == "DARK"
        elif topic == "home/mode/state":
            esp["mode"] = payload.strip()
        elif topic == "home/agent/status":
            s = json.loads(payload)
            esp["status"] = {k: s.get(k) for k in ("state", "stateName", "proposals", "approvalRate", "lastChange")}
        elif topic == "home/wifi/status":
            s = json.loads(payload)
            esp["ip"], esp["ssid"] = s.get("ip"), s.get("ssid")
        elif topic == "home/agent/log" and not retained:
            e = json.loads(payload)
            if e.get("seq") not in self._esp_log_seen:
                self._esp_log_seen.add(e.get("seq"))
                home.log("ESP32", e.get("type", "LOG"), f"Lamp #{e.get('seq')}: {e.get('detail', '')}")
        elif topic == "home/agent/proposal":
            p = json.loads(payload)
            home.log("ESP32", "PROPOSAL", f"On-device lamp agent asks: {p.get('action')} ({p.get('reason')})")

    # -------------------------------------------------------- app commands

    def _ack(self, cmd: dict, result: str):
        self.publish("thdt/ack", {"type": cmd.get("type"), "result": result, "ts": time.time()})

    def _deliver_answer(self, ans: dict):
        home = self.home
        if ans.get("answer") is None:    # the SLM failed: escalate through the AHDT gateway
            ans = dict(ans, answer=home.ahdt.cloud_escalate(ans["question"]), source="cloud escalation (stub)")
        home.answers.insert(0, ans)
        del home.answers[10:]
        home.log("ARDT", "ANSWER", f"[{ans['source']}] {ans['answer'][:160]}")
        self.publish("thdt/answer", ans)

    def _handle_command(self, payload: str):
        cmd = json.loads(payload)
        home, ahdt = self.home, self.home.ahdt
        t = cmd.get("type")
        if t == "device":
            r = ahdt.manual(cmd["device"], cmd.get("on"), cmd.get("action"), cmd.get("params"))
        elif t == "mode":
            r = ahdt.set_mode(cmd.get("twin", "ALL"), cmd.get("mode", "")) if cmd.get("mode") in MODES \
                else "Unknown mode."
        elif t == "respond":
            r = ahdt.respond(cmd["id"], bool(cmd.get("approve")))
        elif t == "ask":
            self.assistant.handle(cmd.get("id") or uuid.uuid4().hex[:8], str(cmd.get("text", ""))[:300])
            return
        elif t == "reset_alarm":
            r = ahdt.manual("siren", action="ALARM_OFF")
            if not r.startswith("Not allowed"):
                for dev in ("sprinkler_kitchen", "vent_fan_kitchen"):
                    if home.devices[dev].on:
                        ahdt.manual(dev, False)
        elif t == "restore_power":
            cut = [room for room, ok in home.env.circuits.items() if not ok]
            r = "; ".join(ahdt.manual("ats", action="RESTORE_CIRCUIT", params={"room": room}) for room in cut) \
                or "All circuits already have power."
        elif t == "set_source":
            r = ahdt.manual("ats", action="SWITCH_SOURCE", params={"source": cmd.get("source", "GRID")})
        elif t == "hazard_suite":
            r = ahdt.hazard_suite(cmd["twin"])
        elif t == "distill":
            r = ahdt.distill()
        elif t == "move":
            home.move_resident(cmd["resident"], cmd.get("room"))
            r = "Moved."
        elif t == "verify_audit":
            ok, n, bad = home.audit.verify()
            home._audit_checked = 0
            r = f"Audit chain {'intact' if ok else f'BROKEN at entry #{bad}'}: {n} entries checked."
            home.log("AHDT", "AUDIT", r)
        elif t == "scenario":
            r = self.scenario(cmd.get("name", ""), cmd.get("room"), cmd.get("value"))
        else:
            r = f"Unknown command {t}."
        self._ack(cmd, r)

    # ------------------------------------------------------------- scenarios

    def scenario(self, name: str, room: str | None = None, value=None) -> str:
        """Demonstration events injected into the simulated home (Layer 1)."""
        home, env = self.home, self.home.env
        first = home.residents[0]
        msg = {
            "blackout": "Grid outage (PHCN) started.", "grid_restore": "Grid supply restored.",
            "fire": f"Fire started in the {home.room_name(room or 'kitchen')}.", "gas": "Gas leak in the kitchen.",
            "gen_co": "Generator bay ventilation blocked.", "leak": "Pipe leak under the kitchen sink.",
            "water_bad": "Borehole water turned cloudy.", "visitor": "Unknown visitor at the front door.",
            "intruder": "Movement at the back door.", "internet_down": "Broadband/satellite link down.",
            "internet_up": "Broadband/satellite link restored.", "cellular_down": "4G/5G backup link down.",
            "cellular_up": "4G/5G backup link restored.", "rain": "Rain started.", "sunny": "Rain stopped.",
            "low_battery": "Battery drained to 18%.", "low_tank": "Tank drawn down to 20%.",
            "low_fuel": "Generator fuel down to 3 L.", "sensor_fault": "A detector stopped reporting.",
            "clear": "All hazards cleared in the simulation.",
        }
        if name == "blackout":
            env.grid_up = False
        elif name == "grid_restore":
            env.grid_up = True
        elif name == "fire":
            env.fire_rooms.add(room or "kitchen")
        elif name == "gas":
            env.gas_leak = True
        elif name == "gen_co":
            env.gen_vent_blocked = True
        elif name == "leak":
            env.leak = True
        elif name == "water_bad":
            env.turbidity = 9.0
        elif name == "arrive":
            rid = value or first["id"]
            home.move_resident(rid, None)
            home.twins["ARDT"].seen[rid] = None
            env.at_door = rid
            msg["arrive"] = f"{home.resident(rid)['name']} arrived at the front door."
        elif name == "leave":
            for r in home.residents:
                home.move_resident(r["id"], None)
            msg["leave"] = "Everyone left the house."
        elif name == "move":
            home.move_resident(value or first["id"], room)
            msg["move"] = f"{home.resident(value or first['id'])['name']} moved to {home.room_name(room)}."
        elif name == "visitor":
            env.visitor_at_door = True
        elif name == "intruder":
            env.intruder = True
        elif name in ("internet_down", "internet_up"):
            env.broadband_up = name == "internet_up"
        elif name in ("cellular_down", "cellular_up"):
            env.cellular_up = name == "cellular_up"
        elif name in ("rain", "sunny"):
            env.raining = name == "rain"
        elif name == "low_battery":
            env.battery_kwh = 0.18 * env.battery_kwh_cap
        elif name == "low_tank":
            env.tank_l = 0.20 * env.tank_cap_l
        elif name == "low_fuel":
            env.gen_fuel_l = 3.0
        elif name == "sensor_fault":
            dev = value or "smoke_bedroom"
            env.faults.add(dev)
            for t in home.twins.values():
                if home.devices.get(dev) and home.devices[dev].twin == t.code:
                    change = t.graduation.record_fault(home.devices[dev].name)
                    if change:
                        home.log(t.code, "GRADUATION", change)
        elif name == "clear":
            env.clear_hazards()
            for d in home.devices.values():
                d.functional = True
        elif name == "time":
            env.set_time(str(value or "18:00"))
            msg["time"] = f"Clock set to {env.clock}."
        elif name == "speed":
            env.speed = max(1.0, min(600.0, float(value or 60)))
            msg["speed"] = f"Simulation speed {env.speed:.0f}x."
        else:
            return f"Unknown scenario {name}."
        home.log("SIM", "SCENARIO", msg.get(name, name))
        return msg.get(name, name)
