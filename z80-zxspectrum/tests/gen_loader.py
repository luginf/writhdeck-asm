#!/usr/bin/env python3
"""Construit le bloc BASIC autoloader (format .tap standard : bloc
en-tete + bloc donnees, chacun avec son octet drapeau et son checksum
XOR) et le prepend a spectrum/writhdeck.tap (deja produit par
sjasmplus, bloc CODE seul -- voir Makefile). Le bloc BASIC est
construit ici en Python plutot que par une 2e directive SAVETAP dans
main.asm a cause d'un bug reel de sjasmplus 1.20.3 : plusieurs
directives SAVETAP dans le meme fichier dupliquent chacune leurs blocs
(verifie isolement : 1 SAVETAP => 2 blocs, 2 SAVETAP => 4 blocs).

La ligne BASIC generee (numero de ligne 10, autostart) :

    10 CLEAR 32767: LOAD ""CODE: RANDOMIZE USR <adresse de _start>

encodee directement avec la table de tokens standard du ROM 48K
(CLEAR=0xFD, LOAD=0xEF, CODE=0xAF, RANDOMIZE=0xF9, USR=0xC0 -- le
sous-ensemble 0xE6-0xFF, un mot-cle par lettre A-Z en mode curseur K,
a ete confirme experimentalement en faisant taper 'C'/'L'/'R' par une
vraie ROM sous zesarux, qui a bien produit CONTINUE/LET/RUN).

Chaque nombre litteral (32767, l'adresse USR) DOIT etre suivi de son
"cache" flottant ROM -- 0x0E puis 5 octets encodant sa valeur -- teste
et confirme NECESSAIRE (pas juste une optimisation cosmetique comme
suppose au debut) : sans ce cache, le RUN-time echoue avec "Nonsense
in BASIC" des le premier nombre (bug reel rencontre en testant : cette
hypothese erronee expliquait tous les symptomes de "LOAD ""CODE qui
boucle" observes auparavant, aussi bien sous zesarux que sous fuse).
Format du cache pour un entier positif 0-65535 (forme "petit entier") :
00, signe(00), octet bas, octet haut, 00.

Usage : gen_loader.py <main.sym> <writhdeck.tap>
"""
import re
import struct
import sys

CLEAR = 0xFD
LOAD = 0xEF
CODE = 0xAF
RANDOMIZE = 0xF9
USR = 0xC0
NUMBER_MARKER = 0x0E
CLEAR_ADDR = 32767  # un de moins que ORG $8000 (voir main.asm program_start)
AUTOSTART_LINE = 10


def encode_number(n):
    if not (0 <= n <= 65535):
        raise ValueError(f"encode_number: hors plage petit-entier 0-65535 : {n}")
    cache = bytes([0x00, 0x00, n & 0xFF, (n >> 8) & 0xFF, 0x00])
    return str(n).encode() + bytes([NUMBER_MARKER]) + cache


def build_basic_statement(usr_addr):
    if not (32768 <= usr_addr <= 65535):
        raise ValueError(f"adresse USR hors plage attendue (5 chiffres) : {usr_addr}")
    return bytes([CLEAR]) + encode_number(CLEAR_ADDR) + b":" \
        + bytes([LOAD]) + b'""' + bytes([CODE]) + b":" \
        + bytes([RANDOMIZE]) + bytes([USR]) + encode_number(usr_addr) + b"\x0d"


def build_program_area(usr_addr):
    # Le programme BASIC stocke en RAM (et donc sur bande) n'est PAS
    # juste le texte tokenise : chaque ligne y est prefixee de son
    # numero (2 octets GRAND-boutiste) et de la longueur de ce qui suit
    # (2 octets PETIT-boutiste, tokens+ENTER, sans compter ce prefixe
    # lui-meme) -- omettre ce prefixe de 4 octets (bug reel rencontre
    # en testant : le ROM relit alors les 4 premiers octets des tokens
    # comme un faux numero de ligne/une fausse longueur, corrompant
    # toute la recherche de ligne -- symptome : LOAD ""CODE en boucle,
    # "Program:" reaffiche, RUN qui ne trouve jamais la ligne 10).
    statement = build_basic_statement(usr_addr)
    return struct.pack(">H", AUTOSTART_LINE) + struct.pack("<H", len(statement)) + statement


def tap_block(flag, payload):
    body = bytes([flag]) + payload
    checksum = 0
    for b in body:
        checksum ^= b
    block = body + bytes([checksum])
    return struct.pack("<H", len(block)) + block


def build_basic_tap_prelude(usr_addr):
    program = build_program_area(usr_addr)
    # en-tete standard 17 octets : type(0=Program) + nom(10) + longueur
    # totale de la zone programme(2) + ligne d'autostart(2) + offset
    # variables(2, = fin de programme ici puisqu'on ne stocke pas de
    # variables)
    name = b"writhdeck ".ljust(10)[:10]
    header = bytes([0]) + name + struct.pack("<H", len(program)) \
        + struct.pack("<H", AUTOSTART_LINE) + struct.pack("<H", len(program))
    return tap_block(0x00, header) + tap_block(0xFF, program)


def find_start_addr(sym_path):
    with open(sym_path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("_start:"):
                m = re.search(r"0x([0-9A-Fa-f]+)", line)
                if m:
                    return int(m.group(1), 16)
    raise SystemExit(f"ERREUR: symbole _start introuvable dans {sym_path}")


def main():
    if len(sys.argv) != 3:
        print("usage: gen_loader.py <main.sym> <writhdeck.tap>", file=sys.stderr)
        sys.exit(2)
    sym_path, tap_path = sys.argv[1], sys.argv[2]

    start_addr = find_start_addr(sym_path)
    prelude = build_basic_tap_prelude(start_addr)

    with open(tap_path, "rb") as f:
        existing = f.read()

    with open(tap_path, "wb") as f:
        f.write(prelude + existing)

    print(f"-> bloc BASIC autoloader ({len(prelude)} octets, RANDOMIZE USR {start_addr}) "
          f"prepende a {tap_path}")


if __name__ == "__main__":
    main()
