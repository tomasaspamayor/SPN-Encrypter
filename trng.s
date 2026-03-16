#include <xc.inc>

; This module will use time jitter in the clocks of the microcontroller to generate random numbers. It will
; use the UART receiver to sample the noise in the system, which is a common technique for TRNGs on microcontrollers.
; The TRNG will generate 128 bits (16 bytes) of random data and store it in a buffer for later retrieval.

global  Generate_Master_Key
extrn   Key_Buffer


psect	udata_acs   ; reserve data space in access ram
TRNG_counter:	ds  1	    ; reserve 1 byte for variable TRNG_counter
TIMER:		ds  1
TR_count_reg:	ds  1
TR_Temp_0:		ds  1
    

psect	trng_code,class=CODE
; We use the WDT in interrupt mode to trigger the TRNG writing with the TMR0 setup 
; at its highest possible value, which will give us the most jitter.

Generate_Master_Key:
    lfsr    2, Key_Buffer
    movlw   16
    movwf   TR_count_reg, A
    
Byte_Loop:
    clrf    TR_Temp_0, A    ; Clear our "bit accumulator"
    movlw   8               ; 8 bits per byte
    movwf   TRNG_counter, A

TRNG_Generate_Loop:
    ; --- Entropy Generation ---
    ; We wait for TMR1 (if configured as a slow clock) 
    ; or simply use a software delay to create a 'sampling window'
    movlw   0xFF
    movwf   TIMER, A           ; Use PRODL as a simple delay counter

Delay_Window:
    decfsz  TIMER, F, A
    bra     Delay_Window

    ; --- Capture Jitter ---
    movf    TMR0L, W, A     ; Grab the high-speed timer LSBs
    andlw   0x01
    
    rlncf   TR_Temp_0, F, A ; Rotate Left (KS_Temp_0 << 1)
    iorwf   TR_Temp_0, F, A ; KS_Temp_0 = KS_Temp_0 | new_bit
    
    decfsz  TRNG_counter, F, A
    bra     TRNG_Generate_Loop
    
    movff   TR_Temp_0, POSTINC2
    
    decfsz  TR_count_reg, F, A
    bra     Byte_Loop
    
    return
