#include <xc.inc>

global  UART_Receive_Package, UART_Send_Package, pkg_buffer
extrn   UART_Setup, UART_Transmit_Message

; State 1: Listening from the PC

psect udata_acs
pkg_buffer:  ds  16      ; Reserve 16 bytes for the 128-bit packet
rx_counter: ds  1       ; Loop counter

UART_Receive_Package:
    ; --- Initialization ---
    lfsr    2, pkg_buffer    ; Point FSR2 to the start of our 16-byte RAM
    movlw   16              ; We expect exactly 16 bytes (128 bits)
    movwf   rx_counter, A
    bsf     CREN, A         ; Ensure Continuous Receive is enabled

Wait_Byte:
    ; --- Error Checking ---
    btfsc   OERR, A         ; Check for Overrun Error (data came too fast)
    bra     Handle_Overrun
    btfsc   FERR, A         ; Check for Framing Error (bad baud rate/noise)
    bra     Handle_Framing

    ; --- Wait for Data ---
    btfss   RC1IF, A        ; Check for bytes in RCREG1
    bra     Wait_Byte       ; Keep polling until a byte is received

    ; --- Store Data ---
    movf    RCREG1, W, A    ; Read the byte (also clears RC1IF)
    movwf   POSTINC2, A     ; Store in buffer and increment pointer

    decfsz  rx_counter, A   ; Decrement loop counter
    bra     Wait_Byte       ; Get next byte if not finished
    
    return                  ; Buffer is now full (16 bytes received)

Handle_Overrun:
    bcf     CREN, A         ; Reset the UART receiver logic
    bsf     CREN, A
    bra     Wait_Byte       ; Continue (Note: current packet is likely corrupted)

Handle_Framing:
    movf    RCREG1, W, A    ; Read RCREG to clear the error
    bra     Wait_Byte       ; Continue (Note: current packet is likely corrupted)

; State 2: ENCRYPTION or DECRYPTION happens here (not shown in this file)

; State 3: Transmitting to the PC

UART_Send_Package:
    ; --- Step 1: Point FSR2 back to the start of the package ---
    lfsr    2, pkg_buffer        ; FSR2 = Base address of our 16-byte data

    ; --- Step 2: Set the length for the transmit routine ---
    movlw   16                  ; W = 16 (number of bytes to send)

    ; --- Step 3: Call your existing global routine ---
    call    UART_Transmit_Message 

    return
