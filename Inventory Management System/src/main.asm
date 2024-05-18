default rel  ; Use RIP-relative addressing
bits 64  ; Target 64-bit architecture exclusively

%include "src/common.asm"
%include "src/dynamic_array.asm"
%include "src/console.asm"
%include "src/string.asm"

global mainCRTStartup  ; Entry point for the CONSOLE subsystem


; Rodata section
section .rodata

control:
    .clear_screen: db ESC, "[1;1H",  ESC, "[2J", ESC, "[3J", NULL  ; Resets cursor position and clears the screen


; Data section
section .data


; Bss section
sectalign 8
section .bss

; A dynamic array to store item information
alignb 8 
item_array:
    .address:       resb 8
    .count:         resb 4
    .capacity:      resb 4
    .member_size:   resb 4


; Text section
section .text

; Entry point for the CONSOLE subsystem 
mainCRTStartup:
    sub rsp, 8  ; Align the stack to a 16-byte boundary
    jmp exit
