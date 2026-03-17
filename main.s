#include <xc.inc>

global  pkg_buffer, current_key, encryption_timer, decryption_timer
extrn   UART_Setup, UART_Receive_Package, UART_Send_Package, UART_Send_Timers
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
        call    UART_Setup          ; Initialize UART
	; start timer for key gen
	movlw   0b11011000      ; T08BIT=1, T0CS=0, PSA=0 (1:2 prescaler)
	movwf   T0CON, A
	
	movlw	0x00
	movwf	key_generated, A
	

        ; Configure TMR1: internal clock (Fosc/4), 1:8 prescale, 16-bit r/w, OFF initially
        ; T1CON: RD16=1, T1CKPS=11 (1:8), T1OSCEN=0, T1SYNC=0, TMR1CS=00, TMR1ON=0
        ; T1CON: RD16=1, T1CKPS=00 (1:1), T1OSCEN=0, T1SYNC=0, TMR1CS=00, TMR1ON=0
        ; 1 tick = 1/Fcy = 62.5 ns at 16 MHz; max range ~4 ms (well within cipher time)
        movlw   0b10000000
        movwf   T1CON, A

	bra	Loop
        ; generate keys and start scheduling

Encrypt:
        ; generate key for use
        btfsc	key_generated, 0, A	; check if a key has already been generated, if not skip next line
	bra	Continue_Encryption
	
	call	Key_Setup
	bsf	key_generated, 0, A

Continue_Encryption:
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

        ; either encryopt or decrypt the package based on some condition 

        clrf    TMR1H, A
        clrf    TMR1L, A
        movlw   0b10000001          ; RD16=1, 1:1 prescale, TMR1ON=1 — start timer
        movwf   T1CON, A
        call    Encrypt
        movlw   0b10000000          ; TMR1ON=0 — stop timer
        movwf   T1CON, A
        movff   TMR1L, encryption_timer
        movff   TMR1H, encryption_timer+1

        clrf    TMR1H, A
        clrf    TMR1L, A
        movlw   0b10000001          ; start timer
        movwf   T1CON, A
        call    Decrypt
        movlw   0b10000000          ; stop timer
        movwf   T1CON, A
        movff   TMR1L, decryption_timer
        movff   TMR1H, decryption_timer+1

        call    UART_Send_Package
        call    UART_Send_Timers

        bra     Loop
