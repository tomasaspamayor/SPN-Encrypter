#include <xc.inc>

; This module implements the key schedule for the SPN cipher. It generates round keys from the initial key using a specific algorithm.

global  Key_Schedule, Test_Run_Expansion, Key_Buffer, Round_Keys ; We need to make the key schedule function available to other modules
extrn   SBOX_Encrypt_Byte, pkg_buffer ; External S-Box and its AL register

psect   udata

AL:      ds 1         ; Define AL as 1 byte in access bank
count_reg:  ds 1
round_idx:  ds 1
Temp_0:     ds 1
Temp_1:     ds 1
Temp_2:     ds 1
Temp_3:     ds 1
xor_offset: ds 1

Key_Buffer: ds 16     ; Original Master Key
Round_Keys: ds 176    ; All 11 Round Keys (16 * 11)

psect    ks_code,class=CODE
Rcon_Table:
    db 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36 ; Rcon values for AES-128

Key_Schedule:
    ; 1. Copy Master Key (16 bytes) from Key_Buffer to Round_Keys[0..15]
    lfsr    0, Key_Buffer ; FSR0 points to start of master key
    lfsr    1, Round_Keys ; FSR1 points to start of round keys
    movlw   16 ; Number of bytes to copy
    movwf   count_reg, A ; Store in counter variable

Copy_Master:
    movff   POSTINC0, POSTINC1 ; Copy byte and increment both pointers
    decfsz  count_reg, f, A ; Decrement counter, skip if zero
    bra     Copy_Master ; Loop until all 16 bytes are copied

    ; 2. Initialize Pointers for the Loop
    ; FSR0 will always point to W[i-4] (4 words ago)
    ; FSR1 will always point to W[i]   (current word being written)
    lfsr    0, Round_Keys       ; Point to Word 0
    lfsr    1, Round_Keys + 16  ; Point to Word 4 (Start of Round 1)
    
    clrf    round_idx, A           ; round_idx = 0 (used for Rcon lookup)

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

; --- STEP A.2: SubWord (The AES Fix) ---
    ; We must move the byte into the AL register that the S-Box uses.
    
    movf    Temp_0, w, A
    movwf   AL, A              ; Move Temp_0 to the S-Box's input
    call    SBOX_Encrypt_Byte  ; Substitutes AL
    movff   AL, Temp_0         ; Store result (should be 0x63) back

    movf    Temp_1, w, A
    movwf   AL, A
    call    SBOX_Encrypt_Byte
    movff   AL, Temp_1

    movf    Temp_2, w, A
    movwf   AL, A
    call    SBOX_Encrypt_Byte
    movff   AL, Temp_2

    movf    Temp_3, w, A
    movwf   AL, A
    call    SBOX_Encrypt_Byte
    movff   AL, Temp_3
    
; --- STEP A.3: Rcon XOR  ---
    movf    round_idx, w, A     ; Load current round index (0-9)
    call    Get_Rcon            ; Fetch Rcon[round_idx] into AL
    movf    AL, w, A            ; Move Rcon value to W
    xorwf   Temp_0, f, A        ; XOR Rcon ONLY with the first byte (Temp_0)

    ; --- STEP B: GENERATE W[i] (First word of new key) ---
    movf    POSTINC0, w, A        ; Get W[i-4] byte 0, increment FSR0
    xorwf   Temp_0, w, A          
    movwf   POSTINC1, A           ; Store to W[i] byte 0, increment FSR1

    movf    POSTINC0, w, A        ; Get W[i-4] byte 1
    xorwf   Temp_1, w, A          
    movwf   POSTINC1, A           

    movf    POSTINC0, w, A        ; Get W[i-4] byte 2
    xorwf   Temp_2, w, A          
    movwf   POSTINC1, A           

    movf    POSTINC0, w, A        ; Get W[i-4] byte 3
    xorwf   Temp_3, w, A          
    movwf   POSTINC1, A

; --- STEP C: GENERATE W[i+1], W[i+2], W[i+3] ---
    movlw   12              ; 3 words * 4 bytes = 12 bytes
    movwf   count_reg, A          

XOR_Chain:
    movlw   -4              ; Always look back exactly 4 bytes from current FSR1
    movf    PLUSW1, w, A    ; Get byte from W[i-1]
    xorwf   POSTINC0, w, A  ; XOR with W[i-4] (POSTINC0 handles the i-4 pointer)
    movwf   POSTINC1, A     ; Store result to W[i], move FSR1 forward
    decfsz  count_reg, f, A
    bra     XOR_Chain

; --- LOOP CONTROL ---
    incf    round_idx, f, A       ; Increment round counter
    movlw   10                    ; AES-128 does 10 expansion rounds
    cpfseq  round_idx, A          ; Compare and skip if round_idx == 10
    bra     Main_Expansion_Loop   ; Loop back if not finished
    return

; --- SUBROUTINES ---

Get_Rcon:
    ; Input: WREG = index into Rcon_Table
    ; Load base address of Rcon_Table into TBLPTR
    movlw   LOW(Rcon_Table)
    movwf   TBLPTRL, A
    movlw   HIGH(Rcon_Table)
    movwf   TBLPTRH, A
    movlw   (Rcon_Table >> 16) & 0xFF
    movwf   TBLPTRU, A

    ; Add index (in WREG) to TBLPTR, handle carry across bytes
    addwf   TBLPTRL, F, A
    addwfc  TBLPTRH, F, A
    addwfc  TBLPTRU, F, A
    
    ; Read the byte from program memory into TABLAT
    tblrd*
    movf    TABLAT, W, A
    movwf   AL, A
    return 

Test_Run_Expansion:
    ; Copy pkg_buffer (received master key) to Key_Buffer
    lfsr    0, pkg_buffer
    lfsr    1, Key_Buffer
    movlw   16
    movwf   count_reg, A
Copy_Master_Key:
    movff   POSTINC0, POSTINC1
    decfsz  count_reg, f, A
    bra     Copy_Master_Key
    
    ; Now run the schedule with correct master key
    call    Key_Schedule
    
    ; Copy Round_Keys[0:15] (first round key = master key) back to pkg_buffer
    lfsr    0, Round_Keys
    lfsr    1, pkg_buffer
    movlw   16
    movwf   count_reg, A
Copy_Round_Key_Back:
    movff   POSTINC0, POSTINC1
    decfsz  count_reg, f, A
    bra     Copy_Round_Key_Back
    
    nop  ; breakpoint here
    return
