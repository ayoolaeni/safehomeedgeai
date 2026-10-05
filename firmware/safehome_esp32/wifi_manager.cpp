// wifi_manager.cpp
//
// See wifi_manager.h for the behaviour. The password is never printed to
// Serial or published anywhere; only the SSID is.

#include "wifi_manager.h"
#include "config.h"
#include "safety.h"
#include <WiFi.h>
#include <Preferences.h>

static Preferences prefs;

static char activeSsid[WIFI_SSID_MAX_LEN + 1];
static char activePass[WIFI_PASS_MAX_LEN + 1];

// The network we are trying to reach, and the one to go back to if it fails.
static char attemptSsid[WIFI_SSID_MAX_LEN + 1];
static char previousSsid[WIFI_SSID_MAX_LEN + 1];
static char previousPass[WIFI_PASS_MAX_LEN + 1];

static bool probation = false;
static unsigned long probationStartMs = 0;

static const char *switchState = "NONE";
static char switchReason[96] = "";

static void setSwitch(const char *state, const char *reason) {
  switchState = state;
  snprintf(switchReason, sizeof(switchReason), "%s", reason);
  Serial.printf("wifi_manager: %s - %s\n", state, reason);
}

void wifiManagerInit() {
  // Read-only open: a namespace that has never been written just returns
  // the defaults below.
  prefs.begin("wifi", true);
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  prefs.end();

  if (ssid.length() > 0) {
    snprintf(activeSsid, sizeof(activeSsid), "%s", ssid.c_str());
    snprintf(activePass, sizeof(activePass), "%s", pass.c_str());
    Serial.printf("wifi_manager: using saved network '%s'\n", activeSsid);
  } else {
    snprintf(activeSsid, sizeof(activeSsid), "%s", WIFI_SSID);
    snprintf(activePass, sizeof(activePass), "%s", WIFI_PASSWORD);
    Serial.printf("wifi_manager: using config.h default network '%s'\n", activeSsid);
  }
}

const char *wifiActiveSsid() { return activeSsid; }
const char *wifiActivePassword() { return activePass; }

bool wifiNeedsSetup() { return strlen(activeSsid) == 0; }

void wifiSaveCredentials(const char *ssid, const char *password) {
  snprintf(activeSsid, sizeof(activeSsid), "%s", ssid);
  snprintf(activePass, sizeof(activePass), "%s", password);

  prefs.begin("wifi", false);
  prefs.putString("ssid", activeSsid);
  prefs.putString("pass", activePass);
  prefs.end();
  Serial.printf("wifi_manager: saved network '%s'\n", activeSsid);
}

void wifiForgetCredentials() {
  prefs.begin("wifi", false);
  prefs.clear();
  prefs.end();
  Serial.println("wifi_manager: saved network forgotten");
}

const char *wifiSwitchState() { return switchState; }
const char *wifiSwitchReason() { return switchReason; }

int wifiScan(WifiScanEntry *out, int maxCount) {
  int found = WiFi.scanNetworks();
  int count = 0;

  // Repeatedly take the strongest unused network whose SSID isn't already
  // listed. Mesh and extender setups broadcast one SSID from several access
  // points; the app only needs one entry for each.
  bool used[64] = {false};
  while (count < maxCount && count < found) {
    int best = -1;
    for (int i = 0; i < found && i < 64; i++) {
      if (used[i]) continue;
      String s = WiFi.SSID(i);
      if (s.length() == 0 || s.length() > WIFI_SSID_MAX_LEN) {
        used[i] = true;
        continue;
      }
      if (best < 0 || WiFi.RSSI(i) > WiFi.RSSI(best)) best = i;
    }
    if (best < 0) break;

    used[best] = true;
    String name = WiFi.SSID(best);
    bool duplicate = false;
    for (int k = 0; k < count; k++) {
      if (strcmp(out[k].ssid, name.c_str()) == 0) duplicate = true;
    }
    if (duplicate) continue;

    snprintf(out[count].ssid, sizeof(out[count].ssid), "%s", name.c_str());
    out[count].rssi = WiFi.RSSI(best);
    out[count].secure = WiFi.encryptionType(best) != WIFI_AUTH_OPEN;
    count++;
  }

  WiFi.scanDelete();
  return count;
}

bool wifiBeginSwitch(const char *ssid, const char *password) {
  if (safetyGetMode() != MODE_MANUAL) {
    setSwitch("REJECTED", "network can only be changed in MANUAL mode");
    return false;
  }
  if (probation) {
    setSwitch("REJECTED", "a network switch is already in progress");
    return false;
  }
  size_t ssidLen = strlen(ssid);
  if (ssidLen == 0 || ssidLen > WIFI_SSID_MAX_LEN) {
    setSwitch("REJECTED", "SSID must be 1-32 characters");
    return false;
  }
  if (strlen(password) > WIFI_PASS_MAX_LEN) {
    setSwitch("REJECTED", "password must be at most 63 characters");
    return false;
  }

  // Remember where we came from so a failed attempt can be undone.
  snprintf(previousSsid, sizeof(previousSsid), "%s", activeSsid);
  snprintf(previousPass, sizeof(previousPass), "%s", activePass);
  snprintf(attemptSsid, sizeof(attemptSsid), "%s", ssid);
  snprintf(activeSsid, sizeof(activeSsid), "%s", ssid);
  snprintf(activePass, sizeof(activePass), "%s", password);

  probation = true;
  probationStartMs = millis();

  char reason[96];
  snprintf(reason, sizeof(reason), "joining '%s'", attemptSsid);
  setSwitch("CONNECTING", reason);

  WiFi.disconnect();
  WiFi.begin(activeSsid, activePass);
  return true;
}

bool wifiTickProbation() {
  if (!probation) return false;
  if (millis() - probationStartMs < WIFI_PROBATION_MS) return false;

  // Time is up without the broker answering on the new network. Go back.
  probation = false;
  snprintf(activeSsid, sizeof(activeSsid), "%s", previousSsid);
  snprintf(activePass, sizeof(activePass), "%s", previousPass);

  char reason[96];
  snprintf(reason, sizeof(reason), "could not reach broker on '%s', restored '%s'",
           attemptSsid, activeSsid);
  setSwitch("REVERTED", reason);

  WiFi.disconnect();
  WiFi.begin(activeSsid, activePass);
  return true;
}

void wifiConfirmActive() {
  if (!probation) return;
  probation = false;

  prefs.begin("wifi", false);
  prefs.putString("ssid", activeSsid);
  prefs.putString("pass", activePass);
  prefs.end();

  char reason[96];
  snprintf(reason, sizeof(reason), "connected to '%s'", activeSsid);
  setSwitch("CONNECTED", reason);
}
