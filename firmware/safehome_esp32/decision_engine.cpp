// decision_engine.cpp
//
// See decision_engine.h for the public interface and
// AGENT_BUILD_SPEC.md section 4.3 for the rules this implements.

#include "decision_engine.h"
#include "safety.h"
#include "config.h"
#include <string.h>

static unsigned long lastPollMs = 0;
static unsigned long lastMotionMs = 0;         // last time debounced motion was TRUE
static unsigned long motionRisingEdgeMs = 0;   // when the raw PIR pin last went HIGH
static bool motionRawPrev = false;
static bool motionDebounced = false;

static int ldrRaw = 0;
static bool isDark = false;
static unsigned long lastSensorReadMs = 0;

#if LDR_USE_DIGITAL_OUTPUT
// When the LDR is read through its DO pin, remember when the dark/bright
// state last changed - a state that only just flipped is "on the boundary".
static unsigned long lastLdrChangeMs = 0;
static bool ldrStateKnown = false;
#endif

// Fault detection state
#if !LDR_USE_DIGITAL_OUTPUT
static int lastLdrRawForFault = -1;
static int identicalLdrReadCount = 0;
#endif
static unsigned long pirHighSinceMs = 0;
static bool faultDetected = false;
static char faultReason[96] = "";

void decisionEngineInit() {
  // Pull the PIR pin HIGH when nothing is connected. A working HC-SR501 drives
  // its output fully LOW or HIGH, so this only matters when the wire is
  // unplugged, and then the pin reads HIGH and the 10-minute stuck check
  // reports the sensor as disconnected.
  pinMode(PIN_PIR, INPUT_PULLUP);
#if LDR_POWER_FROM_GPIO
  // The LDR module's VCC is wired to this pin, so switch it on to power the
  // module. (Called after safetyFailSafeInit(), so the relay is already OFF.)
  pinMode(PIN_LDR_POWER, OUTPUT);
  digitalWrite(PIN_LDR_POWER, HIGH);
#endif
#if LDR_USE_DIGITAL_OUTPUT
  // GPIO34 is input-only with no internal pull resistor; the module's DO
  // output drives it fully (high or low), so a plain INPUT is correct.
  pinMode(PIN_LDR, INPUT);
#endif
  lastPollMs = 0;
}

// True if the light reading is safely away from the dark/bright boundary.
static bool ldrFarFromBoundary(unsigned long now) {
#if LDR_USE_DIGITAL_OUTPUT
  return (now - lastLdrChangeMs) >= LDR_DO_STABLE_MS;
#else
  return abs(ldrRaw - LDR_DARK_THRESHOLD) >= 150;
#endif
}

bool decisionEngineMotionState() { return motionDebounced; }
int decisionEngineLdrRaw() { return ldrRaw; }
bool decisionEngineIsDark() { return isDark; }
bool decisionEngineFaultDetected() { return faultDetected; }
const char *decisionEngineFaultReason() { return faultReason; }

static void checkSensorFaults() {
#if !LDR_USE_DIGITAL_OUTPUT
  // LDR stuck: identical raw value for LDR_STUCK_READ_COUNT reads in a row.
  // (Skipped in digital-output mode: a DO pin legitimately stays the same
  // for hours, so this check would raise false faults.)
  if (ldrRaw == lastLdrRawForFault) {
    identicalLdrReadCount++;
  } else {
    identicalLdrReadCount = 0;
    lastLdrRawForFault = ldrRaw;
  }
  if (identicalLdrReadCount >= LDR_STUCK_READ_COUNT && !faultDetected) {
    faultDetected = true;
    strncpy(faultReason, "LDR stuck (identical reading, likely disconnected)", sizeof(faultReason) - 1);
  }
#endif

  // PIR stuck: continuously HIGH for more than PIR_STUCK_MS.
  bool raw = digitalRead(PIN_PIR) == HIGH;
  if (raw) {
    if (pirHighSinceMs == 0) pirHighSinceMs = millis();
    if ((millis() - pirHighSinceMs) > PIR_STUCK_MS && !faultDetected) {
      faultDetected = true;
      strncpy(faultReason, "PIR stuck HIGH for over 10 minutes (likely disconnected)", sizeof(faultReason) - 1);
    }
  } else {
    pirHighSinceMs = 0;
    // The sensor is responding again (it reads LOW). Clear the fault so the
    // lamp can resume proposing. The demotion itself is kept by the
    // graduation engine, so the lamp still has to earn its level back.
    if (faultDetected) {
      faultDetected = false;
      faultReason[0] = '\0';
    }
  }
}

void decisionEngineUpdate(bool lampIsOn) {
  unsigned long now = millis();
  if (now - lastPollMs < SENSOR_POLL_MS) return;
  lastPollMs = now;

  // --- Observe: PIR with dwell filter ---
  bool motionRaw = digitalRead(PIN_PIR) == HIGH;
  if (motionRaw && !motionRawPrev) {
    motionRisingEdgeMs = now;   // pin just went HIGH, start the dwell timer
  }
  if (motionRaw) {
    if ((now - motionRisingEdgeMs) >= MOTION_DWELL_MS) {
      motionDebounced = true;
      lastMotionMs = now;
    }
  } else {
    motionDebounced = false;
  }
  motionRawPrev = motionRaw;

  // --- Observe: LDR ---
#if LDR_USE_DIGITAL_OUTPUT
  bool darkNow = (digitalRead(PIN_LDR) == HIGH) == LDR_DO_HIGH_IS_DARK;
  if (!ldrStateKnown || darkNow != isDark) {
    lastLdrChangeMs = now;   // first reading, or the light just changed
    ldrStateKnown = true;
  }
  isDark = darkNow;
  ldrRaw = darkNow ? 4095 : 0;   // stand-in value so the app's "raw" field still makes sense
#else
  ldrRaw = analogRead(PIN_LDR);
  isDark = LDR_HIGHER_IS_BRIGHTER ? (ldrRaw < LDR_DARK_THRESHOLD)
                                   : (ldrRaw > LDR_DARK_THRESHOLD);
#endif
  lastSensorReadMs = now;

  checkSensorFaults();
  if (faultDetected) {
    // A demoted/faulted sensor must not keep proposing actions based on
    // readings it can no longer trust. graduation.cpp's demotion is
    // triggered from safety.cpp's tick, which checks this flag.
    return;
  }

  // --- Decide: two rules only ---
  if (!lampIsOn && isDark && motionDebounced) {
    // RULE 1: turn on.
    bool freshReading = (now - lastSensorReadMs) <= 2000UL;   // trivially true here, kept for clarity/logging
    bool farFromBoundary = ldrFarFromBoundary(now);
    bool confident = freshReading && farFromBoundary && !faultDetected;

    safetyHandleProposal("LIGHT_ON", confident ? "HIGH" : "LOW", "Dark and motion detected");
  } else if (lampIsOn && !motionDebounced &&
             (now - lastMotionMs) >= EFFECTIVE_ABSENCE_TIMEOUT_MS) {
    // RULE 2: turn off.
    bool freshReading = (now - lastSensorReadMs) <= 2000UL;
    bool farFromBoundary = ldrFarFromBoundary(now);
    bool confident = freshReading && farFromBoundary && !faultDetected;

    const char *reasonText = "No motion for 30 minutes";
#if FAST_TEST_MODE
    reasonText = "No motion for absence timeout (FAST_TEST_MODE)";
#endif
    safetyHandleProposal("LIGHT_OFF", confident ? "HIGH" : "LOW", reasonText);

    // Prevent re-proposing LIGHT_OFF every poll while still absent: treat
    // this proposal as "handled" by resetting the absence clock. If it
    // gets declined/expired, decision_engine will propose again after
    // another full absence timeout, which is the intended behaviour.
    lastMotionMs = now;
  }
}
