import secrets
import numpy as np
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

sns.set_style("whitegrid")
sns.set_context("paper", font_scale=3.2)


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


def plot_hamming_percentages(hamming_results, mean_percent, target_percent=50.0, se_percent=0.0):
    """
    Plots Hamming distance percentages with target and mean reference lines.
    """
    labels = [f"{i+1}→{i+2}" for i in range(len(hamming_results))]
    percents = [percent for _, _, percent in hamming_results]

    plt.figure(figsize=(12, 5))

    # Alternate bar colors with labels
    single_flip_color = "#2a9d8f"
    multiple_flip_color = "#e76f51"
    colors = [single_flip_color if i % 2 == 0 else multiple_flip_color
              for i in range(len(labels))]

    bars = plt.bar(labels, percents, color=colors, alpha=0.8)

    # Add percentage labels on top of each bar
    for bar, percent in zip(bars, percents):
        height = bar.get_height()
        ax_temp = plt.gca()
        ax_temp.text(bar.get_x() + bar.get_width()/2., height,
                     f'{percent:.1f}%', ha='center', va='bottom', fontsize=21, weight='bold')

    # Add shaded region for ±1 standard error
    if se_percent > 0:
        plt.axhspan(mean_percent - se_percent, mean_percent + se_percent,
                    alpha=0.2, color="gray")

    plt.axhline(y=target_percent, color="#e76f51", linestyle="--",
                label=f"Target ({target_percent:.1f}%)")
    plt.axhline(y=mean_percent, color="#264653", linestyle="-", linewidth=2, alpha=0.8,
                label=f"Mean ({mean_percent:.2f}% ± {se_percent:.2f}%)")

    # Rescale y-axis so mean is in the middle
    plt.ylim(48.5, 52.5)
    plt.yticks(np.arange(48.5, 52.6, 0.5))

    # Add custom legend entries for bar colors and lines
    from matplotlib.patches import Patch
    legend_elements = [
        Patch(facecolor=single_flip_color, alpha=0.8, label="Single Bit Flip"),
        Patch(facecolor=multiple_flip_color,
              alpha=0.8, label="Multiple Bit Flips"),
        plt.Line2D([0], [0], color="#e76f51", linestyle="--",
                   label=f"Target ({target_percent:.1f}%)"),
        plt.Line2D([0], [0], color="#264653", linestyle="-", linewidth=2,
                   label=f"Mean ({mean_percent:.2f}% ± {se_percent:.2f}%)"),
    ]

    if se_percent > 0:
        legend_elements.append(
            Patch(facecolor="gray", alpha=0.2, label="±1 Standard Error"))

    plt.legend(handles=legend_elements, loc="upper right", ncol=2)

    plt.xlabel("Adjacent Key Pair", fontweight="bold")
    plt.ylabel("Hamming Distance (%)", fontweight="bold")
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
    fig, ax = plt.subplots(figsize=(14, 7))

    # Fill area under curve for visual appeal
    ax.fill_between(positions, entropies, alpha=0.25,
                    color="#2a9d8f", label="Entropy Distribution")

    # Main entropy line
    ax.plot(positions, entropies, color="#2a9d8f",
            linewidth=2.5, label="Positional Entropy")

    # Max entropy reference line
    ax.axhline(y=max_entropy, color="#e76f51", linestyle="--", linewidth=2.5, alpha=0.8,
               label=f"Maximum Entropy ({max_entropy:.1f} bits)")

    # Styling
    ax.set_xlabel(f"{unit_label.title()} Position",
                  fontsize=32, fontweight="bold")
    ax.set_ylabel("Entropy (bits)", fontsize=32, fontweight="bold")

    # Better grid
    ax.grid(True, alpha=0.5, linestyle="--", linewidth=1.2)
    ax.set_axisbelow(True)

    # X-axis ticks
    tick_step = 15
    ax.set_xticks(range(0, len(entropies), tick_step))
    ax.tick_params(axis="both", labelsize=20)

    # Y-axis formatting
    ax.set_ylim(0, max_entropy * 1.05)

    # Legend with better positioning
    ax.legend(loc="lower right", fontsize=28,
              framealpha=0.95, edgecolor="black")

    # Spines styling
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_linewidth(1.5)
    ax.spines["bottom"].set_linewidth(1.5)

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
            hamming_results, mean_percent, target_percent=50.0, se_percent=se_percent)


def positional_entropy():
    with open("data/round_keys_history.txt", "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    byte_entropies = positional_entropy_across_entries(lines, unit="byte")
    if byte_entropies:
        plot_positional_entropy(
            byte_entropies, max_entropy=8.0, unit_label="byte")


if __name__ == "__main__":
    hamming()
    # positional_entropy()
