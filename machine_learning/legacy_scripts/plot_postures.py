import pandas as pd
import matplotlib.pyplot as plt
import glob
import os


DATA_FOLDER = "dataset"


files = glob.glob(
    os.path.join(DATA_FOLDER, "*.csv")
)


# Load all data
data = []

for file in files:

    df = pd.read_csv(file)

    # Keep only the important columns
    df = df[["timestamp", "ax", "ay", "az", "label"]]

    data.append(df)


data = pd.concat(data, ignore_index=True)


# Create separate plots for each posture
labels = sorted(data["label"].unique())


for label in labels:

    posture = data[data["label"] == label]

    plt.figure(figsize=(12, 5))

    plt.plot(
        posture["ax"].values,
        label="AX"
    )

    plt.plot(
        posture["ay"].values,
        label="AY"
    )

    plt.plot(
        posture["az"].values,
        label="AZ"
    )

    plt.title(f"IMU Data - {label}")

    plt.xlabel("Sample")
    plt.ylabel("Raw Accelerometer Value")

    plt.legend()

    plt.grid(True)

    plt.tight_layout()

    filename = f"{label}_plot.png"

    plt.savefig(filename)

    print(f"Saved: {filename}")

    plt.show()