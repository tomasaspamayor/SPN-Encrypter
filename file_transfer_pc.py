"""
Routine to exchange 128-bit packets with a PIC18 microprocessor.
For every packet sent by the PC, it waits for a 128-bit response 
from the PIC before sending the next one.
"""

import os
import time
import serial

SOT_MARKER = bytes([0x3A, 0xC5, 0x7E, 0x11, 0xD2, 0x9B, 0x4F, 0x80])
FRAME_MARKER_SIZE = len(SOT_MARKER)
MODE_DECRYPT_BYTE = 0x00
MODE_ENCRYPT_BYTE = 0x01
KEY_REQUEST_PAYLOAD = bytes([0xAA, 0x55, 0x4B, 0x45, 0x59] + [0x00] * 11)


class FileTransfer():
    """
    A class to handle file exchange between a PC and a PIC18 microprocessor over a serial
    connection. It covers the PC's point of view, including reading from a local file,
    sending data to the PIC, receiving responses, and writing responses to a local file.
    The class also includes error handling for common issues that may arise during the process.

    Files ending in .txt are interpreted as hexadecimal text dumps. BMP files are handled
    with selective pixel-data encryption (header preserved). Other files are transferred as raw binary.

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
        """Compute compact 8-bit additive checksum (sum modulo 256)."""
        return sum(data) & 0xFF

    def _build_packet_with_checksum(self, payload):
        """Build one packet unit as payload + 8-bit additive checksum."""
        checksum = self._checksum8(payload)
        return payload + bytes([checksum])

    def _read_exact(self, ser, size):
        """Read exactly 'size' bytes from serial or return what was available."""
        data = bytearray()
        while len(data) < size:
            chunk = ser.read(size - len(data))
            if not chunk:
                break
            data.extend(chunk)
        return bytes(data)

    def _read_packet_payload(self, ser, payload_len):
        """Read one packet payload and validate trailing checksum."""
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
        if self.use_framing:
            ser.write(SOT_MARKER)

    def _expect_sot(self, ser):
        if not self.use_framing:
            return True
        # PIC firmware replies with a single 0x02 ACK after matching SOT.
        ack = self._read_exact(ser, 1)
        return ack == bytes([0x02])

    def _send_mode_byte(self, ser):
        """Send one mode byte after SOT handshake: 0x01 encrypt, 0x00 decrypt."""
        mode_byte = MODE_ENCRYPT_BYTE if self.encryption_mode else MODE_DECRYPT_BYTE
        ser.write(bytes([mode_byte]))

    def _calculate_packet_count(self, data_len):
        """Return how many payload packets will be sent for a given data length."""
        if data_len <= 0:
            return 0
        return (data_len + self.packet_size - 1) // self.packet_size

    def _send_packet_count(self, ser, packet_count):
        """Send packet count as 2 bytes (little-endian) right after mode byte."""
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
        """
        if len(data) < 26:
            raise ValueError("File too small for BMP header")
        if data[0:2] != b'BM':
            raise ValueError("Not a BMP file (missing BM signature)")
        
        # Offset to pixel data is stored at bytes 10-13 (little-endian)
        pixel_offset = int.from_bytes(data[10:14], 'little')
        if pixel_offset < 14 or pixel_offset > len(data):
            raise ValueError(f"Invalid pixel offset {pixel_offset}")
        
        header = data[:pixel_offset]
        pixel_data = data[pixel_offset:]
        return header, pixel_offset, pixel_data

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

        # Detect BMP and extract pixel data for selective encryption
        is_bmp = False
        bmp_header = b''
        payload = data
        
        if not self._uses_hex_text_format(self.send_path):
            ext = os.path.splitext(self.send_path)[1].lower()
            if ext == '.bmp' and data[:2] == b'BM':
                try:
                    bmp_header, _, pixel_data = self._parse_bmp_header(data)
                    is_bmp = True
                    payload = pixel_data
                    print(f"BMP detected: header size {len(bmp_header)} bytes, pixel data {len(pixel_data)} bytes")
                except ValueError as e:
                    print(f"BMP parse error: {e}. Falling back to whole file encryption.")
                    payload = data

        input_mode = "hex-text" if self._uses_hex_text_format(
            self.send_path) else ("bmp" if is_bmp else "binary")
        print(f"Read {len(data)} bytes from {input_mode} input file.")
        total_packets_to_send = self._calculate_packet_count(len(payload))
        print(f"Planned packets to send: {total_packets_to_send}")

        ser = None
        try:
            ser = serial.Serial(self.serial_port, self.baud_rate, timeout=200)

            output_mode = 'w' if self._uses_hex_text_format(
                self.receive_path) else 'wb'
            output_kwargs = {"encoding": "utf-8"} if output_mode == 'w' else {}
            
            # Buffer for BMP pixel data reconstruction
            bmp_recv_pixels = bytearray() if is_bmp else None

            with open(self.receive_path, output_mode, **output_kwargs) as f_recv:
                packet_count = 0
                bytes_written = 0

                key_file = None
                if self.key_log_path:
                    key_file = open(self.key_log_path, "w", encoding="utf-8")

                timing_file = None
                if self.timing_log_path:
                    timing_file = open(self.timing_log_path,
                                       "w", encoding="utf-8")
                    timing_file.write(
                        "packet,encrypt_us,decrypt_us,transaction_us,throughput_mb_s\n")

                round_keys_file = None
                if self.round_keys_log_path:
                    # Append mode preserves all historical round-key dumps.
                    round_keys_file = open(
                        self.round_keys_log_path, "a", encoding="utf-8")

                if self.use_framing:
                    self._send_sot(ser)
                    if not self._expect_sot(ser):
                        print("Frame error: did not receive SOT from device.")
                        return
                    ser.flush()
                    time.sleep(0.5)  # 50 ms, change as required
                    self._send_mode_byte(ser)
                    self._send_packet_count(ser, total_packets_to_send)
                    ready = self._read_exact(ser, 1)
                    if ready != bytes([0x03]):
                        print("Frame error: did not receive READY from device.")
                        return

                for i in range(0, len(payload), self.packet_size):
                    send_packet = payload[i: i + self.packet_size]
                    
                    if len(send_packet) < self.packet_size:
                        send_packet = send_packet.ljust(self.packet_size, b'\x00')

                    # Send raw bytes to hardware
                    if packet_count < 10:
                        print(
                            f"Sending packet to PIC {packet_count + 1}: {send_packet.hex()}")
                    if packet_count == 10:
                        print(
                            "(additional packets will not be printed to avoid console overflow)")
                    tx_payload = send_packet
                    tx_bytes = self._build_packet_with_checksum(
                        tx_payload) if self.use_framing else tx_payload
                    txn_start = time.perf_counter()
                    ser.write(tx_bytes)

                    # Read payload from hardware: 16 data + 4 timer bytes + 176 round-key bytes
                    recv_total_len = self.packet_size + 4 + self.round_keys_size
                    recv_total = self._read_packet_payload(ser, recv_total_len)
                    txn_end = time.perf_counter()

                    if recv_total is None or len(recv_total) < recv_total_len:
                        txn_us = (txn_end - txn_start) * 1_000_000.0
                        print(
                            f"Timeout at packet {packet_count + 1} (transaction {txn_us:.2f} us)")
                        break

                    recv_packet = recv_total[:self.packet_size]
                    enc_ticks = int.from_bytes(
                        recv_total[self.packet_size:self.packet_size + 2], 'little')
                    dec_ticks = int.from_bytes(
                        recv_total[self.packet_size + 2:self.packet_size + 4], 'little')
                    TICK_US = 0.25
                    round_keys = recv_total[self.packet_size +
                                            4:self.packet_size + 4 + self.round_keys_size]
                    enc_us = enc_ticks * TICK_US
                    dec_us = dec_ticks * TICK_US
                    txn_us = (txn_end - txn_start) * 1_000_000.0
                    txn_s = txn_us / 1_000_000.0
                    rx_wire_bytes = recv_total_len + \
                        (1 if self.use_framing else 0)
                    wire_bytes = len(tx_bytes) + rx_wire_bytes
                    throughput_mb_s = (
                        wire_bytes / 1_000_000.0) / txn_s if txn_s > 0 else 0.0
                    print(f"  Packet {packet_count + 1} timings \u2014 encrypt: {enc_us:.2f} \u00b5s ({enc_ticks} ticks), "
                          f"decrypt: {dec_us:.2f} \u00b5s ({dec_ticks} ticks), "
                          f"transaction: {txn_us:.2f} \u00b5s, "
                          f"throughput: {throughput_mb_s:.3f} MB/s "
                          f"[raw: {recv_total[self.packet_size:self.packet_size+4].hex()}]")
                    if timing_file:
                        timing_file.write(
                            f"{packet_count + 1},{enc_us:.1f},{dec_us:.1f},{txn_us:.1f},{throughput_mb_s:.3f}\n")

                    if round_keys_file:
                        round_keys_file.write(round_keys.hex() + "\n")

                    if is_bmp:
                        bmp_recv_pixels.extend(recv_packet)
                        # No need to increment bytes_written here, handled at the end
                    else:
                        packet_to_write = recv_packet
                        if not self._uses_hex_text_format(self.receive_path):
                            # Trim padding for raw binary files
                            remaining_bytes = len(data) - bytes_written
                            packet_to_write = recv_packet[:remaining_bytes]
                        
                        self._write_output_packet(f_recv, packet_to_write)
                        bytes_written += len(packet_to_write)

                    packet_count += 1

                if timing_file:
                    timing_file.close()
                    print(f"Timings saved to {self.timing_log_path}")

                if round_keys_file:
                    round_keys_file.close()
                    print(f"Round keys appended to {self.round_keys_log_path}")

                if key_file:
                    key_file.close()
                    print(f"Keys saved to {self.key_log_path}")
                
                # For BMP: write reconstructed file with original header + encrypted/decrypted pixels
                if is_bmp and bmp_recv_pixels is not None:
                    with open(self.receive_path, 'wb') as out_bmp:
                        out_bmp.write(bmp_header)
                        # Write only the received pixel bytes (up to original pixel data length)
                        orig_pixel_len = len(payload)
                        pixel_slice = bytes(bmp_recv_pixels)[:orig_pixel_len]
                        out_bmp.write(pixel_slice)
                    print(f"Reconstructed BMP written to {self.receive_path}")

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
    file_type = 2

    if file_type == 0:  # Example usage: .TXT file, encryption mode, with framing and logging.
        transfer_txt = FileTransfer(send_path='tester.txt',
                                    receive_path='tester_out.txt',
                                    serial_port='COM4',
                                    timing_log_path='timings.txt',
                                    round_keys_log_path='round_keys_history.txt',
                                    use_framing=True,
                                    encryption_mode=True)
        transfer_txt.file_exchange()
    elif file_type == 1:  # Example usage: .TXT file, decryption mode.
        transfer_txt_dec = FileTransfer(send_path='tester_out.txt',
                                        receive_path='tester_out_dec.txt',
                                        serial_port='COM4',
                                        timing_log_path='timings.txt',
                                        round_keys_log_path='round_keys_history.txt',
                                        use_framing=True,
                                        encryption_mode=False)
        transfer_txt_dec.file_exchange()
    else:  # Example usage: .BMP file, encryption mode, with selective pixel-data encryption.
        transfer_bmp = FileTransfer(send_path='tester.bmp',
                                    receive_path='tester_encrypted.bmp',
                                    serial_port='COM4',
                                    timing_log_path='timings.txt',
                                    round_keys_log_path='round_keys_history.txt',
                                    use_framing=True,
                                    encryption_mode=True)
        transfer_bmp.file_exchange()
