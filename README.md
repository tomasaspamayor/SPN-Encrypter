# Microprocessors - AES Encrypter Project

Repository for Physics Year 3 Microprocessors Lab.

A hardware-based cryptographic device implementing AES encryption and decryption on a PIC18 microprocessor. This project demonstrates a complete Substitution-Permutation Network (SPN) cipher with USB communication, featuring full 10-round AES-128 encryption/decryption, system timer-based key generation, real-time performance timing analysis, and PC-side utilities for data transfer and cryptographic analysis. All low-level operations are implemented in assembly language for efficiency and direct hardware control.

## Project Features

- **Full AES-128 Implementation**: Complete encryption and decryption pipeline with 10 rounds (9 main rounds + final round)
- **Substitution-Permutation Network**: S-Box substitution, row shifting, column mixing, and key mixing transformations
- **System Timer-Based Key Generation**: Master key derivation using system timer for pseudo-randomness
- **USB Communication**: UART-based serial interface for PC-microcontroller data transfer
- **EEPROM Key Storage**: Persistent cryptographic key storage in microcontroller memory
- **Performance Analysis**: Real-time timing measurements for encryption/decryption operations with TMR1 precision
- **Cryptanalysis Tools**: Hamming distance analysis, Shannon entropy calculation, and system efficiency metrics
- **Multi-Mode Operation**: Support for encryption-only, decryption-only, and mixed mode (timing both operations)
- **Test Suite**: BMP image encryption/decryption with visual testing capabilities

## Directory Structure

### Core Assembly Source Files
- **main.s** - Entry point and main control flow
- **config.s** - Microprocessor configuration and setup
- **UART.s** - Serial communication protocol (USB interface)
- **sbox.s** - S-Box lookup tables for AES SubBytes step
- **eeprom.s** - EEPROM read/write operations for key storage
- **key-schedule.s** - AES key expansion algorithm
- **key-mixing.s** - Round key XOR operations
- **p_box_enc.s** - Forward P-Box transformation (ShiftRows + MixColumns)
- **p_box_dec.s** - Inverse P-Box transformation (InvShiftRows + InvMixColumns)
- **trng.s** - True Random Number Generator using hardware jitter

### Build and Project Directories
- **_build/** - CMake build configuration directory
- **build/default/** - Compiled object files and intermediate build artifacts
- **cmake/** - CMake configuration files for PIC18 compilation
- **nbproject/** - NetBeans IDE project configuration
- **dist/** - Distribution/final compiled output

### Data and Testing
- **data/** - Test vectors and analysis results
  - Encrypted/decrypted test images (BMPs)
  - Round key histories for encryption/decryption rounds
  - Timing measurements for performance analysis
  - Generated encryption keys for multiple rounds
- **hamming/** - Hamming distance analysis data (key correlation study)
- **debug/** - Debug logs and queue logs for troubleshooting

### Analysis and Utilities
- **images/** - Supporting images and diagrams
- **data_acquisition.py** - Python script for collecting performance/timing data
- **file_transfer_pc.py** - PC-side interface for USB communication with microcontroller
- **system_eff.py** - System efficiency analysis tool

### Configuration and Documentation
- **Makefile** - Build automation and compilation targets
- **keys.txt** - Reference/test key data
- **round_keys_history.txt** - Round key expansion history
- **shannon_entropy.txt** - Entropy analysis results
- **tester.txt** - Test execution logs
- **tester_out.txt** - Test output results
- **timings.txt** - Performance timing data
- **output.map** - Linker memory map

## Build Instructions

### Requirements
- **Microcontroller**: PIC18 microprocessor (PIC18F4585 or compatible)
- **Development Environment**: MPLAB X IDE with XC8 compiler
- **Build System**: CMake 3.10+
- **Build Tools**: Make or equivalent build tool
- **Python 3.7+** (for PC utilities)

### Compilation Steps

1. **Clone the repository:**
   ```bash
   git clone https://github.com/tomasaspamayor/SPN-Encrypter.git
   cd SPN-Encrypter
   ```

2. **Create build directory:**
   ```bash
   mkdir -p build/default
   cd build/default
   ```

3. **Configure with CMake:**
   ```bash
   cmake ../../
   ```

4. **Build the project:**
   ```bash
   make
   ```

5. **Output:** The compiled firmware will be in `build/default/` (typically as `.hex` for flash programming)


## Contributors

- **Louis Liu** - Assembly implementation, cryptanalysis, documentation
- **Tomàs Aspa Mayor** - Architecture design, testing, PC utilities

---

*Physics Year 3 Lab Project - Imperial College London*
