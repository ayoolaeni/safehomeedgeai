"""Agentic Climate Digital Twin (ACDT): cooling, humidity and lighting comfort.

Agentic, Edge, Safe and Green AI. Resilient AI is excluded because a comfort
excursion is a low-stakes event. The sitting-room lamp is the real ESP32
node; it runs its own on-device agent, so this twin only commands it when a
person asks or during an emergency.
"""

from ..environment import CLIMATE_ROOMS, ROOMS_WITH_AC, SITTING
from ..model import FLEXIBLE
from .base import Twin

COMFORT_SET = 23.0
ECO_SET = 24.5          # 'Eco-Cooling' inverter profile while on battery
AC_START_T = 25.5
EMPTY_OFF_MIN = 20
LIGHT_EMPTY_OFF_MIN = 10


class ClimateTwin(Twin):
    code = "ACDT"
    name = "Climate & Comfort"
    principles = frozenset({"agentic", "edge", "safe", "green"})
    excluded_why = "Resilient AI excluded: a temperature or lighting excursion is a low-stakes event."
    agents = ("Comfort Control Agent", "Lighting Comfort Agent", "Air Quality Agent",
              "Energy-Aware Scheduling Agent")
    actions = frozenset({"AC_ON", "AC_OFF", "LIGHT_ON", "LIGHT_OFF"})

    def __init__(self, home, saved_graduation=None):
        super().__init__(home, saved_graduation)
        self.empty_since: dict[str, float] = {}

    def observe(self):
        env = self.home.env
        for r in CLIMATE_ROOMS:
            self.dev(f"temp_{r}").value = round(env.temps[r], 1)
            self.dev(f"humidity_{r}").value = round(env.humidity[r])
        occupied = self.home.occupied_rooms()
        for room in {d.room for d in self.home.devices.values()}:
            if room in occupied:
                self.empty_since.pop(room, None)
            else:
                self.empty_since.setdefault(room, env.sim_s)

    def _empty_min(self, room) -> float:
        since = self.empty_since.get(room)
        return 0.0 if since is None else (self.home.env.sim_s - since) / 60.0

    def decide(self):
        env, home, out = self.home.env, self.home, []
        occupied = home.occupied_rooms()
        if home.ahdt.emergencies:
            return out    # an AHDT emergency directive outranks comfort and savings

        def add(p):
            if p:
                out.append(p)

        for r in ROOMS_WITH_AC:
            ac, t = self.dev(f"ac_{r}"), env.temps[r]
            name = home.room_name(r)
            if r in occupied and not ac.on and not ac.shed and t >= AC_START_T:
                eco = env.source == "BATTERY"
                setp = ECO_SET if eco else COMFORT_SET
                why = (f"{name} occupied at {t:.1f} °C: cool to {setp:.1f} °C"
                       + (" (Eco-Cooling profile on solar/battery)." if eco else "."))
                add(self.propose("AC_ON", why, ac.id, {"setpoint": setp},
                                 confidence="HIGH" if t >= 26.5 else "LOW", category=FLEXIBLE,
                                 agent="Comfort Control Agent", cooldown_s=40))
            elif ac.on and self._empty_min(r) >= EMPTY_OFF_MIN:
                add(self.propose("AC_OFF", f"{name} empty for {self._empty_min(r):.0f} min: switching the "
                                 "AC off to save energy.", ac.id, agent="Energy-Aware Scheduling Agent",
                                 cooldown_s=40))

        for d in home.devices.values():
            if d.kind != "light" or d.twin != self.code:
                continue
            if d.room == SITTING and home.esp_linked():
                continue          # the ESP32's own agent decides for the sitting room
            if d.room in occupied and env.is_dark and not d.on:
                add(self.propose("LIGHT_ON", f"{home.room_name(d.room)} occupied and dark.", d.id,
                                 agent="Lighting Comfort Agent", cooldown_s=40))
            elif d.on and self._empty_min(d.room) >= LIGHT_EMPTY_OFF_MIN and d.room != "compound":
                add(self.propose("LIGHT_OFF", f"{home.room_name(d.room)} empty for "
                                 f"{self._empty_min(d.room):.0f} min.", d.id, agent="Lighting Comfort Agent",
                                 cooldown_s=40))
        return out

    def actuate(self, p):
        d = self.home.devices[p.device]
        on = p.action.endswith("_ON")
        if d.kind == "light" and d.real and self.home.esp_linked():
            self.home.esp_command(on)
            return f"command sent to the ESP32 lamp ({'ON' if on else 'OFF'})"
        d.on = on
        if p.action == "AC_ON":
            d.value = float(p.params.get("setpoint", COMFORT_SET))
            return f"{d.name} on, set to {d.value:.1f} °C"
        return f"{d.name} {'on' if on else 'off'}"

    def summary(self):
        env = self.home.env
        temps = " · ".join(f"{self.home.room_name(r).split()[0]} {env.temps[r]:.1f}°C" for r in CLIMATE_ROOMS)
        acs = sum(1 for r in ROOMS_WITH_AC if self.dev(f"ac_{r}").on)
        lights = sum(1 for d in self.home.devices.values() if d.kind == "light" and d.on)
        return f"{temps} · {acs} AC on · {lights} lights on"
