// Combined hardware test: PIR + LDR + buzzer all running together, using the
// same pins as the real SafeHome firmware. The relay is left alone.
#define PIR_PIN        27
#define LDR_PIN        34   // module DO pin
#define LDR_POWER_PIN  32   // module VCC, switched on by this sketch
#define BUZZER_PIN     25
#define DO_HIGH_IS_DARK true

bool lastMotion = false;
bool lastDark = false;
bool started = false;

void beep(int ms) {
  digitalWrite(BUZZER_PIN, HIGH);
  delay(ms);
  digitalWrite(BUZZER_PIN, LOW);
}

void setup() {
  Serial.begin(115200);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  pinMode(PIR_PIN, INPUT);
  pinMode(LDR_POWER_PIN, OUTPUT);
  digitalWrite(LDR_POWER_PIN, HIGH);
  pinMode(LDR_PIN, INPUT);
  delay(500);
  Serial.println("All-sensors test. Wave at the PIR, cover/uncover the LDR.");
  beep(600);   // one long beep = buzzer works alongside everything else
}

void loop() {
  bool motion = digitalRead(PIR_PIN) == HIGH;
  bool dark = (digitalRead(LDR_PIN) == HIGH) == DO_HIGH_IS_DARK;

  if (!started) {
    lastMotion = motion;
    lastDark = dark;
    started = true;
  }

  if (motion && !lastMotion) {
    Serial.println(">>> MOTION detected  (1 beep)");
    beep(150);
  }
  if (!motion && lastMotion) {
    Serial.println("... motion ended");
  }
  if (dark != lastDark) {
    Serial.println(dark ? "*** light changed to DARK  (2 beeps)" : "*** light changed to BRIGHT  (2 beeps)");
    beep(100);
    delay(100);
    beep(100);
  }

  lastMotion = motion;
  lastDark = dark;
  delay(200);
}
