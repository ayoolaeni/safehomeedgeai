// broker_settings.h
//
// Where the MQTT broker (Mosquitto on the client's laptop) is, and the
// login for it. These are typed in on the setup page and kept in flash, so
// the same firmware works on any network and any laptop without editing
// code. An empty host means setup has not been done yet.

#ifndef BROKER_SETTINGS_H
#define BROKER_SETTINGS_H

#include <Arduino.h>

#define BROKER_HOST_MAX_LEN 64
#define BROKER_USER_MAX_LEN 64
#define BROKER_PASS_MAX_LEN 64

// Loads the saved settings from NVS. Call once before connecting.
void brokerSettingsInit();

// Laptop name (e.g. "LAPTOP-SONIA" or "LAPTOP-SONIA.local") or IP address.
const char *brokerHost();
const char *brokerUser();   // empty if the broker has no login
const char *brokerPass();

// Saves all three to NVS and makes them active.
void brokerSettingsSave(const char *host, const char *user, const char *pass);

#endif // BROKER_SETTINGS_H
