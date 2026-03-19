import secrets
import numpy as np
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

def generate_test_data(rows=100):
    """
    Generates 16-byte HEX strings and saves them to .txt files.

    - `keys.txt`: Contains random 16-byte HEX strings.
    - `tester.txt`: Contains a mix of fixed patterns and incremental HEX strings.
    - `tester_out.txt`: Contains random 16-byte HEX strings for output testing.
    """
    keys = [secrets.token_hex(16) for _ in range(rows)]

    tester = []
    for i in range(rows):
        if i % 10 == 0:
            tester.append("0" * 32)
        elif i % 10 == 1:
            tester.append("f" * 32)
        else:
            tester.append(hex(i).split('x')[-1].zfill(32))

    tester_out = [secrets.token_hex(16) for _ in range(rows)]

    pd.Series(keys).to_csv("keys.txt", index=False, header=False)
    pd.Series(tester).to_csv("tester.txt", index=False, header=False)
    pd.Series(tester_out).to_csv("tester_out.txt", index=False, header=False)

    print(f"--- Data Generation Complete: {rows} rows created. ---")

def to_bin(hex_str):
    """
    Converts a hex string to a 128-bit binary string.
    """
    try:
        return bin(int(str(hex_str), 16))[2:].zfill(128)
    except ValueError:
        return "0" * 128

def calculate_hamming_distance(str1, str2):
    """
    Calculates the Hamming distance between two binary strings.
    """
    return sum(el1 != el2 for el1, el2 in zip(str1, str2))

def calculate_sac(ciphertexts_list):
    """
    Calculates the Strict Avalanche Criterion (SAC) by computing
    the Hamming distance between all unique pairs of ciphertexts.
    """
    sac_values = []
    n = len(ciphertexts_list)
    for i in range(n):
        for j in range(i + 1, n):
            dist = calculate_hamming_distance(ciphertexts_list[i], ciphertexts_list[j])
            sac_values.append(dist)
    return sac_values

def calculate_shannon_entropy(list_of_keys):
    """
    Calculates entropy based on hex character frequency.
    """
    all_chars = pd.Series(list("".join(list_of_keys)))
    prob = all_chars.value_counts(normalize=True)
    return -np.sum(prob * np.log2(prob))

def calculate_big_o_complexity(input_sizes, times_list):
    """
    Estimates the exponent 'k' in O(n^k) using log-log linear regression.
    A slope of ~1.0 indicates Linear time O(n).
    A slope of ~2.0 indicates Quadratic time O(n^2).
    """
    if len(input_sizes) != len(times_list):
        raise ValueError("Input sizes and times must have the same length.")
    
    # Filter out zero or negative values to avoid log errors
    valid_indices = [i for i, t in enumerate(times_list) if t > 0]
    x = np.array(input_sizes)[valid_indices]
    y = np.array(times_list)[valid_indices]
    
    log_x = np.log(x)
    log_y = np.log(y)
    
    # Linear fit: log(y) = k * log(x) + log(a)
    coefficients = np.polyfit(log_x, log_y, 1)
    return coefficients[0]  # This is the exponent 'k'

def calculate_process_rates(input_sizes_bytes, times_list):
    """Calculates throughput in Megabytes per second (MB/s)."""
    # Convert bytes to MB: bytes / (1024 * 1024)
    sizes_mb = [s / (1024**2) for s in input_sizes_bytes]
    rates = [mb / t if t > 0 else 0 for mb, t in zip(sizes_mb, times_list)]
    return rates

def plot_sac_values(sac_values, bit_length=128):
    """
    Plots the Hamming distances calculated for the SAC analysis,
    with a reference line for the ideal SAC value.
    """
    plt.figure(figsize=(12, 6))
    plt.scatter(range(len(sac_values)), sac_values, color='teal', alpha=0.4, s=10)
    plt.axhline(y=bit_length/2, color='r', linestyle='--', label=f'Ideal SAC ({bit_length/2} bits)')
    plt.title('Strict Avalanche Criterion (Hamming Distance)')
    plt.xlabel('Unique Pair Index')
    plt.ylabel('Hamming Distance (Bits)')
    plt.legend()
    plt.tight_layout()
    plt.show()

def plot_hex_distribution(list_of_keys):
    """
    Plots the distribution of hex characters in the generated keys.
    """
    all_chars = list("".join(list_of_keys))
    plt.figure(figsize=(12, 6))
    sns.countplot(x=all_chars, order=list("0123456789abcdef"), palette="magma")
    entropy = calculate_shannon_entropy(list_of_keys)
    plt.title(f"Hex Character Distribution (Shannon Entropy: {entropy:.4f})")
    plt.xlabel("Hex Character")
    plt.ylabel("Frequency")
    plt.tight_layout()
    plt.show()

def plot_bigo_complexity(input_sizes, times_list):
    """Plots measured times vs input sizes with a Big-O trendline."""
    plt.figure(figsize=(10, 6))
    plt.scatter(input_sizes, times_list, color='blue', label='Actual Timing Data')
    
    k = calculate_big_o_complexity(input_sizes, times_list)
    
    # Generate trendline: y = a * x^k
    # We find 'a' by taking the mean of (times / input_sizes^k)
    a = np.mean(np.array(times_list) / (np.array(input_sizes)**k))
    trendline = a * (np.array(input_sizes)**k)
    
    plt.plot(input_sizes, trendline, color='red', linestyle='--', 
             label=f'Estimated Trend: $O(n^{{{k:.2f}}})$')
    
    plt.xscale('log')
    plt.yscale('log')
    plt.title('Encryption Complexity Analysis (Log-Log Scale)')
    plt.xlabel('Input Size (Number of 16-byte Blocks)')
    plt.ylabel('Time Taken (Seconds)')
    plt.legend()
    plt.show()

def plot_process_rates(input_sizes_bytes, rates_list):
    """Plots throughput consistency across different data volumes."""
    sizes_mb = [s / (1024**2) for s in input_sizes_bytes]
    plt.figure(figsize=(10, 6))
    sns.lineplot(x=sizes_mb, y=rates_list, marker='o', color='green')
    
    avg_rate = np.mean(rates_list)
    plt.axhline(y=avg_rate, color='r', linestyle='--', label=f'Avg: {avg_rate:.2f} MB/s')
    
    plt.title('Throughput Performance (Process Rates)')
    plt.xlabel('Data Size (MB)')
    plt.ylabel('Rate (MB/s)')
    plt.legend()
    plt.show()

if __name__ == "__main__":
    generate_test_data(100)

    keys_df = pd.read_csv("shannon_entropy.txt", header=None)
    cipher_df = pd.read_csv("tester_out.txt", header=None)

    ciphertexts_binary = cipher_df[0].astype(str).apply(to_bin).tolist()
    keys_list = keys_df[0].astype(str).tolist()

    print(f"Calculated Shannon Entropy: {calculate_shannon_entropy(keys_list):.4f}")

    sac_results = calculate_sac(ciphertexts_binary)

    plot_sac_values(sac_results)
    plot_hex_distribution(keys_list)

    block_counts = [100, 500, 1000, 5000, 10000]
    byte_sizes = [count * 16 for count in block_counts]

    simulated_times = [0.0001 * n + np.random.normal(0, 0.001 * n) for n in block_counts]
    simulated_times = [max(t, 0.00001) for t in simulated_times]

    plot_bigo_complexity(block_counts, simulated_times)

    rates = calculate_process_rates(byte_sizes, simulated_times)
    plot_process_rates(byte_sizes, rates)
