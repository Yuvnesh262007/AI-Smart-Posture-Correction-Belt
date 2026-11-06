import csv
import time
from pathlib import Path

import serial

# ==============================
# Configuration
# ==============================
PORT = "COM9"
BAUD_RATE = 115200

# The dataset_wore folder must be beside this Python file.
DATASET_DIR = Path(__file__).resolve().parent / "dataset_wore"

COLUMNS = ["timestamp", "ax", "ay", "az"]

# Arduino warm-up is 120 seconds. Allow extra time for startup.
STARTUP_TIMEOUT = 240

POSTURES = {
    "1": "normal",
    "2": "slouch",
    "3": "lean_left",
    "4": "lean_right",
}

ALIASES = {
    "normal": "normal",
    "slouch": "slouch",
    "lean_left": "lean_left",
    "left": "lean_left",
    "lean left": "lean_left",
    "lean_right": "lean_right",
    "right": "lean_right",
    "lean right": "lean_right",
}


def parse_sensor_row(line):
    """Return four integer values if the line is valid sensor data."""
    parts = line.strip().split(",")

    if len(parts) != 4:
        return None

    try:
        return [int(part.strip()) for part in parts]
    except ValueError:
        return None


def is_csv_header(line):
    return line.strip().lower().replace(" ", "") == (
        "timestamp,ax,ay,az"
    )


def next_filename(posture):
    """Choose the next unused filename without overwriting data."""
    number = 1

    while True:
        path = DATASET_DIR / f"{posture}_{number}.csv"

        if not path.exists():
            return path

        number += 1


def wait_for_arduino(ser):
    """Ignore startup messages until the sensor stream begins."""
    print("\nWaiting for the Arduino's 2-minute countdown...")
    print("Keep the ESP32 connected. Please wait.")

    start = time.monotonic()
    next_update = start + 15

    while time.monotonic() - start < STARTUP_TIMEOUT:
        line = ser.readline().decode("utf-8", errors="ignore").strip()

        if is_csv_header(line):
            print("\nArduino countdown finished. Sensor stream ready.")
            return

        # If the header was missed, valid numeric rows prove
        # that collection has already started.
        if parse_sensor_row(line) is not None:
            print("\nSensor stream detected. Ready to record.")
            return

        now = time.monotonic()

        if now >= next_update:
            elapsed = int(now - start)
            print(f"Still waiting for sensor data... ({elapsed}s)")
            next_update = now + 15

    raise TimeoutError(
        "No sensor data received. Check the ESP32, COM port, "
        "and Arduino collector firmware."
    )


def choose_posture():
    print("\nWhich posture do you want to record?")
    print("1. Normal")
    print("2. Slouch")
    print("3. Lean left")
    print("4. Lean right")
    print("Q. Finish this session")

    choice = input("Choose 1-4 or Q: ").strip().lower()

    if choice in ("q", "quit", "done"):
        return None

    if choice in POSTURES:
        return POSTURES[choice]

    return ALIASES.get(choice)


def choose_duration():
    while True:
        value = input(
            "Recording duration in seconds [45]: "
        ).strip()

        if value == "":
            return 45

        try:
            seconds = int(value)

            if 5 <= seconds <= 600:
                return seconds

        except ValueError:
            pass

        print("Enter a whole number between 5 and 600.")


def record_posture(ser, posture, duration):
    DATASET_DIR.mkdir(parents=True, exist_ok=True)

    output_path = next_filename(posture)

    print(f"\nSelected posture: {posture.upper()}")
    print("Wear the belt in its final position.")
    print(f"Get into the {posture.replace('_', ' ')} posture.")
    input("When ready, press ENTER to start recording...")

    # Discard buffered readings gathered while you were preparing.
    ser.reset_input_buffer()

    samples = 0
    start = time.monotonic()

    try:
        with output_path.open(
            "w", newline="", encoding="utf-8"
        ) as csv_file:
            writer = csv.writer(csv_file)
            writer.writerow(COLUMNS)

            print(f"\nRecording {posture.upper()} for {duration} seconds.")

            while time.monotonic() - start < duration:
                line = ser.readline().decode(
                    "utf-8", errors="ignore"
                ).strip()

                row = parse_sensor_row(line)

                if row is not None:
                    writer.writerow(row)
                    samples += 1

                elapsed = time.monotonic() - start
                remaining = max(0, int(duration - elapsed))

                print(
                    f"\rTime remaining: {remaining:3d}s"
                    f" | Samples: {samples:5d}",
                    end="",
                    flush=True,
                )

    except KeyboardInterrupt:
        print("\nRecording interrupted. Saving collected samples.")

    print()
    print(f"Saved file: {output_path}")
    print(f"Samples recorded: {samples}")

    if samples == 0:
        print("WARNING: No samples were saved. Check sensor streaming.")


def main():
    DATASET_DIR.mkdir(parents=True, exist_ok=True)

    print("=" * 45)
    print("POSTURE BELT - WEARABLE DATA COLLECTOR")
    print("=" * 45)
    print(f"Dataset folder: {DATASET_DIR}")
    print(f"Serial port: {PORT} at {BAUD_RATE} baud")

    print("\nBefore continuing:")
    print("- Close Arduino Serial Monitor.")
    print("- Close any other program using COM9.")
    print("- Keep the ESP32 connected through USB.")
    input("\nPress ENTER when ready to connect...")

    try:
        with serial.Serial(
            PORT, BAUD_RATE, timeout=1
        ) as ser:
            # Opening the serial connection may restart the ESP32.
            time.sleep(2)

            wait_for_arduino(ser)

            print("\nYou can now record several postures.")
            print("The 2-minute countdown will not repeat")
            print("between recordings in this session.")

            while True:
                posture = choose_posture()

                if posture is None:
                    break

                if posture not in POSTURES.values():
                    print("Invalid posture. Please try again.")
                    continue

                duration = choose_duration()
                record_posture(ser, posture, duration)

    except serial.SerialException as error:
        print(f"\nSERIAL PORT ERROR: {error}")
        print("Check the COM port and close Arduino Serial Monitor.")

    except TimeoutError as error:
        print(f"\nSTARTUP ERROR: {error}")

    print("\nData collection session finished.")
    print(f"Files are in: {DATASET_DIR}")


if __name__ == "__main__":
    main()