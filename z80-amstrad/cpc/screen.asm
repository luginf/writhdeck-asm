; screen.asm -- rendu ecran Amstrad CPC, via la ROM firmware (routines
; TXT_*/SCR_* du jumpblock, adresses fixes et stables sur tout CPC
; 464/664/6128) plutot qu'un adressage bitmap direct comme cote
; Spectrum : le firmware CPC gere deja le texte en mode caracteres
; (pas de police a embarquer, pas de calcul d'adresse bitmap a la
; main). Specifique Amstrad : ne fait PAS partie de core/.
;
; Pas de plan d'attributs separe comme le Spectrum (ATTR_BASE) : sur
; CPC, une fois un caractere trace, sa couleur est figee dans les
; pixels deja dessines -- impossible de la "recolorer" sans redessiner
; le caractere. scr_put_line integre donc directement la surbrillance
; du curseur DANS la boucle de trace (elle connait le vrai caractere a
; cet endroit), plutot qu'un scr_set_attr() a part comme cote Spectrum
; (main.asm de cette plateforme n'appelle donc pas scr_set_attr -- ce
; nom n'existe pas ici, differemment de spectrum/screen.asm).

SCR_ROWS     equ 25
SCR_COLS     equ 32     ; n'utilise que 32 des 40 colonnes du MODE 1
                         ; (SCREEN_COLS de core/layout.inc reste a 32,
                         ; commun aux deux portages -- voir Makefile)

; -- jumpblock firmware (adresses fixes, stables sur tout CPC) --
TXT_INITIALISE  equ 0xBB6C
TXT_WR_CHAR     equ 0xBB5D   ; A=caractere, PAS d'interpretation de code de controle
TXT_SET_CURSOR  equ 0xBB75   ; H=colonne(1-based), L=ligne(1-based)
TXT_CUR_OFF     equ 0xBB7E
TXT_CLEAR_WINDOW equ 0xBB88
TXT_SET_PEN     equ 0xBB90   ; A=encre (0-3 en MODE 1)
TXT_SET_PAPER   equ 0xBB96   ; A=encre
SCR_SET_MODE    equ 0xBC0E   ; A=mode (1 = 40 colonnes, 4 couleurs)

PEN_NORMAL  equ 1   ; encre normale (texte)
PAPER_NORMAL equ 0  ; fond normal
PEN_REVERSE  equ 0  ; encre du curseur (= papier normal, pour inverser)
PAPER_REVERSE equ 1 ; fond du curseur (= encre normale)

; scr_init -- MODE 1, couleurs par defaut, curseur texte firmware
; masque (on dessine notre propre surbrillance de curseur -- pas
; besoin du curseur clignotant du firmware). Detruit AF.
scr_init:
    call TXT_INITIALISE
    ld a, 1
    call SCR_SET_MODE
    ld a, PEN_NORMAL
    call TXT_SET_PEN
    ld a, PAPER_NORMAL
    call TXT_SET_PAPER
    call TXT_CUR_OFF
    ret

; scr_clear -- efface tout l'ecran (couleurs normales). Detruit AF.
scr_clear:
    jp TXT_CLEAR_WINDOW

; scr_put_line -- entree A=ligne(0-24), HL=pointeur texte, B=longueur
; (clampee a SCR_COLS), D=colonne du curseur a surligner dans CETTE
; ligne (0-31), ou 0xFF si le curseur n'est pas sur cette ligne.
; Dessine SCR_COLS caracteres (espaces au-dela de la longueur reelle,
; meme discipline "toujours frais" que le portage Spectrum), en
; inversant encre/papier le temps du seul caractere du curseur.
; Detruit AF, BC, DE, HL.
scr_put_line:
    ld (spl_ptr), hl
    ld (spl_cursor), a       ; reutilise temporairement, ecrase juste apres
    ld c, a                  ; C = ligne (0-based)
    ld a, b
    cp SCR_COLS
    jr c, .len_ok
    ld a, SCR_COLS
.len_ok:
    ld (spl_len), a
    ld a, d
    ld (spl_cursor), a

    ld a, c
    inc a                    ; firmware = 1-based
    ld l, a
    ld h, 1                  ; colonne 1 (debut de ligne)
    call TXT_SET_CURSOR

    xor a
    ld (spl_col), a
.loop:
    ld a, (spl_col)
    cp SCR_COLS
    jr z, .done

    ld hl, spl_len
    cp (hl)
    jr nc, .is_space
    ld hl, (spl_ptr)
    ld e, a
    ld d, 0
    add hl, de
    ld a, (hl)
    jr .have_char
.is_space:
    ld a, ' '
.have_char:
    ld b, a                  ; B = caractere a tracer

    ld a, (spl_col)
    ld hl, spl_cursor
    cp (hl)
    jr nz, .normal_pen
    push bc
    ld a, PEN_REVERSE
    call TXT_SET_PEN
    ld a, PAPER_REVERSE
    call TXT_SET_PAPER
    pop bc
    ld a, b
    call TXT_WR_CHAR
    ld a, PEN_NORMAL
    call TXT_SET_PEN
    ld a, PAPER_NORMAL
    call TXT_SET_PAPER
    jr .advance
.normal_pen:
    ld a, b
    call TXT_WR_CHAR
.advance:
    ld a, (spl_col)
    inc a
    ld (spl_col), a
    jr .loop
.done:
    ret

; scr_clear_line -- entree A=ligne. Efface toute la ligne (espaces),
; sans curseur. Detruit AF, BC, DE, HL.
scr_clear_line:
    ld hl, 0
    ld b, 0
    ld d, 0xFF
    jp scr_put_line

; ============================================================
; donnees
; ============================================================
spl_ptr:    defw 0
spl_len:    defb 0
spl_col:    defb 0
spl_cursor: defb 0
