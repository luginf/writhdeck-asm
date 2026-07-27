; heap.asm -- allocateur malloc/free/realloc, base sur brk, liste
; implicite style K&R (voir plan). En-tete de bloc, 8 octets contigus
; juste avant chaque zone utile renvoyee a l'appelant :
;   [bloc+0] size  (dword) -- taille utile (hors en-tete), multiple de 4
;   [bloc+4] used  (dword) -- 0 = libre, 1 = occupe
; Les blocs sont contigus en memoire entre [heap_start] et [heap_end]
; (le "brk" courant). Stockage de heap_start/heap_end/heap_inited dans
; heap_data.inc (a inclure une fois, dans un segment "readable
; writeable").
;
; first-fit a l'allocation, coalescing AVANT seulement a la liberation
; (pas de coalescing arriere, pas de best-fit, pas de split au malloc --
; suffisant pour ce cas d'usage, voir plan). Attendu : ce fichier est
; inclus alors que le segment "readable executable" est deja actif.

HDR_SIZE = 8

; dword heap_set_brk(dword desired) -- cdecl. Enveloppe sys_brk : renvoie
; le brk reellement obtenu (Linux ne renvoie jamais -1, brk(0) renvoie
; simplement la valeur courante si la demande echoue -- pas de gestion
; d'erreur "out of memory" a ce stade).
heap_set_brk:
    proc_enter
    push ebx
    mov ebx, [ebp+8]
    mov eax, SYS_BRK
    int 0x80
    pop ebx
    proc_leave
    ret

; void heap_ensure_init(void) -- initialise heap_start/heap_end au brk
; courant, une seule fois (garde par heap_inited).
heap_ensure_init:
    proc_enter
    cmp byte [heap_inited], 0
    jne .done
    push 0
    call heap_set_brk
    add esp, 4
    mov [heap_start], eax
    mov [heap_end], eax
    mov byte [heap_inited], 1
.done:
    proc_leave
    ret

; void* malloc(dword size) -- cdecl, [ebp+8] = size demandee
malloc:
    proc_enter
    push ebx
    push esi
    push edi

    call heap_ensure_init

    mov eax, [ebp+8]
    add eax, 3
    and eax, 0xFFFFFFFC        ; arrondi a un multiple de 4
    test eax, eax
    jnz .sizeok
    mov eax, 4                 ; taille minimale non nulle
.sizeok:
    mov esi, eax               ; esi = taille demandee (alignee)

    mov ebx, [heap_start]
.scan:
    cmp ebx, [heap_end]
    jae .extend
    mov eax, [ebx]             ; eax = taille du bloc courant
    cmp dword [ebx+4], 0
    jne .scan_next
    cmp eax, esi
    jb .scan_next
    ; bloc libre assez grand -- reutilisation directe (pas de split)
    mov dword [ebx+4], 1
    lea eax, [ebx+HDR_SIZE]
    jmp .ret
.scan_next:
    lea ebx, [ebx+HDR_SIZE+eax]
    jmp .scan

.extend:
    ; aucun bloc libre convenable : nouveau bloc en fin de tas. Il faut
    ; d'abord etendre reellement le brk (sys_brk) -- ecrire l'en-tete
    ; AVANT l'extension ecrirait dans une page pas encore mappee.
    mov ebx, [heap_end]
    lea eax, [ebx+HDR_SIZE+esi]
    push eax
    call heap_set_brk
    add esp, 4
    mov [heap_end], eax
    mov [ebx], esi
    mov dword [ebx+4], 1
    lea eax, [ebx+HDR_SIZE]

.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void free(void* ptr) -- cdecl, [ebp+8] = ptr (NULL accepte, no-op).
; Marque le bloc libre puis relance un passage complet de coalescing
; sur tout le tas (voir heap_coalesce_all) : un simple coalescing "vers
; l'avant" limite au bloc qu'on vient de liberer ne fusionnerait JAMAIS
; deux blocs adjacents libres quand celui de gauche a ete libere avant
; celui de droite (cas courant : liberations dans l'ordre d'adresse
; croissante) -- le passage complet couvre ce cas, cout negligeable a
; l'echelle de ce projet (quelques centaines de blocs au plus).
free:
    proc_enter
    mov eax, [ebp+8]
    test eax, eax
    jz .done
    lea eax, [eax-HDR_SIZE]
    mov dword [eax+4], 0
    call heap_coalesce_all
.done:
    proc_leave
    ret

; void heap_coalesce_all(void) -- fusionne toute paire de blocs libres
; adjacents, en un seul passage gauche->droite (une fusion ne fait pas
; avancer le curseur : elle peut re-creer une nouvelle paire fusionnable
; avec le bloc encore plus a droite).
heap_coalesce_all:
    proc_enter
    push ebx
    push esi
    mov ebx, [heap_start]
.scan:
    cmp ebx, [heap_end]
    jae .done
    lea esi, [ebx+HDR_SIZE]
    add esi, [ebx]                ; esi = adresse du bloc suivant
    cmp esi, [heap_end]
    jae .advance
    cmp dword [ebx+4], 0
    jne .advance
    cmp dword [esi+4], 0
    jne .advance
    mov ecx, [esi]
    add ecx, HDR_SIZE
    add [ebx], ecx                 ; fusion -- ne pas avancer ebx
    jmp .scan
.advance:
    mov ebx, esi
    jmp .scan
.done:
    pop esi
    pop ebx
    proc_leave
    ret

; void heap_copy_bytes(void* dst, void* src, dword len) -- cdecl, copie
; octet par octet (utilise par realloc, evite toute dependance vers
; strutil.asm/memcpy a ce stade).
heap_copy_bytes:
    proc_enter
    push esi
    push edi
    mov edi, [ebp+8]
    mov esi, [ebp+12]
    mov ecx, [ebp+16]
    cld
    rep movsb
    pop edi
    pop esi
    proc_leave
    ret

; void* realloc(void* ptr, dword new_size) -- cdecl
; ptr==NULL -> equivaut a malloc(new_size). new_size==0 -> free(ptr),
; renvoie NULL. Retrecissement : garde le meme pointeur (pas de split).
; Agrandissement : absorbe les blocs libres contigus qui suivent tant
; que necessaire ; si ca ne suffit pas, malloc+copie+free.
realloc:
    proc_enter
    sub esp, 4                 ; [ebp-4] = taille utile d'origine (local)
    push ebx
    push esi
    push edi

    mov eax, [ebp+8]           ; ptr
    test eax, eax
    jnz .ptr_ok
    push dword [ebp+12]
    call malloc
    add esp, 4
    jmp .ret
.ptr_ok:
    mov esi, eax               ; esi = ptr
    mov eax, [ebp+12]          ; new_size
    test eax, eax
    jnz .newsize_ok
    push esi
    call free
    add esp, 4
    xor eax, eax
    jmp .ret
.newsize_ok:
    add eax, 3
    and eax, 0xFFFFFFFC
    test eax, eax
    jnz .have_new
    mov eax, 4
.have_new:
    mov edi, eax                ; edi = taille demandee, alignee

    lea ebx, [esi-HDR_SIZE]
    mov eax, [ebx]              ; taille utile actuelle du bloc
    cmp edi, eax
    jbe .keep                   ; deja assez grand -- meme pointeur

    mov [ebp-4], eax            ; memorise la taille utile d'origine

.absorb:
    mov eax, [ebx]
    cmp eax, edi
    jae .grow_ok
    lea ecx, [ebx+HDR_SIZE+eax]  ; bloc suivant
    cmp ecx, [heap_end]
    jae .grow_fail
    cmp dword [ecx+4], 0
    jne .grow_fail
    mov edx, [ecx]
    add edx, HDR_SIZE
    add [ebx], edx
    jmp .absorb

.grow_ok:
    mov eax, esi
    jmp .ret

.grow_fail:
    push edi
    call malloc
    add esp, 4
    mov edi, eax                 ; edi = nouveau pointeur
    push dword [ebp-4]
    push esi
    push edi
    call heap_copy_bytes
    add esp, 12
    push esi
    call free
    add esp, 4
    mov eax, edi
    jmp .ret

.keep:
    mov eax, esi

.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret
