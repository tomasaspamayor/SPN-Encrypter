"""
Routine to transfer files from the host computer to the PIC18 microprocessor.
Converts any file into a bit pattern and makes it into 128 byte packets,
which are then sent to the microprocessor via the serial port.
"""

import os
import serial

def file_transfer(file_path, serial_port, baud_rate=9600, packet_size=128):
    """
    Transfers a file to a PIC18 with ACK/NAK flow control and error handling.
    
    Args:
        file_path (str): Path to the source file.
        serial_port (str): e.g., 'COM4'
        baud_rate (int): Speed of transmission.
        packet_size (int): Size of chunks in bytes (default 128).
    """
    if not os.path.exists(file_path):
        print(f"Error: File '{file_path}' not found.")
        return

    try:
        # Initialize Serial with a 2-second timeout for the ACK response
        ser = serial.Serial(serial_port, baud_rate, timeout=2)
        print(f"Connected to {serial_port}. Starting transfer...")

        with open(file_path, 'rb') as f:
            packet_count = 0

            while True:
                # Read exactly 'packet_size' bytes
                packet = f.read(packet_size)

                if not packet:
                    break  # End of File reached

                # Send the packet
                ser.write(packet)

                # FLOW CONTROL: Wait for ACK from PIC18
                # The PIC should send 0x06 (ACK) when ready for more,
                # or 0x15 (NAK) if there was a buffer error.
                ack = ser.read(1)

                if ack == b'\x06':
                    packet_count += 1
                    print(f"Packet {packet_count} sent and acknowledged.")
                elif ack == b'\x15':
                    print(f"Error: PIC18 reported a NAK at packet {packet_count+1}.")
                    break
                else:
                    print(f"Timeout: PIC18 did not respond after packet {packet_count+1}.")
                    break

            # Optional: Send a specific 'End of Transmission' byte (e.g., 0x04)
            ser.write(b'\x04')
            print("Transfer Complete. Sent EOT signal.")

        ser.close()

    except serial.SerialException as e:
        print(f"Serial Error: Check if {serial_port} is unplugged or used by another app. {e}")
    except FileNotFoundError:
        print(f"Error: The file at {file_path} was not found.")
    except PermissionError:
        print("Error: Permission denied. Close the file if it's open in another app.")
    except KeyboardInterrupt:
        print("\nTransfer cancelled by user.")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print("Serial port safely closed.")

if __name__ == "__main__":
    path = 'path_to_your_file.bin'  # Replace with your file path
    port = 'COM4'  # Replace with your serial port
    file_transfer(path, port)
