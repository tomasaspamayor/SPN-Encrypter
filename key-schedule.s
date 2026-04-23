#include <xc.inc>

;; This module implements the Key Schedule for the AES Encrypter.

global  Key_Schedule
extrn   SBOX_Encrypt_Byte, Key_Buffer, Round_Keys

psect   udata_acs 
KS_count_reg: ds 1 ; Counter variable for loops
KS_round_idx: ds 1 ; Round index for Rcon lookup
; Temporary storage for the G-Function output
KS_Temp_0:    ds 1
KS_Temp_1:    ds 1
KS_Temp_2:    ds 1
KS_Temp_3:    ds 1

psect    ks_code,class=CODE
Rcon_Table:
    db 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36 ; Standard Rcon values for AES-128

Schedule_Setup:
    ; We copy the master key into the first 16 bytes of the round key buffer
    lfsr    0, Key_Buffer   ; FSR0 points to start of master key
    lfsr    1, Round_Keys   ; FSR1 points to start of round keys
    movlw   16              ; Number of bytes to copy
    movwf   KS_count_reg, A ; Store in counter variable
    
Copy_Master:
    movff   POSTINC0, POSTINC1  ; Copy byte and increment both pointers
    decfsz  KS_count_reg, f, A  ; Decrement counter, skip if zero
    bra     Copy_Master         ; Loop until all 16 bytes are copied

    ; Initialise FSRs for the loop
    lfsr    0, Round_Keys       ; Point to Word 0
    lfsr    1, Round_Keys + 16  ; Point to Word 4
    
    clrf    KS_round_idx, A     ; Clear round index for loop control

Main_Expansion_Loop:
    ; The G-Function:

    ; We first produce the rotations    
    movlw   253
    movff   PLUSW1, KS_Temp_0
    movlw   254
    movff   PLUSW1, KS_Temp_1
    movlw   255
    movff   PLUSW1, KS_Temp_2
    movlw   252
    movff   PLUSW1, KS_Temp_3

    ; We then apply the S-Box substitution with the subroutine
    movf    KS_Temp_0, w, A
    call    SBOX_Encrypt_Byte
    movwf   KS_Temp_0, A

    movf    KS_Temp_1, w, A
    call    SBOX_Encrypt_Byte
    movwf   KS_Temp_1, A

    movf    KS_Temp_2, w, A
    call    SBOX_Encrypt_Byte
    movwf   KS_Temp_2, A

    movf    KS_Temp_3, w, A
    call    SBOX_Encrypt_Byte
    movwf   KS_Temp_3, A

    ; Finally we XOR with the defined Rcon value
    movf    KS_round_idx, w, A
    call    Get_Rcon
    xorwf   KS_Temp_0, f, A

    ; We generate W[i] by XORing the G-function result with W[i-4]
    movf    POSTINC0, w, A
    xorwf   KS_Temp_0, w, A
    movwf   POSTINC1, A

    movf    POSTINC0, w, A
    xorwf   KS_Temp_1, w, A
    movwf   POSTINC1, A

    movf    POSTINC0, w, A
    xorwf   KS_Temp_2, w, A
    movwf   POSTINC1, A

    movf    POSTINC0, w, A
    xorwf   KS_Temp_3, w, A
    movwf   POSTINC1, A

    ; We generate the next 3 words (W[i+1], W[i+2], W[i+3]) by XORing with the previous word
    movlw   12
    movwf   KS_count_reg, A          

XOR_Chain:
    movlw   252             ; Offset to the preivous word
    movf    PLUSW1, w, A    ; Load W[i-1] into WREG

    xorwf   POSTINC0, w, A      ; XOR with W[i-4] to get W[i+1]
    movwf   POSTINC1, A         ; Store W[i+1]
    decfsz  KS_count_reg, f, A  ; Decrement counter, skip if zero
    bra     XOR_Chain

    ; Loop Control
    incf    KS_round_idx, f, A  ; Increment round counter
    movlw   10                  ; Produce 10 round keys
    cpfseq  KS_round_idx, A     ; Compare and skip if round_idx == 10
    bra     Main_Expansion_Loop ; Loop back if not finished
    return

; SUBROUTINES

Get_Rcon:
    ; Input: WREG = round_idx (0-9)
    ; Output: WREG = Rcon value
    movwf   TBLPTRL, A      ; Temporarily store round_idx
    ; Set up base address of Rcon_Table
    movlw   LOW(Rcon_Table)
    addwf   TBLPTRL, f, A   ; TBLPTRL = LOW(Rcon_Table) + round_idx

    movlw   HIGH(Rcon_Table)
    movwf   TBLPTRH, A      ; Set TBLPTRH to high byte of Rcon_Table base
    btfsc   STATUS, 0, A    ; Check carry flag from previous add
    incf    TBLPTRH, f, A   ; Add carry to high byte if needed
    
    movlw   (Rcon_Table >> 16) & 0xFF ; High byte of Rcon_Table base (if needed)
    movwf   TBLPTRU, A                ; Set TBLPTRU to high byte of Rcon_Table base (if needed)
    
    tblrd*                  ; Read the Rcon value from the table
    movf    TABLAT, W, A    ; Result returned in WREG
    return

Key_Schedule:               ; Define a global entry point for the Key Schedule
    call    Schedule_Setup  ; Execute Key Schedule setup and expansion
    return
