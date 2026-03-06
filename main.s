#include <xc.inc>

global  pkg_buffer
extrn   UART_Setup, UART_Receive_Package, UART_Send_Package
extrn	Key_Setup, Mix_Key
extrn	Run_P_Box, Mix_All_Columns, Shift_Rows

psect  udata_acs
pkg_buffer:  ds 16

psect   code
Setup:
    call    UART_Setup          ; Initialize UART
    call    Key_Setup		; generate key
Loop:
    ; --- Step 0: Clear pkg_buffer to avoid leftover RAM content ---
    lfsr    2, pkg_buffer       ; FSR2 points to start of buffer
    movlw   16                  ; Number of bytes to clear
Clear_Loop:
    movwf   POSTINC2            ; Write W=0 (clear) and increment pointer
    decfsz  WREG, F             ; Decrement counter, skip if zero
    bra     Clear_Loop

    call    UART_Receive_Package
    
    call    Shift_Rows

    call    UART_Send_Package
