"""
Routine to exchange BMP files with a PIC18 microprocessor.
This covers the PC's point of view, including reading from a local file, 
sending data to the PIC, receiving responses, and writing responses to a local file.
"""

import os
import time
import serial
from PIL import Image

# Framing constants
SOT_MARKER = bytes([0x3A, 0xC5, 0x7E, 0x11, 0xD2, 0x9B, 0x4F, 0x80])
FRAME_MARKER_SIZE = len(SOT_MARKER)
MODE_DECRYPT_BYTE = 0x00
MODE_ENCRYPT_BYTE = 0x01
MODE_MIXED_BYTE = 0x02
KEY_REQUEST_PAYLOAD = bytes([0xAA, 0x55, 0x4B, 0x45, 0x59] + [0x00] * 11)

## WARNING: This code works for BMP files only. For the TXT methods, go to 'main_pc_txt.py'.

class FileTransfer():
    """
    A class to handle file exchange between a PC and a PIC18 microprocessor over a serial
    connection. It covers the PC's point of view, including reading from a local file,
    sending data to the PIC, receiving responses, and writing responses to a local file.
    The class also includes error handling for common issues that may arise during the process.

    Attributes:
        send_path (str): Path to the local file to send to the PIC.
        receive_path (str): Path to the local file to save the response from the PIC.
        serial_port (str): Serial port to use for communication (e.g., 'COM4' or '/dev/ttyUSB0').
        baud_rate (int): Baud rate for serial communication. Default is 9600.
        packet_size (int): Size of each packet in bytes. Default is 16 bytes (128 bits).
        key_log_path (str): Optional path to log one 16-byte master key per packet.
        timing_log_path (str): Optional path to write per-packet timing data as CSV.
        round_keys_log_path (str): Optional path to append 176-byte round-key dumps.
        round_keys_size (int): Size in bytes of the round-key payload sent by firmware.
        use_framing (bool): If True, exchange uses SOT + mode-byte + (packet+checksum)*N.
        encryption_mode (bool): True for encryption mode, False for decryption mode.
    """

    def __init__(self, send_path, receive_path, serial_port, baud_rate=9600, packet_size=16,
                 key_log_path=None, timing_log_path=None, round_keys_log_path=None,
                 round_keys_size=176, use_framing=True, encryption_mode=True):
        self.send_path = send_path
        self.receive_path = receive_path
        self.serial_port = serial_port
        self.baud_rate = baud_rate
        self.packet_size = packet_size
        self.key_log_path = key_log_path
        self.timing_log_path = timing_log_path
        self.round_keys_log_path = round_keys_log_path
        self.round_keys_size = round_keys_size
        self.use_framing = use_framing
        self.encryption_mode = bool(encryption_mode)

    def _checksum8(self, data):
        """
        Compute compact 8-bit additive checksum (sum modulo 256).
        
        Args:
            data: The bytes for which to compute the checksum.
        
        Returns:
            int: Integer representing the 8-bit checksum of the input data.
        """
        return sum(data) & 0xFF

    def _build_packet_with_checksum(self, payload):
        """
        Build one packet unit as payload + 8-bit additive checksum.
        
        Args:
            payload: The raw bytes of the packet payload (e.g., 16 bytes for data).
        
        Returns:
            bytes: The packet with checksum appended.
        """
        checksum = self._checksum8(payload)
        return payload + bytes([checksum])

    def _read_exact(self, ser, size):
        """
        Read exactly 'size' bytes from serial or return what was available.

        Args:
            ser: An open serial.Serial instance to read from.
            size: The exact number of bytes to read.

        Returns:
            bytes: The data read from the serial port.
        """
        data = bytearray()
        while len(data) < size:
            chunk = ser.read(size - len(data))
            if not chunk:
                break
            data.extend(chunk)
        return bytes(data)

    def _read_packet_payload(self, ser, payload_len):
        """
        Read one packet payload and validate trailing checksum.

        Args:
            ser: An open serial.Serial instance to read from.
            payload_len: The length of the payload to read.

        Returns:
            bytes: The packet payload or None if validation fails.
        """
        if not self.use_framing:
            return self._read_exact(ser, payload_len)

        body = self._read_exact(ser, payload_len + 1)
        if len(body) != payload_len + 1:
            return None

        payload = body[:payload_len]
        recv_checksum = body[-1]
        calc_checksum = self._checksum8(payload)
        if recv_checksum != calc_checksum:
            print(
                f"Frame error: checksum mismatch recv=0x{recv_checksum:02X}, calc=0x{calc_checksum:02X}")
            return None

        return payload

    def _send_sot(self, ser):
        """
        Send the Start of Transfer (SOT) marker to the PIC to initiate the handshake.
        
        Args:
            ser: An open serial.Serial instance to write to.
        """
        if self.use_framing:
            ser.write(SOT_MARKER)

    def _expect_sot(self, ser):
        """
        Expect SOT marker from device and return True if it matches.
        
        Args:
            ser: An open serial.Serial instance to read from.
        Returns:
            bool: True if the SOT marker is received, False otherwise.
        """
        if not self.use_framing:
            return True
        # PIC firmware replies with a single 0x02 ACK after matching SOT.
        ack = self._read_exact(ser, 1)
        return ack == bytes([0x02])

    def _send_mode_byte(self, ser):
        """
        Send one mode byte after SOT handshake: 0x01 encrypt, 0x00 decrypt.
        
        Args:
            ser: An open serial.Serial instance to write to.
        """
        mode_byte = MODE_ENCRYPT_BYTE if self.encryption_mode else MODE_DECRYPT_BYTE
        ser.write(bytes([mode_byte]))

    def _calculate_packet_count(self, data_len):
        """
        Return how many payload packets will be sent for a given data length.
        
        Args:
            data_len: The total length of the data to be sent in bytes.

        Returns:
            int: The number of packets needed to send the data, based on the packet size.
        """
        if data_len <= 0:
            return 0
        return (data_len + self.packet_size - 1) // self.packet_size

    def _send_packet_count(self, ser, packet_count):
        """
        Send packet count as 2 bytes (little-endian) right after mode byte.
        
        Args:
            ser: An open serial.Serial instance to write to.
            packet_count (int): The number of packets to send.

        Raises:
            ValueError: If packet_count is negative or exceeds 65535 (max for 2 bytes).
        """
        if packet_count < 0 or packet_count > 0xFFFF:
            raise ValueError(
                "Packet count out of range for 2-byte field (0..65535).")
        ser.write(packet_count.to_bytes(2, byteorder='little'))

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

    def _uses_bmp_format(self, path):
        """Return True for BMP files that can use selective pixel-data encryption."""
        return os.path.splitext(path)[1].lower() == ".bmp"

    def _parse_bmp_header(self, data: bytes):
        """
        Parse BMP header and return (header_bytes, pixel_data_offset, pixel_data).
        Raises ValueError if not a valid BMP or file is truncated.

        Args:
            data (bytes): The raw bytes of the BMP file.
        """
        if len(data) < 26:
            raise ValueError("File too small for BMP header")
        if data[0:2] != b'BM':
            raise ValueError("Not a BMP file (missing BM signature)")

        pixel_offset = int.from_bytes(data[10:14], 'little')
        if pixel_offset < 14 or pixel_offset > len(data):
            raise ValueError(f"Invalid pixel offset {pixel_offset}")

        header = data[:pixel_offset]
        pixel_data = data[pixel_offset:]

        return header, pixel_offset, pixel_data

    def _check_bmp_compression(self, path):
        with open(path, 'rb') as f:
            f.seek(30)
            compression_bytes = f.read(4)
            compression_val = int.from_bytes(compression_bytes, 'little')

            modes = {0: "Uncompressed (BI_RGB)", 1: "RLE 8-bit", 2: "RLE 4-bit", 3: "Bitfields"}
            status = modes.get(compression_val, "Unknown/Other")

            print(f"Compression Value: {compression_val} ({status})")
            return compression_val == 0

    def _convert_to_uncompressed_bmp(self, input_path, output_path):
        """
        Convert a BMP file to an uncompressed 24-bit format using PIL.

        Args:
            input_path (str): The path to the original BMP file.
            output_path (str): The path to save the uncompressed BMP file.
        """
        img = Image.open(input_path)
        img = img.convert("RGB")
        img.save(output_path, "BMP")
        print(f"Successful uncompression. {output_path} is now a raw 24-bit uncompressed BMP.")

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

        is_bmp = False
        if self._uses_bmp_format(self.send_path):
            print(f"BMP detected. Ensuring '{self.send_path}' is uncompressed 24-bit...")
            try:
                self._convert_to_uncompressed_bmp(self.send_path, self.send_path)
                if not self._check_bmp_compression(self.send_path):
                    print("Critical Error: Conversion failed to uncompress file. Aborting.")
                    return
                is_bmp = True

            except (FileNotFoundError, PermissionError) as e:
                print(f"File Access Error: Check if the file is open in another program. {e}")
                return
            except ValueError as e:
                print(f"Data Error: {e}. Falling back to raw transfer.")
                is_bmp = False

        try:
            data = self._read_input_data()
        except ValueError:
            print("Error: Input file contains invalid hex characters.")
            return

        bmp_header = b''
        payload = data

        if is_bmp:
            try:
                bmp_header, _, pixel_data = self._parse_bmp_header(data)
                payload = pixel_data
                print("Ready for Selective Encryption:")
                print(f"  Header: {len(bmp_header)} bytes (preserved)")
                print(f"  Pixels: {len(pixel_data)} bytes (to be processed)")
            except ValueError as e:
                print(f"BMP parse error: {e}. Falling back to whole file encryption.")
                payload = data

        total_packets = self._calculate_packet_count(len(payload))
        print(f"Planned packets to send: {total_packets}")

        ser = None
        try:
            ser = serial.Serial(self.serial_port, self.baud_rate, timeout=20)

            output_mode = 'w' if self._uses_hex_text_format(self.receive_path) else 'wb'
            output_kwargs = {"encoding": "utf-8"} if output_mode == 'w' else {}

            bmp_recv_pixels = bytearray() if is_bmp else None

            with open(self.receive_path, output_mode, **output_kwargs) as f_recv:
                packet_count = 0
                bytes_written = 0

                timing_file = open(self.timing_log_path, "w", encoding="utf-8") if self.timing_log_path else None
                if timing_file:
                    timing_file.write("packet,encrypt_us,decrypt_us,transaction_us,throughput_mb_s\n")

                round_keys_file = open(self.round_keys_log_path, "a", encoding="utf-8") if self.round_keys_log_path else None

                if self.use_framing:
                    print("Starting Handshake with PIC...")
                    self._send_sot(ser)
                    if not self._expect_sot(ser):
                        print("Frame error: PIC did not ACK the Start of Transfer.")
                        return

                    time.sleep(0.1) 
                    self._send_mode_byte(ser)
                    self._send_packet_count(ser, total_packets)

                    ready = self._read_exact(ser, 1)
                    if ready != bytes([0x03]):
                        print(f"Frame error: PIC not READY. Received: {ready.hex()}")
                        return
                    print("Handshake successful. Sending data...")

                for i in range(0, len(payload), self.packet_size):
                    send_packet = payload[i: i + self.packet_size]

                    if len(send_packet) < self.packet_size:
                        send_packet = send_packet.ljust(self.packet_size, b'\x00')

                    tx_bytes = self._build_packet_with_checksum(send_packet) if self.use_framing else send_packet

                    txn_start = time.perf_counter()
                    ser.write(tx_bytes)

                    recv_total_len = self.packet_size + 4 + self.round_keys_size
                    recv_total = self._read_packet_payload(ser, recv_total_len)
                    txn_end = time.perf_counter()

                    if recv_total is None or len(recv_total) < recv_total_len:
                        print(f"\nTimeout/Error at packet {packet_count + 1}")
                        break

                    recv_packet = recv_total[:self.packet_size]

                    if timing_file:
                        enc_ticks = int.from_bytes(recv_total[16:18], 'little')
                        dec_ticks = int.from_bytes(recv_total[18:20], 'little')
                        txn_us = (txn_end - txn_start) * 1_000_000.0
                        timing_file.write(f"{packet_count+1},{enc_ticks*0.25},{dec_ticks*0.25},{txn_us},0\n")

                    if round_keys_file:
                        round_keys_file.write(recv_total[20:].hex() + "\n")

                    if is_bmp:
                        bmp_recv_pixels.extend(recv_packet)
                    else:
                        packet_to_write = recv_packet
                        if not self._uses_hex_text_format(self.receive_path):
                            remaining = len(data) - bytes_written
                            packet_to_write = recv_packet[:remaining]
                        self._write_output_packet(f_recv, packet_to_write)
                        bytes_written += len(packet_to_write)

                    packet_count += 1

                    if packet_count % 10 == 0 or packet_count == total_packets:
                        percent = (packet_count / total_packets) * 100
                        print(f"\rProgress: {percent:.1f}% [{packet_count}/{total_packets} packets]", end="")

                print("\nTransfer complete. Cleaning up...")

                if timing_file:
                    timing_file.close()
                if round_keys_file:
                    round_keys_file.close()

                if is_bmp and bmp_recv_pixels:
                    with open(self.receive_path, 'wb') as out_bmp:
                        out_bmp.write(bmp_header)
                        out_bmp.write(bytes(bmp_recv_pixels)[:len(payload)])
                    print(f"Reconstructed BMP saved to: {self.receive_path}")

        except serial.SerialException as e:
            print(f"\n[Hardware Error] Serial communication failed: {e}")
            print("Check USB cable and COM port settings.")

        except (FileNotFoundError, PermissionError) as e:
            print(f"\n[File Error] Could not access the drive: {e}")

        except ValueError as e:
            print(f"\n[Data Error] HEX conversion or BMP parsing failed: {e}")

        except KeyboardInterrupt:
            print("\n[User Abort] Process interrupted by user.")

        except Exception as e:
            print(f"\n[Unexpected Bug] An unhandled error occurred: {e}")
            raise

        finally:
            if ser and ser.is_open:
                ser.close()
                print("Serial port closed.")

if __name__ == "__main__":
    transfer_bmp = FileTransfer(send_path='tester.bmp',
                                receive_path='tester_encrypted.bmp',
                                serial_port='COM4',
                                timing_log_path='timings.txt',
                                round_keys_log_path='round_keys_history.txt',
                                use_framing=True,
                                encryption_mode=True)
    transfer_bmp.file_exchange()
