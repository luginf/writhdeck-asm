; test_buffer.asm -- portage des scenarios de tests/test_buffer.c :
; nouveau buffer a une ligne vide, insertion (incl. UTF-8), split puis
; backspace fait un aller-retour exact, delete en fin de ligne fusionne,
; word/char count, join, et sauvegarde/chargement fichier (y compris
; fichier absent -> reset silencieux).
format ELF executable
entry _start

include '../src/sys.inc'
include '../src/macros.inc'

segment readable executable

include 'tap.inc'
include '../src/heap.asm'
include '../src/strutil.asm'
include '../src/utf8.asm'
include '../src/buffer.asm'

; dword str_eq(const char* a, const char* b) -- aide de test uniquement
; (pas dans src/) : 1 si chaines identiques, sinon 0.
str_eq:
    proc_enter
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]
.loop:
    mov al, [esi]
    mov ah, [edi]
    cmp al, ah
    jne .neq
    test al, al
    jz .eq
    inc esi
    inc edi
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

; void sys_unlink(const char* path) -- aide de test uniquement.
sys_unlink:
    proc_enter
    push ebx
    mov ebx, [ebp+8]
    mov eax, SYS_UNLINK
    int 0x80
    pop ebx
    proc_leave
    ret

_start:
    ; --- buffer_new : une seule ligne vide ---
    call buffer_new
    mov esi, eax                      ; esi = buf (garde pour la suite)
    cmp dword [esi+BUF_COUNT], 1
    je @f
    TAP_FAIL 'buffer_new: count doit valoir 1'
@@:
    mov ecx, [esi+BUF_LINES]
    mov eax, [ecx]
    push zero_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'buffer_new: ligne 0 doit etre une chaine vide'
@@:
    TAP_OK 'buffer_new: ok'

    ; --- insertion caractere par caractere : "hi" ---
    push 'h'
    push 0
    push 0
    push esi
    call buffer_insert_char
    add esp, 16
    push 'i'
    push 1
    push 0
    push esi
    call buffer_insert_char
    add esp, 16
    push 0
    push esi
    call buffer_line_char_count
    add esp, 8
    cmp eax, 2
    je @f
    TAP_FAIL 'buffer_insert_char: "hi" doit compter 2 caracteres'
@@:
    mov ecx, [esi+BUF_LINES]
    mov eax, [ecx]
    push hi_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'buffer_insert_char: contenu attendu "hi"'
@@:
    TAP_OK 'buffer_insert_char: ok'

    ; --- insertion UTF-8 : 'e' accent (cp=0xE9) en position 2 -> "hie" (accent) ---
    push 0xE9
    push 2
    push 0
    push esi
    call buffer_insert_char
    add esp, 16
    push 0
    push esi
    call buffer_line_char_count
    add esp, 8
    cmp eax, 3
    je @f
    TAP_FAIL 'buffer_insert_char: UTF-8 doit compter pour 1 caractere'
@@:
    mov ecx, [esi+BUF_LINES]
    push dword [ecx]
    call strlen
    add esp, 4
    cmp eax, 4                          ; 'h','i',0xC3,0xA9 = 4 octets
    je @f
    TAP_FAIL 'buffer_insert_char: UTF-8 doit occuper 2 octets en stockage'
@@:
    TAP_OK 'buffer_insert_char: UTF-8 ok'

    ; --- split_line puis backspace : aller-retour exact ---
    ; buf ligne 0 = "hi" + e-accent (4 octets, 3 caracteres) ; split a col=2
    push 2
    push 0
    push esi
    call buffer_split_line
    add esp, 12
    cmp dword [esi+BUF_COUNT], 2
    je @f
    TAP_FAIL 'buffer_split_line: doit produire 2 lignes'
@@:
    ; backspace a (ligne=1, col=0) doit fusionner et redonner "hi"+e-accent
    lea eax, [out_line]
    lea ecx, [out_col]
    push ecx
    push eax
    push 0
    push 1
    push esi
    call buffer_backspace
    add esp, 20
    cmp dword [esi+BUF_COUNT], 1
    je @f
    TAP_FAIL 'buffer_backspace: doit refusionner en 1 ligne'
@@:
    mov eax, [out_line]
    test eax, eax
    jz @f
    TAP_FAIL 'buffer_backspace: out_line attendu 0'
@@:
    mov eax, [out_col]
    cmp eax, 2
    je @f
    TAP_FAIL 'buffer_backspace: out_col attendu 2 (colonne de la coupure)'
@@:
    mov ecx, [esi+BUF_LINES]
    mov eax, [ecx]
    push hi_accent_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'buffer_split_line+backspace: contenu doit redevenir identique'
@@:
    TAP_OK 'buffer_split_line + buffer_backspace: aller-retour exact'

    ; --- buffer_delete_char en fin de ligne fusionne avec la suivante ---
    push esi
    call buffer_free
    add esp, 4
    call buffer_new
    mov esi, eax
    push 'a'
    push 0
    push 0
    push esi
    call buffer_insert_char
    add esp, 16
    push 0
    push 0
    push esi
    call buffer_split_line          ; ligne0="", ligne1="a"
    add esp, 12
    push 'b'
    push 0
    push 0
    push esi
    call buffer_insert_char         ; ligne0="b"
    add esp, 16
    cmp dword [esi+BUF_COUNT], 2
    je @f
    TAP_FAIL 'setup delete: attendu 2 lignes'
@@:
    push 1                              ; col=1 = fin de "b"
    push 0
    push esi
    call buffer_delete_char
    add esp, 12
    cmp dword [esi+BUF_COUNT], 1
    je @f
    TAP_FAIL 'buffer_delete_char: doit fusionner avec la ligne suivante'
@@:
    mov ecx, [esi+BUF_LINES]
    mov eax, [ecx]
    push ba_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'buffer_delete_char: fusion doit donner "ba"'
@@:
    TAP_OK 'buffer_delete_char: fusion en fin de ligne ok'

    ; --- word_count / char_count / join ---
    push esi
    call buffer_free
    add esp, 4
    call buffer_new
    mov esi, eax
    ; construit "un" sur la ligne 0 puis une 2e ligne "deux mots"
    push 'u'
    push 0
    push 0
    push esi
    call buffer_insert_char
    add esp, 16
    push 'n'
    push 1
    push 0
    push esi
    call buffer_insert_char
    add esp, 16
    push 2
    push 0
    push esi
    call buffer_split_line
    add esp, 12
    ; ligne 1 = "deux mots"
    mov edi, deux_mots_str
    xor ebx, ebx
.copy_words:
    movzx eax, byte [edi+ebx]
    test eax, eax
    jz .words_done
    push eax
    push ebx
    push 1
    push esi
    call buffer_insert_char
    add esp, 16
    inc ebx
    jmp .copy_words
.words_done:
    push esi
    call buffer_word_count
    add esp, 4
    cmp eax, 3                          ; "un", "deux", "mots"
    je @f
    TAP_FAIL 'buffer_word_count: attendu 3 mots'
@@:
    push esi
    call buffer_char_count
    add esp, 4
    cmp eax, 12                          ; "un" (2) + '\n' (1) + "deux mots" (9) = 12
    je @f
    TAP_FAIL 'buffer_char_count: total attendu 12'
@@:
    push esi
    call buffer_join
    add esp, 4
    mov edi, eax                          ; edi = chaine jointe (allouee)
    push un_deux_mots_str
    push edi
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'buffer_join: attendu "un\ndeux mots"'
@@:
    push edi
    call free
    add esp, 4
    TAP_OK 'buffer_word_count/char_count/join: ok'

    ; --- sauvegarde puis rechargement (round-trip fichier) ---
    push tmp_path
    push esi
    call buffer_save_file
    add esp, 8
    test eax, eax
    jz @f
    TAP_FAIL 'buffer_save_file: doit renvoyer 0'
@@:
    push esi
    call buffer_free
    add esp, 4
    call buffer_new
    mov esi, eax
    push tmp_path
    push esi
    call buffer_load_file
    add esp, 8
    test eax, eax
    jz @f
    TAP_FAIL 'buffer_load_file: doit renvoyer 0 (fichier present)'
@@:
    cmp dword [esi+BUF_COUNT], 2
    je @f
    TAP_FAIL 'buffer_load_file: attendu 2 lignes apres rechargement'
@@:
    mov ecx, [esi+BUF_LINES]
    mov eax, [ecx]
    push un_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'buffer_load_file: ligne 0 attendue "un"'
@@:
    mov ecx, [esi+BUF_LINES]
    mov eax, [ecx+4]
    push deux_mots_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'buffer_load_file: ligne 1 attendue "deux mots"'
@@:
    TAP_OK 'buffer_save_file + buffer_load_file: round-trip ok'

    push tmp_path
    call sys_unlink
    add esp, 4

    ; --- fichier absent : reset silencieux a une ligne vide ---
    push esi
    call buffer_free
    add esp, 4
    call buffer_new
    mov esi, eax
    push 'x'
    push 0
    push 0
    push esi
    call buffer_insert_char           ; pollue le buffer avant le chargement
    add esp, 16
    push missing_path
    push esi
    call buffer_load_file
    add esp, 8
    cmp eax, -1
    je @f
    TAP_FAIL 'buffer_load_file: fichier absent doit renvoyer -1'
@@:
    cmp dword [esi+BUF_COUNT], 1
    je @f
    TAP_FAIL 'buffer_load_file: fichier absent doit reinitialiser a 1 ligne'
@@:
    mov ecx, [esi+BUF_LINES]
    mov eax, [ecx]
    push zero_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'buffer_load_file: fichier absent doit donner une ligne vide'
@@:
    TAP_OK 'buffer_load_file: fichier absent -> reset silencieux ok'

    syscall1 SYS_EXIT, 0

segment readable writeable
include '../src/heap_data.inc'

zero_str          db 0
hi_str            db 'hi', 0
hi_accent_str     db 'hi', 0xC3, 0xA9, 0
ba_str            db 'ba', 0
deux_mots_str     db 'deux mots', 0
un_str            db 'un', 0
un_deux_mots_str  db 'un', 10, 'deux mots', 0
tmp_path          db 'tests/tmp_buffer_test.txt', 0
missing_path      db 'tests/this_file_does_not_exist.txt', 0

out_line dd 0
out_col  dd 0
