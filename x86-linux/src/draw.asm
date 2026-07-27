; draw.asm -- construction de la barre de statut minimale et dessin de
; l'ecran d'edition (word-wrap + defilement). Utilise par main.asm ;
; separe dans son propre module pour pouvoir etre exercee par un test
; sans terminal reel (voir tests/test_draw.asm). Depend de buffer.asm,
; editor.asm, utf8.asm, strutil.asm, ui_ansi.asm -- attendu inclus alors
; que le segment "readable executable" est deja actif. Donnees dans
; draw_data.inc (status_buf + libelles).

; dword num_to_ascii(dword n, char* out) -- cdecl. Ecrit les chiffres
; decimaux de n (n >= 0) a out, SANS terminateur nul. Renvoie le nombre
; d'octets ecrits.
num_to_ascii:
    proc_enter
    sub esp, 12
    push ebx
    push esi
    push edi
    mov eax, [ebp+8]
    mov edi, [ebp+12]
    mov esi, 12
    test eax, eax
    jnz .loop
    dec esi
    mov byte [ebp+esi-12], '0'
    jmp .done
.loop:
    test eax, eax
    jz .done
    xor edx, edx
    mov ebx, 10
    div ebx
    add edx, '0'
    dec esi
    mov [ebp+esi-12], dl
    jmp .loop
.done:
    mov ecx, 12
    sub ecx, esi
    mov ebx, ecx                ; sauvegarder la longueur AVANT l'appel :
                                 ; memcpy charge son 3e argument (la taille)
                                 ; dans ECX pour rep movsb, qui le laisse a
                                 ; 0 en sortie -- ecx n'est PAS preserve
                                 ; par convention (voir macros.inc), donc
                                 ; le relire apres l'appel serait errone.
    push ecx
    lea eax, [ebp+esi-12]
    push eax
    push edi
    call memcpy
    add esp, 12
    mov eax, ebx
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; char* sb_append_str(char* dst, const char* src) -- cdecl. Copie
; strlen(src) octets de src vers dst, renvoie dst+len (nouveau curseur
; d'ecriture). Centralise ce calcul precisement parce que memcpy()
; ecrase eax avec SA propre valeur de retour (dst, pas une longueur) --
; enchainer "call strlen puis, apres un call memcpy, reutiliser eax
; comme si c'etait toujours la longueur" est un piege reel (corrige ici
; une fois pour toutes plutot qu'a chaque site d'appel).
sb_append_str:
    proc_enter
    sub esp, 4                  ; [ebp-4] = longueur
    push ebx
    mov ebx, [ebp+8]
    push dword [ebp+12]
    call strlen
    add esp, 4
    mov [ebp-4], eax
    push eax
    push dword [ebp+12]
    push ebx
    call memcpy
    add esp, 12
    mov eax, ebx
    add eax, [ebp-4]
    pop ebx
    proc_leave
    ret

; void build_status_line(editor_t* ed, char* out) -- cdecl. Construit
; "<basename ou [draft]> | line X/Y col Z[ *]" (nul-termine) dans out
; (doit pouvoir contenir au moins ~280 octets -- voir status_buf).
build_status_line:
    proc_enter
    sub esp, 4                  ; [ebp-4] = longueur du basename (chemin present)
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]

    cmp dword [esi+EDITOR_FILEPATH], 0
    jne .have_path
    push draft_label
    push edi
    call sb_append_str
    add esp, 8
    mov edi, eax
    jmp .after_name
.have_path:
    ; basename : dernier '/' + 1, ou le debut du chemin si aucun --
    ; copie directe (longueur explicite, pas de nul dans le milieu de la
    ; chaine source) donc pas besoin de sb_append_str ici.
    push dword [esi+EDITOR_FILEPATH]
    call strlen
    add esp, 4
    mov ebx, [esi+EDITOR_FILEPATH]
    add ebx, eax                       ; ebx = fin de chaine
    mov ecx, ebx
.find_slash:
    cmp ecx, [esi+EDITOR_FILEPATH]
    jle .have_basename
    cmp byte [ecx-1], '/'
    je .have_basename
    dec ecx
    jmp .find_slash
.have_basename:
    mov eax, ebx
    sub eax, ecx
    mov [ebp-4], eax             ; longueur sauvegardee AVANT l'appel : ecx
                                  ; (utilise ici comme pointeur source) est
                                  ; l'un des arguments de memcpy, donc PAS
                                  ; fiable apres l'appel (voir num_to_ascii).
    push eax
    push ecx
    push edi
    call memcpy
    add esp, 12
    mov eax, [ebp-4]
    add edi, eax
.after_name:

    push sep1_label
    push edi
    call sb_append_str
    add esp, 8
    mov edi, eax

    mov eax, [esi+EDITOR_CY]
    inc eax
    push edi
    push eax
    call num_to_ascii
    add esp, 8
    add edi, eax

    push slash_label
    push edi
    call sb_append_str
    add esp, 8
    mov edi, eax

    mov eax, [esi+EDITOR_BUF]
    mov eax, [eax+BUF_COUNT]
    push edi
    push eax
    call num_to_ascii
    add esp, 8
    add edi, eax

    push col_label
    push edi
    call sb_append_str
    add esp, 8
    mov edi, eax

    mov eax, [esi+EDITOR_CX]
    inc eax
    push edi
    push eax
    call num_to_ascii
    add esp, 8
    add edi, eax

    cmp dword [esi+EDITOR_DIRTY], 0
    je .no_star
    push star_label
    push edi
    call sb_append_str
    add esp, 8
    mov edi, eax
.no_star:
    mov byte [edi], 0

    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void draw_editor(editor_t* ed, dword cols, dword rows) -- cdecl.
draw_editor:
    proc_enter
    sub esp, 48                  ; -4 usable -8 wrows -12 wcount
                                  ; -16 cursor_vrow -20 screen_row
                                  ; -24 cur_scr_row -28 cur_scr_col -32 i
                                  ; -36 start_char -40 len_chars
                                  ; -44 line_ptr -48 byte_start
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]                ; ed

    mov eax, [ebp+16]
    dec eax
    mov [ebp-4], eax                   ; usable = rows-1

    lea eax, [ebp-12]
    push eax
    lea eax, [ebp-8]
    push eax
    push dword [ebp+12]                  ; cols = largeur de wrap
    push esi
    call editor_wrap
    add esp, 16

    mov eax, [esi+EDITOR_CX]
    push eax
    mov eax, [esi+EDITOR_CY]
    push eax
    push dword [ebp-12]
    push dword [ebp-8]
    call editor_cursor_visual_row
    add esp, 16
    mov [ebp-16], eax                     ; cursor_vrow

    mov ecx, [esi+EDITOR_SCROLL]
    mov eax, [ebp-16]
    cmp eax, ecx
    jge .not_below
    mov [esi+EDITOR_SCROLL], eax
    jmp .scroll_clamped
.not_below:
    mov ecx, [esi+EDITOR_SCROLL]
    add ecx, [ebp-4]
    cmp eax, ecx
    jl .scroll_clamped
    mov ecx, eax
    sub ecx, [ebp-4]
    inc ecx
    mov [esi+EDITOR_SCROLL], ecx
.scroll_clamped:
    cmp dword [esi+EDITOR_SCROLL], 0
    jge .scroll_ok
    mov dword [esi+EDITOR_SCROLL], 0
.scroll_ok:

    mov dword [ebp-20], 0                 ; screen_row
    mov dword [ebp-24], -1                  ; cursor_screen_row
    mov dword [ebp-28], -1                    ; cursor_screen_col
    mov eax, [esi+EDITOR_SCROLL]
    mov [ebp-32], eax                          ; i

.draw_loop:
    mov eax, [ebp-32]
    cmp eax, [ebp-12]
    jge .draw_done
    mov eax, [ebp-20]
    cmp eax, [ebp-4]
    jge .draw_done

    mov eax, [ebp-32]
    imul eax, eax, WRAP_ROW_SIZE
    add eax, [ebp-8]                        ; eax = &wrows[i]
    mov ebx, [eax]                            ; logical_line
    mov ecx, [eax+4]                            ; start_char
    mov [ebp-36], ecx
    mov edx, [eax+8]                              ; len_chars
    mov [ebp-40], edx

    mov eax, [esi+EDITOR_BUF]
    mov eax, [eax+BUF_LINES]
    mov eax, [eax+ebx*4]
    mov [ebp-44], eax                          ; line_ptr

    push dword [ebp-36]
    push dword [ebp-44]
    call utf8_byte_offset
    add esp, 8
    mov [ebp-48], eax                            ; byte_start

    push dword [ebp-20]
    call ui_clear_line
    add esp, 4

    push UI_ATTR_NORMAL
    push dword [ebp-40]
    mov eax, [ebp-44]
    add eax, [ebp-48]
    push eax
    push 0
    push dword [ebp-20]
    call ui_put_str
    add esp, 20

    mov eax, [ebp-32]
    cmp eax, [ebp-16]
    jne .not_cursor_row
    mov eax, [ebp-20]
    mov [ebp-24], eax
    mov eax, [esi+EDITOR_CX]
    sub eax, [ebp-36]
    mov [ebp-28], eax
.not_cursor_row:

    inc dword [ebp-20]
    inc dword [ebp-32]
    jmp .draw_loop
.draw_done:

    push dword [ebp-8]
    call free
    add esp, 4

.clear_rest:
    mov eax, [ebp-20]
    cmp eax, [ebp-4]
    jge .status_bar
    push eax
    call ui_clear_line
    add esp, 4
    inc dword [ebp-20]
    jmp .clear_rest

.status_bar:
    push status_buf
    push esi
    call build_status_line
    add esp, 8
    mov eax, [ebp+16]
    dec eax
    push UI_ATTR_REVERSE
    mov ecx, [ebp+12]
    push ecx
    push status_buf
    push 0
    push eax
    call ui_put_str
    add esp, 20
    ; (ui_put_str efface deja la ligne avant d'ecrire -- pas besoin d'un
    ; ui_clear_line separe ici, qui effacerait ce qu'on vient de dessiner)

    cmp dword [ebp-24], 0
    jl .no_cursor
    push dword [ebp-28]
    push dword [ebp-24]
    call ui_set_cursor
    add esp, 8
.no_cursor:
    call ui_refresh

    pop edi
    pop esi
    pop ebx
    proc_leave
    ret
