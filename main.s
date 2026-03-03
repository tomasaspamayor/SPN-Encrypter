#include <xc.inc>

global  pkg_buffer
extrn   UART_Setup, UART_Receive_Package, UART_Send_Package

; --- Reserve 16 bytes for the 128-bit packet ---
psect   udata_acs
pkg_buffer:  ds 16

; --- Code section ---
psect   code
Main:
    call    UART_Setup          ; Initialize UART
Loop:

    ; --- Step 0: Clear pkg_buffer to avoid leftover RAM content ---
    lfsr    2, pkg_buffer       ; FSR2 points to start of buffer
    movlw   16                  ; Number of bytes to clear
Clear_Loop:
    movwf   POSTINC2            ; Write W=0 (clear) and increment pointer
    decfsz  WREG, F
    bra     Clear_Loop

    ; --- Step 1: Receive 16-byte packet from PC ---
    call    UART_Receive_Package

    ; --- Step 2: Process the buffer (optional encryption/decryption) ---
    ; [Insert your algorithm here, operating on pkg_buffer]

    ; --- Step 3: Send the 16-byte packet back to PC ---
    call    UART_Send_Package

    bra     Loop                ; Repeat forever
    