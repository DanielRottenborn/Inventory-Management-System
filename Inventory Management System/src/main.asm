default rel  ; Use RIP-relative addressing
bits 64  ; Target 64-bit architecture exclusively

%include "src/common.asm"
%include "src/dynamic_array.asm"
%include "src/console.asm"
%include "src/string.asm"

global mainCRTStartup  ; Entry point for the CONSOLE subsystem


; Rodata section
section .rodata

window_title: db "Inventory Management System - TP065500", NULL

table_border:
    .left: db "|", NULL
    .left_padding: db " ", NULL
    .middle: db " | ", NULL
    .right: db " ", DEFAULT_BG_COLOR, "|", LF, NULL  ; Resets background color


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

    lea rcx, [window_title]
    fast_call console.init

    jmp exit


; Prints out a table entry with member information, either in long or in short form args(QWORD item struct pointer, DWORD bool shorten)
print_item_info:
    ; Prolog
    mov [rsp + 8], r12  ; Save nonvolotile register
    mov [rsp + 16], r13  ; Save nonvolotile register
    sub rsp, 8 + 64  ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary
    mov r12, rcx  ; Save item struct pointer in nonvolotile register
    mov r13d, edx  ; Save shorten flag in nonvolotile register

    ; Print left border
    lea rcx, [table_border.left]
    fast_call console.print_string

    cmp DWORD [r12 + 160], 3
    jae ._print_item_info  ; Check if item quantity is equal to or greater than 3
       
        lea rcx, [console_control.highlight_background]
        fast_call console.print_string  ; Highlight the row otherwise

    ._print_item_info:

    ; Print left border padding
    lea rcx, [table_border.left_padding]
    fast_call console.print_string

    ; Copy item name into the temporary buffer
    lea rcx, [rsp]  ; Use temporary buffer as destination
    lea rdx, [r12]  ; Item struct pointer points to the name of the item string
    fast_call string.copy

    ; Pad the name
    lea rcx, [rsp]  ; Use temporary buffer as string argument for padding
    cmp r13d, 0
    jnz ._shorten_name  ; Check if strings should be shortened to 32 characters
        fast_call string.pad  ; Pad to 63 characters otherwise
        jmp ._end_name_padding

    ._shorten_name:
        fast_call string.pad_short  ; Pad or shorten to 32 characters   

    ._end_name_padding:

    ; Print the name
    lea rcx, [rsp]
    fast_call console.print_string

    ; Print border
    lea rcx, [table_border.middle]
    fast_call console.print_string

    ; Copy item category into the temporary buffer
    lea rcx, [rsp]  ; Use temporary buffer as destination
    lea rdx, [r12 + 64]
    fast_call string.copy

    ; Pad the category
    lea rcx, [rsp]  ; Use temporary buffer as string argument for padding
    cmp r13d, 0
    jnz ._shorten_category  ; Check if strings should be shortened to 32 characters
        fast_call string.pad  ; Pad to 63 characters otherwise
        jmp ._end_category_padding

    ._shorten_category:
        fast_call string.pad_short  ; Pad or shorten to 32 characters   

    ._end_category_padding:

    ; Print the category
    lea rcx, [rsp]
    fast_call console.print_string

    ; Print border
    lea rcx, [table_border.middle]
    fast_call console.print_string

    ; Print the priority value
    mov ecx, [r12 + 128]
    fast_call console.print_int

    ; Print border
    lea rcx, [table_border.middle]
    fast_call console.print_string

    ; Print the quantity value
    mov ecx, [r12 + 160]
    fast_call console.print_int

    ; Print border
    lea rcx, [table_border.middle]
    fast_call console.print_string

    ; Print the max quantity value
    mov ecx, [r12 + 192]
    fast_call console.print_int

    ; Print right border and restore background color
    lea rcx, [table_border.right]
    fast_call console.print_string

    ; Epilog
    add rsp, 8 + 64  ; Restore the stack
    mov r12, [rsp + 8]  ; Restore nonvolotile register
    mov r13, [rsp + 16]  ; Restore nonvolotile register
    ret