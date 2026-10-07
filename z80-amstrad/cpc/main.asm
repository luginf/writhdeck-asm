; main.asm -- point d'entree reel du portage Amstrad CPC : boucle
; principale clavier -> editor_*, dessin de l'ecran (word-wrap +
; defilement par ligne logique + barre de statut minimale
; ligne/colonne), sauvegarde/chargement cassette. Assemble directement
; (voir Makefile). Meme structure generale que spectrum/main.asm, mais
; SANS anti-rebond clavier a ecrire (le firmware CPC s'en charge, voir
; cpc/keyboard.asm) et SANS passe scr_set_attr separee (le curseur est
; surligne directement pendant le trace de la ligne, voir
; cpc/screen.asm) -- deux simplifications reelles rendues possibles
; par la plateforme, pas juste des raccourcis.
;
; Memes simplifications assumees que le portage Spectrum (coherentes
; avec le reste du projet) : pas de navigateur de fichiers (nom de
; bande fixe "WRITHDEK"), pas de confirmation a la fermeture,
; defilement par ligne logique (pas par rangee visuelle).
    DEVICE AMSTRADCPC464
    ORG 0x8000

program_start:
    ; voir le commentaire equivalent dans spectrum/main.asm : le bloc
    ; sauvegarde doit couvrir tout le code+donnees des modules inclus,
    ; pas seulement _start.

    include "../core/buffer.asm"
    include "../core/editor.asm"
    include "../cpc/screen.asm"
    include "../cpc/keyboard.asm"
    include "../cpc/tape.asm"

TEXT_ROWS = SCR_ROWS - 1   ; derniere rangee reservee a la barre de statut

; ============================================================
; num_to_ascii -- entree HL=valeur (0-9999), DE=pointeur destination.
; Ecrit les chiffres decimaux (sans zero de tete, "0" si HL=0), sortie
; DE=pointeur avance. Detruit AF, BC, HL. (identique au portage Spectrum)
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
; met a jour status_len. Detruit AF, BC, DE, HL.
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

; draw_status_bar -- dessine la barre de statut (derniere rangee),
; sans curseur dessus. Detruit AF, BC, DE, HL.
draw_status_bar:
    call build_status_line
    ld a, (status_len)
    ld b, a
    ld a, TEXT_ROWS
    ld hl, status_buf
    ld d, 0xFF
    call scr_put_line
    ret

; render_line_segments -- dessine les rangees ecran d'UNE ligne logique
; deja "wrappee" (wrap_count/wrap_segs valides pour elle) : entree
; rp_li=ligne, rp_cursor_seg=indice de segment du curseur (ou 0xFF),
; rp_screenrow=rangee de depart, rp_seg=0. Avance rp_screenrow/rp_seg,
; met a jour found_cursor/cursor_screen_row/col si le curseur est
; croise (surbrillance integree directement dans scr_put_line, voir
; cpc/screen.asm -- rien de plus a faire ici pour le curseur). Sortie
; (flag) : carry=1 si arrete faute de place ecran avant la fin de la
; ligne, carry=0 si la ligne a ete entierement dessinee. Detruit AF,
; BC, DE, HL. Extrait de render_pass pour etre reutilise tel quel par
; render_current_line_fast (voir draw_screen).
render_line_segments:
.seg_loop:
    ld a, (rp_seg)
    ld hl, wrap_count
    cp (hl)
    jp nc, .done_ok
    ld a, (rp_screenrow)
    cp TEXT_ROWS
    jp nc, .done_full

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

    ; determine si le curseur tombe sur ce segment -> colonne ecran, ou 0xFF
    ld a, 0xFF
    ld (rp_cursor_col), a
    ld a, (rp_seg)
    ld hl, rp_cursor_seg
    cp (hl)
    jr nz, .not_cursor_seg
    ld hl, (CURCOL)
    ld de, (rp_segstart)
    or a
    sbc hl, de
    ld a, l
    ld (rp_cursor_col), a
    ld a, (rp_screenrow)
    ld (cursor_screen_row), a
    ld a, (rp_cursor_col)
    ld (cursor_screen_col), a
    ld a, 1
    ld (found_cursor), a
.not_cursor_seg:

    ld a, (rp_li)
    call buffer_line_addr
    ld de, (rp_segstart)
    add hl, de

    ld a, (rp_seglen)
    ld b, a
    ld a, (rp_cursor_col)
    ld d, a
    ld a, (rp_screenrow)
    call scr_put_line

    ld a, (rp_screenrow)
    inc a
    ld (rp_screenrow), a
    ld a, (rp_seg)
    inc a
    ld (rp_seg), a
    jp .seg_loop
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
    jp c, .lines_done

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
; frequent en tapant), seule cette ligne est redessinee (quelques
; appels TXT_WR_CHAR firmware) au lieu de l'ecran entier (768 appels).
; Sinon (Entree/Suppr fusionnant des lignes/UP/DOWN/Undo/Redo/
; defilement), rendu complet comme avant. Detruit AF, BC, DE, HL.
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
    ret

; do_save -- sauve tout le document sur cassette (WRITHDEK). Detruit
; AF, BC, DE, HL.
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
    ; Contrairement au portage Spectrum (voir la note equivalente dans
    ; spectrum/main.asm), ICI on active les interruptions expres : le
    ; clavier firmware CPC (KM_WAIT_CHAR, voir cpc/keyboard.asm) est
    ; concu pour fonctionner AVEC l'interruption 300Hz standard (c'est
    ; elle qui fait avancer le scan clavier/l'anti-rebond en tache de
    ; fond) -- ce n'est pas optionnel ici, contrairement au Spectrum ou
    ; on avait notre propre lecture directe du port clavier. Pas de
    ; conflit attendu : on utilise les routines TXT_*/KM_* officielles
    ; du firmware pour tout (ecran, clavier), donc son gestionnaire
    ; d'interruption standard reste dans un etat qu'il gere lui-meme.
    ei
    call scr_init
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
rp_cursor_col: defb 0
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

status_buf: defs 16
status_len: defb 0

    SAVEBIN "writhdeck.bin", program_start, $-program_start
