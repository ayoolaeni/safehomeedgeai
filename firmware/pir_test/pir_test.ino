#define PIR_PIN 27

void setup() {
  Serial.begin(115200);
  pinMode(PIR_PIN, INPUT);
  Serial.println("PIR test starting. Warming up for 40 seconds...");
  delay(40000);
  Serial.println("Ready. Wave your hand at the sensor.");
}

void loop() {
  if (digitalRead(PIR_PIN) == HIGH) {
    Serial.println(">>> MOTION DETECTED <<<");
    delay(2000);
  } else {
    Serial.println("... no motion");
    delay(1000);
  }
}
