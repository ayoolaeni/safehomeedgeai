"""Common behaviour of every Agentic Subsystem Digital Twin (ASsDT)."""

import time

from ..graduation import Graduation
from ..model import MANUAL, PRINCIPLES, ROUTINE, Proposal


class Twin:
    code = ""
    name = ""
    principles: frozenset = frozenset()
    excluded_why = ""           # why a principle is left out of this twin's fusion
    agents: tuple = ()          # Layer 6 service agents
    actions: frozenset = frozenset()   # bounded action space, set by the AHDT
    non_graduating = False

    def __init__(self, home, saved_graduation: dict | None = None):
        self.home = home
        self.mode = MANUAL      # fail-safe boot default, as on the lamp firmware
        self.graduation = Graduation(self.code, home.cfg.get("fast_graduation", True),
                                     self.non_graduating, saved_graduation)
        self._cooldown: dict[tuple, float] = {}
        self.distill_requests = 0

    # Overridden by each twin -------------------------------------------------

    def observe(self):
        """Copy the physical readings into this twin's sensor devices."""

    def decide(self) -> list[Proposal]:
        """Let the twin's agents look at their sensors and propose actions."""
        return []

    def actuate(self, p: Proposal) -> str:
        """Carry out an approved action and describe what happened."""
        return "no change"

    def summary(self) -> str:
        return ""

    def status(self) -> str:
        return "OK"

    # Helpers -------------------------------------------------------------------

    def propose(self, action: str, reason: str, device: str | None = None, params: dict | None = None,
                confidence: str = "HIGH", category: str = ROUTINE, agent: str = "",
                cooldown_s: float = 20.0) -> Proposal | None:
        p = Proposal(self.code, action, reason, device, params or {}, confidence, category, agent)
        key = p.key()
        now = time.time()
        if self._cooldown.get(key, 0) > now:
            return None
        if any(q.key() == key for q in self.home.pending):
            return None
        self._cooldown[key] = now + cooldown_s
        return p

    def dev(self, device_id: str):
        return self.home.devices[device_id]

    def to_dict(self) -> dict:
        return {
            "code": self.code, "name": self.name,
            "principles": {pr: (pr in self.principles) for pr in PRINCIPLES},
            "excluded_why": self.excluded_why,
            "agents": list(self.agents), "actions": sorted(self.actions),
            "mode": self.mode, "graduation": self.graduation.to_dict(),
            "status": self.status(), "summary": self.summary(),
            "devices": [d.id for d in self.home.devices.values() if d.twin == self.code],
            "distill_requests": self.distill_requests,
        }
