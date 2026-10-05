#define LDR_POWER_PIN 32
#define LDR_DO_PIN    34

void setup() {
  Serial.begin(115200);
  pinMode(LDR_POWER_PIN, OUTPUT);
  digitalWrite(LDR_POWER_PIN, HIGH);   // D32 becomes our 3.3V supply
  pinMode(LDR_DO_PIN, INPUT);
  delay(500);
  Serial.println("LDR test. Cover the sensor with your hand.");
}

void loop() {
  int reading = digitalRead(LDR_DO_PIN);
  int analogValue = analogRead(LDR_DO_PIN);
  Serial.print("DO pin reads: ");
  Serial.print(reading == HIGH ? "HIGH" : "LOW");
  Serial.print("   analog: ");
  Serial.println(analogValue);
  delay(500);
}
