// graduation.cpp
//
// See graduation.h for the public interface. Two implementation notes
// worth reading before you touch this file:
//
// 1) S3 ("escalation tuning") gate. The dissertation defines it as "every
//    LOW proposal was escalated and none acted on". Because the safety
//    layer's confidence gate structurally prevents a LOW proposal from
//    ever being acted on, this is really an audit condition: has the
//    system handled a meaningful number of LOW proposals correctly, with
//    zero violations? We require LOW_PROPOSALS_FOR_S3 correct escalations
//    with zero violations since entering S2. If your dissertation defines
//    a different minimum count, change LOW_PROPOSALS_FOR_S3 below.
//
// 2) S4 ("hazard suite + canary"). The hazard suite (HZ1-HZ6 in
//    docs/TESTING.md) involves physically pulling power and disconnecting
//    sensors - the firmware cannot verify that for itself. The student
//    confirms it passed by sending 'H' over the Serial Monitor (see
//    safehome_esp32.ino). Once that flag is set AND the canary window
//    (EFFECTIVE_CANARY_MS) has elapsed with zero faults/violations/
//    demotions, S4 promotes to S5.

#include "graduation.h"
#include "config.h"
#include <Preferences.h>
#include <stdarg.h>
#include <string.h>

#define LOW_PROPOSALS_FOR_S3   5

static Preferences prefs;

static GraduationState state = G_S1;
static uint32_t totalProposals = 0;
static uint32_t totalApprovals = 0;
static uint32_t lowConfidenceEscalatedCount = 0;
static bool hazardSuitePassedFlag = false;
static unsigned long canaryStartMs = 0;
static bool canaryRunning = false;
static char lastChangeReason[80] = "Boot: starting at S1";
static bool lastChangeWasDemotion = false;

// Rolling ring buffers, mirrored in RAM and persisted to NVS as raw bytes.
// outcomes[i]: 1 = approved, 0 = declined. Used for the last-50 approval
// rate demotion check.
static uint8_t outcomes[DEMOTE_WINDOW];
static uint8_t outcomesCount = 0;   // how many slots are filled (caps at DEMOTE_WINDOW)
static uint8_t outcomesHead = 0;    // next write position

// autonomousActions[i]: 1 = overridden within 60s, 0 = not overridden.
static uint8_t autonomousActions[DEMOTE_WINDOW];
static uint8_t autonomousActionsCount = 0;
static uint8_t autonomousActionsHead = 0;

// ---------------------------------------------------------------------
// Persistence helpers
// ---------------------------------------------------------------------

static void saveCounters() {
  prefs.putUChar("state", (uint8_t)state);
  prefs.putUInt("totalProp", totalProposals);
  prefs.putUInt("totalAppr", totalApprovals);
  prefs.putUInt("lowEscCnt", lowConfidenceEscalatedCount);
  prefs.putBool("hazardOk", hazardSuitePassedFlag);
  prefs.putULong("canaryStart", canaryStartMs);
  prefs.putBool("canaryRun", canaryRunning);
  prefs.putBytes("outcomes", outcomes, sizeof(outcomes));
  prefs.putUChar("outCount", outcomesCount);
  prefs.putUChar("outHead", outcomesHead);
  prefs.putBytes("autoActs", autonomousActions, sizeof(autonomousActions));
  prefs.putUChar("actCount", autonomousActionsCount);
  prefs.putUChar("actHead", autonomousActionsHead);
}

void graduationInit() {
  prefs.begin("graduation", false);

  state = (GraduationState)prefs.getUChar("state", (uint8_t)G_S1);
  totalProposals = prefs.getUInt("totalProp", 0);
  totalApprovals = prefs.getUInt("totalAppr", 0);
  lowConfidenceEscalatedCount = prefs.getUInt("lowEscCnt", 0);
  hazardSuitePassedFlag = prefs.getBool("hazardOk", false);
  canaryStartMs = prefs.getULong("canaryStart", 0);
  canaryRunning = prefs.getBool("canaryRun", false);

  size_t n = prefs.getBytesLength("outcomes");
  if (n == sizeof(outcomes)) {
    prefs.getBytes("outcomes", outcomes, sizeof(outcomes));
  } else {
    memset(outcomes, 0, sizeof(outcomes));
  }
  outcomesCount = prefs.getUChar("outCount", 0);
  outcomesHead = prefs.getUChar("outHead", 0);

  size_t m = prefs.getBytesLength("autoActs");
  if (m == sizeof(autonomousActions)) {
    prefs.getBytes("autoActs", autonomousActions, sizeof(autonomousActions));
  } else {
    memset(autonomousActions, 0, sizeof(autonomousActions));
  }
  autonomousActionsCount = prefs.getUChar("actCount", 0);
  autonomousActionsHead = prefs.getUChar("actHead", 0);

  // canaryStartMs was stored against the pre-reboot millis() clock, which
  // is meaningless after a restart. If a canary was running, restart its
  // timer rather than trusting a stale timestamp.
  if (canaryRunning) {
    canaryStartMs = millis();
  }
}

// ---------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------

const char *graduationStateName(GraduationState s) {
  switch (s) {
    case G_S1: return "THRIFTOGENTIC";
    case G_S2: return "Shadow-mode rehearsal";
    case G_S3: return "Escalation tuning";
    case G_S4: return "Hazard suite + canary";
    case G_S5: return "THRIFTONOMOUS";
    default:   return "UNKNOWN";
  }
}

GraduationState graduationCurrentState() { return state; }

static void setLastChangeReason(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vsnprintf(lastChangeReason, sizeof(lastChangeReason), fmt, args);
  va_end(args);
}

const char *graduationLastChangeReason() { return lastChangeReason; }
bool graduationLastChangeWasDemotion() { return lastChangeWasDemotion; }

uint32_t graduationTotalProposals() { return totalProposals; }
uint32_t graduationTotalApprovals() { return totalApprovals; }

float graduationOverallApprovalRatePct() {
  if (totalProposals == 0) return 0.0f;
  return (100.0f * (float)totalApprovals) / (float)totalProposals;
}

float graduationRecentApprovalRatePct() {
  if (outcomesCount == 0) return 100.0f;   // no data yet: don't falsely demote
  uint8_t approvedCount = 0;
  for (uint8_t i = 0; i < outcomesCount; i++) {
    if (outcomes[i]) approvedCount++;
  }
  return (100.0f * (float)approvedCount) / (float)outcomesCount;
}

static float overrideRatePct() {
  if (autonomousActionsCount == 0) return 0.0f;
  uint8_t overriddenCount = 0;
  for (uint8_t i = 0; i < autonomousActionsCount; i++) {
    if (autonomousActions[i]) overriddenCount++;
  }
  return (100.0f * (float)overriddenCount) / (float)autonomousActionsCount;
}

static void pushOutcome(bool approved) {
  outcomes[outcomesHead] = approved ? 1 : 0;
  outcomesHead = (outcomesHead + 1) % DEMOTE_WINDOW;
  if (outcomesCount < DEMOTE_WINDOW) outcomesCount++;
}

static void pushAutonomousAction(bool overridden) {
  autonomousActions[autonomousActionsHead] = overridden ? 1 : 0;
  autonomousActionsHead = (autonomousActionsHead + 1) % DEMOTE_WINDOW;
  if (autonomousActionsCount < DEMOTE_WINDOW) autonomousActionsCount++;
}

// ---------------------------------------------------------------------
// Demotion
// ---------------------------------------------------------------------

static bool demoteToS1(const char *reason) {
  bool changed = (state != G_S1);
  state = G_S1;
  canaryRunning = false;
  if (changed) {
    setLastChangeReason("Demoted: %s", reason);
    lastChangeWasDemotion = true;
  }
  saveCounters();
  return changed;
}

// ---------------------------------------------------------------------
// Promotion checks (S1 -> S2 -> S3 -> S4 -> S5)
// ---------------------------------------------------------------------

static bool checkPromotion() {
  bool changed = false;

  if (state == G_S1 && totalProposals >= G1_MIN_PROPOSALS) {
    state = G_S2;
    setLastChangeReason("Promoted to S2: %lu proposals logged", (unsigned long)totalProposals);
    changed = true;
  }

  if (state == G_S2 && graduationOverallApprovalRatePct() >= G2_MIN_APPROVAL_PCT) {
    state = G_S3;
    setLastChangeReason("Promoted to S3: approval rate %.1f%% >= %d%%",
                         graduationOverallApprovalRatePct(), G2_MIN_APPROVAL_PCT);
    changed = true;
  }

  if (state == G_S3 && lowConfidenceEscalatedCount >= LOW_PROPOSALS_FOR_S3) {
    state = G_S4;
    canaryStartMs = millis();
    canaryRunning = true;
    setLastChangeReason("Promoted to S4: %lu LOW proposals escalated cleanly, canary started",
                         (unsigned long)lowConfidenceEscalatedCount);
    changed = true;
  }

  if (state == G_S4 && hazardSuitePassedFlag && canaryRunning &&
      (millis() - canaryStartMs) >= EFFECTIVE_CANARY_MS) {
    state = G_S5;
    canaryRunning = false;
    setLastChangeReason("Promoted to S5: hazard suite passed, canary elapsed cleanly");
    changed = true;
  }

  if (changed) {
    lastChangeWasDemotion = false;
    saveCounters();
  }
  return changed;
}

// ---------------------------------------------------------------------
// Public recording functions
// ---------------------------------------------------------------------

bool graduationRecordProposalResponse(bool approved) {
  totalProposals++;
  if (approved) totalApprovals++;
  pushOutcome(approved);

  bool changed = false;

  // Require a small minimum sample (10) before the recent-rate demotion
  // rule can fire, so a single early decline doesn't demote a system that
  // has barely started.
  if (outcomesCount >= 10 && graduationRecentApprovalRatePct() < DEMOTE_APPROVAL_PCT) {
    char reason[64];
    snprintf(reason, sizeof(reason), "approval rate %.0f%% over last %u",
             graduationRecentApprovalRatePct(), outcomesCount);
    changed = demoteToS1(reason);
    saveCounters();
    return changed;
  }

  changed = checkPromotion();
  saveCounters();
  return changed;
}

bool graduationRecordAutonomousAction(bool overridden) {
  pushAutonomousAction(overridden);

  if (autonomousActionsCount >= 10 && overrideRatePct() > DEMOTE_OVERRIDE_PCT) {
    char reason[64];
    snprintf(reason, sizeof(reason), "override rate %.0f%% over last %u autonomous actions",
             overrideRatePct(), autonomousActionsCount);
    bool changed = demoteToS1(reason);
    saveCounters();
    return changed;
  }

  saveCounters();
  return false;
}

bool graduationRecordLowConfidenceEscalated() {
  lowConfidenceEscalatedCount++;
  bool changed = checkPromotion();
  saveCounters();
  return changed;
}

bool graduationRecordLowConfidenceViolation() {
  bool changed = demoteToS1("LOW-confidence proposal acted on without escalation (safety bug guard)");
  saveCounters();
  return changed;
}

bool graduationRecordSensorFault() {
  bool changed = demoteToS1("sensor fault detected");
  saveCounters();
  return changed;
}

bool graduationTick() {
  // Currently nothing needs to happen every tick beyond what checkPromotion
  // already evaluates when counters change - the canary elapsing is
  // re-checked here so S4->S5 can fire even with no new proposals arriving.
  if (state == G_S4) {
    return checkPromotion();
  }
  return false;
}

void graduationMarkHazardSuitePassed() {
  hazardSuitePassedFlag = true;
  saveCounters();
}

bool graduationHazardSuitePassed() { return hazardSuitePassedFlag; }
