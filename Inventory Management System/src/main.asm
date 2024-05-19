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

table_header:            db " |", TABLE_HEADER_BG_COLOR, " Item Name", 63 - 9 dup " ", " | Category", 63 - 8 dup " ", " | Priority   | Quantity   | Capacity   ", DEFAULT_BG_COLOR, "|", LF, NULL
table_header_contracted: db " |", TABLE_HEADER_BG_COLOR, " Item Name", 32 - 9 dup " ", " | Category", 32 - 8 dup " ", " | Priority   | Quantity   | Capacity   ", DEFAULT_BG_COLOR, "|", LF, NULL

table_empty:             db " | No Items Found", 63 - 14 + 1 dup " ", "|", 63 + 2 dup " ", "|            |            |            |", LF, NULL
table_empty_contracted:  db " | No Items Found", 32 - 14 + 1 dup " ", "|", 32 + 2 dup " ", "|            |            |            |", LF, NULL

messages:
    .remark:           db " *Items in quantity less than 3 are highlighted in red.", LF
                       db " *Type /help to get the list of available commands.", LF, LF, NULL

    .command_list: db "List of available commands:", LF
                   db "    /add - add a new item", LF, LF, NULL

    .invalid_command: db ERROR_COLOR, "Invalid command, try again: ", DEFAULT_COLOR, NULL

    .enter_name:     db "Enter item name: ", NULL
    .enter_category: db "Enter item category: ", NULL
    .enter_priority: db "Enter item priority: ", NULL
    .enter_quantity: db "Enter current item quantity: ", NULL 
    .enter_capacity: db "Enter available capacity: ", NULL

    .entered_capacity_zero: db ERROR_COLOR, "Capacity can not be zero, try again: ", DEFAULT_COLOR, NULL
    .entered_capacity_too_low: db ERROR_COLOR, "Entered capacity is too low, try again: ", DEFAULT_COLOR, NULL
    .empty_name: db ERROR_COLOR, "Item name should not be blank, try again: ", DEFAULT_COLOR, NULL 
    .item_exists: db ERROR_COLOR, "This item already exists, try again: ", DEFAULT_COLOR, NULL
    
commands:
    .help: db "/help", NULL
    .add: db "/add", NULL


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
display_sequence:
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
    fast_call inventory_system.run

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
        lea rcx, [display_sequence]
        mov edx, 4  ; Size of a 32-bit item index
        fast_call dynamic_array.init

        add rsp, 8  ; Restore the stack
        ret


    ; Main application loop, clear the screen, displays the item table and waits for user action, in cycle
    .run:
        sub rsp, 8  ; Align the stack to a 16-byte boundary 

        lea rcx, [console_control.clear_screen]
        fast_call console.print_string  ; Clear the screen

        fast_call .display_item_table  ; Display item table

        ; Display remark
        lea rcx, [messages.remark]
        fast_call console.print_string

        fast_call .await_command  ; Wait for user input

        add rsp, 8  ; Restore the stack
        jmp .run  ; Continue 


    ; Prints out available commands, waits for user input, and executes specified command
    .await_command:
        sub rsp, 8 + 64 ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary 

        lea rcx, [rsp]
        fast_call console.read_string  ; Read command from the console

        lea rcx, [rsp]
        lea rdx, [commands.help]
        fast_call string.compare  ; Compare input to the help command

        cmp eax, 1
        jne ._compare_to_add  ; Check for equality

            lea rcx, [messages.command_list]
            fast_call console.print_string  ; Show command list
            add rsp, 8 + 64 ; Restore the stack
            jmp .await_command  ; Wait for another command

        ._compare_to_add:

        lea rcx, [rsp]
        lea rdx, [commands.add]
        fast_call string.compare  ; Compare input to the add item command

        cmp eax, 1
        jne ._invalid_command  ; Check for equality

            fast_call .add_item  ; Execute add_item procedure
            jmp ._end_await_command

        ._invalid_command:

            lea rcx, [messages.invalid_command]
            fast_call console.print_string  ; Notify the user that the command is invalid

            add rsp, 8 + 64 ; Restore the stack
            jmp .await_command ; Prompt the user again

        ._end_await_command:

        add rsp, 8 + 64 ; Restore the stack
        ret


    ; Prompts user to input item info, then adds a new item to the system
    .add_item:
        sub rsp, 8 + 144  ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary        

        ; Prompt for item name
        lea rcx, [messages.enter_name]
        fast_call console.print_string  ; Display prompt message

        ._prompt_for_item_name:

        lea rcx, [rsp]
        fast_call console.read_string  ; Read name from the console

        lea rcx, [rsp]
        fast_call string.len  ; Check entered name length

        cmp rax, 0
        jne ._verify_name_uniqueness

            lea rcx, [messages.empty_name]
            fast_call console.print_string  ; Notify user that the entered name should not be empty prompt again otherwise 
            
            jmp ._prompt_for_item_name

        ._verify_name_uniqueness:

        lea rcx, [rsp]
        fast_call .find_item_by_name  ; Search for items with similar name

        cmp rax, -1
        je ._prompt_for_item_category  ; Proceed if the name is unique

            lea rcx, [messages.item_exists]
            fast_call console.print_string  ; Notify user that the entered name is already in use and prompt again otherwise 
            
            jmp ._prompt_for_item_name            

        ._prompt_for_item_category:

        ; Prompt for item category
        lea rcx, [messages.enter_category]
        fast_call console.print_string  ; Display prompt message
        lea rcx, [rsp + ITEM_CATEGORY_OFFSET]
        fast_call console.read_string  ; Read category from the console

        ; Prompt for item priority
        lea rcx, [messages.enter_priority]
        fast_call console.print_string  ; Display prompt message
        fast_call console.read_int  ; Read priority from the console
        mov [rsp + ITEM_PRIORITY_OFFSET], eax  ; Save in temporary buffer

        ; Prompt for item quantity
        lea rcx, [messages.enter_quantity]
        fast_call console.print_string  ; Display prompt message
        fast_call console.read_int  ; Read quantity from the console
        mov [rsp + ITEM_QUANTITY_OFFSET], eax  ; Save in temporary buffer

        ; Prompt for item capacity
        lea rcx, [messages.enter_capacity]
        fast_call console.print_string  ; Display prompt message

        ._prompt_for_capacity:

        fast_call console.read_int  ; Read capacity from the console
        mov [rsp + ITEM_CAPACITY_OFFSET], eax  ; Save in temporary buffer

        cmp eax, 0
        ja ._check_against_quantity  ; Check if capacity is not zero and proceed

            lea rcx, [messages.entered_capacity_zero]
            fast_call console.print_string  ; Notify user that entered capacity is too low and prompt again otherwise 
            
            jmp ._prompt_for_capacity

        ._check_against_quantity:

        cmp eax, [rsp + ITEM_QUANTITY_OFFSET]
        jae ._push_new_item  ; Check if capacity is equal to or greater than quantity entered and proceed

            lea rcx, [messages.entered_capacity_too_low]
            fast_call console.print_string  ; Notify user that entered capacity is too low and prompt again otherwise 
            
            jmp ._prompt_for_capacity

        ._push_new_item:

        ; Push new item to the array
        lea rcx, [items]
        lea rdx, [rsp]
        fast_call dynamic_array.push

        ; Push item index to the display sequence array
        mov [rsp], eax
        lea rcx, [display_sequence]
        lea rdx, [rsp]
        fast_call dynamic_array.push

        add rsp, 8 + 144  ; Restore the stack
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
            cmp r12d, [display_sequence + ARRAY_COUNT_OFFSET]
            jae ._end_display_items_loop  ; Terminate display sequence if all items in display sequence array were processed

            ; Get index of the next item to be displayed
            lea rcx, [display_sequence]
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


    ; Prints out a table entry with member information, either in long or in short form, args(QWORD item struct pointer, DWORD bool shorten)
    .display_item_info:
        ; Prolog
        mov [rsp + 8], r12  ; Save nonvolatile register
        mov [rsp + 16], r13  ; Save nonvolatile register
        sub rsp, 8 + 64  ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary
        mov r12, rcx  ; Save item struct pointer in nonvolatile register
        mov r13d, edx  ; Save shorten flag in nonvolatile register

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
        mov r12, [rsp + 8]  ; Restore nonvolatile register
        mov r13, [rsp + 16]  ; Restore nonvolatile register
        ret


    ; Searches for an item by name, returns index of the found item or QWORD -1 if not found, args(QWORD name string pointer)
    .find_item_by_name:
        ; Prolog
        mov [rsp + 8], r12   ; Save nonvolatile register
        mov [rsp + 16], r13  ; Save nonvolatile register
        mov [rsp + 24], r14  ; Save nonvolatile register
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov r12, rcx  ; Save the name string pointer in nonvolatile register

        mov r13d, 0  ; Initialize current item index
        mov r14d, [items + ARRAY_COUNT_OFFSET]  ; Save array count in novolatile register

        ._search_for_item_loop:
            cmp r13d, r14d
            je ._end_search_for_item_loop  ; End itteration if all items in the array were checked

            ; Get pointer to the current item
            lea rcx, [items]
            mov edx, r13d
            fast_call dynamic_array.get

            ; Compare names
            lea rcx, [r12]
            lea rdx, [rax]  ; Pointer to the name of the current item
            fast_call string.compare

            cmp rax, 1
            je ._end_search_for_item_loop  ; Stop itteration if the item was found

            inc r13d  ; Increment item index
            jmp ._search_for_item_loop  ; Continue itteration

        ._end_search_for_item_loop:

        mov eax, r13d  ; Set up return value

        cmp eax, r14d
        jb ._end_find_item_by_name  ; Check if item index is below item count, meaning the item was found

            mov rax, -1  ; return -1 otherwise

        ._end_find_item_by_name:

        ; Epilog
        add rsp, 8  ; Restore the stack
        mov r12, [rsp + 8]  ; Restore nonvolatile register
        mov r13, [rsp + 16]  ; Restore nonvolatile register
        mov r14, [rsp + 24]  ; Restore nonvolatile register
        ret            
