#!/usr/bin/env python3
"""Verifie spectrum/tape.asm par un aller-retour complet :
1) test_tape_save.sna sauve "Hello!" sur une cassette de sortie
   (capturee par zesarux --outtape) ;
2) on verifie la structure .tap produite (en-tete CODE "WRITHDECK ",
   checksums) directement en Python (format .tap bien documente) ;
3) test_tape_load.sna recharge CETTE MEME cassette et on verifie que
   les octets/la longueur recuperes correspondent exactement.
"""
import os
import sys
from zrcp_harness import load_symbols, run_checks

TAP_PATH = "captured_roundtrip.tap"


def check_tap_structure():
    with open(TAP_PATH, "rb") as f:
        data = f.read()

    ok = True

    def block(offset):
        length = data[offset] | (data[offset + 1] << 8)
        payload = data[offset + 2: offset + 2 + length]
        return length, payload, offset + 2 + length

    len1, block1, next_off = block(0)
    flag1, header, checksum1 = block1[0], block1[1:-1], block1[-1]
    expect_checksum1 = flag1
    for b in header:
        expect_checksum1 ^= b
    if flag1 == 0 and header[0] == 3 and header[1:11] == b"WRITHDECK " and checksum1 == expect_checksum1:
        print("ok: .tap bloc 1 (en-tete CODE 'WRITHDECK ') structure + checksum valides")
    else:
        print(f"ECHEC: .tap bloc 1 -- flag={flag1} header={header!r} checksum={checksum1:#x} attendu {expect_checksum1:#x}")
        ok = False

    declared_len = header[11] | (header[12] << 8)
    if declared_len == 6:
        print("ok: .tap en-tete: longueur declaree == 6")
    else:
        print(f"ECHEC: .tap en-tete longueur declaree -- attendu 6, obtenu {declared_len}")
        ok = False

    len2, block2, _ = block(next_off)
    flag2, payload, checksum2 = block2[0], block2[1:-1], block2[-1]
    expect_checksum2 = flag2
    for b in payload:
        expect_checksum2 ^= b
    if flag2 == 0xFF and payload == b"Hello!" and checksum2 == expect_checksum2:
        print("ok: .tap bloc 2 (donnees 'Hello!') structure + checksum valides")
    else:
        print(f"ECHEC: .tap bloc 2 -- flag={flag2:#x} payload={payload!r} checksum={checksum2:#x} attendu {expect_checksum2:#x}")
        ok = False

    return ok


def main():
    if os.path.exists(TAP_PATH):
        os.remove(TAP_PATH)

    # 1) sauvegarde -> capture le .tap produit
    with_output = run_checks(
        "test_tape_save.sna", [], port=10133, run_delay=2.0, tape_out=TAP_PATH,
    )
    if not os.path.exists(TAP_PATH):
        print("ECHEC: tape_save n'a produit aucun fichier .tap")
        sys.exit(1)

    ok = check_tap_structure()

    # 2) rechargement de cette meme cassette
    load_symbols_dict = load_symbols("test_tape_load.sym")
    checks = [
        ("result_ok", bytes([1]), "tape_load: succes (A==1)"),
        ("result_len", (6).to_bytes(2, "little"), "tape_load: longueur chargee == 6"),
        ("dest_buf", b"Hello!", "tape_load: contenu recharge == 'Hello!'"),
    ]
    ok = run_checks(
        "test_tape_load.sna", checks, symbols=load_symbols_dict, port=10134,
        run_delay=3.0, tape_in=TAP_PATH,
    ) and ok

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
