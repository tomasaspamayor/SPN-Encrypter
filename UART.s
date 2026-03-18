#include <xc.inc>

global  UART_Setup, UART_Transmit_Message, UART_Receive_Package, UART_Send_Package, UART_Send_Round_Keys, UART_Send_Timers
extrn   pkg_buffer, Round_Keys, encryption_timer, decryption_timer
extrn	Key_Setup
extrn	EEPROM_Read_Buffer

psect	udata_acs   ; reserve data space in access ram
UART_counter: ds    1	    ; reserve 1 byte for variable UART_counter
rx_counter: ds  1       ; reserve 1 byte for variable rx_counter
rx_checksum: ds 1
tx_checksum: ds 1
session_active: ds 1
rx_first_byte: ds 1
key_generated: ds 1

psect	uart_code,class=CODE
UART_Setup:
    bsf	    SPEN	; enable
    bcf	    SYNC	; synchronous
    bcf	    BRGH	; slow speed
    bsf	    TXEN	; enable transmit
    bcf	    BRG16	; 8-bit generator only
    movlw   103		; gives 9600 Baud rate (actually 9615)
    movwf   SPBRG1, A	; set baud rate
    bsf	    TRISC, PORTC_TX1_POSN, A	; TX1 pin is output on RC6 pin
					; must set TRISC6 to 1
    clrf    session_active, A
    clrf    key_generated, A	; key generated flag
    clrf    rx_checksum, A
    clrf    tx_checksum, A
    return

UART_Transmit_Message:	    ; Message stored at FSR2, length stored in W
    movwf   UART_counter, A

UART_Loop_message:
    movf    POSTINC2, W, A
    call    UART_Transmit_Byte
    decfsz  UART_counter, A
    bra	    UART_Loop_message
    return

UART_Transmit_Byte:	    ; Transmits byte stored in W
    btfss   TX1IF	    ; TX1IF is set when TXREG1 is empty
    bra	    UART_Transmit_Byte
    movwf   TXREG1, A
    return

UART_Receive_Byte:
    btfss   PIR1, 5, A           ; RC1IF = bit 5 of PIR1
    bra     UART_Receive_Byte
    movf    RCREG1, W, A
    return

UART_Receive_Package:
    ; Session framing expected by PC side:
    ; SOT (0x02), then N * (16-byte payload + 1-byte checksum), then EOT (0x04)
    bsf     RCSTA1, 4, A

    btfsc   session_active, 0, A
    bra     No_Key_Gen

RX_Wait_SOT:
    call    UART_Receive_Byte
    xorlw   0x02
    bnz     RX_Wait_SOT
    bsf     session_active, 0, A
    
    ; generate key for use if the start of the package is detected (with SOT byte currently 0x02)
    
    ; double check that no key exists for this transmission using key_generated flag
    movlw   0x00                   
    cpfseq  key_generated, A       
    bra     No_Key_Gen              
    
    movlw   0x01
    movwf   key_generated, A        
    call    Key_Setup
    
    movlw   0x02                    ; ACK SOT to host
    call    UART_Transmit_Byte
    
    bra	    RX_Read_First
    
No_Key_Gen:
    call   EEPROM_Read_Buffer  ; load current key in EEPROM
    
RX_Read_First:
    call    UART_Receive_Byte
    movwf   rx_first_byte, A

    ; If session terminator arrives, ACK and wait for next session.
    movf    rx_first_byte, W, A
    xorlw   0x04
    bz      RX_Handle_EOT

    lfsr    2, pkg_buffer
    movlw   16
    movwf   rx_counter, A
    clrf    rx_checksum, A

    movf    rx_first_byte, W, A
    addwf   rx_checksum, F, A
    movwf   POSTINC2, A
    decfsz  rx_counter, A
    bra     RX_Read_Remaining
    bra     RX_Read_Checksum

RX_Read_Remaining:
    call    UART_Receive_Byte
    addwf   rx_checksum, F, A
    movwf   POSTINC2, A
    decfsz  rx_counter, A
    bra     RX_Read_Remaining

RX_Read_Checksum:
    call    UART_Receive_Byte       ; received checksum in W
    cpfseq  rx_checksum, A          ; compare with computed checksum
    bra     UART_Receive_Package    ; invalid packet: drop and resync

    return

RX_Handle_EOT:
    movlw   0x04                    ; ACK EOT to host
    call    UART_Transmit_Byte
    bcf     session_active, 0, A    ; reset the session flag
    
    ; if end of package contains 0x04 (EOT marker), reset key generated flag to 0 for next package
    movlw   0x00
    movwf   key_generated, A
    
    bra     UART_Receive_Package

Handle_Overrun:
    bcf     RCSTA1, 4, A   ; CREN = bit 4 of RCSTA1
    bsf     RCSTA1, 4, A
    bcf     RCSTA1, 4, A   ; CREN = bit 4 of RCSTA1
    bsf     RCSTA1, 4, A
    bra     UART_Receive_Package    ; Continue (current packet is likely corrupted)

Handle_Framing:
    movf    RCREG1, W, A    ; Read RCREG to clear the error
    bra     UART_Receive_Package    ; Continue (current packet is likely corrupted)

UART_Send_Package:
    lfsr    2, pkg_buffer   
    movlw   16
    clrf    tx_checksum, A
    call    UART_Transmit_Message_With_Checksum
    return

UART_Send_Round_Keys:
    lfsr    2, Round_Keys
    movlw   176
    call    UART_Transmit_Message_With_Checksum
    movf    tx_checksum, W, A
    call    UART_Transmit_Byte
    return

UART_Send_Timers:
    ; Send exactly 4 timer bytes (enc_low, enc_high, dec_low, dec_high)
    ; and update the running checksum ? do NOT transmit an intermediate checksum here.
    lfsr    2, encryption_timer
    movlw   4
    call    UART_Transmit_Message_With_Checksum
    return

UART_Transmit_Message_With_Checksum:
    movwf   UART_counter, A

UART_WithChecksum_Loop:
    movf    POSTINC2, W, A
    addwf   tx_checksum, F, A
    call    UART_Transmit_Byte
    decfsz  UART_counter, A
    bra     UART_WithChecksum_Loop
    return
