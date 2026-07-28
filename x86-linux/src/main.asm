; main.asm -- point d'entree reel du programme : argv, chargement du
; fichier (ou brouillon si aucun argument), boucle principale clavier ->
; editor_*, dessin de l'ecran (word-wrap + defilement + barre de statut).
; Portage simplifie de writhdeck-c/src/main.c : pas de navigateur de
; fichiers (un chemin en argv[1] ou un brouillon vide), pas
; d'autosave/watch-file/minuteur/i18n -- voir README pour le perimetre
; exact. Coloration par ligne (highlight.asm) et table des matieres
; plein ecran (F11) portees a l'identique de main.c (round 13 cote C),
; avec des marqueurs de titre/commentaire fixes (pas de cle .ini pour
; les rendre configurables). Ctrl+Q propose de sauver avant de quitter
; si le document est modifie (voir confirm()/save_with_prompt()
; ci-dessous). Marges et objectif de mots (config.asm) lus depuis
; writhd.ini/writhdeck.ini si present -- voir README, section ".ini
; config (partial)".
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
include 'highlight.asm'
include 'editor.asm'
include 'ui_ansi.asm'
include 'draw.asm'
include 'config.asm'

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
    ; envp[0] = esp + 4*(argc+2) : esp n'a pas bouge depuis l'entree du
    ; processus (aucun push/call avant ce point) donc [esp] vaut encore
    ; argc ici -- voir config.asm:cfg_init, qui ne peut pas retrouver
    ; envp lui-meme (seul _start a acces a la pile d'entree brute).
    mov eax, [esp]
    lea ecx, [esp+eax*4+8]
    push ecx
    call cfg_init
    add esp, 4

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
    cmp eax, UIK_CTRL_F
    je .do_find
    cmp eax, UIK_CTRL_Q
    je .quit
    cmp eax, UIK_F11
    je .do_f11
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
    push dword [g_cols]
    call ud_text_width
    add esp, 4
    push eax
    push dword [g_ed]
    call editor_move_up
    add esp, 8
    jmp .main_loop

.do_down:
    push dword [g_cols]
    call ud_text_width
    add esp, 4
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
    push dword [g_ed]
    call save_with_prompt
    add esp, 4
    jmp .main_loop

; Rechercher (Ctrl+F) -- portage du cas UIK_CTRL_F de run_editor
; (main.c:669-688). Un terme vide a la saisie (Echap OU Entree sans
; rien taper) reutilise g_last_search tel quel -- meme "trouver
; suivant" que le C, qui ne distingue pas non plus les deux cas pour ce
; prompt (voir prompt_line ci-dessous). g_last_search survit d'une
; recherche a l'autre (pas remis a zero par un simple Echap).
.do_find:
    push find_prompt_label_len
    push find_prompt_label
    call prompt_line
    add esp, 8
    test eax, eax
    jz .find_use_last            ; Echap -- pas de nouveau terme
    cmp byte [prompt_input_buf], 0
    je .find_use_last            ; Entree sur une saisie vide -- idem
    push dword [g_last_search]
    call free
    add esp, 4
    push prompt_input_buf
    call strdup
    add esp, 4
    mov [g_last_search], eax
.find_use_last:
    cmp dword [g_last_search], 0
    je .main_loop
    cmp byte [g_last_search], 0
    je .main_loop
    push dword [g_last_search]
    push dword [g_ed]
    call editor_find
    add esp, 8
    test eax, eax
    jnz .main_loop                ; trouve -- editor_find a deja deplace le curseur
    push not_found_prefix
    push prompt_render_buf
    call sb_append_str
    add esp, 8
    push dword [g_last_search]
    push eax
    call sb_append_str
    add esp, 8
    mov byte [eax], 0
    push prompt_render_buf
    call show_message
    add esp, 4
    jmp .main_loop

.do_f11:
    push dword [g_ed]
    call show_toc
    add esp, 4
    cmp eax, 0
    jl .f11_no_target
    push 0
    push eax
    push dword [g_ed]
    call editor_set_cursor
    add esp, 12
.f11_no_target:
    call ui_clear                ; la TOC a dessine un ecran different --
                                  ; l'editeur repart d'un ecran vide, meme
                                  ; souci que main.c:734
    jmp .main_loop

.quit:
    ; Ctrl+Q quitte toujours, mais propose de sauver d'abord si des
    ; modifications ne sont pas encore enregistrees -- portage du cas
    ; UIK_CTRL_Q de run_editor (main.c:746-755) : "o"/Entree=oui sauve
    ; sauve puis quitte, "n"/Echap=quitte sans sauver -- jamais
    ; d'annulation de la fermeture elle-meme, comme le C (running=0
    ; dans tous les cas apres le if).
    mov eax, [g_ed]
    cmp dword [eax+EDITOR_DIRTY], 0
    je .do_quit
    push quit_confirm_label
    call confirm
    add esp, 4
    test eax, eax
    jz .do_quit
    push dword [g_ed]
    call save_with_prompt
    add esp, 4
.do_quit:
    call ui_cleanup
    push dword [g_ed]
    call editor_free
    add esp, 4
    syscall1 SYS_EXIT, 0

; dword ud_text_width(dword cols) -- cdecl. Meme calcul de largeur de
; wrap que draw_editor (voir draw.asm : text_width = cols -
; 2*margin_cols, repli sur cols si le terminal est trop etroit) --
; NECESSAIRE ici aussi, portage de ud_text_width (main.c:655-657) :
; UP/DOWN doivent recalculer le word-wrap avec la MEME largeur que
; celle affichee pour savoir sur quelle ligne VISUELLE se trouve le
; curseur. Sans ce recalcul, editor_move_up/down (appeles avec la
; largeur BRUTE du terminal) et draw_editor (qui rogne 2*margin_cols)
; desaccordent des que g_cfg_margin_cols > 0 -- le curseur "saute"
; alors sur une rangee visuelle differente de celle reellement
; affichee, de facon apparemment aleatoire (bug reel corrige ici).
ud_text_width:
    proc_enter
    mov eax, [ebp+8]
    mov ecx, [g_cfg_margin_cols]
    add ecx, ecx
    sub eax, ecx
    cmp eax, 1
    jge .ok
    mov eax, [ebp+8]
.ok:
    proc_leave
    ret

; dword confirm(const char* question) -- cdecl. Affiche question en
; video inverse sur la derniere rangee, attend 'y'/'Y' (renvoie 1) ou
; 'n'/'N'/Echap (renvoie 0) -- ignore toute autre touche. Portage de
; confirm() (main.c:49-59), avec les touches y/n de ce portage plutot
; que o/n (round o/n cote C : locale francaise par defaut ; ce portage
; n'a pas d'i18n et n'affiche que de l'anglais, meme convention y/n
; deja utilisee par l'invite d'ecrasement de prompt_save_as ci-dessous).
confirm:
    proc_enter
    push ebx
    push esi

.redraw:
    call ui_rows
    dec eax
    mov ebx, eax                ; row = rows-1
    call ui_cols
    mov esi, eax                 ; cols

    push UI_ATTR_REVERSE
    push esi
    push dword [ebp+8]
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
    jne .check_escape
    mov ecx, [g_event+4]
    cmp ecx, 'y'
    je .yes
    cmp ecx, 'Y'
    je .yes
    cmp ecx, 'n'
    je .no
    cmp ecx, 'N'
    je .no
    jmp .redraw
.check_escape:
    cmp eax, UIK_ESCAPE
    je .no
    jmp .redraw

.yes:
    mov eax, 1
    jmp .ret
.no:
    xor eax, eax
.ret:
    pop esi
    pop ebx
    proc_leave
    ret

; void save_with_prompt(editor_t* ed) -- cdecl. Sauve directement si
; ed a deja un chemin, sinon delegue a prompt_save_as (invite de nom) --
; portage de save_with_prompt (main.c:303-314), factorise ici pour
; servir a la fois a Ctrl+S (.do_save) et a la confirmation de
; fermeture (.quit) ci-dessus.
save_with_prompt:
    proc_enter
    mov eax, [ebp+8]
    cmp dword [eax+EDITOR_FILEPATH], 0
    jne .has_path
    push dword [ebp+8]
    call prompt_save_as
    add esp, 4
    jmp .ret
.has_path:
    push dword [ebp+8]
    call editor_save
    add esp, 4
.ret:
    proc_leave
    ret

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

; int prompt_line(const char* label, dword label_len) -- cdecl. Saisie
; generique d'une ligne au bas de l'ecran (portage de prompt_line,
; main.c:22-47), factorisee hors de prompt_save_as (ci-dessus) pour
; servir aussi a Ctrl+F : "<label><texte tape>" en video inversee,
; Retour arriere efface, Echap annule (renvoie 0, prompt_input_buf
; inchange), Entree valide (renvoie 1, prompt_input_buf NUL-termine) --
; MEME avec une saisie vide, contrairement a prompt_save_as : c'est
; l'appelant qui decide quoi faire d'un terme vide (le C traite Echap
; et Entree-vide de la meme facon pour Ctrl+F : reutiliser le dernier
; terme cherche). ASCII imprimable uniquement (32-126), meme choix que
; prompt_save_as. Ecrit dans prompt_input_buf, le meme buffer partage
; que prompt_save_as (jamais utilises en meme temps, l'UI est modale).
prompt_line:
    proc_enter
    sub esp, 4                   ; [ebp-4] = longueur courante tapee
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]             ; label
    mov edi, [ebp+12]            ; label_len
    mov dword [ebp-4], 0

.redraw:
    push esi
    push prompt_render_buf
    call sb_append_str
    add esp, 8
    push dword [ebp-4]
    push prompt_input_buf
    push eax
    call memcpy
    add esp, 12
    mov eax, prompt_render_buf
    add eax, edi
    add eax, [ebp-4]
    mov byte [eax], 0

    call ui_rows
    mov ebx, eax
    dec ebx                      ; row = rows-1 (rangee de la barre de statut)
    call ui_cols                 ; eax = cols, consomme tout de suite ci-dessous,
                                  ; aucun registre dedie necessaire (pas d'appel
                                  ; entre celui-ci et le push qui le consomme)
    push UI_ATTR_REVERSE
    push eax
    push prompt_render_buf
    push 0
    push ebx
    call ui_put_str
    add esp, 20

    mov eax, edi
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
    je .confirmed
    cmp eax, UIK_BACKSPACE
    je .do_backspace
    cmp eax, UIK_CHAR
    je .do_char
    jmp .redraw

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
    jmp .ret2

.confirmed:
    mov eax, [ebp-4]
    mov byte [prompt_input_buf+eax], 0
    mov eax, 1

.ret2:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void show_message(const char* text) -- cdecl. Affiche text en video
; inversee sur la derniere rangee et attend n'importe quelle touche
; avant de rendre la main -- ce portage n'a pas le mecanisme de message
; "affiche un seul tour de boucle" du C (draw_editor n'a pas de
; parametre msg ici, voir README), donc un message doit etre confirme
; explicitement pour rester lisible avant le prochain redessin complet.
; Utilise pour "Not found: <terme>" de Ctrl+F. Meme structure que
; confirm() ci-dessus, sans interpretation y/n : toute touche dismiss.
show_message:
    proc_enter
    push ebx
    push esi

    call ui_rows
    dec eax
    mov ebx, eax
    call ui_cols
    mov esi, eax

    push UI_ATTR_REVERSE
    push esi
    push dword [ebp+8]
    push 0
    push ebx
    call ui_put_str
    add esp, 20
    call ui_refresh

    push g_event
    call ui_read_event
    add esp, 4

    pop esi
    pop ebx
    proc_leave
    ret

; int show_toc(editor_t* ed) -- cdecl. Table des matieres plein ecran
; (F11), portage de show_toc (main.c:414-472) : navigation Haut/Bas/
; Home/End, Entree selectionne (renvoie la ligne logique cible,
; 0-indexee), Echap/F11 annule (renvoie -1). Selection initiale sur le
; dernier titre dont la ligne est <= a la position actuelle du
; curseur, comme le C. Repli silencieux (-1) si le document n'a aucun
; titre. N'appelle PAS editor_set_cursor lui-meme -- c'est
; l'appelant (.do_f11 ci-dessus) qui deplace le curseur si le retour
; est >= 0, comme main.c:735.
show_toc:
    proc_enter
    sub esp, 56           ; -4 entries_tmp -8 count_tmp -12 sel -16 scroll
                           ; -20 rows -24 cols -28 usable -32 drawn
                           ; -36 i -40 entry_ptr -44 cursor -48 attr
                           ; -52 r -56 chosen
    push ebx
    push esi
    push edi

    lea eax, [ebp-8]
    push eax
    lea eax, [ebp-4]
    push eax
    push HL_MARKDOWN_SUPPORT_DEFAULT
    push hl_default_heading_marker
    mov eax, [ebp+8]
    mov eax, [eax+EDITOR_BUF]
    push eax
    call build_toc
    add esp, 20

    mov esi, [ebp-4]              ; entries
    mov ebx, [ebp-8]              ; count

    cmp ebx, 0
    jne .toc_have_entries
    push esi
    call free
    add esp, 4
    mov eax, -1
    jmp .toc_ret
.toc_have_entries:

    mov dword [ebp-12], 0         ; sel
    xor ecx, ecx                   ; i
    mov edx, [ebp+8]
    mov edx, [edx+EDITOR_CY]
.toc_sel_loop:
    cmp ecx, ebx
    jge .toc_sel_done
    mov eax, ecx
    imul eax, eax, TOC_ENTRY_SIZE
    add eax, esi
    mov eax, [eax+TOC_LINE]
    cmp eax, edx
    jg .toc_sel_next
    mov [ebp-12], ecx
.toc_sel_next:
    inc ecx
    jmp .toc_sel_loop
.toc_sel_done:

    mov dword [ebp-16], 0          ; scroll
    mov dword [ebp-56], -1          ; chosen
    call ui_clear

.toc_redraw:
    call ui_rows
    mov [ebp-20], eax
    call ui_cols
    mov [ebp-24], eax
    mov eax, [ebp-20]
    sub eax, 2
    mov [ebp-28], eax               ; usable = rows-2

    mov eax, [ebp-12]
    cmp eax, [ebp-16]
    jge .toc_not_below
    mov [ebp-16], eax
    jmp .toc_scroll_clamped
.toc_not_below:
    mov eax, [ebp-16]
    add eax, [ebp-28]
    cmp [ebp-12], eax
    jl .toc_scroll_clamped
    mov eax, [ebp-12]
    sub eax, [ebp-28]
    inc eax
    mov [ebp-16], eax
.toc_scroll_clamped:
    cmp dword [ebp-16], 0
    jge .toc_scroll_ok
    mov dword [ebp-16], 0
.toc_scroll_ok:

    push UI_ATTR_REVERSE
    push dword [ebp-24]
    push toc_title_label
    push 0
    push 0
    call ui_put_str
    add esp, 20

    mov dword [ebp-32], 0          ; drawn
    mov eax, [ebp-16]
    mov [ebp-36], eax               ; i = scroll
.toc_draw_loop:
    mov eax, [ebp-32]
    cmp eax, [ebp-28]
    jge .toc_draw_done
    mov eax, [ebp-36]
    cmp eax, ebx
    jge .toc_draw_done

    mov eax, [ebp-36]
    imul eax, eax, TOC_ENTRY_SIZE
    add eax, esi
    mov [ebp-40], eax               ; entry_ptr = &entries[i]

    ; indent = "- " repete (level-1) fois, borne a 62 octets utiles
    ; (comme indent[64] cote C -- voir main.c:441-446)
    mov ecx, [eax+TOC_LEVEL]
    dec ecx
    mov edi, toc_indent_buf
.toc_indent_loop:
    cmp ecx, 0
    jle .toc_indent_done
    mov eax, edi
    sub eax, toc_indent_buf
    cmp eax, 62
    jge .toc_indent_done
    mov byte [edi], '-'
    mov byte [edi+1], ' '
    add edi, 2
    dec ecx
    jmp .toc_indent_loop
.toc_indent_done:
    mov byte [edi], 0

    mov eax, toc_line_buf
    mov [ebp-44], eax               ; cursor

    push toc_two_spaces
    push dword [ebp-44]
    call sb_append_str
    add esp, 8
    mov [ebp-44], eax

    mov eax, [ebp-40]
    mov eax, [eax+TOC_LINE]
    inc eax
    push dword [ebp-44]
    push eax
    call num_to_ascii
    add esp, 8
    mov ecx, [ebp-44]
    add ecx, eax
    mov [ebp-44], ecx

    push toc_gap
    push dword [ebp-44]
    call sb_append_str
    add esp, 8
    mov [ebp-44], eax

    push toc_indent_buf
    push dword [ebp-44]
    call sb_append_str
    add esp, 8
    mov [ebp-44], eax

    mov eax, [ebp-40]
    add eax, TOC_TITLE
    push eax
    push dword [ebp-44]
    call sb_append_str
    add esp, 8
    mov [ebp-44], eax
    mov byte [eax], 0

    mov eax, UI_ATTR_NORMAL
    mov ecx, [ebp-36]
    cmp ecx, [ebp-12]
    jne .toc_attr_done
    mov eax, UI_ATTR_REVERSE
.toc_attr_done:
    mov [ebp-48], eax

    mov eax, [ebp-32]
    inc eax
    push dword [ebp-48]
    push dword [ebp-24]
    push toc_line_buf
    push 0
    push eax
    call ui_put_str
    add esp, 20

    inc dword [ebp-32]
    inc dword [ebp-36]
    jmp .toc_draw_loop
.toc_draw_done:

    mov eax, [ebp-32]
    inc eax
    mov [ebp-52], eax               ; r = 1+drawn
.toc_clear_loop:
    mov eax, [ebp-52]
    mov ecx, [ebp-20]
    dec ecx
    cmp eax, ecx
    jge .toc_clear_done
    push eax
    call ui_clear_line
    add esp, 4
    inc dword [ebp-52]
    jmp .toc_clear_loop
.toc_clear_done:

    mov eax, toc_status_buf
    mov [ebp-44], eax
    push toc_status_prefix
    push dword [ebp-44]
    call sb_append_str
    add esp, 8
    mov [ebp-44], eax

    push dword [ebp-44]
    push ebx
    call num_to_ascii
    add esp, 8
    mov ecx, [ebp-44]
    add ecx, eax
    mov [ebp-44], ecx

    cmp ebx, 1
    je .toc_status_singular
    push toc_status_suffix_plural
    push dword [ebp-44]
    call sb_append_str
    add esp, 8
    mov [ebp-44], eax
    jmp .toc_status_done
.toc_status_singular:
    push toc_status_suffix_singular
    push dword [ebp-44]
    call sb_append_str
    add esp, 8
    mov [ebp-44], eax
.toc_status_done:
    mov eax, [ebp-44]
    mov byte [eax], 0

    mov eax, [ebp-20]
    dec eax
    push UI_ATTR_REVERSE
    push dword [ebp-24]
    push toc_status_buf
    push 0
    push eax
    call ui_put_str
    add esp, 20

    call ui_refresh

    push g_event
    call ui_read_event
    add esp, 4

    mov eax, [g_event]
    cmp eax, UIK_UP
    jne .toc_not_up
    cmp dword [ebp-12], 0
    jle .toc_redraw
    dec dword [ebp-12]
    jmp .toc_redraw
.toc_not_up:
    cmp eax, UIK_DOWN
    jne .toc_not_down
    mov ecx, [ebp-12]
    inc ecx
    cmp ecx, ebx
    jge .toc_redraw
    mov [ebp-12], ecx
    jmp .toc_redraw
.toc_not_down:
    cmp eax, UIK_HOME
    jne .toc_not_home
    mov dword [ebp-12], 0
    jmp .toc_redraw
.toc_not_home:
    cmp eax, UIK_END
    jne .toc_not_end
    mov eax, ebx
    dec eax
    mov [ebp-12], eax
    jmp .toc_redraw
.toc_not_end:
    cmp eax, UIK_ENTER
    jne .toc_not_enter
    mov eax, [ebp-12]
    imul eax, eax, TOC_ENTRY_SIZE
    add eax, esi
    mov eax, [eax+TOC_LINE]
    mov [ebp-56], eax
    jmp .toc_loop_end
.toc_not_enter:
    cmp eax, UIK_ESCAPE
    je .toc_loop_end
    cmp eax, UIK_F11
    je .toc_loop_end
    jmp .toc_redraw

.toc_loop_end:
    push esi
    call free
    add esp, 4
    mov eax, [ebp-56]

.toc_ret:
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
include 'config_data.inc'

g_open_path dd 0
g_ed        dd 0
g_rows      dd 0
g_cols      dd 0
g_event     dd 0, 0
g_last_search dd 0            ; dernier terme cherche (Ctrl+F), strdup'e, NULL au depart

PROMPT_INPUT_CAP = 256
save_prompt_label     db 'Save as: ', 0
save_prompt_label_len = 9
overwrite_suffix db ' exists - overwrite? (y/n)', 0
quit_confirm_label db 'Save changes? (y/n)', 0
find_prompt_label     db 'Find: ', 0
find_prompt_label_len = 6
not_found_prefix db 'Not found: ', 0
prompt_input_buf  rb PROMPT_INPUT_CAP
; +PROMPT_INPUT_CAP de marge (pas seulement +label_len) : ce buffer sert
; aussi a "Not found: " + g_last_search, qui peut faire jusqu'a
; PROMPT_INPUT_CAP-1 octets a lui seul (strdup'e depuis prompt_input_buf).
prompt_render_buf rb PROMPT_INPUT_CAP + PROMPT_INPUT_CAP + 32

; --- table des matieres plein ecran (show_toc, F11) ---
toc_title_label            db 'Table of contents', 0
toc_two_spaces             db '  ', 0
toc_gap                    db '   ', 0
toc_status_prefix          db 'Up/Down:navigate  Enter:go  Esc:cancel  ', 0
toc_status_suffix_singular db ' heading', 0
toc_status_suffix_plural   db ' headings', 0
toc_indent_buf rb 64
toc_line_buf   rb 512
toc_status_buf rb 128
