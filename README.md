# AI-Enabled Smart Posture Correction Belt

An academic wearable posture-monitoring prototype combining an ESP32, an MPU6500-family
accelerometer module, a Python Random Forest classification pipeline, Bluetooth Low Energy
(BLE), a Flutter Android application and a custom 3D-printed enclosure.

> **Repository status:** assembled from the project files identified in the development
> workspace. This repository is initially intended to remain private while the team checks
> institutional intellectual-property and dataset-sharing permissions.

## Project overview

The system records upper-body movement using accelerometer readings. The V3 machine-learning
pipeline derives 30 statistical features from overlapping 40-sample windows and classifies
four posture categories:

- `normal`
- `slouch`
- `lean_left`
- `lean_right`

The checked real-time architecture uses USB Serial between the ESP32 and a host Python process.
The ESP32 firmware candidate also provides a BLE service used by the Flutter application to
receive posture notifications. The application presents posture feedback and includes history
and analysis UI.

The prototype was USB-powered during the documented project stage. Battery-powered operation
should not be claimed as completed unless subsequently verified.

## High-level architecture

```text
MPU6500-family IMU
        |
        v
ESP32 development board
        |  USB Serial sensor stream
        v
Python V3 inference process
        |  Random Forest prediction
        |  POSTURE|LABEL|CONFIDENCE
        v
ESP32 BLE firmware
        |  BLE notifications
        v
Flutter Android application
        |
        +-- posture feedback
        +-- history / analysis interface
```

The firmware contains GPIO-based vibration-motor control. The October 7 sketch accepts a
`VIBRATE` Serial command. The checked `realtime_wearable_v3.py` sends posture-classification
messages; it does not itself send a `VIBRATE` command. Treat automatic vibration triggering
as requiring separate integration verification.

## Machine-learning pipeline

The final dataset is in `machine_learning/dataset_wore/` and contains 16 CSV recordings:
four recordings per posture class. Each CSV contains `timestamp,ax,ay,az`; the class is
derived from the filename.

The V3 training script:

- uses recordings `_1`, `_2` and `_3` for training;
- holds out recording `_4` for evaluation for each class;
- uses 40 samples per window and a 20-sample step;
- calculates 30 features from acceleration axes, magnitude, roll and pitch;
- splits at timestamp resets/non-increasing values and gaps greater than 250 ms;
- removes exact duplicate sensor rows.

The recorded project evaluation was 100% accuracy on the held-out `_4` recordings in this
dataset. This is a result on the collected dataset, not a guarantee of performance on
new users, devices or real-world conditions.

### Python environment

The development environment reported Python 3.13.14 and the versions pinned in
`machine_learning/requirements.txt`.

```powershell
cd machine_learning
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

To retrain the model:

```powershell
python train_wearable_model_v3.py
```

This regenerates `posture_model_wearable_v3.pkl`. The runtime inference script loads that
model from the same directory.

### Running live inference

Before running `realtime_wearable_v3.py`:

1. Connect the ESP32 to the computer.
2. Close Arduino Serial Monitor and any other program using the serial port.
3. Change `PORT = "COM9"` in the Python script to the ESP32's actual port.
4. Verify that the firmware sends the exact five-column format expected by
   `parse_sensor_line`: `sample_id,timestamp,ax,ay,az`.

**Known protocol mismatch:** the checked October 7 and October 23 candidate sketches emit
four fields (`timestamp,ax,ay,az`), while the checked V3 inference parser requires five.
The firmware candidates are preserved as historical files and are not claimed to be
directly compatible with the current V3 parser. Confirm the firmware revision or reconcile
the serial protocol before running live inference.

## Flutter application

The Flutter source is in `flutter_app/`.

```powershell
cd flutter_app
flutter pub get
flutter run
```

The app source includes the dashboard, BLE scan/connection flow, posture feedback character,
and history/analysis interface. Device permissions and BLE compatibility depend on the
Android device and Flutter plugin configuration.

## ESP32 firmware

Historical firmware candidates are in `esp32_firmware/`. See
[`esp32_firmware/README.md`](esp32_firmware/README.md) for their roles and known protocol notes.
The project uses the BLE device name `POSTURE_BELT` and the following service/characteristic
UUIDs in the checked October 7 sketch:

- Service: `12345678-1234-1234-1234-123456789001`
- Characteristic: `12345678-1234-1234-1234-123456789002`

## Hardware and CAD

The `hardware/CAD/` folder contains STEP files, STL print exports, and GLB assembly
visualisations for the main enclosure, battery cradle/lid and motor mount. See
[`hardware/CAD/README.md`](hardware/CAD/README.md) for design notes.

The presence of a battery enclosure CAD file does not indicate that battery operation was
completed in the evaluated prototype.

## Important limitations and reproducibility notes

- The held-out evaluation uses four `_4` recordings from the collected dataset. Broader
  testing with additional participants and recording sessions is needed.
- The checked V3 runtime parser and checked ESP32 candidate sketches have different CSV
  field counts; verify the serial protocol before running the live pipeline.
- The COM port is machine-specific and must be configured locally.
- The legacy analysis scripts are stored separately under
  `machine_learning/legacy_scripts/`; they target the earlier `dataset` format and are not
  part of the V3 wearable pipeline.
- Do not commit personal credentials, Android signing keys, private tokens or local IDE
  configuration.

## Intellectual property and licensing

This repository is intended to remain private pending confirmation of the team's and
institution's rights to publish the invention, CAD files and recorded dataset. No open-source
license is included. Do not make the repository public or add a license until the appropriate
team/institutional approval has been obtained.

## Team

Developed as a B.Tech Engineering Clinics project at CGC University, Mohali.

Team: Yuvnesh Kumar Garg, Yash Sharma, Yugvender Sharma and Lakshay.
