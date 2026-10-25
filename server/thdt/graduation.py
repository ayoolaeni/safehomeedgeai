"""Thriftogentic-to-Thriftonomous maturity ladder, one per subsystem twin.

S1 THRIFTOGENTIC      baseline: every routine action is asked first
S2 SHADOW REHEARSAL   enough proposals answered to judge the twin
S3 ESCALATION TUNING  approval rate at or above the promotion threshold
S4 HAZARD + CANARY    hazard suite passed, canary period running
S5 THRIFTONOMOUS      household signed off through the AHDT: may act alone

Promotion to S5 always needs AHDT governance sign-off (no twin self-graduates).
A falling approval rate, too many overrides or a sensor fault demotes the
twin back to S1. Fire & Safety is permanently non-graduating.
"""

import time
from collections import deque

NAMES = {1: "THRIFTOGENTIC", 2: "SHADOW REHEARSAL", 3: "ESCALATION TUNING",
         4: "HAZARD SUITE + CANARY", 5: "THRIFTONOMOUS"}

PROMOTE_APPROVAL_PCT = 90
DEMOTE_APPROVAL_PCT = 85
DEMOTE_OVERRIDE_PCT = 20
WINDOW = 50


class Graduation:
    def __init__(self, code: str, fast: bool, non_graduating: bool = False, saved: dict | None = None):
        self.code = code
        self.non_graduating = non_graduating
        self.min_proposals = 10 if fast else 100
        self.canary_s = 120 if fast else 48 * 3600
        self.state = 1
        self.proposals = 0
        self.approvals = 0
        self.answered_since_reset = 0     # promotion evidence is rebuilt after a demotion
        self.recent = deque(maxlen=WINDOW)       # True = approved
        self.auto_recent = deque(maxlen=WINDOW)  # True = overridden by a person
        self.hazard_suite = False
        self.canary_start = None
        self.signoff_pending = False
        self.last_change = ("Permanently non-graduating: life-safety decisions always stay with people."
                            if non_graduating else "Starting at THRIFTOGENTIC.")
        if saved:
            self._load(saved)

    # --- inputs -----------------------------------------------------------

    def record_response(self, approved: bool) -> str | None:
        self.proposals += 1
        self.approvals += int(approved)
        self.answered_since_reset += 1
        self.recent.append(approved)
        return self._evaluate()

    def record_autonomous(self, overridden: bool) -> str | None:
        self.auto_recent.append(overridden)
        if len(self.auto_recent) >= 10 and self._pct(self.auto_recent) > DEMOTE_OVERRIDE_PCT:
            return self._demote(f"people reversed {self._pct(self.auto_recent):.0f}% of its own actions")
        return None

    def record_fault(self, what: str) -> str | None:
        if self.state > 1:
            return self._demote(f"sensor fault: {what}")
        return None

    def mark_hazard_suite(self) -> str | None:
        if self.non_graduating:
            return None
        self.hazard_suite = True
        return self._evaluate()

    def tick(self, now: float | None = None) -> bool:
        """True when the twin has just become ready for governance sign-off."""
        now = now or time.time()
        if (self.state == 4 and not self.signoff_pending and self.canary_start
                and now - self.canary_start >= self.canary_s):
            self.signoff_pending = True
            self.last_change = "Canary period complete. Waiting for household sign-off."
            return True
        return False

    def signoff(self, approved: bool) -> str:
        self.signoff_pending = False
        if approved and self.state == 4:
            self.state = 5
            self.last_change = "Signed off by the household: now THRIFTONOMOUS."
        else:
            self.canary_start = time.time()
            self.last_change = "Sign-off declined: canary period restarted."
        return self.last_change

    # --- rules ------------------------------------------------------------

    def _evaluate(self) -> str | None:
        if self.non_graduating:
            return None
        if len(self.recent) >= 10 and self._pct(self.recent) < DEMOTE_APPROVAL_PCT and self.state > 1:
            return self._demote(f"approval fell to {self._pct(self.recent):.0f}% over the last {len(self.recent)}")
        before = self.state
        if self.state == 1 and self.answered_since_reset >= self.min_proposals:
            self.state = 2
        if self.state == 2 and self._pct(self.recent) >= PROMOTE_APPROVAL_PCT:
            self.state = 3
        if self.state == 3 and self.hazard_suite:
            self.state, self.canary_start = 4, time.time()
        if self.state != before:
            self.last_change = f"Promoted to S{self.state} {NAMES[self.state]}."
            return self.last_change
        return None

    def _demote(self, why: str) -> str:
        self.state, self.canary_start, self.signoff_pending = 1, None, False
        self.answered_since_reset = 0
        self.recent.clear()
        self.auto_recent.clear()
        self.last_change = f"Demoted to S1 THRIFTOGENTIC: {why}."
        return self.last_change

    @staticmethod
    def _pct(seq) -> float:
        return 100.0 * sum(seq) / len(seq) if seq else 0.0

    @property
    def approval_rate(self) -> float:
        return 100.0 * self.approvals / self.proposals if self.proposals else 0.0

    @property
    def thriftonomous(self) -> bool:
        return self.state == 5

    # --- persistence ------------------------------------------------------

    def to_dict(self) -> dict:
        canary_left = None
        if self.state == 4 and self.canary_start and not self.signoff_pending:
            canary_left = max(0, int(self.canary_s - (time.time() - self.canary_start)))
        return {"state": f"S{self.state}", "name": NAMES[self.state], "proposals": self.proposals,
                "answered_since_reset": self.answered_since_reset,
                "approvals": self.approvals, "approval_rate": round(self.approval_rate, 1),
                "min_proposals": self.min_proposals, "hazard_suite": self.hazard_suite,
                "canary_left_s": canary_left, "signoff_pending": self.signoff_pending,
                "non_graduating": self.non_graduating, "last_change": self.last_change}

    def save(self) -> dict:
        return {"state": self.state, "proposals": self.proposals, "approvals": self.approvals,
                "answered_since_reset": self.answered_since_reset,
                "recent": list(self.recent), "auto_recent": list(self.auto_recent),
                "hazard_suite": self.hazard_suite, "last_change": self.last_change}

    def _load(self, d: dict):
        self.state = 1 if self.non_graduating else max(1, min(5, int(d.get("state", 1))))
        self.proposals = int(d.get("proposals", 0))
        self.approvals = int(d.get("approvals", 0))
        self.answered_since_reset = int(d.get("answered_since_reset", self.proposals))
        self.recent.extend(bool(x) for x in d.get("recent", []))
        self.auto_recent.extend(bool(x) for x in d.get("auto_recent", []))
        self.hazard_suite = bool(d.get("hazard_suite", False)) and not self.non_graduating
        self.last_change = d.get("last_change", self.last_change)
        if self.state == 4:
            # The canary period restarts after a reboot: it must be observed live.
            self.canary_start = time.time()
