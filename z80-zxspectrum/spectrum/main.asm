; main.asm -- point d'entree reel du portage ZX Spectrum : boucle
; principale clavier -> editor_*, dessin de l'ecran (word-wrap +
; defilement par ligne logique + barre de statut minimale
; ligne/colonne), sauvegarde/chargement cassette. Assemble en .tap
; directement (voir Makefile). Barre de statut volontairement minimale
; (juste "L<ligne> C<colonne>", pas de total de lignes ni d'indicateur
; de modification) : une version complete existait, retiree pour
; alleger le rendu a chaque frappe, puis cette version reduite
; redemandee -- garder minimal si on y retouche.
;
; Simplifications assumees (coherentes avec le reste du portage) :
; pas de navigateur de fichiers (un seul document, nom de bande fixe
; "WRITHDECK"), pas de confirmation a la fermeture (SYM+Q quitte sans
; condition, via RST 0 -- retour a l'ecran BASIC), pas de recherche
; liee au clavier dans cette passe (editor_find existe dans core/ pour
; un usage futur), defilement par LIGNE LOGIQUE (pas par rangee
; visuelle comme le x86) : simple et robuste, quitte a ne pas remplir
; l'ecran a l'octet pres quand des lignes tres longues se replient.
    DEVICE ZXSPECTRUM48
    ORG $8000

program_start:
    ; etiquette du tout debut de l'image assemblee -- IMPORTANT : les
    ; modules inclus ci-dessous (buffer/editor/screen/keyboard/tape)
    ; placent tout leur code ET LEURS DONNEES (dont TEXTBUF/LINETAB,
    ; plusieurs Ko) AVANT _start (qui n'arrive qu'apres tous les
    ; INCLUDE, une fois assemble) : le bloc CODE sauvegarde par
    ; SAVETAP doit donc couvrir [program_start.._start_du_dernier_octet],
    ; PAS "$ - _start" (qui ne couvrirait que le code de la boucle
    ; principale elle-meme, en oubliant tout le reste -- bug reel
    ; rencontre en testant, voir le .tap produit une premiere fois).

    include "../core/buffer.asm"
    include "../core/editor.asm"
    include "../spectrum/screen.asm"
    include "../spectrum/keyboard.asm"
    include "../spectrum/tape.asm"

TEXT_ROWS = SCR_ROWS - 1   ; derniere rangee (23) reservee a la barre de statut

; ============================================================
; num_to_ascii -- entree HL=valeur (0-9999), DE=pointeur destination.
; Ecrit les chiffres decimaux (sans zero de tete, "0" si HL=0), sortie
; DE=pointeur avance. Detruit AF, BC, HL.
; ============================================================
num_to_ascii:
    ld a, h
    or l
    jr nz, .extract
    ld a, '0'
    ld (de), a
    inc de
    ret
.extract:
    ld b, 0
.extract_loop:
    call num__div10
    push af
    inc b
    ld a, h
    or l
    jr nz, .extract_loop
.write_loop:
    pop af
    add a, '0'
    ld (de), a
    inc de
    djnz .write_loop
    ret

; num__div10 -- entree HL ; sortie HL=HL/10, A=HL mod 10. Detruit BC.
num__div10:
    ld bc, 0
.loop:
    ld a, h
    or a
    jr nz, .big
    ld a, l
    cp 10
    jr c, .done
.big:
    ld a, l
    sub 10
    ld l, a
    ld a, h
    sbc a, 0
    ld h, a
    inc bc
    jr .loop
.done:
    ld a, l
    push af
    ld h, b
    ld l, c
    pop af
    ret

; build_status_line -- construit "L<ligne+1> C<col+1>" dans status_buf,
; met a jour status_len. Volontairement minimal (pas de total de
; lignes, pas d'indicateur de modification). Detruit AF, BC, DE, HL.
build_status_line:
    ld de, status_buf
    ld a, 'L'
    ld (de), a
    inc de
    ld a, (CURLINE)
    inc a
    ld h, 0
    ld l, a
    call num_to_ascii
    ld a, ' '
    ld (de), a
    inc de
    ld a, 'C'
    ld (de), a
    inc de
    ld hl, (CURCOL)
    inc hl
    call num_to_ascii
    push de
    pop hl
    ld bc, status_buf
    or a
    sbc hl, bc
    ld a, l
    ld (status_len), a
    ret

; draw_status_bar -- dessine la barre de statut (derniere rangee,
; video inversee sur toute sa largeur). Detruit AF, BC, DE, HL.
draw_status_bar:
    call build_status_line
    ld a, (status_len)
    ld b, a
    ld a, TEXT_ROWS
    ld hl, status_buf
    call scr_put_line
    ld a, TEXT_ROWS
    ld e, 0
    ld b, SCR_COLS
    ld c, ATTR_REVERSE
    call scr_set_attr
    ret

; render_line_segments -- dessine les rangees ecran d'UNE ligne logique
; deja "wrappee" (wrap_count/wrap_segs valides pour elle) : entree
; rp_li=ligne, rp_cursor_seg=indice de segment du curseur (ou 0xFF),
; rp_screenrow=rangee de depart, rp_seg=0. Avance rp_screenrow/rp_seg,
; met a jour found_cursor/cursor_screen_row/col si le curseur est
; croise. Sortie (flag) : carry=1 si arrete faute de place ecran avant
; la fin de la ligne, carry=0 si la ligne a ete entierement dessinee.
; Detruit AF, BC, DE, HL. Extrait de render_pass pour etre reutilise
; tel quel par render_current_line_fast (voir draw_screen).
render_line_segments:
.seg_loop:
    ld a, (rp_seg)
    ld hl, wrap_count
    cp (hl)
    jr nc, .done_ok
    ld a, (rp_screenrow)
    cp TEXT_ROWS
    jr nc, .done_full

    ld a, (rp_seg)
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    ld de, wrap_segs
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (rp_segstart), de
    inc hl
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (rp_seglen), de

    ld a, (rp_li)
    call buffer_line_addr
    ld de, (rp_segstart)
    add hl, de

    ld a, (rp_seglen)
    ld b, a
    ld a, (rp_screenrow)
    call scr_put_line

    ld a, (rp_seg)
    ld hl, rp_cursor_seg
    cp (hl)
    jr nz, .not_cursor_seg
    ld a, (rp_screenrow)
    ld (cursor_screen_row), a
    ld hl, (CURCOL)
    ld de, (rp_segstart)
    or a
    sbc hl, de
    ld a, l
    ld (cursor_screen_col), a
    ld a, 1
    ld (found_cursor), a
.not_cursor_seg:

    ld a, (rp_screenrow)
    inc a
    ld (rp_screenrow), a
    ld a, (rp_seg)
    inc a
    ld (rp_seg), a
    jr .seg_loop
.done_ok:
    or a
    ret
.done_full:
    scf
    ret

; render_pass -- une passe de rendu COMPLETE a partir de disp_top_line
; (toutes les lignes visibles). Remplit found_cursor/cursor_screen_row/
; cursor_screen_col, et au passage cur_line_row0/cur_line_rows (rangee
; de depart + nombre de rangees occupees par CURLINE -- utilise par
; draw_screen pour decider si un futur redessin peut se limiter a cette
; seule ligne, voir render_current_line_fast). Detruit AF, BC, DE, HL.
render_pass:
    xor a
    ld (found_cursor), a

    ld a, (disp_top_line)
    ld (rp_li), a
    xor a
    ld (rp_screenrow), a
.line_loop:
    ld a, (rp_li)
    ld hl, LINECOUNT
    cp (hl)
    jp nc, .lines_done
    ld a, (rp_screenrow)
    cp TEXT_ROWS
    jp nc, .lines_done

    ld a, (rp_li)
    call editor_wrap_line

    ld a, (rp_li)
    ld hl, CURLINE
    cp (hl)
    jr nz, .no_cursor_here
    ld a, (rp_li)
    ld de, (CURCOL)
    call editor__wrap_and_find
    ld a, (wf_idx)
    ld (rp_cursor_seg), a
    ld a, (rp_screenrow)
    ld (cur_line_row0), a
    ld a, (wrap_count)
    ld (cur_line_rows), a
    jr .have_cursor_check
.no_cursor_here:
    ld a, 0xFF
    ld (rp_cursor_seg), a
.have_cursor_check:

    xor a
    ld (rp_seg), a
    call render_line_segments
    jr c, .lines_done

    ld a, (rp_li)
    inc a
    ld (rp_li), a
    jp .line_loop
.lines_done:

.clear_loop:
    ld a, (rp_screenrow)
    cp TEXT_ROWS
    jr nc, .clear_done
    call scr_clear_line
    ld a, (rp_screenrow)
    inc a
    ld (rp_screenrow), a
    jr .clear_loop
.clear_done:
    ret

; render_current_line_fast -- redessine UNIQUEMENT les rangees ecran de
; CURLINE (wrap_count/wrap_segs deja calcules par l'appelant), a partir
; de last_row0. N'est correct QUE si le nombre de rangees qu'occupe
; CURLINE n'a pas change depuis le dernier rendu complet -- c'est
; draw_screen qui verifie cette condition avant d'appeler cette
; routine. Detruit AF, BC, DE, HL.
render_current_line_fast:
    ld a, (CURLINE)
    ld de, (CURCOL)
    call editor__wrap_and_find
    ld a, (wf_idx)
    ld (rp_cursor_seg), a

    xor a
    ld (found_cursor), a
    ld a, (CURLINE)
    ld (rp_li), a
    ld a, (last_row0)
    ld (rp_screenrow), a
    xor a
    ld (rp_seg), a
    call render_line_segments
    ret

; draw_screen -- assure que CURLINE est visible et que l'ecran reflete
; l'etat courant, en redessinant le MOINS possible : si rien n'a change
; depuis le dernier rendu a part le contenu de CURLINE (meme ligne,
; meme defilement, meme nombre de rangees occupees -- le cas le plus
; frequent en tapant), seule cette ligne est redessinee au lieu de
; l'ecran entier. Sinon (Entree/Suppr fusionnant des lignes/UP/DOWN/
; Undo/Redo/defilement), rendu complet comme avant. Dans tous les cas,
; la surbrillance du curseur est geree a part, par une mise a jour
; ciblee de DEUX cellules d'attribut au plus (l'ancienne position et la
; nouvelle) -- PAS par la remise a plat de tout le plan d'attributs
; comme avant (celle-ci n'etait necessaire que pour effacer l'ancienne
; surbrillance, jamais pour le texte lui-meme : scr_draw_char ne touche
; jamais aux attributs, seul scr_set_attr le fait). Detruit AF, BC, DE, HL.
draw_screen:
    ld a, (last_valid)
    or a
    jr z, .full_path
    ld a, (disp_top_line)
    ld hl, last_top
    cp (hl)
    jr nz, .full_path
    ld a, (LINECOUNT)
    ld hl, last_linecount
    cp (hl)
    jr nz, .full_path
    ld a, (CURLINE)
    ld hl, last_curline
    cp (hl)
    jr nz, .full_path

    ld a, (CURLINE)
    call editor_wrap_line
    ld a, (wrap_count)
    ld hl, last_rows
    cp (hl)
    jr nz, .full_path

    call render_current_line_fast
    jr .after_render

.full_path:
    ld a, (CURLINE)
    ld hl, disp_top_line
    cp (hl)
    jr nc, .try_render
    ld (disp_top_line), a
.try_render:
    call render_pass
    ld a, (found_cursor)
    or a
    jr nz, .have_cursor
    ld a, (CURLINE)
    ld (disp_top_line), a
    call render_pass
.have_cursor:
    ld a, (disp_top_line)
    ld (last_top), a
    ld a, (CURLINE)
    ld (last_curline), a
    ld a, (LINECOUNT)
    ld (last_linecount), a
    ld a, (cur_line_row0)
    ld (last_row0), a
    ld a, (cur_line_rows)
    ld (last_rows), a
    ld a, 1
    ld (last_valid), a

.after_render:
    call draw_status_bar

    ld a, (prev_cursor_valid)
    or a
    jr z, .no_old_cursor
    ld a, (prev_cursor_col)
    ld e, a
    ld b, 1
    ld c, ATTR_NORMAL
    ld a, (prev_cursor_row)
    call scr_set_attr
.no_old_cursor:
    ld a, (found_cursor)
    ld (prev_cursor_valid), a
    or a
    jr z, .no_new_cursor
    ld a, (cursor_screen_col)
    ld e, a
    ld b, 1
    ld c, ATTR_REVERSE
    ld a, (cursor_screen_row)
    call scr_set_attr
    ld a, (cursor_screen_row)
    ld (prev_cursor_row), a
    ld a, (cursor_screen_col)
    ld (prev_cursor_col), a
.no_new_cursor:
    ret

; do_save -- sauve tout le document sur cassette (bloc CODE "WRITHDECK").
; Detruit AF, BC, DE, HL, IX.
do_save:
    call buffer_char_count
    ex de, hl
    ld hl, TEXTBUF
    call tape_save
    xor a
    ld (DIRTY), a
    ret

; ============================================================
; point d'entree
; ============================================================
_start:
    ; PAS d'EI ici : rester en interruptions desactivees (etat par
    ; defaut) expres. Une tentative anterieure activait les
    ; interruptions pour utiliser HALT comme anti-rebond clavier, ce
    ; qui laissait le gestionnaire d'interruption STANDARD de la ROM
    ; tourner en tache de fond (toutes les ~20ms) -- celui-ci s'appuie
    ; sur des variables systeme (etat du curseur clignotant, etc.) que
    ; notre programme ne met jamais a jour (on gere l'ecran nous-memes,
    ; sans passer par la ROM) : apres quelques secondes de frappe, ceci
    ; corrompait la memoire de facon reproductible (bug reel rencontre
    ; en testant : le tampon texte se remplissait d'un octet errone
    ; apres ~3s de frappe). L'anti-rebond clavier (voir keyboard.asm)
    ; utilise desormais une boucle d'attente calibree en T-states, pas
    ; HALT -- aucun besoin d'interruptions actives.
    call editor_init
    call scr_clear
    xor a
    ld (disp_top_line), a

.main_loop:
    call draw_screen
    call keyb_wait_key          ; A=type (KEY_*), C=caractere si KEY_CHAR

    cp KEY_CHAR
    jr nz, .not_char
    call editor_insert_codepoint
    jr .main_loop
.not_char:
    cp KEY_ENTER
    jr nz, .not_enter
    call editor_enter
    jr .main_loop
.not_enter:
    cp KEY_DELETE
    jr nz, .not_delete
    call editor_backspace
    jr .main_loop
.not_delete:
    cp KEY_LEFT
    jr nz, .not_left
    call editor_move_left
    jr .main_loop
.not_left:
    cp KEY_RIGHT
    jr nz, .not_right
    call editor_move_right
    jr .main_loop
.not_right:
    cp KEY_UP
    jr nz, .not_up
    call editor_move_up
    jr .main_loop
.not_up:
    cp KEY_DOWN
    jr nz, .not_down
    call editor_move_down
    jr .main_loop
.not_down:
    cp KEY_SAVE
    jr nz, .not_save
    call do_save
    jr .main_loop
.not_save:
    cp KEY_UNDO
    jr nz, .not_undo
    call editor_undo
    jr .main_loop
.not_undo:
    cp KEY_REDO
    jr nz, .not_redo
    call editor_redo
    jr .main_loop
.not_redo:
    cp KEY_QUIT
    jr nz, .main_loop
    rst 0                       ; quitter = redemarrage doux (retour BASIC)

; ============================================================
; donnees
; ============================================================
disp_top_line: defb 0
found_cursor:  defb 0
cursor_screen_row: defb 0
cursor_screen_col: defb 0

rp_li:         defb 0
rp_screenrow:  defb 0
rp_seg:        defb 0
rp_cursor_seg: defb 0
rp_segstart:   defw 0
rp_seglen:     defw 0

cur_line_row0: defb 0
cur_line_rows: defb 0

; etat du dernier rendu, pour decider si draw_screen peut se limiter a
; redessiner CURLINE seule (voir draw_screen) -- last_valid=0 force un
; rendu complet au premier appel.
last_valid:     defb 0
last_top:       defb 0
last_curline:   defb 0
last_linecount: defb 0
last_row0:      defb 0
last_rows:      defb 0

; derniere cellule mise en surbrillance (video inversee) pour le
; curseur -- permet de ne restaurer QUE cette cellule (au lieu de tout
; le plan d'attributs) quand le curseur bouge. Voir draw_screen.
prev_cursor_valid: defb 0
prev_cursor_row:   defb 0
prev_cursor_col:   defb 0

status_buf: defs 16
status_len: defb 0

    ; Bloc CODE simple (5 arguments) : le champ "adresse de chargement"
    ; de l'en-tete DOIT etre program_start (0x8000), pas _start --
    ; sinon le chargeur placerait le bloc au mauvais endroit en
    ; memoire (piege reel rencontre en testant : un 6e argument
    ; "autostart" a fait passer program_start dans le mauvais champ de
    ; l'en-tete). NOTE : un seul SAVETAP dans ce fichier, expres -- en
    ; sjasmplus 1.20.3, 2 directives SAVETAP dans le meme fichier
    ; dupliquent chacune leurs blocs (bug d'outillage reel rencontre en
    ; testant, verifie isole : 1 SAVETAP -> 2 blocs corrects, 2 SAVETAP
    ; -> 4 blocs, chacun ecrit deux fois). Le bloc BASIC autoloader
    ; (qui doit precede celui-ci sur la bande) est donc construit a
    ; part et prepende par tests/gen_loader.py, voir Makefile.
    SAVETAP "writhdeck.tap", CODE, "writhdeck", program_start, $ - program_start

    ; .sna additionnel (PC=_start directement) : uniquement pour les
    ; tests automatises (voir tests/test_main.py), qui evitent ainsi
    ; de rejouer LOAD "" + attente cassette a chaque execution. Le
    ; .tap ci-dessus (complete par gen_loader.py) reste le veritable
    ; livrable pour un usage reel.
    SAVESNA "writhdeck.sna", _start
