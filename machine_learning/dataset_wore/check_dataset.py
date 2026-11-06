import pandas as pd
import glob
import os
import re

# Path to the new wearable dataset folder
DATASET_DIR = "dataset_wore"

files = glob.glob(os.path.join(DATASET_DIR, "*.csv"))

print(f"\nFound {len(files)} CSV files\n")

if not files:
    print(f"No CSV files found in '{DATASET_DIR}'.")
    print("Check that the folder exists in your current working directory.")

else:
    all_data = []

    for file in sorted(files):

        df = pd.read_csv(file)

        print("=" * 50)
        print("FILE:", os.path.basename(file))
        print("Rows:", len(df))
        print("Columns:", list(df.columns))

        print("\nFirst 3 rows:")
        print(df.head(3))

        # Extract label from filename:
        # normal_1.csv -> normal
        # lean_left_2.csv -> lean_left
        filename = os.path.splitext(os.path.basename(file))[0]
        label = re.sub(r"_\d+$", "", filename).lower()

        # Add label column automatically
        df["label"] = label

        all_data.append(df)

    # Combine all files
    data = pd.concat(all_data, ignore_index=True)

    print("\n" + "=" * 50)
    print("COMBINED WEARABLE DATASET")
    print("=" * 50)

    print("\nTotal samples:", len(data))

    print("\nSamples per class:")
    print(data["label"].value_counts())

    print("\nMissing values:")
    print(data.isnull().sum())

    print("\nData types:")
    print(data.dtypes)

    print("\nBasic statistics:")
    print(data[["ax", "ay", "az"]].describe())

    print("\nDuplicate rows:", data.duplicated().sum())

    print("\nTotal duration per file (approximate):")

    for file in sorted(files):
        df = pd.read_csv(file)
        if len(df) > 1 and "timestamp" in df.columns:
            duration = (
                df["timestamp"].iloc[-1] -
                df["timestamp"].iloc[0]
            ) / 1000

            print(
                f"{os.path.basename(file)}: "
                f"{duration:.2f} seconds"
            )