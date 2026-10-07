; keyboard.asm -- lecture clavier Amstrad CPC via le firmware
; (KM_WAIT_CHAR, routine ROM mature qui gere DEJA le debounce, la
; repetition automatique et la traduction des touches -- pas de scan
; de matrice a la main comme cote Spectrum, et donc PAS besoin de
; reinventer l'anti-rebond/les combinaisons qui ont pose tant de
; problemes sur ce portage-la). Specifique Amstrad : ne fait PAS
; partie de core/.
;
; Le clavier CPC a de VRAIES touches curseur (haut/bas/gauche/droite)
; et une VRAIE touche CONTROL -- contrairement au Spectrum 48K/128 qui
; n'a ni l'un ni l'autre. Consequence directe sur les conventions :
;   - fleches : les vraies touches curseur, pas de combinaison CAPS+
;     chiffre a simuler (voir spectrum/keyboard.asm : ZX_ARROWS_VIA_CAPS
;     est desactive par defaut la-bas precisement parce que le 48K n'a
;     pas ce luxe).
;   - CONTROL+lettre : le firmware traduit nativement CONTROL+lettre en
;     code de controle ASCII (1-26, A=1..Z=26) -- Sauver/Quitter/
;     Annuler/Refaire utilisent donc CTRL+S/Q/Z/Y, plus proche des
;     conventions d'edition modernes que le SYMBOL SHIFT+lettre du
;     Spectrum (qui n'existe pas sur cette machine de toute facon).
;   - touche DEL (retour arriere) : code 127 (firmware).
;
; NOTE (a verifier sur materiel/emulateur reel avec vrai clavier PPI --
; voir README) : les codes de touches speciales ci-dessous sont ceux
; documentes pour le firmware CPC standard (table de traduction
; "ASCII"). Ils n'ont pu etre verifies dans cet environnement que pour
; les caracteres imprimables et ENTREE (voir tests/) -- fleches/CTRL+
; lettre a confirmer des qu'un clavier reel ou un emulateur pilotable
; est disponible.

KEY_NONE   equ 0
KEY_CHAR   equ 1
KEY_ENTER  equ 2
KEY_DELETE equ 3
KEY_LEFT   equ 4
KEY_RIGHT  equ 5
KEY_UP     equ 6
KEY_DOWN   equ 7
KEY_SAVE   equ 8
KEY_QUIT   equ 9
KEY_UNDO   equ 10
KEY_REDO   equ 11

KM_WAIT_CHAR equ 0xBB09   ; bloquant : attend une touche, A=code ASCII/etendu

CH_ENTER equ 13
CH_DEL   equ 127
; codes etendus firmware pour les fleches (table de traduction ASCII
; standard) -- voir note ci-dessus, a confirmer.
CH_LEFT  equ 240
CH_RIGHT equ 241
CH_DOWN  equ 242
CH_UP    equ 243

; keyb_wait_key -- lecture BLOQUANTE d'une touche (le firmware gere
; deja l'anti-rebond/la repetition -- rien a faire ici). Sortie :
; A=type (KEY_*), C=caractere si type=KEY_CHAR. Detruit AF, C.
keyb_wait_key:
    call KM_WAIT_CHAR
    ld c, a

    cp CH_ENTER
    jr z, .is_enter
    cp CH_DEL
    jr z, .is_delete
    cp CH_LEFT
    jr z, .is_left
    cp CH_RIGHT
    jr z, .is_right
    cp CH_UP
    jr z, .is_up
    cp CH_DOWN
    jr z, .is_down

    cp 1                     ; CTRL+A..CTRL+Z -> codes 1-26 (firmware)
    jr c, .plain              ; A=0 : rien de tel (ne devrait pas arriver)
    cp 27
    jr nc, .plain
    ; A = 1..26 -> lettre = 'A'+(A-1)
    add a, 'A'-1
    cp 'S'
    jr z, .is_save
    cp 'Q'
    jr z, .is_quit
    cp 'Z'
    jr z, .is_undo
    cp 'Y'
    jr z, .is_redo
    ; CTRL+autre lettre : pas de commande associee -> ignorer (KEY_NONE)
    xor a
    ret

.plain:
    ld a, KEY_CHAR
    ret
.is_enter:
    ld a, KEY_ENTER
    ret
.is_delete:
    ld a, KEY_DELETE
    ret
.is_left:
    ld a, KEY_LEFT
    ret
.is_right:
    ld a, KEY_RIGHT
    ret
.is_up:
    ld a, KEY_UP
    ret
.is_down:
    ld a, KEY_DOWN
    ret
.is_save:
    ld a, KEY_SAVE
    ret
.is_quit:
    ld a, KEY_QUIT
    ret
.is_undo:
    ld a, KEY_UNDO
    ret
.is_redo:
    ld a, KEY_REDO
    ret
