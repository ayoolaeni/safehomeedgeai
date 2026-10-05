// mqtt_client.cpp
//
// See mqtt_client.h for the public interface and AGENT_BUILD_SPEC.md
// section 3 for the exact topic names and payload formats. This file owns
// WiFiClient/PubSubClient and does nothing except translate between MQTT
// messages and calls into safety.h. It never decides anything itself.

#include "mqtt_client.h"
#include "graduation.h"
#include "config.h"
#include "wifi_manager.h"
#include "broker_settings.h"
#include <WiFi.h>
#include <ESPmDNS.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

static WiFiClient espClient;
static PubSubClient mqtt(espClient);

static unsigned long lastWifiRetryMs = 0;
static unsigned long lastMqttRetryMs = 0;
#define RETRY_INTERVAL_MS 5000UL

// ---------------------------------------------------------------------
// Incoming message handling
// ---------------------------------------------------------------------

static void handleResponseMessage(const char *jsonPayload) {
  StaticJsonDocument<192> doc;
  DeserializationError err = deserializeJson(doc, jsonPayload);
  if (err) {
    Serial.printf("mqtt_client: malformed home/agent/response payload, ignoring (%s)\n", err.c_str());
    return;
  }
  const char *id = doc["id"] | "";
  const char *answer = doc["answer"] | "";
  if (strlen(id) == 0 || strlen(answer) == 0) {
    Serial.println("mqtt_client: home/agent/response missing id/answer, ignoring");
    return;
  }
  safetyHandleResponse(id, answer);
}

// Retained, so an app that connects later still sees the last switch result.
static void publishWifiStatus() {
  StaticJsonDocument<256> doc;
  doc["state"] = wifiSwitchState();
  doc["reason"] = wifiSwitchReason();
  doc["ssid"] = wifiActiveSsid();
  doc["ip"] = WiFi.localIP().toString();
  char buf[256];
  serializeJson(doc, buf, sizeof(buf));
  mqtt.publish("home/wifi/status", buf, true /* retained */);
}

// Not retained: a scan is a one-off answer to a request from the app.
static void publishWifiScan() {
  WifiScanEntry list[WIFI_SCAN_MAX_RESULTS];
  int n = wifiScan(list, WIFI_SCAN_MAX_RESULTS);

  StaticJsonDocument<1024> doc;
  JsonArray networks = doc.createNestedArray("networks");
  for (int i = 0; i < n; i++) {
    JsonObject net = networks.createNestedObject();
    net["ssid"] = list[i].ssid;
    net["rssi"] = list[i].rssi;
    net["secure"] = list[i].secure;
  }
  char buf[1024];
  serializeJson(doc, buf, sizeof(buf));
  mqtt.publish("home/wifi/scans", buf, false);
  Serial.printf("mqtt_client: published %d Wi-Fi networks\n", n);
}

// Payload on home/wifi/set: {"ssid":"...","password":"..."}
static void handleWifiSet(const char *jsonPayload) {
  StaticJsonDocument<256> doc;
  DeserializationError err = deserializeJson(doc, jsonPayload);
  if (err) {
    Serial.printf("mqtt_client: malformed home/wifi/set payload, ignoring (%s)\n", err.c_str());
    return;
  }
  const char *ssid = doc["ssid"] | "";
  const char *password = doc["password"] | "";

  // The password is never logged or published. wifi_manager reports the
  // outcome through home/wifi/status.
  if (wifiBeginSwitch(ssid, password)) {
    // The old network's broker session is about to go. The result is
    // published by connectMqttOnce() once the broker answers again.
    mqtt.disconnect();
  } else {
    publishWifiStatus();   // refused: tell the app why straight away
  }
}

static void mqttCallback(char *topic, byte *payload, unsigned int length) {
  // Copy the payload into a null-terminated buffer - PubSubClient hands us
  // a raw, non-terminated byte buffer.
  static char buf[256];
  if (length >= sizeof(buf)) length = sizeof(buf) - 1;
  memcpy(buf, payload, length);
  buf[length] = '\0';

  String t(topic);

  if (t == "home/light/cmd") {
    safetyHandleManualCommand(buf);
  } else if (t == "home/mode/set") {
    if (strcmp(buf, "MANUAL") == 0) {
      safetySetMode(MODE_MANUAL);
    } else if (strcmp(buf, "ASSISTED") == 0) {
      safetySetMode(MODE_ASSISTED);
    } else if (strcmp(buf, "AUTONOMOUS") == 0) {
      safetySetMode(MODE_AUTONOMOUS);
    } else {
      Serial.printf("mqtt_client: unknown mode '%s' on home/mode/set, ignoring\n", buf);
    }
  } else if (t == "home/agent/response") {
    handleResponseMessage(buf);
  } else if (t == "home/wifi/scan/request") {
    publishWifiScan();
  } else if (t == "home/wifi/set") {
    handleWifiSet(buf);
  }
}

// ---------------------------------------------------------------------
// Connection management
// ---------------------------------------------------------------------

static void connectWifiBlocking() {
  Serial.printf("Connecting to Wi-Fi SSID '%s'", wifiActiveSsid());
  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiActiveSsid(), wifiActivePassword());
  unsigned long startMs = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - startMs > WIFI_BOOT_TIMEOUT_MS) {
      Serial.println();
      Serial.println("Could not join Wi-Fi in 3 minutes - forgetting it and opening setup.");
      wifiForgetCredentials();
      ESP.restart();   // the next boot finds nothing saved and shows the setup page
    }
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("Wi-Fi connected, IP address: ");
  Serial.println(WiFi.localIP());
}

static void replayRecentLog() {
  int n = safetyRecentLogCount();
  for (int i = 0; i < n; i++) {
    const LogEntry *e = safetyRecentLog(i);
    if (e) publishLog(*e);
  }
}

// The broker host can be an IP address (used as-is) or a laptop name, which
// is looked up with mDNS. Looked up fresh on every connection attempt, so
// the broker is found again if the laptop's IP has changed.
static bool resolveBrokerIp(IPAddress &out) {
  const char *host = brokerHost();

  IPAddress direct;
  if (direct.fromString(host)) {
    out = direct;
    return true;
  }

  // Accept "LAPTOP.local" as well as "LAPTOP": the lookup wants the bare name.
  String name = host;
  if (name.endsWith(".local")) name.remove(name.length() - 6);

  IPAddress ip = MDNS.queryHost(name, 3000);
  if (ip != IPAddress(0, 0, 0, 0)) {
    Serial.printf("mqtt_client: resolved %s -> %s via mDNS\n", host, ip.toString().c_str());
    out = ip;
    return true;
  }
  Serial.printf("mqtt_client: could not find '%s' on the network, will retry\n", host);
  return false;
}

static bool connectMqttOnce() {
  // The network may have just changed, so restart mDNS on the current
  // interface before resolving the broker.
  MDNS.end();
  if (!MDNS.begin("safehome-esp32")) {
    Serial.println("mqtt_client: mDNS restart failed - broker lookups will not work");
  }

  IPAddress brokerIp;
  if (!resolveBrokerIp(brokerIp)) return false;
  mqtt.setServer(brokerIp, MQTT_PORT);

  String clientId = String(MQTT_CLIENT_ID) + "-" + String((unsigned long)millis());
  Serial.printf("Connecting to MQTT broker %s:%d as %s ... ", brokerIp.toString().c_str(), MQTT_PORT, clientId.c_str());

  bool connected = strlen(brokerUser()) > 0
                       ? mqtt.connect(clientId.c_str(), brokerUser(), brokerPass())
                       : mqtt.connect(clientId.c_str());
  if (connected) {
    Serial.println("connected.");
    mqtt.subscribe("home/light/cmd");
    mqtt.subscribe("home/mode/set");
    mqtt.subscribe("home/agent/response");
    mqtt.subscribe("home/wifi/scan/request");
    mqtt.subscribe("home/wifi/set");

    // Reaching the broker on a new network is what confirms a switch.
    wifiConfirmActive();
    publishWifiStatus();

    // Publish current state immediately so a freshly (re)connected app
    // doesn't have to wait for the next sensor poll or decision.
    publishLightState(safetyLampIsOn());
    publishModeState(safetyGetMode());
    publishStatus();
    replayRecentLog();
    return true;
  }
  Serial.printf("failed, rc=%d\n", mqtt.state());
  return false;
}

void mqttClientInit() {
  wifiManagerInit();   // saved network from NVS, or the config.h default
  brokerSettingsInit();
  connectWifiBlocking();

  // Required before MDNS.queryHost() will work, even though this ESP32
  // doesn't need to advertise its own name for anything.
  if (!MDNS.begin("safehome-esp32")) {
    Serial.println("mqtt_client: mDNS init failed - broker hostname lookups will use the fallback IP only");
  }

  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(1024);  // large enough for the Wi-Fi scan list
  connectMqttOnce();         // resolves the broker's address itself
}

void mqttClientLoop() {
  unsigned long now = millis();

  // A switch that never reached the broker is undone here. The old
  // session is already gone, so there is nothing to disconnect cleanly.
  if (wifiTickProbation()) {
    mqtt.disconnect();
  }

  if (WiFi.status() != WL_CONNECTED) {
    if (now - lastWifiRetryMs >= RETRY_INTERVAL_MS) {
      lastWifiRetryMs = now;
      Serial.println("Wi-Fi dropped, retrying...");
      WiFi.disconnect();
      WiFi.begin(wifiActiveSsid(), wifiActivePassword());
    }
    return;   // nothing else to do until Wi-Fi is back
  }

  if (!mqtt.connected()) {
    if (now - lastMqttRetryMs >= RETRY_INTERVAL_MS) {
      lastMqttRetryMs = now;
      connectMqttOnce();
    }
    return;
  }

  mqtt.loop();
}

bool mqttClientIsConnected() {
  return WiFi.status() == WL_CONNECTED && mqtt.connected();
}

// ---------------------------------------------------------------------
// Publishers
// ---------------------------------------------------------------------

void publishLightState(bool on) {
  mqtt.publish("home/light/state", on ? "ON" : "OFF", true /* retained */);
}

void publishMotion(bool detected) {
  mqtt.publish("home/sensors/motion", detected ? "TRUE" : "FALSE", false);
}

void publishLightSensor(int raw, bool dark) {
  StaticJsonDocument<96> doc;
  doc["raw"] = raw;
  doc["level"] = dark ? "DARK" : "BRIGHT";
  char buf[96];
  serializeJson(doc, buf, sizeof(buf));
  mqtt.publish("home/sensors/light", buf, false);
}

void publishModeState(OperatingMode mode) {
  mqtt.publish("home/mode/state", safetyModeName(mode), true /* retained */);
}

void publishProposal(const Proposal &p) {
  StaticJsonDocument<256> doc;
  doc["id"] = p.id;
  doc["action"] = p.action;
  doc["confidence"] = p.confidence;
  doc["reason"] = p.reason;
  doc["ts"] = p.ts;
  char buf[256];
  serializeJson(doc, buf, sizeof(buf));
  mqtt.publish("home/agent/proposal", buf, false);
}

void publishStatus() {
  StaticJsonDocument<320> doc;
  GraduationState s = graduationCurrentState();
  doc["state"] = String("S") + String((int)s);
  doc["stateName"] = graduationStateName(s);
  doc["proposals"] = graduationTotalProposals();
  doc["approvals"] = graduationTotalApprovals();
  doc["approvalRate"] = round(graduationOverallApprovalRatePct() * 10) / 10.0;
  doc["lastChange"] = graduationLastChangeReason();
  doc["ts"] = millis() / 1000UL;
  char buf[320];
  serializeJson(doc, buf, sizeof(buf));
  mqtt.publish("home/agent/status", buf, true /* retained */);
}

void publishLog(const LogEntry &entry) {
  StaticJsonDocument<256> doc;
  doc["seq"] = entry.seq;
  doc["ts"] = entry.ts;
  doc["type"] = entry.type;
  doc["detail"] = entry.detail;
  char buf[256];
  serializeJson(doc, buf, sizeof(buf));
  mqtt.publish("home/agent/log", buf, false);
}
