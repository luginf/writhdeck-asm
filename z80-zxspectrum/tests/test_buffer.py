#!/usr/bin/env python3
"""Verifie core/buffer.asm via le programme test_buffer.asm assemble
en .sna, execute sous zesarux (voir zrcp_harness.py)."""
import sys
from zrcp_harness import load_symbols, run_checks

SYM = "test_buffer.sym"
SNA = "test_buffer.sna"


def main():
    symbols = load_symbols(SYM)
    textbuf = symbols["TEXTBUF"]

    def addr(n):
        # TEXTEND est une adresse ABSOLUE (TEXTBUF + longueur utilisee)
        return (textbuf + n).to_bytes(2, "little")

    checks = [
        ("snap1_linecount", bytes([1]), "insert_char x2: LINECOUNT==1"),
        ("snap1_textend", addr(2), "insert_char x2: TEXTEND==TEXTBUF+2 (hi)"),
        ("snap1_text", b"hi", "insert_char x2: contenu = 'hi'"),

        ("snap2_linecount", bytes([2]), "split_line: LINECOUNT==2"),
        ("snap2_textend", addr(3), "split_line: TEXTEND==TEXTBUF+3 (h\\nLFi)"),
        ("snap2_text", bytes([ord('h'), 10, ord('i')]), "split_line: contenu = 'h'+LF+'i'"),

        ("snap3_cy", bytes([0]), "backspace apres split: curseur ligne==0"),
        ("snap3_cx", (1).to_bytes(2, "little"), "backspace apres split: curseur col==1"),
        ("snap3_linecount", bytes([1]), "backspace apres split: LINECOUNT==1 (refusionne)"),
        ("snap3_textend", addr(2), "backspace apres split: TEXTEND==TEXTBUF+2"),
        ("snap3_text", b"hi", "backspace apres split: contenu redevenu 'hi'"),

        ("snap4_linecount", bytes([1]), "delete_char en fin de ligne: fusionne (LINECOUNT==1)"),
        ("snap4_text", b"ba", "delete_char en fin de ligne: contenu = 'ba'"),

        ("snap5_words", (3).to_bytes(2, "little"), "word_count: 'un'+'deux mots' == 3 mots"),
        ("snap5_chars", (12).to_bytes(2, "little"), "char_count: 'un'(2)+LF(1)+'deux mots'(9) == 12"),
    ]

    ok = run_checks(SNA, checks, symbols=symbols, port=10124)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
