; test_ui.asm -- verifie les parties de ui_ansi.asm testables sans vrai
; terminal : accumulation dans le tampon de frame (ui__append_uint,
; ui_clear_line, ui_put_str, ui_set_cursor produisent les bonnes
; sequences ANSI). ui_init/term_enable_raw (ioctl sur un vrai tty) sont
; verifies a part, de facon interactive (voir README/plan).
format ELF executable
entry _start

include '../src/sys.inc'
include '../src/macros.inc'

segment readable executable

include 'tap.inc'
include '../src/heap.asm'
include '../src/strutil.asm'
include '../src/utf8.asm'
include '../src/term.asm'
include '../src/buffer.asm'
include '../src/ui_ansi.asm'

; dword mem_eq(const void* a, const void* b, dword len) -- aide de test.
mem_eq:
    proc_enter
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]
    mov ecx, [ebp+16]
    xor edx, edx
.loop:
    cmp edx, ecx
    jge .eq
    mov al, [esi+edx]
    cmp al, [edi+edx]
    jne .neq
    inc edx
    jmp .loop
.eq:
    mov eax, 1
    jmp .ret
.neq:
    xor eax, eax
.ret:
    pop edi
    pop esi
    proc_leave
    ret

_start:
    ; --- ui__append_uint(0) ---
    push 0
    call ui__append_uint
    add esp, 4
    cmp dword [frame_len], 1
    je @f
    TAP_FAIL 'ui__append_uint(0): longueur attendue 1'
@@:
    push 1
    push zero_digit
    push dword [frame_buf]
    call mem_eq
    add esp, 12
    test eax, eax
    jnz @f
    TAP_FAIL 'ui__append_uint(0): attendu "0"'
@@:
    mov dword [frame_len], 0

    ; --- ui__append_uint(42) ---
    push 42
    call ui__append_uint
    add esp, 4
    cmp dword [frame_len], 2
    je @f
    TAP_FAIL 'ui__append_uint(42): longueur attendue 2'
@@:
    push 2
    push forty_two_digits
    push dword [frame_buf]
    call mem_eq
    add esp, 12
    test eax, eax
    jnz @f
    TAP_FAIL 'ui__append_uint(42): attendu "42"'
@@:
    mov dword [frame_len], 0
    TAP_OK 'ui__append_uint: ok'

    ; --- ui_clear_line(0) -> "\033[1;1H\033[K" ---
    push 0
    call ui_clear_line
    add esp, 4
    push clear_line0_len
    push expect_clear_line0
    push dword [frame_buf]
    call mem_eq
    add esp, 12
    test eax, eax
    jnz @f
    TAP_FAIL 'ui_clear_line(0): sequence ANSI inattendue'
@@:
    cmp dword [frame_len], clear_line0_len
    je @f
    TAP_FAIL 'ui_clear_line(0): longueur inattendue'
@@:
    mov dword [frame_len], 0
    TAP_OK 'ui_clear_line: ok'

    ; --- ui_set_cursor(0,0) -> "\033[1;1H" ---
    push 0
    push 0
    call ui_set_cursor
    add esp, 8
    push set_cursor00_len
    push expect_set_cursor00
    push dword [frame_buf]
    call mem_eq
    add esp, 12
    test eax, eax
    jnz @f
    TAP_FAIL 'ui_set_cursor(0,0): sequence ANSI inattendue'
@@:
    mov dword [frame_len], 0
    TAP_OK 'ui_set_cursor: ok'

    ; --- ui_put_str(2,3,"hi",2,NORMAL) -> "\033[3;4H\033[Khi" ---
    push UI_ATTR_NORMAL
    push 2
    push hi_text
    push 3
    push 2
    call ui_put_str
    add esp, 20
    push put_str_len
    push expect_put_str
    push dword [frame_buf]
    call mem_eq
    add esp, 12
    test eax, eax
    jnz @f
    TAP_FAIL 'ui_put_str: sequence ANSI + texte inattendus'
@@:
    cmp dword [frame_len], put_str_len
    je @f
    TAP_FAIL 'ui_put_str: longueur inattendue'
@@:
    mov dword [frame_len], 0
    TAP_OK 'ui_put_str: ok'

    syscall1 SYS_EXIT, 0

segment readable writeable
include '../src/heap_data.inc'
include '../src/term_data.inc'
include '../src/ui_data.inc'

zero_digit           db '0'
forty_two_digits     db '4', '2'
expect_clear_line0   db 27, '[', '1', ';', '1', 'H', 27, '[', 'K'
clear_line0_len = $ - expect_clear_line0
expect_set_cursor00  db 27, '[', '1', ';', '1', 'H'
set_cursor00_len = $ - expect_set_cursor00
hi_text              db 'hi', 0
expect_put_str       db 27, '[', '3', ';', '4', 'H', 27, '[', 'K', 'h', 'i'
put_str_len = $ - expect_put_str
