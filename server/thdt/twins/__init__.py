from .access import AccessSecurityTwin
from .climate import ClimateTwin
from .energy import EnergyTwin
from .fire import FireSafetyTwin
from .resident import ResidentTwin
from .water import WaterTwin

ALL_TWINS = (EnergyTwin, FireSafetyTwin, WaterTwin, ClimateTwin, AccessSecurityTwin, ResidentTwin)
