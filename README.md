# SafeHome Edge AI

> **New here? Start with [docs/CLIENT_SETUP.md](docs/CLIENT_SETUP.md).** It's a
> step-by-step guide for setting up the laptop, the lamp board, the phone and
> the Wi-Fi, written for people who haven't used these tools before. The
> sections below are the older developer notes.

### Installing the lamp software (no tools needed)

The lamp board is flashed from a web page, so nobody needs the Arduino tools:

1. Plug the lamp board into the laptop, and open the install page in Chrome or Edge:
   `https://ayoolaeni.github.io/safehomeedgeai/flash/`
2. Click **Install SafeHome lamp** and follow the on-screen steps.

For the developer: after changing any file in `firmware/`, run
`firmware\build-firmware.bat`. It rebuilds the lamp software and refreshes
`docs/flash/`. Commit and push that folder, so the install page serves the new
version. The install page needs GitHub Pages turned on for the repository
(Settings, Pages, deploy from the main branch).

A single lamp, controlled by an ESP32 that senses motion (PIR) and light
level (LDR) and decides locally whether the lamp should be on. A Flutter
phone app talks to it over MQTT on your home Wi-Fi. There is no cloud
service anywhere in this project - everything works with the internet
switched off, as long as your phone, laptop and ESP32 are on the same
Wi-Fi network.

This guide assumes you have never used Mosquitto, Arduino, or Flutter
before. Follow it in order.

---

## What you need

- The laptop you're reading this on, running Windows.
- The ESP32 + sensors, wired as described in `AGENT_BUILD_SPEC.md` section 1
  (PIR -> GPIO27, LDR -> GPIO34, relay -> GPIO26, buzzer -> GPIO25).
- Your Android phone.
- A USB data cable (not a charge-only cable) for the ESP32.
- All three devices on the **same Wi-Fi network**. A phone on mobile data
  will never reach the broker - turn Wi-Fi on and mobile data off while
  testing.

---

## 1. Install Mosquitto on the laptop

Mosquitto is the MQTT "broker" - the message hub the ESP32 and the phone
both connect to. It runs on your laptop.

1. Download the Windows installer from <https://mosquitto.org/download/>
   (get the 64-bit `.exe` installer).
2. Run the installer. Accept the defaults - it installs to
   `C:\Program Files\mosquitto` and offers to install it as a Windows
   service.
3. Open `C:\Program Files\mosquitto\mosquitto.conf` in Notepad (you may
   need "Run as administrator" to save it) and add these two lines at the
   end:

   ```
   listener 1883 0.0.0.0
   allow_anonymous true
   ```

   This tells Mosquitto to accept connections from other devices on the
   network (not just the laptop itself), with no username/password. That's
   fine for a local-network-only student project, but don't expose this
   port to the internet.

4. Restart the Mosquitto service so the new config takes effect. Open
   PowerShell **as Administrator** and run:

   ```powershell
   Restart-Service mosquitto
   ```

5. **Allow Mosquitto through Windows Firewall.** This is the single most
   common reason the phone can't connect, so don't skip it:
   - Open **Windows Defender Firewall with Advanced Security** (search for
     it in the Start menu).
   - Click **Inbound Rules** → **New Rule...**
   - Rule type: **Port**. Next.
   - **TCP**, Specific local ports: `1883`. Next.
   - **Allow the connection**. Next.
   - Tick all three profiles (Domain, Private, Public). Next.
   - Name it `Mosquitto MQTT` and finish.

6. Test it's listening: in PowerShell, run
   `Test-NetConnection -ComputerName localhost -Port 1883` and check
   `TcpTestSucceeded : True`.

---

## 2. Find the laptop's computer name (and, for the app, its IP)

**For the ESP32 (`config.h`):** the firmware finds the laptop automatically
by hostname (via mDNS), so it keeps working even if your laptop's IP
changes day to day - you only need to set this once. Find your computer's
name by running `hostname` in PowerShell (or Settings → System → About →
Device name on Windows). You'll put this in `MQTT_BROKER_HOSTNAME` in
`config.h` in the next step - no ".local" suffix needed, the firmware adds
that itself.

**For the phone app:** the app doesn't do mDNS lookups, so it still needs
the laptop's actual IP address, entered via the connection tile (tap it,
type the IP, save - no rebuild needed). Get it by running:

```powershell
ipconfig
```

Look for the **IPv4 Address** under the Wi-Fi adapter you're using, e.g.
`192.168.1.100`. (On macOS/Linux the equivalent command is `ifconfig`.)
If this changes later and the app shows DISCONNECTED, just re-check it and
update it in the app - the ESP32 side won't need touching.

---

## 3. Flash the ESP32

1. Install the [Arduino IDE](https://www.arduino.cc/en/software) (2.x).
2. Add ESP32 board support: **File → Preferences**, add this URL to
   "Additional Boards Manager URLs":
   `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
   Then **Tools → Board → Boards Manager**, search "esp32", install the
   package by Espressif Systems.
3. Install libraries via **Tools → Manage Libraries**:
   - `PubSubClient` by Nick O'Leary
   - `ArduinoJson` by Benoit Blanchon (v6.x)
   - `ESPmDNS` is built into the ESP32 board package - nothing extra to install.
4. Open `firmware/safehome_esp32/safehome_esp32.ino`.
5. Edit `firmware/safehome_esp32/config.h`:
   - Set `WIFI_SSID` and `WIFI_PASSWORD` to your Wi-Fi network.
   - Set `MQTT_BROKER_HOSTNAME` to your laptop's computer name from step 2.
6. **Tools → Board**: select "ESP32 Dev Module".
7. **Tools → Port**: select the COM port your ESP32 appears on (plug it in
   first; if nothing appears, install the CP2102 or CH340 USB driver for
   your board).
8. Click **Upload**.
9. Once uploaded, open **Tools → Serial Monitor**, set the baud rate to
   **115200**. You should see Wi-Fi connecting, then MQTT connecting, then
   a stream of sensor/decision logs. Leave this open while testing - it is
   the best debugging tool you have.

---

## 4. Build the Flutter app

1. Install [Flutter](https://docs.flutter.dev/get-started/install/windows)
   and make sure `flutter doctor` reports no blocking issues for Android.
2. From the `app/` folder:

   ```powershell
   flutter pub get
   flutter build apk --release
   ```

3. The finished APK is at:

   ```
   app/build/app/outputs/flutter-apk/app-release.apk
   ```

---

## 5. Get the APK onto your phone

Pick whichever is easiest:

- **USB transfer**: plug the phone in, copy `app-release.apk` to the
  phone's Downloads folder, then open it from the phone's file manager.
- **Google Drive**: upload the APK to Drive, open the Drive app on the
  phone, and download/open it there.
- **`flutter run` over USB**: enable Developer Options and USB debugging on
  the phone (Settings → About phone → tap "Build number" 7 times, then
  Settings → Developer options → USB debugging), plug it in, and from the
  `app/` folder run `flutter run --release`.

Android will warn that installing from an unknown source is blocked the
first time - tap **Settings** in that warning, then allow installs from
whichever app you used (Files, Chrome, Drive, etc.).

Once installed, tap the connection tile at the top of the app and confirm
the broker IP matches your laptop's IP from step 2. This is saved on the
phone, so if your laptop's IP changes later you can update it here without
reinstalling the app.

---

## 6. Everything on the same Wi-Fi network

**The laptop (running Mosquitto), the phone, and the ESP32 must all be on
the same Wi-Fi network.** A phone on mobile data, or a guest network that
isolates devices from each other, will never reach the broker. If your
router has a "guest network" or "AP/client isolation" setting, make sure
it's off for the network you're using.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| App shows DISCONNECTED | Wrong broker IP in the app (tap the connection tile to fix); laptop firewall blocking port 1883 (see step 1.5); phone on mobile data instead of Wi-Fi; phone and laptop on different Wi-Fi networks or a guest network with client isolation. |
| ESP32 will not join Wi-Fi | Double-check `WIFI_SSID`/`WIFI_PASSWORD` in `config.h` (case-sensitive); ESP32 only supports 2.4GHz Wi-Fi, not 5GHz - if your router broadcasts both under one name, temporarily split them or check your phone is testing against the 2.4GHz band too. |
| Relay clicks but lamp does not light | Check the lamp's own power supply and wiring to the relay's NO/COM terminals; confirm the LED module is rated for the voltage you're feeding it. |
| Lamp is inverted (turns on when app says OFF) | Your relay module is active-high, not active-low. In `config.h`, set `RELAY_ACTIVE_LOW` to `false` and re-upload. |
| PIR triggers constantly / never clears | Give the HC-SR501 a minute after power-up to settle. Check its two onboard potentiometers aren't turned to maximum sensitivity/delay. Make sure nothing is moving in its field of view (fans, curtains, sunlight through a window). |
| LDR always reads DARK (or always BRIGHT) | This build reads the LDR module's **DO** pin on GPIO34. Turn the small blue dial on the module until its DO LED is ON in normal room light and goes OFF when you cover the sensor. If the app shows DARK and BRIGHT the wrong way round, flip `LDR_DO_HIGH_IS_DARK` in `config.h`. (If you later wire the module's AO pin instead, set `LDR_USE_DIGITAL_OUTPUT` to `false` and calibrate `LDR_DARK_THRESHOLD`.) |
| Voice button doesn't respond | Make sure you allowed the microphone permission when Android asked; if you denied it, go to Android Settings → Apps → SafeHome Edge AI → Permissions and enable Microphone. |

---

## Project layout

```
safehome-edge-ai/
├── firmware/safehome_esp32/   ESP32 Arduino sketch (see AGENT_BUILD_SPEC.md section 4)
├── app/                       Flutter Android app (see AGENT_BUILD_SPEC.md section 5)
└── docs/TESTING.md            Acceptance test checklist for your Chapter 4
```

See `AGENT_BUILD_SPEC.md` in the parent folder for the full technical
specification this project was built against, including the MQTT topic
contract, the graduation state machine, and every design decision's
rationale.
