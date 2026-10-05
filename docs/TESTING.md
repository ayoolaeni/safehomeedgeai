# Acceptance Test Checklist

Print this page (or screenshot each row as you go) for Chapter 4. Tick each
test off as it passes. Run them in order - later tests assume earlier ones
already work.

Before you start: flash the firmware, install the app, confirm the
connection tile shows CONNECTED, and leave the ESP32's Serial Monitor open
at 115200 baud so you can see what it's doing as you test.

**FAST_TEST_MODE**: `config.h` ships with `FAST_TEST_MODE` set to `true`,
which shortens the 30-minute absence timeout to 30 seconds and the 48-hour
canary period to 2 minutes, specifically so you can run TS9 and reach S5
without waiting real-world hours. Set it back to `false` before your final
demo if you want to show the real timings; the Serial Monitor prints a
warning banner at boot whenever it's active so you don't forget.

## Core functionality

| # | Test | Steps | Expected result | ☐ |
|---|---|---|---|---|
| TS1 | Manual buttons | Press TURN ON, then TURN OFF | Lamp follows within 500 ms; both actions appear in the activity log | ☐ |
| TS2 | Voice command | Hold the voice button and say "turn on the light" | Lamp comes on; log shows a manual/ACTION entry | ☐ |
| TS3 | Proposal appears | Switch to ASSISTED. Cover the LDR (dark), **wait 2 seconds** (HIGH confidence needs the light reading to have been stable that long), then wave in front of the PIR until it settles. Waving straight after covering gives a LOW-confidence proposal instead - also worth showing | A proposal card appears showing "Dark and motion detected" and HIGH confidence | ☐ |
| TS4 | Approve | Tap APPROVE on that proposal | Lamp turns on; log shows both a RESPONSE and an ACTION entry | ☐ |
| TS5 | Decline | Trigger another proposal (turn the lamp off first, then re-cover LDR + PIR) and tap DECLINE | Lamp does not change; the banner's approval rate drops | ☐ |
| TS6 | No false proposal | In a bright room, wave at the PIR | No proposal appears at all | ☐ |
| TS7 | Autonomy not yet earned | Select AUTONOMOUS while the banner still shows S1-S4 | Banner turns red and reads "Not yet earned — still asking first"; the system still asks before acting | ☐ |
| TS8 | Autonomous action | Once the banner shows S5 (THRIFTONOMOUS, green) and AUTONOMOUS is selected: cover LDR + wave PIR | Lamp acts immediately, no proposal card appears | ☐ |
| TS9 | Autonomous absence | While in S5/AUTONOMOUS with the lamp on, leave the sensor's view and wait out the absence timeout (30s with FAST_TEST_MODE, else 30 min) | Lamp switches off on its own | ☐ |

## Hazard / safety tests

These are the ones your dissertation's safety chapter most needs on video.

| # | Test | Steps | Expected result | ☐ |
|---|---|---|---|---|
| HZ1 | Fail-safe boot | While the lamp is ON, pull the ESP32's USB power, then plug it back in | On restart: lamp is OFF, mode shows MANUAL, a BOOT entry appears in the log, and no pending action resumes | ☐ |
| HZ2 | Works with no Wi-Fi | Stop the Mosquitto service (or turn off the laptop's Wi-Fi) while the ESP32 is in ASSISTED mode, then trigger dark+motion | The ESP32 keeps sensing and reacting locally; the buzzer beeps once when it escalates; the app shows DISCONNECTED and doesn't receive the proposal | ☐ |
| HZ3 | PIR disconnected | Unplug the PIR's signal wire from GPIO27 | Within 10 minutes (or immediately if it reads stuck HIGH), a FAULT is logged and the system is demoted to S1 with an alert visible in the app | ☐ |
| HZ4 | LDR stuck | **Not testable on this build.** This build reads the LDR module's DO (digital) pin, which legitimately stays the same for hours, so the "60 identical readings" stuck-sensor check is switched off (`LDR_USE_DIGITAL_OUTPUT` in `config.h`). To demonstrate HZ4 you need a module with an AO pin: wire AO to GPIO34, set `LDR_USE_DIGITAL_OUTPUT` to `false`, then short or disconnect the LDR. Record this limitation in Chapter 4. | With AO wiring: after 60 consecutive identical readings, a FAULT is logged and the system demotes to S1 | ☐ |
| HZ5 | Non-whitelisted command | Using a tool like MQTT Explorer or `mosquitto_pub`, publish `FAN_ON` to `home/light/cmd` | The message is rejected and logged as REJECTION; nothing on the relay changes | ☐ |
| HZ6 | Demotion on repeated declines | In ASSISTED mode, trigger and DECLINE proposals repeatedly until the recent approval rate drops below 85% (needs at least 10 responses recorded) | The system automatically demotes to S1; the banner turns amber within about two seconds of the triggering decline | ☐ |

### Marking the hazard suite passed (needed to reach S5)

HZ1-HZ6 involve physically pulling power and disconnecting sensors, so the
firmware can't verify them on its own. Once you've run through HZ1-HZ6 and
they all pass, type `H` and press Enter in the Serial Monitor. This sets a
flag the graduation engine checks before promoting from S4 to S5 - without
it, the system will sit at S4 forever even if every other condition is
met.

## How to trigger `mosquitto_pub` / `mosquitto_sub` for HZ5 (and general debugging)

From the laptop, with Mosquitto running:

```powershell
# Watch everything the system is doing:
mosquitto_sub -h localhost -t "home/#" -v

# Send the non-whitelisted command for HZ5:
mosquitto_pub -h localhost -t "home/light/cmd" -m "FAN_ON"
```

## Notes for Chapter 4

- Screenshot or photograph the app for each ☐ as you tick it, and keep the
  Serial Monitor visible in frame where possible - it's the clearest
  evidence a reader/examiner has that the decision is happening *on the
  device*, not in the app.
- HZ6 is worth recording on video: decline proposals until you see the
  banner flip from green/amber to demoted, with a timestamp overlay if you
  can, to demonstrate the "within two seconds" requirement.
