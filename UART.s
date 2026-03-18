#include <xc.inc>

global  UART_Setup, UART_Transmit_Message, UART_Receive_Package, UART_Send_Package, UART_Send_Round_Keys, UART_Send_Timers, session_mode
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
match_counter: ds 1
packets_remaining: ds 2
session_mode: ds 1
    
psect   const_data,class=CONST,reloc=2
SOT_Seq:
    db      0x3A, 0xC5, 0x7E, 0x11, 0xD2, 0x9B, 0x4F, 0x80
    
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
    btfsc   RCSTA1, 1, A
    call    Handle_Overrun
    
    btfss   PIR1, 5, A           ; RC1IF = bit 5 of PIR1
    bra     UART_Receive_Byte
    movf    RCREG1, W, A
    return

UART_Receive_Package:
    bsf     RCSTA1, 4, A

    btfsc   session_active, 0, A ; if session is not active
    bra     RX_Wait_SOT_Init	; wait for an SOT sequence

RX_Wait_SOT_Init:
    movlw   low(SOT_Seq)
    movwf   TBLPTRL, A
    movlw   high(SOT_Seq)
    movwf   TBLPTRH, A
    movlw   low(highword(SOT_Seq))
    movwf   TBLPTRU, A
    movlw   8
    movwf   match_counter, A

RX_Wait_Loop:
    call    UART_Receive_Byte      
    
    tblrd* ; read in first start of transmission byte
    cpfseq  TABLAT, A               ; Compare W with TABLAT 
    bra     Sequence_Failed         ; branch away if not

    ; match 
    tblrd*+                         ; increment to next expected byte
    decfsz  match_counter, F, A     ; decrement byte count
    bra     RX_Wait_Loop            ; if counter is not zero, wait for next byte

    ; all match
    bsf     session_active, 0, A    
    bra     Session_Started         ; branch to receiving code

Sequence_Failed:
    ; if any byte is wrong, start again
    bra     RX_Wait_SOT_Init

Session_Started:  
    movlw   0x02                    ; ACK SOT to host
    call    UART_Transmit_Byte
    
    call    UART_Receive_Byte       ; get the Instruction Byte 
    movwf   session_mode, A	    ; set the session mode
    
    call    UART_Receive_Byte	    ; packets remaining setter
    movwf   packets_remaining, A
    
    call    UART_Receive_Byte	    ; read second packets remaining byte
    movwf   packets_remaining+1, A
    
    movf    session_mode, W, A
    xorlw   0x01
    bz	    Encryption_Setup
    
    movf    session_mode, W, A
    xorlw   0x00
    bz	    Decryption_Setup
    
    movf    session_mode, W, A ; both encryption and decryption
    xorlw   0x02
    bz	    Encryption_Setup
    
Encryption_Setup:
    ; generate key for use if the start of the package is detected  
    call    Key_Setup
    bra	    Session_Ready
    
Decryption_Setup:
    call   EEPROM_Read_Buffer  ; load current key in EEPROM
    bra	   Session_Ready

Session_Ready:
    movlw   0x03                    ; ACK ready for first packet
    call    UART_Transmit_Byte
    bra     RX_Read_First
    
RX_Read_First:
    call    UART_Receive_Byte
    movwf   rx_first_byte, A

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

    movf    packets_remaining, W, A   ; load the low byte 
    bnz     Decrement_Low             ; if low byte is nonzero, skip the borrow
    decf    packets_remaining+1, F, A ; if the low byte is zero, borrow the high byte

Decrement_Low:
    ; dec the low byte
    decf    packets_remaining, F, A   

    ; check if the entire thing is 0x0000
    movf    packets_remaining, W, A   ; load low byte W
    iorwf   packets_remaining+1, W, A ; or the high byte with W
    
    bz      Session_Complete          ; if the result is zero, have 0x0000
    
    bra     UART_Receive_Package      ; If not, go to next package

Session_Complete:
    ; all packets recieved
    bcf     session_active, 0, A      
    bra     UART_Receive_Package

Handle_Overrun:
    bcf     RCSTA1, 4, A   ; CREN = bit 4 of RCSTA1
    bsf     RCSTA1, 4, A
    bcf     RCSTA1, 4, A   ; CREN = bit 4 of RCSTA1
    bsf     RCSTA1, 4, A
    return    ; Continue (current packet is likely corrupted)

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
