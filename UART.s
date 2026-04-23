#include <xc.inc>

;; This module implements all UART communication procedures with the serial port.

global  UART_Setup, UART_Transmit_Message, UART_Receive_Package, UART_Send_Package, UART_Send_Round_Keys, UART_Send_Timers, session_mode
extrn   pkg_buffer, Round_Keys, encryption_timer, decryption_timer
extrn	Key_Setup
extrn	EEPROM_Read_Buffer

psect	udata_acs
UART_counter: ds 1
rx_counter: ds  1
rx_checksum: ds 1
tx_checksum: ds 1
session_active: ds 1
rx_first_byte: ds 1
match_counter: ds 1
packets_remaining: ds 2
session_mode: ds 1

psect   const_data,class=CONST,reloc=2
SOT_Seq: ; Define an arbitrary Start Of Transmission sequence.
    db      0x3A, 0xC5, 0x7E, 0x11, 0xD2, 0x9B, 0x4F, 0x80

psect	uart_code,class=CODE
UART_Setup:
    bsf	    SPEN	                    ; Enable serial port
    bcf	    SYNC	                    ; Synchronous mode
    bcf	    BRGH	                    ; Slow speed
    bsf	    TXEN	                    ; Enable transmit
    bcf	    BRG16	                    ; 8-bit generator only
    movlw   103		                    ; 9600 Baud rate (actually 9615)
    movwf   SPBRG1, A	                ; set baud rate
    bsf	    TRISC, PORTC_TX1_POSN, A	; TX1 pin is output on RC6 pin

    clrf    session_active, A           ; No session active at the start
    clrf    rx_checksum, A              ; Clear the checksum accumulators
    clrf    tx_checksum, A              ; To be used by the first package sent/received
    return

UART_Transmit_Message: ; Transmit a message of length in W, starting at FSR2
    movwf   UART_counter, A

UART_Loop_message:     ; Loop to transmit message bytes, decrementing counter until zero
    movf    POSTINC2, W, A
    call    UART_Transmit_Byte
    decfsz  UART_counter, A
    bra	    UART_Loop_message
    return

UART_Transmit_Byte:	   ; Transmits byte stored in W
    btfss   TX1IF	    ; TX1IF is set when TXREG1 is empty
    bra	    UART_Transmit_Byte
    movwf   TXREG1, A
    return

UART_Receive_Byte: ; Receives a byte and returns it in W
    btfsc   RCSTA1, 1, A        ; Check for framing error
    call    Handle_Overrun      ; Clear the error and continue (user should check for validity of packet after receiving)

    btfss   PIR1, 5, A          ; Check for overrun error
    bra     UART_Receive_Byte   ; Clear the error and continue (user should check for validity of packet after receiving)
    movf    RCREG1, W, A        ; Read the received byte
    return

UART_Receive_Package:
    bsf     RCSTA1, 4, A            ; Enable continuous reception (CREN = bit 4 of RCSTA1)

    btfss   session_active, 0, A    ; Check if a session is already active
    bra     RX_Wait_SOT_Init	    ; Wait for an SOT sequence
    bra     RX_Read_First           ; Read the next packet

RX_Wait_SOT_Init:                   ; Wait for the Start Of Transmission sequence from the host
    movlw   low(SOT_Seq)            ; Load the address of SOT_Seq into TBLPTR
    movwf   TBLPTRL, A              ; Load the high byte of the address of SOT_Seq into TBLPTRH 
    movlw   high(SOT_Seq)           ; Load the low byte of the address of SOT_Seq into TBLPTRU
    movwf   TBLPTRH, A              ; Load the high byte of the address of SOT_Seq into TBLPTRU
    movlw   low(highword(SOT_Seq))
    movwf   TBLPTRU, A
    movlw   8
    movwf   match_counter, A        ; Set the match counter to the length of the SOT sequence

RX_Wait_Loop:
    call    UART_Receive_Byte
    
    tblrd*                          ; Read the current byte of SOT_Seq into TABLAT and increment TBLPTR
    cpfseq  TABLAT, A               ; Compare W with TABLAT 
    bra     Sequence_Failed         ; Branch away if not

    tblrd*+                         ; Increment to next expected byte
    decfsz  match_counter, F, A     ; Decrement byte count
    bra     RX_Wait_Loop            ; If counter is not zero, wait for next byte

    bsf     session_active, 0, A    ; Mark session as active
    bra     Session_Started         ; Branch to receiving code

Sequence_Failed:
    ; If any byte is wrong, start again
    bra     RX_Wait_SOT_Init

Session_Started:  
    movlw   0x02                    ; Send ACK for SOT received
    call    UART_Transmit_Byte
    
    call    UART_Receive_Byte       ; Mode Byte 
    movwf   session_mode, A
    
    call    UART_Receive_Byte	    ; Packet Number
    movwf   packets_remaining, A 
    
    call    UART_Receive_Byte	    ; Read the high byte of the packet count
    movwf   packets_remaining+1, A
    
    movf    session_mode, W, A      ; Check the mode byte
    xorlw   0x01
    bz	    Encryption_Setup        ; If bit 0 is set, encryption only, so skip decryption setup
    
    movf    session_mode, W, A      ; Check the mode byte again
    xorlw   0x00                
    bz	    Decryption_Setup        ; If bit 1 is set, decryption only, so skip encryption setup
    
    movf    session_mode, W, A      ; Check the mode byte again
    xorlw   0x02
    bz	    Encryption_Setup        ; If bit 2 is set, encryption and decryption.
    
Encryption_Setup:
    call    Key_Setup           ; Set up the encryption key in RAM
    bra	    Session_Ready       ; Branch to receiving code
    
Decryption_Setup:
    call   EEPROM_Read_Buffer   ; Set up the decryption key in RAM by reading it from EEPROM
    bra	   Session_Ready        ; Branch to receiving code

Session_Ready:
    movlw   0x03                ; ACK ready for first packet
    call    UART_Transmit_Byte
    bra     RX_Read_First       ; Read the first packet of the session
    
RX_Read_First: 
; Read the first packet of the session. Handled separately from the remaining packets as the checksum is calculated only over the payload bytes.
    call    UART_Receive_Byte
    movwf   rx_first_byte, A    ; Store payload byte

    lfsr    2, pkg_buffer       ; Point FSR2 to the start of the packet buffer to store the received bytes
    movlw   16                  ; Load the expected packet length (16 bytes) into W
    movwf   rx_counter, A       ; Store the expected packet length in rx_counter for the loop to read the remaining bytes of the packet
    clrf    rx_checksum, A      ; Clear the checksum accumulator before reading the packet bytes

    movf    rx_first_byte, W, A ; Add the first byte to the checksum
    addwf   rx_checksum, F, A   ; Store the first byte in the packet buffer
    movwf   POSTINC2, A
    decfsz  rx_counter, A       ; Decrement the counter for the remaining bytes and check if zero
    bra     RX_Read_Remaining
    bra     RX_Read_Checksum

RX_Read_Remaining:
    call    UART_Receive_Byte
    addwf   rx_checksum, F, A   ; Add the received byte to the checksum
    movwf   POSTINC2, A         ; Store the received byte in the packet buffer and increment the pointer
    decfsz  rx_counter, A       ; Decrement the counter for the remaining bytes and check if zero
    bra     RX_Read_Remaining

RX_Read_Checksum:
    call    UART_Receive_Byte
    cpfseq  rx_checksum, A              ; Compare with the received checksum byte
    bra     UART_Receive_Package        ; Invalid packet, start over (user should check for validity of packet after receiving)

    movf    packets_remaining, W, A     ; Check if the low byte of the packet count is zero
    bnz     Decrement_Low               ; If nonzero, skip the borrow
    decf    packets_remaining+1, F, A   ; if zero, borrow the high byte

Decrement_Low:
    decf    packets_remaining, F, A
    movf    packets_remaining, W, A     ; Check if the low byte of the packet count is zero again after decrementing
    iorwf   packets_remaining+1, W, A   ; If both bytes are now zero, all packets have been received
    
    bz      Session_Complete            ; if the result is zero, have 0x0000
    return                              ; return to main loop for processing

Session_Complete:
    bcf     session_active, 0, A        ; Mark session as inactive
    return

Handle_Overrun: ; Clear the overrun error
    bcf     RCSTA1, 4, A   ; CREN = bit 4 of RCSTA1
    bsf     RCSTA1, 4, A
    bcf     RCSTA1, 4, A   ; CREN = bit 4 of RCSTA1
    bsf     RCSTA1, 4, A
    return

Handle_Framing: ; Clear the framing error
    movf    RCREG1, W, A            ; Read RCREG to clear the error
    bra     UART_Receive_Package

UART_Send_Package:  ; Send the 16-byte package in pkg_buffer with a checksum byte at the end
    lfsr    2, pkg_buffer                       ; Point FSR2 to the start of the packet buffer
    movlw   16                                  ; Load the packet length (16 bytes) into W
    clrf    tx_checksum, A                      ; Clear the checksum accumulator before sending the packet bytes
    call    UART_Transmit_Message_With_Checksum
    return

UART_Send_Round_Keys:   ; Send the 176 bytes of round keys starting at Round_Keys with a checksum byte at the end
    lfsr    2, Round_Keys                       ; Point FSR2 to the start of the round keys
    movlw   176                                 ; Load the round key length (176 bytes) into W
    call    UART_Transmit_Message_With_Checksum
    movf    tx_checksum, W, A                   ; After sending the round keys, transmit the checksum byte
    call    UART_Transmit_Byte
    return

UART_Send_Timers:  ; Send the 4 timer bytes (enc_low, enc_high, dec_low, dec_high)
    lfsr    2, encryption_timer ; Point FSR2 to the start of the timer values
    movlw   4                   ; Load the timer byte length (4 bytes) into W
    call    UART_Transmit_Message_With_Checksum
    return

UART_Transmit_Message_With_Checksum: ; Transmits a message of length in W, starting at FSR2, and calculates a checksum
    movwf   UART_counter, A          ; Store the message length

UART_WithChecksum_Loop:              ; Loop to transmit and compute checksum
    movf    POSTINC2, W, A           ; Read the next byte of the message and increment the pointer
    addwf   tx_checksum, F, A        ; Add the byte to the checksum
    call    UART_Transmit_Byte
    decfsz  UART_counter, A         
    bra     UART_WithChecksum_Loop
    return
