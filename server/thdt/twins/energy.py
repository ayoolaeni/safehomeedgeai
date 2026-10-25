"""Agentic Energy Digital Twin (AEDT): grid, solar/battery and generator.

The only subsystem twin with the full five-principle fusion: Green AI sets
its objective (renewables first, least fuel) and Resilient AI is its core
mechanism (automatic grid -> solar/battery -> generator switching that every
other twin depends on).
"""

from ..environment import ROOMS
from ..model import FAILSAFE
from .base import Twin

SHEDDABLE = ("ac_sitting_room", "ac_bedroom", "sockets_sitting")


class EnergyTwin(Twin):
    code = "AEDT"
    name = "Energy"
    principles = frozenset({"agentic", "edge", "safe", "resilient", "green"})
    agents = ("Source Selection Agent", "Load Management Agent", "Generator Control Agent",
              "Battery Management Agent", "Demand Coordination Agent", "Resilience Monitoring Agent")
    actions = frozenset({"SWITCH_SOURCE", "START_GENERATOR", "STOP_GENERATOR", "SHED_LOAD",
                         "RESTORE_LOAD", "CUT_CIRCUIT", "RESTORE_CIRCUIT"})

    def observe(self):
        env = self.home.env
        self.dev("grid_supply").value = 230 if env.grid_up else 0
        self.dev("grid_supply").on = env.grid_up
        self.dev("solar_pv").value = round(env.solar_w)
        self.dev("battery").value = round(env.battery_soc, 1)
        self.dev("ats").value = env.source
        g = self.dev("generator")
        g.on, g.value = env.gen_running, round(env.gen_fuel_l, 1)
        self.dev("load_meter").value = round(env.load_w)
        self.dev("gen_ventilation").value = "BLOCKED" if env.gen_vent_blocked else "OK"
        h = self.home
        h.alert_if(env.gen_running and env.gen_fuel_l < 4, "low_fuel", "WARN", self.code,
                   "Generator fuel low", f"{env.gen_fuel_l:.1f} L left")
        # The transfer switch moves within one tick; only a lasting loss is an alert.
        self._lost_ticks = 0 if env.power_ok else getattr(self, "_lost_ticks", 0) + 1
        h.alert_if(self._lost_ticks >= 3, "power_lost", "CRITICAL", self.code, "Power interrupted",
                   "No supply is currently feeding the house")

    def decide(self):
        env, out = self.home.env, []
        soc = env.battery_soc
        occupied = bool(self.home.occupied_rooms())

        def add(p):
            if p:
                out.append(p)

        # Resilience Monitoring + Source Selection: automatic failover.
        if not env.grid_up and env.source == "GRID":
            add(self.propose("SWITCH_SOURCE", "Grid outage detected: transferring the house to "
                             f"solar/battery ({soc:.0f}% charged).", "ats", {"source": "BATTERY"},
                             category=FAILSAFE, agent="Resilience Monitoring Agent", cooldown_s=3))
        if env.source == "GENERATOR" and not env.gen_running:
            add(self.propose("SWITCH_SOURCE", "Generator stopped: falling back to battery.", "ats",
                             {"source": "BATTERY"}, category=FAILSAFE, agent="Resilience Monitoring Agent",
                             cooldown_s=3))
        if env.grid_up and env.source != "GRID" and not (6.5 < env.hour < 16 and soc > 60):
            add(self.propose("SWITCH_SOURCE", f"Grid is back. Battery at {soc:.0f}%: returning to grid "
                             "so the battery can recover.", "ats", {"source": "GRID"},
                             agent="Source Selection Agent", cooldown_s=30))
        if env.grid_up and env.gen_running:
            add(self.propose("STOP_GENERATOR", "Grid restored: stopping the generator to save fuel.",
                             "generator", agent="Generator Control Agent"))

        # Generator Control: autostart is suppressed until the battery is low.
        if env.source == "BATTERY" and not env.gen_running and not env.grid_up:
            if soc < 10:
                add(self.propose("START_GENERATOR", f"Battery critical ({soc:.0f}%): starting the "
                                 "generator to protect critical loads.", "generator",
                                 category=FAILSAFE, agent="Generator Control Agent"))
            elif soc < 20 and occupied:
                add(self.propose("START_GENERATOR", f"Battery below 20% ({soc:.0f}%) with people at "
                                 "home: generator start recommended.", "generator",
                                 agent="Generator Control Agent"))
        if env.gen_running and env.gen_co >= 50:
            add(self.propose("STOP_GENERATOR", f"Carbon monoxide at {env.gen_co:.0f} ppm in the "
                             "generator bay: emergency stop.", "generator", category=FAILSAFE,
                             agent="Generator Control Agent", cooldown_s=3))
        if env.gen_running and soc > 80 and not env.grid_up:
            add(self.propose("STOP_GENERATOR", f"Battery recharged to {soc:.0f}%: stopping the "
                             "generator and running on solar/battery.", "generator",
                             agent="Battery Management Agent"))

        # Load Management: shed non-critical loads before the battery runs out.
        if env.source == "BATTERY":
            for dev_id in SHEDDABLE:
                d = self.dev(dev_id)
                if d.on and soc < 15:
                    add(self.propose("SHED_LOAD", f"Battery at {soc:.0f}%: shedding {d.name} to keep "
                                     "critical loads running.", dev_id, category=FAILSAFE,
                                     agent="Load Management Agent"))
                elif d.on and soc < 30:
                    add(self.propose("SHED_LOAD", f"Battery at {soc:.0f}%: switch off {d.name}?",
                                     dev_id, agent="Load Management Agent", cooldown_s=40))
        for dev_id in SHEDDABLE:
            d = self.dev(dev_id)
            if d.shed and (env.source != "BATTERY" or soc > 50):
                add(self.propose("RESTORE_LOAD", f"Supply recovered: {d.name} may be used again.",
                                 dev_id, agent="Load Management Agent"))
        return out

    def actuate(self, p):
        env, d = self.home.env, self.home.devices.get(p.device or "")
        if p.action == "SWITCH_SOURCE":
            env.source = p.params["source"]
            if env.source == "GENERATOR" and not env.gen_running:
                env.gen_running = True
            return f"supply now {env.source}"
        if p.action == "START_GENERATOR":
            env.gen_running, env.source = True, "GENERATOR"
            return "generator running, house on generator"
        if p.action == "STOP_GENERATOR":
            env.gen_running = False
            if env.source == "GENERATOR":
                env.source = "GRID" if env.grid_up else "BATTERY"
            return f"generator stopped, house on {env.source}"
        if p.action == "SHED_LOAD" and d:
            d.on, d.shed = False, True
            return f"{d.name} shed"
        if p.action == "RESTORE_LOAD" and d:
            d.shed = False
            if d.kind == "load":
                d.on = True
            return f"{d.name} available again"
        if p.action in ("CUT_CIRCUIT", "RESTORE_CIRCUIT"):
            room = p.params["room"]
            env.circuits[room] = p.action == "RESTORE_CIRCUIT"
            name = next(r.name for r in ROOMS if r.id == room)
            return f"{name} circuit {'restored' if env.circuits[room] else 'cut'}"
        return "no change"

    def summary(self):
        env = self.home.env
        gen = f", generator {env.gen_fuel_l:.0f} L" if env.gen_running else ""
        return (f"{env.source.title()} supply · battery {env.battery_soc:.0f}% · solar "
                f"{env.solar_w:.0f} W · load {env.load_w:.0f} W{gen}")

    def status(self):
        env = self.home.env
        if not env.power_ok:
            return "ALERT"
        return "WARN" if (not env.grid_up or env.battery_soc < 30) else "OK"
