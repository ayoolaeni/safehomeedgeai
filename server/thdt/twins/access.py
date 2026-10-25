"""Agentic Access & Security Digital Twin (AA&SDT): locks, camera, intrusion.

Agentic, Edge, Safe and Resilient AI; Green AI is excluded because security
is continuity-critical, not a resource-optimisation problem. Letting a
stranger in is always a human decision.
"""

from ..environment import SITTING
from ..model import FAILSAFE, HUMAN_ONLY
from .base import Twin


class AccessSecurityTwin(Twin):
    code = "AA&SDT"
    name = "Access & Security"
    principles = frozenset({"agentic", "edge", "safe", "resilient"})
    excluded_why = "Green AI excluded: security is continuity-critical, not an efficiency problem."
    agents = ("Entry Recognition Agent", "Lock Control Agent", "Intrusion Detection Agent",
              "Egress Support Agent")
    actions = frozenset({"LOCK", "UNLOCK", "ARM", "DISARM", "EMERGENCY_UNLOCK_ALL", "ALARM_INTRUDER"})

    def observe(self):
        env, home = self.home.env, self.home
        self.dev("alarm_panel").on = env.armed
        self.dev("alarm_panel").value = "ARMED" if env.armed else "DISARMED"
        cam = self.dev("camera_front")
        if env.at_door:
            cam.value = f"{home.resident(env.at_door)['name']} recognised"
        elif env.visitor_at_door:
            cam.value = "Unknown visitor"
        else:
            cam.value = "Clear"
        # A recognised resident walks in once the front door is unlocked.
        if env.at_door and not self.dev("lock_front").on:
            rid, env.at_door = env.at_door, None
            home.move_resident(rid, SITTING)
        if env.visitor_at_door and not self.dev("lock_front").on:
            env.visitor_at_door = False
            for p in [p for p in home.pending if p.twin == self.code and p.action == "UNLOCK"]:
                home.pending.remove(p)
            if home.ahdt.emergencies:
                home.log(self.code, "ENTRY", "Front door unlocked for evacuation while a visitor was outside.")
            else:
                home.log(self.code, "ENTRY", "Visitor let in by a resident.")

    def decide(self):
        env, home, out = self.home.env, self.home, []
        front, back = self.dev("lock_front"), self.dev("lock_back")
        nobody_home = not any(r["location"] for r in home.residents)
        night = env.hour >= 22 or env.hour < 6

        def add(p):
            if p:
                out.append(p)

        if env.at_door and front.on:
            name = home.resident(env.at_door)["name"]
            add(self.propose("UNLOCK", f"{name} recognised at the front door (on-device recognition)."
                             + (" Intrusion alarm will be disarmed." if env.armed else ""), front.id,
                             agent="Entry Recognition Agent"))
        if env.visitor_at_door and front.on:
            add(self.propose("UNLOCK", "Unknown visitor at the front door. Only a resident can let a "
                             "stranger in.", front.id, confidence="LOW", category=HUMAN_ONLY,
                             agent="Entry Recognition Agent", cooldown_s=60))
        if nobody_home and not env.at_door:
            for lock in (front, back):
                if not lock.on:
                    add(self.propose("LOCK", f"Everyone has left: lock the {lock.name.lower()}.", lock.id,
                                     agent="Lock Control Agent"))
            if not env.armed and front.on and back.on:
                add(self.propose("ARM", "Everyone has left and the doors are locked: arm the "
                                 "intrusion alarm.", "alarm_panel", agent="Intrusion Detection Agent"))
        elif night:
            for lock in (front, back):
                if not lock.on:
                    add(self.propose("LOCK", f"Night time: lock the {lock.name.lower()}.", lock.id,
                                     agent="Lock Control Agent", cooldown_s=60))
        if env.intruder:
            if env.armed:
                add(self.propose("ALARM_INTRUDER", "Movement at the back door while the house is "
                                 "armed and empty.", "alarm_panel", category=FAILSAFE,
                                 agent="Intrusion Detection Agent", cooldown_s=30))
            else:
                home.ahdt.escalate(self.code, "Movement at the back door",
                                   "Unrecognised movement at the back door. Doors: front "
                                   f"{'locked' if front.on else 'UNLOCKED'}, back "
                                   f"{'locked' if back.on else 'UNLOCKED'}.", "WARN", "kitchen",
                                   once_key="intruder_home")
        return out

    def actuate(self, p):
        env, home = self.home.env, self.home
        d = home.devices.get(p.device or "")
        if p.action in ("LOCK", "UNLOCK") and d:
            d.on = p.action == "LOCK"
            if p.action == "UNLOCK" and env.armed and d.id == "lock_front":
                env.armed = False
                return f"{d.name} unlocked and alarm disarmed"
            return f"{d.name} {'locked' if d.on else 'unlocked'}"
        if p.action in ("ARM", "DISARM"):
            env.armed = p.action == "ARM"
            if not env.armed:
                home.clear_alert("intruder")
            return f"intrusion alarm {'armed' if env.armed else 'disarmed'}"
        if p.action == "EMERGENCY_UNLOCK_ALL":
            self.dev("lock_front").on = self.dev("lock_back").on = False
            env.armed = False
            return "all doors unlocked for evacuation"
        if p.action == "ALARM_INTRUDER":
            home.devices["siren"].on = True
            home.alert_if(True, "intruder", "CRITICAL", self.code, "Intruder alarm",
                          "Movement at the back door while armed. Resident and contacts notified.",
                          room="kitchen", resettable=True)
            home.ahdt.escalate(self.code, "Intruder alarm", "Movement at the back door while the house "
                               "is armed and empty. Siren sounding.", "CRITICAL", "kitchen")
            return "siren on, residents notified"
        return "no change"

    def summary(self):
        env = self.home.env
        f = "locked" if self.dev("lock_front").on else "UNLOCKED"
        b = "locked" if self.dev("lock_back").on else "UNLOCKED"
        return f"Front {f} · back {b} · alarm {'ARMED' if env.armed else 'disarmed'}"

    def status(self):
        if self.home.env.intruder and self.home.env.armed:
            return "ALERT"
        return "WARN" if self.home.env.visitor_at_door else "OK"
