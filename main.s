#include <xc.inc>

global  pkg_buffer
extrn   UART_Setup, UART_Receive_Package, UART_Send_Package
extrn	SBOX_Encrypt_Byte, SBOX_Encrypt_Buffer, SBOX_Decrypt_Byte, SBOX_Decrypt_Buffer
extrn	Key_Setup, Mix_Key, Key_Buffer
extrn	Test_Run_Expansion

; --- Reserve 16 bytes for the 128-bit packet ---
psect  udata_acs
pkg_buffer:  ds 16
CLEAR_CNT:   ds 1          ; NEED THIS: counter variable for clearing buffer

; --- Code section ---
psect   code
Setup:
    call    UART_Setup          ; Initialize UART
    call    Key_Setup		; generate key
Loop:
    ; --- Step 0: Clear pkg_buffer ---
    lfsr    2, pkg_buffer
    movlw   16
    movwf   CLEAR_CNT, A
Clear_Loop:
    clrf    POSTINC2, A         ; Explicitly clear
    decfsz  CLEAR_CNT, F, A
    bra     Clear_Loop

    ; --- Step 1: Receive (TEMPORARILY COMMENT THIS OUT) ---
    ; call    UART_Receive_Package 

    ; --- Step 2: Process expansion with ZEROS ---
    call    Test_Run_Expansion

    ; --- Step 3: Send back to PC ---
    call    UART_Send_Package ; This should now send 16 zeros (or the expansion of zeros)

    bra     Loop                ; Repeat indefinitely
