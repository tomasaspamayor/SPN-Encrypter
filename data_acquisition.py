import secrets
import numpy as np
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

sns.set_style("whitegrid")
sns.set_context("paper", font_scale=1.6)


def generate_test_data(rows=100):
    keys = [secrets.token_hex(176) for _ in range(rows)]

    tester = []
    for i in range(rows):
        if i % 10 == 0:
            tester.append("0" * 352)
        elif i % 10 == 1:
            tester.append("f" * 352)
        else:
            tester.append(hex(i).split('x')[-1].zfill(352))

    tester_out = [secrets.token_hex(176) for _ in range(rows)]

    pd.Series(keys).to_csv("keys.txt", index=False, header=False)
    pd.Series(tester).to_csv("tester.txt", index=False, header=False)
    pd.Series(tester_out).to_csv("tester_out.txt", index=False, header=False)


def to_bin(hex_str):
    try:
        return bin(int(str(hex_str), 16))[2:].zfill(1408)
    except ValueError:
        return "0" * 1408


def calculate_hamming_distance(str1, str2):
    """
    Calculates the Hamming distance between two binary strings.
    """
    return sum(el1 != el2 for el1, el2 in zip(str1, str2))


def calculate_hamming_distance_percent(str1, str2):
    """
    Calculates Hamming distance as a percentage of total length.
    """
    if len(str1) != len(str2):
        raise ValueError("Binary strings must have the same length.")
    if len(str1) == 0:
        return 0.0
    dist = calculate_hamming_distance(str1, str2)
    return (dist / len(str1)) * 100.0


def hex_to_bin_any(hex_str):
    """
    Converts a hex string to a binary string without fixed padding.
    """
    hex_str = str(hex_str).strip()
    if not hex_str:
        return ""
    try:
        return bin(int(hex_str, 16))[2:].zfill(len(hex_str) * 4)
    except ValueError:
        raise ValueError("Invalid hex string.")


def load_ciphertext_file_hex(path):
    """
    Loads a ciphertext file with one hex string per line and concatenates.
    """
    series = pd.read_csv(path, header=None, dtype=str)[0].dropna()
    return "".join(series.tolist())


def hamming_distance_file_percent(file_a, file_b):
    """
    Computes Hamming distance percentage between two ciphertext files.
    """
    hex_a = load_ciphertext_file_hex(file_a)
    hex_b = load_ciphertext_file_hex(file_b)
    if len(hex_a) != len(hex_b):
        raise ValueError("Ciphertext files must have the same total length.")
    bin_a = hex_to_bin_any(hex_a)
    bin_b = hex_to_bin_any(hex_b)
    return calculate_hamming_distance_percent(bin_a, bin_b)


def hamming_distance_series_percent(file_paths):
    """
    Computes Hamming distance percentages for adjacent file pairs.
    """
    results = []
    for idx in range(len(file_paths) - 1):
        file_a = file_paths[idx]
        file_b = file_paths[idx + 1]
        percent = hamming_distance_file_percent(file_a, file_b)
        results.append((file_a, file_b, percent))
    return results


def plot_hamming_percentages(hamming_results, mean_percent, target_percent=50.0):
    """
    Plots Hamming distance percentages with target and mean reference lines.
    """
    labels = [f"{i+1}->{i+2}" for i in range(len(hamming_results))]
    percents = [percent for _, _, percent in hamming_results]

    plt.figure(figsize=(10, 5))
    plt.bar(labels, percents, color="#2a9d8f", alpha=0.8)
    plt.axhline(y=target_percent, color="#e76f51", linestyle="--",
                label=f"Target {target_percent:.0f}%")
    plt.axhline(y=mean_percent, color="#264653", linestyle="-",
                label=f"Mean {mean_percent:.2f}%")
    plt.title("Hamming Distance (% of Total File Size)")
    plt.xlabel("Adjacent Key Pair")
    plt.ylabel("Hamming Distance (%)")
    plt.legend()
    plt.tight_layout()
    plt.show()


def shannon_entropy_from_counts(counts):
    """
    Computes Shannon entropy from a count array.
    """
    total = np.sum(counts)
    if total == 0:
        return 0.0
    probs = counts[counts > 0] / total
    return float(-np.sum(probs * np.log2(probs)))


def positional_entropy_across_entries(hex_lines, unit="byte"):
    """
    Computes positional entropy across all entries by byte or nibble.
    """
    rows = []
    for line in hex_lines:
        line = line.strip()
        if not line:
            continue
        if unit == "byte":
            if len(line) % 2 != 0:
                raise ValueError("Hex line length must be even for bytes.")
            rows.append([int(line[i:i + 2], 16)
                        for i in range(0, len(line), 2)])
        elif unit == "nibble":
            rows.append([int(ch, 16) for ch in line])
        else:
            raise ValueError("unit must be 'byte' or 'nibble'.")

    if not rows:
        return []

    row_len = len(rows[0])
    if any(len(row) != row_len for row in rows):
        raise ValueError("All lines must have the same length.")

    max_symbols = 256 if unit == "byte" else 16
    entropies = []
    for pos in range(row_len):
        samples = [row[pos] for row in rows]
        counts = np.bincount(samples, minlength=max_symbols)
        entropies.append(shannon_entropy_from_counts(counts))
    return entropies


def plot_positional_entropy(entropies, max_entropy, unit_label):
    """
    Plots positional entropy across all entries for a given unit.
    """
    positions = list(range(len(entropies)))
    plt.figure(figsize=(12, 5))
    plt.plot(positions, entropies, color="#1f77b4", linewidth=2)
    plt.axhline(y=max_entropy, color="#e76f51", linestyle="--",
                label=f"Max {max_entropy:.0f} bits")
    plt.title(f"Positional Shannon Entropy per {unit_label}")
    plt.xlabel(f"{unit_label.title()} Position")
    plt.ylabel("Entropy (bits)")
    tick_step = 8 if unit_label == "byte" else 16
    plt.xticks(range(0, len(entropies), tick_step))
    plt.grid(True, axis="y", alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.show()


def hamming():
    key_files = [f"data/key{i}_enc.txt" for i in range(1, 11)]
    hamming_results = hamming_distance_series_percent(key_files)

    for file_a, file_b, percent in hamming_results:
        print(f"{file_a} vs {file_b}: {percent:.4f}%")

    percents = [percent for _, _, percent in hamming_results]
    if percents:
        mean_percent = float(np.mean(percents))
        se_percent = float(np.std(percents, ddof=1) /
                           np.sqrt(len(percents))) if len(percents) > 1 else 0.0
        print(f"Average Hamming distance: {mean_percent:.4f}%")
        print(f"Standard error: {se_percent:.4f}%")
        plot_hamming_percentages(
            hamming_results, mean_percent, target_percent=50.0)


def positional_entropy():
    with open("data/round_keys_history.txt", "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    byte_entropies = positional_entropy_across_entries(lines, unit="byte")
    if byte_entropies:
        plot_positional_entropy(
            byte_entropies, max_entropy=8.0, unit_label="byte")


if __name__ == "__main__":
    # hamming()
    positional_entropy()
