#include <xc.inc>

; This module implements the key schedule for the SPN cipher. It generates round keys from the initial key using a specific algorithm.

global  Key_Schedule ; We need to make the key schedule function available to other modules
extrn   SBOX_Encrypt_Byte, Key_Buffer, Round_Keys ; External S-Box byte routine (WREG in/out)

psect   udata_acs ; Use same psect as other modules to avoid memory overlap
KS_count_reg: ds 1   ; Renamed to avoid S-Box 'COUNT' conflict
KS_round_idx: ds 1
KS_Temp_0:    ds 1   ; Renamed to avoid S-Box 'TEMP' conflict
KS_Temp_1:    ds 1
KS_Temp_2:    ds 1
KS_Temp_3:    ds 1

psect   udata


psect    ks_code,class=CODE
Rcon_Table:
    db 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36 ; Rcon values for AES-128

Schedule_Setup:
    ; 1. Copy Master Key (16 bytes) from Key_Buffer to Round_Keys[0..15]
    lfsr    0, Key_Buffer ; FSR0 points to start of master key
    lfsr    1, Round_Keys ; FSR1 points to start of round keys
    movlw   16 ; Number of bytes to copy
    movwf   KS_count_reg, A ; Store in counter variable
    
Copy_Master:
    movff   POSTINC0, POSTINC1 ; Copy byte and increment both pointers
    decfsz  KS_count_reg, f, A ; Decrement counter, skip if zero
    bra     Copy_Master ; Loop until all 16 bytes are copied

    ; 2. Initialize Pointers for the Loop
    ; FSR0 will always point to W[i-4] (4 words ago)
    ; FSR1 will always point to W[i]   (current word being written)
    lfsr    0, Round_Keys       ; Point to Word 0
    lfsr    1, Round_Keys + 16  ; Point to Word 4 (Start of Round 1)
    
    clrf    KS_round_idx, A           ; round_idx = 0 (used for Rcon lookup)

Main_Expansion_Loop:
    ; --- STEP A: THE G-FUNCTION (RotWord) ---
    ; Using unique KS_Temp names to prevent S-Box memory collisions
    
    movlw   253             ; Byte 1 -> Becomes first byte
    movff   PLUSW1, KS_Temp_0
    movlw   254             ; Byte 2 -> Becomes second byte
    movff   PLUSW1, KS_Temp_1
    movlw   255             ; Byte 3 -> Becomes third byte
    movff   PLUSW1, KS_Temp_2
    movlw   252             ; Byte 0 -> Becomes fourth byte
    movff   PLUSW1, KS_Temp_3

    ; --- STEP A.2: SubWord (WREG in/out) ---
    ; WREG is used for transfer; KS_Temp variables hold the state
    
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
    
    ; --- STEP A.3: Rcon XOR ---
    movf    KS_round_idx, w, A
    call    Get_Rcon         ; WREG = Rcon[round_idx]
    
    ; XOR Rcon with the FIRST byte of the substituted word
    xorwf   KS_Temp_0, f, A

    ; --- STEP B: GENERATE W[i] (Word 4) ---
    movf    POSTINC0, w, A   ; Get W[0] byte 0 (0x2B)
    xorwf   KS_Temp_0, w, A  ; XOR with G-func byte 0
    movwf   POSTINC1, A      ; Result -> 0xA0

    movf    POSTINC0, w, A   ; Get W[0] byte 1 (0x7E)
    xorwf   KS_Temp_1, w, A  ; XOR with G-func byte 1
    movwf   POSTINC1, A      ; Result -> 0xFA

    movf    POSTINC0, w, A   ; Get W[0] byte 2 (0x15)
    xorwf   KS_Temp_2, w, A  ; XOR with G-func byte 2
    movwf   POSTINC1, A      ; Result -> 0xFE (Target)

    movf    POSTINC0, w, A   ; Get W[0] byte 3 (0x16)
    xorwf   KS_Temp_3, w, A  ; XOR with G-func byte 3
    movwf   POSTINC1, A      ; Result -> 0x17

    ; --- STEP C: GENERATE W[i+1], W[i+2], W[i+3] ---
    movlw   12              ; 3 words * 4 bytes = 12 bytes
    movwf   KS_count_reg, A          

XOR_Chain:
    ; 1. Get the byte we JUST wrote (which is W[i-1])
    ; Since FSR1 is pointing at the NEXT empty slot, -4 is the previous word
    movlw   252             ; Offset -4
    movf    PLUSW1, w, A    ; WREG = Round_Keys[i-4] relative to FSR1
    
    ; 2. XOR it with the word from 4 positions ago (W[i-4])
    ; FSR0 is already pointing at the start of W[i-4] because Step B finished there
    xorwf   POSTINC0, w, A  
    
    ; 3. Store the result into the current slot and move FSR1 forward
    movwf   POSTINC1, A     
    
    decfsz  KS_count_reg, f, A
    bra     XOR_Chain

    ; --- LOOP CONTROL ---
    incf    KS_round_idx, f, A       ; Increment round counter
    movlw   10                    ; AES-128 does 10 expansion rounds
    cpfseq  KS_round_idx, A          ; Compare and skip if round_idx == 10
    bra     Main_Expansion_Loop   ; Loop back if not finished
    return

; --- SUBROUTINES ---

Get_Rcon:
    ; Input: WREG = round_idx (0-9)
    ; Output: WREG = Rcon value
    ; Save round_idx and calculate table address properly
    movwf   TBLPTRL, A      ; Temporarily store round_idx
    
    ; Set up base address of Rcon_Table
    movlw   LOW(Rcon_Table)
    addwf   TBLPTRL, f, A   ; TBLPTRL = LOW(Rcon_Table) + round_idx
    
    movlw   HIGH(Rcon_Table)
    movwf   TBLPTRH, A
    btfsc   STATUS, 0, A    ; Check carry flag from previous add
    incf    TBLPTRH, f, A   ; Add carry to high byte if needed
    
    movlw   (Rcon_Table >> 16) & 0xFF
    movwf   TBLPTRU, A
    
    tblrd*
    movf    TABLAT, W, A    ; Result returned in WREG
    return

Key_Schedule:    
    call    Schedule_Setup
    return

