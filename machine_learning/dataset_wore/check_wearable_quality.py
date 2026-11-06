import pandas as pd
from pathlib import Path

folder = Path("dataset_wore")
files = sorted(folder.glob("*.csv"))

if not files:
    print("No CSV files found in dataset_wore.")
    raise SystemExit

print(f"Checking {len(files)} files\n")

total_rows = 0
total_duplicates = 0

for file in files:
    df = pd.read_csv(file)

    required = {"timestamp", "ax", "ay", "az"}
    if not required.issubset(df.columns):
        print(f"{file.name}: Invalid columns")
        continue

    timestamps = pd.to_numeric(
        df["timestamp"], errors="coerce"
    )

    intervals = timestamps.diff()
    negative = int((intervals < 0).sum())
    zero = int((intervals == 0).sum())
    large_gaps = int((intervals > 500).sum())

    duplicates = int(df.duplicated().sum())
    total_rows += len(df)
    total_duplicates += duplicates

    print("=" * 55)
    print("File:", file.name)
    print("Rows:", len(df))
    print("Exact duplicate rows:", duplicates)
    print("Backward timestamp jumps:", negative)
    print("Repeated timestamps:", zero)
    print("Gaps over 500 ms:", large_gaps)

    positive = intervals[intervals > 0]

    if not positive.empty:
        print(
            "Median sample interval:",
            f"{positive.median():.1f} ms"
        )
        print(
            "Largest positive interval:",
            f"{positive.max():.1f} ms"
        )

print("\n" + "=" * 55)
print("TOTAL ROWS:", total_rows)
print("TOTAL EXACT DUPLICATES:", total_duplicates)