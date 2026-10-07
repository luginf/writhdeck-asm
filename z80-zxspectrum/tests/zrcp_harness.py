#!/usr/bin/env python3
"""Harnais de test pour les programmes Z80 assembles en .sna : lance
zesarux en arriere-plan (sans affichage), se connecte au protocole de
commande a distance (ZRCP), attend que le programme de test ait
fini de s'executer (il boucle sur lui-meme en fin de sequence, comme
tests/tap.h cote C/x86 -- ici pas de sortie de process, on lit l'etat
memoire directement), puis verifie une liste d'assertions memoire.

Usage typique (voir test_buffer.py) :
    from zrcp_harness import run_checks
    ok = run_checks("test_buffer.sna", [
        (0x9000, bytes([...]), "description du cas"),
    ])
    sys.exit(0 if ok else 1)
"""
import contextlib
import re
import socket
import subprocess
import sys
import time

ZESARUX = "zesarux"


def load_symbols(sym_path):
    """Parse un fichier --sym= de sjasmplus (lignes "label: EQU 0xXXXX")
    en dict {label: valeur}."""
    symbols = {}
    with open(sym_path) as f:
        for line in f:
            line = line.strip()
            if not line or ":" not in line:
                continue
            name, rest = line.split(":", 1)
            m = re.search(r"0x([0-9A-Fa-f]+)", rest)
            if m:
                symbols[name.strip()] = int(m.group(1), 16)
    return symbols


def resolve_addr(spec, symbols):
    """Resout 'NAME', 'NAME+N' ou 'NAME-N' (ou un entier/chaine
    numerique) en adresse via la table de symboles."""
    if isinstance(spec, int):
        return spec
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_.]*)\s*([+-]\s*\d+)?$", spec)
    if m and m.group(1) in symbols:
        base = symbols[m.group(1)]
        if m.group(2):
            base += int(m.group(2).replace(" ", ""))
        return base
    return int(spec, 0)


def _recv_until_prompt(sock, timeout=5.0):
    sock.settimeout(timeout)
    data = b""
    while not data.endswith(b"command> "):
        chunk = sock.recv(65536)
        if not chunk:
            break
        data += chunk
    return data


def read_memory(sock, addr, length):
    """Lit `length` octets consecutifs a `addr` (deja resolue). Renvoie
    des bytes (vide si la reponse n'est pas du hexadecimal valide)."""
    sock.sendall(f"read-memory {addr} {length}\n".encode())
    resp = _recv_until_prompt(sock)
    hexline = resp.split(b"\n", 1)[0].strip()
    try:
        return bytes.fromhex(hexline.decode())
    except ValueError:
        return b""


def read_memory_strided(sock, addr, count, stride):
    """Lit `count` octets, un par un, a addr, addr+stride, addr+2*stride,
    ... -- utilise pour les glyphes ecran ZX Spectrum (8 lignes de
    balayage espacees de 256 octets, voir spectrum/screen.asm)."""
    out = bytearray()
    for i in range(count):
        out += read_memory(sock, addr + i * stride, 1)
    return bytes(out)


@contextlib.contextmanager
def zesarux_session(sna_path, port=10123, machine="48k", run_delay=1.0,
                     tape_in=None, tape_out=None, extra_args=None):
    """Lance zesarux (sans affichage) avec le .sna donne, se connecte
    au ZRCP, laisse le programme tourner `run_delay` secondes, puis
    fournit le socket connecte (deja au prompt "command> "). Ferme
    proprement l'emulateur a la sortie du bloc `with`. Reutilisable
    pour des verifications personnalisees (voir test_screen.py) en plus
    de run_checks. tape_in/tape_out ajoutent --tape/--outtape (voir
    test_tape.py) ; extra_args ajoute des options zesarux arbitraires."""
    args = [
        ZESARUX,
        "--noconfigfile",
        "--machine", machine,
        "--vo", "null",
        "--ao", "null",
        "--enable-remoteprotocol",
        "--remoteprotocol-port", str(port),
        "--snap", sna_path,
    ]
    if tape_in:
        args += ["--tape", tape_in]
    if tape_out:
        args += ["--outtape", tape_out]
    if extra_args:
        args += extra_args
    proc = subprocess.Popen(
        args,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(1.0)
        sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        _recv_until_prompt(sock)
        time.sleep(run_delay)
        yield sock
        sock.sendall(b"exit-emulator\n")
        time.sleep(0.3)
        sock.close()
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def run_checks(sna_path, checks, port=10123, run_delay=1.0, machine="48k", symbols=None,
               tape_in=None, tape_out=None, extra_args=None):
    """checks: liste de (addr, expected:bytes, label:str) ou
    (addr, expected:bytes, label:str, stride:int) -- addr peut etre un
    entier ou une expression symbolique ("TEXTBUF+2") resolue via
    `symbols` (dict issu de load_symbols). stride>1 lit chaque octet
    separement a addr+i*stride (glyphes ecran) au lieu d'une lecture
    d'un bloc consecutif. Renvoie True si toutes les verifications
    passent (affiche un "ok"/"ECHEC" par cas, comme TAP_OK/TAP_FAIL
    cote asm x86)."""
    symbols = symbols or {}
    all_ok = True
    with zesarux_session(sna_path, port=port, machine=machine, run_delay=run_delay,
                          tape_in=tape_in, tape_out=tape_out, extra_args=extra_args) as sock:
        for check in checks:
            if len(check) == 4:
                addr_spec, expected, label, stride = check
            else:
                addr_spec, expected, label = check
                stride = 1
            addr = resolve_addr(addr_spec, symbols)
            if stride == 1:
                actual = read_memory(sock, addr, len(expected))
            else:
                actual = read_memory_strided(sock, addr, len(expected), stride)
            if actual == expected:
                print(f"ok: {label}")
            else:
                print(f"ECHEC: {label} -- attendu {expected.hex()}, obtenu {actual.hex()}")
                all_ok = False
    return all_ok


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: zrcp_harness.py <fichier.sna> <addr>:<hexoctets> [...]")
        sys.exit(2)
    sna = sys.argv[1]
    checks = []
    for spec in sys.argv[2:]:
        addr_s, hex_s = spec.split(":")
        checks.append((int(addr_s, 0), bytes.fromhex(hex_s), spec))
    ok = run_checks(sna, checks)
    sys.exit(0 if ok else 1)
