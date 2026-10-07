; test_writhdeck_tap.asm -- charge successivement les 2 blocs du .tap
; livrable (spectrum/writhdeck.tap : autoloader BASIC puis bloc CODE)
; via tape_load (donc via les VRAIES routines ROM LD-BYTES), et verifie
; leur contenu. Sert de test de non-regression fiable pour le .tap
; final -- contrairement a une simulation de frappe BASIC interactive
; (LOAD ""), qui s'est averee peu fiable sous zesarux headless dans cet
; environnement (voir le rapport de session : le fichier lui-meme est
; verifie correct par ce test, l'usage reel via un vrai clavier/materiel
; n'est pas affecte par cette limitation d'outillage de test).
    DEVICE ZXSPECTRUM48
    ORG $8000

    include "../core/buffer.asm"
    include "../spectrum/tape.asm"

; NOTE : maxlen doit couvrir la longueur REELLE declaree par chaque
; bloc, sinon LD-BYTES lirait un octet de donnees a la place du
; checksum attendu -> echec systematique meme si la bande est correcte
; (piege reel rencontre en ecrivant ce test).
start:
    ld hl, loader_buf
    ld de, loader_buf_size
    call tape_load
    ld (loader_ok), a
    ld (loader_len), bc

    ld hl, code_buf
    ld de, code_buf_size
    call tape_load
    ld (code_ok), a
    ld (code_len), bc

loop:
    jr loop

; doit couvrir la longueur maximale possible de la zone programme
; (numero de ligne + longueur + tokens, y compris les caches flottants
; des nombres -- voir gen_loader.py) avec de la marge.
loader_buf_size equ 64
loader_buf: defs loader_buf_size
loader_ok:  defb 0
loader_len: defw 0

code_buf_size equ 10000
code_buf: defs code_buf_size
code_ok:  defb 0
code_len: defw 0

    SAVESNA "test_writhdeck_tap.sna", start
