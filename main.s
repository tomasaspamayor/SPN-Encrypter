#include <xc.inc>

global  pkg_buffer
extrn   UART_Setup, UART_Receive_Package, UART_Send_Package
extrn	SBOX_Encrypt_Byte, SBOX_Encrypt_Buffer, SBOX_Decrypt_Byte, SBOX_Decrypt_Buffer
extrn	Key_Setup
extrn   P_Box_Enc, P_Box_Dec

psect  udata_acs
pkg_buffer:  ds 16
CLEAR_CNT:   ds 1          ; Counter for clearing buffer
n_cycles:    ds 1          ; Counter for number of encryption cycles


psect   code
Setup:
        call    UART_Setup          ; Initialize UART
        call    Key_Setup		    ; generate key
        ; generate keys and start scheduling

Encrypt:
        movlw  10                  ; Number of encryption cycles
        movwf  n_cycles, A         ; Store in cycle counter variable

        ; mix first key

    Encrypt_Loop:
        call    SBOX_Encrypt_Buffer
        call    P_Box_Enc

        ; mix all other keys

        decfsz  n_cycles, F, A         ; Decrement cycle counter, skip if zero
        bra     Encrypt_Loop


Decrypt: 
        movlw   10                   ; Number of decryption cycles
        movwf   n_cycles, A          ; Store in cycle counter variable

        ; mix first key

    Decrypt_Loop:
        call    P_Box_Dec
        call    SBOX_Decrypt_Buffer

        ; mix all other keys

        decfsz  n_cycles, F, A         ; Decrement cycle counter, skip if zero
        bra     Decrypt_Loop

Loop:
        lfsr    2, pkg_buffer       ; FSR2 points to start of buffer
        movlw   16                  ; Number of bytes to clear
        movwf   CLEAR_CNT, A        ; Store in counter variable
        movlw   0                   ; Load 0 into WREG for clearing

Clear_Loop:
        movwf   POSTINC2, A            ; Write W=0 (clear) and increment pointer
        decfsz  WREG, F, A             ; Decrement counter, skip if zero
        bra     Clear_Loop

        call    UART_Receive_Package

        ; either encryopt or decrypt the package based on some condition 

        call    Encrypt

        call    Decrypt

        call    UART_Send_Package

        bra     Loop                ; Repeat indefinitely
