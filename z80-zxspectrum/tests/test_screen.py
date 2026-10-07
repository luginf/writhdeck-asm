#!/usr/bin/env python3
"""Verifie spectrum/screen.asm : la reference "attendue" pour un
glyphe est lue directement dans la police ROM (adresse fixe $3D00),
pas devinee a la main -- on verifie que le rendu ecran reproduit
EXACTEMENT ces octets, a la bonne adresse entrelacee."""
import sys
from zrcp_harness import load_symbols, read_memory, read_memory_strided, zesarux_session

SYM = "test_screen.sym"
SNA = "test_screen.sna"
FONT_BASE = 0x3D00
ATTR_BASE = 0x5800


def rom_glyph(sock, ch):
    return read_memory(sock, FONT_BASE + (ord(ch) - 32) * 8, 8)


def main():
    symbols = load_symbols(SYM)
    ok = True

    with zesarux_session(SNA, port=10127) as sock:
        # adresses calculees par le programme lui-meme (scr__pixel_addr)
        addr_a = int.from_bytes(read_memory(sock, symbols["snap_addr_a"], 2), "little")
        addr_z = int.from_bytes(read_memory(sock, symbols["snap_addr_z"], 2), "little")

        expect_a = 0x4000
        expect_z = 0x4805  # ligne 8 = debut du 2e tiers d'ecran, colonne 5
        if addr_a == expect_a:
            print("ok: scr__pixel_addr(0,0) == 0x4000")
        else:
            print(f"ECHEC: scr__pixel_addr(0,0) -- attendu {expect_a:#06x}, obtenu {addr_a:#06x}")
            ok = False
        if addr_z == expect_z:
            print("ok: scr__pixel_addr(8,5) == 0x4805 (franchissement de tiers)")
        else:
            print(f"ECHEC: scr__pixel_addr(8,5) -- attendu {expect_z:#06x}, obtenu {addr_z:#06x}")
            ok = False

        # glyphe 'A' dessine a (0,0) : 8 lignes de balayage espacees de 256o
        drawn_a = read_memory_strided(sock, addr_a, 8, 256)
        expected_a = rom_glyph(sock, 'A')
        if drawn_a == expected_a and expected_a != b"\x00" * 8:
            print("ok: scr_draw_char('A' @ 0,0) == police ROM")
        else:
            print(f"ECHEC: scr_draw_char('A') -- ROM={expected_a.hex()} ecran={drawn_a.hex()}")
            ok = False

        # glyphe 'Z' dessine a (8,5)
        drawn_z = read_memory_strided(sock, addr_z, 8, 256)
        expected_z = rom_glyph(sock, 'Z')
        if drawn_z == expected_z and expected_z != b"\x00" * 8:
            print("ok: scr_draw_char('Z' @ 8,5) == police ROM (franchissement de tiers)")
        else:
            print(f"ECHEC: scr_draw_char('Z') -- ROM={expected_z.hex()} ecran={drawn_z.hex()}")
            ok = False

        # scr_put_line("Hi!", ligne 2) : 'H' en colonne 0, espace en colonne 5
        addr_h = 0x4040   # ligne 2, colonne 0 (calcule a la main, meme formule)
        addr_sp = 0x4045  # ligne 2, colonne 5 (au-dela de "Hi!", doit etre efface)
        drawn_h = read_memory_strided(sock, addr_h, 8, 256)
        expected_h = rom_glyph(sock, 'H')
        if drawn_h == expected_h:
            print("ok: scr_put_line: 'H' correctement dessine en colonne 0")
        else:
            print(f"ECHEC: scr_put_line 'H' -- ROM={expected_h.hex()} ecran={drawn_h.hex()}")
            ok = False

        drawn_sp = read_memory_strided(sock, addr_sp, 8, 256)
        expected_sp = rom_glyph(sock, ' ')
        if drawn_sp == expected_sp:
            print("ok: scr_put_line: colonne 5 effacee (espace) au-dela de 'Hi!'")
        else:
            print(f"ECHEC: scr_put_line espace -- ROM={expected_sp.hex()} ecran={drawn_sp.hex()}")
            ok = False

        # scr_set_attr : 5 octets inverses puis retour a la normale
        attrs = read_memory(sock, ATTR_BASE, 6)
        if attrs == bytes([0x07] * 5 + [0x38]):
            print("ok: scr_set_attr: 5 attributs inverses puis normal (non ecrase)")
        else:
            print(f"ECHEC: scr_set_attr -- obtenu {attrs.hex()}")
            ok = False

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
