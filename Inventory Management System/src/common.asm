%ifndef COMMON_ASM
%define COMMON_ASM

default rel  ; Use RIP-relative addressing
bits 64  ; Target 64-bit architecture exclusively

; Externals
extern ExitProcess  ; Win32 API exit procedure

; Constants
NULL equ 0  ; NULL
LF equ 10  ; Newline character
ESC equ 27  ; Escape character

; Macros
%define DEFAULT_COLOR ESC, "[97m"  ; Resets text color
%define INPUT_COLOR ESC, "[38;2;145;250;150m"  ; Changes text color to bright green
%define WARNING_COLOR ESC, "[93m"  ; Changes text color to bright yellow
%define ERROR_COLOR ESC, "[38;2;255;145;65m"  ; Changes text color to bright orange
%define FATAL_ERROR_COLOR ESC, "[91m"  ; Changes text color to bright red

%define DEFAULT_BG_COLOR ESC, "[40m"  ; Resets background color
%define TABLE_HEADER_BG_COLOR ESC, "[48;2;0;120;120m"  ; Changes background color to dark cyan
%define HIGHLIGHT_BG_COLOR ESC, "[48;2;210;60;75m"  ; Changes background color to bright red

%macro fast_call 1  ; Reserves shadow space for __fastcall convention
    sub rsp, 32  ; Reserve shadow space
    call %1  ; Call the procedure
    add rsp, 32  ; Restore the stack

%endmacro


; Text section
section .text

; Copies memory from one location to another, args(QWORD destination pointer, QWORD source pointer, QWORD number of bytes)
mem_copy:
    mov rax, 0  ; Set offset to 0

    ._loop:
        cmp rax, r8
        jae ._loop_end  ; Loop until the offset is equal to the number of bytes

        mov r10b, [rdx + rax]  ; Moves a byte from source + offset to r10b
        mov [rcx + rax], r10b  ; Moves a byte from r10b to destination + offset

        inc rax  ; Increment the offset
        jmp ._loop

    ._loop_end:

    ret


exit:
    mov ecx, 0  ; Load exit status
    fast_call ExitProcess  ; Terminate the process


%endif
