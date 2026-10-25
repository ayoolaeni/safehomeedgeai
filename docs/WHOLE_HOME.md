# SafeHome whole-home implementation: the Thriftogentic Home Digital Twin

This document maps the design specifications to the code. The specifications
are:

- *Agentic Home Digital Twin* framework.
- *Thriftogentic Home Digital Twin* specifications: AHDT, AEDT, AF&SDT, AWDT.
- *Thriftonomous AI Homes in Resource-Constrained Settings*, the Lagos case
  study.

The prototype covers a **whole home**, not one room:

- **The AHDT** orchestrates six Agentic Subsystem Digital Twins (ASsDTs).
- **Every action** passes through a Thriftogentic AI layer before it can touch
  a device.
- **Each twin** earns autonomy on its own, from THRIFTOGENTIC to
  THRIFTONOMOUS.

## What is real, simulated or stubbed

| Part | Status |
| --- | --- |
| Sitting-room lamp: ESP32, PIR, LDR, relay, buzzer | **Real hardware.** Runs its own on-device agent; bridged into the AHDT over MQTT. |
| AHDT, the six twins, the Thriftogentic AI layer, graduation, audit log | **Real software**, running on the home server (`server/thdt`). |
| Local small language model (SLM) | **Real.** Ollama with `llama3.2` on the laptop; optional, with a rule-based fallback. |
| Solar, battery, grid, generator, water tank, borehole, smoke/heat/CO/gas detectors, sprinkler, locks, AC, other lights | **Simulated** sensors and actuators, with physics in `environment.py`. Labelled SIMULATED in the app. |
| Cloud LLM escalation, 4G/5G emergency channel, emergency services | **Stubbed.** They follow the specified path and are logged in the audit trail, but no paid API or SMS is used. |
| Distillation cycle | **Governed and logged** by the AHDT, the sole initiator. No model weights are changed in the prototype. |

## Layer 1–8 map

| Layer | Specification | Implementation |
| --- | --- | --- |
| 1 Physical | Sensors, actuators, physical twin | `environment.py`: 7 rooms, 59 devices, house physics. The real ESP32 lamp is in `firmware/`. |
| 2 Network & cloud | Home LAN, broadband/satellite, 4G/5G backup | Mosquitto MQTT on the LAN. Broadband and cellular link states with failover in `ahdt.escalate()`. Demo events take links down. |
| 3 Data ingestion | Raw data and knowledge | Device registry and snapshot (`home.py`). Hash-chained SQLite audit log (`audit.py`). |
| 4 Model | Local SLM, cloud LLM | `assistant.py`: `LocalSLM` (Ollama), with cloud escalation through the AHDT gateway. |
| 5 Thriftogentic AI | The five-principle fusion | `thriftogentic.py`: every action checked for Agentic, Edge, Safe, Resilient and Green. Each twin is only checked against the principles it selected. |
| 6 Service (agents) | Agents per twin | The `agents` list of each twin (`twins/*.py`). Each proposal records which agent raised it. |
| 7 Agentic (orchestrator) | AHDT orchestrator | `ahdt.py`: submit/approve/execute, emergency directives, escalation gateway, Green arbitration, graduation sign-off, distillation governance. |
| 8 Application | Resident dashboards | Flutter app with Home, Rooms (floor plan), Twins, Assistant and Activity (audit) tabs, plus the ESP32 lamp screen. |

## Twins and their principle selection

| Twin | Principles | Excluded and why | Agents |
| --- | --- | --- | --- |
| **AHDT** (orchestrator) | All five | n/a | Spatial & Equipment Registry, Global State, Emergency Coordination, Escalation Gateway, Distillation Governance, Edge Inference & Routing |
| **AEDT** Energy | All five | n/a | Source Selection, Load Management, Generator Control, Battery Management, Demand Coordination, Resilience Monitoring |
| **AF&SDT** Fire & Safety | Agentic, Edge, Safe, Resilient | Green: life safety is not an optimisation problem. **Permanently non-graduating.** | Detection, Suppression, Evacuation Support, Escalation, Health/Self-Test |
| **AWDT** Water | Agentic, Edge, Safe, Green | Resilient: tank, borehole and rain storage give passive continuity | Source Management, Treatment & Quality, Distribution, Irrigation Optimization, Energy-Water Coordination |
| **ACDT** Climate & lighting | Agentic, Edge, Safe, Green | Resilient: a comfort excursion is low-stakes | Comfort Control, Lighting Comfort, Air Quality, Energy-Aware Scheduling |
| **AA&SDT** Access & Security | Agentic, Edge, Safe, Resilient | Green: security is continuity-critical | Entry Recognition, Lock Control, Intrusion Detection, Egress Support |
| **ARDT** Resident (per-resident partitions) | Agentic, Edge, Safe | Minimal-fit liaison | Resident Liaison, Presence, Preference, Notification |

## How an action is decided

1. A twin's agent raises a **proposal**, with a category:
   - `failsafe`: protects life, property or critical loads.
   - `info`: a notification.
   - `routine`: an ordinary action.
   - `flexible`: an action that adds load.
   - `human_only`: always needs a person.
   - `governance`: a household decision, such as a graduation sign-off.
2. The **Thriftogentic AI layer** checks it:
   - **Agentic:** the action is inside the twin's bounded action space and
     within budgets, such as generator runtime.
   - **Edge:** the decision is made locally.
   - **Safe:** hard guardrails, the confidence gate, and human-only actions.
   - **Resilient:** the target device is healthy and has a supply.
   - **Green:** the energy budget. On battery below about 40%, extra load
     needs a person.
3. **The AHDT orchestrator** then acts on the result:
   - A blocked action is logged as `DENIED`.
   - `failsafe` and `info` actions run in **every** mode.
   - In **Manual** mode, the twin only observes.
   - In **Assisted** mode, the twin asks the household.
   - In **Autonomous** mode, the twin acts alone only if it is THRIFTONOMOUS,
     the confidence is HIGH and no check needs a person. Otherwise it asks.
   - People reversing an autonomous action within 60 seconds counts as an
     override, and too many overrides demote the twin.

## Hard rules (from the specifications)

- **Critical loads** (fridge, medicine fridge) are never shed, not even on
  command.
- **The fire alarm** can't be silenced by automation. A person can reset it
  only after the hazard has cleared.
- **Power stays cut** in a room while a hazard is still present.
- **Letting a stranger in** always needs a resident, even for a graduated
  Access twin.
- **Generator interlock:** no start when CO is at or above 50 ppm, or when
  the ventilation check fails. A CO spike stops the generator.
- **Potable water first:** irrigation is refused below 40% tank. A leak
  closes the main valve, and only a person may reopen it.
- **No twin self-graduates:** reaching THRIFTONOMOUS needs AHDT governance
  sign-off by the household. A sensor fault or a falling approval rate
  demotes the twin.
- **The AHDT alone** may escalate to residents or the cloud LLM, start
  distillation, and issue cross-domain emergency directives. Each twin keeps
  its own local fail-safes.

## Demonstration scenarios (flask icon in the app)

| Scenario | What the twins do |
| --- | --- |
| Arrive home (Lagos welcome-home case) | AA&SDT recognises the resident and proposes unlocking. Once unlocked, the resident is placed in the sitting room. ACDT proposes cooling, using Eco-Cooling on battery. ARDT speaks a welcome message on the laptop. |
| Grid outage | AEDT switches automatically to solar/battery (a fail-safe). Generator autostart is suppressed until the battery is below 20% with people home. Non-critical loads are shed below 30% (asks first) or 15% (fail-safe). |
| Kitchen fire | AF&SDT sounds the siren and starts the sprinkler. The AHDT emergency directive then unlocks all doors, cuts kitchen power, switches the AC off, turns on evacuation lights (including the real ESP32 lamp) and withdraws comfort requests. Residents are alerted with an evacuation route over the 4G/5G backup (stub). |
| Gas leak | Extraction fan on, kitchen power cut, doors unlocked, "do not switch anything on". |
| Blocked generator vent | AEDT stops the generator. Restarting is refused by the interlock. |
| Pipe leak, dirty water, tank at 20% | The main valve closes. Treatment starts. A refill is proposed, arbitrated by the AHDT against cooling while on battery. |
| Visitor, intruder | A visitor at the door always needs a person. An intruder while armed sounds the siren and sends a cellular alert. |
| Internet down, 4G/5G down | The cloud escalation is deferred. Emergency alerts fall back from cellular to broadband to local siren and voice. |
| Detector fault | AF&SDT flags the degraded detector. A twin that depends on the device is demoted. |

## Tests

- **Server:** `cd server` then `python -m unittest discover -s tests`. There
  are 18 end-to-end tests covering every rule above.
- **App:** `cd app` then `flutter test`.
