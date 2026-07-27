; utf8.asm -- portage direct de writhdeck-c/src/utf8.c (decode/encode,
; comptage et conversions colonne<->octet). Toutes les fonctions sont en
; codepoints pour la position logique (colonne curseur) et en octets
; pour le stockage -- voir buffer.asm, qui convertit systematiquement
; via utf8_byte_offset/utf8_char_index a chaque operation.

; dword utf8_seq_len(dword lead_byte) -- cdecl. Pur test de bits sur
; l'octet de tete, pas de table. Retombe sur 1 (repli Latin-1) pour un
; octet de continuation isole ou un octet de tete invalide.
utf8_seq_len:
    proc_enter
    mov eax, [ebp+8]
    and eax, 0xFF
    test eax, 0x80
    jz .one
    mov ecx, eax
    and ecx, 0xE0
    cmp ecx, 0xC0
    jne .try3
    mov eax, 2
    jmp .ret
.try3:
    mov ecx, eax
    and ecx, 0xF0
    cmp ecx, 0xE0
    jne .try4
    mov eax, 3
    jmp .ret
.try4:
    mov ecx, eax
    and ecx, 0xF8
    cmp ecx, 0xF0
    jne .one
    mov eax, 4
    jmp .ret
.one:
    mov eax, 1
.ret:
    proc_leave
    ret

; dword utf8_decode(const char* s, dword* cp_out) -- cdecl, renvoie le
; nombre d'octets consommes (>=1). s[0]==0 -> *cp=0, renvoie 1. Sequence
; de continuation invalide/tronquee -> *cp = octet de tete BRUT (non
; masque), renvoie 1 (un seul octet consomme -- l'appel suivant
; relira a partir de l'octet fautif). Voir le rapport d'exploration
; pour la justification de chaque cas -- portage bit a bit du C.
utf8_decode:
    proc_enter
    sub esp, 4                 ; [ebp-4] = octet de tete brut
    push ebx
    push esi
    push edi

    mov esi, [ebp+8]
    movzx eax, byte [esi]
    test eax, eax
    jnz .not_nul
    mov edi, [ebp+12]
    mov dword [edi], 0
    mov eax, 1
    jmp .ret
.not_nul:
    mov [ebp-4], eax
    mov ebx, eax                ; ebx = octet de tete (pour les tests de bits)
    test ebx, 0x80
    jz .len1
    mov eax, ebx
    and eax, 0xE0
    cmp eax, 0xC0
    jne .try3
    mov edx, ebx
    and edx, 0x1F
    mov ecx, 2
    jmp .haveinit
.try3:
    mov eax, ebx
    and eax, 0xF0
    cmp eax, 0xE0
    jne .try4
    mov edx, ebx
    and edx, 0x0F
    mov ecx, 3
    jmp .haveinit
.try4:
    mov eax, ebx
    and eax, 0xF8
    cmp eax, 0xF0
    jne .len1
    mov edx, ebx
    and edx, 0x07
    mov ecx, 4
    jmp .haveinit
.len1:
    mov edx, ebx
    mov ecx, 1
.haveinit:
    cmp ecx, 1
    je .success
    mov edi, 1                  ; i = 1
.contloop:
    cmp edi, ecx
    jge .success
    movzx eax, byte [esi+edi]
    mov ebx, eax
    and ebx, 0xC0
    cmp ebx, 0x80
    je .cont_ok
    ; continuation invalide -- n'avance que d'un octet, cp = octet de
    ; tete brut
    mov edi, [ebp+12]
    mov eax, [ebp-4]
    mov [edi], eax
    mov eax, 1
    jmp .ret
.cont_ok:
    shl edx, 6
    and eax, 0x3F
    or edx, eax
    inc edi
    jmp .contloop
.success:
    mov ebx, [ebp+12]
    mov [ebx], edx
    mov eax, ecx
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; dword utf8_encode(dword cp, char* out) -- cdecl, renvoie le nombre
; d'octets ecrits (1 a 4). N'ecrit PAS de terminateur nul.
utf8_encode:
    proc_enter
    push ebx
    push edi
    mov eax, [ebp+8]
    mov edi, [ebp+12]
    cmp eax, 0x80
    jb .one
    cmp eax, 0x800
    jb .two
    cmp eax, 0x10000
    jb .three
    jmp .four
.one:
    mov [edi], al
    mov eax, 1
    jmp .ret
.two:
    mov ebx, eax
    shr ebx, 6
    or ebx, 0xC0
    mov [edi], bl
    mov ecx, eax
    and ecx, 0x3F
    or ecx, 0x80
    mov [edi+1], cl
    mov eax, 2
    jmp .ret
.three:
    mov ebx, eax
    shr ebx, 12
    or ebx, 0xE0
    mov [edi], bl
    mov ebx, eax
    shr ebx, 6
    and ebx, 0x3F
    or ebx, 0x80
    mov [edi+1], bl
    mov ecx, eax
    and ecx, 0x3F
    or ecx, 0x80
    mov [edi+2], cl
    mov eax, 3
    jmp .ret
.four:
    mov ebx, eax
    shr ebx, 18
    or ebx, 0xF0
    mov [edi], bl
    mov ebx, eax
    shr ebx, 12
    and ebx, 0x3F
    or ebx, 0x80
    mov [edi+1], bl
    mov ebx, eax
    shr ebx, 6
    and ebx, 0x3F
    or ebx, 0x80
    mov [edi+2], bl
    mov ecx, eax
    and ecx, 0x3F
    or ecx, 0x80
    mov [edi+3], cl
    mov eax, 4
.ret:
    pop edi
    pop ebx
    proc_leave
    ret

; dword utf8_strlen(const char* s) -- cdecl, compte les codepoints en
; marchant par utf8_seq_len (PAS de validation des octets de
; continuation, contrairement a utf8_decode) ; une sequence tronquee en
; fin de chaine est bornee a 1 caractere restant.
utf8_strlen:
    proc_enter
    sub esp, 4                  ; [ebp-4] = n
    push ebx
    push esi
    push edi
    push dword [ebp+8]
    call strlen
    add esp, 4
    mov ebx, eax                 ; total
    mov esi, [ebp+8]
    xor edi, edi                 ; i
    mov dword [ebp-4], 0
.loop:
    cmp edi, ebx
    jge .done
    movzx eax, byte [esi+edi]
    push eax
    call utf8_seq_len
    add esp, 4
    mov ecx, ebx
    sub ecx, edi
    cmp eax, ecx
    jbe .lenok
    mov eax, 1
.lenok:
    add edi, eax
    inc dword [ebp-4]
    jmp .loop
.done:
    mov eax, [ebp-4]
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; dword utf8_byte_offset(const char* s, dword char_index) -- cdecl,
; renvoie l'offset en octets du char_index-ieme codepoint (meme
; troncature de secours que utf8_strlen). char_index == utf8_strlen(s)
; renvoie la fin de chaine.
utf8_byte_offset:
    proc_enter
    sub esp, 4                   ; [ebp-4] = n
    push ebx
    push esi
    push edi
    push dword [ebp+8]
    call strlen
    add esp, 4
    mov ebx, eax                  ; total
    mov esi, [ebp+8]
    xor edi, edi                  ; i
    mov dword [ebp-4], 0
.loop:
    mov eax, [ebp-4]
    cmp eax, [ebp+12]
    jge .done
    cmp edi, ebx
    jge .done
    movzx eax, byte [esi+edi]
    push eax
    call utf8_seq_len
    add esp, 4
    mov ecx, ebx
    sub ecx, edi
    cmp eax, ecx
    jbe .lenok
    mov eax, 1
.lenok:
    add edi, eax
    inc dword [ebp-4]
    jmp .loop
.done:
    mov eax, edi
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; dword utf8_char_index(const char* s, dword byte_offset) -- cdecl,
; inverse de utf8_byte_offset : un byte_offset tombant au milieu d'une
; sequence multi-octets est traite comme juste apres le dernier
; caractere complet avant lui. byte_offset > strlen(s) est borne a
; strlen(s).
utf8_char_index:
    proc_enter
    sub esp, 8                    ; [ebp-4]=n, [ebp-8]=i
    push ebx
    push esi
    push edi
    push dword [ebp+8]
    call strlen
    add esp, 4
    mov ebx, eax                   ; total
    mov esi, [ebp+8]
    mov edi, [ebp+12]                ; byte_offset (cible, constante)
    cmp edi, ebx
    jbe .clamped
    mov edi, ebx
.clamped:
    mov dword [ebp-4], 0
    mov dword [ebp-8], 0
.loop:
    mov eax, [ebp-8]
    cmp eax, ebx
    jge .done
    movzx ecx, byte [esi+eax]
    push ecx
    call utf8_seq_len
    add esp, 4
    mov ecx, ebx
    sub ecx, dword [ebp-8]
    cmp eax, ecx
    jbe .lenok
    mov eax, 1
.lenok:
    mov ecx, [ebp-8]
    add ecx, eax
    cmp ecx, edi
    jg .done
    mov [ebp-8], ecx
    inc dword [ebp-4]
    jmp .loop
.done:
    mov eax, [ebp-4]
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret
