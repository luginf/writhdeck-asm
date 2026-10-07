#!/usr/bin/env python3
"""Test d'integration final : reproduit exactement ce qu'un utilisateur
fait a la main -- demarrage a froid en BASIC 48K (pas de --snap), bande
inseree via --tape, une seule frappe LOAD"" (touche J = mot-cle LOAD en
mode curseur K, PAS les lettres L,O,A,D separement -- voir README) puis
ENTER. Verifie que le bloc BASIC autoloader charge, s'auto-execute
(CLEAR/LOAD CODE/RANDOMIZE USR) et saute dans l'editeur tout seul.

--noautoload : desactive l'auto-chargement automatique de zesarux (qui
demarrerait sa propre frappe "LOAD"" " des l'insertion de la bande) --
sinon elle entre en collision avec la frappe simulee ci-dessous (meme
piege reel qu'un utilisateur rencontrerait en lancant `fuse fichier.tap`
puis en tapant lui-meme LOAD"" par-dessus l'auto-chargement de fuse --
voir le README, section "Running it")."""
import socket
import subprocess
import sys
import time

sys.path.insert(0, ".")
from zrcp_harness import _recv_until_prompt, load_symbols, read_memory

PORT = 10149
TAP = "../spectrum/writhdeck.tap"
SYM = "../spectrum/main.sym"


def send_ascii(sock, code, delay=80):
    sock.sendall(f"send-keys-ascii {delay} {code}\n".encode())
    _recv_until_prompt(sock)
    time.sleep(delay / 1000.0 + 0.1)


def main():
    symbols = load_symbols(SYM)
    ok = True

    proc = subprocess.Popen(
        ["zesarux", "--noconfigfile", "--machine", "48k",
         "--vo", "null", "--ao", "null", "--noautoload",
         "--enable-remoteprotocol", "--remoteprotocol-port", str(PORT),
         "--tape", TAP],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(1.5)
        sock = socket.create_connection(("127.0.0.1", PORT), timeout=5)
        _recv_until_prompt(sock)
        time.sleep(10.0)  # laisser le boot 48K se stabiliser avant de taper

        for ch in ['J', '"', '"']:
            send_ascii(sock, ord(ch))
        send_ascii(sock, 13)

        time.sleep(20.0)  # chargement des 2 blocs (traps -> quasi instantane) + editor_init

        textend = read_memory(sock, symbols["TEXTEND"], 2)
        textbuf = symbols["TEXTBUF"]
        expected = bytes([textbuf & 0xFF, (textbuf >> 8) & 0xFF])
        if textend == expected:
            print("ok: LOAD \"\" seul (touche J + 2 quotes + ENTER) charge l'autoloader, "
                  "qui charge le bloc CODE et saute dans editor_init (TEXTEND==TEXTBUF)")
        else:
            print(f"ECHEC: TEXTEND={textend.hex()} attendu {expected.hex()} "
                  "-- l'autoloader n'a pas correctement demarre l'editeur")
            ok = False

        sock.sendall(b"exit-emulator\n")
        time.sleep(0.3)
        sock.close()
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
