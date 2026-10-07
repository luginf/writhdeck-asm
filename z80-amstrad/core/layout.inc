; layout.inc -- constantes de dimensionnement partagees entre
; core/buffer.asm et core/editor.asm (et les tests). Independant de la
; plateforme (Spectrum/CPC aujourd'hui ou demain) -- n'ajuster qu'ici.
; Garde d'inclusion : buffer.asm ET editor.asm l'incluent chacun.

    IFNDEF WRITHDECK_LAYOUT_INC
    DEFINE WRITHDECK_LAYOUT_INC

TEXTBUF_SIZE equ 4096   ; taille du buffer de texte contigu (octets)
MAX_LINES    equ 200    ; plafond du nombre de lignes (tient sur 1 octet)
LINE_END     equ 10     ; octet marqueur de fin de ligne (LF) -- coincide
                         ; avec le format fichier : TEXTBUF[0..TEXTEND)
                         ; est directement le contenu pret a sauvegarder.

SCREEN_COLS   equ 32    ; largeur de wrap fixe (32 colonnes, ecran Spectrum)
MAX_WRAP_SEGS equ 32    ; plafond de rangees visuelles par ligne logique
                         ; (256 caracteres/rangee de 1 -- tres large marge)

    ENDIF
