#define BUZZER_PIN 25

void setup() {
  Serial.begin(115200);
  pinMode(BUZZER_PIN, OUTPUT);
  Serial.println("Buzzer test. Listen for beeps.");
}

void loop() {
  Serial.println("BEEP");
  digitalWrite(BUZZER_PIN, HIGH);
  delay(300);

  digitalWrite(BUZZER_PIN, LOW);
  delay(1700);
}
