#include <xc.inc>

extrn  Key_Schedule, Key_Buffer, Round_Keys

psect	udata_acs 
eeprom_counter:	    ds 1
	
psect	eeprom_code,class=CODE
    
EEPROM_Setup:
	bcf	EECON1, EEPGD	; point to data memory 
	bcf	EECON1, CFGS	; access eeprom =0

EEPROM_Write:
	bsf	EECON1, WREN	; enable write
	movlw	0x10
	movwf	eeprom_counter, A
	lfsr	0, Key_Buffer	; move key buffer to fsr0
	
Write_Loop:
	movf	POSTINC0, W	; increment and pass ot EEDATA register
	movwf	EEDATA
    
	bcf	INTCON, GIE	; disable system interrupts
	movlw	0x55		; unlock sequence
	movwf	EECON2		
	movlw	0xAA
	movwf	EECON2
	bsf	EECON1, WR	; set WR bit to begin write 
	bsf	INTCON, WR	; reenable system interrupts
	
	btfsc	EECON1, WR	; wait for write to complete goto $-2
	goto	$-2		; loop back 1 if WR is still 1
	
	incf	EEADR, F
	decfsz	eeprom_counter, F, A
	goto	Write_Loop
	
	
	bcf	EECON1, WREN	; disable writes once write complete
	
	