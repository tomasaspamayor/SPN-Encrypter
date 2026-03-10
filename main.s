#include <xc.inc>

global  pkg_buffer
extrn   UART_Setup, UART_Receive_Package, UART_Send_Package
extrn	SBOX_Encrypt_Byte, Encrypt_Buffer, SBOX_Decrypt_Byte, Decrypt_Buffer
extrn	Key_Setup, Mix_Key
extrn	P_Box_Enc, P_Box_Dec

psect  udata_acs
pkg_buffer:  ds 16
CLEAR_CNT:   ds 1          ; NEED THIS: counter variable for clearing buffer

psect   code
Setup:
    call    UART_Setup          ; Initialize UART
    call    Key_Setup		; generate key
Loop:
    ; --- Step 0: Clear pkg_buffer to avoid leftover RAM content ---
    lfsr    2, pkg_buffer       ; FSR2 points to start of buffer
    movlw   16                  ; Number of bytes to clear
    movwf   CLEAR_CNT, A        ; Store in counter variable
    movlw   0                   ; Load 0 into WREG for clearing
Clear_Loop:
    movwf   POSTINC2, A            ; Write W=0 (clear) and increment pointer
    decfsz  WREG, F, A             ; Decrement counter, skip if zero
    bra     Clear_Loop

    call    UART_Receive_Package
    
    call    P_Box_Enc
    call    P_Box_Dec

    call    UART_Send_Package

    bra     Loop                ; Repeat indefinitely
