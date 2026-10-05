// Tests the LED lamp powered THROUGH the relay: + rail -> relay COM,
// relay NO -> LED VCC, LED GND -> - rail, LED IN pin -> D33 (held HIGH
// the whole time, since that path is already proven working on its own).
// Only the relay (D26) is toggled, so the LED should switch on/off in
// step with it if the relay wiring is correct.
#define RELAY_PIN 26
#define LED_IN_PIN 33

void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(LED_IN_PIN, OUTPUT);
  digitalWrite(LED_IN_PIN, HIGH);   // LED's IN pin held on throughout
  Serial.println("Relay+LED test. LED IN pin held HIGH. Toggling relay only.");
}

void loop() {
  Serial.println("Relay -> ON  (LED should light if wiring is correct)");
  digitalWrite(RELAY_PIN, HIGH);
  delay(2500);

  Serial.println("Relay -> OFF (LED should go dark)");
  digitalWrite(RELAY_PIN, LOW);
  delay(2500);
}
