; main.asm -- point d'entree reel du programme : argv, chargement du
; fichier (ou brouillon si aucun argument), boucle principale clavier ->
; editor_*, dessin de l'ecran (word-wrap + defilement + barre de statut
; minimale). Portage simplifie de writhdeck-c/src/main.c : pas de
; navigateur de fichiers (un chemin en argv[1] ou un brouillon vide),
; pas de confirmation a la fermeture (Ctrl+Q quitte sans condition), pas
; de config .ini/JSON, pas d'autosave/watch-file/minuteur/i18n/
; coloration -- voir README pour le perimetre exact.
format ELF executable
entry _start

include 'sys.inc'
include 'macros.inc'

segment readable executable

include 'heap.asm'
include 'strutil.asm'
include 'utf8.asm'
include 'term.asm'
include 'buffer.asm'
include 'editor.asm'
include 'ui_ansi.asm'
include 'draw.asm'

_start:
    mov eax, [esp]
    cmp eax, 2
    jl .no_path
    mov ecx, esp
    add ecx, 4
    mov edx, [ecx+4]
    mov [g_open_path], edx
    jmp .path_done
.no_path:
    mov dword [g_open_path], 0
.path_done:

    call editor_new
    mov [g_ed], eax

    cmp dword [g_open_path], 0
    je .no_load
    push dword [g_open_path]
    push dword [g_ed]
    call editor_load
    add esp, 8
.no_load:

    call ui_init
    test eax, eax
    jz .ui_ok
    syscall1 SYS_EXIT, 1
.ui_ok:

.main_loop:
    call ui_rows
    mov [g_rows], eax
    call ui_cols
    mov [g_cols], eax

    mov eax, [g_rows]
    push eax
    mov eax, [g_cols]
    push eax
    push dword [g_ed]
    call draw_editor
    add esp, 12

    push g_event
    call ui_read_event
    add esp, 4

    mov eax, [g_event]
    cmp eax, UIK_UP
    je .skip_sticky_reset
    cmp eax, UIK_DOWN
    je .skip_sticky_reset
    mov ecx, [g_ed]
    mov dword [ecx+EDITOR_STICKY], -1
.skip_sticky_reset:

    mov eax, [g_event]
    cmp eax, UIK_CHAR
    je .do_char
    cmp eax, UIK_ENTER
    je .do_enter
    cmp eax, UIK_BACKSPACE
    je .do_backspace
    cmp eax, UIK_DELETE
    je .do_delete
    cmp eax, UIK_TAB
    je .do_tab
    cmp eax, UIK_CTRL_Z
    je .do_undo
    cmp eax, UIK_CTRL_Y
    je .do_redo
    cmp eax, UIK_LEFT
    je .do_left
    cmp eax, UIK_RIGHT
    je .do_right
    cmp eax, UIK_UP
    je .do_up
    cmp eax, UIK_DOWN
    je .do_down
    cmp eax, UIK_HOME
    je .do_home
    cmp eax, UIK_END
    je .do_end
    cmp eax, UIK_PGUP
    je .do_pgup
    cmp eax, UIK_PGDN
    je .do_pgdn
    cmp eax, UIK_CTRL_SPACE
    je .do_wordright
    cmp eax, UIK_CTRL_S
    je .do_save
    cmp eax, UIK_CTRL_Q
    je .quit
    jmp .main_loop

.do_char:
    push dword [g_ed]
    call editor_push_undo
    add esp, 4
    push dword [g_event+4]
    push dword [g_ed]
    call editor_insert_codepoint
    add esp, 8
    jmp .main_loop

.do_enter:
    push dword [g_ed]
    call editor_push_undo
    add esp, 4
    push dword [g_ed]
    call editor_enter
    add esp, 4
    jmp .main_loop

.do_backspace:
    push dword [g_ed]
    call editor_push_undo
    add esp, 4
    push dword [g_ed]
    call editor_backspace
    add esp, 4
    jmp .main_loop

.do_delete:
    push dword [g_ed]
    call editor_push_undo
    add esp, 4
    push dword [g_ed]
    call editor_delete
    add esp, 4
    jmp .main_loop

.do_tab:
    push dword [g_ed]
    call editor_push_undo
    add esp, 4
    push 9
    push dword [g_ed]
    call editor_insert_codepoint
    add esp, 8
    jmp .main_loop

.do_undo:
    push dword [g_ed]
    call editor_undo
    add esp, 4
    jmp .main_loop

.do_redo:
    push dword [g_ed]
    call editor_redo
    add esp, 4
    jmp .main_loop

.do_left:
    push dword [g_ed]
    call editor_move_left
    add esp, 4
    jmp .main_loop

.do_right:
    push dword [g_ed]
    call editor_move_right
    add esp, 4
    jmp .main_loop

.do_up:
    mov eax, [g_cols]
    push eax
    push dword [g_ed]
    call editor_move_up
    add esp, 8
    jmp .main_loop

.do_down:
    mov eax, [g_cols]
    push eax
    push dword [g_ed]
    call editor_move_down
    add esp, 8
    jmp .main_loop

.do_home:
    push dword [g_ed]
    call editor_move_home
    add esp, 4
    jmp .main_loop

.do_end:
    push dword [g_ed]
    call editor_move_end
    add esp, 4
    jmp .main_loop

.do_pgup:
    mov eax, [g_rows]
    dec eax
    push eax
    push dword [g_ed]
    call editor_move_pgup
    add esp, 8
    jmp .main_loop

.do_pgdn:
    mov eax, [g_rows]
    dec eax
    push eax
    push dword [g_ed]
    call editor_move_pgdn
    add esp, 8
    jmp .main_loop

.do_wordright:
    push dword [g_ed]
    call editor_move_word_right
    add esp, 4
    jmp .main_loop

.do_save:
    mov eax, [g_ed]
    cmp dword [eax+EDITOR_FILEPATH], 0
    jne .save_has_path
    push dword [g_ed]
    call prompt_save_as
    add esp, 4
    jmp .main_loop
.save_has_path:
    push dword [g_ed]
    call editor_save
    add esp, 4
    jmp .main_loop

.quit:
    call ui_cleanup
    push dword [g_ed]
    call editor_free
    add esp, 4
    syscall1 SYS_EXIT, 0

; int prompt_save_as(editor_t* ed) -- cdecl. Cas Ctrl+S sans fichier
; ouvert (brouillon) : jusque-la, editor_save() refusait silencieusement
; (voir editor.asm) -- aucune facon de sauver un brouillon. Affiche une
; invite "Save as: " sur la derniere rangee (celle de la barre de statut
; normale, qui sera redessinee au prochain tour de main_loop quoi qu'il
; arrive -- pas besoin de restaurer quoi que ce soit ici en cas
; d'annulation), capture un nom de fichier en ASCII imprimable
; (Retour arriere pour corriger, Echap pour annuler, Entree pour
; valider), puis sauve dessus et memorise le chemin dans ed (les Ctrl+S
; suivants passeront par editor_save direct, sans invite). Renvoie 1 si
; sauve, 0 si annule ou echec (chemin invalide/droits -- dans ce cas
; ed->filepath reste a 0 pour qu'un prochain Ctrl+S reprompte plutot que
; de re-essayer silencieusement le meme chemin en echec). Pas de gestion
; UTF-8 ici par choix : un nom de fichier tape reste dans l'ASCII
; imprimable (32-126), coherent avec le "pas de i18n" du reste de ce
; portage (voir README).
prompt_save_as:
    proc_enter
    sub esp, 4                   ; [ebp-4] = longueur courante du nom tape
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]             ; ed
    mov dword [ebp-4], 0

.redraw:
    push save_prompt_label
    push prompt_render_buf
    call sb_append_str
    add esp, 8
    push dword [ebp-4]
    push prompt_input_buf
    push eax
    call memcpy
    add esp, 12
    mov eax, prompt_render_buf
    add eax, save_prompt_label_len
    add eax, [ebp-4]
    mov byte [eax], 0

    call ui_rows
    mov ebx, eax
    dec ebx                      ; row = rows-1 (rangee de la barre de statut)
    call ui_cols
    mov edi, eax                 ; cols

    push UI_ATTR_REVERSE
    push edi
    push prompt_render_buf
    push 0
    push ebx
    call ui_put_str
    add esp, 20

    mov eax, save_prompt_label_len
    add eax, [ebp-4]
    push eax
    push ebx
    call ui_set_cursor
    add esp, 8
    call ui_refresh

    push g_event
    call ui_read_event
    add esp, 4

    mov eax, [g_event]
    cmp eax, UIK_ESCAPE
    je .cancelled
    cmp eax, UIK_ENTER
    je .maybe_confirm
    cmp eax, UIK_BACKSPACE
    je .do_backspace
    cmp eax, UIK_CHAR
    je .do_char
    jmp .redraw

.maybe_confirm:
    cmp dword [ebp-4], 0
    je .redraw                   ; nom vide -- ignorer, continuer la saisie
    jmp .confirm

.do_backspace:
    cmp dword [ebp-4], 0
    je .redraw
    dec dword [ebp-4]
    jmp .redraw

.do_char:
    mov eax, [g_event+4]
    cmp eax, 32
    jl .redraw
    cmp eax, 126
    jg .redraw
    mov ecx, [ebp-4]
    cmp ecx, PROMPT_INPUT_CAP-1
    jge .redraw
    mov [prompt_input_buf+ecx], al
    inc dword [ebp-4]
    jmp .redraw

.cancelled:
    xor eax, eax
    jmp .ret

.confirm:
    mov eax, [ebp-4]
    mov byte [prompt_input_buf+eax], 0

    ; le fichier tape existe-t-il deja ? sys_open en lecture seule est
    ; le test d'existence le plus simple disponible ici (pas de wrapper
    ; sys_stat/sys_access dans ce projet) -- s'il s'ouvre, il existe, le
    ; refermer aussitot (on ne veut que le savoir, pas le lire).
    push 0
    push O_RDONLY
    push prompt_input_buf
    call sys_open
    add esp, 12
    test eax, eax
    js .do_actual_save           ; negatif (ENOENT...) -> n'existe pas, sauver direct
    push eax
    call sys_close
    add esp, 4

.overwrite_redraw:
    push dword [ebp-4]
    push prompt_input_buf
    push prompt_render_buf
    call memcpy
    add esp, 12
    mov eax, prompt_render_buf
    add eax, [ebp-4]
    push overwrite_suffix
    push eax
    call sb_append_str
    add esp, 8
    mov byte [eax], 0

    call ui_rows
    mov ebx, eax
    dec ebx
    call ui_cols
    mov edi, eax

    push UI_ATTR_REVERSE
    push edi
    push prompt_render_buf
    push 0
    push ebx
    call ui_put_str
    add esp, 20
    call ui_refresh

    push g_event
    call ui_read_event
    add esp, 4

    mov eax, [g_event]
    cmp eax, UIK_CHAR
    jne .overwrite_check_escape
    mov ecx, [g_event+4]
    cmp ecx, 'y'
    je .do_actual_save
    cmp ecx, 'Y'
    je .do_actual_save
    cmp ecx, 'n'
    je .redraw                   ; decline -- retour a la saisie, nom conserve
    cmp ecx, 'N'
    je .redraw
    jmp .overwrite_redraw
.overwrite_check_escape:
    cmp eax, UIK_ESCAPE
    je .redraw
    jmp .overwrite_redraw

.do_actual_save:
    push prompt_input_buf
    call strdup
    add esp, 4
    mov [esi+EDITOR_FILEPATH], eax

    push eax
    mov ecx, [esi+EDITOR_BUF]
    push ecx
    call buffer_save_file
    add esp, 8
    test eax, eax
    jnz .save_failed
    mov dword [esi+EDITOR_DIRTY], 0
    mov eax, 1
    jmp .ret

.save_failed:
    push dword [esi+EDITOR_FILEPATH]
    call free
    add esp, 4
    mov dword [esi+EDITOR_FILEPATH], 0
    xor eax, eax

.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

segment readable writeable
include 'heap_data.inc'
include 'term_data.inc'
include 'ui_data.inc'
include 'draw_data.inc'

g_open_path dd 0
g_ed        dd 0
g_rows      dd 0
g_cols      dd 0
g_event     dd 0, 0

PROMPT_INPUT_CAP = 256
save_prompt_label     db 'Save as: ', 0
save_prompt_label_len = 9
overwrite_suffix db ' exists - overwrite? (y/n)', 0
prompt_input_buf  rb PROMPT_INPUT_CAP
prompt_render_buf rb PROMPT_INPUT_CAP + save_prompt_label_len + 32
