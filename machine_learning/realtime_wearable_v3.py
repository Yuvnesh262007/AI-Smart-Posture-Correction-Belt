"""Real-time inference for posture_model_wearable_v3.pkl.

Reads the 5-column ESP32 runtime stream, calculates the exact 30 features
used by train_wearable_model_v3.py, then sends confirmed classifications back
as POSTURE|LABEL|CONFIDENCE over the same COM port. The ESP32 relays them over
BLE and controls the vibration motor.
"""
from collections import deque, Counter
from pathlib import Path
import time
import sys

import joblib
import numpy as np
import serial

BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "posture_model_wearable_v3.pkl"
PORT = "COM9"
BAUD_RATE = 115200
WINDOW_SIZE = 40
WINDOW_STEP = 20
MAX_INTERVAL_MS = 250
CONFIDENCE_THRESHOLD = 0.70
CONFIRMATION_COUNT = 3
HEARTBEAT_SECONDS = 1.0
LABELS = {"normal": "NORMAL", "slouch": "SLOUCH",
          "lean_left": "LEAN_LEFT", "lean_right": "LEAN_RIGHT"}


def make_features(rows):
    """Feature order must exactly match train_wearable_model_v3.py."""
    arr = np.asarray(rows, dtype=np.float64)
    ax, ay, az = arr[:, 0], arr[:, 1], arr[:, 2]
    magnitude = np.sqrt(ax * ax + ay * ay + az * az)
    roll = np.degrees(np.arctan2(ay, az))
    pitch = np.degrees(np.arctan2(-ax, np.sqrt(ay * ay + az * az)))
    signals = [ax, ay, az, magnitude, roll, pitch]
    features = []
    for values in signals:
        features.extend([
            float(np.mean(values)),
            float(np.std(values, ddof=0)),
            float(np.min(values)),
            float(np.max(values)),
            float(np.max(values) - np.min(values)),
        ])
    return np.asarray(features, dtype=np.float64).reshape(1, -1)


def parse_sensor_line(line):
    """Accept only sample_id,timestamp,ax,ay,az sensor rows."""
    parts = line.strip().split(",")
    if len(parts) != 5:
        return None
    try:
        sample_id, timestamp, ax, ay, az = (int(p.strip()) for p in parts)
        return sample_id, timestamp, (ax, ay, az)
    except ValueError:
        return None


def main():
    print("=" * 62)
    print("POSTURE BELT — REAL-TIME RANDOM FOREST V3")
    print("=" * 62)
    print(f"Model: {MODEL_PATH}")
    print(f"Serial: {PORT} at {BAUD_RATE} baud")
    print("Window: 40 samples (~2 seconds), step: 20 (~1 second)")
    print("Close Arduino Serial Monitor before continuing.")

    if not MODEL_PATH.is_file():
        print("ERROR: Model file not found.")
        print("Expected posture_model_wearable_v3.pkl beside this script.")
        sys.exit(1)

    model = joblib.load(MODEL_PATH)
    expected_features = getattr(model, "n_features_in_", None)
    if expected_features != 30:
        print(f"ERROR: Expected a 30-feature model, got {expected_features}.")
        sys.exit(1)

    samples = deque(maxlen=WINDOW_SIZE)
    last_sample_id = None
    last_timestamp = None
    samples_since_prediction = 0
    recent_predictions = deque(maxlen=CONFIRMATION_COUNT)
    current_sent_label = None
    last_sent_at = 0.0
    last_display_at = 0.0
    windows_seen = 0

    try:
        with serial.Serial(PORT, BAUD_RATE, timeout=1, write_timeout=1) as ser:
            # USB serial opening may reset the ESP32. Allow it to boot.
            time.sleep(2)
            ser.reset_input_buffer()
            print("Connected. Waiting for valid sensor samples...")
            print("Wear the belt securely; keep your posture natural.")

            while True:
                raw = ser.readline().decode("utf-8", errors="ignore").strip()
                parsed = parse_sensor_line(raw)
                if parsed is None:
                    continue

                sample_id, timestamp, xyz = parsed

                # Skip exact repeats. A reset of sample_id or timestamp starts
                # a fresh segment so no feature window crosses a restart/gap.
                if last_sample_id is not None and sample_id == last_sample_id:
                    continue
                if last_timestamp is not None:
                    dt = timestamp - last_timestamp
                    if sample_id <= last_sample_id or dt <= 0 or dt > MAX_INTERVAL_MS:
                        samples.clear()
                        recent_predictions.clear()
                        samples_since_prediction = 0
                        last_sample_id = None
                        last_timestamp = None
                        print("[INFO] Sensor stream reset/gap; buffer cleared.")
                        # Treat current row as first row of fresh segment.

                last_sample_id = sample_id
                last_timestamp = timestamp
                samples.append(xyz)
                samples_since_prediction += 1

                if len(samples) < WINDOW_SIZE:
                    continue
                if samples_since_prediction < WINDOW_STEP:
                    continue
                samples_since_prediction = 0

                features = make_features(list(samples))
                probabilities = model.predict_proba(features)[0]
                best_idx = int(np.argmax(probabilities))
                label = str(model.classes_[best_idx]).lower()
                confidence = float(probabilities[best_idx])
                windows_seen += 1

                if confidence < CONFIDENCE_THRESHOLD:
                    recent_predictions.clear()
                    shown_label = "UNCERTAIN"
                else:
                    recent_predictions.append(label)
                    shown_label = label.upper()

                now = time.monotonic()
                if now - last_display_at >= 0.8:
                    print(f"Prediction: {shown_label:10s} | Confidence: {confidence * 100:5.1f}% | windows: {windows_seen}")
                    last_display_at = now

                # Require three consecutive confident windows before sending.
                if (len(recent_predictions) == CONFIRMATION_COUNT and
                        len(set(recent_predictions)) == 1):
                    confirmed_label = recent_predictions[-1]
                    outbound_label = LABELS.get(confirmed_label)
                    if outbound_label is None:
                        continue

                    changed = outbound_label != current_sent_label
                    heartbeat_due = (now - last_sent_at) >= HEARTBEAT_SECONDS
                    if changed or heartbeat_due:
                        message = f"POSTURE|{outbound_label}|{confidence * 100:.1f}\n"
                        ser.write(message.encode("ascii"))
                        ser.flush()
                        current_sent_label = outbound_label
                        last_sent_at = now
                        print(f"  -> ESP32/BLE: {message.strip()}")

    except serial.SerialException as exc:
        print(f"SERIAL ERROR: {exc}")
        print("Check the ESP32 COM port and close Arduino Serial Monitor.")
    except KeyboardInterrupt:
        print("\nStopped by user.")


if __name__ == "__main__":
    main()
    
