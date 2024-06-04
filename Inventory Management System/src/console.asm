%ifndef CONSOLE_ASM
%define CONSOLE_ASM

%include "src/common.asm"
%include "src/string.asm"

; Externals
extern GetStdHandle  ; Returns standard console handles
extern SetConsoleMode  ; Sets the console mode
extern ReadConsoleA  ; Reads ANSI characters from standard input
extern WriteConsoleA  ; Writes ANSI characters to standard output


; Rodata section
section .rodata
console_messages:
    .input_too_large: db WARNING_COLOR, "Input is too large and will be clipped.", DEFAULT_COLOR, LF, NULL
    .integer_too_large: db WARNING_COLOR, "Entered number is too large and will be clamped.", DEFAULT_COLOR, LF, NULL
    .integer_parse_failed: db ERROR_COLOR, "Failed to read a number, try again: ", DEFAULT_COLOR, NULL
    .input_error: db FATAL_ERROR_COLOR,"An error occured while reading input.", DEFAULT_COLOR, LF, NULL

console_control:
    .set_window_name_begin: db ESC, "]0;", NULL  ; Starts changing the window title
    .set_window_name_end: db ESC, 0x5C , NULL ; Ends changing the window title
    .clear_screen: db ESC, "[1;1H",  ESC, "[2J", ESC, "[3J", NULL  ; Resets cursor position and clears the screen
    .apply_input_color: db INPUT_COLOR, NULL
    .restore_text_color: db DEFAULT_COLOR, NULL 
    .highlight_background: db HIGHLIGHT_BG_COLOR, NULL


; Data section
sectalign 4
section .data

    alignb 4
    preserved_env.saved: dd 0  ; Bool, indicates if the environment was previously saved to restore with the abort command


; Bss section
sectalign 8
section .bss

alignb 8
preserved_env:
    .r12_register: resq 1
    .r13_register: resq 1
    .r14_register: resq 1
    .r15_register: resq 1
    .rdi_register: resq 1 
    .rsi_register: resq 1
    .rbx_register: resq 1
    .rbp_register: resq 1
    .rsp_register: resq 1

    .return_address: resq 1

console_abort_command: resq 1  ; Pointer to the command string used to abort the current action

console_input_handle: resq 1  ; Handles for standard IO
console_output_handle: resq 1


; Text section
section .text

; Console IO functionality
console:

    ; Change window name, apply default text colors, and register abort command, 
    ; Args (QWORD window name string pointer, QWORD abort command string pointer)
    .init:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], rcx  ; Save string pointer in shadow space

        mov [console_abort_command], rdx  ; Save abort command

        ; Get standard input handle
        mov ecx, -10  ; Set to -10 to receive an input handle
        fast_call GetStdHandle  ; Returns standard input handle
        mov [console_input_handle], rax  ; Save input handle for future use

        ; Get standard output handle
        mov ecx, -11  ; Set to -11 to receive an output handle
        fast_call GetStdHandle  ; Returns standard output handle
        mov [console_output_handle], rax  ; Save output handle for future use

        mov rcx, rax  ; Set output handle
        mov edx, 1 | 4  ; Enable processed output and virtual terminal processing
        fast_call SetConsoleMode

        ; Check for errors (NULL return)
        cmp eax, NULL
        je ._output_error

        lea rcx, [console_control.restore_text_color]
        fast_call .print_string  ; Apply default text color

        lea rcx, [console_control.set_window_name_begin]
        fast_call .print_string  ; Start changing the window title

        mov rcx, [rsp + 16]  ; Retrieve string pointer
        fast_call .print_string  ; Change Window Title

        lea rcx, [console_control.set_window_name_end]
        fast_call .print_string  ; End changing the window title 

        add rsp, 8  ; Restore the stack
        ret


    ; Captures current environment and saves an address to jump to in case user aborts current action by a designated command,
    ; Args(QWORD return address)
    .capture_env_for_abort:
        ; Save nonvolatile registers
        mov [preserved_env.r12_register], r12
        mov [preserved_env.r13_register], r13
        mov [preserved_env.r14_register], r14
        mov [preserved_env.r15_register], r15
        mov [preserved_env.rdi_register], rdi
        mov [preserved_env.rsi_register], rsi
        mov [preserved_env.rbx_register], rbx
        mov [preserved_env.rbp_register], rbp
        mov [preserved_env.rsp_register], rsp
        sub QWORD [preserved_env.rsp_register],  40  ; Compensate for rsp changing after this function was called

        mov [preserved_env.return_address], rcx  ; Save the return address

        mov DWORD [preserved_env.saved], 1  ; Allow to use the abort command
        ret


    ; Restores saved environment
    ._restore_env:
        ; Restore nonvolatile registers
        mov r12, [preserved_env.r12_register]
        mov r13, [preserved_env.r13_register]
        mov r14, [preserved_env.r14_register]
        mov r15, [preserved_env.r15_register]
        mov rdi, [preserved_env.rdi_register]
        mov rsi, [preserved_env.rsi_register]
        mov rbx, [preserved_env.rbx_register]
        mov rbp, [preserved_env.rbp_register]
        mov rsp, [preserved_env.rsp_register]

        jmp [preserved_env.return_address]  ; Jump to the saved address
 

    ; Prints a space-padded integer, args(DWORD unsigned integer)
    .print_int:
        ; Prolog
        sub rsp, 32 + 8  ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary

        mov eax, ecx  ; Move argument to the divident register
        mov ecx, 10  ; Use ecx register as a divisor

        lea r10, [rsp + 15]  ; Initialize character pointer to the least significant digit position
        mov DWORD [rsp + 16], 0x20202020  ;Fill padding with whitespaces
        mov DWORD [rsp + 20], 0x20202020
        mov BYTE  [rsp + 24], 0x20

        ._convert_digits_loop:
            mov edx, 0  ; Reset edx for division
            div ecx  ; Divide remaining number by ten
            add dl, 48  ; Convert the remainder to ASCII digit
            mov [r10], dl  ; Write it to the buffer
            dec r10  ; Decrement the character pointer

            cmp eax, 0
            jne ._convert_digits_loop  ; Break if all digits have been processed

        inc r10  ; Correct the resulting string pointer after itteration   

        ; Write to standard output
        mov rcx, [console_output_handle]  ; Set output handle
        mov rdx, r10  ; Use calculated string pointer
        mov r8d, 10  ; Print 10 characters
        lea r9, [rsp + 24 + 32]  ; The procedure will save the number of characters it will have written in shadow space
        sub rsp, 48  ; Reserve shadow space for 5 parameters and preserve stack alignment
        mov QWORD [rsp + 32], NULL  ; Reserved NULL parameter
        call WriteConsoleA  ; Writes to the console
        add rsp, 48  ; Restore the stack

        ; Check for errors (NULL return)
        cmp eax, NULL
        je ._output_error

        add rsp, 32 + 8  ; Restore the stack
        ret


    ; Prints a NULL-terminated string, args(QWORD string pointer)
    .print_string:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], rcx  ; Save string pointer in shadow space

        ; Calculate string length
        fast_call string.len

        ; Write to standard output
        mov rcx, [console_output_handle]  ; Set output handle
        mov rdx, [rsp + 16]  ; Retrieve string pointer
        mov r8d, eax  ; String length previously calculated
        lea r9, [rsp + 32]  ; The procedure will save the number of characters it will have written in shadow space
        sub rsp, 48  ; Reserve shadow space for 5 parameters and preserve stack alignment
        mov QWORD [rsp + 32], NULL  ; Reserved NULL parameter
        call WriteConsoleA  ; Writes to the console
        add rsp, 48  ; Restore the stack

        ; Check for errors (NULL return)
        cmp eax, NULL
        je ._output_error

        add rsp, 8  ; Restore the stack
        ret


    ;Uses the read_string procedure and then parses and returns a 32-bit integer
    ;Displays a warning message in case input is larger than max unsigned 32-bit integer and returns max int instead
    ;Displays a warning message in case input cant be parsed and prompts the user again
    .read_int:
        ; Read formatted input string
        sub rsp, 64 + 8  ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary
        lea rcx, [rsp]  ; Set destination buffer
        fast_call .read_string  ; Read formatted input

        ; Parse an integer
        mov eax, 0  ; Initialize return value
        lea r10, [rsp]  ; Initialize character pointer

        ; Itterate through characters
        ._parse_digits_loop:
            
            ;Check if current character is a digit, stop itteration if it isn't
            cmp BYTE [r10], 48
            jb ._end_parse_digits_loop

            cmp BYTE [r10], 57
            ja ._end_parse_digits_loop

            mov ecx, 10
            mul ecx  ; 'Shift' previous digits right by 1

            mov ecx, 0       
            mov cl, [r10]  ; Load current character
            sub cl, 48  ; Substract ASCII digit offset
            inc r10  ; Increment character pointer

            add eax, ecx  ; Add current digit
            jc ._int_overflow  ; Check for addition overflow 
            
            cmp edx, 0
            je ._parse_digits_loop  ; Check for multiplication overflow

            ._int_overflow:
                ; Display a warning if an overflow has occured
                lea rcx, [console_messages.integer_too_large]
                fast_call .print_string

                mov ecx, 1000
                fast_call Sleep  ; Sleep for 1000 milliseconds to prevent the warning message from immediately flushing in certain scenarios

                mov eax, -1
                jmp ._end_read_int  ; Load max int as a return value and end the procedure 
   
        ._end_parse_digits_loop:

        ; Verify if at least one digit was parsed, display a warning message and prompt the user again otherwise
        cmp r10, rsp
        jne ._end_read_int

            ; Display a warning otherwise
            lea rcx, [console_messages.integer_parse_failed]
            fast_call .print_string
            
            ;Prompt the user again
            add rsp, 64 + 8 ; Restore the stack
            jmp .read_int

        ._end_read_int:
        
        add rsp, 64 + 8  ; Restore the stack
        ret


    ;Same as console_read_raw, except it removes unwanted characters, replaces tabs with whitespaces, trims the string
    ;Displays a warning message in case input exceeds max length
    .read_string:
        ; Prolog
        sub rsp, 64 + 8  ; Reserve space for a temporary buffer and align the stack to a 16-byte boundary
        mov [rsp + 16 + 64], rcx  ; Save destination buffer pointer in shadow space

        ; Read raw input string
        fast_call ._read_raw
        mov [rsp + 24 + 64], rax  ; Save ._read_raw return value

        ; Format the string
        mov rcx, [rsp + 16 + 64]  ; Retrieve the buffer pointer
        fast_call string.format  ; Formats the string

        ; Trim the string
        mov rcx, [rsp + 16 + 64]  ; Retrieve the buffer pointer
        fast_call string.trim  ; Trims the string

        cmp QWORD [rsp + 24 + 64], 0  ; Check if input size was larger than max supported input length
        jne ._check_for_abort_command  ; Skip warning if it wasn't

            lea rcx, [console_messages.input_too_large]  ; Notify the user that input string will be trimmed
            fast_call .print_string  ; Print warning message

            mov ecx, 1000
            fast_call Sleep  ; Sleep for 1000 milliseconds to prevent the warning message from immediately flushing in certain scenarios

        ._check_for_abort_command:

        lea rcx, [rsp]
        mov rdx, [rsp + 16 + 64]  ; Retrieve the buffer pointer
        fast_call string.copy  ; Copy resulting string to the temporary buffer

        ; Lowercase the temporary string
        lea rcx, [rsp]
        fast_call string.lower

        ; Compare input to the abort command
        lea rcx, [rsp]
        mov rdx, [console_abort_command]
        fast_call string.compare

        cmp DWORD [preserved_env.saved], 1
        jne ._end_read_string  ; Check if the environment to return to was previously saved 
        
        cmp eax, 1
        jne ._end_read_string  ; Check if user entered the abort command

            fast_call ._restore_env  ; restore the environment in case the user entered the abort command
        
        ._end_read_string:

        add rsp, 64 + 8  ; Restore the stack
        ret


    ;Reads up to 63 ANSI characters from console input without formatting, null-terminates the resulting string, 
    ;Flushes the input buffer, Returns 0 if input string length exceeds 63 characters, args(QWORD destination 64-byte buffer pointer)
    ._read_raw:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], rcx  ; Save destination buffer pointer in shadow space

        ; Apply input color
        lea rcx, [console_control.apply_input_color]
        fast_call .print_string

        ; Read from standard input
        sub rsp, 80  ; Reserve space for a temporary buffer
        mov rcx, [console_input_handle]  ; Set input handle
        lea rdx, [rsp]  ; Set temporary destination buffer
        mov r8d, 66  ; Read 63 characters + CR + LF + another character to see if input is greater tan 63 characters
        lea r9, [rsp + 24 + 80]  ; The procedure will save the number of characters it will have read in shadow space
        sub rsp, 48  ; Reserve shadow space for 5 parameters and preserve stack alignment
        mov QWORD [rsp + 32], NULL  ; Input control argument should be NULL for ANSI mode
        call ReadConsoleA  ; Reads input
        add rsp, 48  ; Restore the stack

        ; Check for errors (NULL return)
        cmp eax, NULL
        je ._input_error

        ; Restore text color
        lea rcx, [console_control.restore_text_color]
        fast_call .print_string

        ; NULL-terminate the string
        mov ecx, [rsp + 24 + 80]  ; Retrieve the number of characters read
        sub rcx, 2  ; Get the offset to CR character
        mov rdx, rcx
        shr rdx, 6  ; If input string length was more than 63 characters,
        sub rcx, rdx  ; Substract one to get proper offset
        add rcx, rsp  ; Add the base address of the temporary buffer
        mov BYTE [rcx], NULL ; Set the CR character to NULL

        ; Copy the string to the destination
        mov rcx, [rsp + 16 + 80]  ; Retrieve the destination buffer pointer
        lea rdx, [rsp]  ; Set the source string pointer      
        fast_call string.copy  ; Copy the string to the destination

        ; Check if input string length did not exceed 63 characters
        mov ecx, [rsp + 24 + 80]  ; Retrieve the number of characters read
        cmp ecx, 65  ; Compare against max length + CR + LF
        jbe ._end_read_raw  ; Return if string length did not exceed max length

            ; Flushing remaining input characters
            ._flush_buffer:
                ; Check if there might be more unread characters
                mov cl, [rsp + 65] ; Load the last character from the discard buffer
                cmp cl, LF
                je ._end_flush_buffer  ; Stop flushing if the last character read is a newline character
                mov ecx, [rsp + 24 + 80]  ; Load the number of characters the ReadConsole procedure has previously read
                cmp ecx, 66  ; Compare against discard buffer size
                jb ._end_flush_buffer  ; Stop flushing if the procedure has read less than 64 characters

                ; Read remaining characters from standard input
                mov rcx, [console_input_handle]  ; Retrieve standard input handle
                lea rdx, [rsp]  ; Specify the discard buffer
                mov r8d, 66  ; Read 66 characters
                lea r9, [rsp + 24 + 80]  ; The procedure will save the number of characters it will have read in shadow space
                sub rsp, 48  ; Reserve shadow space for 5 parameters and preserve stack alignment
                mov QWORD [rsp + 32], NULL  ; Input control argument should be NULL for ANSI mode
                call ReadConsoleA  ; Reads and flushes 64 characters
                add rsp, 48  ; Restore the stack

                ; Check for errors (NULL return)
                cmp eax, NULL
                je ._input_error

                jmp ._flush_buffer  ; Continue flushing

            ._end_flush_buffer:

            add rsp, 80 + 8  ; Restore the stack
            mov rax, 0  ; Return zero if string length has exceeded max length
            ret

        ._end_read_raw:
            add rsp, 80 + 8  ; Restore the stack
            mov rax, 1  ; Return non-zero value if the whole input was read
            ret


    ; Jump here when input error is encountered
    ._input_error:
        lea rcx, [console_messages.input_error]  ; Notify the user that an error occured while reading input
        fast_call .print_string  ; Print error message

        mov ecx, 2000
        fast_call Sleep  ; Sleep for 2000 milliseconds to display the error message before halting

        jmp exit


    ; Jump here when output error is encountered
    ._output_error:
        jmp exit


%endif
