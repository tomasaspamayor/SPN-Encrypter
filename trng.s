#include <xc.inc>

; This module will use time jitter in the clocks of the microcontroller to generate random numbers. It will
; use the UART receiver to sample the noise in the system, which is a common technique for TRNGs on microcontrollers.
; The TRNG will generate 128 bits (16 bytes) of random data and store it in a buffer for later retrieval.

global  Generate_Master_Key
extrn   Key_Buffer

psect	udata_acs
TRNG_counter:	ds  1
TIMER:		ds  1
TR_count_reg:	ds  1
TR_Temp_0:	ds  1
    

psect	trng_code,class=CODE
Init_TRNG_Timers:
    ; --- Timer0: FAST (Instruction Clock) ---
    movlw   0b11011000      ; T08BIT=1, T0CS=0, PSA=0 (1:2 prescaler)
    movwf   T0CON, A

    ; --- Replace Timer1 with the Asynchronous ADC FRC ---
    ; ADCON2: Right justify, ACQT=000, ADCS=011 (Selects the dedicated FRC clock)
    movlw   0b00001011      
    movwf   ADCON2, A
    
    ; ADCON0: Turn on the ADC module (Channel 0)
    movlw   0b00000001      ; ADON = 1
    movwf   ADCON0, A
    
    return

Generate_Master_Key:
    call    Init_TRNG_Timers
    lfsr    2, Key_Buffer
    movlw   16
    movwf   TR_count_reg, A
    
Byte_Loop:
    clrf    TR_Temp_0, A    
    movlw   8               
    movwf   TRNG_counter, A

TRNG_Generate_Loop:
    ; Start an asynchronous ADC conversion
    bsf     ADCON0, 1, A    ; Set the GO/DONE bit

Wait_For_Tick:
    ; Wait for the conversion to complete
    btfsc   ADCON0, 1, A    ; Check if GO/DONE is cleared by hardware
    bra     Wait_For_Tick   ; If still 1, keep waiting

Capture_Jitter:
    ; The conversion finished! Sample the fast instruction timer
    movf    TMR0L, W, A     
    andlw   0x01            
    
    rlncf   TR_Temp_0, F, A 
    iorwf   TR_Temp_0, F, A 
    
    ; --- MANDATORY ADC RESET DELAY ---
    ; Wait ~10 microseconds to allow the ADC to recover (2 TAD)
    ; before we allow the loop to set GO/DONE again.
    movlw   50              ; Load delay counter (Adjust higher if your system clock is very fast)
    movwf   TIMER, A        
ADC_Cooldown_Loop:
    decfsz  TIMER, F, A     ; Decrement TIMER
    bra     ADC_Cooldown_Loop ; Loop until zero
    ; ---------------------------------
    
    decfsz  TRNG_counter, F, A
    bra     TRNG_Generate_Loop
    
    movff   TR_Temp_0, POSTINC2
    
    decfsz  TR_count_reg, F, A
    bra     Byte_Loop
    
    return
    