; test_keyboard.asm -- exercice la logique de DECODAGE de
; spectrum/keyboard.asm (rangees 0,1,3,4 -- les plus a risque : bascules
; CAPS/SYM, ecrasement des chiffres par les fleches/Suppr sous CAPS).
; N'utilise PAS le port clavier reel (pas besoin de simuler des
; frappes physiques dans l'emulateur) : injecte directement
; kb_caps/kb_sym/kb_rowval en memoire et appelle les points d'entree
; "*_decode" (voir keyboard.asm), qui sautent l'appel au port et
; partent directement du decodage.
    DEVICE ZXSPECTRUM48
    ORG $8000

; Le produit reel (spectrum/main.asm) desactive les fleches CAPS+5/6/7/8
; par defaut (voir keyboard.asm) ; ce test force l'activation pour
; continuer a verifier que ce decodage reste correct.
    DEFINE ZX_ARROWS_VIA_CAPS 1
    include "../spectrum/keyboard.asm"

start:
    ; --- rangee 3 (chiffres 1-5), sans CAPS/SYM : bit0='1' presse ---
    xor a
    ld (kb_caps), a
    xor a
    ld (kb_sym), a
    ld a, 0xFE
    ld (kb_rowval), a
    call keyb__row3_decode
    ld (snap1_type), a
    ld a, c
    ld (snap1_char), a

    ; --- rangee 3, SYM enfonce : bit0='1' presse -> '!' ---
    ld a, 1
    ld (kb_sym), a
    ld a, 0xFE
    ld (kb_rowval), a
    call keyb__row3_decode
    ld (snap2_type), a
    ld a, c
    ld (snap2_char), a
    xor a
    ld (kb_sym), a

    ; --- rangee 3, CAPS enfonce : bit4='5' presse -> GAUCHE ---
    ld a, 1
    ld (kb_caps), a
    ld a, 0xEF
    ld (kb_rowval), a
    call keyb__row3_decode
    ld (snap3_type), a

    ; --- rangee 4, CAPS enfonce : bit0='0' presse -> SUPPR ---
    ld a, 0xFE
    ld (kb_rowval), a
    call keyb__row4_decode
    ld (snap4_type), a

    ; --- rangee 4, CAPS enfonce : bit3='7' presse -> HAUT ---
    ld a, 0xF7
    ld (kb_rowval), a
    call keyb__row4_decode
    ld (snap5_type), a

    ; --- rangee 4, CAPS enfonce : bit4='6' presse -> BAS ---
    ld a, 0xEF
    ld (kb_rowval), a
    call keyb__row4_decode
    ld (snap6_type), a

    ; --- rangee 4, CAPS enfonce : bit2='8' presse -> DROITE ---
    ld a, 0xFB
    ld (kb_rowval), a
    call keyb__row4_decode
    ld (snap11_type), a
    xor a
    ld (kb_caps), a

    ; --- rangee 0, SYM enfonce : bit1='Z' presse -> ANNULER ---
    ld a, 1
    ld (kb_sym), a
    ld a, 0xFD
    ld (kb_rowval), a
    call keyb__row0_decode
    ld (snap7_type), a
    xor a
    ld (kb_sym), a

    ; --- rangee 1, SYM enfonce : bit1='S' presse -> SAUVER ---
    ld a, 1
    ld (kb_sym), a
    ld a, 0xFD
    ld (kb_rowval), a
    call keyb__row1_decode
    ld (snap8_type), a
    xor a
    ld (kb_sym), a

    ; --- rangee 1, sans CAPS : bit0='A' presse -> 'a' minuscule ---
    ld a, 0xFE
    ld (kb_rowval), a
    call keyb__row1_decode
    ld (snap9_type), a
    ld a, c
    ld (snap9_char), a

    ; --- rangee 1, CAPS enfonce : bit0='A' presse -> 'A' majuscule ---
    ld a, 1
    ld (kb_caps), a
    ld a, 0xFE
    ld (kb_rowval), a
    call keyb__row1_decode
    ld (snap10_type), a
    ld a, c
    ld (snap10_char), a

loop:
    jr loop

snap1_type: defb 0
snap1_char: defb 0
snap2_type: defb 0
snap2_char: defb 0
snap3_type: defb 0
snap4_type: defb 0
snap5_type: defb 0
snap6_type: defb 0
snap7_type: defb 0
snap8_type: defb 0
snap9_type: defb 0
snap9_char: defb 0
snap10_type: defb 0
snap10_char: defb 0
snap11_type: defb 0

    SAVESNA "test_keyboard.sna", start
