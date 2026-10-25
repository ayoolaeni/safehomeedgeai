"""Agentic Water Digital Twin (AWDT): borehole, public supply, rain and tank.

Agentic, Edge, Safe and Green AI. Resilient AI is excluded because the tank,
borehole and rain harvesting already give passive continuity through storage.
"""

from ..model import FAILSAFE, FLEXIBLE
from .base import Twin

IRRIGATION_START_H, IRRIGATION_MIN = 18.0, 20


class WaterTwin(Twin):
    code = "AWDT"
    name = "Water"
    principles = frozenset({"agentic", "edge", "safe", "green"})
    excluded_why = ("Resilient AI excluded: storage tanks, the borehole and rain harvesting already "
                    "provide continuity without active switching.")
    agents = ("Source Management Agent", "Treatment & Quality Agent", "Distribution Agent",
              "Irrigation Optimization Agent", "Energy-Water Coordination Agent")
    actions = frozenset({"PUMP_ON", "PUMP_OFF", "CLOSE_MAIN_VALVE", "OPEN_MAIN_VALVE", "TREATMENT_ON",
                         "TREATMENT_OFF", "IRRIGATION_ON", "IRRIGATION_OFF"})

    def __init__(self, home, saved_graduation=None):
        super().__init__(home, saved_graduation)
        self.irrigated_day = -1
        self.irrigation_started = None

    def observe(self):
        env, h = self.home.env, self.home
        self.dev("tank_level").value = round(h.tank_pct(), 1)
        self.dev("utility_supply").value = 1.5 if env.utility_on else 0.0
        self.dev("rain_gauge").value = 4.0 if env.raining else 0.0
        self.dev("turbidity").value = round(env.turbidity, 1)
        leak = self.dev("leak_sensor")
        leak.value = leak.on = env.leak
        h.alert_if(h.tank_pct() < 20, "low_tank", "WARN", self.code, "Water tank low",
                   f"Tank at {h.tank_pct():.0f}%")
        h.alert_if(env.leak, "leak", "CRITICAL", self.code, "Water leak · Kitchen",
                   "Leak detector wet. Main valve closes automatically; a person must reopen it.",
                   room="kitchen", resettable=False)
        h.alert_if(env.turbidity > 5, "water_quality", "WARN", self.code, "Water quality",
                   f"Turbidity {env.turbidity:.1f} NTU: water routed through treatment")

    def decide(self):
        env, h, out = self.home.env, self.home, []
        tank = h.tank_pct()
        pump = self.dev("borehole_pump")
        surplus = env.solar_w - env.load_w

        def add(p):
            if p:
                out.append(p)

        if env.leak and self.dev("main_valve").on:
            add(self.propose("CLOSE_MAIN_VALVE", "Leak detected in the kitchen: closing the house main "
                             "valve.", "main_valve", category=FAILSAFE, agent="Distribution Agent",
                             cooldown_s=3))
        if env.turbidity > 5 and not self.dev("treatment_unit").on:
            add(self.propose("TREATMENT_ON", f"Turbidity {env.turbidity:.1f} NTU: routing potable water "
                             "through filtration and chlorination.", "treatment_unit", category=FAILSAFE,
                             agent="Treatment & Quality Agent", cooldown_s=3))
        if env.turbidity <= 2 and self.dev("treatment_unit").on:
            add(self.propose("TREATMENT_OFF", "Water quality back to normal: treatment can stop.",
                             "treatment_unit", agent="Treatment & Quality Agent"))
        if pump.on and tank >= 95:
            add(self.propose("PUMP_OFF", f"Tank full ({tank:.0f}%): stopping the pump.", "borehole_pump",
                             category=FAILSAFE, agent="Source Management Agent", cooldown_s=3))
        elif not pump.on and tank < 25:
            add(self.propose("PUMP_ON", f"Tank at {tank:.0f}%: refill from the borehole (potable water "
                             "comes first).", "borehole_pump", category=FLEXIBLE,
                             agent="Source Management Agent"))
        elif not pump.on and tank < 70 and surplus >= 900:
            add(self.propose("PUMP_ON", f"Solar surplus of {surplus:.0f} W: store it as water by "
                             f"pumping now (tank {tank:.0f}%).", "borehole_pump", category=FLEXIBLE,
                             agent="Energy-Water Coordination Agent"))
        elif pump.on and env.source == "BATTERY" and tank >= 40 and surplus < 0:
            add(self.propose("PUMP_OFF", f"On battery and tank at {tank:.0f}%: pause pumping until "
                             "solar or grid is available.", "borehole_pump",
                             agent="Energy-Water Coordination Agent"))

        irr = self.dev("irrigation")
        day = int(env.sim_s // 86400)
        if (not irr.on and self.irrigated_day != day and IRRIGATION_START_H <= env.hour < 18.5
                and not env.raining and tank >= 50):
            add(self.propose("IRRIGATION_ON", f"Evening garden watering (tank {tank:.0f}%, no rain).",
                             "irrigation", agent="Irrigation Optimization Agent", cooldown_s=60))
        if irr.on:
            if tank < 40:
                add(self.propose("IRRIGATION_OFF", f"Tank down to {tank:.0f}%: irrigation stopped to "
                                 "protect drinking water.", "irrigation", category=FAILSAFE,
                                 agent="Irrigation Optimization Agent", cooldown_s=3))
            elif self.irrigation_started and env.sim_s - self.irrigation_started >= IRRIGATION_MIN * 60:
                add(self.propose("IRRIGATION_OFF", f"Garden watered for {IRRIGATION_MIN} minutes.",
                                 "irrigation", category=FAILSAFE, agent="Irrigation Optimization Agent",
                                 cooldown_s=3))
        return out

    def actuate(self, p):
        d, env = self.home.devices.get(p.device or ""), self.home.env
        on = p.action.endswith("_ON") or p.action == "OPEN_MAIN_VALVE"
        if d:
            d.on = on
        if p.action == "IRRIGATION_ON":
            self.irrigated_day = int(env.sim_s // 86400)
            self.irrigation_started = env.sim_s
        if p.action == "OPEN_MAIN_VALVE":
            self.home.clear_alert("leak")
        names = {"PUMP": "borehole pump", "CLOSE_MAIN_VALVE": "main valve", "OPEN_MAIN_VALVE": "main valve",
                 "TREATMENT": "treatment unit", "IRRIGATION": "irrigation"}
        label = next((v for k, v in names.items() if p.action.startswith(k)), "device")
        state = ("open" if on else "closed") if "VALVE" in p.action else ("on" if on else "off")
        return f"{label} {state}"

    def summary(self):
        h = self.home
        pump = "pumping" if self.dev("borehole_pump").on else "pump idle"
        valve = "" if self.dev("main_valve").on else " · MAIN VALVE CLOSED"
        return f"Tank {h.tank_pct():.0f}% · {pump} · quality {h.env.turbidity:.1f} NTU{valve}"

    def status(self):
        env = self.home.env
        if env.leak:
            return "ALERT"
        return "WARN" if (self.home.tank_pct() < 20 or env.turbidity > 5) else "OK"
