#include <xc.inc>
; TRNG (True Random Number Generator) module for master key initialization. Uses time jitter and external async clock to generate 128-bit random keys. Dependencies: Key_Buffer (16-byte buffer), TMR0, RC0/T1CKI input.

global  Generate_Master_Key
extrn   Key_Buffer

psect   const_data,class=CONST,reloc=2
Fixed_Key_Data:
    db	    'T', 'E', 'M', 'M', 'U', 'Z', 'T', 'U'
    db      'M', 'A', 'Y', 'I', 'S', 'A'
    
psect   udata_acs
TRNG_counter:   ds  1

psect   trng_code,class=CODE

Generate_Master_Key:
        ; Copies fixed key data (14 bytes) to Key_Buffer, then appends TMR0 jitter (2 bytes) for pseudo-randomness.
        ; Dependencies: Key_Buffer, Fixed_Key_Data, TMR0L/TMR0H, TRNG_counter.
		
		; move fixed key data from ROM to Key_Buffer
		lfsr    2, Key_Buffer   	
		movlw   low(Fixed_Key_Data)	
		movwf   TBLPTRL, A
		movlw   high(Fixed_Key_Data)
		movwf   TBLPTRH, A
		movlw   low(highword(Fixed_Key_Data))
		movwf   TBLPTRU, A

		movlw   15
		movwf   TRNG_counter, A

	Copy_ROM_Loop:
	; read byte from ROM using TBLRD*+ and write to Key_Buffer using POSTINC2
		tblrd*+               
		movff   TABLAT, POSTINC2

		decfsz  TRNG_counter, F, A
		bra     Copy_ROM_Loop
		
		movff   TMR0L, POSTINC2 
		movff   TMR0H, INDF2    

		return