; screen.asm -- rendu ecran bitmap ZX Spectrum (256x192, grille de
; caracteres 32x24), en reutilisant la police de la ROM 48K a $3D00
; (96 glyphes, codes ASCII 32-127, 8 octets/glyphe) -- pas besoin
; d'embarquer notre propre police. Specifique Spectrum (adressage
; bitmap entrelace par tiers) : ne fait PAS partie de core/.
;
; Adressage bitmap (formule standard ZX Spectrum) : pour une ligne de
; pixel Y (0-191) et une colonne d'octet X (0-31),
;   octet_haut = 0x40 | ((Y&0xC0)>>3) | (Y&0x07)
;   octet_bas  = ((Y&0x38)<<2) | X
; (voir scr__pixel_addr). Les attributs (encre/papier), eux, sont en
; adressage lineaire classique : ATTR_BASE + ligne*32 + colonne.

SCR_ROWS     equ 24
SCR_COLS     equ 32
FONT_BASE    equ 0x3D00
ATTR_BASE    equ 0x5800
ATTR_NORMAL  equ 0x38     ; encre noire, papier blanc
ATTR_REVERSE equ 0x07     ; encre blanche, papier noir (barre de statut/curseur)

; scr_clear -- efface le bitmap (noir) et remet l'attribut normal
; partout. Detruit AF, BC, DE, HL.
scr_clear:
    ld hl, 0x4000
    ld (hl), 0
    ld de, 0x4001
    ld bc, 6143
    ldir
    ld hl, ATTR_BASE
    ld (hl), ATTR_NORMAL
    ld de, ATTR_BASE+1
    ld bc, 767
    ldir
    ret

; scr__pixel_addr -- entree A=Y (ligne de pixel, 0-191), E=X (colonne
; d'octet, 0-31) ; sortie HL=adresse dans le bitmap. Detruit AF, BC.
scr__pixel_addr:
    ld b, a
    and 0xC0
    rrca
    rrca
    rrca
    or 0x40
    ld c, a
    ld a, b
    and 0x07
    or c
    ld h, a

    ld a, b
    and 0x38
    add a, a
    add a, a
    or e
    ld l, a
    ret

; scr_draw_char -- entree A=ligne(0-23), E=colonne(0-31), C=code
; caractere ASCII (32-127 -- la police ROM ne couvre que cette plage).
; Detruit AF, BC, DE, HL.
scr_draw_char:
    ; entree : A=ligne, E=colonne, C=caractere. On sauve TOUT de suite
    ; ligne/colonne en memoire scratch : le calcul d'adresse police a
    ; besoin de DE pour additionner FONT_BASE ("ld de,FONT_BASE" ecrase
    ; E, qui porte la colonne), et scr__pixel_addr utilise B comme
    ; registre de travail interne (ecraserait le caractere si on
    ; l'y stockait) -- deux pieges reels rencontres en testant, voir
    ; tests/test_screen.*.
    ld (sd_row), a
    ld a, e
    ld (sd_col), a

    ld a, c
    sub 32
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, FONT_BASE
    add hl, de
    ld (sd_fontaddr), hl

    ld a, (sd_row)
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    ld a, l                  ; A = ligne*8 = Y (0-184)
    ld hl, sd_col
    ld e, (hl)                ; E = colonne, relue depuis le scratch
    call scr__pixel_addr     ; -> HL = adresse ecran (scanline 0)
    ld (sd_scraddr), hl

    ld b, 8
.loop:
    ld hl, (sd_fontaddr)
    ld a, (hl)
    inc hl
    ld (sd_fontaddr), hl
    ld hl, (sd_scraddr)
    ld (hl), a
    ld a, h
    inc a
    ld h, a
    ld (sd_scraddr), hl
    djnz .loop
    ret

; scr_put_line -- entree A=ligne(0-23), HL=pointeur texte, B=longueur
; (clampee a SCR_COLS). Efface d'abord toute la ligne (espaces) puis
; dessine les caracteres -- meme discipline "toujours frais" que
; ui_put_str du portage x86. Detruit AF, BC, DE, HL.
scr_put_line:
    ld (spl_row), a
    ld (spl_ptr), hl
    ld a, b
    cp SCR_COLS
    jr c, .len_ok
    ld a, SCR_COLS
.len_ok:
    ld (spl_len), a

    xor a
    ld (spl_col), a
.clearloop:
    ld a, (spl_col)
    cp SCR_COLS
    jr z, .clear_done
    ld e, a
    ld a, (spl_row)
    ld c, ' '
    call scr_draw_char
    ld a, (spl_col)
    inc a
    ld (spl_col), a
    jr .clearloop
.clear_done:

    xor a
    ld (spl_col), a
.drawloop:
    ld a, (spl_col)
    ld hl, spl_len
    cp (hl)
    jr z, .draw_done
    ld hl, (spl_ptr)
    ld d, 0
    ld a, (spl_col)
    ld e, a
    add hl, de
    ld c, (hl)
    ld a, (spl_col)
    ld e, a
    ld a, (spl_row)
    call scr_draw_char
    ld a, (spl_col)
    inc a
    ld (spl_col), a
    jr .drawloop
.draw_done:
    ret

; scr_clear_line -- entree A=ligne. Efface toute la ligne (espaces).
; Detruit AF, BC, DE, HL.
scr_clear_line:
    ld hl, 0
    ld b, 0
    jp scr_put_line

; scr_set_attr -- entree A=ligne, E=colonne, B=longueur, C=attribut.
; Detruit AF, DE, HL.
scr_set_attr:
    ld d, 0
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                ; HL = ligne*32
    add hl, de                ; + colonne
    ld de, ATTR_BASE
    add hl, de                ; HL = adresse cible
    ld a, b
    or a
    ret z
.loop:
    ld (hl), c
    inc hl
    djnz .loop
    ret

; ============================================================
; donnees
; ============================================================
sd_scraddr:  defw 0
sd_fontaddr: defw 0
sd_row:      defb 0
sd_col:      defb 0

spl_row: defb 0
spl_ptr: defw 0
spl_len: defb 0
spl_col: defb 0
