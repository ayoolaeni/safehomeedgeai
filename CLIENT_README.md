# SafeHome smart lamp: setup guide

A smart lamp that senses motion and light, decides when it should be on, and
asks you before acting until you trust it. You control it with the SafeHome
app, on an **Android phone**, on your **Windows laptop**, or on both.
Everything runs on your home Wi-Fi, with no cloud service.

The lamp board is already wired. This guide sets up the software so the lamp,
your laptop and your phone can talk to each other. Follow the steps in order.
Each step tells you what you should see when it worked.

> **Part 1** is for you (the client).
> **Part 2** at the end is for the developer: how to pack and send this kit.

---

# Part 1: Setting up the lamp

## How the parts work together

```
   Android phone (SafeHome app) --+
                                  +--Wi-Fi-->  Laptop (Mosquitto)  <--Wi-Fi-->  Lamp board
   Laptop (SafeHome app) ---------+
```

- **The laptop** runs a small free program called **Mosquitto** (the
  "broker"). It passes messages between the app and the lamp, like a post
  office. The laptop must be **on and awake** for the lamp to be controlled.
- **The lamp board** joins your home Wi-Fi, reads its sensors and switches the
  lamp.
- **The SafeHome app** sends the commands. It runs on an Android phone
  (Step 9), on the laptop itself (Step 10), or on both at the same time.

Everything must be on the **same home Wi-Fi**.

> **iPhone users:** the SafeHome app doesn't run on iPhones. Skip Step 9 and
> use the laptop app (Step 10). Your iPhone is still handy for Step 8.

## What you need

- The **SafeHome kit** folder from your developer (`safehome-client-kit.zip`).
  It contains:
  - `CLIENT_README.md`: this guide.
  - `safehome-edge-ai.apk`: the app for an Android phone.
  - `SafeHome\`: the app for the Windows laptop.
  - `broker\mosquitto.conf`: a settings file for the laptop.
- A **Windows laptop** with **Google Chrome** or **Microsoft Edge**.
- A **phone** (Android or iPhone) for Step 8. An Android phone can also run
  the app.
- The **SafeHome lamp board** (already wired).
- A **USB cable that carries data**. Some cables only charge; if the laptop
  doesn't notice the board, try another cable.
- Your **home Wi-Fi name and password**.

> **Important:** the lamp board only works on **2.4 GHz Wi-Fi**. Most home
> routers provide both 2.4 GHz and 5 GHz. If your router shows two names (for
> example `MyHome` and `MyHome-5G`), use the one **without** "5G".

Keep a piece of paper nearby. You will write down three things:

| Write down | Example | From step |
| --- | --- | --- |
| Broker username | `safehome` | Step 3 |
| Broker password | (the one you choose) | Step 3 |
| Laptop IP address | `192.168.1.20` | Step 5 |

---

## Step 1: Unzip the kit

1. Save `safehome-client-kit.zip` on the laptop, for example on the Desktop.
2. Right-click it, choose **Extract All**, then **Extract**.
3. A folder called `safehome-client-kit` opens. Keep it open.

---

## Step 2: Install Mosquitto on the laptop

1. Open **https://mosquitto.org/download/** in Chrome or Edge.
2. Under **Windows**, download the **64-bit** installer (`mosquitto-...-install-windows-x64.exe`).
3. Run it. Click **Next** through every page and keep all the default options.
   Mosquitto installs into `C:\Program Files\mosquitto`.

---

## Step 3: Create the broker login

1. Press the **Windows key**, type `PowerShell`, right-click **Windows
   PowerShell** and choose **Run as administrator**. Click **Yes**.
2. Copy and paste these two lines, then press **Enter**:
   ```
   cd "C:\Program Files\mosquitto"
   .\mosquitto_passwd.exe -c passwd safehome
   ```
3. Type a password and press Enter. Nothing appears on screen while you type;
   that's normal. Type it again and press Enter.
4. Write down the username **safehome** and the password.

**Keep this PowerShell window open** for the next steps.

---

## Step 4: Apply the SafeHome settings to Mosquitto

Out of the box, Mosquitto only accepts connections from the laptop itself.
This step lets the lamp and the phone reach it, and only with your login.

1. In the kit folder, open the `broker` folder. Copy `mosquitto.conf`.
2. Open `C:\Program Files\mosquitto` in File Explorer and paste. Choose
   **Replace the file in the destination**, and click **Continue** if Windows
   asks for administrator permission.
3. Back in the administrator PowerShell window, paste these lines and press
   **Enter**:
   ```
   Set-Service mosquitto -StartupType Automatic
   Restart-Service mosquitto
   New-NetFirewallRule -DisplayName "SafeHome Mosquitto" -Direction Inbound -Protocol TCP -LocalPort 1883 -Action Allow -Profile Private
   Get-Service mosquitto
   ```
   - The first line makes Mosquitto start by itself whenever the laptop starts.
   - The third line opens the laptop's firewall for Mosquitto on your home
     network.

**You should see:** the last line shows `Running` next to `mosquitto`.

4. Make sure Windows treats your home Wi-Fi as a **private** network:
   **Settings > Network & internet > Wi-Fi >** click your Wi-Fi name **>**
   choose **Private network**.

5. Stop the laptop from sleeping while it's plugged in:
   **Settings > System > Power & battery > Screen and sleep >** set **When
   plugged in, put my device to sleep after** to **Never**.

---

## Step 5: Find the laptop's IP address

1. In the PowerShell window, type `ipconfig` and press **Enter**.
2. Find the section **Wireless LAN adapter Wi-Fi**.
3. Write down the number next to **IPv4 Address**, for example `192.168.1.20`.

---

## Step 6: Plug in the lamp board

1. Connect the lamp board to the laptop with the USB cable. A light on the
   board turns on.
2. Check that Windows recognises the board. Right-click the **Start** button,
   choose **Device Manager**, and open **Ports (COM & LPT)**.

**You should see:** a line such as **USB-Enhanced-SERIAL CH9102 (COM3)** or
**USB Serial Device (COM3)**. The COM number can differ.

**If you don't see it:**
- The **Ports** section is missing, or the board appears under **Other
  devices** with a yellow warning sign: Windows needs the board's driver.
  Download **CH343SER.EXE** from
  **https://www.wch-ic.com/downloads/CH343SER_EXE.html**, run it, click
  **INSTALL**, then unplug the board and plug it in again.
- Nothing changes at all when you plug the board in: use a different USB
  cable or another USB port.

Close Device Manager once the board appears.

---

## Step 7: Install the lamp software on the board (one time only)

1. Make sure no other program (such as Arduino IDE) is open.
2. Open this page in **Chrome** or **Edge**:
   **https://ayoolaeni.github.io/safehomeedgeai/flash/**
3. Click **Install SafeHome lamp**.
4. A small window lists the connected boards. Choose the one you saw in Step 6
   (**USB-Enhanced-SERIAL CH9102** or **USB Serial**) and click **Connect**.
5. Click **Install**, then confirm. Wait for the progress bar, about
   30 seconds to 1 minute.
6. When it says **Installation complete**, close the window. Unplug the board
   and plug it in again.

From now on, the board only needs **power**. It can stay plugged into the
laptop, or into any USB phone charger.

**If the install fails:** unplug the board, plug it back in, reload the page
and try again. If it still fails, hold the **BOOT** button on the board while
you click **Install**, and let go when the progress bar starts.

---

## Step 8: Connect the lamp to your home Wi-Fi (using your phone)

1. With the board powered, wait about 10 seconds. It creates its own Wi-Fi
   network called **SafeHome-Setup**.
2. On your **phone**, open **Settings > Wi-Fi** and connect to
   **SafeHome-Setup**. The password is:
   ```
   safehome-setup
   ```
   The phone may say **"No internet"**. That's expected.
   - **Android:** if it asks whether to stay connected, choose **Keep
     connection** or **Stay connected**.
   - **iPhone:** if a login window pops up by itself, tap **Cancel**, then
     **Use Other Network** or **Use Without Internet**.
3. Open the phone's browser (**Chrome** on Android, **Safari** on iPhone) and
   go to:
   ```
   http://192.168.4.1
   ```
   The **SafeHome setup** page opens.
4. Fill in the page:

   | Field | What to enter |
   | --- | --- |
   | **Your home Wi-Fi name** | Pick your home Wi-Fi from the list (the 2.4 GHz one). |
   | **Wi-Fi password** | Your home Wi-Fi password. Check capital letters. |
   | **Laptop name or IP address** | The laptop IP address from Step 5, for example `192.168.1.20`. |
   | **Broker username** | `safehome` |
   | **Broker password** | The password from Step 3. |

5. Tap **Save and connect**. The page shows **Saved** and the board restarts.
6. On your phone, go back to **Settings > Wi-Fi** and reconnect to your
   **home Wi-Fi**.

*No phone handy?* The laptop can do this step instead: click the Wi-Fi icon at
the bottom right of the screen, connect to **SafeHome-Setup**, and open
`http://192.168.4.1` in Chrome or Edge. Reconnect the laptop to your home
Wi-Fi afterwards.

The lamp joins your home Wi-Fi within about 20 seconds.

**If you typed something wrong:** if the lamp can't join your Wi-Fi within
about 3 minutes, it opens **SafeHome-Setup** again by itself. Repeat this step.

---

## Step 9: Install the SafeHome app on an Android phone

**iPhone users: skip this step** and go to Step 10. The app doesn't run on
iPhones.

1. Copy `safehome-edge-ai.apk` from the kit folder to your phone. Use whichever
   is easiest:
   - **USB cable:** connect the phone to the laptop, choose **File transfer**
     on the phone, and drag the file into the phone's **Download** folder.
   - **Google Drive / email / WhatsApp:** send the file to yourself and
     download it on the phone.
2. On the phone, open the **Files** app (or **My Files**), go to **Downloads**,
   and tap **safehome-edge-ai.apk**.
3. If Android says **"For your security, your phone is not allowed to install
   unknown apps from this source"**, tap **Settings**, turn on **Allow from
   this source**, then go back.
4. Tap **Install**. If Google Play Protect warns about an unknown app, tap
   **More details > Install anyway**. The app comes from your developer, not
   the Play Store, which is why Android warns.
5. Tap **Open**. Allow **microphone** access when asked (for voice commands).

---

## Step 10: Install the SafeHome app on the laptop

Do this if you use an iPhone, or if you also want to control the lamp from the
laptop. There's no installer: the app runs straight from its folder.

1. In the kit folder, copy the **SafeHome** folder.
2. Open **This PC > Local Disk (C:)** (or your **Documents** folder) and paste
   it there. Keep everything inside the folder together; the app needs all of
   it.
3. Open the **SafeHome** folder, right-click **SafeHome.exe**, and choose
   **Show more options > Send to > Desktop (create shortcut)**. From now on,
   open the app from the **SafeHome** icon on your Desktop.
4. Double-click **SafeHome.exe** (or the Desktop icon).
   - If a blue window says **"Windows protected your PC"**, click **More info**,
     then **Run anyway**. Windows shows this for apps that don't come from the
     Microsoft Store.
   - If it complains that **VCRUNTIME140.dll** or **MSVCP140.dll** is missing,
     install the **Microsoft Visual C++ Redistributable (x64)** from
     **https://aka.ms/vs/17/release/vc_redist.x64.exe**, then try again.

---

## Step 11: Connect the app to Mosquitto

Do this in each app you installed (the phone, the laptop, or both).

1. **On the phone:** make sure the phone is on your **home Wi-Fi** (not
   SafeHome-Setup).
2. In the app, tap the red card that says **DISCONNECTED**, "Tap to enter
   your laptop address".
3. Fill in:

   | Field | On the Android phone | On the laptop |
   | --- | --- | --- |
   | **Laptop name or IP address** | The laptop IP address from Step 5, for example `192.168.1.20` | `localhost` |
   | **Broker username** | `safehome` | `safehome` |
   | **Broker password** | The password from Step 3 | The password from Step 3 |

   The laptop uses `localhost` because the app and Mosquitto are on the same
   laptop.
4. Tap **Save**.

**You should see:** the card turns green and shows **CONNECTED**. Within a few
seconds the **Light**, **Motion** and **Light level** cards fill in, and the
**Wi-Fi** card shows your home Wi-Fi name. That means the lamp is talking to
the app.

---

## Step 12: Test it

1. Tap **TURN ON**. The lamp turns on (you may hear the relay click).
2. Tap **TURN OFF**. The lamp turns off.
3. Wave your hand in front of the motion sensor. The **Motion** card changes.
4. Hold the blue voice button and say **"turn on the light"**.
   - On the **Android phone**, this works once microphone access is allowed.
   - On the **laptop**, it only works if the laptop has a microphone. If it
     says "Voice unavailable", use the buttons instead; everything else works
     the same.

Setup is finished.

---

## Everyday use

- **Every day:** keep the laptop on (Mosquitto starts by itself) and the
  lamp board powered. Open the SafeHome app on your Android phone (on home
  Wi-Fi) or from the **SafeHome** icon on the laptop's Desktop.
- **Buttons:** tap **TURN ON** or **TURN OFF**.
- **Voice:** hold the blue voice button and say "turn on the light" or
  "turn off the light".
- **Modes:**
  - **Manual:** you control the lamp. It always starts in this mode.
  - **Assisted:** the lamp suggests changes, and you approve or decline them.
  - **Autonomous:** the lamp acts on its own, once it has earned your trust.
    Until then, it keeps asking.
- **Changing Wi-Fi later:** in **Manual** mode, tap the **Wi-Fi** card and
  pick another network. If the lamp can't reach the laptop on the new network
  within a minute, it goes back to the old one.
- **After a power cut:** nothing to do. The lamp and Mosquitto reconnect by
  themselves once the laptop and router are back on.

---

## Troubleshooting

| What you see | What to do |
| --- | --- |
| The **Install SafeHome lamp** button doesn't appear | Open the page in Chrome or Edge, not Firefox or Safari. |
| No board appears in the install window | Do Step 6 again (driver, cable, USB port). Close Arduino IDE or any other program using the board. |
| No **SafeHome-Setup** network appears | Unplug the board, wait 30 seconds, plug it back in, and wait 10 seconds. |
| The setup page doesn't open | Check the phone is still on SafeHome-Setup (phones sometimes switch back to home Wi-Fi or mobile data by themselves), then type `http://192.168.4.1` yourself. |
| Your Wi-Fi isn't in the list on the setup page | It's probably 5 GHz only. Use the 2.4 GHz network, or turn on 2.4 GHz in the router. |
| "Windows protected your PC" when opening the laptop app | Click **More info**, then **Run anyway**. |
| The laptop app doesn't open at all, or a DLL is missing | Install the Visual C++ Redistributable (Step 10), and make sure you copied the **whole** SafeHome folder, not just SafeHome.exe. |
| The app says **DISCONNECTED** | Check: the laptop is on and awake; `Get-Service mosquitto` shows `Running`; the username and password are correct. **Phone:** it's on home Wi-Fi and the address is the laptop IP. **Laptop:** the address is `localhost`. |
| App is **CONNECTED** but the cards stay empty and the lamp doesn't respond | The lamp isn't reaching the laptop. Check the board has power. If the laptop's IP changed, see the next row. |
| The laptop's IP address changed (after a router restart) | Do Step 5 again and enter the new address in the **phone** app (Step 11). The laptop app is fine, since it uses `localhost`. The lamp also has the old address saved, and it won't reopen SafeHome-Setup by itself in this case, so ask your developer to reset its setup. To stop this happening, ask whoever manages the router to give the laptop a **fixed (reserved) IP address** right after setup. |
| The voice button says "unavailable" | **Phone:** **Settings > Apps > SafeHome > Permissions > Microphone > Allow**. **Laptop:** check it has a microphone and that **Settings > Privacy & security > Microphone** allows desktop apps. |

## Security notes

- The broker login stops other people on your Wi-Fi from controlling the lamp.
  Keep the password private.
- Messages are not encrypted. Someone already inside your home network could
  read them. This is a limitation of this prototype.

---
---

# Part 2: For the developer: packing and sending the kit

The client doesn't need the source code, Flutter or Arduino. She only needs:

- the **Android app** (`safehome-edge-ai.apk`),
- the **Windows app** (the `SafeHome` folder),
- the **Mosquitto settings file**,
- **this guide**.

Both apps go in the kit, so she can use whichever device she has. An iPhone
app would need a Mac and a paid Apple developer account, so iPhone users use
the laptop app.

The lamp software is installed from the web page
`https://ayoolaeni.github.io/safehomeedgeai/flash/` (GitHub Pages, served from
`docs/flash/`), so it isn't in the kit.

## 1. (If you changed the firmware) rebuild the install page

Run `firmware\build-firmware.bat`, then commit and push `docs/flash/`. Wait a
minute or two for GitHub Pages to update. Skip this if the firmware hasn't
changed.

## 2. Build both apps

In PowerShell, from the project folder:

```powershell
cd app
flutter pub get
flutter build apk --release
flutter build windows --release
cd ..
```

- The **Android app** is created at
  `app\build\app\outputs\flutter-apk\app-release.apk`.
- The **Windows app** is created in `app\build\windows\x64\runner\Release\`.
  That whole folder is the app: `safehome_edge_ai.exe`, the `.dll` files and
  the `data` folder must stay together.

Before sending, check both reach **CONNECTED**: the APK on a test phone (with
the laptop IP), and the Windows app with `localhost`.

## 3. Pack the kit

From the project folder:

```powershell
Remove-Item -Recurse -Force client-kit, safehome-client-kit.zip -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force client-kit\broker | Out-Null
Copy-Item app\build\app\outputs\flutter-apk\app-release.apk client-kit\safehome-edge-ai.apk
Copy-Item app\build\windows\x64\runner\Release client-kit\SafeHome -Recurse
Rename-Item client-kit\SafeHome\safehome_edge_ai.exe SafeHome.exe
Copy-Item broker\mosquitto.conf client-kit\broker\
Copy-Item CLIENT_README.md client-kit\
Compress-Archive -Path client-kit\* -DestinationPath safehome-client-kit.zip -Force
```

This creates `safehome-client-kit.zip` (about 33 MB) containing:

```
safehome-client-kit.zip
├── CLIENT_README.md
├── safehome-edge-ai.apk
├── SafeHome\
│   ├── SafeHome.exe
│   ├── flutter_windows.dll
│   ├── speech_to_text_windows_plugin.dll
│   └── data\
└── broker\
    └── mosquitto.conf
```

`client-kit/` and `*.zip` are in `.gitignore`, so they are never committed.

## 4. Send it to the client

The zip is about 33 MB, which is over the 25 MB email limit. Use one of these
instead:

- **Google Drive:** upload the zip, click **Share**, set **Anyone with the
  link**, and send her the link.
- **WeTransfer** (wetransfer.com): free up to 2 GB, no account needed.
- **USB flash drive:** copy the zip onto it and hand it over.
- **GitHub Release:** attach `safehome-client-kit.zip` to a release.

Tell her to start with **Part 1, Step 1** of `CLIENT_README.md`.
