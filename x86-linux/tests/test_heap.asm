; test_heap.asm -- verifie malloc/free/realloc (heap.asm) : reutilisation
; first-fit d'un bloc libere, coalescing avant a la liberation, et
; realloc (agrandissement avec preservation du contenu).
format ELF executable
entry _start

include '../src/sys.inc'
include '../src/macros.inc'

segment readable executable

include 'tap.inc'
include '../src/heap.asm'

_start:
    ; --- 1) malloc renvoie des pointeurs distincts et croissants ---
    push 10
    call malloc
    add esp, 4
    mov esi, eax                ; esi = ptr1

    push 20
    call malloc
    add esp, 4
    mov edi, eax                ; edi = ptr2

    cmp edi, esi
    ja .distinct_ok
    TAP_FAIL 'malloc: ptr2 doit suivre ptr1'
.distinct_ok:
    TAP_OK 'malloc: deux allocations distinctes'

    ; --- 2) free(ptr1) puis malloc d'une taille compatible reutilise ptr1 ---
    push esi
    call free
    add esp, 4

    push 8
    call malloc
    add esp, 4
    mov ebx, eax                  ; ebx = ptr3 -- capture avant TAP_OK,
                                   ; qui ecrase eax (retour du write())
    cmp ebx, esi
    je .reuse_ok
    TAP_FAIL 'malloc: devrait reutiliser le bloc libere (first-fit)'
.reuse_ok:
    TAP_OK 'malloc: reutilisation first-fit apres free'

    ; --- 3) coalescing avant : liberer ptr3 (== ptr1) puis ptr2 doit
    ; fusionner en un seul bloc libre assez grand pour 10+8+20 = 38 ---
    push ebx
    call free
    add esp, 4
    push edi
    call free
    add esp, 4

    push 30
    call malloc
    add esp, 4
    cmp eax, ebx
    je .coalesce_ok
    TAP_FAIL 'free: les blocs adjacents liberes devraient avoir fusionne'
.coalesce_ok:
    TAP_OK 'free: coalescing avant fonctionne'

    ; --- 4) realloc preserve le contenu lors d'un agrandissement ---
    push 4
    call malloc
    add esp, 4
    mov esi, eax                 ; esi = ptr
    mov dword [esi], 0x44434241  ; 'ABCD' (little endian)

    ; bloque la reutilisation immediate en allouant un voisin, pour
    ; forcer realloc a passer par malloc+copie+free (chemin le plus
    ; risque a valider)
    push 4
    call malloc
    add esp, 4
    mov edi, eax

    push 64
    push esi
    call realloc
    add esp, 8
    mov ebx, eax                  ; ebx = nouveau pointeur

    cmp dword [ebx], 0x44434241
    je .realloc_ok
    TAP_FAIL 'realloc: le contenu original doit etre preserve'
.realloc_ok:
    TAP_OK 'realloc: contenu preserve apres agrandissement'

    syscall1 SYS_EXIT, 0

segment readable writeable
include '../src/heap_data.inc'
