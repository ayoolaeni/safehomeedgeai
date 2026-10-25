"""Agentic Resident Digital Twin (ARDT): one private partition per resident.

A minimal-fit liaison: Agentic, Edge and Safe AI only. It greets residents,
delivers the messages the AHDT has put in context, and keeps each resident's
preferences and presence private to their own partition.
"""

from ..model import INFO
from .base import Twin


class ResidentTwin(Twin):
    code = "ARDT"
    name = "Resident"
    principles = frozenset({"agentic", "edge", "safe"})
    excluded_why = ("Minimal fit: Green and Resilient AI live in the Energy and Fire twins; the liaison "
                    "only needs to act safely and locally for each resident.")
    agents = ("Resident Liaison Agent", "Presence Agent", "Preference Agent", "Notification Agent")
    actions = frozenset({"NOTIFY"})

    def __init__(self, home, saved_graduation=None):
        super().__init__(home, saved_graduation)
        self.seen = {r["id"]: r["location"] for r in home.residents}

    def decide(self):
        out = []
        for r in self.home.residents:
            before, now = self.seen.get(r["id"]), r["location"]
            self.seen[r["id"]] = now
            if before is None and now:
                p = self.propose("NOTIFY", self.home.ahdt.welcome_message(r), params={"resident": r["id"]},
                                 category=INFO, agent="Resident Liaison Agent", cooldown_s=5)
                if p:
                    out.append(p)
            elif before and not now:
                p = self.propose("NOTIFY", f"Goodbye, {r['name']}. I'll keep the house secure.",
                                 params={"resident": r["id"]}, category=INFO, agent="Resident Liaison Agent",
                                 cooldown_s=5)
                if p:
                    out.append(p)
        return out

    def actuate(self, p):
        self.home.message(p.reason, p.params.get("resident"))
        return "delivered to the resident"

    def summary(self):
        parts = []
        for r in self.home.residents:
            where = self.home.room_name(r["location"]) if r["location"] else "away"
            parts.append(f"{r['name']}: {where}")
        return " · ".join(parts)
