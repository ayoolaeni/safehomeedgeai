# Wiring Guide

Follow this once, with the ESP32 **unplugged from any power source**. Double
check everything before you plug in power.

## Pin map (must match `firmware/safehome_esp32/config.h`)

| Component | Pin on component | Connects to ESP32 |
|---|---|---|
| HC-SR501 PIR sensor | OUT | GPIO 27 |
| HC-SR501 PIR sensor | VCC | 5V |
| HC-SR501 PIR sensor | GND | GND |
| LDR light sensor module | DO (digital out) | GPIO 34 |
| LDR light sensor module | VCC | **GPIO 32** (the firmware switches it on to power the module) — or 3.3V if you have a free socket. **Never 5V**, see warning below |
| LDR light sensor module | GND | GND |
| Relay module | IN | GPIO 26 |
| Relay module | VCC | 5V |
| Relay module | GND | GND |
| Buzzer | + (positive leg, or VCC if it's a 3-pin module) | GPIO 25 |
| Buzzer | − (negative leg, or GND if it's a 3-pin module) | GND |

**⚠️ LDR voltage warning:** ESP32 input pins (GPIO34 included) can only
safely take up to 3.3V. The LDR module's DO output swings up to whatever
voltage you power the module from, so if you power it from 5V the DO pin
can put 5V onto GPIO34 and damage it. Power the LDR module's VCC from the
ESP32's **3.3V** pin, not 5V. The module still works fine at 3.3V.

**Setting the light/dark switch-over point:** your module only has a DO
(digital) output - a simple dark/bright signal. The small blue dial on the
module sets where it flips. In your normal room light the module's DO LED
should be **ON**, and when you cover the sensor with your hand it should
go **OFF**. If it doesn't, turn the dial a little at a time until it does.

## Step by step

1. **Place the ESP32 on the breadboard**, straddling the centre gap, so its
   two rows of pins are each on their own side.
2. **Wire the power rails.** Run a jumper from the ESP32's `5V` pin to the
   breadboard's red (+) rail, and from `GND` to the blue (−) rail. Run
   another jumper from the ESP32's `3.3V` pin to a *separate* strip or the
   other end of the rail if your board has two rail pairs — keep 5V and
   3.3V clearly separate so you don't accidentally feed 5V into the LDR.
3. **PIR sensor (HC-SR501):** VCC → 5V rail, GND → GND rail, OUT → GPIO27.
   It has 3 pins, usually labelled on the board.
4. **LDR module:** VCC → **GPIO32**, GND → GND rail, **DO → GPIO34**. The
   firmware sets GPIO32 HIGH at boot, which gives the module 3.3V (it only
   draws a few mA). If you ever have a free 3V3 socket you can use that
   instead - then set `LDR_POWER_FROM_GPIO` to `false` in `config.h`.
5. **Relay module:** VCC → 5V rail, GND → GND rail, IN → GPIO26.
   The relay's *other* side (screw terminals, separate from the 3 control
   pins) has three terminals: **COM**, **NO**, **NC**. You'll wire the lamp
   through COM and NO in the next step - leave NC alone.
6. **Buzzer:** if it's a bare 2-legged piezo buzzer, the legs aren't
   polarised the same way LEDs are but conventionally the longer leg is +.
   + leg → GPIO25, − leg → GND. If it's a 3-pin module (VCC/GND/I-O),
   VCC → 3.3V, GND → GND, I/O → GPIO25.
7. **Wire the lamp through the relay** (this is the only part that isn't
   just breadboard wiring):
   - Take your 5V USB power adapter's output and identify + and −.
   - Cut/interrupt the **positive (+)** wire between the adapter and the
     lamp. Connect the adapter's + to the relay's **COM** terminal, and the
     relay's **NO** terminal to the lamp's +.
   - Connect the adapter's − directly to the lamp's − (not through the
     relay), **and** to the same GND rail the ESP32 is using. Everything
     needs a common ground - this is what lets the ESP32 safely switch a
     separately-powered lamp.
   - Do NOT wire anything to mains electricity - this project is 5V DC
     only, as required by the spec.
8. **Double-check before powering on:**
   - No exposed wire is touching another exposed wire it shouldn't.
   - GND is shared between the ESP32, the relay, the buzzer, the PIR, the
     LDR, and the lamp's power adapter.
   - The LDR's VCC is on GPIO32 (or 3V3), and definitely not on 5V/VIN.
9. **Power up.** Plug the ESP32 into your laptop via USB. Separately plug in
   the 5V USB power adapter for the lamp circuit. Nothing should smoke or
   get hot. If the relay clicks the instant you power on and stays
   clicked, see the "Lamp is inverted" row in the README's troubleshooting
   table - that's just `RELAY_ACTIVE_LOW` needing to be flipped, not a
   wiring fault.

## What the push buttons and spare resistors are for

The current firmware does **not** use physical push buttons - manual on/off
is done from the phone app, per the dissertation's design. You can leave
any push buttons unwired. The 220Ω resistors aren't needed either: the PIR,
LDR and relay are all pre-built modules with their own onboard components.
If you'd like physical button support added as an extra feature, ask and
it can be added on top of the existing design.
