# ESP32 firmware sketches and protocol notes

The sketches are kept as separate historical candidates. The project owner could not confirm
which sketch was flashed during the final evaluation, so none is labelled as the verified
final demonstration firmware.

- `sketch_oct7a_ble_candidate`: MPU6500 accelerometer readout, BLE service/characteristic,
  and GPIO 25 vibration command handling.
- `sketch_oct23a_sensor_stream`: MPU6500 accelerometer CSV stream over USB Serial.
- `sketch_sep26a_motor_test`: basic GPIO 0 vibration-motor test.

## Serial protocol compatibility warning

The checked `realtime_wearable_v3.py` parser expects five comma-separated integers:
`sample_id,timestamp,ax,ay,az`.

The checked October 7 and October 23 sketches print four CSV fields:
`timestamp,ax,ay,az`. Therefore these checked sketches are not directly compatible with
the checked V3 real-time parser without a matching firmware/protocol revision.

Verify the actual flashed firmware and serial format before attempting live inference.
Do not assume that the motor is automatically triggered by the Python V3 script: the
October 7 firmware accepts a `VIBRATE` serial command, but the checked V3 inference
script sends `POSTURE|...` messages and does not itself send `VIBRATE`.
