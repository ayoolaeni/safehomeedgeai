// broker_settings.cpp
//
// See broker_settings.h. The password is never printed to Serial.

#include "broker_settings.h"
#include <Preferences.h>

static Preferences prefs;

static char host[BROKER_HOST_MAX_LEN + 1] = "";
static char user[BROKER_USER_MAX_LEN + 1] = "";
static char pass[BROKER_PASS_MAX_LEN + 1] = "";

void brokerSettingsInit() {
  prefs.begin("broker", true);   // read-only; an empty namespace gives empty strings
  String h = prefs.getString("host", "");
  String u = prefs.getString("user", "");
  String p = prefs.getString("pass", "");
  prefs.end();

  snprintf(host, sizeof(host), "%s", h.c_str());
  snprintf(user, sizeof(user), "%s", u.c_str());
  snprintf(pass, sizeof(pass), "%s", p.c_str());
  Serial.printf("broker_settings: broker '%s', login %s\n",
                host, strlen(user) > 0 ? user : "(none)");
}

const char *brokerHost() { return host; }
const char *brokerUser() { return user; }
const char *brokerPass() { return pass; }

void brokerSettingsSave(const char *newHost, const char *newUser, const char *newPass) {
  snprintf(host, sizeof(host), "%s", newHost);
  snprintf(user, sizeof(user), "%s", newUser);
  snprintf(pass, sizeof(pass), "%s", newPass);

  prefs.begin("broker", false);
  prefs.putString("host", host);
  prefs.putString("user", user);
  prefs.putString("pass", pass);
  prefs.end();
  Serial.printf("broker_settings: saved broker '%s'\n", host);
}
