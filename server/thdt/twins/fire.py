"""Agentic Fire & Safety Digital Twin (AF&SDT).

Agentic, Edge, Safe and Resilient AI; Green AI is excluded because life
safety is not a resource-optimisation problem. Biased to alert rather than
stay silent, never silences its own alarm, and permanently non-graduating.
"""

from ..environment import CO_ALARM, FIRE_ROOMS, GAS_ALARM, GENBAY, HEAT_ALARM, KITCHEN, SMOKE_ALARM
from ..model import FAILSAFE
from .base import Twin

SELF_TEST_EVERY_SIM_S = 6 * 3600
SEVERITY = {"ambiguous": 1, "gas": 2, "fire": 3}


class FireSafetyTwin(Twin):
    code = "AF&SDT"
    name = "Fire & Safety"
    principles = frozenset({"agentic", "edge", "safe", "resilient"})
    excluded_why = "Green AI excluded: an efficiency objective has no place in fire and life safety."
    agents = ("Detection Agent", "Suppression Agent", "Evacuation Support Agent", "Escalation Agent",
              "Health/Self-Test Agent")
    actions = frozenset({"ALARM_ON", "ALARM_OFF", "SPRINKLER_ON", "SPRINKLER_OFF", "VENT_FAN_ON",
                         "VENT_FAN_OFF", "SELF_TEST"})
    non_graduating = True

    def __init__(self, home, saved_graduation=None):
        super().__init__(home, saved_graduation)
        self.handled: dict[str, str] = {}   # room -> hazard kind already responded to
        self.last_self_test = home.env.sim_s

    def readings(self, room: str) -> dict:
        h = self.home.env.hazard[room]
        return {"smoke": h["smoke"], "heat": h["heat"], "co": h["co"], "gas": h["gas"]}

    def abnormal(self, room: str) -> list[str]:
        r, out = self.readings(room), []
        if r["smoke"] >= SMOKE_ALARM and room != GENBAY:
            out.append(f"smoke {r['smoke']:.1f} %/m")
        if r["heat"] >= HEAT_ALARM:
            out.append(f"heat {r['heat']:.0f} °C")
        if r["co"] >= CO_ALARM:
            out.append(f"CO {r['co']:.0f} ppm")
        if room == KITCHEN and r["gas"] >= GAS_ALARM:
            out.append(f"gas {r['gas']:.0f} %LEL")
        return out

    def observe(self):
        env = self.home.env
        for room in FIRE_ROOMS:
            r = self.readings(room)
            for kind in ("smoke", "heat", "co"):
                dev = self.home.devices.get(f"{kind}_{room}")
                if not dev:
                    continue
                dev.functional = dev.id not in env.faults
                dev.value = round(r[kind], 1) if dev.functional else None
            if room == KITCHEN:
                self.dev("gas_kitchen").value = round(r["gas"], 1)
        for dev_id in env.faults:
            d = self.home.devices.get(dev_id)
            if d and d.twin == self.code:
                self.home.alert_if(True, f"fault_{dev_id}", "WARN", self.code, "Detector degraded",
                                   f"{d.name} is not reporting - redundant detectors still cover the room")

    def decide(self):
        out, env = [], self.home.env

        def add(p):
            if p:
                out.append(p)

        for room in FIRE_ROOMS:
            found = self.abnormal(room)
            if not found:
                self.handled.pop(room, None)
                continue
            gas_only = found and all(f.startswith("gas") for f in found)
            co_only = all(f.startswith("CO") for f in found)
            if room == GENBAY and co_only:
                continue   # generator exhaust: handled by the Energy twin's interlock
            kind = "gas" if gas_only else ("fire" if len(found) >= 2 else "ambiguous")
            # Only escalate upwards: suppression lowering the readings is not a new event.
            if SEVERITY[kind] <= SEVERITY.get(self.handled.get(room), 0):
                continue
            self.handled[room] = kind
            room_name = self.home.room_name(room)
            what = ", ".join(found)
            # Fail-alert default: the siren always sounds, even on one reading.
            add(self.propose("ALARM_ON", f"{room_name}: {what}.", "siren", {"room": room, "kind": kind},
                             category=FAILSAFE, agent="Detection Agent", cooldown_s=2))
            if kind == "fire":
                if room == KITCHEN:
                    add(self.propose("SPRINKLER_ON", f"Confirmed fire in the kitchen ({what}): "
                                     "discharging the sprinkler.", "sprinkler_kitchen",
                                     category=FAILSAFE, agent="Suppression Agent", cooldown_s=2))
                self.home.ahdt.emergency("fire", room, what)
            elif kind == "gas":
                add(self.propose("VENT_FAN_ON", f"Gas leak in the kitchen ({what}): extracting air.",
                                 "vent_fan_kitchen", category=FAILSAFE, agent="Suppression Agent",
                                 cooldown_s=2))
                self.home.ahdt.emergency("gas", room, what)
            else:
                self.home.ahdt.escalate(self.code, "Unconfirmed hazard reading",
                                        f"{room_name}: {what}. Only one detector type is abnormal; "
                                        "please check the room.", "CRITICAL", room)

        # Health/Self-Test Agent: periodic detector self-test.
        if env.sim_s - self.last_self_test >= SELF_TEST_EVERY_SIM_S:
            self.last_self_test = env.sim_s
            add(self.propose("SELF_TEST", "Scheduled detector self-test.", category=FAILSAFE,
                             agent="Health/Self-Test Agent", cooldown_s=5))
        return out

    def actuate(self, p):
        home = self.home
        if p.action == "ALARM_ON":
            self.dev("siren").on = True
            room = p.params.get("room")
            kind = p.params.get("kind", "fire")
            title = {"fire": "FIRE", "gas": "GAS LEAK"}.get(kind, "Hazard detected")
            home.alert_if(True, f"fire_{room}", "CRITICAL", self.code, f"{title} · {home.room_name(room)}",
                          p.reason, room=room, resettable=False)
            return "siren and strobe on"
        if p.action == "ALARM_OFF":
            self.dev("siren").on = False
            self.handled.clear()
            for a in list(home.alerts.values()):
                if a["twin"] == self.code:
                    home.clear_alert(a["id"])
            return "alarm reset by a person"
        if p.action in ("SPRINKLER_ON", "SPRINKLER_OFF"):
            self.dev("sprinkler_kitchen").on = p.action == "SPRINKLER_ON"
            return f"sprinkler {'discharging' if self.dev('sprinkler_kitchen').on else 'stopped'}"
        if p.action in ("VENT_FAN_ON", "VENT_FAN_OFF"):
            self.dev("vent_fan_kitchen").on = p.action == "VENT_FAN_ON"
            return f"extraction fan {'on' if self.dev('vent_fan_kitchen').on else 'off'}"
        if p.action == "SELF_TEST":
            dets = [d for d in home.devices.values() if d.twin == self.code and d.kind == "sensor"]
            bad = [d.name for d in dets if not d.functional]
            return f"{len(dets) - len(bad)}/{len(dets)} detectors passed" + (f"; failed: {', '.join(bad)}"
                                                                           if bad else "")
        return "no change"

    def summary(self):
        if self.dev("siren").on:
            return "ALARM ACTIVE - " + ", ".join(self.home.room_name(r) for r in self.handled) if self.handled \
                else "ALARM ACTIVE"
        n = sum(1 for d in self.home.devices.values() if d.twin == self.code and d.kind == "sensor")
        return f"All clear · {n} detectors monitored · non-graduating by design"

    def status(self):
        if self.dev("siren").on:
            return "ALERT"
        return "WARN" if self.home.env.faults else "OK"
