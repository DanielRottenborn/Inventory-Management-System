%ifndef STRING_ASM
%define STRING_ASM

%include "src/common.asm"

; Text section
section .text

; String manipulation
string:

    ; Copies a NULL-terminated string, args(QWORD destination pointer, QWORD source string pointer)
    .copy:
        mov rax, 0  ; Set offset to 0

        ._copy_loop:
            mov bl, [rdx + rax]  ; Moves a char from source + offset to bl
            mov [rcx + rax], bl  ; Moves a char from bl to destination + offset

            inc rax  ; Increment the offset
            cmp bl, NULL
            jne ._copy_loop  ; Loop until the NULL character is reached and copied

        ret


    ; Returns string length, args(QWORD NULL-terminated string pointer)
    .len:
        mov rax, 0  ; Initialize current character pointer to 0

        ; Search for NULL terminator
        ._find_terminator_loop:
            cmp BYTE [rcx + rax], NULL
            je ._end_find_terminator_loop  ; Break if current character is a NULL terminator         
            inc rax  ; Increment character pointer
            jmp ._find_terminator_loop  ; Continue itteration

        ._end_find_terminator_loop:

        ret  ; Return current char pointer (string length)


    ; Tests two strings for equality, returns 1 if strings are equal, 0 otherwise, args(QWORD NULL-terminated string pointer, QWORD NULL-terminated string pointer)    
    .compare:
        mov eax, 1  ; Initialize return value to true
        mov rbx, 0  ; Initialize character offset to 0

        ._compare_characters_loop:
            mov r8b, [rcx + rbx]  ; Load characters
            mov r9b, [rdx + rbx] 

            cmp r8b, r9b
            je ._check_terminators  ; Proceed if characters are equal

                mov eax, 0  ; Return false otherwise
                ret

            ._check_terminators:

            ; Check if either of the NULL terminators were reached
            cmp r8b, NULL
            je ._end_compare_characters_loop

            cmp r9b, NULL
            je ._end_compare_characters_loop

            inc rbx  ; Increment character pointer
            jmp ._compare_characters_loop  ; Proceed otherwise

        ._end_compare_characters_loop:

        ret


    ; Converts all uppercase letters into lowercase, args(QWORD NULL-terminated string pointer) 
    .lower:
        ; Itterate through all characters
        ._lower_loop:
            mov al, [rcx]  ; Get current character

            cmp al, NULL  ; Check if current character is a NULL terminator
            je ._end_lower_loop

            cmp al, 65  ; Check if current character is not an uppercase letter
            jb ._lower_continue

            cmp al, 90 ; Check if current character is not an uppercase letter
            ja ._lower_continue
                
                add al, 32  ; Convert current character to a lowercase equivalent
                mov BYTE [rcx], al  ; Update the string

            ._lower_continue:

            inc rcx  ; Increment character pointer
            jmp ._lower_loop  ; Continue itteration

        ._end_lower_loop:

        ret
        

    ; Removes unwanted characters, replaces tabs with whitespaces, args(QWORD NULL-terminated string pointer)    
    .format:
        mov rbx, rcx  ; Initialize character shift location to string pointer

        ; Itterate through all characters
        ._format_loop:
            mov al, [rcx]  ; Get current character

            cmp al, 9  ; Check if current character is a tab character
            je ._tab_character

            cmp al, NULL  ; Check if current character is a NULL terminator
            je ._NULL_terminator

            cmp al, 16  ; Check if current character is otherwise invalid
            jbe ._invalid_character

            cmp al, 127  ; Check if current character is invalid
            jae ._invalid_character

                ;Shift a valid character otherwise
                mov [rbx], al  ; Place current character into current shift location
                inc rcx  ; Increment character pointer
                inc rbx  ; Increment shift location
                jmp ._format_loop  ; Continue itteration

            ._invalid_character:
                inc rcx  ; Only increment character pointer to replace the current character in next itteration
                jmp ._format_loop  ; Continue itteration

            ._tab_character:
                mov BYTE [rbx], ' '  ; Place a whitespace character into current shift location
                inc rcx  ; Increment character pointer
                inc rbx  ; Increment shift location
                jmp ._format_loop  ; Continue itteration

            ._NULL_terminator:
                mov [rbx], al  ; Place character into current shift location
                ; fallthrough to return
        ret


    ; Removes leading and trailing whitespaces, args(QWORD NULL-terminated string pointer) 
    .trim:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], rcx  ; Save string pointer in shadow space

        mov rdx, rcx  ; Set up offset pointer

        ; Search for the first non-whitespace character
        ._find_leading_loop:
            cmp BYTE [rdx], ' '
            jne ._end_find_leading_loop  ; Break if current character is not a whitespace character
            inc rdx  ; Increment offset pointer
            jmp ._find_leading_loop  ; Continue itteration

        ._end_find_leading_loop:

        cmp rdx, rcx  ; Skip shifting if there are no leading whitespace characters
        je ._find_last_character

            ; Shift the string to remove leading spaces
            fast_call .copy  ; Copy the string without leading spaces 
            mov rcx, [rsp + 16]  ; Retrieve string pointer

        ._find_last_character:

        fast_call string.len  ; Get string length
        add rax, rcx  ; Calculate pointer to the NULL terminator
        dec rax  ; Get the last non-NULL character

        ; Remove trailing whitespaces
        ._remove_trailing_loop:
            cmp rax, rcx
            jb ._end_remove_trailing_loop  ; Break if current character pointer is below the string pointer

            cmp BYTE [rax], ' '
            jne ._end_remove_trailing_loop  ; Break if current character is not a whitespace

            mov BYTE [rax], NULL  ; Replace current character with NULL otherwise
            dec rax  ; Decrement current character pointer
            jmp ._remove_trailing_loop  ; Continue itteration

        ._end_remove_trailing_loop:

        add rsp, 8  ; Restore the stack
        ret


    ; Pads a string with whitespaces up to a length of 63 characters, args(QWORD pointer to a NULL-terminated string in a 64-byte buffer)
    .pad:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], rcx  ; Save string pointer in shadow space

        ; Get pointer to the NULL-terminator
        fast_call .len  ; Get string length
        mov rcx, [rsp + 16]  ; Retrieve string pointer

        ; Fill remaining space with shitespaces
        ._pad_fill_loop:
            mov BYTE [rcx + rax], ' '  ; Replace current character with a whitespace
            inc rax  ; Increment character pointer

            cmp rax, 63
            jb ._pad_fill_loop  ; Continue itteration for all characters in buffer except the last one

        ; NULL-terminate the string
        mov BYTE [rcx + 63], NULL

        add rsp, 8  ; Restore the stack
        ret


    ; Pads a string with whitespaces up to a length of 32 characters, shortens the string if it exceeds 32 characters in length
    ; args(QWORD pointer to a NULL-terminated string in a 64-byte buffer)
    .pad_short:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], rcx  ; Save string pointer in shadow space

        fast_call .len  ; Get string length
        mov rcx, [rsp + 16]  ; Retrieve string pointer

        cmp rax, 32
        ja ._shorten  ; Shorten the string if it exceeds 32 characters in length
        je ._end_pad_short  ; End procedure if the string is exactly 32 characters long, pad with whitespaces otherwise

            ._pad_short_fill_loop:
                mov BYTE [rcx + rax], ' '  ; Replace current character with a whitespace
                inc rax  ; Increment character pointer

                cmp rax, 32
                jb ._pad_short_fill_loop  ; Continue itteration for all characters in buffer except the last one    

            jmp ._end_pad_short  ; End procedure

        ._shorten:
            mov BYTE [rcx + 29], '.'  ; Show that the string was shortened
            mov BYTE [rcx + 30], '.'
            mov BYTE [rcx + 31], '.'

        ._end_pad_short:

        ; NULL-terminate the string
        mov BYTE [rcx + 32], NULL

        add rsp, 8  ; Restore the stack
        ret


%endif
