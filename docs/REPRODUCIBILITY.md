# Reproducibility and project notes

- Python version reported by the development environment: 3.13.14.
- ML package versions are pinned in `machine_learning/requirements.txt`.
- Final data folder: `machine_learning/dataset_wore/` (16 CSV recordings, four classes).
- Final saved model: `machine_learning/posture_model_wearable_v3.pkl`.
- Training split: recordings `_1`, `_2`, `_3`; held-out evaluation: `_4`.
- Model: RandomForestClassifier with 300 estimators, maximum depth 15 and minimum leaf size 2.
- Feature extraction: 30 statistics from ax, ay, az, acceleration magnitude, roll and pitch.
- Window size: 40 samples; step: 20 samples.
- The checked runtime parser expects five fields, while the checked candidate ESP32 sketches
  emit four fields. Resolve/verify this before claiming a reproducible live run.
