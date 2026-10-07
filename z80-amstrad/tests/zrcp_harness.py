#!/usr/bin/env python3
"""Harnais de test pour le portage Amstrad CPC : lance zesarux
(machine CPC464) en arriere-plan, sans affichage.

Contrairement au portage ZX Spectrum, zesarux (v8.1, cet
environnement) ne sait PAS charger de bande CPC (.cdt) ni de snapshot
CPC (.sna, "MV - SNA") via --tape/--snap -- confirme experimentalement
("Error: Tape format not supported" / ".SNA file corrupt", son parseur
--snap est code en dur pour le format Spectrum). Contournement : demarre
un CPC464 "propre" (ROM de base, BASIC), puis injecte directement le
binaire assemble en RAM via write-memory (ZRCP), et positionne PC via
set-register -- pas besoin de charger quoi que ce soit. Voir
tests/gen_cpc_bin.py -- pas d'equivalent ici (SAVEBIN suffit, pas de
tokenisation BASIC a construire comme cote Spectrum).

Usage typique (voir test_buffer.py) :
    from zrcp_harness import load_symbols, run_checks
    ok = run_checks("test_buffer.bin", start_symbol_addr, [
        (0x9000, bytes([...]), "description du cas"),
    ])
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


def _cmd(sock, c):
    sock.sendall((c + "\n").encode())
    return _recv_until_prompt(sock)


def read_memory(sock, addr, length):
    resp = _cmd(sock, f"read-memory {addr} {length}")
    hexline = resp.split(b"\n", 1)[0].strip()
    try:
        return bytes.fromhex(hexline.decode())
    except ValueError:
        return b""


def write_memory(sock, addr, data):
    vals = " ".join(str(b) for b in data)
    _cmd(sock, f"write-memory {addr} {vals}")


@contextlib.contextmanager
def cpc_session(bin_path, load_addr, start_addr, port=10200, boot_delay=1.5):
    """Demarre un CPC464 headless, injecte `bin_path` a `load_addr`,
    positionne PC=`start_addr`. Fournit le socket ZRCP connecte."""
    proc = subprocess.Popen(
        [
            ZESARUX, "--noconfigfile", "--machine", "CPC464",
            "--vo", "null", "--ao", "null",
            "--enable-remoteprotocol", "--remoteprotocol-port", str(port),
        ],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(boot_delay)
        sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        _recv_until_prompt(sock)
        with open(bin_path, "rb") as f:
            data = f.read()
        write_memory(sock, load_addr, data)
        _cmd(sock, f"set-register PC={start_addr}")
        time.sleep(0.3)
        yield sock
        _cmd(sock, "exit-emulator")
        time.sleep(0.3)
        sock.close()
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def send_key(sock, ch, delay_ms=100):
    _cmd(sock, f"send-keys-ascii {delay_ms} {ord(ch)}")


def run_checks(bin_path, load_addr, start_addr, checks, symbols=None, port=10200,
               boot_delay=1.5, settle=1.0):
    """checks: liste de (addr, expected:bytes, label:str). Renvoie True
    si toutes les verifications passent."""
    symbols = symbols or {}
    all_ok = True
    with cpc_session(bin_path, load_addr, start_addr, port=port, boot_delay=boot_delay) as sock:
        time.sleep(settle)
        for addr_spec, expected, label in checks:
            addr = resolve_addr(addr_spec, symbols)
            got = read_memory(sock, addr, len(expected))
            if got == expected:
                print(f"ok: {label}")
            else:
                print(f"ECHEC: {label} -- attendu {expected!r}, obtenu {got!r}")
                all_ok = False
    return all_ok
