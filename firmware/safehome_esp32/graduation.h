// graduation.h
//
// The graduation engine tracks how much the autonomous task has "earned
// the right" to act on its own. It holds one state (S1-S5), persisted in
// NVS (flash) so it survives reboot, and a handful of rolling counters used
// to promote or demote that state.
//
// This file only tracks numbers and state. It never touches the relay,
// Wi-Fi, or MQTT directly - the safety layer (safety.h/.cpp) is the only
// thing allowed to act on what this engine decides.

#ifndef GRADUATION_H
#define GRADUATION_H

#include <Arduino.h>

enum GraduationState {
  G_S1 = 1,   // THRIFTOGENTIC (baseline)
  G_S2 = 2,   // Shadow-mode rehearsal
  G_S3 = 3,   // Escalation tuning
  G_S4 = 4,   // Hazard suite + canary
  G_S5 = 5    // THRIFTONOMOUS (terminal, until demoted)
};

// Load persisted counters and state from NVS. Call once from setup().
void graduationInit();

// Human-readable name for a state, exactly as it appears in the MQTT
// contract's "stateName" field.
const char *graduationStateName(GraduationState state);

GraduationState graduationCurrentState();

// Call after every APPROVE/DECLINE response to an escalated proposal.
// Updates totalProposals/totalApprovals and the rolling 50-outcome buffer,
// then checks both promotion and demotion conditions. Returns true if the
// state changed (caller should log + publish home/agent/status).
bool graduationRecordProposalResponse(bool approved);

// Call after every proposal the system acted on with no human in the loop
// (i.e. an AUTONOMOUS + S5 + HIGH-confidence action). `overridden` is true
// if a manual command reversed it within 60 seconds. Updates the rolling
// 50-action override buffer and checks the override-rate demotion rule.
// Returns true if the state changed.
bool graduationRecordAutonomousAction(bool overridden);

// Call every time a LOW-confidence proposal is correctly escalated (i.e.
// NOT acted on automatically). This is what the S2->S3 gate ("every LOW
// proposal was escalated and none acted on") measures: enough LOW
// proposals have been handled correctly with zero violations. Returns true
// if the state changed.
bool graduationRecordLowConfidenceEscalated();

// Bug guard: call ONLY if a LOW-confidence proposal was ever acted on
// without escalation. This should never happen if the safety layer's
// confidence gate is implemented correctly - if it fires, something is
// broken. Forces immediate demotion to S1.
bool graduationRecordLowConfidenceViolation();

// Call as soon as decision_engine detects a stuck/disconnected sensor.
// Forces immediate demotion to S1.
bool graduationRecordSensorFault();

// Call once per loop() iteration. Advances the S3->S4->S5 promotion timer
// (the canary period) and returns true if the state changed as a result.
bool graduationTick();

// Manually mark the hazard suite (HZ1-HZ6 in docs/TESTING.md) as passed.
// These tests involve physically pulling power, unplugging sensors, etc,
// so they cannot be verified by the firmware itself - the student performs
// them and confirms success over Serial (see safehome_esp32.ino, sending
// 'H' over the Serial Monitor while in S3 marks the suite passed). Without
// this, S4 will never promote to S5 even if the canary timer elapses.
void graduationMarkHazardSuitePassed();
bool graduationHazardSuitePassed();

// Stats used to build the home/agent/status payload.
uint32_t graduationTotalProposals();
uint32_t graduationTotalApprovals();
float graduationOverallApprovalRatePct();   // totalApprovals / totalProposals * 100
float graduationRecentApprovalRatePct();    // over the last DEMOTE_WINDOW outcomes
const char *graduationLastChangeReason();

// True if the most recent state change (reported via a `true` return above)
// was a demotion rather than a promotion. Lets safety.cpp log the right
// event type (DEMOTION vs PROMOTION) without guessing from the state alone.
bool graduationLastChangeWasDemotion();

#endif // GRADUATION_H
