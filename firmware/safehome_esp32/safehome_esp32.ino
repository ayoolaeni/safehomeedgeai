// safehome_esp32.ino
//
// SafeHome Edge AI - main firmware sketch.
//
// This file just wires the other modules together in the right order. All
// the actual behaviour lives in:
//   config.h            - every tunable constant (pins, thresholds, Wi-Fi)
//   decision_engine.*    - reads sensors, applies the two decision rules
//   safety.*             - the seven safety mechanisms, relay control, log
//   graduation.*          - the S1-S5 autonomy graduation state machine
//   mqtt_client.*         - Wi-Fi + MQTT, translates messages <-> safety.h
//
// Required libraries (Arduino Library Manager): PubSubClient (Nick
// O'Leary), ArduinoJson (v6, Benoit Blanchon). WiFi.h and Preferences.h are
// built into the ESP32 board package.
//
// Board: "ESP32 Dev Module". Serial Monitor: 115200 baud.

#include "config.h"
#include "decision_engine.h"
#include "safety.h"
#include "graduation.h"
#include "mqtt_client.h"
#include "wifi_manager.h"
#include "setup_portal.h"

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println("=== SafeHome Edge AI ===");

  // Fail-safe defaults MUST run first: relay forced OFF, mode forced
  // MANUAL, before Wi-Fi or anything else touches the system.
  safetyFailSafeInit();

  // Graduation state (S1-S5) is persisted across reboots and is NOT reset
  // by safetyFailSafeInit() - only the operating mode is.
  graduationInit();
  Serial.printf("Graduation state loaded: %s\n", graduationStateName(graduationCurrentState()));

  decisionEngineInit();

  // First boot (or after 'S' in the Serial Monitor): no Wi-Fi saved yet.
  // The setup page takes over, keeps the relay OFF, and restarts the board
  // once the home network and broker details are saved.
  wifiManagerInit();
  if (wifiNeedsSetup()) {
    setupPortalRun();   // never returns
  }

  // Wi-Fi + MQTT connect. This is deliberately the LAST thing set up, so
  // that if it never succeeds, the relay is still safely OFF and the
  // board is still doing useful local work (sensing) rather than being
  // stuck mid-boot with unknown outputs.
  mqttClientInit();

  Serial.println("Setup complete. Type 'H' + Enter in the Serial Monitor");
  Serial.println("once you have physically completed the HZ1-HZ6 hazard");
  Serial.println("tests in docs/TESTING.md - this is required before the");
  Serial.println("graduation engine will ever promote to S5 (AUTONOMOUS).");
}

// Tracks what has already been published so sensor topics are only sent
// when something actually changes, instead of flooding the broker every
// SENSOR_POLL_MS.
static bool lastPublishedMotion = false;
static bool lastPublishedDark = false;
static int lastPublishedRaw = -1;
static bool firstPublishDone = false;

static void publishSensorChanges() {
  bool motionNow = decisionEngineMotionState();
  bool darkNow = decisionEngineIsDark();
  int rawNow = decisionEngineLdrRaw();

  if (!firstPublishDone || motionNow != lastPublishedMotion) {
    publishMotion(motionNow);
    lastPublishedMotion = motionNow;
  }

  // Publish the light sensor on a DARK/BRIGHT flip, or if the raw value
  // has drifted by more than 20 counts, so the app's raw reading isn't
  // stale for long without spamming the broker on every tiny fluctuation.
  if (!firstPublishDone || darkNow != lastPublishedDark || abs(rawNow - lastPublishedRaw) > 20) {
    publishLightSensor(rawNow, darkNow);
    lastPublishedDark = darkNow;
    lastPublishedRaw = rawNow;
  }

  firstPublishDone = true;
}

static void handleSerialCommands() {
  if (!Serial.available()) return;
  char c = Serial.read();
  if (c == 'H' || c == 'h') {
    graduationMarkHazardSuitePassed();
    Serial.println(">>> Hazard suite marked PASSED. Canary period will complete the promotion to S5 once elapsed.");
  } else if (c == 'S' || c == 's') {
    // Forget the saved Wi-Fi and restart into the setup page.
    wifiForgetCredentials();
    Serial.println(">>> Restarting into setup mode...");
    delay(500);
    ESP.restart();
  }
}

void loop() {
  bool lampBefore = safetyLampIsOn();

  // Observe + decide + (maybe) escalate/act. Never touches the relay
  // directly - everything goes through safety.h.
  decisionEngineUpdate(lampBefore);

  // Timeouts, fault checks, graduation ticks.
  safetyTick();

  // Wi-Fi/MQTT connection maintenance and incoming message dispatch.
  mqttClientLoop();

  publishSensorChanges();
  handleSerialCommands();
}
