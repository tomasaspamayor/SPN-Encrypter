#include <xc.inc>

extrn	UART_Setup, UART_Transmit_Message  ; external uart subroutines
extrn	ADC_Setup, ADC_Read		   ; external ADC subroutines
extrn	Keypad_Setup, Keypad_Read  ; external subroutines
extrn	LCD_Setup, LCD_Write_Message, LCD_Clear, LCD_Newline, LCD_Send_Byte_D, LCD_delay_ms, LCD_Write_Hex
	
psect	udata_acs   ; reserve data space in access ram
counter:    ds 1    ; reserve one byte for a counter variable
delay_count:ds 1    ; reserve one byte for counter in the delay routine

state: ds 1
special: ds 1
    
psect	udata_bank4 ; reserve data anywhere in RAM (here at 0x400)
myArray:    ds 0x80 ; reserve 128 bytes for message data

psect	data    
	; ******* myTable, data in programme memory, and its length *****
myTable:
	db	'T','e','m','m','u','z',' ','T','u','m','a','y',0x0a
					; message, plus carriage return
	myTable_l   EQU	12	; length of data
	align	2
    
psect	code, abs	
rst: 	org 0x0
 	goto	setup

	; ******* Programme FLASH read Setup Code ***********************
setup:	bcf	CFGS	; point to Flash program memory  
	bsf	EEPGD 	; access Flash program memory
	call	UART_Setup	; setup UART
	call	LCD_Setup	; setup UART
	call	ADC_Setup	; setup ADC
	goto	start
	
	; ******* Main programme ****************************************
start: 	lfsr	0, myArray	; Load FSR0 with address in RAM	
	movlw	low highword(myTable)	; address of data in PM
	movwf	TBLPTRU, A		; load upper bits to TBLPTRU
	movlw	high(myTable)	; address of data in PM
	movwf	TBLPTRH, A		; load high byte to TBLPTRH
	movlw	low(myTable)	; address of data in PM
	movwf	TBLPTRL, A		; load low byte to TBLPTRL
	movlw	myTable_l	; bytes to read
	movwf 	counter, A		; our counter register
loop: 	tblrd*+			; one byte from PM to TABLAT, increment TBLPRT
	movff	TABLAT, POSTINC0; move data from TABLAT to (FSR0), inc FSR0	
	decfsz	counter, A		; count down to zero
	bra	loop		; keep going until finished
		
	movlw	myTable_l	; output message to UART
	lfsr	2, myArray
	call	UART_Transmit_Message

	movlw	myTable_l-1	; output message to LCD
				; don't send the final carriage return to LCD
	lfsr	2, myArray
	call	LCD_Write_Message
	
measure_loop:
	call	ADC_Read
	movf	ADRESH, W, A
	call	LCD_Write_Hex
	movf	ADRESL, W, A
	call	LCD_Write_Hex
	goto	measure_loop		; goto current line in code
	
	; a delay subroutine if you need one, times around loop in delay_count
delay:	decfsz	delay_count, A	; decrement until zero
	bra	delay
	return
; ========================================================================================================================================== old keypad code	
;	call	Keypad_Setup	; setup keypad
;	call	LCD_Setup	; setup UART
;	call	LCD_Clear
;	movlw	0x77
;	movwf	state, A
;	movlw	0x43
;	movwf	special, A 
;	goto	loop
;	
;	; ******* Main programme ****************************************
;loop: 	
;	call	Keypad_Read	    ; store key press in W
;	cpfseq	special, A
;	goto send
;	
;	call LCD_Clear
;	bra loop
;	
;send:
;	cpfseq  state, A
;	call	LCD_Send_Byte_D	    ; send byte stored in W
;	
;	movlw	0xFE		; wait a long time
;	call	LCD_delay_ms
;	
;	bra	loop		; goto current line in code
;	; a delay subroutine if you need one, times around loop in delay_count
;	
;	
;	end	rst