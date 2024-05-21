%ifndef DYNAMIC_ARRAY_ASM
%define DYNAMIC_ARRAY_ASM

%include "src/common.asm"
%include "src/console.asm"

; Externals
extern GetProcessHeap  ; Returns a handle to the default heap of the process 
extern HeapAlloc  ; Heap memory allocation
extern HeapReAlloc  ; Heap memory reallocation
extern HeapFree  ; Heap memory release

; Constants
ARRAY_COUNT_OFFSET equ 8  ; Offset to the array count parameter
ARRAY_CAPACITY_OFFSET equ 12  ; Offset to the array capacity parameter
ARRAY_MEMBER_SIZE_OFFSET equ 16  ; Offset to the array member size parameter


; Rodata section
section .rodata
array_messages:
    .memory_error: db FATAL_ERROR_COLOR,"An error occured while managing heap memory.", DEFAULT_COLOR, LF, NULL


; Text section
section .text

; Dynamic array functionality
dynamic_array:

    ; Initializes a dynamic array, args(QWORD array struct pointer, DWORD member size)
    .init:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], rcx  ; Save array struct pointer in shadow space
        mov QWORD [rsp + 24], 0  ; Initialize with 0 for convinient 64-bit multiplication
        mov [rsp + 24], edx  ; Save member size in shadow space
        
        ; Get default heap handle
        fast_call GetProcessHeap

        ; Check for errors (NULL return)
        cmp rax, NULL
        je ._memory_error

        ; Allocate memory
        mov rcx, rax  ; Use the handle as a first argument
        mov rax, 10 ; Initial member slot count
        mul QWORD [rsp + 24]  ; Multiply by member size (affects rdx)
        mov r8, rax  ; Resulting number of bytes to allocate
        mov edx, 0  ; Allocation flags
        fast_call HeapAlloc  ; Returns a pointer to the allocated memory

        ; Check for errors (NULL return)
        cmp rax, NULL
        je ._memory_error

        ; Modify array struct
        mov rcx, [rsp +  16]  ; Retrieve array struct pointer
        mov edx, [rsp + 24]  ; Retrieve member size
        mov [rcx], rax  ; Update allocated memory pointer
        mov DWORD [rcx + ARRAY_COUNT_OFFSET], 0  ; Update initial member count
        mov DWORD [rcx + ARRAY_CAPACITY_OFFSET], 10  ; Update capacity
        mov [rcx + ARRAY_MEMBER_SIZE_OFFSET], edx  ; Update member size

        add rsp, 8  ; Restore the stack
        ret


    ; Pushes new element, returns member index, args(QWORD array struct pointer, QWORD new member pointer)
    .push:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], rcx  ; Save array struct pointer in shadow space
        mov [rsp + 24], rdx  ; Save new member pointer in shadow space

        ; Check capacity
        mov eax, [rcx + ARRAY_COUNT_OFFSET]  ; Load member count value
        cmp eax, [rcx + ARRAY_CAPACITY_OFFSET]  ; Compare against capacity
        jb ._push  ; Skip reallocation if the array is not yet full

            ; Increase capacity
            mov edx, [rcx + ARRAY_CAPACITY_OFFSET]  ; Load current array capacity as an argument
            add edx, edx  ; Double it
            fast_call ._modify_capacity  ; Reallocates memory and updates capacity

        ._push:

        ; Get offset to place a new member
        mov rcx, [rsp + 16]  ; Retrieve array struct pointer
        mov edx, [rcx + ARRAY_COUNT_OFFSET]  ; Get member count
        fast_call .get  ; Get pointer to the next available member location

        ; Push new member to the array and increment member count
        mov rbx, [rsp + 16]  ; Retrieve array struct pointer
        mov rcx, rax  ; Set destination argument
        mov rdx, [rsp + 24]  ; Retrieve new member pointer to use as a source argument
        mov r8d, [rbx + ARRAY_MEMBER_SIZE_OFFSET]  ; Get member size

        mov eax, [rbx + ARRAY_COUNT_OFFSET]  ; Get member count
        inc eax  ; Increment member count
        mov [rbx + ARRAY_COUNT_OFFSET], eax  ; Update member count

        fast_call mem_copy  ; Copy new member to the end of the array

        ; Return member index
        mov rbx, [rsp + 16]  ; Retrieve array struct pointer
        mov eax, [rbx + ARRAY_COUNT_OFFSET]  ; Get element count
        dec eax  ; Decrement to get the index of the last element

        add rsp, 8  ; Restore the stack
        ret


    ; Returns a pointer to a member by index, args(QWORD array struct pointer, DWORD index)
    .get:
        ; Do pointer arithmetic
        mov eax, edx  ; Get index
        mov ebx, [rcx + ARRAY_MEMBER_SIZE_OFFSET]  ; Get member size
        mul rbx  ; Get offset
        add rax, [rcx]  ; Add array base pointer to offset

        ret
        

    ; Removes member by index, shifts everything past by 1, args(QWORD array struct pointer, DWORD index)
    .remove:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], rcx  ; Save array struct pointer in shadow space
        mov [rsp + 24], edx  ; Save element index in shadow space

        ; Get pointer to the member to be removed
        fast_call .get     

        ; Set up destination argument
        mov rbx, [rsp + 16]  ; Retrieve array struct pointer
        mov r9d, [rbx + ARRAY_MEMBER_SIZE_OFFSET]  ; Get member size
        mov rcx, rax  ; Set destingation pointer

        ; Calculate memory block size to be shifted
        mov eax, [rbx + ARRAY_COUNT_OFFSET]  ; Get member count
        mov r8d, [rsp + 24]  ; Retrieve element index
        add r8d, 1  ; Get next element index
        sub eax, r8d  ; Get the number of members to be shifted
        mul r9  ; Get the size of memory chunk to be shifted
        mov r8, rax  ; Use the size as argument

        ; Calculate a pointer to the next member
        mov rdx, rcx  ; Set source pointer
        add rdx, r9  ; Offset source pointer by 1 member

        ; Shift elements
        fast_call mem_copy

        ; Decrement member count
        mov rbx, [rsp + 16]  ; Retrieve array struct pointer
        mov eax, [rbx + ARRAY_COUNT_OFFSET]  ; Get member count
        dec eax
        mov [rbx + ARRAY_COUNT_OFFSET], eax  ; Update member count

        ; Check if the capacity of the array needs to be decreased
        mov eax, [rbx + ARRAY_CAPACITY_OFFSET]  ; Get current capacity
        mov rdx, 0  ; Set rdx to 0 for division
        mov ecx, 4  ; Set the divisor
        div rcx  ; Divide current capacity by 4

        ; Compare against member count
        cmp eax, [rbx + ARRAY_COUNT_OFFSET] 
        jbe ._end_remove  ; Skip reallocation if new capacity is less than or equal to member count

        ; Compare new capacity against min capacity
        cmp eax, 10
        jb ._end_remove  ; Skip reallocation if new capacity is less than min capacity

            ; Decrease capacity
            mov rcx, rbx  ; Array struct pointer argument
            mov edx, eax  ; New capacity
            fast_call ._modify_capacity  ; Reallocates memory and updates capacity

        ._end_remove:

        add rsp, 8  ; Restore the stack
        ret


    ; Clears the array, args(QWORD array struct pointer)
    .clear:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary

        ; Reset member count
        mov DWORD [rcx + ARRAY_COUNT_OFFSET], 0

        ; Check cucrent capacity
        mov ebx, [rcx + ARRAY_CAPACITY_OFFSET]  ; Load capacity
        cmp ebx, 10  ; Compare against min capacity
        jbe ._end_clear  ; Skip reallocation if capacity is minimal

            ; Set min capacity
            mov edx, 10  ; set min capacity as an argument
            fast_call ._modify_capacity  ; Reallocates memory and updates capacity

        ._end_clear:

        add rsp, 8  ; Restore the stack
        ret


    ; Deallocates the array, args(QWORD array struct pointer)
    .free: 
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], rcx  ; Save array struct pointer in shadow space
 
        ; Get default heap handle
        fast_call GetProcessHeap

        ; Check for errors (NULL return)
        cmp rax, NULL
        je ._memory_error

        ; Free memory
        mov rbx, [rsp + 16]  ; Retrieve array struct pointer 
        mov rcx, rax  ; Use the handle as a first argument
        mov edx, 0  ; Allocation flags
        mov r8, [rbx]  ; Address of the memory chunk to be released
        fast_call HeapFree  ; Releases memory

        ; Check for errors (NULL return)
        cmp rax, NULL
        je ._memory_error

        add rsp, 8  ; Restore the stack
        ret


    ; Modify capacity and reallocate memory, args(QWORD array struct pointer, DWORD new capacity)
    ._modify_capacity:
        ; Prolog
        sub rsp, 8  ; Align the stack to a 16-byte boundary
        mov [rsp + 16], rcx  ; Save array struct pointer in shadow space
        mov [rsp + 24], edx  ; Save new capacity in shadow space        

        ; Get default heap handle
        fast_call GetProcessHeap

        ; Check for errors (NULL return)
        cmp rax, NULL
        je ._memory_error

        ; Reallocate memory
        mov rbx, [rsp + 16]  ; Retrieve array struct pointer
        mov rcx, rax  ; Use the handle as a first argument
        mov edx, [rbx + ARRAY_MEMBER_SIZE_OFFSET]  ; Get member size
        mov eax, [rsp + 24]  ; Retrieve new capacity
        mul rdx  ; Multiply by member size (affects rdx)
        mov r9, rax  ; Resulting number of bytes to reallocate
        mov edx, 0  ; Reallocation flags
        mov r8, [rbx]  ; Address of the memory chunk to be reallocated
        fast_call HeapReAlloc  ; Returns a pointer to the allocated memory

        ; Check for errors (NULL return)
        cmp rax, NULL
        je ._memory_error

        ; Modify array struct
        mov rcx, [rsp +  16]  ; Retrieve array struct pointer
        mov edx, [rsp + 24]  ; Retrieve new capacity
        mov [rcx], rax  ; Update allocated memory pointer
        mov [rcx + ARRAY_CAPACITY_OFFSET], edx  ; Update capacity

        add rsp, 8  ; Restore the stack
        ret


    ; Jump here when memory error is encountered
    ._memory_error:
        lea rcx, [array_messages.memory_error]  ; Notify the user that an error occured while managing heap memory
        fast_call console.print_string  ; Print error message

        jmp exit


%endif
