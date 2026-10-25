"""Shared data types: devices, rooms, proposals and the Thriftogentic AI principles."""

import itertools
import time
from dataclasses import dataclass, field
from typing import Any, Optional

PRINCIPLES = ("agentic", "edge", "safe", "resilient", "green")

# Operating modes, the same three the lamp firmware uses.
MANUAL, ASSISTED, AUTONOMOUS = "MANUAL", "ASSISTED", "AUTONOMOUS"
MODES = (MANUAL, ASSISTED, AUTONOMOUS)

# Proposal categories decide how the orchestrator treats an action:
#   failsafe   - protects life, property or critical loads; runs in every mode
#   info       - a notification only; runs in every mode
#   routine    - needs approval unless the twin has graduated to THRIFTONOMOUS
#   flexible   - routine, plus whole-home Green arbitration of power
#   human_only - always needs a person, even when the twin has graduated
#   governance - a decision only the household can make (e.g. graduation sign-off)
#   manual     - a command a person sent from the app
FAILSAFE, INFO, ROUTINE, FLEXIBLE, HUMAN_ONLY, GOVERNANCE, MANUAL_CMD = (
    "failsafe", "info", "routine", "flexible", "human_only", "governance", "manual")

_ids = itertools.count(1)


@dataclass
class Device:
    id: str
    name: str
    room: str
    twin: str
    kind: str                 # light, ac, lock, sensor, pump, valve, siren, ...
    on: bool = False
    value: Any = None         # a reading, setpoint or status text
    unit: str = ""
    functional: bool = True
    real: bool = False        # True for the physical ESP32 lamp
    critical: bool = False    # life-safety / medical load: never shed automatically
    power_w: float = 0.0
    controllable: bool = False
    shed: bool = False        # switched off by load shedding

    def to_dict(self) -> dict:
        return {
            "id": self.id, "name": self.name, "room": self.room, "twin": self.twin,
            "kind": self.kind, "on": self.on, "value": _round(self.value),
            "unit": self.unit, "functional": self.functional, "real": self.real,
            "critical": self.critical, "power_w": self.power_w,
            "controllable": self.controllable, "shed": self.shed,
        }


@dataclass
class Room:
    id: str
    name: str
    floor: int
    x: float
    y: float
    w: float
    h: float
    outdoor: bool = False
    neighbours: tuple = ()

    def to_dict(self) -> dict:
        return {"id": self.id, "name": self.name, "floor": self.floor,
                "x": self.x, "y": self.y, "w": self.w, "h": self.h,
                "outdoor": self.outdoor}


@dataclass
class Proposal:
    twin: str
    action: str
    reason: str
    device: Optional[str] = None
    params: dict = field(default_factory=dict)
    confidence: str = "HIGH"   # HIGH or LOW
    category: str = ROUTINE
    source: str = ""           # which agent raised it
    id: str = field(default_factory=lambda: f"P{next(_ids)}")
    created: float = field(default_factory=time.time)
    checks: list = field(default_factory=list)   # Thriftogentic AI verdict, for the app

    def key(self) -> tuple:
        return (self.twin, self.action, self.device,
                tuple(sorted((k, str(v)) for k, v in self.params.items())))

    def to_dict(self) -> dict:
        return {"id": self.id, "twin": self.twin, "action": self.action,
                "device": self.device, "params": self.params,
                "confidence": self.confidence, "category": self.category,
                "reason": self.reason, "source": self.source,
                "created": self.created, "checks": self.checks}


def _round(v):
    return round(v, 1) if isinstance(v, float) else v
