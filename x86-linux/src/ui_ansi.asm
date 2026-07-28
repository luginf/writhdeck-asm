; ui_ansi.asm -- portage direct de writhdeck-c/src/ui_ansi.c : backend
; TUI ANSI/VT100 ecrit a la main (termios raw + sequences d'echappement),
; zero dependance externe. Depend de term.asm (raw mode/taille/poll),
; heap.asm (malloc/realloc/free) et strutil.asm (memcpy/strlen). Attendu
; inclus alors que le segment "readable executable" est deja actif.
;
; Simplification assumee par rapport au C : pas de gestion de SIGWINCH
; (voir term.asm) -- un redimensionnement est pris en compte a la
; prochaine frappe, pas immediatement pendant un read() bloquant.
;
; Types d'evenement clavier (ui_event_t : {type:dword, ch:dword}) :
UIK_NONE        = 0
UIK_CHAR        = 1
UIK_UP          = 2
UIK_DOWN        = 3
UIK_LEFT        = 4
UIK_RIGHT       = 5
UIK_HOME        = 6
UIK_END         = 7
UIK_PGUP        = 8
UIK_PGDN        = 9
UIK_ENTER       = 10
UIK_BACKSPACE   = 11
UIK_DELETE      = 12
UIK_ESCAPE      = 13
UIK_TAB         = 14
UIK_CTRL_S      = 15
UIK_CTRL_Q      = 16
UIK_CTRL_Z      = 17
UIK_CTRL_Y      = 18
UIK_CTRL_F      = 19
UIK_CTRL_R      = 20
UIK_CTRL_SPACE  = 21
UIK_F11         = 22

UI_ATTR_NORMAL  = 0
UI_ATTR_REVERSE = 1
UI_ATTR_HEADING = 2
UI_ATTR_COMMENT = 3
UI_ATTR_MARKUP  = 4

; --- sequences ANSI constantes (jamais executees comme code : atteintes
; uniquement par adresse, jamais par chute/fall-through -- voir plan) ---
ui_seq_csi          db 27, '[', 0
ui_seq_semi         db ';', 0
ui_seq_h            db 'H', 0
ui_seq_semi_1h      db ';', '1', 'H', 0
ui_seq_clear_eol    db 27, '[', 'K', 0
ui_seq_clear_screen db 27, '[', '2', 'J', 27, '[', 'H', 0
ui_seq_attr_reverse db 27, '[', '7', 'm', 0
ui_seq_attr_heading db 27, '[', '3', '1', 'm', 0
ui_seq_attr_comment db 27, '[', '2', 'm', 0
ui_seq_attr_markup  db 27, '[', '3', '2', 'm', 0
ui_seq_attr_reset   db 27, '[', '0', 'm', 0
ui_seq_hide_cursor  db 27, '[', '?', '2', '5', 'l', 0
ui_seq_show_cursor  db 27, '[', '?', '2', '5', 'h', 0
ui_seq_disable_wrap db 27, '[', '?', '7', 'l', 0
ui_seq_bell         db 7, 0

; void ui__write_direct(const char* s) -- cdecl, ecriture immediate
; (hors tampon de frame) : cleanup et bip, qui doivent sortir tout de
; suite plutot que d'attendre le prochain ui_refresh.
ui__write_direct:
    proc_enter
    push dword [ebp+8]
    call strlen
    add esp, 4
    push eax
    push dword [ebp+8]
    push 1
    call sys_write
    add esp, 12
    proc_leave
    ret

; void ui__append(const void* ptr, dword len) -- cdecl, accumule dans le
; tampon de frame (croissance par doublement, depart 4096).
ui__append:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]
    mov eax, [frame_len]
    add eax, edi
    cmp eax, [frame_cap]
    jbe .cap_ok
    mov ebx, [frame_cap]
    test ebx, ebx
    jnz .grow
    mov ebx, 4096
    jmp .checkloop
.grow:
    shl ebx, 1
.checkloop:
    cmp ebx, eax
    jae .apply
    jmp .grow
.apply:
    push ebx
    push dword [frame_buf]
    call realloc
    add esp, 8
    mov [frame_buf], eax
    mov [frame_cap], ebx
.cap_ok:
    mov eax, [frame_buf]
    add eax, [frame_len]
    push edi
    push esi
    push eax
    call memcpy
    add esp, 12
    mov eax, [frame_len]
    add eax, edi
    mov [frame_len], eax
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void ui__append_str(const char* s) -- cdecl.
ui__append_str:
    proc_enter
    push dword [ebp+8]
    call strlen
    add esp, 4
    push eax
    push dword [ebp+8]
    call ui__append
    add esp, 8
    proc_leave
    ret

; void ui__append_uint(dword n) -- cdecl, ecrit n en decimal (n >= 0).
ui__append_uint:
    proc_enter
    sub esp, 12
    push ebx
    push esi
    mov eax, [ebp+8]
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
    mov eax, 12
    sub eax, esi
    push eax
    lea eax, [ebp+esi-12]
    push eax
    call ui__append
    add esp, 8
    pop esi
    pop ebx
    proc_leave
    ret

; int ui_init(void) -- cdecl. Renvoie 0/-1.
ui_init:
    proc_enter
    call term_enable_raw
    test eax, eax
    jz .raw_ok
    mov eax, -1
    jmp .ret
.raw_ok:
    push cols_cache
    push rows_cache
    call term_get_winsize
    add esp, 8
    push ui_seq_disable_wrap
    call ui__append_str
    add esp, 4
    push ui_seq_show_cursor
    call ui__append_str
    add esp, 4
    xor eax, eax
.ret:
    proc_leave
    ret

; void ui_cleanup(void) -- cdecl.
ui_cleanup:
    proc_enter
    push cleanup_seq_reset_and_wrap
    call ui__write_direct
    add esp, 4
    call term_disable_raw
    proc_leave
    ret

cleanup_seq_reset_and_wrap db 27, '[', '0', 'm', 27, '[', '?', '2', '5', 'h', 27, '[', '?', '7', 'h', 0

; dword ui_rows(void) -- cdecl.
ui_rows:
    proc_enter
    mov eax, [rows_cache]
    proc_leave
    ret

; dword ui_cols(void) -- cdecl.
ui_cols:
    proc_enter
    mov eax, [cols_cache]
    proc_leave
    ret

; void ui_clear(void) -- cdecl.
ui_clear:
    proc_enter
    push ui_seq_clear_screen
    call ui__append_str
    add esp, 4
    proc_leave
    ret

; void ui_clear_line(dword row) -- cdecl.
ui_clear_line:
    proc_enter
    push esi
    mov esi, [ebp+8]
    push ui_seq_csi
    call ui__append_str
    add esp, 4
    inc esi
    push esi
    call ui__append_uint
    add esp, 4
    push ui_seq_semi_1h
    call ui__append_str
    add esp, 4
    push ui_seq_clear_eol
    call ui__append_str
    add esp, 4
    pop esi
    proc_leave
    ret

; void ui_set_cursor(dword row, dword col) -- cdecl.
ui_set_cursor:
    proc_enter
    push esi
    mov esi, [ebp+8]
    push ui_seq_csi
    call ui__append_str
    add esp, 4
    inc esi
    push esi
    call ui__append_uint
    add esp, 4
    push ui_seq_semi
    call ui__append_str
    add esp, 4
    mov esi, [ebp+12]
    inc esi
    push esi
    call ui__append_uint
    add esp, 4
    push ui_seq_h
    call ui__append_str
    add esp, 4
    pop esi
    proc_leave
    ret

; void ui_put_str(dword row, dword col, const char* text, dword max_cols,
;                  dword attr) -- cdecl.
ui_put_str:
    proc_enter
    push esi
    mov esi, [ebp+8]
    push ui_seq_csi
    call ui__append_str
    add esp, 4
    inc esi
    push esi
    call ui__append_uint
    add esp, 4
    push ui_seq_semi
    call ui__append_str
    add esp, 4
    mov esi, [ebp+12]
    inc esi
    push esi
    call ui__append_uint
    add esp, 4
    push ui_seq_h
    call ui__append_str
    add esp, 4
    push ui_seq_clear_eol
    call ui__append_str
    add esp, 4

    mov eax, [ebp+24]
    cmp eax, UI_ATTR_REVERSE
    jne .try_heading
    push ui_seq_attr_reverse
    call ui__append_str
    add esp, 4
    jmp .attr_done
.try_heading:
    cmp eax, UI_ATTR_HEADING
    jne .try_comment
    push ui_seq_attr_heading
    call ui__append_str
    add esp, 4
    jmp .attr_done
.try_comment:
    cmp eax, UI_ATTR_COMMENT
    jne .try_markup
    push ui_seq_attr_comment
    call ui__append_str
    add esp, 4
    jmp .attr_done
.try_markup:
    cmp eax, UI_ATTR_MARKUP
    jne .attr_done
    push ui_seq_attr_markup
    call ui__append_str
    add esp, 4
.attr_done:

    mov eax, [ebp+20]
    test eax, eax
    jle .no_trunc
    push eax
    push dword [ebp+16]
    call utf8_byte_offset
    add esp, 8
    push eax
    push dword [ebp+16]
    call ui__append
    add esp, 8
    jmp .after_text
.no_trunc:
    push dword [ebp+16]
    call ui__append_str
    add esp, 4
.after_text:

    mov eax, [ebp+24]
    cmp eax, UI_ATTR_NORMAL
    je .ret
    push ui_seq_attr_reset
    call ui__append_str
    add esp, 4
.ret:
    pop esi
    proc_leave
    ret

; void ui_bell(void) -- cdecl.
ui_bell:
    proc_enter
    push ui_seq_bell
    call ui__write_direct
    add esp, 4
    proc_leave
    ret

; void ui_refresh(void) -- cdecl. Envoie hide_cursor+frame+show_cursor
; en un seul write() (evite le scintillement, voir ui_ansi.c original).
ui_refresh:
    proc_enter
    push ebx
    push esi
    push edi
    push ui_seq_hide_cursor
    call strlen
    add esp, 4
    mov esi, eax
    push ui_seq_show_cursor
    call strlen
    add esp, 4
    mov edi, eax

    mov eax, esi
    add eax, [frame_len]
    add eax, edi
    push eax
    call malloc
    add esp, 4
    mov ebx, eax

    push esi
    push ui_seq_hide_cursor
    push ebx
    call memcpy
    add esp, 12

    push dword [frame_len]
    push dword [frame_buf]
    mov eax, ebx
    add eax, esi
    push eax
    call memcpy
    add esp, 12

    push edi
    push ui_seq_show_cursor
    mov eax, ebx
    add eax, esi
    add eax, [frame_len]
    push eax
    call memcpy
    add esp, 12

    ; write(1, tmp, total) -- copie le pointeur tampon (ebx) dans ecx
    ; AVANT d'ecraser ebx avec le fd : ebx sert d'argument (registre a1)
    ; au syscall, donc perdrait le pointeur sinon (voir sys.inc).
    mov ecx, ebx
    mov edx, esi
    add edx, [frame_len]
    add edx, edi
    push ebx
    mov ebx, 1
    mov eax, SYS_WRITE
    int 0x80
    pop ebx

    push ebx
    call free
    add esp, 4
    mov dword [frame_len], 0

    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void ui_read_event(ui_event_t* out) -- cdecl. Lecture BLOQUANTE d'un
; evenement clavier ; *out = {type, ch}. Portage direct de la logique de
; ui_ansi.c (voir rapport d'exploration), MOINS la gestion SIGWINCH
; (simplification assumee, voir en-tete de fichier) -- pas de
; UIK_RESIZE genere ici.
ui_read_event:
    proc_enter
    sub esp, 4                  ; [ebp-4] = longueur totale restante (decodage UTF-8 multi-octets)
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov dword [esi], UIK_NONE
    mov dword [esi+4], 0

    call term_read_byte
    cmp eax, -1
    jne .have_byte
    jmp .ret
.have_byte:
    mov ebx, eax

    cmp ebx, 27
    jne .not_escape

    push 50
    call term_read_byte_timeout
    add esp, 4
    cmp eax, -1
    jne .have_c1
    mov dword [esi], UIK_ESCAPE
    jmp .ret
.have_c1:
    cmp eax, '['
    je .c1_ok
    cmp eax, 'O'
    je .c1_ok
    mov dword [esi], UIK_ESCAPE
    jmp .ret
.c1_ok:
    call term_read_byte
    cmp eax, -1
    jne .have_c2
    mov dword [esi], UIK_ESCAPE
    jmp .ret
.have_c2:
    mov ebx, eax
    cmp ebx, 'A'
    jne .not_up
    mov dword [esi], UIK_UP
    jmp .ret
.not_up:
    cmp ebx, 'B'
    jne .not_down
    mov dword [esi], UIK_DOWN
    jmp .ret
.not_down:
    cmp ebx, 'C'
    jne .not_right
    mov dword [esi], UIK_RIGHT
    jmp .ret
.not_right:
    cmp ebx, 'D'
    jne .not_left
    mov dword [esi], UIK_LEFT
    jmp .ret
.not_left:
    cmp ebx, 'H'
    jne .not_home2
    mov dword [esi], UIK_HOME
    jmp .ret
.not_home2:
    cmp ebx, 'F'
    jne .not_end2
    mov dword [esi], UIK_END
    jmp .ret
.not_end2:
    cmp ebx, '0'
    jl .ret
    cmp ebx, '9'
    jg .ret

    ; L'accumulateur des chiffres NE PEUT PAS etre ecx : term_read_byte
    ; (appele a chaque tour de .num_loop) descend jusqu'a sys_read, qui
    ; charge ecx avec le pointeur du tampon pour l'appel systeme (voir
    ; buffer.asm:sys_read) -- ecx est caller-saved, donc ecx serait
    ; ecrase a CHAQUE iteration si on l'utilisait ici. ebx, lui, est
    ; callee-saved (voir macros.inc) : il survit intact a travers
    ; term_read_byte/sys_read.
    sub ebx, '0'
.num_loop:
    call term_read_byte
    cmp eax, -1
    je .num_done
    cmp eax, '0'
    jl .num_done
    cmp eax, '9'
    jg .num_done
    imul ebx, ebx, 10
    sub eax, '0'
    add ebx, eax
    jmp .num_loop
.num_done:
    cmp ebx, 1
    je .set_home
    cmp ebx, 7
    je .set_home
    cmp ebx, 4
    je .set_end
    cmp ebx, 8
    je .set_end
    cmp ebx, 3
    je .set_delete
    cmp ebx, 5
    je .set_pgup
    cmp ebx, 6
    je .set_pgdn
    cmp ebx, 23
    je .set_f11
    jmp .ret
.set_home:
    mov dword [esi], UIK_HOME
    jmp .ret
.set_end:
    mov dword [esi], UIK_END
    jmp .ret
.set_delete:
    mov dword [esi], UIK_DELETE
    jmp .ret
.set_pgup:
    mov dword [esi], UIK_PGUP
    jmp .ret
.set_pgdn:
    mov dword [esi], UIK_PGDN
    jmp .ret
.set_f11:
    mov dword [esi], UIK_F11
    jmp .ret

.not_escape:
    cmp ebx, 0
    jne .not_ctrl_space
    mov dword [esi], UIK_CTRL_SPACE
    jmp .ret
.not_ctrl_space:
    cmp ebx, 9
    jne .not_tab
    mov dword [esi], UIK_TAB
    jmp .ret
.not_tab:
    cmp ebx, 10
    je .set_enter
    cmp ebx, 13
    je .set_enter
    jmp .not_enter
.set_enter:
    mov dword [esi], UIK_ENTER
    jmp .ret
.not_enter:
    cmp ebx, 6
    jne .not_ctrlf
    mov dword [esi], UIK_CTRL_F
    jmp .ret
.not_ctrlf:
    cmp ebx, 17
    jne .not_ctrlq
    mov dword [esi], UIK_CTRL_Q
    jmp .ret
.not_ctrlq:
    cmp ebx, 18
    jne .not_ctrlr
    mov dword [esi], UIK_CTRL_R
    jmp .ret
.not_ctrlr:
    cmp ebx, 19
    jne .not_ctrls
    mov dword [esi], UIK_CTRL_S
    jmp .ret
.not_ctrls:
    cmp ebx, 25
    jne .not_ctrly
    mov dword [esi], UIK_CTRL_Y
    jmp .ret
.not_ctrly:
    cmp ebx, 26
    jne .not_ctrlz
    mov dword [esi], UIK_CTRL_Z
    jmp .ret
.not_ctrlz:
    cmp ebx, 127
    jne .not_backspace
    mov dword [esi], UIK_BACKSPACE
    jmp .ret
.not_backspace:
    cmp ebx, 8
    je .ret
    cmp ebx, 0x80
    jl .ascii_char

    ; decodage UTF-8 multi-octets. Ecrit d'abord le repli (UIK_CHAR,
    ; ch=octet brut) : si la sequence s'avere invalide/tronquee en
    ; cours de route, il suffit de sauter a .ret sans rien recalculer.
    mov dword [esi], UIK_CHAR
    mov [esi+4], ebx

    mov ecx, ebx
    and ecx, 0xE0
    cmp ecx, 0xC0
    jne .try3u
    mov edx, ebx
    and edx, 0x1F
    mov dword [ebp-4], 2
    jmp .have_len
.try3u:
    mov ecx, ebx
    and ecx, 0xF0
    cmp ecx, 0xE0
    jne .try4u
    mov edx, ebx
    and edx, 0x0F
    mov dword [ebp-4], 3
    jmp .have_len
.try4u:
    mov ecx, ebx
    and ecx, 0xF8
    cmp ecx, 0xF0
    jne .ret                       ; tete invalide -- repli deja ecrit
    mov edx, ebx
    and edx, 0x07
    mov dword [ebp-4], 4
.have_len:
    mov ecx, 1
.mb_loop:
    cmp ecx, [ebp-4]
    jge .mb_done
    push ecx
    push edx
    call term_read_byte
    pop edx
    pop ecx
    cmp eax, -1
    je .ret                          ; lecture echouee -- repli deja ecrit
    mov ebx, eax
    and ebx, 0xC0
    cmp ebx, 0x80
    jne .ret                          ; continuation invalide -- repli deja ecrit
    mov ebx, eax
    and ebx, 0x3F
    shl edx, 6
    or edx, ebx
    inc ecx
    jmp .mb_loop
.mb_done:
    mov [esi+4], edx                    ; sequence complete -- ecrase le repli
    jmp .ret

.ascii_char:
    mov dword [esi], UIK_CHAR
    mov [esi+4], ebx

.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret
