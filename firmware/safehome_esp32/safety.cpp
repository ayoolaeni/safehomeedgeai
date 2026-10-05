// safety.cpp
//
// See safety.h for which function implements which of the seven safety
// mechanisms. Read AGENT_BUILD_SPEC.md section 4.4 alongside this file.

#include "safety.h"
#include "graduation.h"
#include "mqtt_client.h"
#include "config.h"
#include <Preferences.h>
#include <string.h>

static Preferences logPrefs;

static OperatingMode currentMode = MODE_MANUAL;
static bool lampOn = false;

static Proposal currentProposal;
static int proposalCounter = 0;

// Tracks the 60-second window after an autonomous action, during which a
// reversing manual command counts as an OVERRIDE (see safetyHandleManualCommand
// and safetyTick). Exactly one graduationRecordAutonomousAction() call is
// made per autonomous action, once this window resolves either way.
static bool awaitingOverrideWindow = false;
static bool pendingOverrideActionOn = false;
static unsigned long pendingOverrideDeadlineMs = 0;

// Tamper-evident log
static uint32_t logSeq = 0;
#define RECENT_LOG_SIZE 20
static LogEntry recentLog[RECENT_LOG_SIZE];
static uint8_t recentLogCount = 0;
static uint8_t recentLogHead = 0;   // next write position (circular)

// ---------------------------------------------------------------------
// Relay control - the only place PIN_RELAY is ever written
// ---------------------------------------------------------------------

static void writeRelay(bool on) {
  bool activeLevel = RELAY_ACTIVE_LOW ? LOW : HIGH;
  bool inactiveLevel = RELAY_ACTIVE_LOW ? HIGH : LOW;
  digitalWrite(PIN_RELAY, on ? activeLevel : inactiveLevel);
#if LAMP_IN_SYNCED_WITH_RELAY
  // A second, independent switch in series with the relay - see config.h.
  // The relay is still the thing genuinely being driven and demonstrated;
  // this just makes sure the lamp positively cannot light unless both
  // agree, which protects against the relay's own contacts misbehaving.
  digitalWrite(PIN_LAMP_IN, on ? HIGH : LOW);
#endif
}

static void setRelay(bool on) {
  lampOn = on;
  writeRelay(on);
  publishLightState(on);
}

bool safetyLampIsOn() { return lampOn; }

// ---------------------------------------------------------------------
// Mechanism 6: tamper-evident log
// ---------------------------------------------------------------------

void safetyLogInit() {
  logPrefs.begin("safetylog", false);
  logSeq = logPrefs.getUInt("seq", 0);
}

void safetyLog(const char *type, const String &detail) {
  logSeq++;
  logPrefs.putUInt("seq", logSeq);   // persist immediately: a gap after a crash is the tamper-evidence

  LogEntry entry;
  entry.seq = logSeq;
  entry.ts = millis() / 1000UL;   // no RTC/NTP on this board: seconds since boot, not wall-clock time
  strncpy(entry.type, type, sizeof(entry.type) - 1);
  entry.type[sizeof(entry.type) - 1] = '\0';
  strncpy(entry.detail, detail.c_str(), sizeof(entry.detail) - 1);
  entry.detail[sizeof(entry.detail) - 1] = '\0';

  recentLog[recentLogHead] = entry;
  recentLogHead = (recentLogHead + 1) % RECENT_LOG_SIZE;
  if (recentLogCount < RECENT_LOG_SIZE) recentLogCount++;

  Serial.printf("[LOG #%lu] %s: %s\n", (unsigned long)entry.seq, entry.type, entry.detail);
  publishLog(entry);
}

int safetyRecentLogCount() { return recentLogCount; }

const LogEntry *safetyRecentLog(int index) {
  // index 0 = oldest kept entry, increasing toward newest.
  if (index < 0 || index >= recentLogCount) return NULL;
  int start = (recentLogCount < RECENT_LOG_SIZE) ? 0 : recentLogHead;
  int actual = (start + index) % RECENT_LOG_SIZE;
  return &recentLog[actual];
}

// ---------------------------------------------------------------------
// Mechanism 5: fail-safe defaults
// ---------------------------------------------------------------------

void safetyFailSafeInit() {
  // Pre-load the output register to OFF, THEN switch the pin to OUTPUT.
  // This ordering means the pin starts driving the correct level the
  // instant it becomes an output, instead of glitching through whatever
  // the pin's power-on default is.
  writeRelay(false);
  pinMode(PIN_RELAY, OUTPUT);
#if LAMP_IN_SYNCED_WITH_RELAY
  pinMode(PIN_LAMP_IN, OUTPUT);
#endif
  writeRelay(false);   // belt and braces: guarantee OFF once more now both pins are real outputs
  lampOn = false;

  pinMode(PIN_BUZZER, OUTPUT);
  digitalWrite(PIN_BUZZER, LOW);

  // Boot mode is ALWAYS MANUAL, regardless of what it was before reset.
  // Graduation state is preserved - only the mode resets.
  currentMode = MODE_MANUAL;
  currentProposal.pending = false;
  awaitingOverrideWindow = false;

  safetyLogInit();

  String bootMsg = "SafeHome Edge AI booting. Relay forced OFF, mode forced MANUAL.";
#if FAST_TEST_MODE
  bootMsg += " FAST_TEST_MODE is ON: absence timeout and canary period are shortened for demo/testing.";
#endif
  safetyLog("BOOT", bootMsg);
}

// ---------------------------------------------------------------------
// Mode / mechanism 3: autonomy switch
// ---------------------------------------------------------------------

const char *safetyModeName(OperatingMode mode) {
  switch (mode) {
    case MODE_MANUAL:     return "MANUAL";
    case MODE_ASSISTED:   return "ASSISTED";
    case MODE_AUTONOMOUS: return "AUTONOMOUS";
    default:              return "MANUAL";
  }
}

OperatingMode safetyGetMode() { return currentMode; }

bool safetyAutonomyIsActive() {
  return currentMode == MODE_AUTONOMOUS && graduationCurrentState() == G_S5;
}

void safetySetMode(OperatingMode mode) {
  currentMode = mode;   // always accepted and confirmed - see header comment

  if (mode == MODE_MANUAL && currentProposal.pending) {
    // Automation is fully suspended in MANUAL: a proposal still waiting
    // for a response no longer makes sense once the user has taken the
    // wheel, so it is dropped silently (the pending state is cleared but
    // no separate log entry is made - the MODE_CHANGE entry below covers
    // it).
    currentProposal.pending = false;
  }

  String detail = String("Mode set to ") + safetyModeName(mode);
  if (mode == MODE_AUTONOMOUS && graduationCurrentState() != G_S5) {
    detail += " (accepted, but graduation state is ";
    detail += graduationStateName(graduationCurrentState());
    detail += " - behaving as ASSISTED until S5 is reached)";
  }
  safetyLog("MODE_CHANGE", detail);
  publishModeState(mode);
}

// ---------------------------------------------------------------------
// Mechanism 1: action whitelist
// ---------------------------------------------------------------------

bool safetyIsWhitelisted(const char *action) {
  return strcmp(action, "LIGHT_ON") == 0 || strcmp(action, "LIGHT_OFF") == 0;
}

// ---------------------------------------------------------------------
// Mechanism 4: manual override
// ---------------------------------------------------------------------

void safetyHandleManualCommand(const char *action) {
  if (!safetyIsWhitelisted(action)) {
    safetyLog("REJECTION", String("Rejected non-whitelisted command on home/light/cmd: ") + action);
    return;
  }

  bool turnOn = strcmp(action, "LIGHT_ON") == 0;

  if (currentProposal.pending) {
    currentProposal.pending = false;   // manual command always cancels a pending proposal
  }

  setRelay(turnOn);
  safetyLog("ACTION", String("Manual: ") + action);

  if (awaitingOverrideWindow && millis() <= pendingOverrideDeadlineMs &&
      turnOn != pendingOverrideActionOn) {
    safetyLog("OVERRIDE", "Manual command reversed an autonomous action within 60 seconds");
    graduationRecordAutonomousAction(true);
    awaitingOverrideWindow = false;
  }
}

// ---------------------------------------------------------------------
// Mechanisms 2 + 7: confidence gate and local escalation
// ---------------------------------------------------------------------

static void beepBuzzer() {
  // A short blocking beep (200ms) is simple and easy to reason about; the
  // loop only escalates occasionally, so a brief pause here is acceptable
  // for a project of this size.
  digitalWrite(PIN_BUZZER, HIGH);
  delay(200);
  digitalWrite(PIN_BUZZER, LOW);
}

static void startEscalation(const char *action, const char *confidence, const char *reason) {
  proposalCounter++;
  snprintf(currentProposal.id, sizeof(currentProposal.id), "p-%04d", proposalCounter);
  strncpy(currentProposal.action, action, sizeof(currentProposal.action) - 1);
  currentProposal.action[sizeof(currentProposal.action) - 1] = '\0';
  strncpy(currentProposal.confidence, confidence, sizeof(currentProposal.confidence) - 1);
  currentProposal.confidence[sizeof(currentProposal.confidence) - 1] = '\0';
  strncpy(currentProposal.reason, reason, sizeof(currentProposal.reason) - 1);
  currentProposal.reason[sizeof(currentProposal.reason) - 1] = '\0';
  currentProposal.ts = millis() / 1000UL;
  currentProposal.createdAtMs = millis();
  currentProposal.pending = true;

  safetyLog("PROPOSAL", String(currentProposal.id) + ": " + action + " (" + confidence + ") - " + reason);
  publishProposal(currentProposal);
  beepBuzzer();
}

void safetyHandleProposal(const char *action, const char *confidence, const char *reason) {
  if (currentMode == MODE_MANUAL) return;   // automation is off in MANUAL

  if (!safetyIsWhitelisted(action)) {
    safetyLog("REJECTION", String("Decision engine proposed a non-whitelisted action: ") + action);
    return;
  }

  if (currentProposal.pending) return;   // one proposal at a time - wait for it to resolve

  bool autonomyActive = safetyAutonomyIsActive();   // AUTONOMOUS mode AND graduation == S5
  bool isHigh = strcmp(confidence, "HIGH") == 0;

  if (autonomyActive && isHigh) {
    // Act immediately, no human in the loop.
    bool turnOn = strcmp(action, "LIGHT_ON") == 0;
    setRelay(turnOn);
    safetyLog("ACTION", String("Autonomous: ") + action + " - " + reason);

    awaitingOverrideWindow = true;
    pendingOverrideActionOn = turnOn;
    pendingOverrideDeadlineMs = millis() + 60000UL;
    return;
  }

  // Every other case escalates: ASSISTED mode, AUTONOMOUS-but-not-yet-S5
  // (must behave like ASSISTED per the spec), and AUTONOMOUS+S5+LOW
  // confidence (the hard confidence-gate rule - LOW is NEVER auto-acted).
  //
  // The S2->S3 graduation gate ("every LOW proposal was escalated and none
  // acted on") is counted here for ANY LOW-confidence proposal, not just
  // ones seen while autonomy is already active - autonomy only ever
  // *becomes* active once S5 is reached, and S5 is reached via S3, so the
  // count has to be able to build up earlier (in MANUAL-adjacent/ASSISTED
  // behaviour) or S3 could never be reached in the first place.
  if (!isHigh) {
    graduationRecordLowConfidenceEscalated();
  }
  startEscalation(action, confidence, reason);
}

void safetyHandleResponse(const char *id, const char *answer) {
  if (!currentProposal.pending) return;
  if (strcmp(id, currentProposal.id) != 0) return;   // stale/unknown id - ignore

  bool approved = strcmp(answer, "APPROVE") == 0;
  currentProposal.pending = false;

  safetyLog("RESPONSE", String(currentProposal.id) + ": " + (approved ? "APPROVE" : "DECLINE"));

  if (approved) {
    bool turnOn = strcmp(currentProposal.action, "LIGHT_ON") == 0;
    setRelay(turnOn);
    safetyLog("ACTION", String("Approved: ") + currentProposal.action);
  }

  bool graduationChanged = graduationRecordProposalResponse(approved);
  if (graduationChanged) {
    safetyLog(graduationLastChangeWasDemotion() ? "DEMOTION" : "PROMOTION", graduationLastChangeReason());
  }
  publishStatus();
}

void safetyTick() {
  // Escalation timeout: mechanism 7. Hold state, never guess.
  if (currentProposal.pending &&
      (millis() - currentProposal.createdAtMs) >= PROPOSAL_TIMEOUT_MS) {
    currentProposal.pending = false;
    safetyLog("ESCALATION", String(currentProposal.id) + ": expired, no response");
  }

  // Resolve the 60-second override-detection window for the last
  // autonomous action, if nobody reversed it in time.
  if (awaitingOverrideWindow && millis() > pendingOverrideDeadlineMs) {
    awaitingOverrideWindow = false;
    bool graduationChanged = graduationRecordAutonomousAction(false);
    if (graduationChanged) {
      safetyLog("DEMOTION", graduationLastChangeReason());
      publishStatus();
    }
  }

  // Sensor faults demote immediately, regardless of mode.
  if (decisionEngineFaultDetected()) {
    static bool alreadyLogged = false;
    if (!alreadyLogged) {
      safetyLog("FAULT", decisionEngineFaultReason());
      bool graduationChanged = graduationRecordSensorFault();
      if (graduationChanged) {
        safetyLog("DEMOTION", graduationLastChangeReason());
      }
      publishStatus();
      alreadyLogged = true;
    }
  }

  if (graduationTick()) {
    safetyLog("PROMOTION", graduationLastChangeReason());
    publishStatus();
  }
}

const Proposal *safetyCurrentProposal() {
  return currentProposal.pending ? &currentProposal : NULL;
}
