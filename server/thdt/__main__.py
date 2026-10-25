"""Start the home server:  python -m thdt   (or safehome-server.exe)."""

import sys

from . import VERSION, config
from .server import Server


def _ask(prompt: str, default: str) -> str:
    try:
        v = input(f"{prompt} [{default}]: ").strip()
    except EOFError:
        return default
    return v or default


def main():
    base = config.base_dir()
    path = base / "config.json"
    cfg, existed = config.load(path)
    print(f"SafeHome THDT home server {VERSION}")
    if not existed and sys.stdin and sys.stdin.isatty():
        print("First run: enter the Mosquitto login you created in Step 3 of the guide.")
        b = cfg["broker"]
        b["host"] = _ask("Broker address", b["host"])
        b["username"] = _ask("Broker username", b["username"] or "safehome")
        b["password"] = _ask("Broker password", b["password"])
        name = _ask("Resident's name", cfg["residents"][0]["name"])
        cfg["residents"][0]["name"] = name
        config.save(path, cfg)
        print(f"Saved to {path}. Edit that file to change these later.")
    print(f"Settings: {path}")
    Server(cfg, base / "data").run()


if __name__ == "__main__":
    main()
