; perform key mixing stage
#include <xc.inc>

global	Key_Setup, Key_Setup_From_TRNG, Mix_Key
extrn	pkg_buffer, current_key  ; the storage location of the package buffer
extrn  Key_Schedule, Key_Schedule_From_KeyBuffer, Key_Buffer, Round_Keys
    
psect	udata_acs   ; reserve data space in access ram
; varaibles
key_count:	ds  1	; counting variable for key generation
mix_count:	ds  1	; counting variable for XOR loop
key_idx:	ds  1	; helper variable to select the current key

    
psect	uart_code,class=CODE
    
Key_Setup: ; test key 
	lfsr    0, Key_Buffer	; point FSR0 to key 
	movlw   0x10	
	movwf   key_count, A    ; set count to 0 
    Key_Loop: 
	movf	key_count, W, A    
	movwf	POSTINC0, A	   ; store incremental test values
	decfsz	key_count, F, A    ; decrement count, and skip next if equal to zero
	bra	Key_Loop
	
	call	Key_Schedule
	return

Key_Setup_From_TRNG:
	; Alternative setup path: preserve TRNG data already in Key_Buffer.
	call	Key_Schedule_From_KeyBuffer
	return

Mix_Key:
	lfsr	0, pkg_buffer
	lfsr	1, Round_Keys
	
	movf	current_key, W, A
	
	; multiply key number by 16
	movwf   key_idx, A
	rlncf   key_idx, F, A
	rlncf   key_idx, F, A
	rlncf   key_idx, F, A
	rlncf   key_idx, F, A
	
	; offset the FSR pointers
	movf	key_idx, W, A
	addwf	FSR1L, F, A 
	movlw	0   ; to correct overflow (add carry to high pointer) --Error prone
	addwfc	FSR1H, F, A

	movlw	0x10		; for 16 bytes
	movwf	mix_count, A
	
    XOR_Loop:
	movf	POSTINC1, W, A	; store key[i], increment FSR1
	xorwf	POSTINC0, F, A	; xor data[i] with key[i], increment FSR0, store in data[i]
	
	decfsz	mix_count, F, A ; decrement counter, store back in F
	goto	XOR_Loop
	return
	
	
	
	
	
	
    