; smoke.asm -- verifie la chaine sjasmplus -> .sna -> execution sous
; zesarux headless, avant d'investir dans core/buffer.asm/editor.asm.
    DEVICE ZXSPECTRUM48

    ORG $8000
start:
    ld a, $AA
    ld ($9000), a
    ld a, $42
    ld ($9001), a
loop:
    jr loop

    SAVESNA "smoke.sna", start
