"""End-to-end tests of the home server, without a broker.

Run from the server folder:  python -m unittest discover -s tests -v
"""

import copy
import json
import sqlite3
import tempfile
import time
import unittest
from pathlib import Path

from thdt import config
from thdt.audit import AuditLog
from thdt.graduation import Graduation
from thdt.model import ASSISTED, AUTONOMOUS, Proposal
from thdt.server import Server


def make_server(**overrides) -> Server:
    cfg = copy.deepcopy(config.DEFAULTS)
    cfg.update(laptop_voice=False, **overrides)
    cfg["ollama"]["enabled"] = False
    tmp = Path(tempfile.mkdtemp())
    s = Server(cfg, tmp)
    s.published = []
    s.publish = lambda topic, payload, retain=False: s.published.append((topic, payload))
    s.home.publish = s.publish
    return s


def run(s: Server, sim_seconds: float, step: float = 15.0):
    t = 0.0
    while t < sim_seconds:
        s.home.env.sim_s += step
        s.step(step)
        t += step


def graduate(twin):
    g = twin.graduation
    for _ in range(g.min_proposals):
        g.record_response(True)
    g.mark_hazard_suite()
    g.canary_s = 0
    g.tick(time.time() + 1)
    g.signoff(True)
    assert g.thriftonomous


class AuditTests(unittest.TestCase):
    def test_tampering_is_detected(self):
        path = Path(tempfile.mkdtemp()) / "a.db"
        log = AuditLog(path)
        for i in range(5):
            log.log("AEDT", "TEST", f"entry {i}")
        self.assertEqual(log.verify(), (True, 5, None))
        log.close()
        db = sqlite3.connect(str(path))
        db.execute("UPDATE events SET detail='edited' WHERE seq=3")
        db.commit()
        db.close()
        ok, _, bad = AuditLog(path).verify()
        self.assertFalse(ok)
        self.assertEqual(bad, 3)


class GraduationTests(unittest.TestCase):
    def test_ladder_needs_household_signoff(self):
        g = Graduation("AEDT", fast=True)
        for _ in range(10):
            g.record_response(True)
        self.assertEqual(g.state, 3)
        g.mark_hazard_suite()
        self.assertEqual(g.state, 4)
        g.canary_s = 0
        self.assertTrue(g.tick(time.time() + 1))
        self.assertEqual(g.state, 4, "must not self-graduate")
        g.signoff(True)
        self.assertTrue(g.thriftonomous)

    def test_low_approval_demotes(self):
        g = Graduation("ACDT", fast=True)
        for _ in range(10):
            g.record_response(True)
        for _ in range(5):
            g.record_response(False)
        self.assertEqual(g.state, 1)

    def test_fire_twin_never_graduates(self):
        s = make_server()
        fire = s.home.twins["AF&SDT"]
        for _ in range(50):
            fire.graduation.record_response(True)
        fire.graduation.mark_hazard_suite()
        self.assertEqual(fire.graduation.state, 1)


class ScenarioTests(unittest.TestCase):
    def test_blackout_failover_runs_even_in_manual(self):
        s = make_server()
        run(s, 60)
        s.scenario("blackout")
        run(s, 60)
        self.assertEqual(s.home.env.source, "BATTERY")
        self.assertTrue(s.home.env.power_ok)

    def test_kitchen_fire_cross_domain_response(self):
        s = make_server()
        s.home.devices["lock_front"].on = True
        s.scenario("fire", "kitchen")
        run(s, 15 * 60)
        h = s.home
        self.assertTrue(h.devices["siren"].on)
        self.assertTrue(h.devices["sprinkler_kitchen"].on)
        self.assertFalse(h.devices["lock_front"].on, "doors unlocked for evacuation")
        self.assertFalse(h.env.circuits["kitchen"], "kitchen power cut")
        self.assertTrue(any(a["id"] == "fire_kitchen" for a in h.alerts.values()))
        types = [e["type"] for e in h.audit.recent(200)]
        self.assertIn("EMERGENCY", types)
        self.assertIn("CELLULAR", types)

    def test_alarm_cannot_be_reset_while_hazard_present(self):
        s = make_server()
        s.scenario("gas")
        run(s, 10 * 60)
        r = s.home.ahdt.manual("siren", action="ALARM_OFF")
        self.assertTrue(r.startswith("Not allowed"))
        self.assertTrue(s.home.devices["siren"].on)
        s.scenario("clear")
        run(s, 30 * 60)
        r = s.home.ahdt.manual("siren", action="ALARM_OFF")
        self.assertFalse(r.startswith("Not allowed"), r)
        self.assertFalse(s.home.devices["siren"].on)

    def test_critical_load_never_shed(self):
        s = make_server()
        r = s.home.ahdt.manual("fridge", False)
        self.assertTrue(r.startswith("Not allowed"))
        self.assertTrue(s.home.devices["fridge"].on)

    def test_stranger_always_needs_a_person(self):
        s = make_server()
        access = s.home.twins["AA&SDT"]
        graduate(access)
        access.mode = AUTONOMOUS
        s.scenario("visitor")
        run(s, 60)
        self.assertTrue(s.home.devices["lock_front"].on, "door must stay locked")
        self.assertTrue(any(p.action == "UNLOCK" for p in s.home.pending))

    def test_assisted_arrival_and_welcome(self):
        s = make_server()
        s.home.ahdt.set_mode("ALL", ASSISTED)
        s.scenario("arrive")
        run(s, 30)
        p = next(p for p in s.home.pending if p.action == "UNLOCK")
        s.home.ahdt.respond(p.id, True)
        run(s, 30)
        self.assertEqual(s.home.residents[0]["location"], "sitting_room")
        self.assertTrue(any("Welcome home" in m["text"] for m in s.home.messages))
        self.assertEqual(s.home.twins["AA&SDT"].graduation.proposals, 1)

    def test_autonomous_action_and_override(self):
        s = make_server()
        climate = s.home.twins["ACDT"]
        graduate(climate)
        climate.mode = AUTONOMOUS
        s.home.env.set_time("20:00")
        s.home.move_resident("r1", "bedroom")
        run(s, 60)
        self.assertTrue(s.home.devices["light_bedroom"].on)
        s.home.ahdt.manual("light_bedroom", False)
        self.assertEqual(list(climate.graduation.auto_recent), [True])

    def test_green_ac_on_low_battery_needs_a_person(self):
        s = make_server()
        climate = s.home.twins["ACDT"]
        graduate(climate)
        climate.mode = AUTONOMOUS
        env = s.home.env
        env.grid_up, env.source = False, "BATTERY"
        env.battery_kwh = 0.35 * env.battery_kwh_cap
        env.temps["sitting_room"] = 30.0
        run(s, 30)
        self.assertFalse(s.home.devices["ac_sitting_room"].on)
        p = next(p for p in s.home.pending if p.action == "AC_ON")
        self.assertEqual(p.params["setpoint"], 24.5, "Eco-Cooling profile on battery")

    def test_leak_closes_valve_and_only_a_person_reopens(self):
        s = make_server()
        s.scenario("leak")
        run(s, 60)
        self.assertFalse(s.home.devices["main_valve"].on)
        v = s.home.thriftogentic.evaluate(Proposal("AWDT", "OPEN_MAIN_VALVE", "test", "main_valve"))
        self.assertFalse(v.allowed)

    def test_generator_co_interlock(self):
        s = make_server()
        env = s.home.env
        env.grid_up, env.source, env.gen_running = False, "GENERATOR", True
        s.scenario("gen_co")
        run(s, 40 * 60)
        self.assertFalse(env.gen_running)
        self.assertIn("STOP_GENERATOR", [e["detail"].split(":")[0] for e in s.home.audit.recent(300)
                                         if e["type"] == "FAILSAFE"])
        r = s.home.ahdt.manual("generator", True)
        self.assertTrue(r.startswith("Not allowed"), r)

    def test_assistant_rules(self):
        s = make_server()
        s.inbox.queue.clear()
        s.assistant.handle("q1", "turn on the kitchen light")
        self.assertTrue(s.home.devices["light_kitchen"].on)
        s.assistant.handle("q2", "what is the battery level?")
        s._drain_inbox()
        answers = [p for t, p in s.published if t == "thdt/answer"]
        self.assertTrue(any("battery" in a["answer"] for a in answers))

    def test_question_without_slm_is_escalated_to_cloud(self):
        s = make_server()
        s.assistant.handle("q3", "Can you plan my electricity budget for next month?")
        s._drain_inbox()
        self.assertEqual(s.home.ahdt.cloud_cases, 1)

    def test_snapshot_is_json(self):
        s = make_server()
        run(s, 120)
        snap = s.home.snapshot()
        json.dumps(snap)
        self.assertEqual(len(snap["twins"]), 6)
        self.assertEqual(snap["twins"][1]["principles"]["green"], False)

    def test_full_day_runs_without_errors(self):
        s = make_server()
        s.home.ahdt.set_mode("ALL", ASSISTED)
        for name in ("blackout", "leave", "intruder", "arrive", "grid_restore", "rain", "low_tank"):
            s.scenario(name)
            run(s, 2 * 3600, step=60)
            for p in list(s.home.pending):
                s.home.ahdt.respond(p.id, True)
        ok, n, _ = s.home.audit.verify()
        self.assertTrue(ok)
        self.assertGreater(n, 20)


if __name__ == "__main__":
    unittest.main()
