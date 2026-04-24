#include <xc.inc>
; P-Box transformation module for AES encryption. Applies ShiftRows and MixColumns operations to 16-byte plaintext blocks. Dependencies: pkg_buffer (16-byte data state), GF_X2 macro.

global  P_Box_Enc, Shift_Rows, Mix_All_Columns
extrn   pkg_buffer

; GF(2^8) macro: multiply W by 2 in GF(2^8) with AES polynomial
GF_X2 macro
    local no_reduce
    addwf   WREG, W, A      
    bnc     no_reduce       
    xorlw   0x1B
no_reduce:
    endm

psect	udata_acs   ; reserve data space in access ram
count_h: ds 1
count_l: ds 1
cnt_ms: ds 1
    
temp_buffer_enc: ds 16	    ; temporary buffer for ShiftRows operation (16 bytes)
res_byte_enc: ds 1	        ; Temporary variable to hold results during MixColumns
col_count_enc: ds 1	        ; Column counter for Mix_All_Columns
copy_count_enc: ds 1        ; Counter for copy-back loop
; Temporary variables for MixColumns
t0_e: ds 1	
t1_e: ds 1
t2_e: ds 1
t3_e: ds 1

psect	uart_code, class=CODE

P_Box_Enc:
        ; Applies P-Box (ShiftRows then MixColumns) to pkg_buffer in-place.
        ; Dependencies: Shift_Rows, Mix_All_Columns.
        call    Shift_Rows
        call	Mix_All_Columns
        return 

Shift_Rows:
        ; Applies ShiftRows transformation (cyclic row left shifts) to pkg_buffer in-place.
        ; Dependencies: pkg_buffer, temp_buffer_enc.

        ; first, clear the temporary buffer
	    lfsr    0, temp_buffer_enc
        movlw   16
        movwf   copy_count_enc, A
        
    Clear_temp_buffer_enc:
        clrf    POSTINC0, A
        decfsz  copy_count_enc, F, A
        bra     Clear_temp_buffer_enc

	
        ; --- Row 0: No Shift ---
        ; [0, 4, 8, 12] -> [0, 4, 8, 12]
        movff   pkg_buffer+0x00,  temp_buffer_enc+0x00
        movff   pkg_buffer+0x04,  temp_buffer_enc+0x04
        movff   pkg_buffer+0x08,  temp_buffer_enc+0x08
        movff   pkg_buffer+0x0C, temp_buffer_enc+0x0C
	
        ; row 1, shift left 1
        ; [1, 5, 9, 13] -> [5, 9, 13, 1]
        movff   pkg_buffer+0x05,  temp_buffer_enc+0x01   ; 5 moves to 1
        movff   pkg_buffer+0x09,  temp_buffer_enc+0x05   ; 9 moves to 5
        movff   pkg_buffer+0x0D, temp_buffer_enc+0x09   ; 13 moves to 9
        movff   pkg_buffer+0x01,  temp_buffer_enc+0x0D  ; 1 (wrapped) moves to 13
	
        ; row 2, shift left 2
        ; [2, 6, 10, 14] -> [10, 14, 2, 6]
        movff   pkg_buffer+0x0A, temp_buffer_enc+0x02   ; 10 moves to 2
        movff   pkg_buffer+0x0E, temp_buffer_enc+0x06   ; 14 moves to 6
        movff   pkg_buffer+0x02,  temp_buffer_enc+0x0A  ; 2 (wrapped) moves to 10
        movff   pkg_buffer+0x06,  temp_buffer_enc+0x0E  ; 6 (wrapped) moves to 14
	
        ; row 3, shift left 3
        ; [3, 7, 11, 15] -> [15, 3, 7, 11]
        movff   pkg_buffer+0x0F, temp_buffer_enc+0x03   ; 15 moves to 3
        movff   pkg_buffer+0x03,  temp_buffer_enc+0x07   ; 3 (wrapped) moves to 7
        movff   pkg_buffer+0x07,  temp_buffer_enc+0x0B  ; 7 (wrapped) moves to 11
        movff   pkg_buffer+0x0B, temp_buffer_enc+0x0F  ; 11 (wrapped) moves to 15
	
        ; Copy temp_buffer_enc back to pkg_buffer
        lfsr    0, temp_buffer_enc
        lfsr    1, pkg_buffer
        movlw   16
        movwf   copy_count_enc, A
    Copy_Back_enc:	
        movf    POSTINC0, W, A
        movwf   POSTINC1, A
        decfsz  copy_count_enc, F, A
        bra     Copy_Back_enc

        return

; ---------------------------------------------------------------------------------------------------------------------
Mix_All_Columns:
        ; Applies MixColumns transformation to all 4 columns of pkg_buffer. Updates pkg_buffer in-place.
        ; Dependencies: Mix_Column, GF_X2 macro, temp_buffer_enc.
        lfsr    0, pkg_buffer       ; FSR0 = input (pkg_buffer)
        lfsr    1, temp_buffer_enc      ; FSR1 = output (temp_buffer_enc)
        movlw   4
        movwf   col_count_enc, A

    Mix_Col_Loop:   ; iteratively mix each column
        call    Mix_Column
        decfsz  col_count_enc, F, A
        bra     Mix_Col_Loop

        ; Move temp_buffer_enc back to pkg_buffer
        lfsr    0, temp_buffer_enc
        lfsr    1, pkg_buffer
        movlw   16
        movwf   copy_count_enc, A

    Mix_Copy_Back:
        movf    POSTINC0, W, A
        movwf   POSTINC1, A
        decfsz  copy_count_enc, F, A
        bra     Mix_Copy_Back
        return

; reads 4 bytes from FSR0, writes output 4 bytes to FSR1
Mix_Column:
        ; Computes MixColumns matrix multiplication (2,3,1,1 coefficients) on one column. Uses FSR0/FSR1 pointers.
        ; Dependencies: GF_X2 macro, t0_e-t3_e, res_byte_enc registers.
        ; read in first column
        movff   POSTINC0, t0_e    ; t0_e = byte 0
        movff   POSTINC0, t1_e    ; t1_e = byte 1
        movff   POSTINC0, t2_e    ; t2_e = byte 2
        movff   POSTINC0, t3_e    ; t3_e = byte 3

        ; --------------------------------------------------------------------------------
        ; Row 0 = (2*t0_e) ^ (3*t1_e) ^ t2_e ^ t3_e
        ; 2*t0_e
        movf    t0_e, W, A
        GF_X2
        movwf   res_byte_enc, A        

        ; ^ 3*t1_e 
        movf    t1_e, W, A
        GF_X2
        xorwf   t1_e, W, A           
        xorwf   res_byte_enc, F, A     

        ; t2_e ^ t3_e
        movf    t2_e, W, A
        xorwf   res_byte_enc, F, A
        movf    t3_e, W, A
        xorwf   res_byte_enc, F, A

        ; Save
        movff   res_byte_enc, POSTINC1 

        ; --------------------------------------------------------------------------------
        ; Row 1 = t0_e ^ (2*t1_e) ^ (3*t2_e) ^ t3_e
        ; 2*t1_e
        movf    t1_e, W, A
        GF_X2
        movwf   res_byte_enc, A        
        
        ; ^ 3*t2_e
        movf    t2_e, W, A
        GF_X2
        xorwf   t2_e, W, A         
        xorwf   res_byte_enc, F, A
        
        ; ^ t0_e ^ t3_e
        movf    t0_e, W, A
        xorwf   res_byte_enc, F, A
        movf    t3_e, W, A
        xorwf   res_byte_enc, F, A
        
        movff   res_byte_enc, POSTINC1
        
        ; --------------------------------------------------------------------------------
        ; Row 2 = t0_e ^ t1_e ^ (2*t2_e) ^ (3*t3_e)
        
        ;   2*t2_e
        movf    t2_e, W, A
        GF_X2
        movwf   res_byte_enc, A
        
        ; ^ 3*t3_e
        movf    t3_e, W, A
        GF_X2
        xorwf   t3_e, W, A
        xorwf   res_byte_enc, F, A
        
        ; ^ t0_e ^ t1_e
        movf    t0_e, W, A
        xorwf   res_byte_enc, F, A
        movf    t1_e, W, A
        xorwf   res_byte_enc, F, A
        
        ; save
        movff   res_byte_enc, POSTINC1

        ; --------------------------------------------------------------------------------
        ; Row 3 = (3*t0_e) ^ t1_e ^ t2_e ^ (2*t3_e)
        
        ; 2*t3_e
        movf    t3_e, W, A
        GF_X2
        movwf   res_byte_enc, A
        
        ; ^ 3*t0_e
        movf    t0_e, W, A
        GF_X2
        xorwf   t0_e, W, A          ; W = 3*t0_e
        xorwf   res_byte_enc, F, A
        
        ; ^ t1_e ^ t2_e
        movf    t1_e, W, A
        xorwf   res_byte_enc, F, A
        movf    t2_e, W, A
        xorwf   res_byte_enc, F, A
        
        ; save 4th byte
        movff   res_byte_enc, POSTINC1

        
        return

	