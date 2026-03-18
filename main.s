#include <xc.inc>

global  pkg_buffer, current_key, encryption_timer, decryption_timer
extrn   UART_Setup, UART_Receive_Package, UART_Send_Package, UART_Send_Timers, UART_Send_Round_Keys
extrn	SBOX_Encrypt_Byte, SBOX_Encrypt_Buffer, SBOX_Decrypt_Byte, SBOX_Decrypt_Buffer
extrn	Key_Setup, Mix_Key
extrn   P_Box_Enc, P_Box_Dec, Unshift_Rows, Shift_Rows
extrn   EEPROM_Read_Buffer

psect  udata_acs
pkg_buffer:  ds 16
CLEAR_CNT:   ds 1          ; Counter for clearing buffer
n_cycles:    ds 1          ; Counter for number of encryption cycles
current_key: ds 1	   ; Current key (0-10)
key_generated: ds 1	   ; has a key been generated
encryption_timer: ds 2     ; Elapsed TMR1 ticks for encryption
decryption_timer: ds 2     ; Elapsed TMR1 ticks for decryption

; Reset vector
psect   reset_vec, class=CODE, reloc=2
    goto    Setup

psect   code
Setup:
        call    UART_Setup

	movlw   0b11011000
	movwf   T0CON, A
	
	movlw	0x00
	movwf	key_generated, A
	
	clrf    T1CON, A        ; Clear register
	bsf     T1CON, 1, A     ; Set Bit 1 (RD16)
	clrf    T1GCON, A       ; Disable gate control

	bra	Loop

Encrypt:
        ; generate key for use if the start of the package is detected (with SOT byte currently 0x02)
        movlw   0x02
        cpfseq  pkg_buffer, A
        bra     No_Key_Gen

        ; if using additional SOT bytes, check here

        ; check if a key has already been generated for this package
        movlw   0x00
        cpfseq  key_generated, A
        BRA     No_Key_Gen

        ; now generate the key and set the flag if start byte detected and no key generated yet
        movlw   0x01
        movwf   key_generated, A ; set key generated flag to 1
        call    Key_Setup

No_Key_Gen:
        call   EEPROM_Read_Buffer  ; load current key in EEPROM

        movlw  9                  ; Number of encryption cycles
        movwf  n_cycles, A         ; Store in cycle counter variable
	
        ; mix first key
	movlw	0x00
	movwf	current_key, A
	
	call	Mix_Key
	
    Encrypt_Loop:
        call    SBOX_Encrypt_Buffer
        call    P_Box_Enc

        ; mix all other keys
	incf	current_key, F, A
	call	Mix_Key

        decfsz  n_cycles, F, A         ; Decrement cycle counter, skip if zero
        bra     Encrypt_Loop
	
	; final round 
	call	SBOX_Encrypt_Buffer
	call	Shift_Rows
	
	incf	current_key, F, A
	call	Mix_Key
	
	return


Decrypt: 
        call    EEPROM_Read_Buffer  ; load current key in EEPROM
        movlw   9                   ; Number of decryption cycles
        movwf   n_cycles, A          ; Store in cycle counter variable

        ; mix last key
	movlw	0x0A
	movwf	current_key, A
	call	Mix_Key
	
	call	Unshift_Rows 
	call	SBOX_Decrypt_Buffer

    Decrypt_Loop:
        ; mix all other keys
	decf	current_key, F, A
	call	Mix_Key
	
        call    P_Box_Dec
        call    SBOX_Decrypt_Buffer

        decfsz  n_cycles, F, A         ; Decrement cycle counter, skip if zero
        bra     Decrypt_Loop
	
	; final round
	decf    current_key, F, A      ; Key pointer is now 0 (Master Key)
        call    Mix_Key

	return

Loop:
        lfsr    2, pkg_buffer       ; FSR2 points to start of buffer
        movlw   16                  ; Number of bytes to clear
        movwf   CLEAR_CNT, A        ; Store in counter variable
        movlw   0                   ; Load 0 into WREG for clearing

Clear_Loop:
        movwf   POSTINC2, A            ; Write W=0 (clear) and increment pointer
        decfsz  CLEAR_CNT, F, A             ; Decrement counter, skip if zero
        bra     Clear_Loop

        call    UART_Receive_Package
         ; if end of package contains 0x04 (EOT marker), reset key generated flag to 0 for next package
        movlw   0x04
        cpfseq  pkg_buffer+15, A
        bra     No_Key_Reset
        movlw   0x00
        movwf   key_generated, A

        ; if using additional EOT bytes, check here

No_Key_Reset:

	    ; --- Encryption timing ---
	bcf     T1CON, 0, A           ; Ensure TMR1ON = 0 (stop timer)
	clrf    TMR1H, A              ; Clear high byte 
	clrf    TMR1L, A              ; Clear low byte
	bsf     T1CON, 0, A           ; Start Timer1 (set TMR1ON = 1)
	call    Encrypt
	bcf     T1CON, 0, A           ; Stop Timer1 (clear TMR1ON = 0)
	movf    TMR1L, W, A           ; Read low (latches high when RD16=1)
	movwf   encryption_timer, A
	movf    TMR1H, W, A
	movwf   encryption_timer+1, A

	; --- Decryption timing ---
	bcf     T1CON, 0, A
	clrf    TMR1H, A
	clrf    TMR1L, A
	bsf     T1CON, 0, A
	call    Decrypt
	bcf     T1CON, 0, A
	movf    TMR1L, W, A
	movwf   decryption_timer, A
	movf    TMR1H, W, A
	movwf   decryption_timer+1, A

        call    UART_Send_Package
        call    UART_Send_Timers
        call    UART_Send_Round_Keys

        bra     Loop
