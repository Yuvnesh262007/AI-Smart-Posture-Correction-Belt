import pandas as pd
import numpy as np
import glob
import os

DATA_FOLDER = "dataset"

files = glob.glob(os.path.join(DATA_FOLDER, "*.csv"))

all_data = []

for file in files:
    df = pd.read_csv(file)

    # Acceleration magnitude
    df["acc_mag"] = np.sqrt(
        df["ax"]**2 +
        df["ay"]**2 +
        df["az"]**2
    )

    all_data.append(df)

data = pd.concat(all_data, ignore_index=True)

print("\n" + "=" * 70)
print("POSTURE DATA ANALYSIS")
print("=" * 70)

# ------------------------------------------------
# 1. Overall statistics
# ------------------------------------------------

print("\nAVERAGE SENSOR VALUES")
print("-" * 70)

print(
    data.groupby("label")[["ax", "ay", "az", "acc_mag"]]
    .mean()
    .round(2)
)

# ------------------------------------------------
# 2. Standard deviation
# ------------------------------------------------

print("\nSENSOR VARIATION")
print("-" * 70)

print(
    data.groupby("label")[["ax", "ay", "az", "acc_mag"]]
    .std()
    .round(2)
)

# ------------------------------------------------
# 3. Minimum values
# ------------------------------------------------

print("\nMINIMUM VALUES")
print("-" * 70)

print(
    data.groupby("label")[["ax", "ay", "az", "acc_mag"]]
    .min()
    .round(2)
)

# ------------------------------------------------
# 4. Maximum values
# ------------------------------------------------

print("\nMAXIMUM VALUES")
print("-" * 70)

print(
    data.groupby("label")[["ax", "ay", "az", "acc_mag"]]
    .max()
    .round(2)
)

# ------------------------------------------------
# 5. Range
# ------------------------------------------------

print("\nRANGE")
print("-" * 70)

ranges = data.groupby("label")[["ax", "ay", "az", "acc_mag"]].agg(
    lambda x: x.max() - x.min()
)

print(ranges.round(2))

# ------------------------------------------------
# 6. Median
# ------------------------------------------------

print("\nMEDIAN")
print("-" * 70)

print(
    data.groupby("label")[["ax", "ay", "az", "acc_mag"]]
    .median()
    .round(2)
)

print("\n" + "=" * 70)
print("ANALYSIS COMPLETE")
print("=" * 70)