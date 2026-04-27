#include <xc.inc>

global  pkg_buffer, current_key, encryption_timer, decryption_timer
extrn   UART_Setup, UART_Receive_Package, UART_Send_Package, UART_Send_Timers, UART_Send_Round_Keys
extrn	SBOX_Encrypt_Byte, SBOX_Encrypt_Buffer, SBOX_Decrypt_Byte, SBOX_Decrypt_Buffer
extrn	Mix_Key
extrn   P_Box_Enc, P_Box_Dec, Unshift_Rows, Shift_Rows
extrn	session_mode
    
psect  udata_acs
pkg_buffer:  ds 16
CLEAR_CNT:   ds 1          		; Counter for clearing buffer
n_cycles:    ds 1          		; Counter for number of encryption cycles
current_key: ds 1	   			; Current key (0-10)
encryption_timer: ds 2     		; Elapsed TMR1 ticks for encryption
decryption_timer: ds 2     		; Elapsed TMR1 ticks for decryption

; Reset vector
psect   reset_vec, class=CODE, reloc=2
    goto    Setup

psect   code
Setup:
        call    UART_Setup

		movlw   0b11011000 			; Configure T0CON: 16-bit, internal clock, prescaler 1:256
		movwf   T0CON, A
		
		clrf    T1CON, A        	; Clear register
		bsf     T1CON, 1, A     	; Set Bit 1 (RD16)
		clrf    T1GCON, A       	; Disable gate control

		bra	Loop

Encrypt:
        movlw  9                  	; Number of encryption cycles
        movwf  n_cycles, A         	; Store in cycle counter variable
	
        ; mix first key
		movlw	0x00
		movwf	current_key, A		; current_key = 0 (Master Key)
		
		call	Mix_Key
	
    Encrypt_Loop:
        call    SBOX_Encrypt_Buffer	; Sbox the buffer
        call    P_Box_Enc			; Pbox the buffer

        ; mix all other keys
		incf	current_key, F, A
		call	Mix_Key

        decfsz  n_cycles, F, A		; Decrement cycle counter, skip if zero
        bra     Encrypt_Loop
	
		; final round 
		call	SBOX_Encrypt_Buffer	; Sbox the buffer
		call	Shift_Rows			; Shift rows (no P-box in final round)
		
		incf	current_key, F, A 
		call	Mix_Key
		
		return


Decrypt: 
        movlw   9                   	; Number of decryption cycles
        movwf   n_cycles, A          	; Store in cycle counter variable

        ; mix last key
		movlw	0x0A					; current_key = 10 (Last Round Key) - decrement through keys
		movwf	current_key, A
		call	Mix_Key
		
		call	Unshift_Rows 			; Unshift rows (no P-box in first round for inverse)	
		call	SBOX_Decrypt_Buffer		; Inverse Sbox the buffer

    Decrypt_Loop:
		; mix all other keys
		decf	current_key, F, A
		call	Mix_Key
		
        call    P_Box_Dec				; Inverse P-box the buffer
        call    SBOX_Decrypt_Buffer		; Inverse Sbox the buffer

        decfsz  n_cycles, F, A         	; Decrement cycle counter, skip if zero
        bra     Decrypt_Loop
	
		; final round
		decf    current_key, F, A      		; Key pointer is now 0 (Master Key)
        call    Mix_Key

	return

Loop:
        lfsr    2, pkg_buffer       	; FSR2 points to start of buffer
        movlw   16                  	; Number of bytes to clear
        movwf   CLEAR_CNT, A       		; Store in counter variable
        movlw   0                   	; Load 0 into WREG for clearing

Clear_Loop:
        movwf   POSTINC2, A            	; Write W=0 (clear) and increment pointer
        decfsz  CLEAR_CNT, F, A         ; Decrement counter, skip if zero
        bra     Clear_Loop
	
		movf	session_mode, W, A		; Check session mode
		xorlw	0x01
		bz	Session_Encrypt				; If mode 0x01, encryption session
		
		movf	session_mode, W, A
		xorlw	0x00					; If mode 0x00, decryption session
		bz	Session_Decrypt
		
		movf	session_mode, W, A
		xorlw	0x02
		bz	Session_Mixed				; If mode 0x02, mixed session (timing both encryption and decryption)
	
	
	
Session_Encrypt:
		; encrypt, send package, timers and round keys
		call	UART_Receive_Package	
		call	Encrypt 
		call    UART_Send_Package
        call    UART_Send_Timers
        call    UART_Send_Round_Keys

        bra     Loop
	
    
Session_Decrypt:
		; decrypt, send package, timers and round keys
		call	UART_Receive_Package
		call	Decrypt 
		call    UART_Send_Package
        call    UART_Send_Timers
        call    UART_Send_Round_Keys

        bra     Loop
	
	
Session_Mixed:
		; encrypt, decrypt (both in same mode), send package, timers and round keys
        call    UART_Receive_Package

	    ; --- Encryption timing ---
		bcf     T1CON, 0, A           	; Ensure TMR1ON = 0 (stop timer)
		clrf    TMR1H, A              	; Clear high byte 
		clrf    TMR1L, A              	; Clear low byte
		bsf     T1CON, 0, A           	; Start Timer1 (set TMR1ON = 1)
		call    Encrypt
		bcf     T1CON, 0, A           	; Stop Timer1 (clear TMR1ON = 0)
		movf    TMR1L, W, A           	; Read low (latches high when RD16=1)
		movwf   encryption_timer, A		; move to first byte
		movf    TMR1H, W, A				; Read high byte
		movwf   encryption_timer+1, A	; move to second byte

		; --- Decryption timing ---
		bcf     T1CON, 0, A				; Ensure TMR1ON = 0 (stop timer)
		clrf    TMR1H, A				; Clear high byte
		clrf    TMR1L, A				; Clear low byte
		bsf     T1CON, 0, A				; Start Timer1 (set TMR1ON = 1)
		call    Decrypt
		bcf     T1CON, 0, A				; Stop Timer1 (clear TMR1ON = 0)
		movf    TMR1L, W, A				; Read low (latches high when RD16=1)
		movwf   decryption_timer, A		; move to first byte
		movf    TMR1H, W, A				; Read high byte
		movwf   decryption_timer+1, A	; move to second byte

        call    UART_Send_Package
        call    UART_Send_Timers
        call    UART_Send_Round_Keys

        bra     Loop
