; Key mixing and setup module for AES encryption round key generation and data XOR operations.
; Dependencies: Generate_Master_Key, Key_Schedule, EEPROM_Write_Buffer, Key_Buffer, Round_Keys, pkg_buffer.
#include <xc.inc>

global	Key_Setup, Mix_Key, Key_Buffer, Round_Keys
extrn	pkg_buffer, current_key  ; the storage location of the package buffer
extrn	Key_Schedule
extrn	Generate_Master_Key
extrn	EEPROM_Write_Buffer
    
psect	udata_acs   ; reserve data space in access ram 
key_count:	ds  1	; counting variable for key generation
mix_count:	ds  1	; counting variable for XOR loop
key_idx:	ds  1	; helper variable to select the current key

psect	udata
Key_Buffer:	ds  16
Round_Keys:	ds  176

    
psect	uart_code,class=CODE
    
Key_Setup:
        ; Initializes master key via TRNG, stores in EEPROM, generates round keys via key schedule.
        ; Dependencies: Generate_Master_Key, EEPROM_Write_Buffer, Key_Schedule.
	
		; test code below
	;	lfsr    1, Key_Buffer	; point FSR0 to key 
	;	movlw   0x10	
	;	movwf   key_count, A    ; set count to 0 
	;    Key_Loop: 
	;	movlw	0x09   
	;	movwf	POSTINC1, A
	;	decfsz	key_count, F, A    ; decrement count, and skip next if equal to zero
	;	bra	Key_Loop
    
		call	Generate_Master_Key ; generate the master key using random key generator
		call 	EEPROM_Write_Buffer ; store the master key in EEPROM for later retrieval
		call	Key_Schedule

		return

Mix_Key:
        ; XORs pkg_buffer with current round key from Round_Keys array. Updates pkg_buffer in-place.
        ; Dependencies: pkg_buffer, Round_Keys, current_key, mix_count, key_idx registers.
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
	
	
	
	
	
	
    