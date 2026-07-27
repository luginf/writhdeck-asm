; test_editor.asm -- portage des scenarios les plus delicats de
; tests/test_editor.c : undo/redo (aller-retour + plafond a 100 avec
; eviction du plus ancien), colonne collante paresseuse/reinitialisee,
; word_right (seul ' ' compte, jamais la tabulation), find (cx+1 sur la
; ligne de depart, parcours circulaire), replace_all (verbatim,
; insensible a la casse).
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
include '../src/editor.asm'

; dword str_eq(const char* a, const char* b) -- aide de test uniquement.
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

; void type_str(editor_t* ed, const char* s) -- aide de test uniquement :
; insere s caractere par caractere via editor_insert_codepoint (ASCII
; seulement -- cp == valeur de l'octet).
type_str:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]
    xor ebx, ebx
.loop:
    movzx eax, byte [edi+ebx]
    test eax, eax
    jz .done
    push eax
    push esi
    call editor_insert_codepoint
    add esp, 8
    inc ebx
    jmp .loop
.done:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

_start:
    ; ================= undo/redo : aller-retour =================
    call editor_new
    mov esi, eax

    push esi
    call editor_push_undo
    add esp, 4
    push 'a'
    push esi
    call editor_insert_codepoint
    add esp, 8

    push esi
    call editor_push_undo
    add esp, 4
    push 'b'
    push esi
    call editor_insert_codepoint
    add esp, 8

    ; buf = "ab", cx=2
    mov eax, [esi+EDITOR_BUF]
    mov ecx, [eax+BUF_LINES]
    mov eax, [ecx]
    push ab_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'setup undo: attendu "ab" avant undo'
@@:
    push esi
    call editor_undo
    add esp, 4
    test eax, eax
    jnz @f
    TAP_FAIL 'editor_undo: doit renvoyer 1 (pile non vide)'
@@:
    mov eax, [esi+EDITOR_BUF]
    mov ecx, [eax+BUF_LINES]
    mov eax, [ecx]
    push a_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'editor_undo: attendu "a" apres 1 undo'
@@:
    cmp dword [esi+EDITOR_CX], 1
    je @f
    TAP_FAIL 'editor_undo: cx attendu 1'
@@:
    push esi
    call editor_undo
    add esp, 4
    mov eax, [esi+EDITOR_BUF]
    mov ecx, [eax+BUF_LINES]
    mov eax, [ecx]
    push zero_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'editor_undo: attendu chaine vide apres 2 undo'
@@:
    push esi
    call editor_redo
    add esp, 4
    test eax, eax
    jnz @f
    TAP_FAIL 'editor_redo: doit renvoyer 1'
@@:
    mov eax, [esi+EDITOR_BUF]
    mov ecx, [eax+BUF_LINES]
    mov eax, [ecx]
    push a_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'editor_redo: attendu "a" apres 1 redo'
@@:
    push esi
    call editor_redo
    add esp, 4
    mov eax, [esi+EDITOR_BUF]
    mov ecx, [eax+BUF_LINES]
    mov eax, [ecx]
    push ab_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'editor_redo: attendu "ab" apres 2 redo'
@@:
    TAP_OK 'editor_undo/editor_redo: aller-retour exact'

    push esi
    call editor_free
    add esp, 4

    ; ================= plafond undo a 100, eviction du plus ancien =================
    call editor_new
    mov esi, eax
    xor ebx, ebx
.push_loop:
    cmp ebx, 120
    jge .push_done
    push esi
    call editor_push_undo
    add esp, 4
    inc ebx
    jmp .push_loop
.push_done:
    cmp dword [esi+EDITOR_UNDO_COUNT], 100
    je @f
    TAP_FAIL 'editor_push_undo: undo_count doit plafonner a 100 apres 120 empilements'
@@:
    xor ebx, ebx
.undo_loop:
    cmp ebx, 100
    jge .undo_done
    push esi
    call editor_undo
    add esp, 4
    test eax, eax
    jnz .undo_ok
    TAP_FAIL 'editor_undo: ne doit pas echouer avant epuisement de la pile (100 undo attendus)'
.undo_ok:
    inc ebx
    jmp .undo_loop
.undo_done:
    cmp dword [esi+EDITOR_UNDO_COUNT], 0
    je @f
    TAP_FAIL 'editor_undo: la pile doit etre vide apres 100 undo'
@@:
    mov eax, [esi+EDITOR_BUF]
    test eax, eax
    jnz @f
    TAP_FAIL 'editor_undo: le buffer ne doit jamais devenir NULL (eviction du plus ancien, pas du plus recent)'
@@:
    TAP_OK 'editor_push_undo: plafond a 100 + eviction du plus ancien ok'

    push esi
    call editor_free
    add esp, 4

    ; ================= colonne collante : capture paresseuse =================
    call editor_new
    mov esi, eax
    push digits_str
    push esi
    call type_str
    add esp, 8
    push esi
    call editor_enter
    add esp, 4
    push ab2_str
    push esi
    call type_str
    add esp, 8
    push esi
    call editor_enter
    add esp, 4
    push upper_str
    push esi
    call type_str
    add esp, 8

    ; buf: ligne0="0123456789" (10c), ligne1="ab" (2c), ligne2="ABCDEFGHIJ" (10c)
    push 9
    push 0
    push esi
    call editor_set_cursor
    add esp, 12

    push 5
    push esi
    call editor_move_down          ; -> ligne1 "ab", sticky capture = 9-5=4, cx=clamp(4,0,2)=2
    add esp, 8
    cmp dword [esi+EDITOR_CY], 1
    je @f
    TAP_FAIL 'sticky_col: descente 1 doit aller sur la ligne courte'
@@:
    cmp dword [esi+EDITOR_CX], 2
    je @f
    TAP_FAIL 'sticky_col: cx attendu 2 (clampe) sur la ligne courte'
@@:
    cmp dword [esi+EDITOR_STICKY], 4
    je @f
    TAP_FAIL 'sticky_col: capture attendue 4'
@@:
    push 5
    push esi
    call editor_move_down          ; -> ligne2 rangee0 : sticky PRESERVEE (4), pas recapturee a 2
    add esp, 8
    cmp dword [esi+EDITOR_CY], 2
    je @f
    TAP_FAIL 'sticky_col: descente 2 doit aller sur la ligne 2'
@@:
    cmp dword [esi+EDITOR_CX], 4
    je @f
    TAP_FAIL 'sticky_col: preservee a travers une ligne courte -> cx attendu 4 (pas 2)'
@@:
    TAP_OK 'sticky_col: capture paresseuse preservee a travers une ligne courte'

    push esi
    call editor_free
    add esp, 4

    ; ================= colonne collante : reinitialisation =================
    call editor_new
    mov esi, eax
    push digits_str
    push esi
    call type_str
    add esp, 8
    push esi
    call editor_enter
    add esp, 4
    push ab2_str
    push esi
    call type_str
    add esp, 8
    push esi
    call editor_enter
    add esp, 4
    push upper_str
    push esi
    call type_str
    add esp, 8

    push 9
    push 0
    push esi
    call editor_set_cursor
    add esp, 12
    push 5
    push esi
    call editor_move_down            ; -> ligne1 "ab", cx=2 (clampe), sticky=4
    add esp, 8

    mov dword [esi+EDITOR_STICKY], -1     ; simule la reinitialisation faite par l'appelant (main.c)

    push 5
    push esi
    call editor_move_down              ; capture FRAICHE a la position courante (cx=2) -> sticky=2
    add esp, 8
    cmp dword [esi+EDITOR_CY], 2
    je @f
    TAP_FAIL 'sticky_col reset: doit atteindre la ligne 2'
@@:
    cmp dword [esi+EDITOR_CX], 2
    je @f
    TAP_FAIL 'sticky_col reset: capture fraiche attendue -> cx=2 (pas 4)'
@@:
    TAP_OK 'sticky_col: reinitialisation donne une capture fraiche'

    push esi
    call editor_free
    add esp, 4

    ; ================= word_right : seul l'espace ASCII compte =================
    call editor_new
    mov esi, eax
    push foo_tab_bar_str
    push esi
    call type_str                       ; "foo<TAB>bar", pas d'espace du tout
    add esp, 8
    push esi
    call editor_enter
    add esp, 4
    push next_str
    push esi
    call type_str
    add esp, 8

    push 0
    push 0
    push esi
    call editor_set_cursor
    add esp, 12
    push esi
    call editor_move_word_right
    add esp, 4
    cmp dword [esi+EDITOR_CY], 1
    je @f
    TAP_FAIL 'word_right: sans espace (tabulation ignoree) doit sauter a la ligne suivante'
@@:
    cmp dword [esi+EDITOR_CX], 0
    je @f
    TAP_FAIL 'word_right: doit atterrir en debut de la ligne suivante'
@@:
    TAP_OK 'word_right: la tabulation n est jamais une frontiere de mot'

    push esi
    call editor_free
    add esp, 4

    ; ================= find : cx+1 sur la ligne de depart, parcours circulaire =================
    call editor_new
    mov esi, eax
    push chat_str
    push esi
    call type_str
    add esp, 8
    push esi
    call editor_enter
    add esp, 4
    push xx_str
    push esi
    call type_str
    add esp, 8

    push 0
    push 1
    push esi
    call editor_set_cursor              ; ligne1 "xx", cx=0
    add esp, 12
    push needle_chat
    push esi
    call editor_find                       ; doit boucler jusqu'a la ligne0 "chat"
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'editor_find: doit trouver "chat" en bouclant sur le document'
@@:
    cmp dword [esi+EDITOR_CY], 0
    je @f
    TAP_FAIL 'editor_find: doit se positionner sur la ligne 0'
@@:
    cmp dword [esi+EDITOR_CX], 0
    je @f
    TAP_FAIL 'editor_find: cx attendu 0'
@@:
    TAP_OK 'editor_find: parcours circulaire ok'

    push esi
    call editor_free
    add esp, 4

    ; ================= replace_all : verbatim, insensible a la casse =================
    call editor_new
    mov esi, eax
    push mixed_case_str
    push esi
    call type_str
    add esp, 8

    push repl_x
    push needle_chat
    push esi
    call editor_replace_all
    add esp, 12
    cmp eax, 3
    je @f
    TAP_FAIL 'editor_replace_all: attendu 3 remplacements'
@@:
    mov eax, [esi+EDITOR_BUF]
    mov ecx, [eax+BUF_LINES]
    mov eax, [ecx]
    push xxx_str
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'editor_replace_all: attendu "x x x" (verbatim, insensible a la casse)'
@@:
    cmp dword [esi+EDITOR_DIRTY], 0
    jne @f
    TAP_FAIL 'editor_replace_all: dirty doit passer a 1'
@@:
    TAP_OK 'editor_replace_all: verbatim + insensible a la casse ok'

    push esi
    call editor_free
    add esp, 4

    syscall1 SYS_EXIT, 0

segment readable writeable
include '../src/heap_data.inc'

zero_str        db 0
a_str           db 'a', 0
ab_str          db 'ab', 0
digits_str      db '0123456789', 0
ab2_str         db 'ab', 0
upper_str       db 'ABCDEFGHIJ', 0
foo_tab_bar_str db 'foo', 9, 'bar', 0
next_str        db 'next', 0
chat_str        db 'chat', 0
xx_str          db 'xx', 0
needle_chat     db 'chat', 0
mixed_case_str  db 'Chat CHAT chat', 0
repl_x          db 'x', 0
xxx_str         db 'x x x', 0
