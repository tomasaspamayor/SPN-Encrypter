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
    
psect   const_data,class=CONST,reloc=2
SOT_Seq:
    db      0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x02

psect   const_data,class=CONST,reloc=2
EOT_SEQ:
    db      0xBB, 0x66, 0xBB, 0x66, 0xBB, 0x66, 0xBB, 0x04

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

RX_Wait_EOT_Init:
    movlw   low(EOT_Seq)
    movwf   TBLPTRL, A
    movlw   high(EOT_Seq)
    movwf   TBLPTRH, A
    movlw   low(highword(EOT_Seq))
    movwf   TBLPTRU, A
    
    movlw   8
    movwf   match_counter, A

RX_EOT_Loop:
    call    UART_Receive_Byte     
    
    tblrd* ; read eot byte into tablat
    
    cpfseq  TABLAT, A               ; compare received byte with expected byte
    bra     EOT_Sequence_Failed     ; branch off if no match

    ; match
    tblrd*+                         ; goto next expected byte
    decfsz  match_counter, F, A     ; decrement byte count
    bra     RX_EOT_Loop             ; if not zero, wait for next

    ; all matches
    movlw   0x04                    ; ACK the EOT to the host PC
    call    UART_Transmit_Byte
    
    bcf     session_active, 0, A    ; reset the session flag
    clrf    key_generated, A        ; clear the key flag
    
    bra     UART_Receive_Package    ; Go back to the very beginning to wait for a new SOT

EOT_Sequence_Failed:
    ; any failures, start again
    bra     RX_Wait_EOT_Init
    
    ; if end of package contains EOT marker, reset key generated flag to 0 for next package
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
