"""
Routine to exchange 128-bit packets with a PIC18 microprocessor.
For every packet sent by the PC, it waits for a 128-bit response 
from the PIC before sending the next one.
"""

import os
import serial
import serial.tools.list_ports

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

    if not os.path.exists(send_path):
        print(f"Error: File '{send_path}' not found.")
        return
    
    with open(r"tester.txt", "rb") as f:
        data = f.read()
        print("File length:", len(data))
        print("File content (hex):", data.hex())

    ser = None
    try:
        ser = serial.Serial(serial_port, baud_rate, timeout=2)
        print(f"Connected to {serial_port}. Starting Ping-Pong exchange...")

        with open(send_path, 'rb') as f_send, open(receive_path, 'wb') as f_recv:
            packet_count = 0

            while True:
                # 1. READ from local file
                send_packet = f_send.read(packet_size)
                if not send_packet:
                    break  # End of file reached

                # Pad last packet if necessary
                if len(send_packet) < packet_size:
                    send_packet = send_packet.ljust(packet_size, b'\x00')

                # Print packet being sent
                print(f"Sending packet {packet_count + 1}: {send_packet.hex()}")

                # 2. SEND to PIC
                ser.write(send_packet)

                # 3. RECEIVE response from PIC (Wait for 128 bits back)
                # Note: We check the first byte for EOT or errors if your PIC uses them
                recv_packet = ser.read(packet_size)
                print(f"pkg_buffer content from PIC: {recv_packet.hex()}")

                if len(recv_packet) < packet_size:
                    print(f"Timeout: PIC did not respond to packet {packet_count + 1}.")
                    break

                # 4. WRITE response to local file
                f_recv.write(recv_packet)

                packet_count += 1
                print(f"Exchanged packet {packet_count} (128 bits).")

            # Signal End of Transmission
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
