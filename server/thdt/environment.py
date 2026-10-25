"""Layer 1 - the physical home.

Builds the house (rooms, sensors, actuators) and simulates the physics the
real home would supply: daylight and solar output, the battery, generator
fuel and exhaust, the water tank, room temperatures, and hazards injected by
demo scenarios. The one real device is the ESP32 lamp in the sitting room;
everything else is labelled SIMULATED in the app.
"""

import math
import random

from .model import Device, Room

SITTING, KITCHEN, BEDROOM, BATHROOM, ENTRANCE, GENBAY, COMPOUND = (
    "sitting_room", "kitchen", "bedroom", "bathroom", "entrance", "generator_bay", "compound")

ROOMS = [
    Room(SITTING, "Sitting room", 0, 0, 0, 6, 5, neighbours=(ENTRANCE, KITCHEN, BEDROOM)),
    Room(KITCHEN, "Kitchen", 0, 6, 0, 4, 3, neighbours=(SITTING, BATHROOM)),
    Room(BATHROOM, "Bathroom", 0, 10, 0, 2, 3, neighbours=(KITCHEN, BEDROOM)),
    Room(BEDROOM, "Bedroom", 0, 6, 3, 6, 4, neighbours=(SITTING, BATHROOM)),
    Room(ENTRANCE, "Entrance", 0, 0, 5, 6, 2, neighbours=(SITTING, COMPOUND)),
    Room(GENBAY, "Generator bay", 0, 12, 0, 3, 3, outdoor=True, neighbours=(COMPOUND,)),
    Room(COMPOUND, "Compound & garden", 0, 0, 7, 15, 3, outdoor=True, neighbours=(ENTRANCE, GENBAY)),
]

EXIT_ROOM = COMPOUND          # evacuation target
ROOMS_WITH_AC = (SITTING, BEDROOM)
CLIMATE_ROOMS = (SITTING, KITCHEN, BEDROOM)
FIRE_ROOMS = (SITTING, KITCHEN, BEDROOM, GENBAY)

# Hazard thresholds used by the Fire & Safety twin.
SMOKE_ALARM = 2.0    # % obscuration per metre
HEAT_ALARM = 57.0    # deg C (fixed-temperature heat detector)
CO_ALARM = 50.0      # ppm
GAS_ALARM = 10.0     # % of lower explosive limit


def build_devices() -> dict[str, Device]:
    d: list[Device] = []
    add = d.append
    # --- Energy (AEDT) ---------------------------------------------------
    add(Device("grid_supply", "Grid supply (PHCN)", COMPOUND, "AEDT", "sensor", unit="V"))
    add(Device("solar_pv", "Solar PV array", COMPOUND, "AEDT", "sensor", unit="W"))
    add(Device("battery", "Battery bank (BESS)", COMPOUND, "AEDT", "sensor", unit="%"))
    add(Device("ats", "Automatic transfer switch", COMPOUND, "AEDT", "ats", value="GRID", controllable=True))
    add(Device("generator", "Petrol/diesel generator", GENBAY, "AEDT", "generator", unit="L fuel", controllable=True))
    add(Device("gen_ventilation", "Generator bay ventilation", GENBAY, "AEDT", "sensor", value="OK"))
    add(Device("load_meter", "Main panel energy meter", ENTRANCE, "AEDT", "sensor", unit="W"))
    add(Device("fridge", "Kitchen fridge (critical)", KITCHEN, "AEDT", "load", on=True, critical=True, power_w=150))
    add(Device("medicine_fridge", "Medicine fridge (critical)", BEDROOM, "AEDT", "load", on=True, critical=True, power_w=80))
    add(Device("sockets_sitting", "TV & sockets", SITTING, "AEDT", "load", on=True, power_w=200, controllable=True))
    # --- Fire & Safety (AF&SDT) -------------------------------------------
    for r in FIRE_ROOMS:
        name = dict((x.id, x.name) for x in ROOMS)[r]
        if r != GENBAY:
            add(Device(f"smoke_{r}", f"Smoke detector · {name}", r, "AF&SDT", "sensor", value=0.0, unit="%/m"))
        add(Device(f"heat_{r}", f"Heat detector · {name}", r, "AF&SDT", "sensor", value=30.0, unit="°C"))
        add(Device(f"co_{r}", f"CO detector · {name}", r, "AF&SDT", "sensor", value=0.0, unit="ppm"))
    add(Device("gas_kitchen", "Gas/LPG detector · Kitchen", KITCHEN, "AF&SDT", "sensor", value=0.0, unit="%LEL"))
    add(Device("siren", "Alarm siren & strobe", ENTRANCE, "AF&SDT", "siren", controllable=True, power_w=20))
    add(Device("sprinkler_kitchen", "Sprinkler valve · Kitchen", KITCHEN, "AF&SDT", "sprinkler", controllable=True))
    add(Device("vent_fan_kitchen", "Smoke extraction fan · Kitchen", KITCHEN, "AF&SDT", "fan", controllable=True, power_w=60))
    # --- Water (AWDT) ------------------------------------------------------
    add(Device("tank_level", "Overhead water tank", COMPOUND, "AWDT", "sensor", unit="%"))
    add(Device("borehole_pump", "Borehole pump", COMPOUND, "AWDT", "pump", controllable=True, power_w=750))
    add(Device("utility_supply", "Public water supply", COMPOUND, "AWDT", "sensor", unit="bar"))
    add(Device("rain_gauge", "Rain gauge", COMPOUND, "AWDT", "sensor", value=0.0, unit="mm/h"))
    add(Device("turbidity", "Water quality (turbidity)", COMPOUND, "AWDT", "sensor", value=0.8, unit="NTU"))
    add(Device("leak_sensor", "Leak detector · Kitchen", KITCHEN, "AWDT", "sensor", value=False))
    add(Device("main_valve", "House main water valve", ENTRANCE, "AWDT", "valve", on=True, controllable=True))
    add(Device("treatment_unit", "Filtration & chlorination", COMPOUND, "AWDT", "treatment", controllable=True, power_w=100))
    add(Device("irrigation", "Garden irrigation valve", COMPOUND, "AWDT", "irrigation", controllable=True))
    # --- Climate & comfort (ACDT) -----------------------------------------
    for r in CLIMATE_ROOMS:
        name = dict((x.id, x.name) for x in ROOMS)[r]
        add(Device(f"temp_{r}", f"Temperature · {name}", r, "ACDT", "sensor", unit="°C"))
        add(Device(f"humidity_{r}", f"Humidity · {name}", r, "ACDT", "sensor", unit="%RH"))
    for r in ROOMS_WITH_AC:
        name = dict((x.id, x.name) for x in ROOMS)[r]
        add(Device(f"ac_{r}", f"Air conditioner · {name}", r, "ACDT", "ac", value=23.0, unit="°C set",
                   controllable=True, power_w=1200))
    add(Device("light_sitting_room", "Sitting room lamp (ESP32)", SITTING, "ACDT", "light", real=True,
               controllable=True, power_w=10))
    for r in (KITCHEN, BEDROOM, BATHROOM, ENTRANCE, COMPOUND):
        name = dict((x.id, x.name) for x in ROOMS)[r]
        add(Device(f"light_{r}", f"Light · {name}", r, "ACDT", "light", controllable=True, power_w=12))
    # --- Access & Security (AA&SDT) ---------------------------------------
    add(Device("lock_front", "Front door lock", ENTRANCE, "AA&SDT", "lock", on=True, controllable=True))
    add(Device("lock_back", "Back door lock", KITCHEN, "AA&SDT", "lock", on=True, controllable=True))
    add(Device("camera_front", "Front door camera (on-device recognition)", ENTRANCE, "AA&SDT", "camera", on=True))
    add(Device("alarm_panel", "Intrusion alarm", ENTRANCE, "AA&SDT", "alarm", controllable=True))
    # --- Presence (AHDT spatial registry) -----------------------------------
    for r in ROOMS:
        add(Device(f"presence_{r.id}", f"Presence · {r.name}", r.id, "AHDT", "presence", value=False,
                   real=(r.id == SITTING)))
    return {x.id: x for x in d}


class Environment:
    """Physical truth of the simulated home, advanced every tick."""

    def __init__(self, start_time: str = "18:00", speed: float = 60, seed: int | None = None):
        hh, mm = (int(x) for x in start_time.split(":"))
        self.sim_s = hh * 3600 + mm * 60
        self.speed = speed
        self.rng = random.Random(seed)
        # power
        self.grid_up = True
        self.source = "GRID"
        self.battery_kwh_cap = 10.0
        self.battery_kwh = 7.0
        self.gen_running = False
        self.gen_fuel_l = 20.0
        self.gen_runtime_today_h = 0.0
        self.gen_co = 0.0
        self.gen_vent_blocked = False
        self.power_ok = True
        self.load_w = 0.0
        self.solar_w = 0.0
        self.circuits = {r.id: True for r in ROOMS}
        # connectivity (Layer 2): home LAN, broadband/satellite, 4G/5G backup
        self.broadband_up = True
        self.cellular_up = True
        # weather
        self.cloud = 1.0
        self.raining = False
        # water
        self.tank_cap_l = 2000.0
        self.tank_l = 1300.0
        self.utility_on = True
        self.leak = False
        self.turbidity = 0.8
        # climate
        self.temps = {r: 29.0 for r in CLIMATE_ROOMS}
        self.humidity = {r: 68.0 for r in CLIMATE_ROOMS}
        # hazards: room -> dict(smoke, heat, co, gas) target levels
        self.fire_rooms: set[str] = set()
        self.gas_leak = False
        self.hazard = {r: {"smoke": 0.0, "heat": 30.0, "co": 0.0, "gas": 0.0} for r in FIRE_ROOMS}
        # people and security
        self.at_door: str | None = None       # resident id waiting at the front door
        self.visitor_at_door = False
        self.intruder = False
        self.armed = False
        self.faults: set[str] = set()

    # --- clock ------------------------------------------------------------

    @property
    def hour(self) -> float:
        return (self.sim_s / 3600.0) % 24

    @property
    def clock(self) -> str:
        h = int(self.hour)
        return f"{h:02d}:{int((self.hour - h) * 60):02d}"

    @property
    def is_dark(self) -> bool:
        return self.hour < 6.5 or self.hour >= 18.75

    @property
    def outdoor_temp(self) -> float:
        # Lagos: about 25 deg C before dawn, 32 deg C mid-afternoon.
        return 28.5 + 3.5 * math.sin(math.pi * (self.hour - 9) / 12)

    @property
    def battery_soc(self) -> float:
        return 100.0 * self.battery_kwh / self.battery_kwh_cap

    def set_time(self, hhmm: str):
        hh, mm = (int(x) for x in hhmm.split(":"))
        self.sim_s = (self.sim_s // 86400) * 86400 + hh * 3600 + mm * 60

    def advance(self, real_dt: float) -> float:
        dt = real_dt * self.speed
        day_before = int(self.sim_s // 86400)
        self.sim_s += dt
        if int(self.sim_s // 86400) != day_before:
            self.gen_runtime_today_h = 0.0
        return dt

    # --- physics ----------------------------------------------------------

    def step(self, dt: float, devices: dict[str, Device], occupied_rooms: set[str]):
        hrs = dt / 3600.0
        # Solar
        irr = max(0.0, math.sin(math.pi * (self.hour - 6.5) / 12.0)) if 6.5 < self.hour < 18.5 else 0.0
        self.solar_w = 3000.0 * irr * self.cloud * (0.3 if self.raining else 1.0)

        # Load: every powered device that is on, plus 100 W of always-on electronics.
        load = 100.0
        for d in devices.values():
            if d.on and d.power_w and self.circuits.get(d.room, True) and d.kind != "generator":
                load += d.power_w
        self.load_w = load

        # Source
        if self.source == "GRID" and self.grid_up:
            self.power_ok = True
            self._charge_battery(self.solar_w * hrs / 1000.0)
        elif self.source == "GENERATOR" and self.gen_running and self.gen_fuel_l > 0:
            self.power_ok = True
            self._charge_battery(self.solar_w * hrs / 1000.0)
        else:
            # Battery (or a source that is no longer available, which the
            # Energy twin's resilience agent switches away from next tick).
            net_kwh = (self.solar_w - load) * hrs / 1000.0
            if self.source != "BATTERY":
                net_kwh = self.solar_w * hrs / 1000.0
                self.power_ok = False
            else:
                self.power_ok = self.battery_kwh > 0.05 or self.solar_w >= load
            self._charge_battery(net_kwh)

        # Generator
        if self.gen_running:
            self.gen_fuel_l = max(0.0, self.gen_fuel_l - 1.4 * hrs)
            self.gen_runtime_today_h += hrs
            target = 120.0 if self.gen_vent_blocked else 18.0
            if self.gen_fuel_l <= 0:
                self.gen_running = False
        else:
            target = 0.0
        self.gen_co += (target - self.gen_co) * min(1.0, dt / 600.0)

        # Water tank
        people = len(occupied_rooms - {COMPOUND})
        use = 0.0
        if devices["main_valve"].on:
            use += (0.002 + 0.004 * people) * dt         # household use
            if self.leak:
                use += 0.05 * dt
        if devices["irrigation"].on:
            use += 0.25 * dt
        fill = 0.6 * dt if (devices["borehole_pump"].on and self.power_ok) else 0.0
        if self.raining:
            fill += 0.02 * dt                             # rain harvesting
        self.tank_l = max(0.0, min(self.tank_cap_l, self.tank_l + fill - use))

        # Room climate
        for r in CLIMATE_ROOMS:
            t = self.temps[r]
            t += (self.outdoor_temp - t) * min(1.0, dt / 7200.0)
            ac = devices.get(f"ac_{r}")
            if ac and ac.on and self.power_ok and self.circuits.get(r, True):
                setpoint = float(ac.value or 23.0)
                t += (setpoint - t) * min(1.0, dt / 900.0)
                self.humidity[r] += (52.0 - self.humidity[r]) * min(1.0, dt / 900.0)
            else:
                self.humidity[r] += (70.0 - self.humidity[r]) * min(1.0, dt / 3600.0)
            if r == KITCHEN and r in self.fire_rooms:
                t += 0.02 * dt
            self.temps[r] = t

        # Hazards rise towards their scenario level; suppression brings them down.
        sprinkler = devices["sprinkler_kitchen"].on
        fan = devices["vent_fan_kitchen"].on
        for r, h in self.hazard.items():
            burning = r in self.fire_rooms and not (r == KITCHEN and sprinkler)
            targets = {"smoke": 6.0 if burning else 0.0, "heat": 75.0 if burning else 30.0,
                       "co": 90.0 if burning else 0.0,
                       "gas": 30.0 if (r == KITCHEN and self.gas_leak) else 0.0}
            if r == GENBAY:
                targets["co"] = max(targets["co"], self.gen_co)
            for k, target in targets.items():
                rate = dt / 120.0
                if k in ("smoke", "gas") and r == KITCHEN and fan and target < h[k]:
                    rate *= 4
                h[k] += (target - h[k]) * min(1.0, rate)
            if r == KITCHEN and sprinkler and r in self.fire_rooms:
                # Sprinkler discharge puts the fire out over a few minutes.
                if h["heat"] < 40:
                    self.fire_rooms.discard(r)

    def _charge_battery(self, kwh: float):
        self.battery_kwh = max(0.0, min(self.battery_kwh_cap, self.battery_kwh + kwh))

    def clear_hazards(self):
        self.fire_rooms.clear()
        self.gas_leak = False
        self.leak = False
        self.turbidity = 0.8
        self.gen_vent_blocked = False
        self.intruder = False
        self.visitor_at_door = False
        self.faults.clear()
