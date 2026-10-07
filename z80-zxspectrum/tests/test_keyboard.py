#!/usr/bin/env python3
"""Verifie le decodage de spectrum/keyboard.asm (rangees 0,1,3,4) en
injectant directement kb_caps/kb_sym/kb_rowval (voir test_keyboard.asm)
-- pas de simulation de frappe physique necessaire."""
import sys
from zrcp_harness import load_symbols, run_checks

SYM = "test_keyboard.sym"
SNA = "test_keyboard.sna"

KEY_CHAR = 1
KEY_DELETE = 3
KEY_LEFT = 4
KEY_RIGHT = 5
KEY_UP = 6
KEY_DOWN = 7
KEY_SAVE = 8
KEY_UNDO = 10


def main():
    symbols = load_symbols(SYM)

    checks = [
        ("snap1_type", bytes([KEY_CHAR]), "rangee3 '1' sans modif: KEY_CHAR"),
        ("snap1_char", b"1", "rangee3 '1' sans modif: caractere '1'"),

        ("snap2_type", bytes([KEY_CHAR]), "rangee3 SYM+'1': KEY_CHAR"),
        ("snap2_char", b"!", "rangee3 SYM+'1': caractere '!'"),

        ("snap3_type", bytes([KEY_LEFT]), "rangee3 CAPS+'5': GAUCHE"),
        ("snap4_type", bytes([KEY_DELETE]), "rangee4 CAPS+'0': SUPPR"),
        ("snap5_type", bytes([KEY_UP]), "rangee4 CAPS+'7': HAUT"),
        ("snap6_type", bytes([KEY_DOWN]), "rangee4 CAPS+'6': BAS"),
        ("snap11_type", bytes([KEY_RIGHT]), "rangee4 CAPS+'8': DROITE"),

        ("snap7_type", bytes([KEY_UNDO]), "rangee0 SYM+'Z': ANNULER"),
        ("snap8_type", bytes([KEY_SAVE]), "rangee1 SYM+'S': SAUVER"),

        ("snap9_type", bytes([KEY_CHAR]), "rangee1 'A' sans CAPS: KEY_CHAR"),
        ("snap9_char", b"a", "rangee1 'A' sans CAPS: minuscule 'a'"),
        ("snap10_type", bytes([KEY_CHAR]), "rangee1 CAPS+'A': KEY_CHAR"),
        ("snap10_char", b"A", "rangee1 CAPS+'A': majuscule 'A'"),
    ]

    ok = run_checks(SNA, checks, symbols=symbols, port=10131)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
