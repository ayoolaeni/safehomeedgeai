"""Layer 5 - the Thriftogentic AI layer.

Every action, whether proposed by a twin agent or commanded by a person, is
checked here before it can touch a device. Each twin is only checked against
the principles it has selected (Fire & Safety and Access & Security exclude
Green AI; Water and Climate exclude Resilient AI), which is what makes the
fusion domain-sensitive rather than one fixed bundle.

  Agentic   - the action is inside the twin's bounded action space and budgets
  Edge      - the decision is made on the local server, never waiting on cloud
  Safe      - hard guardrails, confidence gate, human-only actions
  Resilient - the target device is healthy and power/connectivity allow it
  Green     - the action is affordable on the current energy budget
"""

from dataclasses import dataclass, field

from .environment import CO_ALARM, GAS_ALARM, HEAT_ALARM, SMOKE_ALARM
from .model import FAILSAFE, GOVERNANCE, HUMAN_ONLY, INFO, Proposal

GEN_RUNTIME_BUDGET_H = 6.0       # per day, set by the AHDT
BATTERY_FLOOR_PCT = 20.0         # battery reserve floor for discretionary loads
POTABLE_FLOOR_PCT = 40.0         # tank level below which irrigation is refused
PUMP_LOAD_W = 750


@dataclass
class Verdict:
    allowed: bool = True
    needs_human: bool = False
    checks: list = field(default_factory=list)   # [{"principle", "ok", "note"}]

    def add(self, principle: str, ok: bool, note: str, block: bool = False, human: bool = False):
        self.checks.append({"principle": principle, "ok": ok, "note": note})
        if block:
            self.allowed = False
        if human:
            self.needs_human = True

    @property
    def reasons(self) -> str:
        return "; ".join(c["note"] for c in self.checks if not c["ok"])


class ThriftogenticLayer:
    def __init__(self, home):
        self.home = home

    def evaluate(self, p: Proposal, human: bool = False) -> Verdict:
        home, v = self.home, Verdict()
        twin = home.twins.get(p.twin)
        principles = twin.principles if twin else {"agentic", "edge", "safe", "resilient", "green"}
        dev = home.devices.get(p.device) if p.device else None
        env = home.env

        # Agentic: bounded action space set by the AHDT.
        if twin and p.action not in twin.actions and p.category != GOVERNANCE:
            v.add("agentic", False, f"{p.action} is outside {p.twin}'s bounded action space", block=True)
        elif p.action == "START_GENERATOR" and env.gen_runtime_today_h >= GEN_RUNTIME_BUDGET_H and not human:
            v.add("agentic", False, f"generator runtime budget ({GEN_RUNTIME_BUDGET_H:.0f} h/day) used up",
                  human=True)
        else:
            v.add("agentic", True, "inside the bounded action space")

        # Edge: always decided locally.
        if "edge" in principles:
            v.add("edge", True, "decided on the local server, no cloud round trip")

        # Safe: every twin selects Safe AI, so its guardrails always run.
        self._safe(p, dev, human, v)

        # Resilient: device health and power/connectivity context.
        if "resilient" in principles:
            if dev and not dev.functional:
                v.add("resilient", False, f"{dev.name} is reporting a fault", block=not human)
            elif p.action == "START_GENERATOR" and env.gen_fuel_l <= 0.5:
                v.add("resilient", False, "generator has no fuel", block=True)
            else:
                v.add("resilient", True, "target healthy; supply path available")

        # Green: energy budget, only for twins that selected Green AI.
        if "green" in principles and p.category not in (FAILSAFE, INFO) and not human:
            adds = self._added_load(p, dev)
            if adds >= 100 and env.source == "BATTERY" and env.battery_soc < BATTERY_FLOOR_PCT + 20:
                v.add("green", False,
                      f"adds {adds:.0f} W while on battery at {env.battery_soc:.0f}% - needs approval",
                      human=True)
            elif p.action == "START_GENERATOR" and env.battery_soc > 30 and not human:
                v.add("green", False, "battery still above 30%: generator start deferred", human=True)
            else:
                v.add("green", True, "within the current energy budget")

        if p.category == HUMAN_ONLY and not human:
            v.needs_human = True
        return v

    # ------------------------------------------------------------------

    def _safe(self, p: Proposal, dev, human: bool, v: Verdict):
        env, home = self.home.env, self.home
        blocked = None
        if p.action == "SHED_LOAD" and dev and dev.critical:
            blocked = f"{dev.name} is a critical load and is never shed"
        elif p.action == "START_GENERATOR" and env.gen_co >= CO_ALARM:
            blocked = f"generator interlock: CO at {env.gen_co:.0f} ppm in the generator bay"
        elif p.action == "START_GENERATOR" and env.gen_vent_blocked:
            blocked = "generator interlock: generator bay ventilation check failed"
        elif p.action == "IRRIGATION_ON" and home.tank_pct() < POTABLE_FLOOR_PCT:
            blocked = f"potable priority: tank at {home.tank_pct():.0f}% (floor {POTABLE_FLOOR_PCT:.0f}%)"
        elif p.action == "OPEN_MAIN_VALVE" and env.leak and not human:
            blocked = "leak still detected: valve stays closed until a person reopens it"
        elif p.action in ("ALARM_OFF", "SPRINKLER_OFF") and not human:
            blocked = "only an authorised person may silence an alarm or stop suppression"
        elif p.action == "ALARM_OFF" and self.live_hazard():
            blocked = "a hazard is still being detected: the alarm cannot be reset yet"
        elif p.action == "RESTORE_CIRCUIT" and self.live_hazard(p.params.get("room")):
            blocked = "hazard still present in that room: power stays cut"
        if blocked:
            v.add("safe", False, blocked, block=True)
            return
        if p.action in ("UNLOCK", "DISARM") and env.visitor_at_door and not human:
            v.add("safe", False, "letting a stranger in always needs a resident", human=True)
        elif p.confidence != "HIGH" and p.category not in (FAILSAFE, INFO) and not human:
            v.add("safe", False, "low confidence: escalated to a person", human=True)
        elif p.category == HUMAN_ONLY and not human:
            v.add("safe", False, "human-in-the-loop action: a resident must decide", human=True)
        else:
            v.add("safe", True, "no guardrail triggered")

    def live_hazard(self, room: str | None = None) -> bool:
        for r, h in self.home.env.hazard.items():
            if room and r != room:
                continue
            if (h["smoke"] >= SMOKE_ALARM or h["heat"] >= HEAT_ALARM
                    or h["co"] >= CO_ALARM or h["gas"] >= GAS_ALARM):
                return True
        return False

    @staticmethod
    def _added_load(p: Proposal, dev) -> float:
        if p.action in ("AC_ON", "PUMP_ON", "LIGHT_ON", "RESTORE_LOAD", "TREATMENT_ON"):
            return dev.power_w if dev else PUMP_LOAD_W
        return 0.0
