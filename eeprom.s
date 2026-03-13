#include <xc.inc>

global	EEPROM_Write_Buffer, EEPROM_Read_Buffer
extrn	Key_Buffer
extrn	pkg_buffer

psect	udata_acs 
eeprom_counter:	    ds 1
	
psect	code
    
EEPROM_Write_Buffer:
        bcf	EECON1, 7, A	; point to data memory (EEPGD bit 7)
        bcf	EECON1, 6, A	; access eeprom =0 (CFGS bit 6)
        bsf	EECON1, 2, A	; enable write (WREN bit 2)

        MOVLW   0x00
        movwf   EEADRH, A   ; upper address
        movlw   0x00
        movwf   EEADR, A

        movlw	0x10
        movwf	eeprom_counter, A
        lfsr	0, Key_Buffer	; move key buffer to fsr0
	
Write_Loop:
        movf	POSTINC0, W, A	; increment and pass ot EEDATA register
        movwf	EEDATA, A
        
        bcf	INTCON, 7, A	; disable system interrupts (GIE bit 7)
        movlw	0x55		; unlock sequence
        movwf	EECON2, A		
        movlw	0xAA
        movwf	EECON2, A
        bsf	EECON1, 1, A	; set WR bit to begin write  (WR bit 1)
        bsf	INTCON, 7, A	; reenable system interrupts (GIE bit 7)
        
        btfsc	EECON1, 1, A	; wait for write to complete goto $-2 (WR bit 1)
        goto	$-2		; loop back 1 if WR is still 1
        
        incf	EEADR, F ,A
        decfsz	eeprom_counter, F, A
        bra     Write_Loop
        
        bcf	EECON1, 2, A	; disable writes once write complete (WREN bit 2)
        return


EEPROM_Read_Buffer:
        movlw   0x00
        movwf   EEADRH, A   ; upper address
        movlw   0x00 
        movwf   EEADR, A    ; lower address

        movlw   0x10
        movwf   eeprom_counter, A

        lfsr    0, Key_Buffer

        bcf     EECON1, 7, A   ;(EEPGD bit 7)
        bcf     EECON1, 6, A   ; (CFGS bit 6)

Read_Loop:
        bsf     EECON1, 0, A	; start read (RD - bit 0)
        nop     
        movf    EEDATA, W, A   ; move data into W
        movwf   POSTINC0, A ; move W into fsr0

        incf    EEADR, F, A
        decfsz  eeprom_counter, F, A
        bra     Read_Loop

        bcf	EECON1, 0, A   ; Disable writes to EEPROM (RD - bit 0)
        return 

	