// decision_engine.h
//
// Reads the PIR and LDR, applies the dwell filter, and evaluates the two
// decision rules from the dissertation (section 4.3 of AGENT_BUILD_SPEC.md).
// When a rule fires it builds a Proposal and hands it to the safety layer
// (safety.h) via safetyHandleProposal(). This file never writes to the
// relay itself.

#ifndef DECISION_ENGINE_H
#define DECISION_ENGINE_H

#include <Arduino.h>

// A pending or just-created proposal. Mirrors the MQTT "proposal" payload
// in AGENT_BUILD_SPEC.md section 3.
struct Proposal {
  char id[16];          // e.g. "p-0042"
  char action[10];       // "LIGHT_ON" or "LIGHT_OFF"
  char confidence[5];    // "HIGH" or "LOW"
  char reason[64];
  unsigned long ts;              // unix-ish seconds (millis()/1000 since boot if no NTP)
  bool pending;                   // true while awaiting a response / escalation
  unsigned long createdAtMs;      // millis() timestamp, for the timeout check
};

void decisionEngineInit();

// Call once per loop(). Internally rate-limited to SENSOR_POLL_MS. Needs to
// know whether the lamp is currently on (from safety.h) so it never
// proposes an action the lamp is already in.
void decisionEngineUpdate(bool lampIsOn);

// Current sensor readings, published to MQTT by the caller (mqtt_client.cpp)
// whenever they change.
bool decisionEngineMotionState();      // debounced (post-dwell-filter) state
int decisionEngineLdrRaw();
bool decisionEngineIsDark();

// True if a stuck/disconnected sensor has been detected (see
// AGENT_BUILD_SPEC.md 4.5, "Sensor fault detection").
bool decisionEngineFaultDetected();
const char *decisionEngineFaultReason();

#endif // DECISION_ENGINE_H
