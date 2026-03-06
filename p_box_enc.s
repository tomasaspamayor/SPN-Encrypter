#include <xc.inc>

global  Shift_Rows, Mix_All_Columns
extrn   pkg_buffer

; GF(2^8) xtime macro: multiply W by 2 in GF(2^8) with AES polynomial
GF_X2 macro
    local no_reduce
    addwf   WREG, W, A      ; W = W << 1; carry = old MSB
    bnc     no_reduce       ; skip if no carry (MSB was 0)
    xorlw   0x1B            ; reduce by AES polynomial x^8+x^4+x^3+x+1
no_reduce:
    endm

psect	udata_acs   ; reserve data space in access ram
temp_buffer: ds 16	; temporary buffer for ShiftRows operation (16 bytes)
res_byte: ds 1	; Temporary variable to hold results during MixColumns
col_count: ds 1	; Column counter for Mix_All_Columns
copy_count: ds 1 ; Counter for copy-back loop
t0: ds 1	; Temporary variable for MixColumns
t1: ds 1
t2: ds 1
t3: ds 1


psect	uart_code, class=CODE
    
P_Box: 
    call    Shift_Rows
    
    return 

Shift_Rows:
    ; --- Row 0: No Shift ---
    ; [0, 4, 8, 12] -> [0, 4, 8, 12]
    movff   pkg_buffer+0,  temp_buffer+0
    movff   pkg_buffer+4,  temp_buffer+4
    movff   pkg_buffer+8,  temp_buffer+8
    movff   pkg_buffer+12, temp_buffer+12

    ; row 1, shift left 1
    ; [1, 5, 9, 13] -> [5, 9, 13, 1]
    movff   pkg_buffer+5,  temp_buffer+1   ; 5 moves to 1
    movff   pkg_buffer+9,  temp_buffer+5   ; 9 moves to 5
    movff   pkg_buffer+13, temp_buffer+9   ; 13 moves to 9
    movff   pkg_buffer+1,  temp_buffer+13  ; 1 (wrapped) moves to 13

    ; row 2, shift left 2
    ; [2, 6, 10, 14] -> [10, 14, 2, 6]
    movff   pkg_buffer+10, temp_buffer+2   ; 10 moves to 2
    movff   pkg_buffer+14, temp_buffer+6   ; 14 moves to 6
    movff   pkg_buffer+2,  temp_buffer+10  ; 2 (wrapped) moves to 10
    movff   pkg_buffer+6,  temp_buffer+14  ; 6 (wrapped) moves to 14

    ; row 3, shift left 3
    ; [3, 7, 11, 15] -> [15, 3, 7, 11]
    movff   pkg_buffer+15, temp_buffer+3   ; 15 moves to 3
    movff   pkg_buffer+3,  temp_buffer+7   ; 3 (wrapped) moves to 7
    movff   pkg_buffer+7,  temp_buffer+11  ; 7 (wrapped) moves to 11
    movff   pkg_buffer+11, temp_buffer+15  ; 11 (wrapped) moves to 15

    ; --- Copy temp_buffer back to pkg_buffer ---
    lfsr    0, temp_buffer
    lfsr    1, pkg_buffer
    movlw   16
    movwf   copy_count, A
Copy_Back:
    movff   POSTINC0, POSTINC1
    decfsz  copy_count, F, A
    bra     Copy_Back

    return

; ---------------------------------------------------------------------------------------------------------------------
Mix_All_Columns:
    lfsr    0, pkg_buffer       ; FSR0 = input (pkg_buffer)
    lfsr    1, temp_buffer      ; FSR1 = output (temp_buffer)
    movlw   4
    movwf   col_count, A
Mix_Col_Loop:
    call    Mix_Column
    decfsz  col_count, F, A
    bra     Mix_Col_Loop

    ; Copy temp_buffer back to pkg_buffer
    lfsr    0, temp_buffer
    lfsr    1, pkg_buffer
    movlw   16
    movwf   copy_count, A
Mix_Copy_Back:
    movff   POSTINC0, POSTINC1
    decfsz  copy_count, F, A
    bra     Mix_Copy_Back
    return

; --- Process a single column: reads 4 bytes via FSR0, writes 4 via FSR1 ---
Mix_Column:
    ; Load the 4 bytes of the current column
    movff   POSTINC0, t0    ; t0 = Byte 0
    movff   POSTINC0, t1    ; t1 = Byte 1
    movff   POSTINC0, t2    ; t2 = Byte 2
    movff   POSTINC0, t3    ; t3 = Byte 3

    ; Row 0 = (2*t0) ^ (3*t1) ^ t2 ^ t3
    ; Note: (3*t1) is just (2*t1 ^ t1)

    ; Calculate 2*t0
    movf    t0, W, A
    GF_X2
    movwf   res_byte, A        ; Start Result with (2*t0)

    ; Calculate 3*t1 and XOR
    movf    t1, W, A
    GF_X2                   ; W = 2*t1
    xorwf   t1, W, A           ; W = (2*t1) ^ t1 = 3*t1
    xorwf   res_byte, F, A     ; res_byte ^= 3*t1

    ; XOR t2 and t3
    movf    t2, W, A
    xorwf   res_byte, F, A
    movf    t3, W, A
    xorwf   res_byte, F, A

    ; Save Result for Byte 0
    movff   res_byte, POSTINC1 ; Write to out_buffer

    ; Row 1 = t0 ^ (2*t1) ^ (3*t2) ^ t3
    
    movf    t1, W, A
    GF_X2
    movwf   res_byte, A        ; Start with 2*t1
    
    movf    t2, W, A
    GF_X2
    xorwf   t2, W, A           ; W = 3*t2
    xorwf   res_byte, F, A
    
    movf    t0, W, A
    xorwf   res_byte, F, A
    movf    t3, W, A
    xorwf   res_byte, F, A
    
    movff   res_byte, POSTINC1

    ; Row 2 = t0 ^ t1 ^ (2*t2) ^ (3*t3)
    
    movf    t2, W, A
    GF_X2
    movwf   res_byte, A
    
    movf    t3, W, A
    GF_X2
    xorwf   t3, W, A
    xorwf   res_byte, F, A
    
    movf    t0, W, A
    xorwf   res_byte, F, A
    movf    t1, W, A
    xorwf   res_byte, F, A
    
    movff   res_byte, POSTINC1

    ; Row 3 = (3*t0) ^ t1 ^ t2 ^ (2*t3)
    
    movf    t3, W, A
    GF_X2
    movwf   res_byte, A
    
    movf    t0, W, A
    GF_X2
    xorwf   t0, W, A          ; W = 3*t0
    xorwf   res_byte, F, A
    
    movf    t1, W, A
    xorwf   res_byte, F, A
    movf    t2, W, A
    xorwf   res_byte, F, A
    
    movff   res_byte, POSTINC1
    
    return