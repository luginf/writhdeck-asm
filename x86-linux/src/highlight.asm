; highlight.asm -- portage direct de writhdeck-c/src/highlight.c :
; classification de ligne (titre/commentaire/liste) pour la coloration
; TUI, niveau de titre + extraction, table des matieres. Depend de
; strutil.asm (strlen/memcpy) et heap.asm (malloc/realloc), buffer.asm
; (BUF_LINES/BUF_COUNT) pour build_toc. Attendu inclus alors que le
; segment "readable executable" est deja actif, apres buffer.asm.
;
; Les marqueurs (heading_marker/comment_marker) et markdown_support
; restent des PARAMETRES (memes signatures cdecl que le C, testables
; avec des marqueurs arbitraires -- voir tests/test_highlight.asm) ;
; seuls les points d'appel de ce portage (draw.asm, main.asm) leur
; passent des constantes fixes (hl_default_heading_marker/
; hl_default_comment_marker/HL_MARKDOWN_SUPPORT_DEFAULT ci-dessous),
; puisque ce portage n'a pas de systeme de config .ini (voir README).
; Ces constantes reprennent les defauts de writhdeck-c/src/config.c :
; heading_marker="=", comment_marker="%", markdown_support=1 (actif).

LINE_NORMAL  = 0
LINE_HEADING = 1
LINE_COMMENT = 2
LINE_LIST    = 3

; toc_entry_t : {line:dword, level:dword, title:char[256]}
TOC_LINE       = 0
TOC_LEVEL      = 4
TOC_TITLE      = 8
TOC_ENTRY_SIZE = 264

HL_MARKDOWN_SUPPORT_DEFAULT = 1

hl_default_heading_marker db '=', 0
hl_default_comment_marker db '%', 0

; dword hl__marker_match(const char* ptr, const char* marker_ptr,
;                         dword marker_len) -- cdecl. 1 si les
; marker_len premiers octets de ptr sont identiques a marker_ptr,
; sinon 0. Equivalent d'un memcmp/strncmp borne (le tampon en face
; d'un marqueur non nul s'arrete toujours au premier octet different,
; jamais de lecture au-dela du terminateur nul de ptr en cas de
; non-correspondance -- meme raisonnement que strncmp cote C).
hl__marker_match:
    proc_enter
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]
    mov ecx, [ebp+16]
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

; void hl__set_title_out(char* title_out, dword title_out_sz,
;                         const char* content, dword content_len) --
; cdecl. Copie min(content_len, title_out_sz-1) octets de content vers
; title_out, nul-termine. Sans effet si title_out est 0 ou
; title_out_sz est 0 (title_out peut etre NULL -- seul le niveau
; interesse alors l'appelant, voir heading_level ci-dessous).
hl__set_title_out:
    proc_enter
    push ebx
    push esi
    push edi
    mov edi, [ebp+8]
    test edi, edi
    jz .ret
    mov eax, [ebp+12]
    test eax, eax
    jz .ret
    mov esi, [ebp+16]
    mov ebx, [ebp+20]
    dec eax
    cmp ebx, eax
    jle .copylen_ok
    mov ebx, eax
.copylen_ok:
    push ebx
    push esi
    push edi
    call memcpy
    add esp, 12
    mov eax, edi
    add eax, ebx
    mov byte [eax], 0
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; dword hl__is_comment_line(const char* line, const char* comment_marker)
; -- cdecl. Ancre strict en tete de ligne, aucun espace tolere avant
; (contrairement au titre) -- voir highlight.c:is_comment_line.
; comment_marker vide (chaine "") desactive la detection.
hl__is_comment_line:
    proc_enter
    push esi
    mov esi, [ebp+12]
    cmp byte [esi], 0
    jne .nonempty
    xor eax, eax
    jmp .ret
.nonempty:
    push esi
    call strlen
    add esp, 4
    push eax
    push esi
    push dword [ebp+8]
    call hl__marker_match
    add esp, 12
.ret:
    pop esi
    proc_leave
    ret

; dword hl__is_list_line(const char* line, dword markdown_support) --
; cdecl. "- " toujours reconnu ; "* " reconnu en plus si
; markdown_support -- voir highlight.c:is_list_line.
hl__is_list_line:
    proc_enter
    push esi
    mov esi, [ebp+8]
.skip_ws:
    mov al, [esi]
    cmp al, ' '
    je .ws
    cmp al, 9
    je .ws
    jmp .done
.ws:
    inc esi
    jmp .skip_ws
.done:
    mov al, [esi]
    cmp al, '-'
    jne .try_star
    mov ah, [esi+1]
    cmp ah, ' '
    je .true
    cmp ah, 9
    je .true
    jmp .try_star
.try_star:
    cmp dword [ebp+12], 0
    je .false
    mov al, [esi]
    cmp al, '*'
    jne .false
    mov ah, [esi+1]
    cmp ah, ' '
    je .true
    cmp ah, 9
    je .true
    jmp .false
.true:
    mov eax, 1
    jmp .ret
.false:
    xor eax, eax
.ret:
    pop esi
    proc_leave
    ret

; dword hl__is_heading_line(const char* line, const char* heading_marker)
; -- cdecl. ^\s*<marker>\s*(.+?)\s*<marker>\s*$ : balayage droite-a-
; gauche apres l'ouverture pour trouver la DERNIERE coupure valide
; (le "+?" paresseux Tcl ancre en fin de chaine -- voir
; highlight.c:is_heading_line). Sert seulement a classify_line (pas de
; niveau ici -- voir heading_level plus bas pour la table des
; matieres). heading_marker vide desactive la detection.
hl__is_heading_line:
    proc_enter
    sub esp, 8                  ; [ebp-4] = len(q), [ebp-8] = i
    push ebx
    push esi
    push edi

    mov esi, [ebp+12]
    cmp byte [esi], 0
    jne .marker_nonempty
    xor eax, eax
    jmp .ret
.marker_nonempty:
    push esi
    call strlen
    add esp, 4
    mov ebx, eax                ; mlen

    mov esi, [ebp+8]
.skip_lead_ws:
    mov al, [esi]
    cmp al, ' '
    je .lead_ws
    cmp al, 9
    je .lead_ws
    jmp .lead_done
.lead_ws:
    inc esi
    jmp .skip_lead_ws
.lead_done:

    push ebx
    push dword [ebp+12]
    push esi
    call hl__marker_match
    add esp, 12
    test eax, eax
    jz .not_heading

    add esi, ebx
.skip_q_ws:
    mov al, [esi]
    cmp al, ' '
    je .q_ws
    cmp al, 9
    je .q_ws
    jmp .q_done
.q_ws:
    inc esi
    jmp .skip_q_ws
.q_done:

    push esi
    call strlen
    add esp, 4
    mov [ebp-4], eax

    test eax, eax
    jz .not_heading
    dec eax
    mov [ebp-8], eax

.scan_loop:
    cmp dword [ebp-8], 0
    jl .not_heading

    mov eax, [ebp-8]
    add eax, ebx
    cmp eax, [ebp-4]
    jg .scan_next

    mov eax, [ebp-8]
    add eax, esi
    push ebx
    push dword [ebp+12]
    push eax
    call hl__marker_match
    add esp, 12
    test eax, eax
    jz .scan_next

    cmp dword [ebp-8], 0
    je .scan_next

    mov edi, [ebp-8]
    add edi, ebx
    add edi, esi
.tail_loop:
    mov al, [edi]
    test al, al
    jz .tail_ok
    cmp al, ' '
    je .tail_ws
    cmp al, 9
    je .tail_ws
    jmp .scan_next
.tail_ws:
    inc edi
    jmp .tail_loop
.tail_ok:
    xor edx, edx
.content_loop:
    cmp edx, [ebp-8]
    jge .scan_next
    mov al, [esi+edx]
    cmp al, ' '
    je .content_next
    cmp al, 9
    je .content_next
    jmp .found
.content_next:
    inc edx
    jmp .content_loop

.scan_next:
    dec dword [ebp-8]
    jmp .scan_loop

.found:
    mov eax, 1
    jmp .ret
.not_heading:
    xor eax, eax
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; dword hl__is_markdown_heading_line(const char* line, dword* level_out,
;                                     const char** content_out) --
; cdecl. ^\s*(#{1,6})\s+(.+)$ -- voir highlight.c:is_markdown_heading_line.
; level_out/content_out ecrits seulement si retour non nul (appelants
; internes uniquement, toujours avec des adresses locales valides).
hl__is_markdown_heading_line:
    proc_enter
    push esi
    push edi
    mov esi, [ebp+8]
.skip_ws:
    mov al, [esi]
    cmp al, ' '
    je .ws1
    cmp al, 9
    je .ws1
    jmp .ws1_done
.ws1:
    inc esi
    jmp .skip_ws
.ws1_done:
    xor edi, edi
.count_hash:
    mov al, [esi+edi]
    cmp al, '#'
    jne .count_done
    inc edi
    jmp .count_hash
.count_done:
    cmp edi, 1
    jl .false
    cmp edi, 6
    jg .false
    mov al, [esi+edi]
    cmp al, ' '
    je .ws_ok
    cmp al, 9
    je .ws_ok
    jmp .false
.ws_ok:
    add esi, edi
.skip_ws2:
    mov al, [esi]
    cmp al, ' '
    je .ws2
    cmp al, 9
    je .ws2
    jmp .ws2_done
.ws2:
    inc esi
    jmp .skip_ws2
.ws2_done:
    cmp byte [esi], 0
    je .false

    mov eax, [ebp+12]
    mov [eax], edi
    mov eax, [ebp+16]
    mov [eax], esi
    mov eax, 1
    jmp .ret
.false:
    xor eax, eax
.ret:
    pop edi
    pop esi
    proc_leave
    ret

; dword hl__is_heading_line_md(const char* line, const char* heading_marker,
;                               dword markdown_support) -- cdecl. Le
; marqueur configure est toujours essaye EN PREMIER, Markdown en repli
; seulement si markdown_support -- voir highlight.c:is_heading_line_md.
hl__is_heading_line_md:
    proc_enter
    sub esp, 8                  ; [ebp-4] = level scratch, [ebp-8] = content scratch
    push dword [ebp+12]
    push dword [ebp+8]
    call hl__is_heading_line
    add esp, 8
    test eax, eax
    jnz .true
    cmp dword [ebp+16], 0
    je .false
    lea eax, [ebp-8]
    push eax
    lea eax, [ebp-4]
    push eax
    push dword [ebp+8]
    call hl__is_markdown_heading_line
    add esp, 12
    test eax, eax
    jz .false
.true:
    mov eax, 1
    jmp .ret
.false:
    xor eax, eax
.ret:
    proc_leave
    ret

; dword classify_line(const char* line, const char* heading_marker,
;                      const char* comment_marker, dword markdown_support)
; -- cdecl. Precedence titre > commentaire > liste, une ligne n'est
; jamais classee dans plusieurs categories a la fois -- voir
; highlight.c:classify_line.
classify_line:
    proc_enter
    push dword [ebp+20]
    push dword [ebp+12]
    push dword [ebp+8]
    call hl__is_heading_line_md
    add esp, 12
    test eax, eax
    jz .try_comment
    mov eax, LINE_HEADING
    jmp .ret
.try_comment:
    push dword [ebp+16]
    push dword [ebp+8]
    call hl__is_comment_line
    add esp, 8
    test eax, eax
    jz .try_list
    mov eax, LINE_COMMENT
    jmp .ret
.try_list:
    push dword [ebp+20]
    push dword [ebp+8]
    call hl__is_list_line
    add esp, 8
    test eax, eax
    jz .normal
    mov eax, LINE_LIST
    jmp .ret
.normal:
    mov eax, LINE_NORMAL
.ret:
    proc_leave
    ret

; dword hl__try_markdown_heading(const char* line, char* title_out,
;                                 dword title_out_sz) -- cdecl. Repli
; Markdown de heading_level (marqueur configure absent/non ferme) --
; voir highlight.c:try_markdown_heading.
hl__try_markdown_heading:
    proc_enter
    sub esp, 8                  ; [ebp-4] = level, [ebp-8] = content
    push esi
    lea eax, [ebp-8]
    push eax
    lea eax, [ebp-4]
    push eax
    push dword [ebp+8]
    call hl__is_markdown_heading_line
    add esp, 12
    test eax, eax
    jnz .have_md
    xor eax, eax
    jmp .ret
.have_md:
    mov esi, [ebp-8]
    push esi
    call strlen
    add esp, 4
.trim_loop:
    test eax, eax
    jz .trim_done
    mov ecx, eax
    dec ecx
    mov dl, [esi+ecx]
    cmp dl, ' '
    je .is_ws_trim
    cmp dl, 9
    je .is_ws_trim
    jmp .trim_done
.is_ws_trim:
    dec eax
    jmp .trim_loop
.trim_done:
    test eax, eax
    jz .zero_ret
    push eax
    push esi
    push dword [ebp+16]
    push dword [ebp+12]
    call hl__set_title_out
    add esp, 16
    mov eax, [ebp-4]
    jmp .ret
.zero_ret:
    xor eax, eax
.ret:
    pop esi
    proc_leave
    ret

; dword heading_level(const char* line, const char* heading_marker,
;                      dword markdown_support, char* title_out,
;                      dword title_out_sz) -- cdecl. Niveau (nombre de
; repetitions du marqueur d'OUVERTURE ; nombre de '#' pour un titre
; Markdown), 0 si la ligne n'est pas un titre (title_out laisse vide
; dans ce cas). title_out peut etre 0 si seul le niveau interesse
; l'appelant -- voir highlight.c:heading_level.
heading_level:
    proc_enter
    sub esp, 24                 ; -4 open_count -8 len -12 i -16 j
                                 ; -20 close_count -24 content_len
    push ebx
    push esi
    push edi

    mov eax, [ebp+20]
    test eax, eax
    jz .no_clear
    cmp dword [ebp+24], 0
    je .no_clear
    mov byte [eax], 0
.no_clear:

    mov esi, [ebp+12]
    cmp byte [esi], 0
    jne .marker_nonempty
    jmp .fallback_markdown

.marker_nonempty:
    push esi
    call strlen
    add esp, 4
    mov ebx, eax                ; mlen

    mov esi, [ebp+8]
.skip_lead_ws:
    mov al, [esi]
    cmp al, ' '
    je .lw
    cmp al, 9
    je .lw
    jmp .lw_done
.lw:
    inc esi
    jmp .skip_lead_ws
.lw_done:

    mov dword [ebp-4], 0        ; open_count
.open_loop:
    push ebx
    push dword [ebp+12]
    push esi
    call hl__marker_match
    add esp, 12
    test eax, eax
    jz .open_done
    inc dword [ebp-4]
    add esi, ebx
    jmp .open_loop
.open_done:
    cmp dword [ebp-4], 0
    jne .have_open
    jmp .fallback_markdown
.have_open:

.skip_ws_content:
    mov al, [esi]
    cmp al, ' '
    je .wsc
    cmp al, 9
    je .wsc
    jmp .wsc_done
.wsc:
    inc esi
    jmp .skip_ws_content
.wsc_done:

    push esi
    call strlen
    add esp, 4
    mov [ebp-8], eax            ; len

    mov dword [ebp-12], 0       ; i
.scan_i:
    mov eax, [ebp-12]
    cmp eax, [ebp-8]
    jge .fallback_markdown

    mov eax, [ebp-12]
    add eax, esi
    push ebx
    push dword [ebp+12]
    push eax
    call hl__marker_match
    add esp, 12
    test eax, eax
    jz .scan_next

    cmp dword [ebp-12], 0
    je .scan_next

    mov eax, [ebp-12]
    mov [ebp-16], eax           ; j = i
    mov dword [ebp-20], 0       ; close_count
.close_loop:
    mov eax, [ebp-16]
    add eax, esi
    push ebx
    push dword [ebp+12]
    push eax
    call hl__marker_match
    add esp, 12
    test eax, eax
    jz .close_done
    inc dword [ebp-20]
    mov eax, [ebp-16]
    add eax, ebx
    mov [ebp-16], eax
    jmp .close_loop
.close_done:
    cmp dword [ebp-20], 0
    je .scan_next

    mov edi, [ebp-16]
    add edi, esi
.tail_loop2:
    mov al, [edi]
    test al, al
    jz .tail_ok2
    cmp al, ' '
    je .tail_ws2
    cmp al, 9
    je .tail_ws2
    jmp .scan_next
.tail_ws2:
    inc edi
    jmp .tail_loop2
.tail_ok2:

    mov eax, [ebp-12]
    mov [ebp-24], eax           ; content_len = i
.trim_loop2:
    mov eax, [ebp-24]
    test eax, eax
    jz .trim_done2
    dec eax
    mov dl, [esi+eax]
    cmp dl, ' '
    je .trim_ws2
    cmp dl, 9
    je .trim_ws2
    jmp .trim_done2
.trim_ws2:
    mov [ebp-24], eax
    jmp .trim_loop2
.trim_done2:

    cmp dword [ebp-24], 0
    je .scan_next

    mov eax, [ebp-24]
    push eax
    push esi
    push dword [ebp+24]
    push dword [ebp+20]
    call hl__set_title_out
    add esp, 16

    mov eax, [ebp-4]            ; open_count
    jmp .ret

.scan_next:
    inc dword [ebp-12]
    jmp .scan_i

.fallback_markdown:
    cmp dword [ebp+16], 0
    je .return_zero
    push dword [ebp+24]
    push dword [ebp+20]
    push dword [ebp+8]
    call hl__try_markdown_heading
    add esp, 12
    jmp .ret
.return_zero:
    xor eax, eax

.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void build_toc(const buffer_t* buf, const char* heading_marker,
;                 dword markdown_support, toc_entry_t** out_entries,
;                 dword* out_count) -- cdecl. Une entree par ligne dont
;                 heading_level != 0, dans l'ordre du buffer.
; *out_entries est alloue par la fonction (a liberer avec free()) --
; voir highlight.c:build_toc.
build_toc:
    proc_enter
    sub esp, 264                ; -4 cap -8 level -264..-9 title[256]
    push ebx
    push esi
    push edi

    mov dword [ebp-4], 8
    push TOC_ENTRY_SIZE*8
    call malloc
    add esp, 4
    mov esi, eax                ; entries

    xor ebx, ebx                 ; count
    xor edi, edi                  ; i

.loop:
    mov eax, [ebp+8]
    mov eax, [eax+BUF_COUNT]
    cmp edi, eax
    jge .done

    mov eax, [ebp+8]
    mov eax, [eax+BUF_LINES]
    mov eax, [eax+edi*4]         ; line_ptr

    lea ecx, [ebp-264]
    push 256
    push ecx
    push dword [ebp+16]
    push dword [ebp+12]
    push eax
    call heading_level
    add esp, 20
    test eax, eax
    jz .next_i
    mov [ebp-8], eax             ; level

    cmp ebx, [ebp-4]
    jl .cap_ok
    mov eax, [ebp-4]
    add eax, eax
    mov [ebp-4], eax
    imul eax, eax, TOC_ENTRY_SIZE
    push eax
    push esi
    call realloc
    add esp, 8
    mov esi, eax
.cap_ok:

    mov eax, ebx
    imul eax, eax, TOC_ENTRY_SIZE
    add eax, esi                  ; &entries[count]
    mov [eax+TOC_LINE], edi
    mov ecx, [ebp-8]
    mov [eax+TOC_LEVEL], ecx

    lea edx, [eax+TOC_TITLE]
    push 256
    lea ecx, [ebp-264]
    push ecx
    push edx
    call memcpy
    add esp, 12

    inc ebx

.next_i:
    inc edi
    jmp .loop

.done:
    mov eax, [ebp+20]
    mov [eax], esi
    mov eax, [ebp+24]
    mov [eax], ebx

    pop edi
    pop esi
    pop ebx
    proc_leave
    ret
