; test_editor.asm -- exercice core/editor.asm : undo (insertion et
; suppression), deplacement vertical avec word-wrap (meme ligne et
; changement de ligne), recherche insensible a la casse.
    DEVICE ZXSPECTRUM48
    ORG $8000

    include "../core/buffer.asm"
    include "../core/editor.asm"

start:
    call editor_init

    ; --- insertion "hi" puis undo (annule le dernier 'i') ---
    ld c, 'h'
    call editor_insert_codepoint
    ld c, 'i'
    call editor_insert_codepoint

    ld a, (CURCOL)              ; snapshot avant undo (juste la partie basse suffit, col<256 ici)
    ld (snapA_cx_before), a

    call editor_undo
    ld (snapA_undo_ret), a
    ld a, (CURLINE)
    ld (snapA_cy), a
    ld hl, (CURCOL)
    ld (snapA_cx), hl
    ld hl, (TEXTEND)
    ld (snapA_textend), hl
    ld hl, TEXTBUF
    ld de, snapA_text
    ld bc, 1
    ldir

    ; redo : doit restaurer "hi" et le curseur d'avant l'annulation
    call editor_redo
    ld (snapR_redo_ret), a
    ld a, (CURLINE)
    ld (snapR_cy), a
    ld hl, (CURCOL)
    ld (snapR_cx), hl
    ld hl, (TEXTEND)
    ld (snapR_textend), hl
    ld hl, TEXTBUF
    ld de, snapR_text
    ld bc, 2
    ldir

    ; deuxieme redo : plus rien a refaire -> doit renvoyer 0
    call editor_redo
    ld (snapR2_redo_ret), a

    ; deuxieme undo : plus rien a annuler -> doit renvoyer 0, ne rien changer
    call editor_undo
    ld (snapB_undo_ret), a
    ld hl, (TEXTEND)
    ld (snapB_textend), hl

    ; --- delete puis undo (reinsertion) ---
    ld a, 0
    ld hl, 0
    call editor_set_cursor
    call editor_delete              ; supprime le 'h' restant -> buffer vide
    ld hl, (TEXTEND)
    ld (snapC_textend_after_delete), hl

    call editor_undo
    ld (snapC_undo_ret), a
    ld a, (CURLINE)
    ld (snapC_cy), a
    ld hl, (CURCOL)
    ld (snapC_cx), hl
    ld hl, (TEXTEND)
    ld (snapC_textend), hl
    ld hl, TEXTBUF
    ld de, snapC_text
    ld bc, 1
    ldir

    ; --- word-wrap : ligne0 = 40 chiffres (deborde 32 colonnes), ligne1 = "end" ---
    call editor_init
    ld hl, wrap_src
    ld de, TEXTBUF
    ld bc, 44                      ; 40 chiffres + LF + "end" (3) = 44
    ldir
    ld hl, TEXTBUF
    ld de, 44
    add hl, de
    ld (TEXTEND), hl
    call buffer_rebuild_linetab

    ; positionner le curseur ligne=0, col=35 (2e rangee visuelle, offset 3)
    ld a, 0
    ld hl, 35
    call editor_set_cursor

    call editor_move_up
    ld a, (CURLINE)
    ld (snapD_up_cy), a
    ld hl, (CURCOL)
    ld (snapD_up_cx), hl

    call editor_move_down
    ld a, (CURLINE)
    ld (snapE_down_cy), a
    ld hl, (CURCOL)
    ld (snapE_down_cx), hl

    ; re-descendre : doit passer sur la ligne suivante ("end")
    call editor_move_down
    ld a, (CURLINE)
    ld (snapF_cross_cy), a
    ld hl, (CURCOL)
    ld (snapF_cross_cx), hl

    ; --- recherche insensible a la casse ---
    call editor_init
    ld hl, find_src
    ld de, TEXTBUF
    ld bc, 13
    ldir
    ld hl, TEXTBUF
    ld de, 13
    add hl, de
    ld (TEXTEND), hl
    call buffer_rebuild_linetab

    ld a, 0
    ld hl, 0
    call editor_set_cursor
    ld hl, find_needle
    call editor_find
    ld (snapG_found), a
    ld a, (CURLINE)
    ld (snapG_cy), a
    ld hl, (CURCOL)
    ld (snapG_cx), hl

loop:
    jr loop

wrap_src:   defm "0123456789012345678901234567890123456789"
            defb 10
            defm "end"

find_src:   defm "Chat CHAT ok"
            defb 10
find_needle: defm "chat", 0

snapA_cx_before: defb 0
snapA_undo_ret:  defb 0
snapA_cy:        defb 0
snapA_cx:        defw 0
snapA_textend:   defw 0
snapA_text:      defs 1

snapR_redo_ret:  defb 0
snapR_cy:        defb 0
snapR_cx:        defw 0
snapR_textend:   defw 0
snapR_text:      defs 2
snapR2_redo_ret: defb 0

snapB_undo_ret:  defb 0
snapB_textend:   defw 0

snapC_textend_after_delete: defw 0
snapC_undo_ret:  defb 0
snapC_cy:        defb 0
snapC_cx:        defw 0
snapC_textend:   defw 0
snapC_text:      defs 1

snapD_up_cy:   defb 0
snapD_up_cx:   defw 0
snapE_down_cy: defb 0
snapE_down_cx: defw 0
snapF_cross_cy: defb 0
snapF_cross_cx: defw 0

snapG_found: defb 0
snapG_cy:    defb 0
snapG_cx:    defw 0

    SAVESNA "test_editor.sna", start
