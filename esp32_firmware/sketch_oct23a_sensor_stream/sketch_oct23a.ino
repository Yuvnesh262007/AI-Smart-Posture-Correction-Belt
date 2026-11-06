#include <Wire.h>

#define MPU_ADDR 0x68
#define SDA_PIN 21
#define SCL_PIN 22

int16_t read16() {
  uint8_t highByte = Wire.read();
  uint8_t lowByte = Wire.read();

  return (int16_t)((highByte << 8) | lowByte);
}

bool readAccel(int16_t &ax, int16_t &ay, int16_t &az) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);

  if (Wire.endTransmission(false) != 0) {
    return false;
  }

  if (Wire.requestFrom(MPU_ADDR, 6, true) != 6) {
    return false;
  }

  ax = read16();
  ay = read16();
  az = read16();

  return true;
}

void setup() {
  Serial.begin(115200);
  Wire.begin(SDA_PIN, SCL_PIN);

  // Wake up the MPU6500
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0x01);
  Wire.endTransmission();

  delay(100);

  // Set accelerometer range to +/-4g
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x1C);
  Wire.write(0x08);
  Wire.endTransmission();

  delay(100);

  // CSV header for Python
  Serial.println("timestamp,ax,ay,az");
}

void loop() {
  int16_t ax, ay, az;

  if (readAccel(ax, ay, az)) {
    Serial.print(millis());
    Serial.print(",");
    Serial.print(ax);
    Serial.print(",");
    Serial.print(ay);
    Serial.print(",");
    Serial.println(az);
  }

  // Approximately 20 samples per second
  delay(50);
}