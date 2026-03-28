import csv
import math

PAYLOAD_BYTES = 16
BYTES_PER_MB = 1_000_000  # decimal MB

FILES = {
    "enc_1": "data/timings_1_enc.txt",
    "enc_2": "data/timings_2_enc.txt",
    "dec_1": "data/timings_1_dec.txt",
    "dec_2": "data/timings_2_dec.txt",
}


def load_timings(path):
    transaction_us = []
    encrypt_us = []
    decrypt_us = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            transaction_us.append(float(row["transaction_us"]))
            encrypt_us.append(float(row["encrypt_us"]))
            decrypt_us.append(float(row["decrypt_us"]))
    if not transaction_us:
        raise ValueError(f"No rows found in {path}")
    return transaction_us, encrypt_us, decrypt_us


def mean_and_se(values):
    n = len(values)
    mean = sum(values) / n
    if n < 2:
        return mean, 0.0
    var = sum((x - mean) ** 2 for x in values) / (n - 1)  # sample variance
    std = math.sqrt(var)
    se = std / math.sqrt(n)
    return mean, se


def throughput_mb_s(mean_us):
    mean_s = mean_us / 1_000_000.0
    return (PAYLOAD_BYTES / mean_s) / BYTES_PER_MB


rows = []
for label, path in FILES.items():
    transaction_us, encrypt_us, decrypt_us = load_timings(path)
    mean_us, se_us = mean_and_se(transaction_us)
    tput = throughput_mb_s(mean_us)

    if label.startswith("enc"):
        overhead = [t - e for t, e in zip(transaction_us, encrypt_us)]
    else:
        overhead = [t - d for t, d in zip(transaction_us, decrypt_us)]

    overhead_mean, overhead_se = mean_and_se(overhead)
    rows.append((label, mean_us, se_us, tput, overhead_mean, overhead_se))

print(
    f"{'label':<6} {'mean_us':>12} {'se_us':>12} {'throughput_MB/s':>18} "
    f"{'overhead_us':>14} {'overhead_se':>12}"
)
for label, mean_us, se_us, tput, overhead_mean, overhead_se in rows:
    print(
        f"{label:<6} {mean_us:12.6f} {se_us:12.6f} {tput:18.9f} "
        f"{overhead_mean:14.6f} {overhead_se:12.6f}"
    )
