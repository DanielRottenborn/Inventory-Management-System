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
    .horizontal:            db " +", 170 dup "-", "+", LF, NULL
    .horizontal_contracted: db " +", 108 dup "-", "+", LF, NULL
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
    .remark: db " *Items in quantity less than 3 are highlighted in red.", LF
             db " *Type /help to get the list of available commands.", LF, LF, NULL

    .command_list: db "List of available commands:", LF
                   db "    /add - add a new item", LF
                   db "    /sell - sell a certain quantity of items", LF
                   db "    /order - order a certain quantity of items", LF
                   db "    /modify - modify an item", LF
                   db "    /remove - remove an item", LF
                   db "    /clear - remove all items", LF
                   db "    /expand - expand the item table", LF
                   db "    /contract - contract the item table", LF
                   db "    /back - cancel the current action", LF, LF, NULL

    .enter_name:     db "Enter item name: ", NULL
    .enter_category: db "Enter item category: ", NULL
    .enter_priority: db "Enter item priority: ", NULL
    .enter_quantity: db "Enter current item quantity: ", NULL 
    .enter_capacity: db "Enter available capacity: ", NULL
    .enter_number_to_sell: db "Enter the quantity to sell: ", NULL
    .enter_number_to_order: db "Enter the quantity to order: ", NULL
    .enter_attribute_to_modify: db "Enter the attribute to be modified: ", NULL
    .change_category: db "Change category to: ", NULL
    .change_priority: db "Change priority to: ", NULL
    .change_quantity: db "Change quantity to: ", NULL
    .change_capacity: db "Change capacity to: ", NULL

    ; Error messages
    .invalid_command: db ERROR_COLOR, "Invalid command, try again: ", DEFAULT_COLOR, NULL
    .inventory_empty: db ERROR_COLOR, "This command requires a non-empty inventory, try other commands first: ", DEFAULT_COLOR, NULL
    .empty_name: db ERROR_COLOR, "Item name should not be blank, try again: ", DEFAULT_COLOR, NULL
    .name_already_in_use: db ERROR_COLOR, "This name is already in use, try again: ", DEFAULT_COLOR, NULL
    .entered_capacity_too_low: db ERROR_COLOR, "Entered capacity is too low for the current item quantity, try again: ", DEFAULT_COLOR, NULL
    .item_not_found: db ERROR_COLOR, "Item not found, try again: ", DEFAULT_COLOR, NULL
    .quantity_too_low_to_sell: db ERROR_COLOR, "Item quantity is too low to sell the number specified, try again: ", DEFAULT_COLOR, NULL
    .capacity_too_low_to_order: db ERROR_COLOR, "Remaining item capacity is too low to order the number specified, try again: ", DEFAULT_COLOR, NULL
    .invalid_attribute: db ERROR_COLOR, "Enter a valid atttribute (name, category, priority, quantity, or capacity): ", DEFAULT_COLOR, NULL
    .entered_quantity_too_high: db ERROR_COLOR, "Entered quantity is to high for the current capacity, try again: ", DEFAULT_COLOR, NULL

commands:
    .help: db "/help", NULL
    .add: db "/add", NULL
    .sell: db "/sell", NULL
    .order: db "/order", NULL
    .modify: db "/modify", NULL
    .remove: db "/remove", NULL
    .clear: db "/clear", NULL
    .expand: db "/expand", NULL
    .contract: db "/contract", NULL
    .back: db "/back", NULL

attr_names:
    .name: db "name", NULL
    .category: db "category", NULL
    .priority: db "priority", NULL
    .quantity: db "quantity", NULL
    .capacity: db "capacity", NULL


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
        lea rdx, [commands.back]
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


    ; Main application loop, clears the screen, displays the item table and waits for user action, in cycle
    .run:
        sub rsp, 8  ; Align the stack to a 16-byte boundary 

        ; This works under the assumption that all user input has been processed before any action irreversibly modifies the program state 
        lea rcx, [._run]
        fast_call console.capture_env_for_abort

        ._run:

            lea rcx, [console_control.clear_screen]
            fast_call console.print_string  ; Clear the screen

            fast_call .display_item_table  ; Display item table

            ; Display remark
            lea rcx, [messages.remark]
            fast_call console.print_string

            fast_call .await_command  ; Wait for user input

            jmp ._run  ; Continue 


    ; Prints out available commands, waits for user input, and executes specified command
    .await_command:
        sub rsp, 8 + 64 ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary 

        lea rcx, [rsp]
        fast_call console.read_string  ; Read command from the console

        lea rcx, [rsp]
        fast_call string.lower  ; Convert entered command into lowercase

        ; Compare input to the help command
        lea rcx, [rsp]
        lea rdx, [commands.help]
        fast_call string.compare

        cmp eax, 1
        jne ._compare_to_add  ; Check for equality

            lea rcx, [messages.command_list]
            fast_call console.print_string  ; Show command list
            add rsp, 8 + 64 ; Restore the stack
            jmp .await_command  ; Wait for another command
             
        ._compare_to_add:

        ; Compare input to the add item command
        lea rcx, [rsp]
        lea rdx, [commands.add]
        fast_call string.compare  

        cmp eax, 1
        jne ._compare_to_sell  ; Check for equality

            fast_call .add_item  ; Execute add_item procedure
            jmp ._end_await_command

        ._compare_to_sell:

        ; Compare input to the sell item command
        lea rcx, [rsp]
        lea rdx, [commands.sell]
        fast_call string.compare  

        cmp eax, 1
        jne ._compare_to_order  ; Check for equality

            cmp DWORD [items + ARRAY_COUNT_OFFSET], 0
            je ._command_requires_nonempty_inventory  ; Check if inventory is not empty

            fast_call .sell_item  ; Execute sell item procedure
            jmp ._end_await_command

        ._compare_to_order:

        ; Compare input to the order item command
        lea rcx, [rsp]
        lea rdx, [commands.order]
        fast_call string.compare  

        cmp eax, 1
        jne ._compare_to_modify  ; Check for equality

            cmp DWORD [items + ARRAY_COUNT_OFFSET], 0
            je ._command_requires_nonempty_inventory  ; Check if inventory is not empty

            fast_call .order_item  ; Execute sell item procedure
            jmp ._end_await_command

        ._compare_to_modify:

        ; Compare input to the modify item command
        lea rcx, [rsp]
        lea rdx, [commands.modify]
        fast_call string.compare  

        cmp eax, 1
        jne ._compare_to_remove  ; Check for equality

            cmp DWORD [items + ARRAY_COUNT_OFFSET], 0
            je ._command_requires_nonempty_inventory  ; Check if inventory is not empty

            fast_call .modify_item  ; Execute sell item procedure
            jmp ._end_await_command

        ._compare_to_remove:

        ; Compare input to the remove item command
        lea rcx, [rsp]
        lea rdx, [commands.remove]
        fast_call string.compare  

        cmp eax, 1
        jne ._compare_to_clear  ; Check for equality

            cmp DWORD [items + ARRAY_COUNT_OFFSET], 0
            je ._command_requires_nonempty_inventory  ; Check if inventory is not empty

            fast_call .remove_item  ; Execute remove_item procedure
            jmp ._end_await_command

        ._compare_to_clear:

        ; Compare input to the clear inventory command
        lea rcx, [rsp]
        lea rdx, [commands.clear]
        fast_call string.compare  

        cmp eax, 1
        jne ._compare_to_expand  ; Check for equality

            cmp DWORD [items + ARRAY_COUNT_OFFSET], 0
            je ._command_requires_nonempty_inventory  ; Check if inventory is not empty

            lea rcx, [items]
            fast_call dynamic_array.clear  ; Clear the item array

            lea rcx, [display_sequence]
            fast_call dynamic_array.clear  ; Clear the display sequence

            jmp ._end_await_command
        
        ._compare_to_expand:

        ; Compare input to the expand table command
        lea rcx, [rsp]
        lea rdx, [commands.expand]
        fast_call string.compare  

        cmp eax, 1
        jne ._compare_to_contract ; Check for equality
         
            mov DWORD [item_table.contract], 0  ; Change table contraction setting
            jmp ._end_await_command

        ._compare_to_contract:        

       ; Compare input to the contract table command
        lea rcx, [rsp]
        lea rdx, [commands.contract]
        fast_call string.compare  

        cmp eax, 1
        jne ._invalid_command ; Check for equality

            mov DWORD [item_table.contract], 1  ; Change table contraction setting            
            jmp ._end_await_command

        ._invalid_command:

            lea rcx, [messages.invalid_command]
            fast_call console.print_string  ; Notify the user that the command is invalid

            add rsp, 8 + 64 ; Restore the stack
            jmp .await_command ; Prompt the user again

        ._command_requires_nonempty_inventory:

            lea rcx, [messages.inventory_empty]
            fast_call console.print_string  ; Notify the user that the command requires a non-empty inventory

            add rsp, 8 + 64 ; Restore the stack
            jmp .await_command ; Prompt the user again

        ._end_await_command:

        add rsp, 8 + 64 ; Restore the stack
        ret


    ; Prompts the user to input item info, then adds a new item to the system
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
            fast_call console.print_string  ; Notify the user that the entered name should not be empty prompt again otherwise 
            
            jmp ._prompt_for_item_name

        ._verify_name_uniqueness:

        lea rcx, [rsp]
        fast_call .find_item_by_name  ; Search for items with similar name

        cmp rax, -1
        je ._prompt_for_item_category  ; Proceed if the name is unique

            lea rcx, [messages.name_already_in_use]
            fast_call console.print_string  ; Notify the user that the entered name is already in use and prompt again otherwise 
            
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

        mov ecx, [rsp + ITEM_QUANTITY_OFFSET]  ; Use current item quantity to validate
        fast_call .prompt_for_capacity  ; Prompt for item capacity
        mov [rsp + ITEM_CAPACITY_OFFSET], eax  ; Save in temporary buffer

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


    ; Prompts the user to input item name, then reduces the quantity of that item by the specified number
    .sell_item:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], r12  ; Save nonvolatile register    
        mov [rsp + 24], r13  ; Save nonvolatile register 

        ; Prompt for item name
        lea rcx, [messages.enter_name]
        fast_call console.print_string  ; Display prompt message

        fast_call .select_item  ; Start item selection
        mov r12d, eax  ; Save item index in nonvolatile register

        lea rcx, [items]
        mov edx, r12d
        fast_call dynamic_array.get  ; Get pointer to the selected item
        mov r13d, [rax + ITEM_QUANTITY_OFFSET]  ; Save current item quantity in nonvolatile register

        ; Prompt for the number of items to sell
        lea rcx, [messages.enter_number_to_sell]
        fast_call console.print_string  ; Display prompt message

        ._prompt_for_number_to_sell:

        fast_call console.read_int  ; Read number from the console
        cmp eax, r13d
        jbe ._end_prompt_for_number_to_sell  ; Proceed if the number entered is less than or equal to the current quantity

            lea rcx, [messages.quantity_too_low_to_sell]
            fast_call console.print_string  ; Notify the user that the quantity is too low to sell this number of items and prompt again           
            
            jmp ._prompt_for_number_to_sell

        ._end_prompt_for_number_to_sell:

        sub r13d, eax  ; Decrease current item quantity by the specified number

        ; Update item quantity
        lea rcx, [items]
        mov edx, r12d
        fast_call dynamic_array.get  ; Get pointer to the selected item
        mov [rax + ITEM_QUANTITY_OFFSET], r13d  ; Update item quantity

        ; Epilog
        mov r12, [rsp + 16]  ; Restore nonvolatile register    
        mov r13, [rsp + 24]  ; Restore nonvolatile register 
        add rsp, 8  ; Align the stack to a 16-byte boundary
        ret


    ; Prompts the user to input item name, then increases the quantity of that item by the specified number
    .order_item:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], r12  ; Save nonvolatile register    
        mov [rsp + 24], r13  ; Save nonvolatile register 

        ; Prompt for item name
        lea rcx, [messages.enter_name]
        fast_call console.print_string  ; Display prompt message

        fast_call .select_item  ; Start item selection
        mov r12d, eax  ; Save item index in nonvolatile register

        lea rcx, [items]
        mov edx, r12d
        fast_call dynamic_array.get  ; Get pointer to the selected item
        mov r13d, [rax + ITEM_CAPACITY_OFFSET]  ; Save current item capacity in nonvolatile register
        sub r13d, [rax + ITEM_QUANTITY_OFFSET]  ; Calculate remaining capacity

        ; Prompt for the number of items to order
        lea rcx, [messages.enter_number_to_order]
        fast_call console.print_string  ; Display prompt message

        ._prompt_for_number_to_order:

        fast_call console.read_int  ; Read number from the console
        cmp eax, r13d
        jbe ._end_prompt_for_number_to_order  ; Proceed if the number entered is less than or equal to the remaining capacity

            lea rcx, [messages.capacity_too_low_to_order]
            fast_call console.print_string  ; Notify the user that the capacity is to low to order this number of items and prompt again           
            
            jmp ._prompt_for_number_to_order

        ._end_prompt_for_number_to_order:

        mov r13d, eax  ; Save the number to order in nonvolatile register

        ; Increase item quantity
        lea rcx, [items]
        mov edx, r12d
        fast_call dynamic_array.get  ; Get pointer to the selected item
        add [rax + ITEM_QUANTITY_OFFSET], r13d  ; Increase item quantity

        ; Epilog
        mov r12, [rsp + 16]  ; Restore nonvolatile register    
        mov r13, [rsp + 24]  ; Restore nonvolatile register 
        add rsp, 8  ; Align the stack to a 16-byte boundary
        ret


    ; Prompts the user to input item name, then prompts to select the attribute to be modified and selects appropriate action
    .modify_item:
        ; Prolog
        mov [rsp + 8], r12  ; Save nonvolatile register 
        sub rsp, 8 + 64  ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary 

        ; Prompt for item name
        lea rcx, [messages.enter_name]
        fast_call console.print_string  ; Display prompt message

        fast_call .select_item  ; Start item selection
        mov r12d, eax  ; Save item index in nonvolatile register

        ; Prompt for attribute name
        lea rcx, [messages.enter_attribute_to_modify]
        fast_call console.print_string  ; Display prompt message

        ._select_attribute_to_modify:

        lea rcx, [rsp]
        fast_call console.read_string  ; Read command from the console

        lea rcx, [rsp]
        fast_call string.lower  ; Convert entered command into lowercase

        ; Compare input to the name attribute
        lea rcx, [rsp]
        lea rdx, [attr_names.name]
        fast_call string.compare

        cmp eax, 1
        jne ._compare_to_category  ; Check for equality

            ; Action here

            jmp ._end_select_attribute_to_modify  ; Proceed to return

        ._compare_to_category:

        ; Compare input to the category attribute
        lea rcx, [rsp]
        lea rdx, [attr_names.category]
        fast_call string.compare

        cmp eax, 1
        jne ._compare_to_priority  ; Check for equality

            mov eax, r12d
            fast_call .modify_category

            jmp ._end_select_attribute_to_modify  ; Proceed to return

        ._compare_to_priority:

        ; Compare input to the priority attribute
        lea rcx, [rsp]
        lea rdx, [attr_names.priority]
        fast_call string.compare

        cmp eax, 1
        jne ._compare_to_quantity  ; Check for equality

            mov eax, r12d
            fast_call .modify_priority

            jmp ._end_select_attribute_to_modify  ; Proceed to return

        ._compare_to_quantity:

        ; Compare input to the quantity attribute
        lea rcx, [rsp]
        lea rdx, [attr_names.quantity]
        fast_call string.compare

        cmp eax, 1
        jne ._compare_to_capacity  ; Check for equality

            mov eax, r12d
            fast_call .modify_quantity

            jmp ._end_select_attribute_to_modify  ; Proceed to return

        ._compare_to_capacity:

        ; Compare input to the capacity attribute
        lea rcx, [rsp]
        lea rdx, [attr_names.capacity]
        fast_call string.compare

        cmp eax, 1
        jne ._invalid_attribute  ; Check for equality

            mov eax, r12d
            fast_call .modify_capacity

            jmp ._end_select_attribute_to_modify  ; Proceed to return

        ._invalid_attribute:

            lea rcx, [messages.invalid_attribute]
            fast_call console.print_string  ; Notify the user that the attribute name is invalid            

            jmp ._select_attribute_to_modify  ; Prompt the user again

        ._end_select_attribute_to_modify:

        ; Epilog
        add rsp, 8 + 64  ; Restore the stack 
        mov r12, [rsp + 8]  ; Restore nonvolatile register 
        ret


    ; Prompts user for updated category name, then modifies the selected item, args(DWORD item index)
    .modify_category:
        ; Prolog
        mov [rsp + 8], r12  ; Save nonvolatile register
        sub rsp, 64 + 8  ; ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary        
        mov r12d, eax  ; Save item index in nonvolatile register

        ; Prompt for updated item category
        lea rcx, [messages.change_category]
        fast_call console.print_string  ; Display prompt message

        lea rcx, [rsp]
        fast_call console.read_string  ; Read updated category from the console

        ; Modify the item
        lea rcx, [items]
        mov edx, r12d
        fast_call dynamic_array.get  ; Get pointer to the item

        lea rcx, [rax + ITEM_CATEGORY_OFFSET]
        lea rdx, [rsp]
        fast_call string.copy  ; Modify the category attribute

        ; Epilog
        add rsp, 64 + 8  ; Restore the stack 
        mov r12, [rsp + 8]  ; Restore nonvolatile register
        ret


    ; Prompts user for updated priority value, then modifies the selected item, args(DWORD item index)
    .modify_priority:
        ; Prolog
        mov [rsp + 8], r12  ; Save nonvolatile register
        mov [rsp + 16], r13  ; Save nonvolatile register 
        sub rsp, 8  ; Align the stack to a 16-byte boundary         
        mov r12d, eax  ; Save item index in nonvolatile register

        ; Prompt for updated item priority
        lea rcx, [messages.change_priority]
        fast_call console.print_string  ; Display prompt message
        fast_call console.read_int  ; Read updated priority from the console
        mov r13d, eax  ; Save updated priority in nonvolatile register

        ; Modify the item
        lea rcx, [items]
        mov edx, r12d
        fast_call dynamic_array.get  ; Get pointer to the item
        mov [rax + ITEM_PRIORITY_OFFSET], r13d  ; Modify the priority attribute
  
        ; Epilog
        add rsp, 8  ; Restore the stack 
        mov r12, [rsp + 8]  ; Restore nonvolatile register
        mov r13, [rsp + 16]  ; Restore nonvolatile register
        ret


    ; Prompts user for updated quantity, then modifies the selected item, args(DWORD item index)
    .modify_quantity:
        ; Prolog
        mov [rsp + 8], r12  ; Save nonvolatile register
        mov [rsp + 16], r13  ; Save nonvolatile register 
        sub rsp, 8  ; Align the stack to a 16-byte boundary         
        mov r12d, eax  ; Save item index in nonvolatile register

        ; Prompt for updated item quantity
        lea rcx, [messages.change_quantity]
        fast_call console.print_string  ; Display prompt message

        ._prompt_for_updated_quantity:

        fast_call console.read_int  ; Read updated quantity from the console
        mov r13d, eax  ; Save updated quantity in nonvolatile register

        ; Validate updated quantity
        lea rcx, [items]
        mov edx, r12d
        fast_call dynamic_array.get  ; Get pointer to the item

        cmp r13d, [rax + ITEM_CAPACITY_OFFSET] 
        jbe ._update_item_quantity  ; Proceed if updated quantity is less than or equal to current item capacity

            lea rcx, [messages.entered_quantity_too_high]
            fast_call console.print_string  ; Notify the user that the capacity is to low for the updated quantity and prompt again           

            jmp ._prompt_for_updated_quantity  ; Prompt the user again

        ._update_item_quantity:

        mov [rax + ITEM_QUANTITY_OFFSET], r13d  ; Modify the quantity attribute
  
        ; Epilog
        add rsp, 8  ; Restore the stack 
        mov r12, [rsp + 8]  ; Restore nonvolatile register
        mov r13, [rsp + 16]  ; Restore nonvolatile register
        ret


    ; Prompts user for updated capacity, then modifies the selected item, args(DWORD item index)
    .modify_capacity:
        ; Prolog
        mov [rsp + 8], r12  ; Save nonvolatile register
        mov [rsp + 16], r13  ; Save nonvolatile register 
        sub rsp, 8  ; Align the stack to a 16-byte boundary         
        mov r12d, eax  ; Save item index in nonvolatile register

        ; Prompt for updated item capacity
        lea rcx, [messages.change_capacity]
        fast_call console.print_string  ; Display prompt message

        lea rcx, [items]
        mov edx, r12d
        fast_call dynamic_array.get  ; Get pointer to the item
        mov r13, rax  ; Save pointer to the item in nonvolatile register
        
        mov ecx, [r13 + ITEM_QUANTITY_OFFSET]  ; Use current item quantity to validate
        fast_call .prompt_for_capacity  ; Prompt for updated item capacity

        mov [r13 + ITEM_CAPACITY_OFFSET], rax  ; Modify the capacity attribute
  
        ; Epilog
        add rsp, 8  ; Restore the stack 
        mov r12, [rsp + 8]  ; Restore nonvolatile register
        mov r13, [rsp + 16]  ; Restore nonvolatile register
        ret


    ; Prompts the user to input item name, then removes that item from the inventory and the display sequence
    .remove_item:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], r12  ; Save nonvolatile register    
        mov [rsp + 24], r13  ; Save nonvolatile register         
        mov [rsp + 32], r14  ; Save nonvolatile register

        ; Prompt for item name
        lea rcx, [messages.enter_name]
        fast_call console.print_string  ; Display prompt message

        fast_call .select_item  ; Start item selection
        mov r12d, eax  ; Save item index in nonvolatile register

        lea rcx, [items]
        mov edx, eax
        fast_call dynamic_array.remove  ; Remove item from the items array

        mov ecx, r12d  ; Retrieve the item index
        fast_call .find_in_display_sequence  ; Search for an item index in display sequence

        cmp rax, -1
        je ._update_display_sequence_indices  ; Skip deletion from display sequence if the item is not currently displayed

            lea rcx, [display_sequence]
            mov edx, eax
            fast_call dynamic_array.remove  ; Remove item index from the display sequence

        ._update_display_sequence_indices:

        mov r13d, 0  ; Initialize display sequence index
        mov r14d, [display_sequence + ARRAY_COUNT_OFFSET]  ; Save display sequence count in nonvolatile register

        ._update_display_sequence_indices_loop:     

            cmp r13d, r14d
            jae ._end_update_display_sequence_indices_loop  ; Stop itteration if all display sequence entries were processed
            
            lea rcx, [display_sequence]
            mov edx, r13d
            call dynamic_array.get  ; Get next display sequence entry

            cmp [rax], r12d 
            jb ._continue_update_display_sequence_indices_loop  ; Skip correction if current item index is less than that of the deleted item

                dec DWORD [rax]  ; Decrement item index otherwise

            ._continue_update_display_sequence_indices_loop:
            
            inc r13d  ; Increment display sequence index
            jmp ._update_display_sequence_indices_loop  ; Continue itteration

        ._end_update_display_sequence_indices_loop:

        mov r12, [rsp + 16]  ; Restore nonvolatile register    
        mov r13, [rsp + 24]  ; Restore nonvolatile register 
        mov r14, [rsp + 32]  ; Restore nonvolatile register 
        add rsp, 8  ; Align the stack to a 16-byte boundary
        ret


    ; Repetitively reads a name from the console and searches for the item with that name until it is found, returns the index of that item
    .select_item:
        sub rsp, 8 + 64  ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary

        lea rcx, [rsp]
        fast_call console.read_string  ; Read name from the console

        lea rcx, [rsp]
        fast_call .find_item_by_name  ; Search for an item with entered name

        cmp rax, -1
        jne ._end_select_item  ; Proceed if the item is found

            lea rcx, [messages.item_not_found]
            fast_call console.print_string  ; Notify the user that this name is not registered and prompt again otherwise 
            
            add rsp, 8 + 64  ; Restore the stack
            jmp .select_item  ; Continue

        ._end_select_item:

        add rsp, 8 + 64  ; Restore the stack
        ret


    ; Prompts user for capacity until it passes validation, returns entered capacity, args(DWORD current item quantity)
    .prompt_for_capacity:
        ; Prolog
        mov [rsp + 8], r12  ; Save nonvolatile register
        sub rsp, 8  ; Align the stack to a 16-byte boundary         
        mov r12d, ecx  ; Save current item quantity in nonvolatile register

        ._read_and_validate_capacity:

        fast_call console.read_int  ; Read capacity from the console
 
        cmp eax, r12d
        jae ._end_read_and_validate_capacity  ; Check if capacity is equal to or greater than current item quantity and proceed

            lea rcx, [messages.entered_capacity_too_low]
            fast_call console.print_string  ; Notify the user that entered capacity is too low and prompt again otherwise 
            
            jmp ._read_and_validate_capacity

        ._end_read_and_validate_capacity:

        ; Epilog
        add rsp, 8  ; Restore the stack 
        mov r12, [rsp + 8]  ; Restore nonvolatile register
        ret


    ; Displays an inventory table
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

        ; Epilog
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
        

    ; Searches for an item index in display sequence, returns index of the found entry or QWORD -1 if not found, args(DWORD item index)
    .find_in_display_sequence:
        ; Prolog
        mov [rsp + 8], r12   ; Save nonvolatile register
        mov [rsp + 16], r13  ; Save nonvolatile register
        mov [rsp + 24], r14  ; Save nonvolatile register
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov r12d, ecx  ; Save item index in nonvolatile register

        mov r13d, 0  ; Initialize current display sequence index
        mov r14d, [display_sequence + ARRAY_COUNT_OFFSET]  ; Save array count in novolatile register

        ._search_for_index_loop:
            cmp r13d, r14d
            je ._end_search_for_index_loop  ; End itteration if all entries in the array were checked

            ; Get pointer to the current index value
            lea rcx, [display_sequence]
            mov edx, r13d
            fast_call dynamic_array.get

            ; Compare indices
            cmp [rax], r12d
            je ._end_search_for_index_loop  ; Stop itteration if the item index was found

            inc r13d  ; Increment current display sequence index
            jmp ._search_for_index_loop  ; Continue itteration

        ._end_search_for_index_loop:

        mov eax, r13d  ; Set up return value

        cmp eax, r14d
        jb ._end_find_in_display_sequence  ; Check if display sequence index is below array member count, meaning the item index was found

            mov rax, -1  ; return -1 otherwise

        ._end_find_in_display_sequence:

        ; Epilog
        add rsp, 8  ; Restore the stack
        mov r12, [rsp + 8]  ; Restore nonvolatile register
        mov r13, [rsp + 16]  ; Restore nonvolatile register
        mov r14, [rsp + 24]  ; Restore nonvolatile register
        ret            
