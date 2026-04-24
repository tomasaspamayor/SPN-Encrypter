"""
This module will implement the methods and functiones needed to
study the data collected throught the project. The plots shown
in the reports are generated with these functions.

It focuses on the two main analyses of the Hamming distance
(for the Strict Avalanche Criterion) and the Shannon entropy. For the
methods regarding the pictures, refer to the branch 'feat/bitmap'.
"""

import secrets
import numpy as np
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

from matplotlib import patheffects
from matplotlib.legend_handler import HandlerTuple

sns.set_style("whitegrid")
sns.set_context("paper", font_scale=1.6)


def generate_test_data(rows=100):
    """
    Generates test data for keys, tester, and tester_out files. Each file will contain `rows`
    lines of hex strings with 352 hex characters (1408 bits) each.

    Args:
        rows (int): The number of lines to generate for each file.
    """
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
    """
    Converts a hex string to a binary string, ensuring it is 1408 bits (352 hex characters) 
    long by padding with zeros if necessary.

    Args:
        hex_str (str): The input hex string.
    """
    try:
        return bin(int(str(hex_str), 16))[2:].zfill(1408)
    except ValueError:
        return "0" * 1408

def calculate_hamming_distance(str1, str2):
    """
    Calculates the Hamming distance between two binary strings.

    Args:
        str1 (str): First binary string.
        str2 (str): Second binary string.
    """
    return sum(el1 != el2 for el1, el2 in zip(str1, str2))

def calculate_hamming_distance_percent(str1, str2):
    """
    Calculates Hamming distance as a percentage of total length.

    Args:
        str1 (str): First binary string.
        str2 (str): Second binary string.
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

    Args:
        hex_str (str): The input hex string.
    """
    hex_str = str(hex_str).strip()
    if not hex_str:
        return ""
    try:
        return bin(int(hex_str, 16))[2:].zfill(len(hex_str) * 4)
    except ValueError as exc:
        raise ValueError("Invalid hex string.") from exc

def load_ciphertext_file_hex(path):
    """
    Loads a ciphertext file with one hex string per line and concatenates.

    Args:
        path (str): The path to the ciphertext file.
    """
    series = pd.read_csv(path, header=None, dtype=str)[0].dropna()
    return "".join(series.tolist())

def hamming_distance_file_percent(file_a, file_b):
    """
    Computes Hamming distance percentage between two ciphertext files.

    Args:
        file_a (str): Path to the first ciphertext file.
        file_b (str): Path to the second ciphertext file.
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
    Args:
        file_paths (list of str): List of file paths to compare in sequence.
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
    Plots Hamming distance percentages with a formal, academic grayscale aesthetic.
    Args:        
        hamming_results (list of tuples): Results from hamming_distance_series_percent.
        mean_percent (float): The average Hamming distance percentage across all pairs.
        target_percent (float): The ideal target Hamming distance percentage
        (default is 50% for random data).
    """
    labels = [f"{i+1} $\\to$ {i+2}" for i in range(len(hamming_results))]
    percents = [percent for _, _, percent in hamming_results]

    plt.rcParams['font.family'] = 'serif'
    _, ax = plt.subplots(figsize=(10, 5))

    std_dev = np.std(percents)
    sem = std_dev / np.sqrt(len(percents))

    target_line = ax.axhline(y=target_percent, color="black", linestyle="--",
                             linewidth=1, zorder=1, label=f"Ideal Target ({target_percent}%)")

    mean_line = ax.axhline(y=mean_percent, color="gray", linestyle="-", linewidth=1.5, zorder=1)
    uncertainty_span = ax.axhspan(mean_percent - sem, mean_percent + sem,
                                  color='lightgray', alpha=0.3, zorder=0)

    bars = ax.bar(labels, percents, color="#4D4D4D", edgecolor="black",
                  linewidth=1.2, width=0.7, zorder=2)

    for bar_val in bars:
        height = bar_val.get_height()
        t = ax.annotate(f'{height:.1f}%',
                        xy=(bar_val.get_x() + bar_val.get_width() / 2, height),
                        xytext=(0, 8),
                        textcoords="offset points",
                        ha='center', va='bottom',
                        fontsize=20, fontweight='bold', zorder=3)
        t.set_path_effects([patheffects.withStroke(linewidth=3, foreground='white')])

    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.grid(axis="y", linestyle=':', alpha=0.4, color='lightgray', zorder=0)
    ax.set_ylim(target_percent - 1, target_percent + 1)

    ax.set_title("Adjacent Hamming Distance Analysis", fontsize=40, pad=10)
    ax.set_xlabel("Adjacent Key Pair", fontsize=35)
    ax.set_ylabel("Hamming Distance (%)", fontsize=35)
    ax.tick_params(axis='both', labelsize=25)

    handles = [target_line, (mean_line, uncertainty_span)]
    labels_text = [f"Ideal Target ({target_percent}%)",
                   f"Calculated Mean ({mean_percent:.2f}% ± {sem:.2f}%)"]

    ax.legend(handles=handles,
              labels=labels_text,
              loc="upper right",
              frameon=False,
              fontsize=25,
              handler_map={tuple: HandlerTuple(ndivide=None)})

    plt.tight_layout()
    plt.show()

def shannon_entropy_from_counts(counts):
    """
    Computes Shannon entropy from a count array.

    Args:
        counts (array-like): An array of counts for each symbol.
    """
    total = np.sum(counts)
    if total == 0:
        return 0.0
    probs = counts[counts > 0] / total
    return float(-np.sum(probs * np.log2(probs)))

def positional_entropy_across_entries(hex_lines, unit="byte"):
    """
    Computes positional entropy across all entries by byte or nibble.

    Args:        
        hex_lines (list of str): List of hex strings to analyze.
        unit (str): "byte" for 8-bit positions, "nibble" for 4-bit positions.
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
    Plots positional entropy with a formal, academic grayscale aesthetic.

    Args:
        entropies (list of float): List of entropy values for each position.
        max_entropy (float): The theoretical maximum entropy for the given unit.
        unit_label (str): Label for the unit (e.g., "Byte" or "Nibble").
    """
    positions = list(range(len(entropies)))

    plt.rcParams['font.family'] = 'serif'

    _, ax = plt.subplots(figsize=(10, 4))
    ax.plot(positions, entropies, color="black", linewidth=1.2, label="Measured Entropy")

    ax.axhline(y=max_entropy, color="gray", linestyle=(0, (5, 5)),
                linewidth=1, label=f"Theoretical Max ({max_entropy:.0f} bits)")

    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)

    ax.tick_params(axis='both', which='major', labelsize=25)
    ax.set_title(f"Positional Shannon Entropy per Round Keys {unit_label}",
              fontsize=40,
              pad=10)
    ax.set_xlabel(f"{unit_label.title()} Position", fontsize=35)
    ax.set_ylabel("Entropy (bits)", fontsize=35)
    tick_step = 8 if unit_label == "byte" else 16
    ax.set_xticks(range(0, len(entropies), tick_step))
    ax.grid(axis="y", linestyle=':', alpha=0.6, color='lightgray')
    ax.legend(loc="lower right", frameon=False, fontsize=25)

    plt.tight_layout()
    plt.show()

# Main functions to run the analyses and generate plots.
# These wrap the previous functions into a singular workflow.

def hamming():
    """
    Computes and plots Hamming distances between key files.
    """
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

def shannon():
    """
    Computes and plots positional entropy for round keys from the history file.
    """
    with open("data/round_keys_history.txt", "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    byte_entropies = positional_entropy_across_entries(lines, unit="byte")
    if byte_entropies:
        plot_positional_entropy(
            byte_entropies, max_entropy=8.0, unit_label="Byte")


if __name__ == "__main__":
    hamming()
    shannon()
