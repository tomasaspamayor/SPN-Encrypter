"""
Routine to transfer files from the host computer to the PIC18 microprocessor.
Converts any file into 16-byte (128-bit) packets, which are then sent 
to the microprocessor via the serial port.
"""

import os
import serial

def file_send(file_path, serial_port, baud_rate=9600, packet_size=16):
    """
    Transfers a file to a PIC18 in 128-bit (16-byte) chunks with ACK/NAK flow control.
    
    Args:
        file_path (str): Path to the source file.
        serial_port (str): e.g., 'COM4'
        baud_rate (int): Speed of transmission.
        packet_size (int): Size of chunks in bytes (default 16 for 128 bits).
    """
    if not os.path.exists(file_path):
        print(f"Error: File '{file_path}' not found.")
        return

    ser = None
    try:
        # Initialize Serial with a 2-second timeout for the ACK response
        ser = serial.Serial(serial_port, baud_rate, timeout=2)
        print(f"Connected to {serial_port}. Sending 128-bit packets...")

        with open(file_path, 'rb') as f:
            packet_count = 0

            while True:
                # Read 16 bytes (128 bits)
                packet = f.read(packet_size)

                if not packet:
                    break  # End of File reached

                # If the last chunk is less than 16 bytes, pad it with null bytes
                if len(packet) < packet_size:
                    packet = packet.ljust(packet_size, b'\x00')

                # Send the 128-bit packet
                ser.write(packet)

                # FLOW CONTROL: Wait for ACK (0x06) from PIC18
                ack = ser.read(1)

                if ack == b'\x06':
                    packet_count += 1
                    print(f"Packet {packet_count} (128 bits) acknowledged.")
                elif ack == b'\x15':
                    print(f"Error: PIC18 reported a NAK at packet {packet_count+1}.")
                    break
                else:
                    print(f"Timeout: PIC18 did not respond at packet {packet_count+1}.")
                    break

            # Send End of Transmission signal
            ser.write(b'\x04')
            print("Transfer Complete. Sent EOT signal.")

    except serial.SerialException as e:
        print(f"Serial Error: Check connection on {serial_port}. {e}")
    except FileNotFoundError:
        print(f"Error: The file at {file_path} was not found.")
    except PermissionError:
        print("Error: Permission denied. Close the file in other programs.")
    except KeyboardInterrupt:
        print("\nTransfer cancelled by user.")
    finally:
        if ser and ser.is_open:
            ser.close()
            print("Serial port safely closed.")

def file_receive(save_path, serial_port, baud_rate=9600, packet_size=16):
    ser = None
    try:
        ser = serial.Serial(serial_port, baud_rate, timeout=2)
        print(f"Connected to {serial_port}. Waiting for 128-bit packets...")

        with open(save_path, 'wb') as f:
            packet_count = 0

            while True:
                # Read the first byte to check for EOT
                first_byte = ser.read(1)

                if not first_byte:
                    print("Timeout: No data received.")
                    break

                if first_byte == b'\x04':
                    print("EOT signal received. Ending transfer.")
                    break

                # If not EOT, read the remaining 15 bytes of the 128-bit packet
                remaining_bytes = ser.read(packet_size - 1)
                packet = first_byte + remaining_bytes

                if len(packet) < packet_size:
                    print("Warning: Received incomplete packet. Saving partial data.")

                f.write(packet)

                # Send ACK to PIC18 to signal we are ready for the next 128 bits
                ser.write(b'\x06')

                packet_count += 1
                print(f"Packet {packet_count} (128 bits) received and acknowledged.")

    except serial.SerialException as e:
        print(f"Serial Error: Check connection on {serial_port}. {e}")
    except PermissionError:
        print("Error: Permission denied. Close the file in other programs.")
    except KeyboardInterrupt:
        print("\nTransfer cancelled by user.")
    finally:
        if ser and ser.is_open:
            ser.close()
            print("Serial port safely closed.")

if __name__ == "__main__":
    filepath_sent = 'example_file.txt'
    filepath_received = 'received_data.bin' 
    picport = 'COM4'
    file_send(filepath_sent, picport)
    file_receive(filepath_received, picport)
