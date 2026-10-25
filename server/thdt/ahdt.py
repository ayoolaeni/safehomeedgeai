"""The Agentic Home Digital Twin (AHDT): orchestrator of every subsystem twin.

It holds the full five-principle fusion at whole-home scope and is the only
entity that may:
  * run cross-domain emergency directives (fire -> unlock doors + cut power),
  * escalate to a resident or to the cloud LLM (Escalation Gateway Agent),
  * start a distillation cycle (Distillation Governance Agent),
  * sign off a twin's graduation to THRIFTONOMOUS,
  * arbitrate flexible loads between twins when energy is limited (Green).
Each twin still keeps its own local fail-safes, which do not wait for the AHDT.
"""

import time
from collections import deque

from .environment import EXIT_ROOM, ROOMS_WITH_AC
from .model import (AUTONOMOUS, FAILSAFE, FLEXIBLE, GOVERNANCE, HUMAN_ONLY, INFO, MANUAL, MANUAL_CMD,
                    MODES, PRINCIPLES, Proposal)

OVERRIDE_WINDOW_S = 60

# Device kind -> (action when switched on, action when switched off)
MANUAL_ACTIONS = {
    "light": ("LIGHT_ON", "LIGHT_OFF"), "ac": ("AC_ON", "AC_OFF"), "lock": ("LOCK", "UNLOCK"),
    "pump": ("PUMP_ON", "PUMP_OFF"), "valve": ("OPEN_MAIN_VALVE", "CLOSE_MAIN_VALVE"),
    "irrigation": ("IRRIGATION_ON", "IRRIGATION_OFF"), "treatment": ("TREATMENT_ON", "TREATMENT_OFF"),
    "generator": ("START_GENERATOR", "STOP_GENERATOR"), "load": ("RESTORE_LOAD", "SHED_LOAD"),
    "siren": ("ALARM_ON", "ALARM_OFF"), "sprinkler": ("SPRINKLER_ON", "SPRINKLER_OFF"),
    "fan": ("VENT_FAN_ON", "VENT_FAN_OFF"), "alarm": ("ARM", "DISARM"),
}
OPPOSITE = {a: b for on, off in MANUAL_ACTIONS.values() for a, b in ((on, off), (off, on))}


class AHDT:
    code = "AHDT"
    name = "Agentic Home Digital Twin"
    principles = frozenset(PRINCIPLES)
    agents = ("Spatial & Equipment Registry Agent", "Global State Agent", "Emergency Coordination Agent",
              "Escalation Gateway Agent", "Distillation Governance Agent", "Edge Inference & Routing Agent")

    def __init__(self, home):
        self.home = home
        self.auto_watch: deque = deque()       # autonomous actions watched for human reversal
        self.emergencies: dict[tuple, float] = {}
        self.escalated_once: set[str] = set()
        self.cloud_cases = 0
        self.distill_cycles = 0
        self.last_distill = None

    # ------------------------------------------------------------------
    # Orchestration: every proposal from every twin comes through here.
    # ------------------------------------------------------------------

    def submit(self, p: Proposal) -> str:
        home = self.home
        twin = home.twins.get(p.twin)
        v = home.thriftogentic.evaluate(p)
        p.checks = v.checks
        if not v.allowed:
            home.log(p.twin, "DENIED", f"{p.reason} Blocked by the Thriftogentic AI layer: {v.reasons}.")
            return "denied"
        if p.category in (FAILSAFE, INFO):
            self._execute(p, "FAILSAFE" if p.category == FAILSAFE else "INFO")
            return "executed"
        if p.category in (HUMAN_ONLY, GOVERNANCE):
            self._ask(p)
            return "pending"
        if twin is None or twin.mode == MANUAL:
            # Manual mode: the twin keeps watching but does not act or ask.
            if twin:
                twin._cooldown[p.key()] = time.time() + 300
            home.log(p.twin, "OBSERVED", f"{p.reason} (Manual mode: no action taken.)")
            return "observed"
        if p.category == FLEXIBLE and not self._arbitrate(p):
            return "deferred"
        if (twin.mode == AUTONOMOUS and twin.graduation.thriftonomous and p.confidence == "HIGH"
                and not v.needs_human):
            self._execute(p, "AUTONOMOUS")
            if p.device:
                self.auto_watch.append((time.time(), p))
            return "executed"
        self._ask(p)
        return "pending"

    def _ask(self, p: Proposal):
        self.home.pending.append(p)
        why = "" if p.category not in (HUMAN_ONLY, GOVERNANCE) else " (a person must decide)"
        self.home.log(p.twin, "PROPOSAL", f"{p.reason} -> {p.action}{why}")

    def _execute(self, p: Proposal, how: str) -> str:
        twin = self.home.twins.get(p.twin)
        if p.action == "SIGNOFF":
            return self._signoff(p, True)
        result = twin.actuate(p) if twin else "no twin"
        typ = {"FAILSAFE": "FAILSAFE", "INFO": "INFO", "AUTONOMOUS": "AUTONOMOUS", "APPROVED": "EXECUTED",
               "MANUAL": "MANUAL"}.get(how, how)
        if how != "INFO":
            self.home.log(p.twin, typ, f"{p.action}: {result}." + (f" Reason: {p.reason}" if how != "MANUAL" else ""))
        return result

    def respond(self, pid: str, approve: bool) -> str:
        home = self.home
        p = next((x for x in home.pending if x.id == pid), None)
        if not p:
            return "That request has already been handled."
        home.pending.remove(p)
        if p.category == GOVERNANCE:
            return self._signoff(p, approve)
        twin = home.twins.get(p.twin)
        if twin:
            change = twin.graduation.record_response(approve)
            if change:
                home.log(p.twin, "GRADUATION", change)
            home.save_graduation()
        if not approve:
            if twin:
                twin._cooldown[p.key()] = time.time() + 120
                twin.distill_requests += 1
            home.log(p.twin, "DECLINED", f"{p.action} declined by a resident.")
            return "Declined."
        v = home.thriftogentic.evaluate(p, human=True)   # the world may have changed since it was asked
        p.checks = v.checks
        if not v.allowed:
            home.log(p.twin, "DENIED", f"{p.action} approved, but now blocked: {v.reasons}.")
            return f"Blocked: {v.reasons}"
        return self._execute(p, "APPROVED")

    def manual(self, device_id: str, on: bool | None = None, action: str | None = None,
               params: dict | None = None) -> str:
        """A person's command from the app or the assistant. People always win,
        except where a hard Safe-AI guardrail applies (e.g. an alarm while the
        hazard is still present)."""
        home = self.home
        dev = home.devices.get(device_id)
        if not dev:
            return f"Unknown device {device_id}."
        if action is None:
            if dev.kind not in MANUAL_ACTIONS:
                return f"{dev.name} cannot be switched from the app."
            action = MANUAL_ACTIONS[dev.kind][0 if on else 1]
        params = dict(params or {})
        if action == "AC_ON":
            params.setdefault("setpoint", float(dev.value or 23.0))
        p = Proposal(dev.twin, action, f"Resident command: {action} {dev.name}", dev.id, params,
                     category=MANUAL_CMD, source="Resident (app)")
        v = home.thriftogentic.evaluate(p, human=True)
        if not v.allowed:
            home.log(dev.twin, "DENIED", f"Resident asked for {action} on {dev.name}: {v.reasons}.")
            return f"Not allowed: {v.reasons}"
        self._check_override(p)
        if action == "ALARM_OFF":
            self.emergencies.clear()
        return self._execute(p, "MANUAL")

    def _check_override(self, p: Proposal):
        for item in list(self.auto_watch):
            ts, q = item
            if q.device == p.device and OPPOSITE.get(q.action) == p.action:
                self.auto_watch.remove(item)
                twin = self.home.twins.get(q.twin)
                change = twin.graduation.record_autonomous(True) if twin else None
                self.home.log(q.twin, "OVERRIDE", f"A resident reversed {q.action} on {q.device} within "
                              f"{time.time() - ts:.0f} s.")
                if change:
                    self.home.log(q.twin, "GRADUATION", change)
                self.home.save_graduation()

    # ------------------------------------------------------------------
    # Periodic work
    # ------------------------------------------------------------------

    def tick(self):
        home, now = self.home, time.time()
        timeout = home.cfg.get("proposal_timeout_s", 90)
        for p in list(home.pending):
            if p.category != GOVERNANCE and now - p.created > timeout:
                home.pending.remove(p)
                home.log(p.twin, "EXPIRED", f"No answer to {p.action} within {timeout} s; nothing done.")
        while self.auto_watch and now - self.auto_watch[0][0] > OVERRIDE_WINDOW_S:
            _, q = self.auto_watch.popleft()
            twin = home.twins.get(q.twin)
            if twin:
                twin.graduation.record_autonomous(False)
        for twin in home.twins.values():
            if twin.graduation.tick(now):
                self._ask(Proposal("AHDT", "SIGNOFF", f"The {twin.name} twin has completed its canary period "
                                   "with a high approval rate. Allow it to act on its own (THRIFTONOMOUS)?",
                                   params={"twin": twin.code}, category=GOVERNANCE,
                                   source="Governance sign-off"))
        if not home.env.intruder:
            self.escalated_once.discard("intruder_home")

    def _signoff(self, p: Proposal, approve: bool) -> str:
        twin = self.home.twins.get(p.params.get("twin"))
        if not twin:
            return "Unknown twin."
        result = twin.graduation.signoff(approve)
        self.home.log("AHDT", "SIGNOFF", f"{twin.name}: {result}")
        self.home.save_graduation()
        return result

    # ------------------------------------------------------------------
    # Green AI: whole-home arbitration of flexible loads
    # ------------------------------------------------------------------

    def _priority(self, action: str, device_id: str) -> int:
        if device_id == "borehole_pump":
            return 3 if self.home.tank_pct() < 25 else 1
        return 2   # cooling an occupied room

    def _arbitrate(self, p: Proposal) -> bool:
        home, env = self.home, self.home.env
        if env.source != "BATTERY" or env.battery_soc >= 50:
            return True
        mine = self._priority(p.action, p.device)
        running = [d for d in ("borehole_pump", *(f"ac_{r}" for r in ROOMS_WITH_AC))
                   if home.devices[d].on and d != p.device]
        for d in running:
            if self._priority("", d) >= mine:
                home.log("AHDT", "ARBITRATION", f"Deferred {p.action} ({home.devices[p.device].name}): "
                         f"{home.devices[d].name} has priority while on battery at {env.battery_soc:.0f}%.")
                home.twins[p.twin]._cooldown[p.key()] = time.time() + 60
                return False
        if running:
            home.log("AHDT", "ARBITRATION", f"{home.devices[p.device].name} takes priority on limited battery.")
        return True

    # ------------------------------------------------------------------
    # Emergency Coordination Agent
    # ------------------------------------------------------------------

    def emergency(self, kind: str, room: str, what: str):
        key = (kind, room)
        if key in self.emergencies:
            return
        self.emergencies[key] = time.time()
        home = self.home
        rname = home.room_name(room)
        home.log("AHDT", "EMERGENCY", f"{kind.upper()} in {rname} ({what}). Issuing cross-domain directives.")
        stale = [p for p in home.pending if p.twin in ("ACDT", "AWDT")]
        for p in stale:
            home.pending.remove(p)
        if stale:
            home.log("AHDT", "EMERGENCY", f"Withdrew {len(stale)} comfort/water request(s) for the emergency.")
        directives = [("AA&SDT", "EMERGENCY_UNLOCK_ALL", None, {}, "unlock every door for evacuation")]
        if room == "generator_bay":
            directives.append(("AEDT", "STOP_GENERATOR", "generator", {}, "stop the generator"))
        else:
            directives.append(("AEDT", "CUT_CIRCUIT", None, {"room": room}, f"cut power to the {rname}"))
        if kind == "fire":
            for r in ROOMS_WITH_AC:
                if home.devices[f"ac_{r}"].on:
                    directives.append(("ACDT", "AC_OFF", f"ac_{r}", {}, "stop air circulation spreading smoke"))
            for d in home.devices.values():
                if d.kind == "light" and not d.on and d.room != room:
                    directives.append(("ACDT", "LIGHT_ON", d.id, {}, "evacuation lighting"))
        for twin, action, device, params, why in directives:
            self.submit(Proposal(twin, action, f"AHDT emergency directive ({kind}, {rname}): {why}.", device,
                                 params, category=FAILSAFE, source="Emergency Coordination Agent"))
        route = {r["name"]: self.evacuation_route(r["location"], avoid=room) for r in home.residents if r["location"]}
        guide = "; ".join(f"{n}: {' -> '.join(home.room_name(x) for x in path)}" for n, path in route.items())
        advice = "Leave now and do not switch anything on." if kind == "gas" else "Leave the house now."
        self.escalate("AF&SDT", f"{kind.upper()} in the {rname}",
                      f"{what}. {advice} Doors are unlocked. Route: {guide or 'nobody home'}.",
                      "CRITICAL", room, emergency_services=True)

    def evacuation_route(self, start: str | None, avoid: str | None = None) -> list[str]:
        if not start:
            return []
        rooms = self.home.rooms
        frontier, came = [start], {start: None}
        while frontier:
            cur = frontier.pop(0)
            if cur == EXIT_ROOM:
                break
            for n in rooms[cur].neighbours:
                if n not in came and (n != avoid or n == EXIT_ROOM):
                    came[n] = cur
                    frontier.append(n)
        if EXIT_ROOM not in came:
            return [start, EXIT_ROOM]
        path, cur = [], EXIT_ROOM
        while cur:
            path.append(cur)
            cur = came[cur]
        return path[::-1]

    # ------------------------------------------------------------------
    # Escalation Gateway Agent: the only path to residents and the cloud LLM
    # ------------------------------------------------------------------

    def escalate(self, twin: str, title: str, detail: str, severity: str = "WARN", room: str | None = None,
                 once_key: str | None = None, emergency_services: bool = False):
        if once_key:
            if once_key in self.escalated_once:
                return
            self.escalated_once.add(once_key)
        home, env = self.home, self.home.env
        people = ", ".join(f"{r['name']} in {home.room_name(r['location'])}" if r["location"]
                           else f"{r['name']} away" for r in home.residents)
        context = f" [AHDT context: {env.clock}; {people}; power {env.source} {env.battery_soc:.0f}%]"
        home.message(f"{title}: {detail}", speak=severity == "CRITICAL")
        if severity == "CRITICAL":
            who = "residents and emergency contacts" + (" (+ emergency services, where configured)"
                                                         if emergency_services else "")
            if env.cellular_up:
                home.log("AHDT", "CELLULAR", f"Alert sent over the 4G/5G backup to {who} (stub): {title}.{context}")
            elif env.broadband_up:
                home.log("AHDT", "ESCALATION", f"Cellular down: alert pushed over broadband/satellite to {who}"
                         f" (stub): {title}.{context}")
            else:
                home.log("AHDT", "ESCALATION", f"Both WAN paths down: local siren and voice only for {title}."
                         f"{context}")
        else:
            home.log("AHDT", "ESCALATION", f"{title}: {detail}{context}")

    def cloud_escalate(self, question: str) -> str:
        home, env = self.home, self.home.env
        if not env.broadband_up:
            home.log("AHDT", "CLOUD", f"Deferred cloud escalation (broadband/satellite down; cellular is "
                     f"reserved for emergencies): {question[:80]}")
            return ("I can't answer that on the home server, and the broadband/satellite link is down. "
                    "I've kept your question and will try the cloud model when the link is back.")
        self.cloud_cases += 1
        home.log("AHDT", "CLOUD", f"Escalated to the cloud LLM over broadband/satellite (stub): {question[:80]}")
        return ("That needs the cloud model. In this prototype the escalation is logged instead of calling "
                "a paid API, and the case is kept for the next distillation cycle.")

    # ------------------------------------------------------------------
    # Distillation Governance Agent
    # ------------------------------------------------------------------

    def distill(self) -> str:
        home, env = self.home, self.home.env
        requests = {t.code: t.distill_requests for t in home.twins.values() if t.distill_requests}
        if not env.broadband_up:
            home.log("AHDT", "DISTILL", "Distillation deferred: broadband/satellite link is down.")
            return "Distillation deferred: no broadband/satellite link."
        if not home.cfg.get("distillation_consent", True):
            home.log("AHDT", "DISTILL", "Distillation refused: residents have not consented.")
            return "Residents have not consented to distillation."
        self.distill_cycles += 1
        self.last_distill = env.clock
        src = f"{self.cloud_cases} cloud escalations, twin requests {requests or 'none'}"
        home.log("AHDT", "DISTILL", f"Distillation cycle #{self.distill_cycles} started by the AHDT (sole "
                 f"initiator). Sources: {src}. Consent ledger: yes. Prototype: no model weights changed.")
        self.cloud_cases = 0
        for t in home.twins.values():
            t.distill_requests = 0
        return f"Distillation cycle #{self.distill_cycles} recorded ({src})."

    # ------------------------------------------------------------------
    # Modes, hazard suite, messages
    # ------------------------------------------------------------------

    def set_mode(self, code: str, mode: str) -> str:
        if mode not in MODES:
            return f"Unknown mode {mode}."
        targets = self.home.twins.values() if code == "ALL" else [self.home.twins[code]]
        for t in targets:
            t.mode = mode
            note = ""
            if mode == AUTONOMOUS and not t.graduation.thriftonomous:
                note = " (not yet THRIFTONOMOUS: it will keep asking first)"
            self.home.log(t.code, "MODE", f"{t.name} set to {mode}{note}.")
        return f"{'All twins' if code == 'ALL' else targets[0].name} now {mode}."

    def hazard_suite(self, code: str) -> str:
        t = self.home.twins[code]
        if t.non_graduating:
            return f"{t.name} is permanently non-graduating."
        change = t.graduation.mark_hazard_suite()
        self.home.log(code, "HAZARD_SUITE", "Hazard test suite recorded as passed by a person."
                      + (f" {change}" if change else ""))
        self.home.save_graduation()
        return change or "Hazard suite recorded."

    def welcome_message(self, r: dict) -> str:
        home, env = self.home, self.home.env
        parts = [f"Welcome home, {r['name']}."]
        if not home.devices["lock_front"].on:
            parts.append("Door unlocked.")
        ac = home.devices.get(f"ac_{r['location']}")
        if ac and ac.on:
            parts.append(f"{home.room_name(r['location'])} AC on at {ac.value:.0f} degrees"
                         + (" on solar and battery." if env.source == "BATTERY" else "."))
        if env.source != "GRID":
            parts.append(f"The grid is off; the house is on {env.source.lower()} at {env.battery_soc:.0f} percent.")
        alerts = [a["title"] for a in home.alerts.values()]
        parts.append("Alerts: " + ", ".join(alerts) + "." if alerts
                     else "All fire, water and security systems are normal.")
        return " ".join(parts)

    def to_dict(self) -> dict:
        home = self.home
        functional = sum(1 for d in home.devices.values() if d.functional)
        return {"code": self.code, "name": self.name,
                "principles": {p: True for p in PRINCIPLES}, "agents": list(self.agents),
                "equipment": {"total": len(home.devices), "functional": functional,
                              "faulty": len(home.devices) - functional,
                              "on": sum(1 for d in home.devices.values() if d.on),
                              "real": sum(1 for d in home.devices.values() if d.real)},
                "emergencies": [f"{k} in {home.room_name(r)}" for k, r in self.emergencies],
                "cloud_cases": self.cloud_cases, "distill_cycles": self.distill_cycles,
                "last_distill": self.last_distill}
