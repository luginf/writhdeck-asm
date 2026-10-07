#!/usr/bin/env python3
"""Verifie l'integration complete du programme final ZX Spectrum
(spectrum/main.asm, execute depuis spectrum/writhdeck.sna -- un .sna
PC=_start genere uniquement pour ce test automatise, voir main.asm) :
frappes clavier REELLES simulees via zesarux (ZRCP send-keys-ascii),
verifiees a la fois dans le buffer de texte ET sur l'ecran (compare a
la police ROM, meme technique que test_screen.py)."""
import socket
import sys
import time

sys.path.insert(0, ".")
from zrcp_harness import _recv_until_prompt, load_symbols, read_memory, read_memory_strided, zesarux_session

SYM = "../spectrum/main.sym"
SNA = "../spectrum/writhdeck.sna"
FONT_BASE = 0x3D00


def rom_glyph(sock, ch):
    return read_memory(sock, FONT_BASE + (ord(ch) - 32) * 8, 8)


def send_keys(sock, chars, delay_ms=150):
    # une commande ZRCP separee par caractere : envoyer plusieurs
    # caracteres dans UNE SEULE commande send-keys-ascii ne laisse pas
    # assez de temps reel entre eux pour que notre boucle principale
    # (qui redessine l'ecran entre deux lectures clavier) les distingue
    # -- piege reel rencontre en testant, voir le rapport de session.
    for c in chars:
        sock.sendall(f"send-keys-ascii {delay_ms} {ord(c)}\n".encode())
        _recv_until_prompt(sock)
        time.sleep(delay_ms / 1000.0 + 0.3)


def main():
    symbols = load_symbols(SYM)
    ok = True

    with zesarux_session(SNA, port=10135, run_delay=1.5) as sock:
        # taper "hi" (minuscules -- correspond a notre defaut "sans
        # majuscule = minuscule", voir keyboard.asm)
        send_keys(sock, "hi")
        time.sleep(1.0)

        textbuf = symbols["TEXTBUF"]
        content = read_memory(sock, textbuf, 2)
        if content == b"hi":
            print("ok: frappe clavier reelle 'h','i' -> TEXTBUF == 'hi'")
        else:
            print(f"ECHEC: TEXTBUF apres frappe -- obtenu {content!r}")
            ok = False

        curcol = int.from_bytes(read_memory(sock, symbols["CURCOL"], 2), "little")
        if curcol == 2:
            print("ok: curseur avance a la colonne 2 apres 2 caracteres")
        else:
            print(f"ECHEC: CURCOL -- attendu 2, obtenu {curcol}")
            ok = False

        # verifier le rendu ecran : 'h' en (0,0), 'i' en (0,1)
        drawn_h = read_memory_strided(sock, 0x4000, 8, 256)
        expected_h = rom_glyph(sock, 'h')
        if drawn_h == expected_h:
            print("ok: rendu ecran: 'h' affiche correctement en (0,0)")
        else:
            print(f"ECHEC: rendu 'h' -- ROM={expected_h.hex()} ecran={drawn_h.hex()}")
            ok = False

        drawn_i = read_memory_strided(sock, 0x4001, 8, 256)  # colonne 1 = +1 octet (ligne0 -> pas de decalage de tiers)
        expected_i = rom_glyph(sock, 'i')
        if drawn_i == expected_i:
            print("ok: rendu ecran: 'i' affiche correctement en (0,1)")
        else:
            print(f"ECHEC: rendu 'i' -- ROM={expected_i.hex()} ecran={drawn_i.hex()}")
            ok = False

        # touche Entree (ascii 13) -> nouvelle ligne
        send_keys(sock, "\r")
        time.sleep(0.5)
        linecount = read_memory(sock, symbols["LINECOUNT"], 1)[0]
        if linecount == 2:
            print("ok: touche Entree -> LINECOUNT passe a 2")
        else:
            print(f"ECHEC: LINECOUNT apres Entree -- attendu 2, obtenu {linecount}")
            ok = False

        curline = read_memory(sock, symbols["CURLINE"], 1)[0]
        curcol2 = int.from_bytes(read_memory(sock, symbols["CURCOL"], 2), "little")
        if curline == 1 and curcol2 == 0:
            print("ok: touche Entree -> curseur en debut de la nouvelle ligne")
        else:
            print(f"ECHEC: curseur apres Entree -- ligne={curline} col={curcol2}")
            ok = False

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
