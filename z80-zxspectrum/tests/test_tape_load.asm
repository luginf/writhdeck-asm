; test_tape_load.asm -- charge un bloc CODE depuis une cassette fournie
; en entree (voir test_tape.py, qui reutilise le .tap produit par
; test_tape_save) et verifie que les octets/longueur recuperes
; correspondent exactement a ce qui avait ete sauve.
    DEVICE ZXSPECTRUM48
    ORG $8000

    include "../core/buffer.asm"
    include "../spectrum/tape.asm"

start:
    ld hl, dest_buf
    ld de, 32                  ; longueur max acceptee (marge)
    call tape_load
    ld (result_ok), a
    ld (result_len), bc

loop:
    jr loop

dest_buf: defs 32
result_ok: defb 0
result_len: defw 0

    SAVESNA "test_tape_load.sna", start
