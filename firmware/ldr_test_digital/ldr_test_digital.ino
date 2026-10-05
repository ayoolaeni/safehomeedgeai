// Digital-only LDR test that mirrors how the real SafeHome firmware reads
// the module: DO on GPIO34, HIGH = dark. The module's VCC is on GPIO32,
// which this sketch switches on to power it - exactly like the firmware.
#define LDR_PIN 34
#define LDR_POWER_PIN 32
#define DO_HIGH_IS_DARK true

bool lastDark = false;
bool started = false;
unsigned long lastChangeMs = 0;

void setup() {
  Serial.begin(115200);
  pinMode(LDR_POWER_PIN, OUTPUT);
  digitalWrite(LDR_POWER_PIN, HIGH);
  pinMode(LDR_PIN, INPUT);
  delay(500);
  Serial.println("LDR digital test. Cover the sensor, then uncover it.");
}

void loop() {
  bool dark = (digitalRead(LDR_PIN) == HIGH) == DO_HIGH_IS_DARK;
  unsigned long now = millis();

  if (!started || dark != lastDark) {
    if (started) {
      Serial.print("*** CHANGED to ");
      Serial.println(dark ? "DARK ***" : "BRIGHT ***");
    }
    lastChangeMs = now;
    lastDark = dark;
    started = true;
  }

  Serial.print(dark ? "DARK   " : "BRIGHT ");
  Serial.print("(pin=");
  Serial.print(digitalRead(LDR_PIN) == HIGH ? "HIGH" : "LOW");
  Serial.print(", stable for ");
  Serial.print((now - lastChangeMs) / 1000.0, 1);
  Serial.println(" s)");
  delay(500);
}
