; strutil.asm -- utilitaires sur chaines/blocs memoire octet par octet
; (portage a la main des equivalents libc utilises par writhdeck-c :
; memcpy/memmove/memset/strlen/strdup, plus tolower_ascii/ascii_stristr
; qui portent directement common.c:ascii_stristr). Attendu inclus alors
; que le segment "readable executable" est deja actif ; strdup depend
; de malloc (heap.asm), le reste est autonome.

; dword strlen(const char* s) -- cdecl, longueur hors terminateur nul.
strlen:
    proc_enter
    push edi
    mov edi, [ebp+8]
    mov edx, edi
    xor al, al
    mov ecx, 0xFFFFFFFF
    cld
    repne scasb
    mov eax, edi
    sub eax, edx
    dec eax
    pop edi
    proc_leave
    ret

; void* memcpy(void* dst, const void* src, dword len) -- cdecl, renvoie dst.
memcpy:
    proc_enter
    push esi
    push edi
    mov edi, [ebp+8]
    mov esi, [ebp+12]
    mov ecx, [ebp+16]
    cld
    rep movsb
    mov eax, [ebp+8]
    pop edi
    pop esi
    proc_leave
    ret

; void* memmove(void* dst, const void* src, dword len) -- cdecl, gere le
; chevauchement (copie a l'envers si dst > src). Renvoie dst.
memmove:
    proc_enter
    push esi
    push edi
    mov edi, [ebp+8]
    mov esi, [ebp+12]
    mov ecx, [ebp+16]
    cmp edi, esi
    jbe .forward
    ; dst > src : copie de la fin vers le debut, par securite (correct
    ; que les zones se chevauchent ou non)
    add edi, ecx
    dec edi
    add esi, ecx
    dec esi
    std
    rep movsb
    cld
    jmp .done
.forward:
    cld
    rep movsb
.done:
    mov eax, [ebp+8]
    pop edi
    pop esi
    proc_leave
    ret

; void* memset(void* dst, dword val, dword len) -- cdecl, renvoie dst.
memset:
    proc_enter
    push edi
    mov edi, [ebp+8]
    mov eax, [ebp+12]
    mov ecx, [ebp+16]
    cld
    rep stosb
    mov eax, [ebp+8]
    pop edi
    proc_leave
    ret

; char* strdup(const char* s) -- cdecl, copie allouee (malloc) a liberer
; par l'appelant. Suppose s non NULL (jamais appele autrement dans ce
; projet -- voir buffer.asm).
strdup:
    proc_enter
    push esi
    push edi
    push dword [ebp+8]
    call strlen
    add esp, 4
    mov esi, eax             ; esi = longueur (hors nul)
    lea eax, [esi+1]
    push eax
    call malloc
    add esp, 4
    mov edi, eax             ; edi = nouvelle zone
    push esi
    inc dword [esp]          ; longueur a copier = esi+1 (inclut le nul)
    push dword [ebp+8]
    push edi
    call memcpy
    add esp, 12
    mov eax, edi
    pop edi
    pop esi
    proc_leave
    ret

; dword tolower_ascii(dword c) -- cdecl, ne replie que 'A'-'Z' (voir
; common.c:ascii_stristr : comparaison octet par octet, pas UTF-8 aware).
tolower_ascii:
    proc_enter
    mov eax, [ebp+8]
    cmp eax, 'A'
    jl .done
    cmp eax, 'Z'
    jg .done
    add eax, 0x20
.done:
    proc_leave
    ret

; const char* ascii_stristr(const char* hay, const char* needle) -- cdecl.
; needle vide -> renvoie hay. Sinon recherche naive (O(n*m)) insensible
; a la casse ASCII, renvoie un pointeur dans hay ou 0 si absent -- meme
; contrat que common.c:ascii_stristr.
ascii_stristr:
    proc_enter
    push ebx
    push esi
    push edi
    push dword [ebp+12]
    call strlen
    add esp, 4
    mov ebx, eax               ; ebx = longueur de needle
    test ebx, ebx
    jnz .search
    mov eax, [ebp+8]
    jmp .ret
.search:
    mov esi, [ebp+8]           ; esi = p, position courante dans hay
.outer:
    cmp byte [esi], 0
    je .notfound
    xor edi, edi               ; edi = i
.inner:
    cmp edi, ebx
    jge .match
    movzx eax, byte [esi+edi]
    test al, al
    jz .no_match_here
    mov edx, [ebp+12]
    movzx ecx, byte [edx+edi]
    cmp al, 'A'
    jl .al_done
    cmp al, 'Z'
    jg .al_done
    add al, 0x20
.al_done:
    cmp cl, 'A'
    jl .cl_done
    cmp cl, 'Z'
    jg .cl_done
    add cl, 0x20
.cl_done:
    cmp al, cl
    jne .no_match_here
    inc edi
    jmp .inner
.no_match_here:
    inc esi
    jmp .outer
.match:
    mov eax, esi
    jmp .ret
.notfound:
    xor eax, eax
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret
