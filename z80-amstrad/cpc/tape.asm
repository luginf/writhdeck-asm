; tape.asm -- sauvegarde/chargement cassette Amstrad CPC, via les
; routines firmware CAS_* (jumpblock ROM, equivalent du SA-BYTES/
; LD-BYTES du Spectrum). Specifique Amstrad : ne fait PAS partie de
; core/.
;
; NOTE IMPORTANTE (limitation assumee, a verifier) : ce fichier n'a PAS
; encore ete verifie par un test bout-en-bout (sauver puis recharger)
; dans cet environnement -- l'emulateur zesarux disponible ici ne sait
; pas charger/produire de bande CPC (.cdt) ni de snapshot CPC (.sna),
; voir README pour le contournement utilise pour les autres tests
; (injection memoire directe via ZRCP). Ce fichier suit la meme
; structure d'appel que spectrum/tape.asm (tape_save/tape_load) pour
; rester previsible, mais son bon fonctionnement reel reste a confirmer
; (materiel reel ou emulateur pilotable comme xcpc).

CAS_OUT_OPEN   equ 0xBC59  ; HL=pointeur bloc info fichier (voir cas_header)
CAS_OUT_DIRECT equ 0xBC6B  ; HL=pointeur donnees, DE=longueur
CAS_OUT_CLOSE  equ 0xBC5F
CAS_IN_OPEN    equ 0xBC77  ; HL=pointeur bloc info fichier -> rempli par la routine
CAS_IN_DIRECT  equ 0xBC83  ; HL=pointeur destination, DE=longueur max
CAS_IN_CLOSE   equ 0xBC7D

; tape_save -- entree HL=adresse source, DE=longueur. Sauve le
; document sous le nom fixe "WRITHDEK" (8 caracteres max, convention
; AMSDOS). Detruit AF, BC, DE, HL.
tape_save:
    ld (ts_addr), hl
    ld (ts_len), de

    ld hl, cas_header
    call CAS_OUT_OPEN

    ld hl, (ts_addr)
    ld de, (ts_len)
    call CAS_OUT_DIRECT

    call CAS_OUT_CLOSE
    ret

; tape_load -- entree HL=adresse destination, DE=longueur maximale.
; Sortie : DE=longueur reellement chargee. Detruit AF, BC, HL.
tape_load:
    ld (tl_addr), hl
    ld (tl_len), de

    ld hl, cas_header
    call CAS_IN_OPEN

    ld hl, (tl_addr)
    ld de, (tl_len)
    call CAS_IN_DIRECT

    call CAS_IN_CLOSE
    ret

; ============================================================
; donnees
; ============================================================
ts_addr: defw 0
ts_len:  defw 0
tl_addr: defw 0
tl_len:  defw 0

; bloc info fichier attendu par CAS_OUT_OPEN/CAS_IN_OPEN : nom (8
; caracteres, complete par des espaces), 3 octets reserves, type de
; bloc (1 = binaire), longueur (2 octets, ignoree pour CAS_OUT_DIRECT
; qui utilise DE), adresse de chargement (2 octets), premier bloc (2
; octets, ignore ici) -- format standard AMSDOS.
cas_header:
    defb "WRITHDEK"
    defb 0, 0, 0
    defb 2
    defw 0
    defw 0
    defw 0
