#include <xc.inc>

;; This module implements the main control flow for the AES encryption, decryption or mixed mode processes.

global  pkg_buffer, current_key, encryption_timer, decryption_timer
extrn   UART_Setup, UART_Receive_Package, UART_Send_Package, UART_Send_Timers, UART_Send_Round_Keys 	; UART functions
extrn	SBOX_Encrypt_Byte, SBOX_Encrypt_Buffer, SBOX_Decrypt_Byte, SBOX_Decrypt_Buffer					; S-Box functions
extrn	Mix_Key																							; Key Mixing function
extrn   P_Box_Enc, P_Box_Dec, Unshift_Rows, Shift_Rows													; P-Box and Shift Rows functions
extrn	session_mode																					; Session mode variable					

psect  udata_acs
pkg_buffer:  ds 16			; Incoming/outcoming information buffer (16 bytes)
CLEAR_CNT:   ds 1          	; Counter for clearing buffer
n_cycles:    ds 1          	; Counter for number of encryption cycles
current_key: ds 1	   		; Current key (0-10)
encryption_timer: ds 2     	; TMR1 ticks for encryption
decryption_timer: ds 2     	; TMR1 ticks for decryption


psect   reset_vec, class=CODE, reloc=2 ; Reset vector at address 0x0000
    goto    Setup						

psect   code
Setup:
        call    UART_Setup	; Initialize UART for communication

	movlw   0b11011000		; Timer configuration
	movwf   T0CON, A		; Timer0 off

	clrf    T1CON, A        ; Clear register
	bsf     T1CON, 1, A     ; Set Bit 1 (RD16)
	clrf    T1GCON, A       ; Disable gate control

	bra	Loop

Encrypt:
        movlw  9					; Number of encryption cycles
        movwf  n_cycles, A  		; Store in cycle counter variable

	movlw	0x00					; Start with Master Key (0)
	movwf	current_key, A 
	
	call	Mix_Key					; Mix the first key (Master Key) before starting rounds
	
    Encrypt_Loop:
        call    SBOX_Encrypt_Buffer ; Apply S-Box to the buffer
        call    P_Box_Enc			; Apply P-Box permutation

	incf	current_key, F, A		; Increment key pointer for next round
	call	Mix_Key					; Mix the next key

        decfsz  n_cycles, F, A      ; Decrement cycle counter, skip if zero
        bra     Encrypt_Loop
	
	call	SBOX_Encrypt_Buffer		; Final round S-Box (no P-Box)
	call	Shift_Rows				; Final round Shift Rows (no Mix Key)
	
	incf	current_key, F, A		; Increment key pointer for final round
	call	Mix_Key					; Final round Mix Key
	
	return

Decrypt: 
        movlw   9                   ; Number of decryption cycles
        movwf   n_cycles, A         ; Store in cycle counter variable

	movlw	0x0A					; Start with last round key (0x0A)
	movwf	current_key, A			; Store in current key variable
	call	Mix_Key					; Initial Mix Key for decryption (with last round key)
	
	call	Unshift_Rows 			; Initial Unshift Rows for decryption
	call	SBOX_Decrypt_Buffer		; Initial S-Box for decryption

    Decrypt_Loop:					
	decf	current_key, F, A		; Decrement key pointer for next round
	call	Mix_Key					; Mix Key for decryption round
	
        call    P_Box_Dec			; Apply inverse P-Box permutation
        call    SBOX_Decrypt_Buffer ; Apply inverse S-Box to the buffer

        decfsz  n_cycles, F, A      ; Decrement cycle counter, skip if zero
        bra     Decrypt_Loop		
	
	decf    current_key, F, A      	; Decrement to get Master Key index (0)
        call    Mix_Key				; Final Mix Key for decryption (with Master Key)

	return

Loop:
        lfsr    2, pkg_buffer       ; Point FSR2 to the start of pkg_buffer
        movlw   16                  ; Number of bytes to clear
        movwf   CLEAR_CNT, A        ; Store in counter variable
        movlw   0                   ; Load 0 into WREG for clearing

Clear_Loop:
        movwf   POSTINC2, A         ; Write W=0 (clear) and increment pointer
        decfsz  CLEAR_CNT, F, A     ; Decrement counter, skip if zero
        bra     Clear_Loop
	
	; Session Mode Checks
	movf	session_mode, W, A
	xorlw	0x01					; Check for encryption mode (bit 0 set)
	bz	Session_Encrypt
	
	movf	session_mode, W, A
	xorlw	0x00
	bz	Session_Decrypt				; Check for decryption mode (bit 0 not set)
	
	movf	session_mode, W, A
	xorlw	0x02
	bz	Session_Mixed				; Check for mixed mode (bit 1 set)
	

Session_Encrypt:				
	call	UART_Receive_Package		; Receive data into pkg_buffer
	call	Encrypt 					; Encrypt the data in pkg_buffer
	call    UART_Send_Package			; Send the encrypted data back
        call    UART_Send_Timers		; Send encryption timing information
        call    UART_Send_Round_Keys	; Send round keys used in encryption

        bra     Loop

Session_Decrypt:
	call	UART_Receive_Package		; Receive data into pkg_buffer
	call	Decrypt 					; Decrypt the data in pkg_buffer
	call    UART_Send_Package			; Send the decrypted data back
        call    UART_Send_Timers		; Send decryption timing information
        call    UART_Send_Round_Keys	; Send round keys used in decryption

        bra     Loop

Session_Mixed:
        call    UART_Receive_Package		; Receive data into pkg_buffer
	; --- Encryption timing ---
	bcf     T1CON, 0, A           			; Ensure TMR1ON = 0 (stop timer)
	clrf    TMR1H, A              			; Clear high byte 
	clrf    TMR1L, A              			; Clear low byte
	bsf     T1CON, 0, A           			; Start Timer1 (set TMR1ON = 1)
	call    Encrypt
	bcf     T1CON, 0, A           			; Stop Timer1 (clear TMR1ON = 0)
	movf    TMR1L, W, A           			; Read low (latches high when RD16=1)
	movwf   encryption_timer, A
	movf    TMR1H, W, A
	movwf   encryption_timer+1, A

	; --- Decryption timing ---
	bcf     T1CON, 0, A						; Ensure TMR1ON = 0 (stop timer)
	clrf    TMR1H, A						; Clear high byte
	clrf    TMR1L, A						; Clear low byte
	bsf     T1CON, 0, A						; Start Timer1 (set TMR1ON = 1)
	call    Decrypt
	bcf     T1CON, 0, A						; Stop Timer1 (clear TMR1ON = 0)
	movf    TMR1L, W, A						; Read low (latches high when RD16=1)
	movwf   decryption_timer, A
	movf    TMR1H, W, A
	movwf   decryption_timer+1, A

        call    UART_Send_Package			; Send the processed data back
        call    UART_Send_Timers			; Send both encryption and decryption timing information
        call    UART_Send_Round_Keys		; Send round keys used in both encryption and decryption

        bra     Loop
