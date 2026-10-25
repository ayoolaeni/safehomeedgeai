"""Settings file (config.json, next to the server) and data folder."""

import copy
import json
import sys
from pathlib import Path

DEFAULTS = {
    "broker": {"host": "localhost", "port": 1883, "username": "", "password": ""},
    # How many simulated seconds pass per real second. 60 = one hour per minute.
    "sim_speed": 60,
    "start_time": "18:00",
    "residents": [{"id": "r1", "name": "Sonia"}],
    "ollama": {"enabled": True, "url": "http://localhost:11434", "model": "llama3.2"},
    # Speak resident messages on the laptop with Windows' built-in voice.
    "laptop_voice": True,
    # Short graduation thresholds for demonstrations (10 proposals, 2-minute
    # canary). Set to false for the dissertation values (100, 48 hours).
    "fast_graduation": True,
    "proposal_timeout_s": 90,
    "distillation_consent": True,
}


def base_dir() -> Path:
    """Folder that holds config.json and data/: next to the .exe when frozen."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


def _merge(base: dict, extra: dict) -> dict:
    out = copy.deepcopy(base)
    for k, v in extra.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _merge(out[k], v)
        else:
            out[k] = v
    return out


def load(path: Path) -> tuple[dict, bool]:
    """Returns (config, existed). Missing keys are filled in and saved back."""
    existed = path.exists()
    cfg = copy.deepcopy(DEFAULTS)
    if existed:
        try:
            cfg = _merge(DEFAULTS, json.loads(path.read_text(encoding="utf-8")))
        except (OSError, ValueError) as e:
            print(f"config: could not read {path} ({e}); using defaults")
    save(path, cfg)
    return cfg, existed


def save(path: Path, cfg: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
