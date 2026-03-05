"""
Routine to exchange 128-bit packets with a PIC18 microprocessor.
For every packet sent by the PC, it waits for a 128-bit response 
from the PIC before sending the next one.
"""

import os
import serial

def file_exchange(send_path, receive_path, serial_port, baud_rate=9600, packet_size=16):
    """
    Exchange files with a PIC18 microprocessor over a serial connection.
    Each packet is 128 bits (16 bytes). The PC sends a packet and waits
    for a response before sending the next one.

    Args:
        send_path (str): Path to the local file to send to the PIC.
        receive_path (str): Path to the local file to save the response from the PIC.
        serial_port (str): Serial port to use for communication (e.g., 'COM4' or '/dev/ttyUSB0').
        baud_rate (int, optional): Baud rate for serial communication. Default is 9600.
        packet_size (int, optional): Size of each packet in bytes. Default is 16 bytes (128 bits).
    Raises:
        FileNotFoundError: If the send_path file does not exist.
        PermissionError: If there are issues with file permissions.
        serial.SerialException: If there are issues with the serial connection.
        IOError: If there are issues reading/writing to the local drive.
    """

    # --- 1. READ: Convert the input hex-string file into actual binary data ---
    if not os.path.exists(send_path):
        print(f"Error: File '{send_path}' not found.")
        return

    try:
        with open(send_path, "r", encoding="utf-8") as f:
            raw_text = f.read()
            # Remove spaces/newlines and convert to actual bytes
            data = bytes.fromhex("".join(raw_text.split()))
    except ValueError:
        print("Error: Input file contains invalid hex characters.")
        return

    print(f"Read {len(data)} binary bytes from hex file.")

    ser = None
    try:
        ser = serial.Serial(serial_port, baud_rate, timeout=2)

        # --- 2. WRITE: Open the output file in TEXT mode to save hex strings ---
        with open(receive_path, 'w', encoding="utf-8") as f_recv:
            packet_count = 0

            for i in range(0, len(data), packet_size):
                send_packet = data[i : i + packet_size]
                if len(send_packet) < packet_size:
                    send_packet = send_packet.ljust(packet_size, b'\x00')

                # Send raw bytes to hardware
                ser.write(send_packet)

                # Read raw bytes from hardware
                recv_packet = ser.read(packet_size)

                if len(recv_packet) < packet_size:
                    print(f"Timeout at packet {packet_count + 1}")
                    break

                # --- 3. CONVERT: Turn binary response back into hex text ---
                f_recv.write(recv_packet.hex() + "\n")

                packet_count += 1
                print(f"Exchanged packet {packet_count}")

            ser.write(b'\x04')
            print(f"Exchange complete. {packet_count} packets processed.")

    except serial.SerialException as e:
        print(f"Serial Error: {e}")

    except (FileNotFoundError, PermissionError) as e:
        print(f"File Error: Check your paths and file permissions. {e}")

    except KeyboardInterrupt:
        print("\nProcess interrupted by user (Ctrl+C).")

    except IOError as e:
        print(f"Disk Error: Could not read/write to the local drive. {e}")

    finally:
        if ser and ser.is_open:
            ser.close()
            print("Serial port safely closed.")

if __name__ == "__main__":
    file_send_path = 'tester.txt' # pylint: disable=invalid-name
    file_receive_path = 'tester_out.txt' # pylint: disable=invalid-name
    port = 'COM4' # pylint: disable=invalid-name
    file_exchange(file_send_path, file_receive_path, port)
