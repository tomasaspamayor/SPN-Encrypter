"""
The script to collect and analyse the project data.
It will constitute mainly the calculations and plottings of:

a) Encryption and Decryption checks.
b) The Strict Avalanche Criterion (SAC) by the Hamming distance.
c) The Shannon Entropy of the generated keys.
d) The time taken for the encryption and decryption processes, and their Big-O complexity.
"""
import os
import numpy as np
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

sns.set_style("whitegrid")
sns.set_style("conference")

# We store need to store the plaitext, the ciphertext, and the keys.
keys = pd.read_csv("keys.txt", header=None)
plaintexts = pd.read_csv("tester.txt", header=None)
ciphertexts = pd.read_csv("tester_out.txt", header=None)

def check_encryption_decryption(plaintexts_list, decrypted_list):
    """
    Check if the encryption and decryption processes are correct 
    by comparing plaintexts and ciphertexts.
    """
    if len(plaintexts_list) != len(decrypted_list):
        raise ValueError("The number of plaintexts and ciphertexts must be the same")
    len_texts = len(plaintexts_list)
    for i in range(len_texts):
        if plaintexts_list[i] != decrypted_list[i]:
            print(f"Mismatch at index {i}: plaintext = {plaintexts_list[i]}, decrypted = {decrypted_list[i]}")
            return False
    return True

def check_encryption_decryption_files(plaintexts_file, decrypted_file):
    """
    Now, we check full .jpg or such files. We convert 
    the files to binary and compare the binary strings.
    """
    if not os.path.exists(plaintexts_file):
        print(f"Error: File '{plaintexts_file}' not found.")
        return False
    if not os.path.exists(decrypted_file):
        print(f"Error: File '{decrypted_file}' not found.")
        return False

    with open(plaintexts_file, 'rb') as f_plain, open(decrypted_file, 'rb') as f_decrypted:
        plaintext_data = f_plain.read()
        decrypted_data = f_decrypted.read()

    if plaintext_data != decrypted_data:
        print("Mismatch between plaintext and decrypted data.")
        return False
    return True

keys_binary = keys[0].apply(lambda x: bin(int(x, 16))[2:].zfill(128)).astype(str)
plaintexts_binary = plaintexts[0].apply(lambda x: bin(int(x, 16))[2:].zfill(128)).astype(str)
ciphertexts_binary = ciphertexts[0].apply(lambda x: bin(int(x, 16))[2:].zfill(128)).astype(str)

def calculate_hamming_distance(str1, str2):
    """Calculate the Hamming distance between two strings."""
    if type(str1) != str or type(str2) != str:
        raise ValueError("Both inputs must be strings")
    if len(str1) != len(str2):
        raise ValueError("Strings must be of the same length")
    return sum(el1 != el2 for el1, el2 in zip(str1, str2))

def calculate_sac(ciphertexts_list_1, ciphertexts_list_2):
    """Calculate the Strict Avalanche Criterion (SAC) for the given ciphertexts."""
    sac_values = []
    len_ciphertexts_1 = len(ciphertexts_list_1)
    len_ciphertexts_2 = len(ciphertexts_list_2)
    if len_ciphertexts_1 != len_ciphertexts_2:
        raise ValueError("Both ciphertext lists must be of the same length")
    for i in range(len_ciphertexts_1):
        for j in range(len_ciphertexts_2):
            if i != j:
                hamming_distance = calculate_hamming_distance(ciphertexts_list_1[i], ciphertexts_list_2[j])
                sac_values.append(hamming_distance)
            else:
                sac_values.append(0)
    return sac_values

def calculate_shannon_entropy(keys_list):
    """Calculate the Shannon entropy of the given keys."""
    if type(keys_list) != list:
        raise ValueError("Input keys must be a list")
    if len(keys_list) == 0:
        return 0
    value_counts = pd.Series(keys_list).value_counts()
    probabilities = value_counts / len(keys_list)
    entropy = -np.sum(probabilities * np.log2(probabilities))
    return entropy

# Having defined the calculation functions, we now define the plotting ones.

def plot_sac_values(sac_values, ciphertexts_list):
    """
    Plot the SAC values against the length of the ciphertexts.
    We should also include a horizontal line representing the 50% value mark.
    """
    if type(sac_values) != list or type(ciphertexts_list) != list:
        raise ValueError("Both inputs must be lists")
    if len(sac_values) == 0 or len(ciphertexts_list) == 0:
        raise ValueError("Input lists cannot be empty")
    plt.figure(figsize=(12, 6))
    plt.scatter(range(len(sac_values)), sac_values, alpha=0.5)
    plt.title('SAC Values vs Length of Ciphertexts')
    plt.axhline(y=0.5, color='r', linestyle='--', label='Expected SAC Value (Good Cipher)')
    plt.legend()
    plt.xlabel('Index of Ciphertext Pair')
    plt.ylabel('Hamming Distance (SAC Value)')
    plt.show()

def plot_hex_value_distribution(keys_list):
    """
    Plot the distribution of HEX values in the keys.
    This plot should include the horizontal line representing
    the expected count for a uniform distribution.
    We must also add the Shannon entropy value in the title of the plot.
    """
    if type(keys_list) != list:
        raise ValueError("Input keys must be a list")
    hex_values = [key[i:i+2] for key in keys_list for i in range(0, len(key), 2)]
    value_counts = pd.Series(hex_values).value_counts()
    plt.figure(figsize=(12, 6))
    value_counts.plot(kind='bar')
    plt.title(f'Distribution of HEX Values in Keys (Shannon Entropy: {calculate_shannon_entropy(keys_list):.2f})')
    plt.axhline(y=len(keys_list) * 16 / 256, color='r', linestyle='--', label='Expected Count (Uniform Distribution)')
    plt.legend()
    plt.xlabel('HEX Value')
    plt.ylabel('Count')
    plt.xticks(rotation=90)
    plt.show()

# We finally define the Big-O complexity calculation function.
def calculate_big_o_complexity(times_list):
    """
    Calculate the Big-O complexity of the encryption and decryption processes
    based on the time taken for different input sizes.
    We can use a simple linear regression on the log-log scale to estimate the complexity.
    """
    if type(times_list) != list:
        raise ValueError("Input times must be a list")
    if len(times_list) == 0:
        raise ValueError("Input list cannot be empty")
    input_sizes = [2**i for i in range(len(times_list))]
    log_input_sizes = np.log(input_sizes)
    log_times = np.log(times_list)
    coefficients = np.polyfit(log_input_sizes, log_times, 1)
    return coefficients[0]

def plot_bigo_complexity(times_list):
    """
    Plot the time taken for encryption and decryption processes against input sizes
    on a log-log scale to visualize the Big-O complexity.
    We should also include a line representing the estimated complexity.
    """
    if type(times_list) != list:
        raise ValueError("Input times must be a list")
    if len(times_list) == 0:
        raise ValueError("Input list cannot be empty")
    input_sizes = [2**i for i in range(len(times_list))]
    plt.figure(figsize=(12, 6))
    plt.scatter(input_sizes, times_list, alpha=0.5, label='Measured Times')
    big_o_slope = calculate_big_o_complexity(times_list)
    estimated_times = [input_size ** big_o_slope for input_size in input_sizes]
    plt.plot(input_sizes, estimated_times, color='r', linestyle='--', label=f'Estimated O(n^{big_o_slope:.2f})')
    plt.xscale('log')
    plt.yscale('log')
    plt.title('Time Taken vs Input Size (Log-Log Scale)')
    plt.xlabel('Input Size (log scale)')
    plt.ylabel('Time Taken (log scale)')
    plt.legend()
    plt.show()

def calculate_process_rates(data_sizes_list, times_list):
    """
    Calculate the process rates in MB/s based on the data sizes and time taken.
    We can then plot these rates against input sizes to visualize performance.
    """
    if type(data_sizes_list) != list or type(times_list) != list:
        raise ValueError("Both inputs must be lists")
    if len(data_sizes_list) == 0 or len(times_list) == 0:
        raise ValueError("Input lists cannot be empty")
    rates = [data_size / time for data_size, time in zip(data_sizes_list, times_list)]
    return rates

def plot_process_rates(data_sizes_list, rates_list):
    """
    Plot the process rates in MB/s against input sizes to visualize performance.
    We should also include a line representing the average rate.
    """
    if type(data_sizes_list) != list or type(rates_list) != list:
        raise ValueError("Both inputs must be lists")
    if len(data_sizes_list) == 0 or len(rates_list) == 0:
        raise ValueError("Input lists cannot be empty")
    plt.figure(figsize=(12, 6))
    plt.scatter(data_sizes_list, rates_list, alpha=0.5, label='Measured Rates')
    average_rate = np.mean(rates_list)
    plt.axhline(y=average_rate, color='r', linestyle='--', label=f'Average Rate: {average_rate:.2f} MB/s')
    plt.xscale('log')
    plt.title('Process Rates vs Input Size')
    plt.xlabel('Input Size (MB)')
    plt.ylabel('Process Rate (MB/s)')
    plt.legend()
    plt.show()
