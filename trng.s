#include <xc.inc>

; This module will use time jitter in the clocks of the microcontroller to generate random numbers. It will
; use the UART receiver to sample the noise in the system, which is a common technique for TRNGs on microcontrollers.
; The TRNG will generate 128 bits (16 bytes) of random data and store it in a buffer for later retrieval.

global  TRNG_Generate
extrn   Key_Buffer


psect	udata_acs   ; reserve data space in access ram
TRNG_counter: ds    1	    ; reserve 1 byte for variable TRNG_counter

psect	trng_code,class=CODE
; We use the WDT in interrupt mode to trigger the TRNG writing with the TMR0 setup 
; at its highest possible value, which will give us the most jitter.

TRNG_Generate:
    lfsr    2, Key_Buffer
    movlw   16
    movwf   TRNG_counter, A
    
    bsf     WDTCON, 0, A    ; Manually enable WDT (SWDTEN bit) if using CONFIG WDTEN=SWON

TRNG_Generate_Loop:
    clrwdt          
    sleep           
    nop             

    movf    TMR0L, W, A     ; W = New jittered byte
    xorwf   INDF2, W, A     ; XOR W with what's currently at FSR2
    movwf   POSTINC2, A     ; Store result back and move FSR2 to next byte

    decfsz  TRNG_counter, F, A
    bra     TRNG_Generate_Loop
    return
