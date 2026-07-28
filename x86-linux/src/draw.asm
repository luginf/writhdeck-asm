; draw.asm -- construction de la barre de statut et dessin de l'ecran
; d'edition (word-wrap + defilement + marges + coloration syntaxique).
; Utilise par main.asm ; separe dans son propre module pour pouvoir
; etre exerce par un test sans terminal reel (voir tests/test_draw.asm).
; Depend de buffer.asm, editor.asm, utf8.asm, strutil.asm, ui_ansi.asm,
; highlight.asm (classify_line, coloration) -- attendu inclus alors que
; le segment "readable executable" est deja actif. Marges
; (g_cfg_margin_cols/rows) et objectif de mots (g_cfg_word_goal) lus
; par config.asm (voir README, section ".ini config (partial)") --
; config.asm est inclus APRES ce fichier (il appelle sb_append_str,
; defini ici). Donnees dans draw_data.inc (status_buf + libelles).

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

; status_fields_t minimal -- portage de common.h:status_fields_t, sans
; les champs timer_active/timer_seconds/chrono_show (pas de timer.c
; dans ce portage, voir README -- le token "timer" est donc traite
; comme un no-op, jamais comme une vraie horloge de decompte).
SF_FILENAME = 0   ; pointeur nul-termine (suffixe de EDITOR_FILEPATH), ou 0 pour un brouillon
SF_DIRTY    = 4
SF_LINE1    = 8
SF_TOTAL    = 12
SF_COL1     = 16
SF_WORDS    = 20
SF_CHARS    = 24
SF_GOAL     = 28
SF_SIZE     = 32

; dword st__tok_is(const char* tok_ptr, dword tok_len, const char* literal)
; -- cdecl. 1 si les tok_len octets de tok_ptr sont EXACTEMENT egaux a
; literal (meme longueur, pas juste un prefixe) -- aide de dispatch
; pour build_status_tokens ci-dessous.
st__tok_is:
    proc_enter
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+16]
    push edi
    call strlen                 ; ecx est caller-saved -- strlen l'ecrase
                                  ; en interne (compteur de repne scasb,
                                  ; voir strutil.asm) : ne JAMAIS y charger
                                  ; tok_len avant cet appel (bug reel
                                  ; rencontre en testant, voir memoire
                                  ; projet "ecx-clobber-gotcha"). Relu
                                  ; depuis [ebp+12] APRES l'appel, ebp
                                  ; n'etant lui jamais perturbe.
    add esp, 4
    cmp eax, [ebp+12]
    jne .false
    mov ecx, [ebp+12]
    xor edx, edx
.loop:
    cmp edx, ecx
    jge .true
    mov al, [esi+edx]
    mov ah, [edi+edx]
    cmp al, ah
    jne .false
    inc edx
    jmp .loop
.true:
    mov eax, 1
    jmp .ret
.false:
    xor eax, eax
.ret:
    pop edi
    pop esi
    proc_leave
    ret

; void st__append_piece(char* out, dword outsz, dword* used_ptr,
;                        const char* piece) -- cdecl. Ajoute piece a
; *out (borne a outsz, nul-termine toujours dans les bornes), avance
; *used_ptr d'autant -- portage direct de common.c:append_bounded.
st__append_piece:
    proc_enter
    push ebx
    push esi
    push edi
    mov edi, [ebp+8]            ; out
    mov ebx, [ebp+12]            ; outsz
    mov esi, [ebp+16]             ; used_ptr

    push dword [ebp+20]
    call strlen
    add esp, 4
    mov ecx, eax                  ; plen

    mov edx, [esi]                 ; used (charge APRES l'appel a strlen,
                                     ; qui ne preserve pas edx -- voir
                                     ; strutil.asm:strlen)
    mov eax, edx
    add eax, ecx
    cmp eax, ebx
    jl .plen_ok
    cmp edx, ebx
    jl .trunc_avail
    xor ecx, ecx
    jmp .plen_ok
.trunc_avail:
    mov ecx, ebx
    sub ecx, edx
    dec ecx
.plen_ok:
    cmp ecx, 0
    jle .skip_copy
    lea eax, [edi+edx]
    add edx, ecx
    mov [esi], edx                ; used mis a jour AVANT l'appel : eax/ecx/edx
                                    ; ne sont pas fiables apres memcpy (caller-saved)
    push ecx
    push dword [ebp+20]
    push eax
    call memcpy
    add esp, 12
.skip_copy:
    mov eax, [esi]
    cmp eax, ebx
    jl .idx_ok
    mov eax, ebx
    dec eax
.idx_ok:
    add eax, edi
    mov byte [eax], 0

    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; char* st__append_clock(char* dst) -- cdecl. Ecrit "  HH:MM" (heure
; UTC, deux espaces de tete comme les autres tokens) a dst, nul-termine,
; renvoie dst+len (meme convention que sb_append_str). Simplification
; assumee par rapport au C (qui affiche l'heure LOCALE via localtime_r) :
; pas de base de donnees de fuseaux horaires/TZ dans ce portage minimal
; -- afficher l'heure UTC directement est le compromis le plus simple
; et le moins susceptible de mentir silencieusement.
st__append_clock:
    proc_enter
    sub esp, 4                   ; [ebp-4] = minutes
    push ebx
    push esi
    push edi
    mov edi, [ebp+8]

    syscall1 SYS_TIME, 0          ; eax = secondes depuis epoch (UTC)
    xor edx, edx
    mov ecx, 86400
    div ecx                        ; edx = secondes depuis minuit UTC
    mov eax, edx
    xor edx, edx
    mov ecx, 3600
    div ecx                         ; eax = heures, edx = reste
    mov esi, eax                     ; heures
    mov eax, edx
    xor edx, edx
    mov ecx, 60
    div ecx                           ; eax = minutes
    mov [ebp-4], eax

    mov byte [edi], ' '
    mov byte [edi+1], ' '
    add edi, 2

    cmp esi, 10
    jge .h_no_pad
    mov byte [edi], '0'
    inc edi
.h_no_pad:
    push edi
    push esi
    call num_to_ascii
    add esp, 8
    add edi, eax

    mov byte [edi], ':'
    inc edi

    mov eax, [ebp-4]
    cmp eax, 10
    jge .m_no_pad
    mov byte [edi], '0'
    inc edi
.m_no_pad:
    push edi
    push dword [ebp-4]
    call num_to_ascii
    add esp, 8
    add edi, eax

    mov byte [edi], 0
    mov eax, edi

    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void build_status_tokens(char* out, dword outsz, const char* tokens,
;                           const void* fields /* status_fields_t* */)
; -- cdecl. Construit UNE zone (left/center/right) de la barre de
; statut a partir d'une liste de tokens espace-separee -- portage de
; common.c:build_status_tokens. Tokens reconnus : filename dirty ln col
; words chars goal clock space -- workspace/sel/help_bar/timer sont
; acceptes mais sans effet (pas de second workspace, pas de selection
; de texte, pas de zone d'aide separee, pas de minuteur dans ce portage
; -- voir README). Tout autre token est recopie tel quel (separateurs
; personnalises, ex. "|"). NE MUTE PAS tokens (contrairement au C, qui
; passe par un strdup+strtok jetable) : tokens peut donc pointer
; directement vers un litteral en lecture seule (default_status_left...)
; aussi bien que vers une valeur .ini heap-allouee.
build_status_tokens:
    proc_enter
    sub esp, 12                  ; -4 used -8 p -12 tok_len
    push ebx
    push esi
    push edi

    mov eax, [ebp+8]
    mov byte [eax], 0
    cmp dword [ebp+12], 0
    jne .outsz_ok
    jmp .all_done
.outsz_ok:
    mov dword [ebp-4], 0
    mov eax, [ebp+16]
    mov [ebp-8], eax

.next_token:
    mov esi, [ebp-8]
.skip_ws:
    mov al, [esi]
    cmp al, ' '
    je .ws1
    cmp al, 9
    je .ws1
    jmp .ws_done
.ws1:
    inc esi
    jmp .skip_ws
.ws_done:
    cmp byte [esi], 0
    jne .have_token
    jmp .all_done
.have_token:
    mov edi, esi
.find_end:
    mov al, [edi]
    test al, al
    jz .have_end
    cmp al, ' '
    je .have_end
    cmp al, 9
    je .have_end
    inc edi
    jmp .find_end
.have_end:
    mov ecx, edi
    sub ecx, esi
    mov [ebp-12], ecx             ; tok_len (esi = tok_start, callee-saved)
    mov byte [st_piece_buf], 0

    mov ecx, [ebp-12]
    push str_tok_filename
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jz .try_dirty
    mov eax, [ebp+20]
    mov eax, [eax+SF_FILENAME]
    test eax, eax
    jnz .fname_have
    mov eax, draft_label
.fname_have:
    push eax
    push st_piece_buf
    call sb_append_str
    add esp, 8
    mov byte [eax], 0
    jmp .dispatch_done

.try_dirty:
    mov ecx, [ebp-12]
    push str_tok_dirty
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jz .try_ln
    mov eax, [ebp+20]
    cmp dword [eax+SF_DIRTY], 0
    je .dispatch_done
    push dirty_suffix
    push st_piece_buf
    call sb_append_str
    add esp, 8
    mov byte [eax], 0
    jmp .dispatch_done

.try_ln:
    mov ecx, [ebp-12]
    push str_tok_ln
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jz .try_col
    push ln_prefix
    push st_piece_buf
    call sb_append_str
    add esp, 8
    mov edi, eax
    mov eax, [ebp+20]
    mov eax, [eax+SF_LINE1]
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
    mov eax, [ebp+20]
    mov eax, [eax+SF_TOTAL]
    push edi
    push eax
    call num_to_ascii
    add esp, 8
    add edi, eax
    mov byte [edi], 0
    jmp .dispatch_done

.try_col:
    mov ecx, [ebp-12]
    push str_tok_col
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jz .try_words
    push col_prefix
    push st_piece_buf
    call sb_append_str
    add esp, 8
    mov edi, eax
    mov eax, [ebp+20]
    mov eax, [eax+SF_COL1]
    push edi
    push eax
    call num_to_ascii
    add esp, 8
    mov ecx, eax
    add edi, eax
    cmp ecx, 3
    jge .col_no_pad
    mov ebx, 3
    sub ebx, ecx
.col_pad_loop:
    cmp ebx, 0
    jle .col_no_pad
    mov byte [edi], ' '
    inc edi
    dec ebx
    jmp .col_pad_loop
.col_no_pad:
    mov byte [edi], 0
    jmp .dispatch_done

.try_words:
    mov ecx, [ebp-12]
    push str_tok_words
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jz .try_chars
    push sb_two_spaces
    push st_piece_buf
    call sb_append_str
    add esp, 8
    mov edi, eax
    mov eax, [ebp+20]
    mov eax, [eax+SF_WORDS]
    push edi
    push eax
    call num_to_ascii
    add esp, 8
    add edi, eax
    mov byte [edi], 'w'
    inc edi
    mov byte [edi], 0
    jmp .dispatch_done

.try_chars:
    mov ecx, [ebp-12]
    push str_tok_chars
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jz .try_goal
    push sb_two_spaces
    push st_piece_buf
    call sb_append_str
    add esp, 8
    mov edi, eax
    mov eax, [ebp+20]
    mov eax, [eax+SF_CHARS]
    push edi
    push eax
    call num_to_ascii
    add esp, 8
    add edi, eax
    mov byte [edi], 'c'
    inc edi
    mov byte [edi], 0
    jmp .dispatch_done

.try_goal:
    mov ecx, [ebp-12]
    push str_tok_goal
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jz .try_clock
    mov eax, [ebp+20]
    cmp dword [eax+SF_GOAL], 0
    jle .dispatch_done
    push sb_two_spaces
    push st_piece_buf
    call sb_append_str
    add esp, 8
    mov edi, eax
    mov eax, [ebp+20]
    mov eax, [eax+SF_WORDS]
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
    mov eax, [ebp+20]
    mov eax, [eax+SF_GOAL]
    push edi
    push eax
    call num_to_ascii
    add esp, 8
    add edi, eax
    mov byte [edi], 0
    jmp .dispatch_done

.try_clock:
    mov ecx, [ebp-12]
    push str_tok_clock
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jz .try_space
    push st_piece_buf
    call st__append_clock
    add esp, 4
    jmp .dispatch_done

.try_space:
    mov ecx, [ebp-12]
    push str_tok_space
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jz .try_noop_tokens
    push single_space
    push st_piece_buf
    call sb_append_str
    add esp, 8
    mov byte [eax], 0
    jmp .dispatch_done

.try_noop_tokens:
    ; workspace/sel/help_bar/timer : reconnus, sans effet (voir
    ; l'en-tete de cette fonction) -- piece reste vide.
    mov ecx, [ebp-12]
    push str_tok_workspace
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jnz .dispatch_done
    mov ecx, [ebp-12]
    push str_tok_sel
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jnz .dispatch_done
    mov ecx, [ebp-12]
    push str_tok_help_bar
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jnz .dispatch_done
    mov ecx, [ebp-12]
    push str_tok_timer
    push ecx
    push esi
    call st__tok_is
    add esp, 12
    test eax, eax
    jnz .dispatch_done

    ; token inconnu : recopie tel quel (separateur personnalise)
    mov ecx, [ebp-12]
    push ecx
    push esi
    push st_piece_buf
    call memcpy
    add esp, 12
    mov eax, [ebp-12]
    mov byte [st_piece_buf+eax], 0

.dispatch_done:
    lea eax, [ebp-4]
    push st_piece_buf
    push eax
    push dword [ebp+12]
    push dword [ebp+8]
    call st__append_piece
    add esp, 16

    mov eax, esi
    add eax, [ebp-12]
    mov [ebp-8], eax
    jmp .next_token

.all_done:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void build_status_bar(char* out, dword outsz, dword width,
;                        const char* left, const char* center,
;                        const char* right) -- cdecl. Compose une ligne
; de statut complete de `width` caracteres a partir des trois zones
; deja construites par build_status_tokens : left aligne a gauche,
; right aligne a droite, center centre dans l'espace restant s'il y en
; a assez (ignore sinon) -- portage de common.c:build_status_bar.
build_status_bar:
    proc_enter
    sub esp, 24                  ; -4 used -8 left_len -12 center_len
                                  ; -16 right_len -20 gap -24 pad_before
    push ebx
    push esi
    push edi

    push dword [ebp+20]
    call utf8_strlen
    add esp, 4
    mov [ebp-8], eax

    push dword [ebp+24]
    call utf8_strlen
    add esp, 4
    mov [ebp-12], eax

    push dword [ebp+28]
    call utf8_strlen
    add esp, 4
    mov [ebp-16], eax

    mov dword [ebp-4], 0
    mov eax, [ebp+8]
    mov byte [eax], 0

    lea eax, [ebp-4]
    push dword [ebp+20]
    push eax
    push dword [ebp+12]
    push dword [ebp+8]
    call st__append_piece
    add esp, 16

    mov eax, [ebp+16]
    sub eax, [ebp-8]
    sub eax, [ebp-16]
    mov [ebp-20], eax             ; gap

    mov eax, [ebp-12]
    cmp eax, 0
    jle .no_center
    mov eax, [ebp-20]
    cmp eax, [ebp-12]
    jle .no_center

    mov eax, [ebp-20]
    sub eax, [ebp-12]
    sar eax, 1
    mov [ebp-24], eax             ; pad_before
    mov esi, eax
.pad_before_loop:
    cmp esi, 0
    jle .pad_before_done
    lea eax, [ebp-4]
    push single_space
    push eax
    push dword [ebp+12]
    push dword [ebp+8]
    call st__append_piece
    add esp, 16
    dec esi
    jmp .pad_before_loop
.pad_before_done:

    lea eax, [ebp-4]
    push dword [ebp+24]
    push eax
    push dword [ebp+12]
    push dword [ebp+8]
    call st__append_piece
    add esp, 16

    mov eax, [ebp-20]
    sub eax, [ebp-12]
    sub eax, [ebp-24]
    mov esi, eax                  ; pad_after
.pad_after_loop:
    cmp esi, 0
    jle .append_right
    lea eax, [ebp-4]
    push single_space
    push eax
    push dword [ebp+12]
    push dword [ebp+8]
    call st__append_piece
    add esp, 16
    dec esi
    jmp .pad_after_loop

.no_center:
    mov esi, [ebp-20]
.gap_loop:
    cmp esi, 0
    jle .append_right
    lea eax, [ebp-4]
    push single_space
    push eax
    push dword [ebp+12]
    push dword [ebp+8]
    call st__append_piece
    add esp, 16
    dec esi
    jmp .gap_loop

.append_right:
    lea eax, [ebp-4]
    push dword [ebp+28]
    push eax
    push dword [ebp+12]
    push dword [ebp+8]
    call st__append_piece
    add esp, 16

    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void build_status_line(editor_t* ed, char* out, dword cols) -- cdecl.
; Construit la barre de statut complete a partir de status_left/center/
; right (g_cfg_status_*, voir config.asm) et de l'etat courant de ed --
; portage de la composition faite dans run_editor (main.c:263-290).
build_status_line:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]                ; ed

    ; --- remplit st_fields_buf (status_fields_t) ---
    cmp dword [esi+EDITOR_FILEPATH], 0
    jne .have_path
    mov dword [st_fields_buf+SF_FILENAME], 0
    jmp .fname_done
.have_path:
    ; basename : dernier '/' + 1, ou le debut du chemin si aucun -- reste
    ; un pointeur DANS EDITOR_FILEPATH (deja nul-termine a la bonne place,
    ; puisque le basename en est un suffixe), pas de copie necessaire.
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
    mov dword [st_fields_buf+SF_FILENAME], ecx
.fname_done:

    mov eax, [esi+EDITOR_DIRTY]
    mov dword [st_fields_buf+SF_DIRTY], eax

    mov eax, [esi+EDITOR_CY]
    inc eax
    mov dword [st_fields_buf+SF_LINE1], eax

    mov eax, [esi+EDITOR_BUF]
    mov ebx, eax
    mov eax, [eax+BUF_COUNT]
    mov dword [st_fields_buf+SF_TOTAL], eax

    mov eax, [esi+EDITOR_CX]
    inc eax
    mov dword [st_fields_buf+SF_COL1], eax

    push esi
    call editor_word_count
    add esp, 4
    mov dword [st_fields_buf+SF_WORDS], eax

    push ebx                         ; ed->buf, encore dans ebx
    call buffer_char_count
    add esp, 4
    mov dword [st_fields_buf+SF_CHARS], eax

    mov eax, [g_cfg_word_goal]
    mov dword [st_fields_buf+SF_GOAL], eax

    ; --- construit les trois zones, puis les compose sur `cols` ---
    push st_fields_buf
    push dword [g_cfg_status_left]
    push 256
    push st_left_buf
    call build_status_tokens
    add esp, 16

    push st_fields_buf
    push dword [g_cfg_status_center]
    push 256
    push st_center_buf
    call build_status_tokens
    add esp, 16

    push st_fields_buf
    push dword [g_cfg_status_right]
    push 256
    push st_right_buf
    call build_status_tokens
    add esp, 16

    push st_right_buf
    push st_center_buf
    push st_left_buf
    push dword [ebp+16]              ; cols = width
    push STATUS_BUF_CAP
    push dword [ebp+12]                ; out
    call build_status_bar
    add esp, 24

    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void draw_editor(editor_t* ed, dword cols, dword rows) -- cdecl.
; Marges (g_cfg_margin_cols/rows, [editor] de writhd.ini/writhdeck.ini
; -- voir config.asm) : symetriques gauche/droite et haut/bas, meme
; comportement que draw_editor cote writhdeck-c/src/main.c. Repli sur 0
; si l'ecran est trop petit pour les contenir (zone de texte
; largeur/hauteur negative sinon), meme garde-fou que le C.
draw_editor:
    proc_enter
    sub esp, 76                  ; -4 usable -8 wrows -12 wcount
                                  ; -16 cursor_vrow -20 screen_row
                                  ; -24 cur_scr_row -28 cur_scr_col -32 i
                                  ; -36 start_char -40 len_chars
                                  ; -44 line_ptr -48 byte_start -52 attr
                                  ; -56 margin_cols -60 margin_rows
                                  ; -64 text_width -68 text_top
                                  ; -72 text_bottom -76 status_row
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]                ; ed

    mov eax, [ebp+16]
    dec eax
    mov [ebp-76], eax                  ; status_row = rows-1

    mov eax, [g_cfg_margin_cols]
    mov [ebp-56], eax
    mov eax, [g_cfg_margin_rows]
    mov [ebp-60], eax

    mov eax, [ebp+12]                  ; cols
    mov ecx, [ebp-56]
    add ecx, ecx                       ; 2*margin_cols
    sub eax, ecx
    mov [ebp-64], eax                  ; text_width = cols - 2*margin_cols
    cmp eax, 1
    jge .cols_margin_ok
    mov dword [ebp-56], 0
    mov eax, [ebp+12]
    mov [ebp-64], eax                  ; repli : text_width = cols
.cols_margin_ok:

    mov eax, [ebp-60]
    mov [ebp-68], eax                  ; text_top = margin_rows
    mov eax, [ebp-76]
    sub eax, [ebp-60]
    mov [ebp-72], eax                  ; text_bottom = status_row - margin_rows
    mov ecx, [ebp-72]
    cmp ecx, [ebp-68]
    jg .rows_margin_ok
    mov dword [ebp-60], 0
    mov dword [ebp-68], 0
    mov eax, [ebp-76]
    mov [ebp-72], eax                  ; repli : text_bottom = status_row
.rows_margin_ok:

    mov eax, [ebp-72]
    sub eax, [ebp-68]
    mov [ebp-4], eax                   ; usable = text_bottom - text_top

    ; EBX (callee-saved, cf. macros.inc) sert de compteur ici : "call
    ; ui_clear_line" ecrase eax/ecx/edx (caller-saved), le reincrementer
    ; apres l'appel aurait corrompu la boucle -- bug reel rencontre en
    ; testant (test_draw ne montrait qu'une seule rangee de marge
    ; effacee au lieu de g_cfg_margin_rows, a cause de ca).
    xor ebx, ebx
.clear_top_margin:
    cmp ebx, [ebp-68]
    jge .clear_top_done
    push ebx
    call ui_clear_line
    add esp, 4
    inc ebx
    jmp .clear_top_margin
.clear_top_done:
    mov ebx, [ebp-72]
.clear_bottom_margin:
    cmp ebx, [ebp-76]
    jge .clear_bottom_done
    push ebx
    call ui_clear_line
    add esp, 4
    inc ebx
    jmp .clear_bottom_margin
.clear_bottom_done:

    lea eax, [ebp-12]
    push eax
    lea eax, [ebp-8]
    push eax
    push dword [ebp-64]                  ; text_width = largeur de wrap
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

    mov eax, [ebp-68]
    add eax, [ebp-20]                             ; ligne absolue = text_top + screen_row
    push eax
    call ui_clear_line
    add esp, 4

    ; Coloration syntaxique par ligne entiere (voir highlight.asm) :
    ; classe la ligne LOGIQUE (pas le segment enroule) a chaque rangee
    ; ecran -- toutes ses lignes visuelles heritent la meme couleur,
    ; comme parse-heading/parse-comment/parse-list cote Tcl/C, qui
    ; classent aussi la ligne source entiere (main.c:238).
    push HL_MARKDOWN_SUPPORT_DEFAULT
    push hl_default_comment_marker
    push hl_default_heading_marker
    push dword [ebp-44]
    call classify_line
    add esp, 16
    mov ecx, UI_ATTR_NORMAL
    cmp eax, LINE_HEADING
    jne .attr_check_comment
    mov ecx, UI_ATTR_HEADING
    jmp .attr_mapped
.attr_check_comment:
    cmp eax, LINE_COMMENT
    jne .attr_check_list
    mov ecx, UI_ATTR_COMMENT
    jmp .attr_mapped
.attr_check_list:
    cmp eax, LINE_LIST
    jne .attr_mapped
    mov ecx, UI_ATTR_MARKUP
.attr_mapped:
    mov [ebp-52], ecx

    push dword [ebp-52]
    push dword [ebp-40]
    mov eax, [ebp-44]
    add eax, [ebp-48]
    push eax
    push dword [ebp-56]                           ; colonne = margin_cols
    mov eax, [ebp-68]
    add eax, [ebp-20]
    push eax
    call ui_put_str
    add esp, 20

    mov eax, [ebp-32]
    cmp eax, [ebp-16]
    jne .not_cursor_row
    mov eax, [ebp-68]
    add eax, [ebp-20]
    mov [ebp-24], eax
    mov eax, [esi+EDITOR_CX]
    sub eax, [ebp-36]
    add eax, [ebp-56]                             ; + margin_cols
    cmp eax, [ebp+12]                             ; cols
    jl .col_ok
    mov eax, [ebp+12]
    dec eax                                       ; clamp a cols-1
.col_ok:
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
    mov ecx, [ebp-68]
    add ecx, eax
    push ecx
    call ui_clear_line
    add esp, 4
    inc dword [ebp-20]
    jmp .clear_rest

.status_bar:
    push dword [ebp+12]              ; cols
    push status_buf
    push esi
    call build_status_line
    add esp, 12
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
