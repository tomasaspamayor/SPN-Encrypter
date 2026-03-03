#include <xc.inc>

global  UART_Setup, UART_Transmit_Message, UART_Receive_Package, UART_Send_Package
extrn   pkg_buffer

psect	udata_acs   ; reserve data space in access ram
UART_counter: ds    1	    ; reserve 1 byte for variable UART_counter
rx_counter: ds  1       ; reserve 1 byte for variable rx_counter

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

UART_Receive_Package:
    ; --- Initialization ---
    lfsr    2, pkg_buffer    ; Point FSR2 to the start of our 16-byte RAM
    movlw   16              ; We expect exactly 16 bytes (128 bits)
    movwf   rx_counter, A
    bsf RCSTA1, 4   ; Enable Continuous Receive

Wait_Byte:
    ; --- Error Checking ---
    btfsc   RCSTA1, 1   ; OERR = bit 1 of RCSTA1
    bra     Handle_Overrun
    btfsc   RCSTA1, 2   ; FERR = bit 2 of RCSTA1
    bra     Handle_Framing

    ; --- Wait for Data ---
    btfss   PIR1, 5   ; RC1IF = bit 5 of PIR1
    bra     Wait_Byte       ; Keep polling until a byte is received

    ; --- Store Data ---
    movf    RCREG1, W, A    ; Read the byte (also clears RC1IF)
    movwf   POSTINC2, A     ; Store in buffer and increment pointer

    decfsz  rx_counter, A   ; Decrement loop counter
    bra     Wait_Byte       ; Get next byte if not finished
    
    return                  ; Buffer is now full (16 bytes received)

Handle_Overrun:
    bcf     RCSTA1, 4   ; CREN = bit 4 of RCSTA1
    bsf     RCSTA1, 4
    bra     Wait_Byte       ; Continue (Note: current packet is likely corrupted)

Handle_Framing:
    movf    RCREG1, W, A    ; Read RCREG to clear the error
    bra     Wait_Byte       ; Continue (Note: current packet is likely corrupted)

UART_Send_Package:
    ; --- Step 1: Point FSR2 back to the start of the package ---
    lfsr    2, pkg_buffer        ; FSR2 = Base address of our 16-byte data

    ; --- Step 2: Set the length for the transmit routine ---
    movlw   16                  ; W = 16 (number of bytes to send)

    ; --- Step 3: Call your existing global routine ---
    call    UART_Transmit_Message 

    return
