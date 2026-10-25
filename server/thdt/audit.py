"""Tamper-evident audit log (Safe AI: auditability).

Every decision, escalation, override and distillation trigger is stored in
SQLite. Each row carries the SHA-256 hash of the previous row, so editing or
deleting any past entry breaks the chain and verify() reports where.
"""

import hashlib
import sqlite3
import threading
import time
from pathlib import Path

GENESIS = "0" * 64


def _hash(prev, seq, ts, sim, twin, typ, detail) -> str:
    raw = f"{prev}|{seq}|{ts:.3f}|{sim}|{twin}|{typ}|{detail}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


class AuditLog:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(str(path), check_same_thread=False)
        self._lock = threading.Lock()
        self._db.execute(
            "CREATE TABLE IF NOT EXISTS events (seq INTEGER PRIMARY KEY, ts REAL, sim TEXT,"
            " twin TEXT, type TEXT, detail TEXT, prev TEXT, hash TEXT)")
        self._db.commit()
        row = self._db.execute("SELECT seq, hash FROM events ORDER BY seq DESC LIMIT 1").fetchone()
        self._seq, self._last = (row[0], row[1]) if row else (0, GENESIS)

    def log(self, twin: str, typ: str, detail: str, sim: str = "") -> dict:
        with self._lock:
            seq, ts = self._seq + 1, time.time()
            h = _hash(self._last, seq, ts, sim, twin, typ, detail)
            self._db.execute("INSERT INTO events VALUES (?,?,?,?,?,?,?,?)",
                             (seq, ts, sim, twin, typ, detail, self._last, h))
            self._db.commit()
            self._seq, self._last = seq, h
        entry = {"seq": seq, "ts": ts, "sim": sim, "twin": twin, "type": typ, "detail": detail}
        print(f"[{seq:5d}] {sim:>5} {twin:<6} {typ:<12} {detail}", flush=True)
        return entry

    def recent(self, n: int = 40) -> list[dict]:
        with self._lock:
            rows = self._db.execute(
                "SELECT seq, ts, sim, twin, type, detail FROM events ORDER BY seq DESC LIMIT ?",
                (n,)).fetchall()
        return [dict(zip(("seq", "ts", "sim", "twin", "type", "detail"), r)) for r in rows]

    def verify(self) -> tuple[bool, int, int | None]:
        """Returns (intact, rows checked, first broken seq or None)."""
        prev, count = GENESIS, 0
        with self._lock:
            rows = self._db.execute(
                "SELECT seq, ts, sim, twin, type, detail, prev, hash FROM events ORDER BY seq").fetchall()
        for seq, ts, sim, twin, typ, detail, stored_prev, stored_hash in rows:
            if stored_prev != prev or _hash(prev, seq, ts, sim, twin, typ, detail) != stored_hash:
                return False, count, seq
            prev, count = stored_hash, count + 1
        return True, count, None

    @property
    def count(self) -> int:
        return self._seq

    def close(self):
        with self._lock:
            self._db.close()
