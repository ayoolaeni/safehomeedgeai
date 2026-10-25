# SafeHome: whole-home setup guide

SafeHome is a Thriftogentic home digital twin for the whole house. A home
server on your laptop (the **AHDT**, Agentic Home Digital Twin) coordinates
six subsystem twins:

- **Energy:** grid, solar/battery and generator.
- **Fire & Safety.**
- **Water.**
- **Climate & lighting.**
- **Access & Security.**
- **Resident.**

Each twin senses, decides, and asks you before acting until it has earned your
trust. You control the house with the SafeHome app, on an **Android phone**,
on your **Windows laptop**, or on both. Everything runs on your home Wi-Fi,
with no cloud service.

The **sitting-room lamp** is the real hardware: an ESP32 board with motion and
light sensors, already wired. The rest of the house (solar, generator, water
tank, smoke detectors, door locks, air conditioners) is **simulated** by the
home server, and the app labels those devices **SIMULATED**. Real devices can
replace simulated ones later.

This guide sets up the software so the lamp, the home server, your laptop and
your phone can talk to each other. Follow the steps in order. Each step tells
you what you should see when it worked.

> **Part 1** is for you (the client).
> **Part 2** at the end is for the developer: how to pack and send this kit.

---

## Already set up the lamp before? Upgrade in 5 steps

If you already did the first setup (Mosquitto installed, lamp on your Wi-Fi,
app showing **CONNECTED**), you don't need to repeat it. Do only this:

1. **Unzip the new kit** (right-click `safehome-client-kit.zip` > **Extract
   All**).
2. **Update the phone app:** copy the new `safehome-edge-ai.apk` to your
   Android phone, tap it, and tap **Update** (or **Install**). Your laptop
   address and login are kept. The same steps as Step 9.
3. **Update the laptop app** (if you use it): replace your old **SafeHome**
   folder with the new **SafeHome** folder from the kit, as in Step 10.
4. **Start the home server:** do **Step 12** below. It asks for your broker
   username (`safehome`) and the password you chose. You enter them only the
   first time.
5. **Plug in the lamp board** and open the app. The **Home** tab now shows the
   whole house. Then try **Step 14** (Test it).

That's all. The lamp board needs **no** changes.

---

---

# Part 1: Setting up the house

## How the parts work together

```
   Android phone (SafeHome app) --+               Laptop
                                  +--Wi-Fi-->  Mosquitto  <--Wi-Fi-->  Lamp board (ESP32)
   Laptop (SafeHome app) ---------+               ^
                                                  |
                                     SafeHome home server (AHDT + 6 twins,
                                     optional local AI model)
```

- **The laptop** runs a small free program called **Mosquitto** (the
  "broker"). It passes messages between the app, the home server and the
  lamp, like a post office. The laptop must be **on and awake** for the house
  to be controlled.
- **The home server** (`safehome-server.exe`) is the brain of the whole house.
  It runs the six twins, checks every action against its safety rules,
  keeps a tamper-proof activity log, and can use a small AI model on the
  laptop to answer your questions.
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
  - `safehome-server.exe`: the whole-home server for the laptop.
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
2. In the app, tap **Tap to enter your laptop address** at the bottom of the
   coloured box at the top of the Home tab (or the **settings** button at the
   top right).
3. Fill in:

   | Field | On the Android phone | On the laptop |
   | --- | --- | --- |
   | **Laptop name or IP address** | The laptop IP address from Step 5, for example `192.168.1.20` | `localhost` |
   | **Broker username** | `safehome` | `safehome` |
   | **Broker password** | The password from Step 3 | The password from Step 3 |

   The laptop uses `localhost` because the app and Mosquitto are on the same
   laptop.
4. Tap **Save**.

**You should see:** the line at the top changes to **Connected to …**. Until you
do Step 12, the Home tab says **Home server offline**; that's expected.

---

## Step 12: Start the home server (the whole house)

1. In the kit folder, copy `safehome-server.exe` into a new folder, for
   example **Documents\SafeHome Server**. The server keeps its settings and
   activity log next to the `.exe`, so give it its own folder.
2. Double-click `safehome-server.exe`. If a blue window says **"Windows
   protected your PC"**, click **More info**, then **Run anyway**.
3. A black window opens. The first time, it asks four questions:

   | Question | What to type |
   | --- | --- |
   | **Broker address** | Press **Enter** (keeps `localhost`) |
   | **Broker username** | `safehome`, then **Enter** |
   | **Broker password** | The password from Step 3, then **Enter** |
   | **Resident's name** | Your first name, then **Enter** |

   It saves your answers in `config.json` in the same folder, so you are only
   asked once.

4. Leave the black window open (you can minimise it). It shows every decision
   the house makes.

**You should see:** in the app, the Home tab fills in with the energy and
water cards, the six subsystem twins and **Whole home · 18:00**. The house
clock runs fast (one hour per minute) so you can watch a whole day quickly.
You can change the speed in the app.

**To start it automatically with Windows:** press **Windows key + R**, type
`shell:startup` and press **Enter**. Right-click `safehome-server.exe`,
choose **Show more options > Create shortcut**, and move the shortcut into the
folder that opened.

---

## Step 13 (optional): Install the local AI model

The home server can answer open questions ("Why should we pump water at
noon?") with a small AI model that runs **on the laptop**, without the
internet. Commands and status questions work without it.

1. Download **Ollama for Windows** from **https://ollama.com/download** and
   install it.
2. Open PowerShell and type:
   ```
   ollama pull llama3.2
   ```
   It downloads about 2 GB once. A laptop with 8 GB of memory or more is
   recommended.
3. Within a minute the app's **Twins** tab shows **LOCAL SLM llama3.2**.

---

## Step 14: Test it

**The real lamp:**
1. On the **Home** tab, scroll down to **Real device** and tap **Sitting room
   lamp**. Tap **TURN ON**:
   the lamp turns on (you may hear the relay click). Tap **TURN OFF**.
2. Wave your hand in front of the motion sensor. The **Motion** card changes.
3. Hold the blue voice button and say **"turn on the light"**.
   - On the **Android phone**, this works once microphone access is allowed.
   - On the **laptop**, it only works if the laptop has a microphone. If it
     says "Voice unavailable", use the buttons instead; everything else works
     the same.

**The whole house** (use the flask icon at the top of the app for demo
events):
1. On the **Home** tab, set **Whole-home mode** to **Assisted**.
2. Flask icon > **Grid outage**. The house switches to solar/battery by itself
   (a fail-safe, so it happens in every mode).
3. Flask icon > **Everyone leaves**, then **Arrive home**. The **Waiting for
   you** list asks to unlock the front door for you. Tap **APPROVE**: you are
   welcomed home, on the screen and in a spoken voice on the laptop.
4. Flask icon > **Kitchen fire**. The whole house responds together:
   - the siren sounds and the doors unlock;
   - the kitchen power is cut and the sprinkler starts;
   - the lights come on, including the real lamp;
   - an alert is sent over the 4G/5G backup (simulated).
5. Flask icon > **Clear all hazards**. Wait a few seconds, then tap **Reset
   alarm** and **Restore power**. Only a person can reset an alarm, and only
   once the hazard has cleared.
6. **Assistant** tab: ask "How is the house?" or "Turn on the bedroom light".

Setup is finished.

---

## Everyday use

- **Every day:**
  - Keep the laptop on and the home server running. Mosquitto starts by
    itself.
  - Keep the lamp board powered.
  - Open the SafeHome app on your Android phone (on home Wi-Fi) or from the
    **SafeHome** icon on the laptop's Desktop.
- **The app's five tabs:**
  - **Home:** alerts, anything waiting for your approval, energy, water and
    the six twins.
  - **Rooms:** a floor plan showing who is where and which lights are on,
    plus every device in each room.
  - **Twins:** each twin's AI principles, agents, mode and how far it has
    earned your trust.
  - **Assistant:** type or speak to the house.
  - **Activity:** the tamper-proof log of every decision.
- **Modes** (for the whole house on the Home tab, or per twin on the Twins
  tab):
  - **Manual:** you control everything. Every twin starts in this mode.
  - **Assisted:** twins suggest changes, and you approve or decline them.
  - **Autonomous:** a twin acts on its own only after it has graduated from
    **THRIFTOGENTIC** to **THRIFTONOMOUS**. To graduate, it needs enough
    approvals, a hazard test, a trial period and your sign-off. Until then,
    it keeps asking.
  - **Always, in every mode:**
    - Fail-safes run: switching to battery in a blackout, fire response,
      closing the water valve on a leak.
    - The Fire & Safety twin never acts alone.
    - Letting a stranger in always needs you.
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
| The app says **Not connected** | Check: the laptop is on and awake; `Get-Service mosquitto` shows `Running`; the username and password are correct. **Phone:** it's on home Wi-Fi and the address is the laptop IP. **Laptop:** the address is `localhost`. |
| App is **CONNECTED** but the cards stay empty and the lamp doesn't respond | The lamp isn't reaching the laptop. Check the board has power. If the laptop's IP changed, see the next row. |
| The laptop's IP address changed (after a router restart) | Do Step 5 again and enter the new address in the **phone** app (Step 11). The laptop app is fine, since it uses `localhost`. The lamp also has the old address saved, and it won't reopen SafeHome-Setup by itself in this case, so ask your developer to reset its setup. To stop this happening, ask whoever manages the router to give the laptop a **fixed (reserved) IP address** right after setup. |
| The app says **Home server offline** | On the laptop, start `safehome-server.exe` (Step 12) and leave its window open. The real lamp still works without it. |
| The server window says **broker refused the connection** | The username or password in `config.json` (next to the `.exe`) is wrong. Open it in Notepad, fix `username` and `password`, save, and start the server again. |
| The Assistant only answers simple questions | The local AI model isn't installed or Ollama isn't running. Do Step 13. |
| The voice button says "unavailable" | **Phone:** **Settings > Apps > SafeHome > Permissions > Microphone > Allow**. **Laptop:** check it has a microphone and that **Settings > Privacy & security > Microphone** allows desktop apps. |
| `Start-Service mosquitto` says **Failed to start service** | See **Mosquitto service won't start** below. |

### Mosquitto service won't start

On some laptops, Windows' Mosquitto service refuses to start even though
Mosquitto itself works. Do these in an **administrator** PowerShell window.

**A. Is Mosquitto already running?** An old copy started by hand keeps the
port busy, so the service can't start.
```
Get-Process mosquitto -ErrorAction SilentlyContinue
Get-NetTCPConnection -LocalPort 1883 -State Listen -ErrorAction SilentlyContinue
```
If either command prints a line, Mosquitto is already running, and you can
carry on. To use the permanent fix below instead, first run
`Stop-Process -Name mosquitto -Force`.

**B. Are the settings fine?**
```
cd "C:\Program Files\mosquitto"
.\mosquitto.exe -c mosquitto.conf -v
```
If it ends with `mosquitto version ... running`, the settings are fine. Press
**Ctrl+C** and do C. If it shows an error, send a screenshot to your
developer.

**C. Permanent fix: start Mosquitto with Windows another way.** Paste all of
this:
```
Set-Service mosquitto -StartupType Disabled
$action   = New-ScheduledTaskAction -Execute "C:\Program Files\mosquitto\mosquitto.exe" -Argument '-c "C:\Program Files\mosquitto\mosquitto.conf"' -WorkingDirectory "C:\Program Files\mosquitto"
$trigger  = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "SafeHome Mosquitto" -Action $action -Trigger $trigger -Settings $settings -User SYSTEM -RunLevel Highest -Force
Start-ScheduledTask -TaskName "SafeHome Mosquitto"
Start-Sleep 3
Get-NetTCPConnection -LocalPort 1883 -State Listen
```
**It worked if** the last command shows `1883` and `Listen`. Mosquitto now
starts by itself every time Windows starts, with no window to keep open.

To undo this later:
```
Unregister-ScheduledTask -TaskName "SafeHome Mosquitto" -Confirm:$false
Set-Service mosquitto -StartupType Automatic
```

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
- the **home server** (`safehome-server.exe`, built with PyInstaller so she
  doesn't need Python),
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
flutter build apk --release --no-tree-shake-icons
flutter build windows --release --no-tree-shake-icons
cd ..
```

- The **Android app** is created at
  `app\build\app\outputs\flutter-apk\app-release.apk`.
- The **Windows app** is created in `app\build\windows\x64\runner\Release\`.
  That whole folder is the app: `safehome_edge_ai.exe`, the `.dll` files and
  the `data` folder must stay together.

Before sending, check both reach **CONNECTED**: the APK on a test phone (with
the laptop IP), and the Windows app with `localhost`.

## 3. Build the home server

Double-click `server\build-server-exe.bat`. It runs the server tests first
and builds nothing if they fail. It creates `server\dist\safehome-server.exe`
(about 50 MB). To run the server from source while developing, use
`server\start-server.bat` instead (needs Python 3.11+).

## 4. Pack the kit

From the project folder:

```powershell
Remove-Item -Recurse -Force client-kit, safehome-client-kit.zip -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force client-kit\broker | Out-Null
Copy-Item app\build\app\outputs\flutter-apk\app-release.apk client-kit\safehome-edge-ai.apk
Copy-Item app\build\windows\x64\runner\Release client-kit\SafeHome -Recurse
Rename-Item client-kit\SafeHome\safehome_edge_ai.exe SafeHome.exe
Copy-Item server\dist\safehome-server.exe client-kit\
Copy-Item broker\mosquitto.conf client-kit\broker\
Copy-Item CLIENT_README.md client-kit\
Compress-Archive -Path client-kit\* -DestinationPath safehome-client-kit.zip -Force
```

This creates `safehome-client-kit.zip` (about 80 MB) containing:

```
safehome-client-kit.zip
├── CLIENT_README.md
├── safehome-edge-ai.apk
├── safehome-server.exe
├── SafeHome\
│   ├── SafeHome.exe
│   ├── flutter_windows.dll
│   ├── speech_to_text_windows_plugin.dll
│   └── data\
└── broker\
    └── mosquitto.conf
```

`client-kit/` and `*.zip` are in `.gitignore`, so they are never committed.

## 5. Send it to the client

The zip is about 80 MB, which is over the 25 MB email limit. Use one of these
instead:

- **Google Drive:** upload the zip, click **Share**, set **Anyone with the
  link**, and send her the link.
- **WeTransfer** (wetransfer.com): free up to 2 GB, no account needed.
- **USB flash drive:** copy the zip onto it and hand it over.
- **GitHub Release:** attach `safehome-client-kit.zip` to a release.

Tell her to start with **Part 1, Step 1** of `CLIENT_README.md`.
