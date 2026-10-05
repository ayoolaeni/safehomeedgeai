// mqtt_client.h
//
// Owns the Wi-Fi and MQTT connections and every publish/subscribe on the
// topics defined in AGENT_BUILD_SPEC.md section 3. This is the only file
// that talks to PubSubClient directly. Incoming messages are parsed here
// and handed straight to safety.h - this file makes no decisions itself.

#ifndef MQTT_CLIENT_H
#define MQTT_CLIENT_H

#include <Arduino.h>
#include "decision_engine.h"
#include "safety.h"

// Connects Wi-Fi (blocking, with retry) and the MQTT client, subscribes to
// every app-published topic. Call once from setup(), after
// safetyFailSafeInit().
void mqttClientInit();

// Call once per loop(). Services the MQTT client, reconnects Wi-Fi/MQTT if
// dropped (non-blocking after the first connection), with the connection
// tile behaviour mirrored by home/light/state etc. being retained so a
// reconnecting phone sees current state immediately.
void mqttClientLoop();

bool mqttClientIsConnected();

// --- Publishers, one per outbound topic in the MQTT contract -------------

void publishLightState(bool on);                                  // home/light/state (retained)
void publishMotion(bool detected);                                // home/sensors/motion
void publishLightSensor(int raw, bool dark);                      // home/sensors/light
void publishModeState(OperatingMode mode);                        // home/mode/state (retained)
void publishProposal(const Proposal &p);                          // home/agent/proposal
void publishStatus();                                             // home/agent/status (retained)
void publishLog(const LogEntry &entry);                           // home/agent/log

#endif // MQTT_CLIENT_H
