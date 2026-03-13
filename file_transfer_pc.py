"""
Routine to exchange 128-bit packets with a PIC18 microprocessor.
For every packet sent by the PC, it waits for a 128-bit response 
from the PIC before sending the next one.
"""

import os
import serial

class FileTransfer():
    """
    A class to handle file exchange between a PC and a PIC18 microprocessor over a serial
    connection. It covers the PC's point of view, including reading from a local file,
    sending data to the PIC, receiving responses, and writing responses to a local file.
    The class also includes error handling for common issues that may arise during the process.

    Files ending in .txt are interpreted as hexadecimal text dumps. Any other file type,
    including .jpg, is transferred as raw binary data.

    Attributes:
        send_path (str): Path to the local file to send to the PIC.
        receive_path (str): Path to the local file to save the response from the PIC.
        serial_port (str): Serial port to use for communication (e.g., 'COM4' or '/dev/ttyUSB0').
        baud_rate (int): Baud rate for serial communication. Default is 9600.
        packet_size (int): Size of each packet in bytes. Default is 16 bytes (128 bits).
    """
    def __init__(self, send_path, receive_path, serial_port, baud_rate=9600, packet_size=16, key_log_path=None):
        self.send_path = send_path
        self.receive_path = receive_path
        self.serial_port = serial_port
        self.baud_rate = baud_rate
        self.packet_size = packet_size
        self.key_log_path = key_log_path

    def _request_master_key_over_serial(self, ser):
        """Request the current 16-byte master key over an existing serial session."""
        key_request = bytes([0xAA, 0x55, 0x4B, 0x45, 0x59] + [0x00] * 11)
        ser.write(key_request)
        key_bytes = ser.read(self.packet_size)
        if len(key_bytes) != self.packet_size:
            return None
        return key_bytes

    def _uses_hex_text_format(self, path):
        """
        Determines if the file at the given path should be treated as a hexadecimal text dump
        based on its extension.
        
        Args:
            path (str): The file path to check.
        Returns:
            bool: True if the file should be treated as a hexadecimal text dump, False otherwise.
        """
        return os.path.splitext(path)[1].lower() == ".txt"

    def _read_input_data(self):
        """
        Reads the input data from the file specified by send_path.

        Returns:
            bytes: The raw bytes read from the input file.
        """
        if self._uses_hex_text_format(self.send_path):
            with open(self.send_path, "r", encoding="utf-8") as file_obj:
                raw_text = file_obj.read()
                return bytes.fromhex("".join(raw_text.split()))

        with open(self.send_path, "rb") as file_obj:
            return file_obj.read()

    def _write_output_packet(self, file_obj, packet):
        """
        Writes a packet to the output file.

        Args:
            file_obj: The file object to write to.
            packet (bytes): The packet to write.
        """
        if self._uses_hex_text_format(self.receive_path):
            file_obj.write(packet.hex() + "\n")
            return

        file_obj.write(packet)

    def file_exchange(self):
        """
        Exchange files with a PIC18 microprocessor over a serial connection.
        Each packet is 128 bits (16 bytes). The PC sends a packet and waits
        for a response before sending the next one.

        Args:
            send_path (str): Path to the local file to send to the PIC.
            receive_path (str): Path to the local file to save the response from the PIC.
            serial_port (str): Serial port to use for communication (e.g., 'COM4' or
                               '/dev/ttyUSB0').
            baud_rate (int, optional): Baud rate for serial communication. Default is 9600.
            packet_size (int, optional): Size of each packet in bytes. Default is 16
                                         bytes (128 bits).
        Raises:
            FileNotFoundError: If the send_path file does not exist.
            PermissionError: If there are issues with file permissions.
            serial.SerialException: If there are issues with the serial connection.
            IOError: If there are issues reading/writing to the local drive.
        """
        if not os.path.exists(self.send_path):
            print(f"Error: File '{self.send_path}' not found.")
            return

        try:
            data = self._read_input_data()
        except ValueError:
            print("Error: Input file contains invalid hex characters.")
            return

        input_mode = "hex-text" if self._uses_hex_text_format(self.send_path) else "binary"
        print(f"Read {len(data)} bytes from {input_mode} input file.")

        ser = None
        try:
            ser = serial.Serial(self.serial_port, self.baud_rate, timeout=200)

            output_mode = 'w' if self._uses_hex_text_format(self.receive_path) else 'wb'
            output_kwargs = {"encoding": "utf-8"} if output_mode == 'w' else {}

            with open(self.receive_path, output_mode, **output_kwargs) as f_recv:
                packet_count = 0
                bytes_written = 0

                key_file = None
                if self.key_log_path:
                    key_file = open(self.key_log_path, "w", encoding="utf-8")

                for i in range(0, len(data), self.packet_size):
                    if key_file:
                        master_key = self._request_master_key_over_serial(ser)
                        if master_key is None:
                            print(f"Timeout while requesting key for packet {packet_count + 1}")
                            break
                        key_file.write(master_key.hex() + "\n")

                    send_packet = data[i : i + self.packet_size]
                    if len(send_packet) < self.packet_size:
                        send_packet = send_packet.ljust(self.packet_size, b'\x00')

                    # Send raw bytes to hardware
                    if packet_count < 10:
                        print(f"Sending packet to PIC {packet_count + 1}: {send_packet.hex()}")
                    if packet_count == 10:
                        print("(additional packets will not be printed to avoid console overflow)")
                    ser.write(send_packet)

                    # Read raw bytes from hardware
                    recv_packet = ser.read(self.packet_size)

                    if len(recv_packet) < self.packet_size:
                        print(f"Timeout at packet {packet_count + 1}")
                        break

                    #print(f"Received packet from PIC {packet_count + 1}: {recv_packet.hex()}")
                    packet_to_write = recv_packet
                    if not self._uses_hex_text_format(self.receive_path):
                        remaining_bytes = len(data) - bytes_written
                        packet_to_write = recv_packet[:remaining_bytes]

                    self._write_output_packet(f_recv, packet_to_write)
                    bytes_written += len(packet_to_write)

                    packet_count += 1
                    #print(f"Exchanged packet {packet_count}")

                if key_file:
                    key_file.close()
                    print(f"Master keys saved to {self.key_log_path}")

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

    def request_master_key(self):
        """Request the current 16-byte master key from firmware and print it as hex."""
        key_request = bytes([0xAA, 0x55, 0x4B, 0x45, 0x59] + [0x00] * 11)

        ser = None
        try:
            ser = serial.Serial(self.serial_port, self.baud_rate, timeout=2)
            ser.write(key_request)
            key_bytes = ser.read(self.packet_size)

            if len(key_bytes) != self.packet_size:
                print("Error: did not receive full 16-byte key response.")
                return None

            print(f"Master key (hex): {key_bytes.hex()}")
            return key_bytes

        except serial.SerialException as e:
            print(f"Serial Error: {e}")
            return None

        finally:
            if ser and ser.is_open:
                ser.close()
                print("Serial port safely closed.")

if __name__ == "__main__":

    file_type = 0

    if file_type == 0:  # Example usage: .TXT file.
        transfer_txt = FileTransfer(send_path='tester.txt',
                                receive_path='tester_out.txt',
                                serial_port='COM4',
                                key_log_path='keys.txt')
        transfer_txt.file_exchange()
    else: # Example usage: .JPG file.
        transfer_jpg = FileTransfer(send_path='tester.jpg',
                                receive_path='tester_out.jpg',
                                serial_port='COM4',
                                key_log_path='keys.txt')
        transfer_jpg.file_exchange()
