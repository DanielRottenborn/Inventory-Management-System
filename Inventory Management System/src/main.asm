default rel  ; Use RIP-relative addressing
bits 64  ; Target 64-bit architecture exclusively

%include "src/common.asm"
%include "src/dynamic_array.asm"
%include "src/console.asm"
%include "src/string.asm"

global mainCRTStartup  ; Entry point for the CONSOLE subsystem

; Constants
ITEM_CATEGORY_OFFSET equ  64  ; Offset to the item category parameter
ITEM_PRIORITY_OFFSET equ 128  ; Offset to the item priority parameter
ITEM_QUANTITY_OFFSET equ 132  ; Offset to the item quantity parameter
ITEM_CAPACITY_OFFSET equ 136  ; Offset to the item capacity parameter

; Rodata section
section .rodata

window_title: db "Inventory Management System - TP065500", NULL

table_border:
    .horizontal:            db " ", 172 dup "-", LF, NULL
    .horizontal_contracted: db " ", 110 dup "-", LF, NULL
    .horizontal_separator:            db " |", 63 + 2 dup "-", "|", 63 + 2 dup "-", "|------------|------------|------------|", LF, NULL
    .horizontal_separator_contracted: db " |", 32 + 2 dup "-", "|", 32 + 2 dup "-", "|------------|------------|------------|", LF, NULL 
    .left: db " |", NULL
    .left_padding: db " ", NULL
    .middle: db " | ", NULL
    .right: db " ", DEFAULT_BG_COLOR, "|", LF, NULL  ; Resets background color

table_header:            db " | Item Name", 63 - 9 dup " ", " | Category", 63 - 8 dup " ", " | Priority   | Quantity   | Capacity   |", LF, NULL
table_header_contracted: db " | Item Name", 32 - 9 dup " ", " | Category", 32 - 8 dup " ", " | Priority   | Quantity   | Capacity   |", LF, NULL

table_empty:            db " | No Items Found", 63 - 14 + 1 dup " ", "|", 63 + 2 dup " ", "|            |            |            |", LF, NULL
table_empty_contracted: db " | No Items Found", 32 - 14 + 1 dup " ", "|", 32 + 2 dup " ", "|            |            |            |", LF, NULL


; Data section
sectalign 4
section .data

    alignb 4
    item_table.contract: dd 1  ; Bool, should the item table be contracted or expanded


; Bss section
sectalign 8
section .bss

; A dynamic array to store item information
alignb 8 
items:
    .address:       resb 8
    .count:         resb 4
    .capacity:      resb 4
    .member_size:   resb 4

; A dynamic array to store item display sequence
alignb 8 
item_display_sequence:
    .address:       resb 8
    .count:         resb 4
    .capacity:      resb 4
    .member_size:   resb 4


; Text section
section .text

; Entry point for the CONSOLE subsystem 
mainCRTStartup:
    sub rsp, 8  ; Align the stack to a 16-byte boundary

    fast_call inventory_system.init
    fast_call inventory_system.display_item_table
    fast_call console.read_int

    jmp exit



; Inventory Management System
inventory_system:

    ; Initialize the inventory system
    .init:
        sub rsp, 8  ; Align the stack to a 16-byte boundary

        ; Initialize console
        lea rcx, [window_title]
        fast_call console.init

        ; Initialize item array
        lea rcx, [items]
        mov edx, 64 + 64 + 4 + 4 + 4  ; Size of two 64-byte strings, three 32-bit integers
        fast_call dynamic_array.init

        ; Initialize display sequence array
        lea rcx, [item_display_sequence]
        mov edx, 4  ; Size of a 32-bit item index
        fast_call dynamic_array.init

        add rsp, 8  ; Restore the stack
        ret


    .display_item_table:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], r12  ; Save nonvolatile register

        ; Display header and top borders
        cmp DWORD [item_table.contract], 1
        je ._display_contracted_header  ; Display contracted header if the flag is set

            ; Display horizontal border
            lea rcx, [table_border.horizontal]
            fast_call console.print_string            

            ; Display table header
            lea rcx, [table_header]
            fast_call console.print_string  

            ; Display horizontal separator
            lea rcx, [table_border.horizontal_separator]
            fast_call console.print_string  

            jmp ._display_items

        ._display_contracted_header:

            ; Display contracted horizontal border
            lea rcx, [table_border.horizontal_contracted]
            fast_call console.print_string            

            ; Display contracted table header
            lea rcx, [table_header_contracted]
            fast_call console.print_string  

            ; Display contracted horizontal separator
            lea rcx, [table_border.horizontal_separator_contracted]
            fast_call console.print_string  

        ._display_items:

        mov r12d, 0  ; Set display counter to 0

        ._display_items_loop:
            cmp r12d, [item_display_sequence + ARRAY_COUNT_OFFSET]
            jae ._end_display_items_loop  ; Terminate display sequence if all items in display sequence array were processed

            ; Get index of the next item to be displayed
            lea rcx, [item_display_sequence]
            mov edx, r12d
            fast_call dynamic_array.get

            ; Get pointer the next item to be displayed
            lea rcx, [items]
            mov edx, [rax]
            fast_call dynamic_array.get

            ; Display the item
            lea rcx, [rax]
            mov edx, [item_table.contract]
            fast_call .display_item_info

            ; Continue itteration
            inc r12d
            jmp ._display_items_loop

        ._end_display_items_loop:

        cmp r12d, 0
        ja ._display_footer  ; Check if the table is empty and proceed to footer display if it is not

        ; Display a message to indicate that the table is empty
        cmp DWORD [item_table.contract], 1
        je ._display_contracted_message  ; Display contracted message if the flag is set

            ; Display empty table message
            lea rcx, [table_empty]
            fast_call console.print_string            

            jmp ._display_footer

        ._display_contracted_message:

            ; Display contracted empty table message
            lea rcx, [table_empty_contracted]
            fast_call console.print_string  

        ._display_footer:

        ; Display footer
        cmp DWORD [item_table.contract], 1
        je ._display_contracted_footer  ; Display contracted footer if the flag is set

            ; Display horizontal border
            lea rcx, [table_border.horizontal]
            fast_call console.print_string            

            jmp ._end_display_item_table

        ._display_contracted_footer:

            ; Display contracted horizontal border
            lea rcx, [table_border.horizontal_contracted]
            fast_call console.print_string 
        
        ._end_display_item_table:    

        mov r12, [rsp + 16]  ; Restore nonvolatile register
        add rsp, 8  ; Restore the stack
        ret


    ; Prints out a table entry with member information, either in long or in short form args(QWORD item struct pointer, DWORD bool shorten)
    .display_item_info:
        ; Prolog
        mov [rsp + 8], r12  ; Save nonvolotile register
        mov [rsp + 16], r13  ; Save nonvolotile register
        sub rsp, 8 + 64  ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary
        mov r12, rcx  ; Save item struct pointer in nonvolotile register
        mov r13d, edx  ; Save shorten flag in nonvolotile register

        ; Print left border
        lea rcx, [table_border.left]
        fast_call console.print_string

        cmp DWORD [r12 + ITEM_QUANTITY_OFFSET], 3
        jae ._display_item_info  ; Check if item quantity is equal to or greater than 3
       
            lea rcx, [console_control.highlight_background]
            fast_call console.print_string  ; Highlight the row otherwise

        ._display_item_info:

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
        lea rdx, [r12 + ITEM_CATEGORY_OFFSET]
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
        mov ecx, [r12 + ITEM_PRIORITY_OFFSET]
        fast_call console.print_int

        ; Print border
        lea rcx, [table_border.middle]
        fast_call console.print_string

        ; Print the quantity value
        mov ecx, [r12 + ITEM_QUANTITY_OFFSET]
        fast_call console.print_int

        ; Print border
        lea rcx, [table_border.middle]
        fast_call console.print_string

        ; Print the max quantity value
        mov ecx, [r12 + ITEM_CAPACITY_OFFSET]
        fast_call console.print_int

        ; Print right border and restore background color
        lea rcx, [table_border.right]
        fast_call console.print_string

        ; Epilog
        add rsp, 8 + 64  ; Restore the stack
        mov r12, [rsp + 8]  ; Restore nonvolotile register
        mov r13, [rsp + 16]  ; Restore nonvolotile register
        ret