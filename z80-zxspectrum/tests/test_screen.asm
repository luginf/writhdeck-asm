; test_screen.asm -- exercice spectrum/screen.asm : adresse bitmap
; (dont un franchissement de tiers), dessin de caractere (compare a la
; police ROM elle-meme, prise comme reference), scr_put_line (efface +
; dessine), scr_set_attr.
    DEVICE ZXSPECTRUM48
    ORG $8000

    include "../spectrum/screen.asm"

start:
    call scr_clear

    ; 'A' a (0,0) -- coin superieur gauche, cas trivial
    ld a, 0
    ld e, 0
    ld c, 'A'
    call scr_draw_char

    ; 'Z' a (8,5) -- ligne 8 = premiere ligne du 2e tiers de l'ecran
    ld a, 8
    ld e, 5
    ld c, 'Z'
    call scr_draw_char

    ; "Hi!" a la ligne 2 (le reste de la ligne doit etre efface -> espaces)
    ld a, 2
    ld hl, hi_str
    ld b, 3
    call scr_put_line

    ; attribut inverse sur les 5 premieres cases de la ligne 0
    ld a, 0
    ld e, 0
    ld b, 5
    ld c, ATTR_REVERSE
    call scr_set_attr

    ; verification independante de la formule d'adressage elle-meme
    ; (scr__pixel_addr prend Y=ligne DE PIXEL, pas la ligne de
    ; caractere -- Y = ligne_car*8, meme conversion que scr_draw_char)
    ld a, 0
    ld e, 0
    call scr__pixel_addr
    ld (snap_addr_a), hl

    ld a, 8*8
    ld e, 5
    call scr__pixel_addr
    ld (snap_addr_z), hl

loop:
    jr loop

hi_str: defm "Hi!"
snap_addr_a: defw 0
snap_addr_z: defw 0

    SAVESNA "test_screen.sna", start
