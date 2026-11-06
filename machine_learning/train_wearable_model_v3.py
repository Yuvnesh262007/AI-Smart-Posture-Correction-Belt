"""Train and evaluate a posture Random Forest from dataset_wore.

Expected CSV names: normal_1.csv, slouch_2.csv, lean_left_4.csv, etc.
Expected columns: timestamp, ax, ay, az

Training recordings: *_1.csv, *_2.csv, *_3.csv
Held-out evaluation recordings: *_4.csv
"""

from pathlib import Path
import re
import sys

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "dataset_wore"
MODEL_PATH = BASE_DIR / "posture_model_wearable_v3.pkl"

WINDOW_SIZE = 40          # ~2 seconds at 20 samples/sec
WINDOW_STEP = 20           # ~1 second between windows
MAX_INTERVAL_MS = 250      # never let a window cross a timing interruption
EXPECTED_LABELS = ["normal", "slouch", "lean_left", "lean_right"]

SIGNALS = ["ax", "ay", "az", "magnitude", "roll", "pitch"]
STAT_NAMES = ["mean", "std", "min", "max", "range"]
FEATURE_NAMES = [f"{sig}_{stat}" for sig in SIGNALS for stat in STAT_NAMES]


def label_from_filename(path: Path):
    match = re.fullmatch(r"(normal|slouch|lean_left|lean_right)_(\d+)\.csv", path.name.lower())
    return (match.group(1), int(match.group(2))) if match else (None, None)


def get_contiguous_segments(df: pd.DataFrame):
    """Split rows at non-increasing timestamps or gaps larger than 250 ms."""
    if df.empty:
        return []
    ts = df["timestamp"].to_numpy(dtype=np.int64)
    cuts = [0]
    for i in range(1, len(ts)):
        delta = int(ts[i]) - int(ts[i - 1])
        if delta <= 0 or delta > MAX_INTERVAL_MS:
            cuts.append(i)
    cuts.append(len(df))
    return [df.iloc[cuts[i]:cuts[i + 1]].reset_index(drop=True)
            for i in range(len(cuts) - 1) if cuts[i + 1] > cuts[i]]


def make_window_features(window: pd.DataFrame):
    ax = window["ax"].to_numpy(dtype=np.float64)
    ay = window["ay"].to_numpy(dtype=np.float64)
    az = window["az"].to_numpy(dtype=np.float64)

    magnitude = np.sqrt(ax * ax + ay * ay + az * az)
    roll = np.degrees(np.arctan2(ay, az))
    pitch = np.degrees(np.arctan2(-ax, np.sqrt(ay * ay + az * az)))

    arrays = [ax, ay, az, magnitude, roll, pitch]
    features = []
    for values in arrays:
        features.extend([
            float(np.mean(values)),
            float(np.std(values, ddof=0)),
            float(np.min(values)),
            float(np.max(values)),
            float(np.max(values) - np.min(values)),
        ])
    return features


def process_file(path: Path):
    label, recording_number = label_from_filename(path)
    if label is None:
        print(f"SKIP unexpected filename: {path.name}")
        return [], 0

    try:
        df = pd.read_csv(path)
    except Exception as exc:
        print(f"SKIP {path.name}: could not read CSV ({exc})")
        return [], 0

    required = ["timestamp", "ax", "ay", "az"]
    if not set(required).issubset(df.columns):
        print(f"SKIP {path.name}: expected columns {required}")
        return [], 0

    before = len(df)
    df = df[required].copy()
    for col in required:
        df[col] = pd.to_numeric(df[col], errors="coerce")
        df = df.dropna(subset=required)
    df = df.astype({col: "int64" for col in required})

    # Remove exact duplicate CSV rows, preserving their original order.
    df = df.drop_duplicates(subset=required, keep="first").reset_index(drop=True)
    after_dedup = len(df)

    windows = []
    segments = get_contiguous_segments(df)
    for segment in segments:
        if len(segment) < WINDOW_SIZE:
            continue
        for start in range(0, len(segment) - WINDOW_SIZE + 1, WINDOW_STEP):
            chunk = segment.iloc[start:start + WINDOW_SIZE]
            windows.append({
                "X": make_window_features(chunk),
                "y": label,
                "file": path.name,
                "recording": recording_number,
            })

    print(
        f"{path.name:18s} rows {before:4d} -> {after_dedup:4d} after dedup | "
        f"segments={len(segments):3d} | windows={len(windows):3d}"
    )
    return windows, before - after_dedup


def main():
    print("=" * 68)
    print("WEARABLE POSTURE DATASET — RANDOM FOREST V3")
    print("=" * 68)
    print(f"Dataset folder: {DATA_DIR}")
    print("Training: recording numbers 1, 2, 3")
    print("Evaluation: recording number 4 (held out per posture)")
    print(f"Window: {WINDOW_SIZE} samples, step {WINDOW_STEP}; features: {len(FEATURE_NAMES)}")
    print("Timestamp gaps / resets are segmented; exact duplicate rows are removed.")
    print()

    if not DATA_DIR.is_dir():
        print(f"ERROR: Dataset folder not found: {DATA_DIR}")
        print("Put this script beside the dataset_wore folder.")
        sys.exit(1)

    files = sorted(DATA_DIR.glob("*.csv"))
    matched = [(p, label_from_filename(p)) for p in files]
    matched = [(p, label, number) for p, (label, number) in matched if label is not None]
    if not matched:
        print("ERROR: No matching CSV files found (e.g. normal_1.csv).")
        sys.exit(1)

    all_windows = []
    duplicates_removed = 0
    for path, _, _ in matched:
        windows, removed = process_file(path)
        all_windows.extend(windows)
        duplicates_removed += removed

    train_rows = [w for w in all_windows if w["recording"] in (1, 2, 3)]
    test_rows = [w for w in all_windows if w["recording"] == 4]

    print("\n" + "=" * 68)
    print(f"Total windows: {len(all_windows)}")
    print(f"Exact duplicate rows removed: {duplicates_removed}")
    print(f"Training windows (recordings 1-3): {len(train_rows)}")
    print(f"Held-out test windows (recording 4): {len(test_rows)}")

    if not train_rows or not test_rows:
        print("\nERROR: Need training files _1/_2/_3 and held-out files _4.")
        print("Check filenames and ensure each class has enough continuous sensor data.")
        sys.exit(1)

    train_labels = set(w["y"] for w in train_rows)
    test_labels = set(w["y"] for w in test_rows)
    missing_train = set(EXPECTED_LABELS) - train_labels
    missing_test = set(EXPECTED_LABELS) - test_labels
    if missing_train or missing_test:
        print(f"\nERROR: Missing classes. Training missing={sorted(missing_train)}, test missing={sorted(missing_test)}")
        print("Keep one _4 file for each posture to evaluate independently.")
        sys.exit(1)

    X_train = np.asarray([w["X"] for w in train_rows], dtype=np.float64)
    y_train = np.asarray([w["y"] for w in train_rows])
    X_test = np.asarray([w["X"] for w in test_rows], dtype=np.float64)
    y_test = np.asarray([w["y"] for w in test_rows])

    print("\nTraining samples by class:")
    for label in EXPECTED_LABELS:
        print(f"  {label:12s}: {int(np.sum(y_train == label))}")
    print("Held-out samples by class:")
    for label in EXPECTED_LABELS:
        print(f"  {label:12s}: {int(np.sum(y_test == label))}")

    model = RandomForestClassifier(
        n_estimators=300,
        max_depth=15,
        min_samples_leaf=2,
        class_weight="balanced_subsample",
        random_state=42,
        n_jobs=-1,
    )
    model.fit(X_train, y_train)
    predictions = model.predict(X_test)

    print("\n" + "=" * 68)
    print("HELD-OUT EVALUATION — RECORDING _4 PER CLASS")
    print("=" * 68)
    print(f"Accuracy: {accuracy_score(y_test, predictions) * 100:.2f}%")
    print("\nClassification report:")
    print(classification_report(
        y_test, predictions, labels=EXPECTED_LABELS,
        target_names=EXPECTED_LABELS, zero_division=0, digits=3
    ))
    print("Confusion matrix (rows=actual, columns=predicted):")
    print(pd.DataFrame(
        confusion_matrix(y_test, predictions, labels=EXPECTED_LABELS),
        index=EXPECTED_LABELS, columns=EXPECTED_LABELS
    ))

    joblib.dump(model, MODEL_PATH)
    print(f"\nSaved model: {MODEL_PATH}")
    print(f"Feature count: {len(FEATURE_NAMES)}")
    print("Feature order:")
    print(", ".join(FEATURE_NAMES))
    print("\nIMPORTANT: This saved model uses these exact 30 window features.")
    print("The live inference script must calculate features in the same order.")
    print("This test uses separate _4 recordings; results may still vary in real-world use.")

if __name__ == "__main__":
    main()