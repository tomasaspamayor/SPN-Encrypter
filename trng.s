#include <xc.inc>

; This module will use time jitter in the clocks of the microcontroller to generate random numbers. 
; It uses an external asynchronous square wave (fed into RC0/T1CKI) to sample the main instruction clock.
; The TRNG will generate 128 bits (16 bytes) of random data and store it in a buffer for later retrieval.

global  Generate_Master_Key
extrn   Key_Buffer

psect   const_data,class=CONST,reloc=2
Fixed_Key_Data:
    db	    0b01011001, 'E', 'M', 'M', 'U', 'Z', 'T', 'U'
    db      'M', 'A', 'Y', 'I', 'S', 'A', '1', '2'
    
psect   udata_acs
TRNG_counter:   ds  1

psect   trng_code,class=CODE

Generate_Master_Key:	
	lfsr    2, Key_Buffer   
	movlw   low(Fixed_Key_Data)
	movwf   TBLPTRL, A
	movlw   high(Fixed_Key_Data)
	movwf   TBLPTRH, A
	movlw   low(highword(Fixed_Key_Data))
	movwf   TBLPTRU, A

	movlw   16
	movwf   TRNG_counter, A

Copy_ROM_Loop:
	tblrd*+               
	movff   TABLAT, POSTINC2

	decfsz  TRNG_counter, F, A
	bra     Copy_ROM_Loop
	
;	movff   TMR0L, POSTINC2 
;	movff   TMR0H, INDF2    

	return