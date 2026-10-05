// wifi_manager.h
//
// Owns which Wi-Fi network the ESP32 uses and how it scans for and switches
// to another one. Credentials start as the factory defaults in config.h.
// After a switch is confirmed (the broker answers on the new network), the
// new SSID and password are kept in NVS so they survive a reboot.
//
// A switch is only accepted in MANUAL mode. It stays on probation until the
// broker is reached; if that doesn't happen within WIFI_PROBATION_MS, the
// previous network is restored automatically. A wrong password, or a
// network the laptop isn't on, therefore can't strand the board.
//
// No MQTT in this file. mqtt_client.cpp owns the broker connection and
// publishes the results held here.

#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include <Arduino.h>

#define WIFI_SSID_MAX_LEN     32
#define WIFI_PASS_MAX_LEN     64
#define WIFI_SCAN_MAX_RESULTS 12

struct WifiScanEntry {
  char ssid[WIFI_SSID_MAX_LEN + 1];
  int rssi;
  bool secure;
};

// Loads saved credentials from NVS, or the config.h defaults if none saved.
// Call once from setup(), before the first WiFi.begin().
void wifiManagerInit();

const char *wifiActiveSsid();
const char *wifiActivePassword();

// True if no network is saved and config.h has none either, so the setup
// page must run before anything else can connect.
bool wifiNeedsSetup();

// Saves a network from the setup page to NVS and makes it active.
void wifiSaveCredentials(const char *ssid, const char *password);

// Erases the saved network, so the next boot starts the setup page.
void wifiForgetCredentials();

// Scans visible networks, strongest first, one entry per SSID. Returns the
// number of entries written to out[]. Blocking, a few seconds.
int wifiScan(WifiScanEntry *out, int maxCount);

// Starts a switch to the given network. Returns false if the request is
// refused (not in MANUAL mode, a switch already in progress, or invalid
// input) and sets the switch state to REJECTED. On success the caller
// must drop its MQTT session, because the old network connection is gone.
bool wifiBeginSwitch(const char *ssid, const char *password);

// Call every loop(). Reverts to the previous network if a switch has been
// on probation longer than WIFI_PROBATION_MS. Returns true if it reverted,
// so the caller can drop its MQTT session.
bool wifiTickProbation();

// Call once the broker is reached on the active network. Ends probation and
// saves the active credentials to NVS.
void wifiConfirmActive();

// Switch state for home/wifi/status: "NONE", "CONNECTING", "CONNECTED",
// "REVERTED" or "REJECTED", and a short human-readable reason.
const char *wifiSwitchState();
const char *wifiSwitchReason();

#endif // WIFI_MANAGER_H
