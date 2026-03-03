#include <xc.inc>

global  pkg_buffer

psect	udata_acs   ; reserve data space in access ram
pkg_buffer:  ds  16      ; Reserve exclusive 16 bytes for the 128-bit packet

psect   code
Main:
    call    UART_Setup
Loop:
    call    UART_Receive_Package ; State 1: Blocks until 16 bytes arrive

    ; --- State 2: Encryption/Decryption Logic ---
    ; [Work on pkg_buffer here]

    call    UART_Send_Package    ; State 3: Sends the 16 bytes back to PC
    bra     Loop
