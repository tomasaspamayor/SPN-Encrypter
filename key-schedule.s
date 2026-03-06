#include <xc.inc>

; This module implements the key schedule for the SPN cipher. It generates round keys from the initial key using a specific algorithm.

global  Key_Schedule, Test_Run_Expansion ; We need to make the key schedule function available to other modules
extrn   SBOX_Encrypt_Byte, AL ; External S-Box and its AL register

psect    ks_data,class=DATA
    count_reg: res 1
    round_idx: res 1
    Temp_0:    res 1
    Temp_1:    res 1
    Temp_2:    res 1
    Temp_3:    res 1

    Key_Buffer: res 16    ; Original Master Key
    Round_Keys: res 176   ; All 11 Round Keys (16 * 11)

psect    ks_code,class=CODE
Rcon_Table:
    db 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36 ; Rcon values for AES-128

Key_Schedule:
    ; 1. Copy Master Key (16 bytes) from Key_Buffer to Round_Keys[0..15]
    lfsr    0, Key_Buffer ; FSR0 points to start of master key
    lfsr    1, Round_Keys ; FSR1 points to start of round keys
    movlw   16 ; Number of bytes to copy
    movwf   count_reg ; Store in counter variable

Copy_Master:
    movff   POSTINC0, POSTINC1 ; Copy byte and increment both pointers
    decfsz  count_reg, f ; Decrement counter, skip if zero
    bra     Copy_Master ; Loop until all 16 bytes are copied

    ; 2. Initialize Pointers for the Loop
    ; FSR0 will always point to W[i-4] (4 words ago)
    ; FSR1 will always point to W[i]   (current word being written)
    lfsr    0, Round_Keys       ; Point to Word 0
    lfsr    1, Round_Keys + 16  ; Point to Word 4 (Start of Round 1)
    
    clrf    round_idx           ; round_idx = 0 (used for Rcon lookup)

Main_Expansion_Loop:
    ; --- STEP A: THE G-FUNCTION (Rot + Sub + Rcon) ---
    ; We need W[i-1]. Since FSR1 points to W[i], W[i-1] is at FSR1-4.

    ; --- STEP A.1: RotWord (Dynamic Version) ---
    ; Byte 0 (Temp) = [FSR1-3], Byte 1 = [FSR1-2], Byte 2 = [FSR1-1], Byte 3 = [FSR1-4]
    movlw   -3
    movff   PLUSW1, Temp_0
    movlw   -2
    movff   PLUSW1, Temp_1
    movlw   -1
    movff   PLUSW1, Temp_2
    movlw   -4
    movff   PLUSW1, Temp_3

    ; --- STEP A.2: SubWord (Using your SBox_Encrypt_Byte) ---
    ; Process Temp_0
    movff   Temp_0, AL         ; Move Temp_0 to the S-Box input register
    call    SBOX_Encrypt_Byte  ; Substituted value is now in AL
    movff   AL, Temp_0         ; Store result back to Temp_0
    ; Process Temp_1
    movff   Temp_1, AL
    call    SBOX_Encrypt_Byte
    movff   AL, Temp_1
    ; Process Temp_2
    movff   Temp_2, AL
    call    SBOX_Encrypt_Byte
    movff   AL, Temp_2
    ; Process Temp_3
    movff   Temp_3, AL
    call    SBOX_Encrypt_Byte
    movff   AL, Temp_3

    ; 3. Rcon: XOR first byte of Temp with Rcon_Table[round_idx]
    movf    round_idx, w       ; Get round index for Rcon lookup
    call    Get_Rcon           ; Helper to pull from Rcon_Table
    xorwf   Temp_0, f          ; XOR with first byte of Temp

    ; --- STEP B: GENERATE W[i] (First word of new key) ---
    movf    POSTINC0, w        ; Get W[i-4] byte 0, increment FSR0
    xorwf   Temp_0, w          
    movwf   POSTINC1           ; Store to W[i] byte 0, increment FSR1

    movf    POSTINC0, w        ; Get W[i-4] byte 1
    xorwf   Temp_1, w          
    movwf   POSTINC1           

    movf    POSTINC0, w        ; Get W[i-4] byte 2
    xorwf   Temp_2, w          
    movwf   POSTINC1           

    movf    POSTINC0, w        ; Get W[i-4] byte 3
    xorwf   Temp_3, w          
    movwf   POSTINC1

    ; --- STEP C: GENERATE W[i+1], W[i+2], W[i+3] ---
    ; This is the XOR chain: New Word = (4-words-ago) XOR (immediately-previous-word)
    movlw   12                 ; 3 words * 4 bytes
    movwf   count_reg          ; We need to generate 3 more words (12 bytes)

XOR_Chain:
    ; W[i-4] is already at POSTINC0
    ; W[i-1] is the byte we JUST wrote to POSTINC1
    
    movlw   -1
    movf    PLUSW1, w          ; Get W[i-1]
    xorwf   POSTINC0, w        ; XOR with W[i-4], increment FSR0
    movwf   POSTINC1           ; Store result to W[i], increment FSR1
    
    decfsz  count_reg, f
    bra     XOR_Chain

    ; --- LOOP CONTROL ---
    incf    round_idx, f       ; Move to next round
    movlw   10                 ; AES-128 uses 10 expansion rounds
    cpfseq  round_idx          ; Have we finished round 10?
    bra     Main_Expansion_Loop ; If not, loop back
    return                     ; If yes, we are done!

; --- SUBROUTINES ---

Get_Rcon:
    movlw   upper Rcon_Table
    movwf   TBLPTRU
    movlw   high Rcon_Table
    movwf   TBLPTRH
    movlw   low Rcon_Table
    addwf   round_idx, w       
    movwf   TBLPTRL
    movlw   0
    addwfc  TBLPTRH, f         ; This is fine now because TBLPTRH was just reloaded
    tblrd* ; Read Flash into TABLAT
    movf    TABLAT, w   ; Move TABLAT into WREG    
    return

Test_Run_Expansion:
    ; --- Step 1: Initialize Key_Buffer with All Zeros ---
    lfsr    0, Key_Buffer       ; Point to your master key buffer
    movlw   16                  ; 16 bytes for AES-128
    movwf   count_reg, A
Clear_Key_Loop:
    clrf    POSTINC0, A         ; Clear byte and move to next
    decfsz  count_reg, F, A
    bra     Clear_Key_Loop

    ; --- Step 2: Run the Schedule ---
    call    Key_Schedule

    ; --- Step 3: Stop Here ---
    nop                         ; <--- SET BREAKPOINT HERE
    return
