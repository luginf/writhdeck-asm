#!/usr/bin/env python3
"""Verifie le .tap livrable final (spectrum/writhdeck.tap) de 2 facons
independantes :
1. structure/checksum des 2 blocs (autoloader BASIC + CODE), lus
   directement en Python, sans emulateur ;
2. chargement REEL des 2 blocs via tape_load (donc via les vraies
   routines ROM LD-BYTES), execute sous zesarux -- voir
   test_writhdeck_tap.asm.
Note : ceci ne teste PAS le flux clavier interactif "LOAD ""### au
prompt BASIC (voir README/rapport de session -- simulation de frappe
peu fiable en zesarux headless dans cet environnement, alors que le
fichier lui-meme et le chargement bas niveau sont ici verifies fiables)."""
import struct
import sys

sys.path.insert(0, ".")
from zrcp_harness import load_symbols, run_checks
from gen_loader import CLEAR, LOAD, CODE, RANDOMIZE, USR, CLEAR_ADDR, encode_number

TAP = "../spectrum/writhdeck.tap"
SYM = "test_writhdeck_tap.sym"
SNA = "test_writhdeck_tap.sna"


def check_tap_structure():
    with open(TAP, "rb") as f:
        data = f.read()
    blocks = []
    i = 0
    while i < len(data):
        blocklen = struct.unpack_from("<H", data, i)[0]
        i += 2
        blocks.append(data[i:i + blocklen])
        i += blocklen

    ok = True
    if len(blocks) != 4:
        print(f"ECHEC: nombre de blocs -- attendu 4 (en-tete+donnees x2), obtenu {len(blocks)}")
        return False, None
    print("ok: .tap contient exactement 4 blocs (en-tete+donnees x2)")

    for block in blocks:
        body, checksum = block[:-1], block[-1]
        computed = 0
        for b in body:
            computed ^= b
        if computed != checksum:
            print(f"ECHEC: checksum invalide sur un bloc (flag={block[0]:#x})")
            ok = False
    if ok:
        print("ok: les 4 checksums (XOR) sont valides")

    basic_header, basic_data, code_header, code_data = blocks
    if basic_header[1] != 0:
        print(f"ECHEC: 1er bloc -- type attendu 0 (Program), obtenu {basic_header[1]}")
        ok = False
    autostart_line = struct.unpack_from("<H", basic_header, 14)[0]
    if autostart_line != 10:
        print(f"ECHEC: ligne d'autostart -- attendue 10, obtenue {autostart_line}")
        ok = False
    else:
        print("ok: bloc BASIC autostart sur la ligne 10")

    program = basic_data[1:-1]
    # zone programme = numero de ligne (2 octets grand-boutiste) +
    # longueur de la ligne (2 octets petit-boutiste) + tokens -- PAS
    # juste les tokens seuls (bug reel corrige : ce prefixe de 4 octets
    # manquait, le ROM relisait alors les 4 premiers octets des tokens
    # comme un faux numero/une fausse longueur de ligne)
    line_num = struct.unpack_from(">H", program, 0)[0]
    line_len = struct.unpack_from("<H", program, 2)[0]
    statement = program[4:]
    if line_num != 10:
        print(f"ECHEC: numero de ligne dans la zone programme -- attendu 10, obtenu {line_num}")
        ok = False
    if line_len != len(statement):
        print(f"ECHEC: longueur de ligne declaree ({line_len}) != longueur reelle ({len(statement)})")
        ok = False
    expected_prefix = bytes([CLEAR]) + encode_number(CLEAR_ADDR) + b":" \
        + bytes([LOAD]) + b'""' + bytes([CODE]) + b":" \
        + bytes([RANDOMIZE]) + bytes([USR])
    if not statement.startswith(expected_prefix):
        print(f"ECHEC: contenu autoloader inattendu : {statement.hex()}")
        ok = False
    else:
        print("ok: zone programme = ligne 10 correctement prefixee (numero+longueur), "
              "nombres avec cache flottant = CLEAR 32767: LOAD \"\"CODE: RANDOMIZE USR <adresse>")

    if code_header[1] != 3:
        print(f"ECHEC: 3e bloc -- type attendu 3 (CODE), obtenu {code_header[1]}")
        ok = False
    else:
        print("ok: 2e bloc de la bande est bien de type CODE")

    return ok, statement


def main():
    ok_structure, _loader_line = check_tap_structure()

    symbols = load_symbols(SYM)
    ok_load = run_checks(SNA, [
        ("loader_ok", bytes([1]), "tape_load (bloc 1, autoloader BASIC) : succes"),
        ("code_ok", bytes([1]), "tape_load (bloc 2, CODE) : succes"),
    ], port=10175, run_delay=2.5, symbols=symbols, tape_in=TAP)

    sys.exit(0 if (ok_structure and ok_load) else 1)


if __name__ == "__main__":
    main()
