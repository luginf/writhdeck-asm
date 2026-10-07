; test_buffer.asm -- exercice core/buffer.asm : insertion, split,
; backspace (fusion), delete en fin de ligne (fusion), word/char count.
; Verifie ensuite par lecture memoire via zesarux (voir test_buffer.py).
    DEVICE ZXSPECTRUM48
    ORG $8000

    include "../core/buffer.asm"

start:
    call buffer_init

    ; --- inserer "hi" sur la ligne 0 ---
    ld a, 0
    ld hl, 0
    ld c, 'h'
    call buffer_insert_char

    ld a, 0
    ld hl, 1
    ld c, 'i'
    call buffer_insert_char

    ; snapshot 1 : "hi", 1 ligne (copie du contenu -- le harnais ne lit
    ; la memoire qu'une seule fois, a la toute fin de l'execution, donc
    ; chaque etape doit copier ce qu'elle veut faire verifier plus tard)
    ld a, (LINECOUNT)
    ld (snap1_linecount), a
    ld hl, (TEXTEND)
    ld (snap1_textend), hl
    ld hl, TEXTBUF
    ld de, snap1_text
    ld bc, 2
    ldir

    ; --- split a (0,1) -> "h" / "i" ---
    ld a, 0
    ld hl, 1
    call buffer_split_line

    ld a, (LINECOUNT)
    ld (snap2_linecount), a
    ld hl, (TEXTEND)
    ld (snap2_textend), hl
    ld hl, (LINETAB+2)
    ld (snap2_line1addr), hl
    ld hl, TEXTBUF
    ld de, snap2_text
    ld bc, 3
    ldir

    ; --- backspace a (1,0) -> refusionne en "hi" ---
    ld a, 1
    ld hl, 0
    call buffer_backspace
    ld (snap3_cy), a
    ld (snap3_cx), hl
    ld a, (LINECOUNT)
    ld (snap3_linecount), a
    ld hl, (TEXTEND)
    ld (snap3_textend), hl
    ld hl, TEXTBUF
    ld de, snap3_text
    ld bc, 2
    ldir

    ; --- construire "ba" via 2 lignes puis delete_char en fin de ligne 0 ---
    call buffer_init
    ld a, 0
    ld hl, 0
    ld c, 'a'
    call buffer_insert_char
    ld a, 0
    ld hl, 0
    call buffer_split_line          ; ligne0="" ligne1="a"
    ld a, 0
    ld hl, 0
    ld c, 'b'
    call buffer_insert_char          ; ligne0="b"

    ld a, 0
    ld hl, 1                            ; col=1 = fin de "b"
    call buffer_delete_char
    ld a, (LINECOUNT)
    ld (snap4_linecount), a
    ld hl, TEXTBUF
    ld de, snap4_text
    ld bc, 2
    ldir

    ; --- word_count / char_count sur "un\ndeux mots" ---
    call buffer_init
    ld a, 0
    ld hl, 0
    ld c, 'u'
    call buffer_insert_char
    ld a, 0
    ld hl, 1
    ld c, 'n'
    call buffer_insert_char
    ld a, 0
    ld hl, 2
    call buffer_split_line
    ; ligne1 = "deux mots" (insertion explicite, plus sur qu'une boucle
    ; a jongler avec les registres pour ce simple test)
    ld a, 1 : ld hl, 0 : ld c, 'd' : call buffer_insert_char
    ld a, 1 : ld hl, 1 : ld c, 'e' : call buffer_insert_char
    ld a, 1 : ld hl, 2 : ld c, 'u' : call buffer_insert_char
    ld a, 1 : ld hl, 3 : ld c, 'x' : call buffer_insert_char
    ld a, 1 : ld hl, 4 : ld c, ' ' : call buffer_insert_char
    ld a, 1 : ld hl, 5 : ld c, 'm' : call buffer_insert_char
    ld a, 1 : ld hl, 6 : ld c, 'o' : call buffer_insert_char
    ld a, 1 : ld hl, 7 : ld c, 't' : call buffer_insert_char
    ld a, 1 : ld hl, 8 : ld c, 's' : call buffer_insert_char

    call buffer_word_count
    ld (snap5_words), hl
    call buffer_char_count
    ld (snap5_chars), hl

loop:
    jr loop

snap1_linecount: defb 0
snap1_textend:   defw 0
snap1_text:      defs 2
snap2_linecount: defb 0
snap2_textend:   defw 0
snap2_line1addr: defw 0
snap2_text:      defs 3
snap3_cy:        defb 0
snap3_cx:        defw 0
snap3_linecount: defb 0
snap3_textend:   defw 0
snap3_text:      defs 2
snap4_linecount: defb 0
snap4_text:      defs 2
snap5_words:     defw 0
snap5_chars:     defw 0

    SAVESNA "test_buffer.sna", start
