// safety.h
//
// All seven safety mechanisms from AGENT_BUILD_SPEC.md section 4.4 live in
// this file, each as its own named function so the student can point at
// exactly one during their project defence:
//
//   1. isWhitelisted()            - action whitelist
//   2. (confidence gate)          - enforced inside safetyHandleProposal()
//   3. (autonomy switch)          - enforced inside safetySetMode()
//   4. safetyHandleManualCommand()- manual override, always wins
//   5. safetyFailSafeInit()       - fail-safe boot defaults
//   6. safetyLog()                - tamper-evident sequential log
//   7. (local escalation)         - enforced inside safetyHandleProposal()
//
// This is the ONLY file allowed to write to PIN_RELAY. decision_engine.cpp
// and mqtt_client.cpp must always go through here.

#ifndef SAFETY_H
#define SAFETY_H

#include <Arduino.h>
#include "decision_engine.h"

enum OperatingMode { MODE_MANUAL = 0, MODE_ASSISTED = 1, MODE_AUTONOMOUS = 2 };

// --- Boot / relay -------------------------------------------------------

// Mechanism 5: fail-safe defaults. MUST be called first in setup(), before
// WiFi.begin() or anything else. Forces the relay to the OFF state, then
// sets pinMode(OUTPUT), then resets mode to MANUAL. Logs a BOOT entry once
// the log's sequence counter has been loaded from NVS.
void safetyFailSafeInit();

bool safetyLampIsOn();

// --- Mode ----------------------------------------------------------------

// Mechanism 3: autonomy switch. Selecting MANUAL or ASSISTED takes effect
// immediately. Selecting AUTONOMOUS is always *accepted and recorded* as
// the confirmed mode (so home/mode/state reflects the user's choice), but
// only takes effect behaviourally once graduation has reached S5 - until
// then the system keeps behaving exactly like ASSISTED. Graduation state
// itself is never reset by a mode change.
void safetySetMode(OperatingMode mode);
OperatingMode safetyGetMode();
const char *safetyModeName(OperatingMode mode);

// True if the confirmed mode is AUTONOMOUS and graduation has reached S5 -
// i.e. autonomy is actually *active*, not just requested.
bool safetyAutonomyIsActive();

// --- Commands & proposals --------------------------------------------------

// Mechanism 1: action whitelist. Only "LIGHT_ON" / "LIGHT_OFF" are valid.
bool safetyIsWhitelisted(const char *action);

// Mechanism 4: manual override. Called whenever home/light/cmd arrives.
// Executed immediately in every mode; cancels any pending proposal. If a
// non-whitelisted action arrives it is rejected and logged instead.
void safetyHandleManualCommand(const char *action);

// Central entry point for a freshly-formed proposal from decision_engine.
// Applies mechanism 2 (confidence gate) and mechanism 7 (local escalation):
//  - MANUAL mode: never called (decision engine does not run in MANUAL).
//  - ASSISTED, or AUTONOMOUS-but-not-yet-S5: always escalate (publish +
//    beep + wait for a response).
//  - AUTONOMOUS + S5 + HIGH confidence: act immediately, no human involved.
//  - AUTONOMOUS + S5 + LOW confidence: MUST escalate, never act. This is
//    the hard rule from the spec - violating it demotes the system.
void safetyHandleProposal(const char *action, const char *confidence, const char *reason);

// Called when home/agent/response arrives with {"id":..., "answer":...}.
void safetyHandleResponse(const char *id, const char *answer);

// Call once per loop(). Expires a pending proposal if PROPOSAL_TIMEOUT_MS
// has elapsed with no response (mechanism 7: hold current state, log
// ESCALATION "expired, no response").
void safetyTick();

const Proposal *safetyCurrentProposal();   // NULL if none pending

// --- Tamper-evident log (mechanism 6) -------------------------------------

// Log entry types, exactly as listed in AGENT_BUILD_SPEC.md section 3.
void safetyLog(const char *type, const String &detail);

// Loads the persisted `seq` counter from NVS. Call from safetyFailSafeInit()
// before the first safetyLog() call of this boot.
void safetyLogInit();

struct LogEntry {
  uint32_t seq;
  unsigned long ts;
  char type[12];
  char detail[120];
};

// Last 20 entries in RAM (newest last), for replay to a freshly (re)connected
// phone - see mqtt_client.cpp, which replays these right after MQTT connects.
int safetyRecentLogCount();
const LogEntry *safetyRecentLog(int index);

#endif // SAFETY_H
