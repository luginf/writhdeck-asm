; editor.asm -- etat d'edition (curseur, undo 1 niveau, word-wrap,
; recherche) par-dessus core/buffer.asm. Independant de la plateforme.
; Portage adapte de writhdeck-c/src/editor.c et du portage x86, avec
; deux differences assumees (voir le plan) :
;   - undo a 1 seul niveau (pas de pile de clones -- irrealiste sur
;     48 Ko), stocke comme {type, adresse, octet} suffisant pour
;     REJOUER l'inverse exact de la derniere operation destructrice ;
;   - pas de "colonne collante" persistante entre plusieurs pressions
;     UP/DOWN consecutives : chaque mouvement vertical recalcule sa
;     position depuis la colonne courante (offset dans la rangee
;     visuelle), ce qui reste un comportement raisonnable mais plus
;     simple que le x86.
;
; Attendu inclus APRES core/buffer.asm (utilise buffer_*, buf_*,
; cp_hl_de, LINETAB, LINECOUNT, TEXTEND, TEXTBUF, tmp_pos, tmp_byte).

    include "layout.inc"

; ============================================================
; API publique
; ============================================================

; editor_init -- reinitialise l'editeur (curseur en (0,0), pas de
; modification en attente, pas d'annulation disponible).
editor_init:
    xor a
    ld (CURLINE), a
    ld hl, 0
    ld (CURCOL), hl
    xor a
    ld (DIRTY), a
    ld (UNDO_VALID), a
    ld (REDO_VALID), a
    jp buffer_init

; editor_insert_codepoint -- entree C=caractere. Insere a la position
; courante, avance le curseur d'une colonne. Detruit AF, BC, DE, HL.
editor_insert_codepoint:
    call ed__save_undo_cursor
    ld a, (CURLINE)
    ld hl, (CURCOL)
    call buffer_insert_char

    xor a
    ld (UNDO_TYPE), a        ; 0 = annuler une insertion (-> supprimer)
    ld hl, (tmp_pos)
    ld (UNDO_ADDR), hl
    ld a, 1
    ld (UNDO_VALID), a

    ld hl, (CURCOL)
    inc hl
    ld (CURCOL), hl
    ld a, 1
    ld (DIRTY), a
    ret

; editor_enter -- coupe la ligne courante a la colonne courante (touche
; Entree), place le curseur en debut de la nouvelle ligne.
; Detruit AF, BC, DE, HL.
editor_enter:
    call ed__save_undo_cursor
    ld a, (CURLINE)
    ld hl, (CURCOL)
    call buffer_split_line

    xor a
    ld (UNDO_TYPE), a
    ld hl, (tmp_pos)
    ld (UNDO_ADDR), hl
    ld a, 1
    ld (UNDO_VALID), a

    ld a, (CURLINE)
    inc a
    ld (CURLINE), a
    ld hl, 0
    ld (CURCOL), hl
    ld a, 1
    ld (DIRTY), a
    ret

; editor_backspace -- touche Retour arriere. No-op en tout debut de
; document. Detruit AF, BC, DE, HL.
editor_backspace:
    ld a, (CURLINE)
    or a
    jr nz, .proceed
    ld hl, (CURCOL)
    ld a, h
    or l
    ret z
.proceed:
    call ed__save_undo_cursor
    ld a, (CURLINE)
    ld hl, (CURCOL)
    call buffer_backspace       ; sortie : A=nouvelle ligne, HL=nouvelle colonne
    ld (CURLINE), a
    ld (CURCOL), hl

    ld a, 1
    ld (UNDO_TYPE), a           ; 1 = annuler une suppression (-> reinserer)
    ld hl, (tmp_pos)
    ld (UNDO_ADDR), hl
    ld a, (tmp_byte)
    ld (UNDO_BYTE), a
    ld a, 1
    ld (UNDO_VALID), a

    ld a, 1
    ld (DIRTY), a
    ret

; editor_delete -- touche Suppr. No-op en toute fin de document.
; Ne deplace jamais le curseur. Detruit AF, BC, DE, HL.
editor_delete:
    ld a, (CURLINE)
    call buffer_line_length
    ld (ed_len), hl
    ld hl, (CURCOL)
    ld de, (ed_len)
    call cp_hl_de               ; C : CURCOL<longueur -> pas en fin de ligne
    jr c, .do_delete

    ld a, (LINECOUNT)
    dec a
    ld b, a
    ld a, (CURLINE)
    cp b
    ret z                       ; derniere ligne -> fin de document -> rien a faire

.do_delete:
    call ed__save_undo_cursor
    ld a, (CURLINE)
    ld hl, (CURCOL)
    call buffer_delete_char

    ld a, 1
    ld (UNDO_TYPE), a
    ld hl, (tmp_pos)
    ld (UNDO_ADDR), hl
    ld a, (tmp_byte)
    ld (UNDO_BYTE), a
    ld a, 1
    ld (UNDO_VALID), a

    ld a, 1
    ld (DIRTY), a
    ret

; editor_undo -- annule la derniere operation destructrice (1 niveau).
; Peuple aussi la case de refaire (1 niveau) avec l'inverse exact de ce
; que cette annulation vient de faire, pour qu'un editor_redo immediat
; restaure l'etat d'avant l'annulation. Sortie : A=1 si une annulation
; a eu lieu, 0 si rien a annuler. Detruit AF, BC, DE, HL.
editor_undo:
    ld a, (UNDO_VALID)
    or a
    ret z

    xor a
    ld (UNDO_VALID), a          ; un seul niveau : consomme l'entree

    ; la case de refaire doit restaurer le curseur A LA POSITION
    ; ACTUELLE (avant que cette annulation ne le deplace)
    ld a, (CURLINE)
    ld (REDO_LINE), a
    ld hl, (CURCOL)
    ld (REDO_COL), hl
    ld hl, (UNDO_ADDR)
    ld (REDO_ADDR), hl

    ld a, (UNDO_TYPE)
    or a
    jr nz, .undo_delete

    ; UNDO_TYPE=0 (l'action d'annulation est une SUPPRESSION, elle
    ; annule une insertion d'origine) -- pour refaire, il faudra
    ; RE-INSERER l'octet que l'on s'apprete a supprimer ici.
    ld a, 1
    ld (REDO_TYPE), a
    ld hl, (UNDO_ADDR)
    call buf_delete_byte
    ld (REDO_BYTE), a
    jr .restore

.undo_delete:
    ; UNDO_TYPE=1 (l'action d'annulation est une INSERTION, elle
    ; annule une suppression d'origine) -- pour refaire, il faudra
    ; SUPPRIMER de nouveau (pas besoin d'octet pour cette action).
    xor a
    ld (REDO_TYPE), a
    ld hl, (UNDO_ADDR)
    ld a, (UNDO_BYTE)
    call buf_insert_byte

.restore:
    ld a, 1
    ld (REDO_VALID), a
    ld a, (UNDO_LINE)
    ld (CURLINE), a
    ld hl, (UNDO_COL)
    ld (CURCOL), hl
    ld a, 1
    ld (DIRTY), a
    ld a, 1
    ret

; editor_redo -- refait la derniere annulation (1 niveau, "coup pour
; coup" -- ne repeuple pas la case d'annulation : pas de va-et-vient
; infini, coherent avec le choix "1 seul niveau"). Sortie : A=1 si un
; refaire a eu lieu, 0 sinon. Detruit AF, BC, DE, HL.
editor_redo:
    ld a, (REDO_VALID)
    or a
    ret z

    xor a
    ld (REDO_VALID), a

    ld a, (REDO_TYPE)
    or a
    jr nz, .redo_insert

    ld hl, (REDO_ADDR)
    call buf_delete_byte
    jr .restore2

.redo_insert:
    ld hl, (REDO_ADDR)
    ld a, (REDO_BYTE)
    call buf_insert_byte

.restore2:
    ld a, (REDO_LINE)
    ld (CURLINE), a
    ld hl, (REDO_COL)
    ld (CURCOL), hl
    ld a, 1
    ld (DIRTY), a
    ld a, 1
    ret

; editor_move_left / editor_move_right / editor_move_home / editor_move_end
editor_move_left:
    ld hl, (CURCOL)
    ld a, h
    or l
    jr z, .try_prev
    dec hl
    ld (CURCOL), hl
    ret
.try_prev:
    ld a, (CURLINE)
    or a
    ret z
    dec a
    ld (CURLINE), a
    call buffer_line_length
    ld (CURCOL), hl
    ret

editor_move_right:
    ld a, (CURLINE)
    call buffer_line_length
    ex de, hl                   ; DE = longueur
    ld hl, (CURCOL)
    call cp_hl_de                ; C : CURCOL<longueur
    jr c, .advance

    ld a, (LINECOUNT)
    dec a
    ld b, a
    ld a, (CURLINE)
    cp b
    ret z
    inc a
    ld (CURLINE), a
    ld hl, 0
    ld (CURCOL), hl
    ret
.advance:
    ld hl, (CURCOL)
    inc hl
    ld (CURCOL), hl
    ret

editor_move_home:
    ld hl, 0
    ld (CURCOL), hl
    ret

editor_move_end:
    ld a, (CURLINE)
    call buffer_line_length
    ld (CURCOL), hl
    ret

; editor_set_cursor -- entree A=ligne, HL=colonne ; clampe aux bornes
; reelles du document. Detruit AF, BC, DE, HL.
editor_set_cursor:
    ld (CURLINE), a
    ld (CURCOL), hl

    ld a, (LINECOUNT)
    dec a
    ld b, a
    ld a, (CURLINE)
    cp b
    jr z, .line_ok
    jr c, .line_ok
    ld a, b
    ld (CURLINE), a
.line_ok:
    ld a, (CURLINE)
    call buffer_line_length
    ld (ed_maxcol), hl
    ld hl, (CURCOL)
    ld de, (ed_maxcol)
    call cp_hl_de
    ret c
    ld hl, (ed_maxcol)
    ld (CURCOL), hl
    ret

; editor_move_up / editor_move_down -- deplacement par RANGEE VISUELLE
; (word-wrap a SCREEN_COLS), pas par ligne logique. Detruit AF, BC, DE, HL.
editor_move_up:
    ld a, (CURLINE)
    ld de, (CURCOL)
    call editor__wrap_and_find   ; -> wf_idx, wf_start (pour CURLINE/CURCOL)

    ld hl, (CURCOL)
    ld de, (wf_start)
    or a
    sbc hl, de
    ex de, hl                    ; DE = offset dans la rangee courante

    ld a, (wf_idx)
    or a
    jr nz, .same_line

    ld (ed_pending_offset), de
    ld a, (CURLINE)
    or a
    ret z                        ; deja tout en haut du document
    dec a
    ld (CURLINE), a
    call editor_wrap_line        ; recalcule pour la NOUVELLE ligne courante
    ld de, (ed_pending_offset)
    ld a, (wrap_count)
    dec a                        ; derniere rangee de la ligne precedente
    jp editor__set_col_from_segment

.same_line:
    dec a
    jp editor__set_col_from_segment

editor_move_down:
    ld a, (CURLINE)
    ld de, (CURCOL)
    call editor__wrap_and_find

    ld hl, (CURCOL)
    ld de, (wf_start)
    or a
    sbc hl, de
    ex de, hl                    ; DE = offset

    ld a, (wf_idx)
    inc a
    ld b, a
    ld a, (wrap_count)
    cp b
    jr nz, .same_line_down

    ld (ed_pending_offset), de
    ld a, (LINECOUNT)
    dec a
    ld b, a
    ld a, (CURLINE)
    cp b
    ret z                        ; deja tout en bas du document
    inc a
    ld (CURLINE), a
    call editor_wrap_line
    ld de, (ed_pending_offset)
    xor a                        ; premiere rangee de la ligne suivante
    jp editor__set_col_from_segment

.same_line_down:
    ld a, b
    jp editor__set_col_from_segment

; editor_word_count -- sortie HL = nombre de mots (voir buffer_word_count).
editor_word_count:
    jp buffer_word_count

; editor_find -- entree HL=adresse d'un terme (chaine nul-terminee).
; Recherche insensible a la casse ASCII, en repartant juste apres le
; curseur et en bouclant circulairement sur tout le buffer (equivalent,
; simplifie, de editor_find cote x86 : ici un seul balayage circulaire
; sur le blob contigu, pas un parcours ligne par ligne, puisque
; TEXTBUF[0..TEXTEND) est deja un flux continu). Sortie : A=1 si trouve
; (curseur deplace), 0 sinon. Detruit AF, BC, DE, HL.
editor_find:
    ld (ef_term), hl
    ld a, h
    or l
    jr z, .not_found
    ld a, (hl)
    or a
    jr z, .not_found

    ld a, (CURLINE)
    call buffer_line_addr
    ld de, (CURCOL)
    add hl, de
    inc hl
    ld (ef_search_from), hl

    ld hl, (ef_search_from)
.phase1:
    ld de, (TEXTEND)
    call cp_hl_de
    jr nc, .phase2_start
    ld (ef_scan_pos), hl    ; sauver AVANT l'appel : ef__match_at utilise
                            ; HL comme registre de travail interne et ne
                            ; le laisse PAS pointer sur le debut de la
                            ; correspondance en sortie.
    call ef__match_at
    jr z, .found_here
    ld hl, (ef_scan_pos)
    inc hl
    jr .phase1

.phase2_start:
    ld hl, TEXTBUF
.phase2:
    ld de, (ef_search_from)
    call cp_hl_de
    jr nc, .not_found
    ld (ef_scan_pos), hl
    call ef__match_at
    jr z, .found_here
    ld hl, (ef_scan_pos)
    inc hl
    jr .phase2

.found_here:
    ld hl, (ef_scan_pos)
    call ef__addr_to_linecol
    ld (CURLINE), a
    ld (CURCOL), hl
    ld a, 1
    ret
.not_found:
    xor a
    ret

; ============================================================
; aides internes
; ============================================================

; ed__save_undo_cursor -- enregistre (CURLINE,CURCOL) courants dans la
; case d'annulation, AVANT une operation destructrice (meme discipline
; que le x86 : jamais apres). Invalide aussi la case de refaire (toute
; nouvelle modification invalide l'historique de refaire, meme regle
; que le x86). Detruit AF, HL.
ed__save_undo_cursor:
    ld a, (CURLINE)
    ld (UNDO_LINE), a
    ld hl, (CURCOL)
    ld (UNDO_COL), hl
    xor a
    ld (REDO_VALID), a
    ret

; editor_wrap_line -- entree A=ligne. Remplit wrap_segs[]/wrap_count
; (word-wrap glouton a SCREEN_COLS, coupe sur espace si possible, coupe
; brute sinon -- meme algorithme que editor_wrap cote x86, une seule
; ligne logique a la fois, pas de tableau global pour tout le document).
; Detruit AF, BC, DE, HL.
editor_wrap_line:
    ld (wl_line), a
    call buffer_line_length
    ld (wl_len), hl
    xor a
    ld (wrap_count), a

    ld a, h
    or l
    jr nz, .nonempty
    ld hl, wrap_segs
    ld (hl), 0
    inc hl
    ld (hl), 0
    inc hl
    ld (hl), 0
    inc hl
    ld (hl), 0
    ld a, 1
    ld (wrap_count), a
    ret

.nonempty:
    ld hl, 0
    ld (wl_start), hl
.seg_loop:
    ld hl, (wl_start)
    ld de, (wl_len)
    call cp_hl_de
    jp nc, .done

    ld hl, (wl_len)
    ld de, (wl_start)
    or a
    sbc hl, de
    ld (wl_remaining), hl

    ld hl, (wl_remaining)
    ld de, SCREEN_COLS
    call cp_hl_de               ; C : remaining<32
    jr c, .take_is_remaining
    ld hl, SCREEN_COLS
.take_is_remaining:
    ld (wl_take), hl

    ld hl, (wl_take)
    ld de, (wl_remaining)
    call cp_hl_de                ; C : take<remaining -> chercher un espace
    jr nc, .have_take

    ld hl, (wl_start)
    ld de, (wl_take)
    add hl, de
    dec hl
    ld (wl_p), hl
.search:
    ld hl, (wl_p)
    ld de, (wl_start)
    call cp_hl_de
    jr c, .have_take
    jr z, .have_take
    ld a, (wl_line)
    call buffer_line_addr
    ld de, (wl_p)
    add hl, de
    ld a, (hl)
    cp ' '
    jr z, .found_space
    ld hl, (wl_p)
    dec hl
    ld (wl_p), hl
    jr .search
.found_space:
    ld hl, (wl_p)
    ld de, (wl_start)
    or a
    sbc hl, de
    ld (wl_take), hl
.have_take:
    ld a, (wrap_count)
    ld b, a
    ld h, 0
    ld l, b
    add hl, hl
    add hl, hl
    ld de, wrap_segs
    add hl, de
    ld de, (wl_start)
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl
    ld de, (wl_take)
    ld (hl), e
    inc hl
    ld (hl), d
    ld a, (wrap_count)
    inc a
    ld (wrap_count), a

    ld hl, (wl_start)
    ld de, (wl_take)
    add hl, de
    ld (wl_start), hl

.skip_spaces:
    ld hl, (wl_start)
    ld de, (wl_len)
    call cp_hl_de
    jp nc, .seg_loop
    ld a, (wl_line)
    call buffer_line_addr
    ld de, (wl_start)
    add hl, de
    ld a, (hl)
    cp ' '
    jp nz, .seg_loop
    ld hl, (wl_start)
    inc hl
    ld (wl_start), hl
    jr .skip_spaces
.done:
    ret

; editor__wrap_and_find -- entree A=ligne, DE=colonne. Calcule le
; word-wrap de cette ligne (editor_wrap_line) puis trouve l'indice de
; segment contenant la colonne donnee -> wf_idx, wf_start, wf_len.
; Detruit AF, BC, DE, HL.
editor__wrap_and_find:
    ld (wf_col), de
    call editor_wrap_line
    xor a
    ld (wf_idx), a
.loop:
    ld a, (wf_idx)
    ld b, a
    ld a, (wrap_count)
    cp b
    jr z, .use_last

    ld h, 0
    ld l, b
    add hl, hl
    add hl, hl
    ld de, wrap_segs
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (wf_start), de
    inc hl
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (wf_len), de

    ld hl, (wf_start)
    ld de, (wf_len)
    add hl, de
    ld (wf_rowend), hl

    ld a, (wf_idx)
    inc a
    ld b, a
    ld a, (wrap_count)
    cp b
    jr nz, .not_last_seg
    ld a, 1
    ld (wf_islast), a
    jr .have_islast
.not_last_seg:
    xor a
    ld (wf_islast), a
.have_islast:

    ld hl, (wf_col)
    ld de, (wf_start)
    call cp_hl_de                ; C : col<start -> pas ce segment
    jr c, .next

    ld a, (wf_islast)
    or a
    jr nz, .check_last

    ld hl, (wf_col)
    ld de, (wf_rowend)
    call cp_hl_de                ; C : col<rowend -> trouve
    jr c, .found
    jr .next
.check_last:
    ld hl, (wf_col)
    ld de, (wf_rowend)
    call cp_hl_de
    jr c, .found
    jr z, .found
    jr .next
.next:
    ld a, (wf_idx)
    inc a
    ld (wf_idx), a
    jr .loop

.use_last:
    ld a, (wrap_count)
    dec a
    ld (wf_idx), a
    ld b, a
    ld h, 0
    ld l, b
    add hl, hl
    add hl, hl
    ld de, wrap_segs
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (wf_start), de
    inc hl
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (wf_len), de
.found:
    ret

; editor__set_col_from_segment -- entree A=indice de segment (dans
; wrap_segs, deja calcule pour CURLINE par editor_wrap_line), DE=offset
; souhaite depuis le debut de la rangee. Fixe CURCOL = segment.start +
; min(offset, segment.len). Detruit AF, BC, DE, HL.
editor__set_col_from_segment:
    ld (ed_offset), de
    ld b, a
    ld h, 0
    ld l, b
    add hl, hl
    add hl, hl
    ld de, wrap_segs
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (ed_newstart), de
    inc hl
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (ed_newlen), de

    ld hl, (ed_offset)
    ld de, (ed_newlen)
    call cp_hl_de
    jr c, .off_ok
    ld hl, (ed_newlen)
.off_ok:
    ld de, (ed_newstart)
    add hl, de
    ld (CURCOL), hl
    ret

; ef__tolower -- entree/sortie A. Replie 'A'-'Z' vers 'a'-'z' (ASCII
; seulement, coherent avec le jeu de caracteres de cette cible).
ef__tolower:
    cp 'A'
    ret c
    cp 'Z'+1
    ret nc
    add a, 32
    ret

; ef__match_at -- entree HL=position dans TEXTBUF, ef_term=terme.
; Sortie (flag) : Z si le terme correspond (insensible a la casse) a
; partir de HL, NZ sinon. Detruit AF, DE, HL.
ef__match_at:
    ld de, (ef_term)
    ld (ef_needle_ptr), de
    ld (ef_hay_ptr), hl
.loop:
    ld hl, (ef_needle_ptr)
    ld a, (hl)
    or a
    jr z, .match
    ld hl, (ef_hay_ptr)
    ld de, (TEXTEND)
    call cp_hl_de
    jr nc, .no_match
    ld a, (hl)
    call ef__tolower
    ld b, a
    ld hl, (ef_needle_ptr)
    ld a, (hl)
    call ef__tolower
    cp b
    jr nz, .no_match
    ld hl, (ef_needle_ptr)
    inc hl
    ld (ef_needle_ptr), hl
    ld hl, (ef_hay_ptr)
    inc hl
    ld (ef_hay_ptr), hl
    jr .loop
.match:
    xor a
    ret
.no_match:
    or 1
    ret

; ef__addr_to_linecol -- entree HL=adresse absolue. Sortie : A=ligne,
; HL=colonne (recherche lineaire dans LINETAB). Detruit AF, BC, DE, HL.
ef__addr_to_linecol:
    ld (ef_addr), hl
    xor a
    ld (ef_i), a
    xor a
    ld (ef_besti), a
.scan:
    ld a, (ef_i)
    ld b, a
    ld a, (LINECOUNT)
    cp b
    jr z, .scan_done
    ld h, 0
    ld l, b
    add hl, hl
    ld de, LINETAB
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld hl, (ef_addr)
    call cp_hl_de                ; C : addr<LINETAB[i] -> arreter
    jr c, .scan_done
    ld a, (ef_i)
    ld (ef_besti), a
    ld a, (ef_i)
    inc a
    ld (ef_i), a
    jr .scan
.scan_done:
    ld a, (ef_besti)
    call buffer_line_addr
    ex de, hl
    ld hl, (ef_addr)
    or a
    sbc hl, de
    ld a, (ef_besti)
    ret

; ============================================================
; donnees
; ============================================================
CURLINE:   defb 0
CURCOL:    defw 0
DIRTY:     defb 0

UNDO_VALID: defb 0
UNDO_TYPE:  defb 0     ; 0=annuler une insertion (-> delete) ; 1=annuler une suppression (-> insert)
UNDO_ADDR:  defw 0
UNDO_BYTE:  defb 0
UNDO_LINE:  defb 0
UNDO_COL:   defw 0

REDO_VALID: defb 0
REDO_TYPE:  defb 0     ; 0=action refaire = supprimer ; 1=action refaire = inserer
REDO_ADDR:  defw 0
REDO_BYTE:  defb 0
REDO_LINE:  defb 0
REDO_COL:   defw 0

ed_len:            defw 0
ed_offset:         defw 0
ed_newstart:       defw 0
ed_newlen:         defw 0
ed_pending_offset: defw 0
ed_maxcol:         defw 0

wl_line:      defb 0
wl_len:       defw 0
wl_start:     defw 0
wl_remaining: defw 0
wl_take:      defw 0
wl_p:         defw 0

wrap_count: defb 0
wrap_segs:  defs MAX_WRAP_SEGS*4

wf_col:     defw 0
wf_idx:     defb 0
wf_start:   defw 0
wf_len:     defw 0
wf_rowend:  defw 0
wf_islast:  defb 0

ef_term:        defw 0
ef_needle_ptr:  defw 0
ef_hay_ptr:     defw 0
ef_search_from: defw 0
ef_scan_pos:    defw 0
ef_addr:        defw 0
ef_i:           defb 0
ef_besti:       defb 0
