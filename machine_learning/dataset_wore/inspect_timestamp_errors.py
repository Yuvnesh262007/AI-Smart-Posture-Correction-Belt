import pandas as pd
from pathlib import Path

folder = Path("dataset_wore")

for path in sorted(folder.glob("*.csv")):
    df = pd.read_csv(path)

    if "timestamp" not in df.columns:
        continue

    ts = pd.to_numeric(df["timestamp"], errors="coerce")
    diff = ts.diff()

    bad = df.index[(diff <= 0) | (diff > 500)].tolist()

    if not bad:
        print(f"\n{path.name}: No timestamp anomalies found.")
        continue

    print(f"\n{'=' * 60}")
    print(f"FILE: {path.name}")
    print(f"Anomalies found: {len(bad)}")

    # Show the first three anomalies with surrounding rows.
    for idx in bad[:3]:
        start = max(0, idx - 2)
        end = min(len(df), idx + 3)

        print(f"\nRows around index {idx}:")
        print(df.iloc[start:end].to_string(index=True))

        print(f"Timestamp difference: {diff.iloc[idx]} ms")