default rel  ; Use RIP-relative addressing
bits 64  ; Target 64-bit architecture exclusively


extern GetProcessHeap  ; Returns a handle to the default heap of the process 
extern HeapAlloc  ; Heap memory allocation
extern HeapReAlloc  ; Heap memory reallocation
extern HeapFree  ; Heap memory release

extern GetStdHandle  ; Returns standard console handles
extern ReadConsoleA  ; Reads ANSI characters from standard input
extern FlushConsoleInputBuffer  ; Flushes input buffer

extern ExitProcess  ; Win32 API exit procedure


global mainCRTStartup  ; Entry point for the CONSOLE subsystem


; Rodata section
section .rodata


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
        jge ._loop_end  ; Loop until the offset is equal to the amount

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
        
        ; Get the heap handle
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call GetProcessHeap  ; Returns a handle to the default heap of the process
        add rsp, 40  ; Restore the stack

        ; Check for errors (NULL return)
        cmp rax, 0
        je ._memory_error

        ; Allocate memory
        mov rcx, rax  ; Use the handle as a first argument
        mov rax, 10 ; Initial member slot count
        mul QWORD [rsp + 16]  ; Multiply by member size (affects rdx)
        mov r8, rax  ; Resulting number of bytes to allocate
        mov edx, 0  ; Allocation flags
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call HeapAlloc  ; Returns a pointer to the allocated memory
        add rsp, 40  ; Restore the stack

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
        jl ._push  ; Skip reallocation if the array is not yet full

            ; Increase capacity
            mov edx, [rcx + 12]  ; Load current array capacity as an argument
            add edx, edx  ; Double it
            sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
            call ._modify_capacity  ; Reallocates memory and updates capacity
            add rsp, 40  ; Restore the stack

        ._push:

        ; Get offset to place a new member
        mov rcx, [rsp + 8]  ; Retrieve array struct pointer
        mov edx, [rcx + 8]  ; Get member count
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call .get  ; Get pointer to the next available member location
        add rsp, 40  ; Restore the stack

        ; Push new member to the array and increment member count
        mov rbx, [rsp + 8]  ; Retrieve array struct pointer
        mov rcx, rax  ; Set destination argument
        mov rdx, [rsp + 16]  ; Retrieve new member pointer to use as a source argument
        mov r8d, [rbx + 16]  ; Get member size

        mov eax, [rbx + 8]  ; Get member count
        inc eax  ; Increment member count
        mov [rbx + 8], eax  ; Update member count

        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call mem_copy  ; Copy new member to the end of the array
        add rsp, 40  ; Restore the stack

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
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call .get  ; Get pointer
        add rsp, 40  ; Restore the stack        

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
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call mem_copy  ; Shift elements
        add rsp, 40  ; Restore the stack

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
        jle ._end_remove  ; Skip reallocation if new capacity is less than or equal to member count

        ; Compare new capacity against min capacity
        cmp eax, 10
        jl ._end_remove  ; Skip reallocation if new capacity is less than min capacity

            ; Decrease capacity
            mov rcx, rbx  ; Array struct pointer argument
            mov edx, eax  ; New capacity
            sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
            call ._modify_capacity  ; Reallocates memory and updates capacity
            add rsp, 40  ; Restore the stack

        ._end_remove:

        ret


    ; Clears the array, args(QWORD array struct pointer)
    .clear:
        ; Reset member count
        mov DWORD [rcx + 8], 0

        ; Check cucrent capacity
        mov ebx, [rcx + 12]  ; Load capacity
        cmp ebx, 10  ; Compare against min capacity
        jle ._end_clear  ; Skip reallocation if capacity is minimal

            ; Set min capacity
            mov edx, 10  ; set min capacity as an argument
            sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
            call ._modify_capacity  ; Reallocates memory and updates capacity
            add rsp, 40  ; Restore the stack

        ._end_clear:

         ret


    ; Deallocates the array, args(QWORD array struct pointer)
    .free: 
        ; Save arguments
        mov [rsp + 8], rcx  ; Save array struct pointer in shadow space
 
        ; Get the heap handle
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call GetProcessHeap  ; Returns a handle to the default heap of the process
        add rsp, 40  ; Restore the stack

        ; Check for errors (NULL return)
        cmp rax, 0
        je ._memory_error

        ; Free memory
        mov rbx, [rsp + 8]  ; Retrieve array struct pointer 
        mov rcx, rax  ; Use the handle as a first argument
        mov edx, 0  ; Allocation flags
        mov r8, [rbx]  ; Address of the memory chunk to be released
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call HeapFree  ; Releases memory
        add rsp, 40  ; Restore the stack

        ; Check for errors (NULL return)
        cmp rax, 0
        je ._memory_error

        ret


    ; Modify capacity and reallocate memory, args(QWORD array struct pointer, DWORD new capacity)
    ._modify_capacity:
        ; Save arguments
        mov [rsp + 8], rcx  ; Save array struct pointer in shadow space
        mov [rsp + 16], edx  ; Save new capacity in shadow space        

        ; Get the heap handle
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call GetProcessHeap  ; Returns a handle to the default heap of the process
        add rsp, 40  ; Restore the stack

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
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call HeapReAlloc  ; Returns a pointer to the allocated memory
        add rsp, 40  ; Restore the stack

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
        jmp exit


; Console IO functionality
console:

    ;Reads up to 63 ANSI characters from console input without formatting, null-terminates the resulting string, 
    ;Flushes the input buffer, Returns 0 if input string length exceeds 63 characters, args(QWORD destination 64-byte buffer pointer)
    ._read_raw:
        ; Save arguments
        mov [rsp + 8], rcx  ; Save destination buffer pointer in shadow space

        ; Get input handle
        mov ecx, -10  ; Set to -10 to receive an input handle
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call GetStdHandle  ; Returns standard input handle
        add rsp, 40  ; Restore the stack
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
        je ._console_error

        ; NULL-terminate the string
        mov ecx, [rsp + 16 + 80]  ; Retrieve the number of characters read
        sub rcx, 2  ; Get the offset to CR character
        add rcx, rsp  ; Add the base address of the temporary buffer
        mov BYTE [rcx], 0 ; Set the CR character to NULL

        ; Copy the string to the destination
        mov rcx, [rsp + 8 + 80]  ; Retrieve the destination buffer pointer
        lea rdx, [rsp]  ; Set the source string pointer
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary        
        call string.copy  ; Copy the string to the destination
        add rsp, 40  ; Restore the stack

        ; Check if input string length did not exceed 63 characters
        mov ecx, [rsp + 16 + 80]  ; Retrieve the number of characters read
        cmp ecx, 65  ; Compare against max length + CR + LF
        jle ._end_read_raw  ; Return if string length did not exceed max length

            ; NULL-terminate the resulting string again if string length exceeds max length
            mov rcx, [rsp + 8 + 80]  ; Retrieve the destination buffer pointer
            add rcx, 63  ; Get the pointer to the last character
            mov BYTE [rcx], 0 ; Set the last character to NULL

            ; Flushing remaining input characters
            ._flush_buffer:
                ; Check if there might be more unread characters
                mov cl, [rsp + 65] ; Load the last character from the discard buffer
                cmp cl, 10
                je ._end_flush_buffer  ; Stop flushing if the last character read is a newline character
                mov ecx, [rsp + 16 + 80]  ; Load the number of characters the ReadConsole procedure has previously read
                cmp ecx, 66  ; Compare against discard buffer size
                jl ._end_flush_buffer  ; Stop flushing if the procedure has read less than 64 characters

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
                je ._console_error

                jmp ._flush_buffer  ; Continue flushing

            ._end_flush_buffer:

            add rsp, 80  ; Restore the stack
            mov rax, 0  ; Return zero if string length has exceeded max length
            ret

        ._end_read_raw:
            add rsp, 80  ; Restore the stack
            mov rax, 1  ; Return non-zero value if the whole input was read
            ret

    ._console_error:
        jmp exit


; String manipulation
string:

    ; Copies a NULL-terminated string, args(QWORD destination pointer, QWORD source string pointer)
    .copy:
        mov rax, 0  ; Set offset to 0

        ._loop:
            mov bl, [rdx + rax]  ; Moves a char from source + offset to bl
            mov [rcx + rax], bl  ; Moves a char from bl to destination + offset

            inc rax  ; Increment the offset
            cmp bl, 0
            jne ._loop  ; Loop until the NULL character is reached and cpoied

        ret

exit:
    mov  ecx, 0  ; Load exit status
    call ExitProcess
    hlt
