// setup_portal.cpp
//
// See setup_portal.h. Pages are kept small on purpose: the ESP32 has about
// 300 KB of RAM and the scan list is capped at WIFI_SCAN_MAX_RESULTS.

#include "setup_portal.h"
#include "config.h"
#include "wifi_manager.h"
#include "broker_settings.h"
#include <WiFi.h>
#include <WebServer.h>

static WebServer server(80);

// Stops a network name like <b> from being read as HTML.
static String htmlEscape(const String &text) {
  String out;
  for (size_t i = 0; i < text.length(); i++) {
    char c = text[i];
    switch (c) {
      case '&':  out += "&amp;";  break;
      case '<':  out += "&lt;";   break;
      case '>':  out += "&gt;";   break;
      case '"':  out += "&quot;"; break;
      case '\'': out += "&#39;";  break;
      default:   out += c;
    }
  }
  return out;
}

static void sendPage(const String &body) {
  String html = F("<!doctype html><html><head><meta charset='utf-8'>"
                  "<meta name='viewport' content='width=device-width,initial-scale=1'>"
                  "<title>SafeHome Setup</title>"
                  "<style>"
                  "body{font-family:Arial,sans-serif;margin:0;padding:16px;background:#f4f6f8;color:#222}"
                  "h1{font-size:22px}"
                  "form{background:#fff;padding:16px;border-radius:8px;max-width:420px}"
                  "label{display:block;margin:12px 0 4px;font-weight:bold}"
                  "input,select{width:100%;box-sizing:border-box;padding:10px;font-size:16px;border:1px solid #bbb;border-radius:6px}"
                  "button{margin-top:18px;width:100%;padding:14px;font-size:17px;background:#1565c0;color:#fff;border:0;border-radius:6px}"
                  "small{color:#555}"
                  "</style></head><body>");
  html += body;
  html += F("</body></html>");
  server.send(200, "text/html", html);
}

static void handleRoot() {
  WifiScanEntry list[WIFI_SCAN_MAX_RESULTS];
  int n = wifiScan(list, WIFI_SCAN_MAX_RESULTS);

  String options;
  for (int i = 0; i < n; i++) {
    String name = htmlEscape(String(list[i].ssid));
    options += "<option value=\"" + name + "\">" + name +
               (list[i].secure ? "" : " (open)") + "</option>";
  }
  if (n == 0) {
    options = F("<option value=''>No networks found - tap Scan again</option>");
  }

  String body = F("<h1>SafeHome setup</h1>"
                  "<form method='POST' action='/save'>"
                  "<label>Your home Wi-Fi name</label>"
                  "<select name='ssid'>");
  body += options;
  body += F("</select>"
            "<label>Wi-Fi password</label>"
            "<input type='password' name='password' placeholder='Leave empty for an open network'>"
            "<label>Laptop name or IP address</label>"
            "<input name='host' required placeholder='e.g. LAPTOP-SONIA or 192.168.1.20'>"
            "<small>The laptop that runs the broker (Mosquitto).</small>"
            "<label>Broker username</label>"
            "<input name='user' placeholder='Leave empty if the broker has no login'>"
            "<label>Broker password</label>"
            "<input type='password' name='bpass'>"
            "<button type='submit'>Save and connect</button>"
            "</form>"
            "<p><a href='/'>Scan again</a></p>");
  sendPage(body);
}

static void sendError(const String &message) {
  sendPage("<h1>Please check the form</h1><p>" + htmlEscape(message) +
           "</p><p><a href='/'>Go back</a></p>");
}

static void handleSave() {
  String ssid = server.arg("ssid");
  String password = server.arg("password");
  String host = server.arg("host");
  String user = server.arg("user");
  String bpass = server.arg("bpass");
  ssid.trim();
  host.trim();
  user.trim();

  if (ssid.length() == 0 || ssid.length() > WIFI_SSID_MAX_LEN) {
    return sendError("Choose a Wi-Fi network from the list.");
  }
  if (password.length() > WIFI_PASS_MAX_LEN) {
    return sendError("The Wi-Fi password is too long.");
  }
  if (host.length() == 0 || host.length() > BROKER_HOST_MAX_LEN) {
    return sendError("Enter the laptop name or IP address.");
  }
  if (user.length() > BROKER_USER_MAX_LEN || bpass.length() > BROKER_PASS_MAX_LEN) {
    return sendError("The broker username or password is too long.");
  }

  wifiSaveCredentials(ssid.c_str(), password.c_str());
  brokerSettingsSave(host.c_str(), user.c_str(), bpass.c_str());

  sendPage(F("<h1>Saved</h1>"
             "<p>The board is restarting and will join your home Wi-Fi in about 20 seconds.</p>"
             "<p>Now connect your phone back to your home Wi-Fi and open the SafeHome app.</p>"));
  server.client().flush();
  delay(1500);   // give the page time to reach the phone before the restart
  ESP.restart();
}

void setupPortalRun() {
  Serial.println();
  Serial.println("=== SETUP MODE ===");
  Serial.printf("Connect to Wi-Fi '%s' (password '%s')\n", SETUP_AP_SSID, SETUP_AP_PASSWORD);
  Serial.println("then open http://192.168.4.1 in a browser.");

  WiFi.mode(WIFI_AP_STA);   // AP so the phone can connect; STA so the page can scan
  WiFi.softAP(SETUP_AP_SSID, SETUP_AP_PASSWORD);

  server.on("/", HTTP_GET, handleRoot);
  server.on("/save", HTTP_POST, handleSave);
  server.onNotFound(handleRoot);   // any other address shows the setup page
  server.begin();

  while (true) {
    server.handleClient();
    delay(5);
  }
}
