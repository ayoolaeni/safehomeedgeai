# SafeHome setup guide (for non-technical users)

This guide takes you from an empty laptop and phone to a working smart lamp.
Follow the steps in order. Each step says what you're doing and what you
should see.

---

## What you need

- A **Windows laptop** that will stay on while you use the lamp.
- An **Android phone**.
- The **SafeHome lamp board** (already wired, as shown in `docs/WIRING.md`).
- A **USB cable that can carry data** for the board. Some cables only charge,
  so use one you know works.
- Your **home Wi-Fi name and password**, from the router.
- The **Google Chrome** or **Microsoft Edge** browser on the laptop.

## How the parts work together

- **The laptop** runs the *broker* (a free program called Mosquitto). It's a
  post office that passes messages between the phone and the lamp. The laptop
  must be on and connected to your Wi-Fi for the lamp to be controlled.
- **The lamp board** joins your home Wi-Fi and does the sensing and switching.
- **The phone** runs the SafeHome app and sends the commands.

All three must be on the **same home Wi-Fi**.

---

## Step 1: Get the project from GitHub

1. Open the project page: `https://github.com/ayoolaeni/safehomeedgeai`
   (your developer will give you the exact link).
2. Click the green **Code** button, then **Download ZIP**.
3. Right-click the ZIP and choose **Extract All**. Remember where the folder is.

You only need this folder for the lamp software step. Nothing else in it needs
to be opened.

## Step 2: Set up the broker on the laptop

1. Download **Mosquitto for Windows (64-bit)** from <https://mosquitto.org/download/>
   and run the installer. Keep the default options.
2. Open **PowerShell as administrator**: press the Windows key, type
   PowerShell, right-click it, and choose **Run as administrator**.
3. Create a username and password for the lamp and the phone. Keep the name
   `safehome` if you like:
   ```
   cd "C:\Program Files\mosquitto"
   .\mosquitto_passwd.exe -c passwd safehome
   ```
   Type a password when asked, then type it again. Write both down. The `-c`
   part is only used once.
4. If Windows asks about the firewall, allow access on **private networks**.

**Do not change Mosquitto's settings yet.** Step 7 does that.

## Step 3: Find the laptop's address

1. In PowerShell, type `hostname` and press Enter. This shows the laptop's
   name, for example `LAPTOP-SONIA`.
2. Type `ipconfig` and press Enter. Find the line **IPv4 Address** under your
   **Wi-Fi** connection, for example `192.168.1.20`.

You'll enter one of these in Steps 5 and 6. The IP address is more reliable.

## Step 4: Install the software on the lamp board (once)

1. Plug the lamp board into the laptop with the USB cable.
2. Open the install page in Chrome or Edge:
   **https://ayoolaeni.github.io/safehomeedgeai/flash/**
3. Click the blue **Install SafeHome lamp** button.
4. A window lists the boards it can find. Click the one named
   **USB-Enhanced-SERIAL CH9102** or **USB Serial**, then click **Connect**.
   If you're unsure which one, unplug the board and see which name disappears.
5. Click **Install**. Wait for the progress bar to finish, about 30 seconds.
6. When it says **Installation complete**, unplug the board and plug it in again.

**If the install fails:** unplug the board, plug it back in, and try again. Make
sure no other program is using the board.

## Step 5: Connect the lamp board to your home Wi-Fi

1. Plug the lamp board in. With nothing saved yet, it creates its own Wi-Fi
   network called **SafeHome-Setup**.
2. On your **phone**, open Wi-Fi settings and connect to **SafeHome-Setup**.
   The password is **safehome-setup**.
3. Open the phone's web browser and go to **http://192.168.4.1**. A setup page
   opens.
4. Fill in the page:
   - **Your home Wi-Fi name:** choose it from the list. If it's missing, tap
     **Scan again**.
   - **Wi-Fi password:** your home Wi-Fi password. Type it carefully.
   - **Laptop name or IP address:** from Step 3.
   - **Broker username and password:** from Step 2. Leave blank if you didn't
     set them.
5. Tap **Save and connect**. The lamp restarts and joins your home Wi-Fi in
   about 20 seconds.
6. Reconnect your phone to your **home Wi-Fi**.

**If the lamp can't join within about 3 minutes**, it opens the setup page
again by itself. Check the Wi-Fi password, then repeat this step.

## Step 6: Install the phone app

1. On the project's GitHub page, click **Releases**, then download
   **safehome-edge-ai.apk** from the newest release. Your developer creates
   this release.
2. Open the file on the phone. If Android asks, allow **install from this
   source** for the app you opened it from.
3. Tap **Install**, then **Open**.
4. Allow microphone access when asked, so the voice button works.

In the app, tap the **laptop** card and enter:
- **Laptop name or IP address:** from Step 3.
- **Broker username and password:** from Step 2.

The status should change to **CONNECTED**.

## Step 7: Lock the broker

Only after the lamp and phone are connected (Steps 5 and 6):

1. Copy the file `broker\mosquitto.conf` from the project into
   `C:\Program Files\mosquitto\`, replacing the existing `mosquitto.conf`.
2. Restart the broker in PowerShell as administrator:
   ```
   Restart-Service mosquitto
   ```
3. Check the phone still shows **CONNECTED**. Now only people with the
   username and password can reach the broker.

---

## Using the lamp

- **Turn it on or off:** tap the buttons in the app, or hold the voice button
  and say "turn on the light" or "turn off the light".
- **Modes:**
  - **Manual:** you control the lamp. It always starts in this mode.
  - **Assisted:** the lamp suggests changes, and you approve or decline them.
  - **Autonomous:** the lamp acts on its own, once it has earned that. Until
    then, it keeps asking.
- **Changing the Wi-Fi later:** tap the **Wi-Fi** card in the app and pick
  another network. This only works in Manual mode. If the lamp can't reach the
  laptop on the new network within a minute, it goes back to the old one.

## Starting over

To run the setup page again, you need to reset the board's Wi-Fi memory. Ask
your developer, or see the developer notes in the README.

## Troubleshooting

| What you see | What to do |
| --- | --- |
| The install page's button doesn't appear | Open the page in Chrome or Edge, not Firefox. |
| No board appears in the install window | Use a different USB cable, or a different USB port on the laptop. |
| No SafeHome-Setup network appears | Unplug the board, wait 30 seconds, and plug it back in. |
| The setup page doesn't open | Check the phone is on SafeHome-Setup, then type http://192.168.4.1 yourself. |
| The app says DISCONNECTED | Check the laptop is on, Mosquitto is running, the phone is on home Wi-Fi, and the laptop address and login are correct. |
| The lamp doesn't respond | Check the laptop is on and the board is on home Wi-Fi. |
| The laptop's address changed | Enter the new address in the app. To avoid this, set a fixed address for the laptop in the router's settings. |
| The voice button says "unavailable" | Allow microphone access for SafeHome in the phone's settings. Voice works on the phone only. |

## Security notes

- The broker login stops strangers on your Wi-Fi from controlling the lamp.
- Messages are not encrypted. Someone with access to your home network could
  read them. This is a limitation of this prototype.
- Keep your Wi-Fi and broker passwords private.
