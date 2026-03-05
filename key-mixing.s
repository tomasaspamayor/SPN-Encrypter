; perform key mixing stage
#include <xc.inc>

global	Key_Setup, Mix_Key
extrn	pkg_buffer  ; the storage location of the package buffer
    
psect	udata_acs   ; reserve data space in access ram
; varaibles
key:		ds  16	; 128 bit key stored
key_count:	ds  1	; counting variable for key generation
mix_count:	ds  1	; counting variable for XOR loop
    
psect	uart_code,class=CODE
    
Key_Setup: ; test key 
	lfsr    0, key	; point FSR0 to key 
	movlw   0x10	
	movwf   key_count, A    ; set count to 0 
    Key_Loop: 
	movf	key_count, W, A    
	movwf	POSTINC0, A	   ; store incremental test values
	decfsz	key_count, F, A    ; decrement count, and skip next if equal to zero
	goto	Key_Loop
	
	return
	
	
Mix_Key:
	lfsr	0, pkg_buffer
	lfsr	1, key 
	
	movlw	0x10		; for 16 bytes
	movwf	mix_count, A
	
    XOR_Loop:
	movf	POSTINC1, W, A	; store key[i], increment FSR1
	xorwf	POSTINC0, F, A	; xor data[i] with key[i], increment FSR0, store in data[i]
	
	decfsz	mix_count, F, A ; decrement counter, store back in F
	goto	XOR_Loop
	return
	
	
	
	
	
	
    