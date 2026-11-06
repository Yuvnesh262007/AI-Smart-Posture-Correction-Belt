#include <Wire.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// =========================
// MPU6500
// =========================
#define MPU_ADDR 0x68

// =========================
// Vibration motor
// =========================
#define MOTOR_PIN 25

// =========================
// BLE
// =========================
#define SERVICE_UUID        "12345678-1234-1234-1234-123456789001"
#define CHARACTERISTIC_UUID "12345678-1234-1234-1234-123456789002"

BLECharacteristic *postureCharacteristic;

bool deviceConnected = false;


// =========================
// BLE connection callbacks
// =========================
class ServerCallbacks : public BLEServerCallbacks {

  void onConnect(BLEServer *server) {
    deviceConnected = true;
    Serial.println("BLE: PHONE CONNECTED");
  }

  void onDisconnect(BLEServer *server) {
    deviceConnected = false;
    Serial.println("BLE: PHONE DISCONNECTED");

    BLEDevice::startAdvertising();
  }
};


// =========================
// Read 16-bit MPU register
// =========================
int16_t read16() {

  byte highByte = Wire.read();
  byte lowByte = Wire.read();

  return (int16_t)((highByte << 8) | lowByte);
}


// =========================
// Send message to Flutter
// =========================
void sendBLE(String message) {

  if (deviceConnected) {

    postureCharacteristic->setValue(message.c_str());

    postureCharacteristic->notify();

    Serial.print("BLE SENT: ");
    Serial.println(message);
  }
}


// =========================
// Vibrate motor
// =========================
void vibrateMotor() {

  Serial.println("MOTOR: VIBRATE");

  digitalWrite(MOTOR_PIN, HIGH);

  delay(700);

  digitalWrite(MOTOR_PIN, LOW);

  Serial.println("MOTOR: OFF");
}


// =========================
// Setup
// =========================
void setup() {

  Serial.begin(115200);

  // -------------------------
  // I2C
  // -------------------------
  Wire.begin(21, 22);

  // Wake MPU6500
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0x01);
  Wire.endTransmission();

  delay(100);

  // Accelerometer range = ±4g
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x1C);
  Wire.write(0x08);
  Wire.endTransmission();

  delay(100);


  // -------------------------
  // Motor
  // -------------------------
  pinMode(MOTOR_PIN, OUTPUT);

  digitalWrite(MOTOR_PIN, LOW);


  // -------------------------
  // BLE
  // -------------------------
  BLEDevice::init("POSTURE_BELT");

  BLEServer *server = BLEDevice::createServer();

  server->setCallbacks(new ServerCallbacks());

  BLEService *service =
      server->createService(SERVICE_UUID);

  postureCharacteristic =
      service->createCharacteristic(
          CHARACTERISTIC_UUID,
          BLECharacteristic::PROPERTY_READ |
          BLECharacteristic::PROPERTY_WRITE |
          BLECharacteristic::PROPERTY_NOTIFY
      );

  postureCharacteristic->addDescriptor(
      new BLE2902()
  );

  postureCharacteristic->setValue(
      "POSTURE_BELT_READY"
  );

  service->start();


  // -------------------------
  // BLE advertising
  // -------------------------
  BLEAdvertising *advertising =
      BLEDevice::getAdvertising();

  advertising->addServiceUUID(
      SERVICE_UUID
  );

  advertising->setScanResponse(true);

  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);

  BLEDevice::startAdvertising();


  // -------------------------
  // Startup message
  // -------------------------
  Serial.println();
  Serial.println("==============================");
  Serial.println("AI POSTURE BELT READY");
  Serial.println("==============================");

  Serial.println("MPU6500: READY");
  Serial.println("Motor: READY");
  Serial.println("BLE: READY");
  Serial.println("Device: POSTURE_BELT");

  Serial.println("==============================");

  sendBLE("POSTURE_BELT_READY");

  Serial.println("timestamp,ax,ay,az");
}


// =========================
// Main loop
// =========================
void loop() {

  // =====================================================
  // 1. Receive commands from Python AI
  // =====================================================

  if (Serial.available()) {

    String command =
        Serial.readStringUntil('\n');

    command.trim();


    // -------------------------
    // Vibration command
    // -------------------------
    if (command == "VIBRATE") {

      vibrateMotor();
    }


    // -------------------------
    // Posture result from Python
    //
    // Example:
    // POSTURE|NORMAL|98.5
    //
    // or:
    // POSTURE|SLOUCH|94.2
    // -------------------------
    else if (command.startsWith("POSTURE|")) {

      int firstSeparator =
          command.indexOf('|');

      int secondSeparator =
          command.indexOf('|', firstSeparator + 1);


      if (firstSeparator != -1 &&
          secondSeparator != -1) {

        String posture =
            command.substring(
                firstSeparator + 1,
                secondSeparator
            );

        String confidence =
            command.substring(
                secondSeparator + 1
            );


        String bleMessage =
            "POSTURE:" +
            posture +
            ",CONFIDENCE:" +
            confidence;


        Serial.print("AI RESULT: ");
        Serial.println(bleMessage);


        // Send AI result to Flutter
        sendBLE(bleMessage);
      }
    }
  }


  // =====================================================
  // 2. Read MPU6500
  // =====================================================

  int16_t ax;
  int16_t ay;
  int16_t az;


  Wire.beginTransmission(MPU_ADDR);

  Wire.write(0x3B);

  Wire.endTransmission(false);

  Wire.requestFrom(
      MPU_ADDR,
      6,
      true
  );


  if (Wire.available() >= 6) {

    ax = read16();
    ay = read16();
    az = read16();


    // Send raw data to Python
    Serial.print(millis());

    Serial.print(",");

    Serial.print(ax);

    Serial.print(",");

    Serial.print(ay);

    Serial.print(",");

    Serial.println(az);
  }


  delay(50);
}