default rel  ; Use RIP-relative addressing
bits 64  ; Target 64-bit architecture exclusively


extern GetProcessHeap  ; Returns a handle to the default heap of the process 
extern HeapAlloc  ; Heap memory allocation
extern HeapReAlloc  ; Heap memory reallocation
extern HeapFree  ; Heap memory release

extern GetStdHandle  ; Returns standard console handles
extern ReadConsoleA  ; Reads ANSI characters from standard input
extern WriteConsoleA  ; Writes ANSI characters to standard output

extern ExitProcess  ; Win32 API exit procedure


global mainCRTStartup  ; Entry point for the CONSOLE subsystem


ESC equ 27  ; Escape character
LF equ 10  ; Newline character
NULL equ 0  ; NULL

%define REGULAR_COLOR ESC, "[0m"  ; Resets text color
%define WARNING_COLOR ESC, "[93m"  ; Changes text color to bright yellow
%define ERROR_COLOR ESC, "[38;2;255;145;65m"  ; Changes text color to bright orange
%define FATAL_ERROR_COLOR ESC, "[91m"  ; Changes text color to bright red


%macro call_aligned 1  ; Alligns the stack for procedure calls
    sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
    call %1  ; Call the procedure
    add rsp, 40  ; Restore the stack

%endmacro


; Rodata section
section .rodata
messages:
    .input_too_large: db WARNING_COLOR, "Input is too large and will be clipped.", REGULAR_COLOR, LF, NULL
    .integer_too_large: db WARNING_COLOR, "Entered number is too large and will be clamped.", REGULAR_COLOR, LF, NULL
    .integer_parse_failed: db ERROR_COLOR, "Failed to read a number, try again: ", REGULAR_COLOR, NULL

    .memory_error: db FATAL_ERROR_COLOR,"An error occured while managing heap memory.", REGULAR_COLOR, LF, NULL
    .input_error: db FATAL_ERROR_COLOR,"An error occured while reading input.", REGULAR_COLOR, LF, NULL


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
    jmp exit


; Copies memory from one location to another, args(QWORD destination pointer, QWORD source pointer, QWORD bytes amount)
mem_copy:
    mov rax, 0  ; Set offset to 0

    ._loop:
        cmp rax, r8
        jae ._loop_end  ; Loop until the offset is equal to the amount

        mov bl, [rdx + rax]  ; Moves a byte from source + offset to bl
        mov [rcx + rax], bl  ; Moves a byte from bl to destination + offset

        inc rax  ; Increment the offset
        jmp ._loop

    ._loop_end:

    ret


; Dynamic array functionality
dynamic_array:

    ; Initializes a dynamic array, args(QWORD array struct pointer, DWORD member size)
    .init:
        ; Save arguments
        mov [rsp + 8], rcx  ; Save array struct pointer in shadow space
        mov QWORD [rsp + 16], 0  ; Initialize with 0 for convinient 64-bit multiplication
        mov [rsp + 16], edx  ; Save member size in shadow space
        
        ; Get default heap handle
        call_aligned GetProcessHeap

        ; Check for errors (NULL return)
        cmp rax, 0
        je ._memory_error

        ; Allocate memory
        mov rcx, rax  ; Use the handle as a first argument
        mov rax, 10 ; Initial member slot count
        mul QWORD [rsp + 16]  ; Multiply by member size (affects rdx)
        mov r8, rax  ; Resulting number of bytes to allocate
        mov edx, 0  ; Allocation flags
        call_aligned HeapAlloc  ; Returns a pointer to the allocated memory

        ; Check for errors (NULL return)
        cmp rax, 0
        je ._memory_error

        ; Modify array struct
        mov rcx, [rsp +  8]  ; Retrieve array struct pointer
        mov edx, [rsp + 16]  ; Retrieve member size
        mov [rcx], rax  ; Update allocated memory pointer
        mov DWORD [rcx + 8], 0  ; Update initial member count
        mov DWORD [rcx + 12], 10  ; Update capacity
        mov [rcx + 16], edx  ; Update member size

        ret


    ; Pushes new element, args(QWORD array struct pointer, QWORD new member pointer)
    .push:
        ; Save arguments
        mov [rsp + 8], rcx  ; Save array struct pointer in shadow space
        mov [rsp + 16], rdx  ; Save new member pointer in shadow space

        ; Check capacity
        mov eax, [rcx + 8]  ; Load member count value
        cmp eax, [rcx + 12]  ; Compare against capacity
        jb ._push  ; Skip reallocation if the array is not yet full

            ; Increase capacity
            mov edx, [rcx + 12]  ; Load current array capacity as an argument
            add edx, edx  ; Double it
            call_aligned ._modify_capacity  ; Reallocates memory and updates capacity

        ._push:

        ; Get offset to place a new member
        mov rcx, [rsp + 8]  ; Retrieve array struct pointer
        mov edx, [rcx + 8]  ; Get member count
        call_aligned .get  ; Get pointer to the next available member location

        ; Push new member to the array and increment member count
        mov rbx, [rsp + 8]  ; Retrieve array struct pointer
        mov rcx, rax  ; Set destination argument
        mov rdx, [rsp + 16]  ; Retrieve new member pointer to use as a source argument
        mov r8d, [rbx + 16]  ; Get member size

        mov eax, [rbx + 8]  ; Get member count
        inc eax  ; Increment member count
        mov [rbx + 8], eax  ; Update member count

        call_aligned mem_copy  ; Copy new member to the end of the array

        ret


    ; Returns a pointer to a member by index, args(QWORD array struct pointer, DWORD index)
    .get:
        ; Do pointer arithmetic
        mov eax, edx  ; Get index
        mov ebx, [rcx + 16]  ; Get member size
        mul rbx  ; Get offset
        add rax, [rcx]  ; Add array base pointer to offset

        ret


    ; Removes member by index, shifts everything past by 1, args(QWORD array struct pointer, DWORD index)
    .remove:
        ; Save arguments
        mov [rsp + 8], rcx  ; Save array struct pointer in shadow space
        mov [rsp + 16], edx  ; Save element index in shadow space

        ; Get pointer to the member to be removed
        call_aligned .get     

        ; Set up destination argument
        mov rbx, [rsp + 8]  ; Retrieve array struct pointer
        mov r9d, [rbx + 16]  ; Get member size
        mov rcx, rax  ; Set destingation pointer

        ; Calculate memory block size to be shifted
        mov eax, [rbx + 8]  ; Get member count
        mov r8d, [rsp + 16]  ; Retrieve element index
        add r8d, 1  ; Get next element index
        sub eax, r8d  ; Get the number of members to be shifted
        mul r9  ; Get the size of memory chunk to be shifted
        mov r8, rax  ; Use the size as argument

        ; Calculate a pointer to the next member
        mov rdx, rcx  ; Set source pointer
        add rdx, r9  ; Offset source pointer by 1 member

        ; Shift elements
        call_aligned mem_copy

        ; Decrement member count
        mov rbx, [rsp + 8]  ; Retrieve array struct pointer
        mov eax, [rbx + 8]  ; Get member count
        dec eax
        mov [rbx + 8], eax  ; Update member count

        ; Check if the capacity of the array needs to be decreased
        mov eax, [rbx + 12]  ; Get current capacity
        mov rdx, 0  ; Set rdx to 0 for division
        mov ecx, 4  ; Set the divisor
        div rcx  ; Divide current capacity by 4

        ; Compare against member count
        cmp eax, [rbx + 8] 
        jbe ._end_remove  ; Skip reallocation if new capacity is less than or equal to member count

        ; Compare new capacity against min capacity
        cmp eax, 10
        jb ._end_remove  ; Skip reallocation if new capacity is less than min capacity

            ; Decrease capacity
            mov rcx, rbx  ; Array struct pointer argument
            mov edx, eax  ; New capacity
            call_aligned ._modify_capacity  ; Reallocates memory and updates capacity

        ._end_remove:

        ret


    ; Clears the array, args(QWORD array struct pointer)
    .clear:
        ; Reset member count
        mov DWORD [rcx + 8], 0

        ; Check cucrent capacity
        mov ebx, [rcx + 12]  ; Load capacity
        cmp ebx, 10  ; Compare against min capacity
        jbe ._end_clear  ; Skip reallocation if capacity is minimal

            ; Set min capacity
            mov edx, 10  ; set min capacity as an argument
            call_aligned ._modify_capacity  ; Reallocates memory and updates capacity

        ._end_clear:

         ret


    ; Deallocates the array, args(QWORD array struct pointer)
    .free: 
        ; Save arguments
        mov [rsp + 8], rcx  ; Save array struct pointer in shadow space
 
        ; Get default heap handle
        call_aligned GetProcessHeap

        ; Check for errors (NULL return)
        cmp rax, 0
        je ._memory_error

        ; Free memory
        mov rbx, [rsp + 8]  ; Retrieve array struct pointer 
        mov rcx, rax  ; Use the handle as a first argument
        mov edx, 0  ; Allocation flags
        mov r8, [rbx]  ; Address of the memory chunk to be released
        call_aligned HeapFree  ; Releases memory

        ; Check for errors (NULL return)
        cmp rax, 0
        je ._memory_error

        ret


    ; Modify capacity and reallocate memory, args(QWORD array struct pointer, DWORD new capacity)
    ._modify_capacity:
        ; Save arguments
        mov [rsp + 8], rcx  ; Save array struct pointer in shadow space
        mov [rsp + 16], edx  ; Save new capacity in shadow space        

        ; Get default heap handle
        call_aligned GetProcessHeap

        ; Check for errors (NULL return)
        cmp rax, 0
        je ._memory_error

        ; Reallocate memory
        mov rbx, [rsp + 8]  ; Retrieve array struct pointer
        mov rcx, rax  ; Use the handle as a first argument
        mov edx, [rbx + 16]  ; Get member size
        mov eax, [rsp + 16]  ; Retrieve new capacity
        mul rdx  ; Multiply by member size (affects rdx)
        mov r9, rax  ; Resulting number of bytes to reallocate
        mov edx, 0  ; Reallocation flags
        mov r8, [rbx]  ; Address of the memory chunk to be reallocated
        call_aligned HeapReAlloc  ; Returns a pointer to the allocated memory

        ; Check for errors (NULL return)
        cmp rax, 0
        je ._memory_error

        ; Modify array struct
        mov rcx, [rsp +  8]  ; Retrieve array struct pointer
        mov edx, [rsp + 16]  ; Retrieve new capacity
        mov [rcx], rax  ; Update allocated memory pointer
        mov [rcx + 12], edx  ; Update capacity

        ret


    ._memory_error:
        lea rcx, [messages.memory_error]  ; Notify the user that an error occured while managing heap memory
        call_aligned console.print_string  ; Print error message

        jmp exit


; Console IO functionality
console:

    ; Prints a space-padded integer, args(DWORD unsigned integer)
    .print_int:
        sub rsp, 32  ; Reserve space for a temporary buffer

        mov eax, ecx  ; Move argument to the divident register
        mov ecx, 10  ; Use ecx register as a divisor

        lea rbx, [rsp + 15]  ; Initialize character pointer to the least significant digit position
        mov DWORD [rsp + 16], 0x54545454  ;Fill padding with whitespaces
        mov DWORD [rsp + 20], 0x54545454
        mov BYTE  [rsp + 24], 0x54

        ._convert_digits_loop:
            mov edx, 0  ; Reset edx for division
            div ecx  ; Divide remaining number by ten
            add dl, 48  ; Convert the remainder to ASCII digit
            mov [rbx], dl  ; Write it to the buffer
            dec rbx  ; Decrement the character pointer

            cmp eax, 0
            jne ._convert_digits_loop  ; Break if all digits have been processed

        inc rbx  ; Correct the resulting string pointer after itteration   
        mov [rsp + 8 + 32], rbx  ; Save string pointer in shadow space 

        ; Get output handle
        mov ecx, -11  ; Set to -11 to receive an output handle
        call_aligned GetStdHandle  ; Returns standard output handle

        ; Write to standard output
        mov rcx, rax  ; Set output handle
        mov rdx, [rsp + 8 + 32]  ; Retrieve string pointer
        mov r8d, 10  ; Print 10 characters
        lea r9, [rsp + 16 + 32]  ; The procedure will save the number of characters it will have written in shadow space
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        mov QWORD [rsp], 0  ; Reserved NULL parameter
        call WriteConsoleA  ; Writes to the console
        add rsp, 40  ; Restore the stack

        ; Check for errors (zero return)
        cmp eax, 0
        je ._output_error

        add rsp, 32  ; Restore the stack
        ret

    ; Prints a NULL-terminated string, args(QWORD string pointer)
    .print_string:
        ; Save arguments
        mov [rsp + 8], rcx  ; Save string pointer in shadow space

        ; Initialize current character pointer
        mov rdx, rcx

        ; Search for the terminator character
        ._print_find_terminator_loop:
            cmp BYTE [rdx], 0
            je ._end_print_find_terminator_loop  ; Break if current character is a NULL terminator         
            inc rdx  ; Increment character pointer
            jmp ._print_find_terminator_loop  ; Continue itteration

        ._end_print_find_terminator_loop:

        ; Calculate string length
        sub rdx, rcx
        mov [rsp + 16], rdx  ; Save string length in shadow space

        ; Get output handle
        mov ecx, -11  ; Set to -11 to receive an output handle
        call_aligned GetStdHandle  ; Returns standard output handle

        ; Write to standard output
        mov rcx, rax  ; Set output handle
        mov rdx, [rsp + 8]  ; Retrieve string pointer
        mov r8d, [rsp + 16]  ; Retrieve string length
        lea r9, [rsp + 24]  ; The procedure will save the number of characters it will have written in shadow space
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        mov QWORD [rsp], 0  ; Reserved NULL parameter
        call WriteConsoleA  ; Writes to the console
        add rsp, 40  ; Restore the stack

        ; Check for errors (zero return)
        cmp eax, 0
        je ._output_error

        ret


    ;Uses the read_string procedure and then parses and returns a 32-bit integer
    ;Displays a warning message in case input is larger than max unsigned 32-bit integer and returns max int instead
    ;Displays a warning message in case input cant be parsed and prompts user again
    .read_int:
        ; Read formatted input string
        sub rsp, 64  ; Reserve space for a temporary buffer
        lea rcx, [rsp]  ; Set destination buffer
        call_aligned .read_string  ; Read formatted input

        ; Parse an integer
        mov eax, 0  ; Initialize return value
        lea rbx, [rsp]  ; Initialize character pointer

        ; Itterate through characters
        ._parse_digits_loop:
            
            ;Check if current character is a digit, stop itteration if it isn't
            cmp BYTE [rbx], 48
            jb ._end_parse_digits_loop

            cmp BYTE [rbx], 57
            ja ._end_parse_digits_loop

            mov ecx, 10
            mul ecx  ; 'Shift' previous digits right by 1

            mov ecx, 0       
            mov cl, [rbx]  ; Load current character
            sub cl, 48  ; Substract ASCII digit offset
            inc rbx  ; Increment character pointer

            add eax, ecx  ; Add current digit
            jc ._int_overflow  ; Check for addition overflow 
            
            cmp edx, 0
            je ._parse_digits_loop  ; Check for multiplication overflow

            ._int_overflow:
                ; Display a warning if an overflow has occured
                lea rcx, [messages.integer_too_large]
                call_aligned .print_string

                mov eax, -1
                jmp ._end_read_int  ; Load max int as a return value and end the procedure 
   
        ._end_parse_digits_loop:

        ; Verify if at least one digit was parsed, display a warning message and prompt user again otherwise
        cmp rbx, rsp
        jne ._end_read_int

            ; Display a warning otherwise
            lea rcx, [messages.integer_parse_failed]
            call_aligned .print_string
            
            ;Prompt user again
            add rsp, 64  ; Restore the stack
            jmp .read_int

        ._end_read_int:
        
        add rsp, 64  ; Restore the stack
        ret


    ;Same as console_read_raw, except it removes unwanted characters, replaces tabs with whitespaces, trims the string
    ;Displays a warning message in case input exceeds max length
    .read_string:
        ; Save arguments
        mov [rsp + 8], rcx  ; Save destination buffer pointer in shadow space

        ; Read raw input string
        call_aligned ._read_raw
        mov [rsp + 16], rax  ; Save ._read_raw return value

        ; Format the string
        mov rcx, [rsp + 8]  ; Retrieve the buffer pointer
        call_aligned string.format  ; Formats the string

        ; Trim the string
        mov rcx, [rsp + 8]  ; Retrieve the buffer pointer
        call_aligned string.trim  ; Trims the string

        cmp QWORD [rsp + 16], 0  ; Check if input size was larger than max supported input length
        jne ._end_read_string  ; Skip warning if it wasn't

            lea rcx, [messages.input_too_large]  ; Notify the user that input string will be trimmed
            call_aligned .print_string  ; Print warning message

        ._end_read_string:

        ret


    ;Reads up to 63 ANSI characters from console input without formatting, null-terminates the resulting string, 
    ;Flushes the input buffer, Returns 0 if input string length exceeds 63 characters, args(QWORD destination 64-byte buffer pointer)
    ._read_raw:
        ; Save arguments
        mov [rsp + 8], rcx  ; Save destination buffer pointer in shadow space

        ; Get input handle
        mov ecx, -10  ; Set to -10 to receive an input handle
        call_aligned GetStdHandle  ; Returns standard input handle
        mov [rsp + 24], rax  ; Save input handle in shadow space

        ; Read from standard input
        sub rsp, 80  ; Reserve space for a temporary buffer
        mov rcx, rax  ; Set input handle
        lea rdx, [rsp]  ; Set destination buffer
        mov r8d, 66  ; Read 63 characters + CR + LF + another character to see if input is greater tan 63 characters
        lea r9, [rsp + 16 + 80]  ; The procedure will save the number of characters it will have read in shadow space
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        mov QWORD [rsp], 0  ; Input control argument should be NULL for ANSI mode
        call ReadConsoleA  ; Reads input
        add rsp, 40  ; Restore the stack

        ; Check for errors (zero return)
        cmp eax, 0
        je ._input_error

        ; NULL-terminate the string
        mov ecx, [rsp + 16 + 80]  ; Retrieve the number of characters read
        sub rcx, 2  ; Get the offset to CR character
        mov rdx, rcx
        shr rdx, 6  ; If input string length was more than 63 characters,
        sub rcx, rdx  ; Substract one to get proper offset
        add rcx, rsp  ; Add the base address of the temporary buffer
        mov BYTE [rcx], 0 ; Set the CR character to NULL

        ; Copy the string to the destination
        mov rcx, [rsp + 8 + 80]  ; Retrieve the destination buffer pointer
        lea rdx, [rsp]  ; Set the source string pointer      
        call_aligned string.copy  ; Copy the string to the destination

        ; Check if input string length did not exceed 63 characters
        mov ecx, [rsp + 16 + 80]  ; Retrieve the number of characters read
        cmp ecx, 65  ; Compare against max length + CR + LF
        jbe ._end_read_raw  ; Return if string length did not exceed max length

            ; Flushing remaining input characters
            ._flush_buffer:
                ; Check if there might be more unread characters
                mov cl, [rsp + 65] ; Load the last character from the discard buffer
                cmp cl, LF
                je ._end_flush_buffer  ; Stop flushing if the last character read is a newline character
                mov ecx, [rsp + 16 + 80]  ; Load the number of characters the ReadConsole procedure has previously read
                cmp ecx, 66  ; Compare against discard buffer size
                jb ._end_flush_buffer  ; Stop flushing if the procedure has read less than 64 characters

                ; Read remaining characters from standard input
                mov rcx, [rsp + 24 + 80]  ; Retrieve standard input handle
                lea rdx, [rsp]  ; Specify the discard buffer
                mov r8d, 66  ; Read 66 characters
                lea r9, [rsp + 16 + 80]  ; The procedure will save the number of characters it will have read in shadow space
                sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
                mov QWORD [rsp], 0  ; Input control argument should be NULL for ANSI mode
                call ReadConsoleA  ; Reads and flushes 64 characters
                add rsp, 40  ; Restore the stack

                ; Check for errors (zero return)
                cmp eax, 0
                je ._input_error

                jmp ._flush_buffer  ; Continue flushing

            ._end_flush_buffer:

            add rsp, 80  ; Restore the stack
            mov rax, 0  ; Return zero if string length has exceeded max length
            ret

        ._end_read_raw:
            add rsp, 80  ; Restore the stack
            mov rax, 1  ; Return non-zero value if the whole input was read
            ret


    ._input_error:
        lea rcx, [messages.input_error]  ; Notify the user that an error occured while reading input
        call_aligned .print_string  ; Print error message

        jmp exit


    ._output_error:
        jmp exit


; String manipulation
string:

    ; Copies a NULL-terminated string, args(QWORD destination pointer, QWORD source string pointer)
    .copy:
        mov rax, 0  ; Set offset to 0

        ._copy_loop:
            mov bl, [rdx + rax]  ; Moves a char from source + offset to bl
            mov [rcx + rax], bl  ; Moves a char from bl to destination + offset

            inc rax  ; Increment the offset
            cmp bl, 0
            jne ._copy_loop  ; Loop until the NULL character is reached and copied

        ret


    ; Removes unwanted characters, replaces tabs with whitespaces, args(QWORD NULL-terminated string pointer)    
    .format:
        mov rbx, rcx  ; Initialize character shift location to string pointer

        ; Itterate through all characters
        ._format_loop:
            mov al, [rcx]  ; Get current character

            cmp al, 9  ; Check if current character is a tab character
            je ._tab_character

            cmp al, 0  ; Check if current character is a NULL terminator
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
        ; Save arguments
        mov [rsp + 8], rcx  ; Save string pointer in shadow space

        mov rdx, rcx  ; Set up offset pointer

        ; Search for the first non-whitespace character
        ._find_leading_loop:
            cmp BYTE [rdx], ' '
            jne ._end_find_leading_loop  ; Break if current character is not a whitespace character
            inc rdx  ; Increment offset pointer
            jmp ._find_leading_loop  ; Continue itteration

        ._end_find_leading_loop:

        cmp rdx, rcx  ; Skip shifting if there are no leading whitespace characters
        je ._find_terminator

            ; Shift the string to remove leading spaces
            call_aligned .copy  ; Copy the string without leading spaces 
            mov rcx, [rsp + 8]  ; Retrieve string pointer

        ._find_terminator:
        mov rdx, rcx  ; Set up current character pointer
        
        ; Search for the terminator character
        ._find_terminator_loop:
            cmp BYTE [rdx], 0
            je ._end_find_terminator_loop  ; Break if current character is a NULL terminator         
            inc rdx  ; Increment character pointer
            jmp ._find_terminator_loop  ; Continue itteration

        ._end_find_terminator_loop:

        dec rdx  ; Get the last non-NULL character

        ; Remove trailing whitespaces
        ._remove_trailing_loop:
            cmp rdx, rcx
            jb ._end_remove_trailing_loop  ; Break if current character pointer is below the string pointer

            cmp BYTE [rdx], ' '
            jne ._end_remove_trailing_loop  ; Break if current character is not a whitespace

            mov BYTE [rdx], 0  ; Replace current character with NULL otherwise
            dec rdx  ; Decrement current character pointer
            jmp ._remove_trailing_loop  ; Continue itteration

        ._end_remove_trailing_loop:

        ret


exit:
    mov  ecx, 0  ; Load exit status
    call_aligned ExitProcess
    hlt
