; test_strutil.asm -- verifie strutil.asm (strlen/memcpy/memmove/strdup/
; tolower_ascii/ascii_stristr) et utf8.asm (seq_len/decode/encode/strlen/
; byte_offset/char_index), portage de writhdeck-c/src/utf8.c.
format ELF executable
entry _start

include '../src/sys.inc'
include '../src/macros.inc'

segment readable executable

include 'tap.inc'
include '../src/heap.asm'
include '../src/strutil.asm'
include '../src/utf8.asm'

_start:
    ; --- strlen ---
    push hello
    call strlen
    add esp, 4
    cmp eax, 5
    je @f
    TAP_FAIL 'strlen: "hello" doit faire 5'
@@:
    TAP_OK 'strlen: ok'

    ; --- memcpy ---
    push 6
    push hello
    push buf1
    call memcpy
    add esp, 12
    mov al, [buf1]
    cmp al, 'h'
    je @f
    TAP_FAIL 'memcpy: premier octet incorrect'
@@:
    mov al, [buf1+5]
    cmp al, 0
    je @f
    TAP_FAIL 'memcpy: terminateur nul non copie'
@@:
    TAP_OK 'memcpy: ok'

    ; --- memmove (chevauchement dst > src) ---
    ; buf2 = "abcdef", memmove(buf2+2, buf2, 4) -> "ababcd"
    push 6
    push abcdef_src
    push buf2
    call memcpy
    add esp, 12
    lea eax, [buf2+2]
    push 4
    push buf2
    push eax
    call memmove
    add esp, 12
    mov al, [buf2]
    cmp al, 'a'
    jne .mm_fail
    mov al, [buf2+1]
    cmp al, 'b'
    jne .mm_fail
    mov al, [buf2+2]
    cmp al, 'a'
    jne .mm_fail
    mov al, [buf2+3]
    cmp al, 'b'
    jne .mm_fail
    mov al, [buf2+4]
    cmp al, 'c'
    jne .mm_fail
    mov al, [buf2+5]
    cmp al, 'd'
    je .mm_ok
.mm_fail:
    TAP_FAIL 'memmove: resultat incorrect avec chevauchement dst>src'
.mm_ok:
    TAP_OK 'memmove: chevauchement dst>src correct'

    ; --- strdup ---
    push hello
    call strdup
    add esp, 4
    mov esi, eax
    cmp esi, hello
    je .dup_fail
    push esi
    call strlen
    add esp, 4
    cmp eax, 5
    je .dup_ok
.dup_fail:
    TAP_FAIL 'strdup: copie independante attendue'
.dup_ok:
    TAP_OK 'strdup: ok'

    ; --- tolower_ascii ---
    push 'A'
    call tolower_ascii
    add esp, 4
    cmp eax, 'a'
    je @f
    TAP_FAIL 'tolower_ascii: A doit devenir a'
@@:
    push '5'
    call tolower_ascii
    add esp, 4
    cmp eax, '5'
    je @f
    TAP_FAIL 'tolower_ascii: 5 doit rester inchange'
@@:
    TAP_OK 'tolower_ascii: ok'

    ; --- ascii_stristr ---
    push needle_world
    push haystack
    call ascii_stristr
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'ascii_stristr: WORLD devrait etre trouve (insensible a la casse)'
@@:
    push empty_str
    push haystack
    call ascii_stristr
    add esp, 8
    cmp eax, haystack
    je @f
    TAP_FAIL 'ascii_stristr: aiguille vide doit renvoyer hay tel quel'
@@:
    push needle_absent
    push haystack
    call ascii_stristr
    add esp, 8
    test eax, eax
    jz @f
    TAP_FAIL 'ascii_stristr: motif absent doit renvoyer 0'
@@:
    TAP_OK 'ascii_stristr: ok'

    ; --- utf8_seq_len ---
    push 0x61                 ; 'a' ASCII
    call utf8_seq_len
    add esp, 4
    cmp eax, 1
    je @f
    TAP_FAIL 'utf8_seq_len: ASCII doit faire 1'
@@:
    push 0xC3                 ; tete 2 octets (ex. debut de "é")
    call utf8_seq_len
    add esp, 4
    cmp eax, 2
    je @f
    TAP_FAIL 'utf8_seq_len: tete 2 octets incorrecte'
@@:
    push 0x80                 ; octet de continuation isole -> repli 1
    call utf8_seq_len
    add esp, 4
    cmp eax, 1
    je @f
    TAP_FAIL 'utf8_seq_len: continuation isolee doit replier sur 1'
@@:
    TAP_OK 'utf8_seq_len: ok'

    ; --- utf8_decode : "é" = 0xC3 0xA9 -> cp=0xE9, 2 octets ---
    push cp_out
    push accent_e
    call utf8_decode
    add esp, 8
    cmp eax, 2
    jne .dec_fail
    mov ecx, [cp_out]
    cmp ecx, 0xE9
    je .dec_ok
.dec_fail:
    TAP_FAIL 'utf8_decode: "e accent" doit donner cp=0xE9 en 2 octets'
.dec_ok:
    ; sequence malformee : 0xC3 suivi de 'A' (pas un octet de continuation)
    push cp_out
    push malformed_seq
    call utf8_decode
    add esp, 8
    cmp eax, 1
    jne .dec2_fail
    mov ecx, [cp_out]
    cmp ecx, 0xC3
    je .dec2_ok
.dec2_fail:
    TAP_FAIL 'utf8_decode: continuation invalide doit consommer 1 octet, cp=tete brute'
.dec2_ok:
    TAP_OK 'utf8_decode: ok'

    ; --- utf8_encode : reencode 0xE9 et compare a "é" ---
    push enc_buf
    push 0xE9
    call utf8_encode
    add esp, 8
    cmp eax, 2
    jne .enc_fail
    mov al, [enc_buf]
    cmp al, 0xC3
    jne .enc_fail
    mov al, [enc_buf+1]
    cmp al, 0xA9
    je .enc_ok
.enc_fail:
    TAP_FAIL 'utf8_encode: 0xE9 doit redonner C3 A9'
.enc_ok:
    TAP_OK 'utf8_encode: ok'

    ; --- utf8_strlen("café") == 4 caracteres (5 octets) ---
    push cafe_str
    call utf8_strlen
    add esp, 4
    cmp eax, 4
    je @f
    TAP_FAIL 'utf8_strlen: "cafe accent" doit compter 4 caracteres'
@@:
    TAP_OK 'utf8_strlen: ok'

    ; --- utf8_byte_offset/char_index, round-trip + cas "au milieu" ---
    push 4
    push cafe_str
    call utf8_byte_offset
    add esp, 8
    cmp eax, 5
    je @f
    TAP_FAIL 'utf8_byte_offset: char_index=4 (fin) doit donner offset=5'
@@:
    push 5
    push cafe_str
    call utf8_char_index
    add esp, 8
    cmp eax, 4
    je @f
    TAP_FAIL 'utf8_char_index: offset=5 (fin) doit donner 4 caracteres'
@@:
    ; offset=4 tombe au milieu du 2e octet de "e accent" (qui commence a
    ; l'octet 3) -- ne doit compter que les 3 caracteres complets avant
    push 4
    push cafe_str
    call utf8_char_index
    add esp, 8
    cmp eax, 3
    je @f
    TAP_FAIL 'utf8_char_index: offset au milieu d une sequence doit s arreter avant'
@@:
    TAP_OK 'utf8_byte_offset/char_index: ok'

    syscall1 SYS_EXIT, 0

segment readable writeable
include '../src/heap_data.inc'

hello        db 'hello', 0
abcdef_src   db 'abcdef', 0
haystack     db 'Hello WORLD test', 0
needle_world db 'world', 0
needle_absent db 'xyz', 0
empty_str    db 0
accent_e     db 0xC3, 0xA9, 0
malformed_seq db 0xC3, 'A', 0
cafe_str     db 'c', 'a', 'f', 0xC3, 0xA9, 0

buf1 rb 8
buf2 rb 8
cp_out rd 1
enc_buf rb 4
