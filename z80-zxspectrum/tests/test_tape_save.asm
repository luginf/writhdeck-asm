; test_tape_save.asm -- sauvegarde un petit bloc connu sur cassette
; (capturee via zesarux --outtape, voir test_tape.py) pour verifier la
; structure du fichier .tap produit par tape_save.
    DEVICE ZXSPECTRUM48
    ORG $8000

    include "../core/buffer.asm"
    include "../spectrum/tape.asm"

start:
    ld hl, payload
    ld de, payload_len
    call tape_save

loop:
    jr loop

payload: defm "Hello!"
payload_len = $ - payload

    SAVESNA "test_tape_save.sna", start
