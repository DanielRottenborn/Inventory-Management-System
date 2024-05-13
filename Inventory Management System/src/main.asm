default rel  ; Use RIP-relative addressing
bits 64  ; Target 64-bit architecture exclusively

extern GetProcessHeap  ; Returns a handle to the default heap of the process 
extern HeapAlloc  ; Heap memory allocation
extern HeapReAlloc  ; Heap memory reallocation
extern HeapFree  ; Heap memory release
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
    mov rax, 0  ; Set counter to 0

    .loop:
        cmp rax, r8
        jge .loop_end  ; Loop until counter is equal to the amount

        mov bl, [rdx + rax]  ; Moves a byte from source + offset to bl
        mov [rcx + rax], bl  ; Moves a byte from bl to destination + offset

        inc rax
        jmp .loop

    .loop_end:
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
        jle .end_clear  ; Skip reallocation if capacity is minimal

        ; Set min capacity
            mov edx, 10  ; set min capacity as an argument
            sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
            call ._modify_capacity  ; Reallocates memory and updates capacity
            add rsp, 40  ; Restore the stack

        .end_clear
            ret


    ; Deallocates the array, args(QWORD array struct pointer)
    .free: 
        ; Save arguments
        mov [rsp + 8], rcx  ; Save array struct pointer in shadow space
 
        ; Get the heap handle
        sub rsp, 40  ; Reserve shadow space and align to a 16-byte boundary
        call GetProcessHeap  ; Returns a handle to the default heap of the process
        add rsp, 40  ; Restore the stack

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


exit:
    mov  ecx, 0  ; Load exit status
    call ExitProcess
    hlt
