// config.h
//
// Every tunable value for the SafeHome Edge AI firmware lives in this one
// file. If you need to change Wi-Fi credentials, the broker address, a pin
// number, or a threshold, this is the only file you should have to touch.
//
// IMPORTANT: the pin numbers and graduation thresholds below are copied
// exactly from the dissertation (Figure 4.1 and Chapter 3). Do not change
// them unless the physical wiring or the written thresholds change too.

#ifndef CONFIG_H
#define CONFIG_H

// ---------------------------------------------------------------------
// Network
// ---------------------------------------------------------------------
// The Wi-Fi name and password are NOT stored here any more. On first boot
// (or after pressing 'S' in the Serial Monitor) the board starts a setup
// hotspot and asks for them on a web page, then saves them in its own flash
// memory. Leave these empty so no real password ends up in the public repo.
#define WIFI_SSID        ""
#define WIFI_PASSWORD    ""

// Once the app switches networks successfully, the chosen SSID and password
// are kept in NVS and override these values. A switch that cannot reach the
// broker within WIFI_PROBATION_MS reverts to the previous network.
#define WIFI_PROBATION_MS      60000UL

// If the board cannot join Wi-Fi at startup within this time, it forgets the
// saved network and opens the setup page again. This stops a wrong password
// from leaving the board stuck retrying forever.
#define WIFI_BOOT_TIMEOUT_MS   180000UL

// Setup hotspot the board creates on first boot. Open http://192.168.4.1
// after joining it. The password must be at least 8 characters.
#define SETUP_AP_SSID          "SafeHome-Setup"
#define SETUP_AP_PASSWORD      "safehome-setup"

// The broker's name or IP address, its login, and its password are entered
// on the setup page and stored in flash. They are not stored here.

#define MQTT_PORT        1883
#define MQTT_CLIENT_ID   "safehome-esp32"

// ---------------------------------------------------------------------
// Pins (see AGENT_BUILD_SPEC.md section 1 / dissertation Figure 4.1)
// ---------------------------------------------------------------------
#define PIN_PIR    27   // HC-SR501 OUT. Digital in. HIGH = motion.
#define PIN_LDR    34   // LDR module signal pin (DO on this build). Input-only pin.
#define PIN_RELAY  26   // 5V relay IN. Digital out.
#define PIN_BUZZER 25   // Optional buzzer. Digital out.

// ---------------------------------------------------------------------
// Behaviour
// ---------------------------------------------------------------------

// Most cheap 5V relay modules are ACTIVE LOW: writing LOW to IN closes the
// relay and turns the lamp ON. If your relay turns the lamp on when you
// write HIGH instead, flip this one constant - nothing else needs to change.
#define RELAY_ACTIVE_LOW       true

// analogRead() on GPIO34 returns 0-4095. LDR_DARK_THRESHOLD is the raw
// value below which the room counts as DARK (when LDR_HIGHER_IS_BRIGHTER is
// true). Calibrate this for your specific LDR module and room lighting:
// open the Serial Monitor, note the raw value in a dark room and in a lit
// room, and set the threshold roughly halfway between the two.
#define LDR_DARK_THRESHOLD     1200
// Tested on the real module: covering the sensor makes the reading go HIGH
// (4095), so on this module a HIGHER value means DARKER. Hence false here.
// (Only used in analogue mode - see LDR_USE_DIGITAL_OUTPUT below.)
#define LDR_HIGHER_IS_BRIGHTER false

// --- LDR wired to the module's DO (digital) pin instead of AO ---------------
// This module only has a DO pin, which is a simple on/off "dark or bright"
// signal - the module's little blue dial sets where that switch-over
// happens (turn it until the DO LED goes OFF when you cover the sensor and
// ON in normal room light). With DO there is no 0-4095 range, so:
//  * the firmware reports raw as 4095 (dark) or 0 (bright) for the app;
//  * LDR_DARK_THRESHOLD and the 150-count boundary rule do not apply -
//    instead a reading only counts as "confident" once DO has stayed
//    unchanged for LDR_DO_STABLE_MS (a flickering DO means the light is
//    right on the boundary, which is what the 150-count rule detects);
//  * the "identical reading 60 times = stuck sensor" fault check is turned
//    off, because a digital pin legitimately stays the same for hours.
// Set LDR_USE_DIGITAL_OUTPUT to false if you later wire AO instead.
#define LDR_USE_DIGITAL_OUTPUT true
#define LDR_DO_HIGH_IS_DARK    true     // measured: covered sensor -> DO HIGH
#define LDR_DO_STABLE_MS       2000UL

// The LDR module's VCC wire is on GPIO32 (there is no free 3V3 socket on
// this breadboard), so the firmware switches GPIO32 on at boot to power
// the module. The module only draws a few mA, well within what a GPIO pin
// can supply. Set LDR_POWER_FROM_GPIO to false if you wire VCC to 3V3.
#define LDR_POWER_FROM_GPIO    true
#define PIN_LDR_POWER          32

// This LED lamp module has a separate IN/enable pin, distinct from its
// VCC: the module only lights if BOTH its VCC has power AND this pin is
// HIGH. The relay (PIN_RELAY) still switches the lamp's actual power, as
// the dissertation's hardware design requires - this pin is driven in
// lockstep with it by writeRelay() in safety.cpp, purely as a second,
// independent cutoff. That means the lamp positively cannot light unless
// the relay AND this pin both agree, which protects against the relay's
// own mechanical contacts ever behaving unreliably. Set this to false if
// your lamp module has no separate IN pin (VCC alone is enough).
#define LAMP_IN_SYNCED_WITH_RELAY true
#define PIN_LAMP_IN                33

#define MOTION_DWELL_MS        3000UL      // motion must persist this long to count
#define ABSENCE_TIMEOUT_MS     1800000UL   // 30 min no motion -> propose LIGHT_OFF
#define SENSOR_POLL_MS         500UL
#define PROPOSAL_TIMEOUT_MS    60000UL     // unanswered proposal expires

// ---------------------------------------------------------------------
// Graduation thresholds (from the dissertation, do not change)
// ---------------------------------------------------------------------
#define G1_MIN_PROPOSALS       100
#define G2_MIN_APPROVAL_PCT    90
#define G4_CANARY_HOURS        48
#define DEMOTE_APPROVAL_PCT    85
#define DEMOTE_WINDOW          50
#define DEMOTE_OVERRIDE_PCT    20

// ---------------------------------------------------------------------
// Testing convenience
// ---------------------------------------------------------------------
// The student cannot wait 48 hours during a demo. With FAST_TEST_MODE set
// to true, ABSENCE_TIMEOUT_MS is shortened to 30 seconds and the S4 canary
// period is shortened to 2 minutes. The firmware prints a loud warning at
// boot when this is active so nobody demos it by accident.
#define FAST_TEST_MODE          true

#if FAST_TEST_MODE
  #define EFFECTIVE_ABSENCE_TIMEOUT_MS   30000UL          // 30 seconds
  #define EFFECTIVE_CANARY_MS            120000UL         // 2 minutes
#else
  #define EFFECTIVE_ABSENCE_TIMEOUT_MS   ABSENCE_TIMEOUT_MS
  #define EFFECTIVE_CANARY_MS            (G4_CANARY_HOURS * 3600000UL)
#endif

// Sensor fault detection thresholds
#define LDR_STUCK_READ_COUNT    60          // identical raw reads in a row = fault
#define PIR_STUCK_MS            600000UL    // 10 minutes continuously HIGH = fault

#endif // CONFIG_H
