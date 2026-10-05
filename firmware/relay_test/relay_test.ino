#define RELAY_PIN 26

void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  Serial.println("Relay test. Listen for clicks.");
}

void loop() {
  Serial.println("Relay -> ON");
  digitalWrite(RELAY_PIN, HIGH);
  delay(2000);

  Serial.println("Relay -> OFF");
  digitalWrite(RELAY_PIN, LOW);
  delay(2000);
}
