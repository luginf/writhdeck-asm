#!/usr/bin/env python3
"""Verifie core/editor.asm via test_editor.asm (undo 1 niveau,
deplacement vertical avec word-wrap, recherche)."""
import sys
from zrcp_harness import load_symbols, run_checks

SYM = "test_editor.sym"
SNA = "test_editor.sna"


def main():
    symbols = load_symbols(SYM)
    textbuf = symbols["TEXTBUF"]

    def addr(n):
        return (textbuf + n).to_bytes(2, "little")

    checks = [
        # --- undo d'une insertion ('i' annule, retour a "h") ---
        ("snapA_undo_ret", bytes([1]), "editor_undo (insertion): doit renvoyer 1"),
        ("snapA_cy", bytes([0]), "editor_undo (insertion): ligne restauree = 0"),
        ("snapA_cx", (1).to_bytes(2, "little"), "editor_undo (insertion): colonne restauree = 1"),
        ("snapA_textend", addr(1), "editor_undo (insertion): TEXTEND==TEXTBUF+1"),
        ("snapA_text", b"h", "editor_undo (insertion): contenu redevenu 'h'"),

        # --- redo (restaure "hi", curseur d'avant l'annulation) ---
        ("snapR_redo_ret", bytes([1]), "editor_redo: doit renvoyer 1"),
        ("snapR_cy", bytes([0]), "editor_redo: ligne restauree = 0"),
        ("snapR_cx", (2).to_bytes(2, "little"), "editor_redo: colonne restauree = 2 (etat d'avant l'annulation)"),
        ("snapR_textend", addr(2), "editor_redo: TEXTEND==TEXTBUF+2"),
        ("snapR_text", b"hi", "editor_redo: contenu redevenu 'hi'"),

        # --- deuxieme redo : pile epuisee ---
        ("snapR2_redo_ret", bytes([0]), "editor_redo (pile vide): doit renvoyer 0"),

        # --- deuxieme undo : pile epuisee (le redo n'en repeuple pas) ---
        ("snapB_undo_ret", bytes([0]), "editor_undo (pile vide): doit renvoyer 0"),
        ("snapB_textend", addr(2), "editor_undo (pile vide): TEXTEND inchange (etat 'hi' post-redo)"),

        # --- delete puis undo (reinsertion du 'h') -- a ce stade le
        # buffer contient "hi" (restaure par le redo ci-dessus) ---
        ("snapC_textend_after_delete", addr(1), "editor_delete: TEXTEND==TEXTBUF+1 ('i' restant)"),
        ("snapC_undo_ret", bytes([1]), "editor_undo (suppression): doit renvoyer 1"),
        ("snapC_cy", bytes([0]), "editor_undo (suppression): ligne restauree = 0"),
        ("snapC_cx", (0).to_bytes(2, "little"), "editor_undo (suppression): colonne restauree = 0"),
        ("snapC_textend", addr(2), "editor_undo (suppression): TEXTEND==TEXTBUF+2 ('hi' restaure)"),
        ("snapC_text", b"h", "editor_undo (suppression): premier octet redevenu 'h'"),

        # --- word-wrap : ligne de 40 chiffres (32+8), puis "end" ---
        ("snapD_up_cy", bytes([0]), "move_up (meme ligne): ligne inchangee (0)"),
        ("snapD_up_cx", (3).to_bytes(2, "little"), "move_up (meme ligne): col 35->3 (1ere rangee)"),
        ("snapE_down_cy", bytes([0]), "move_down (retour): ligne inchangee (0)"),
        ("snapE_down_cx", (35).to_bytes(2, "little"), "move_down (retour): col 3->35 (2e rangee)"),
        ("snapF_cross_cy", bytes([1]), "move_down (changement de ligne): ligne 0->1"),
        ("snapF_cross_cx", (3).to_bytes(2, "little"), "move_down (changement de ligne): col==3 ('end')"),

        # --- recherche insensible a la casse ---
        ("snapG_found", bytes([1]), "editor_find: doit trouver 'chat'"),
        ("snapG_cy", bytes([0]), "editor_find: ligne trouvee == 0"),
        ("snapG_cx", (5).to_bytes(2, "little"), "editor_find: colonne trouvee == 5 (2e occurrence, CHAT)"),
    ]

    ok = run_checks(SNA, checks, symbols=symbols, port=10125)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
