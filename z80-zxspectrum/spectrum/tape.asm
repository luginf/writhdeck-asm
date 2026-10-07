; tape.asm -- SAVE/LOAD cassette via les routines standard de la ROM
; 48K (SA-BYTES $04C2, LD-BYTES $0556), format CODE nomme "WRITHDECK".
; Specifique Spectrum (ROM 48K) : ne fait PAS partie de core/. Depend
; de cp_hl_de (core/buffer.asm), suppose deja assemble avec ce module.
;
; Convention ROM (SA-BYTES/LD-BYTES) : IX=adresse donnees, DE=longueur,
; A=octet drapeau (0=en-tete, 0xFF=bloc de donnees), carry flag DOIT
; etre positionne (SCF) avant l'appel. LD-BYTES renvoie carry POSITIONNE
; en cas de succes, EFFACE en cas d'erreur (bande absente/checksum
; invalide) -- verifie a chaque appel.
;
; Simplification assumee : pas de verification du nom sur bande (on
; accepte le premier en-tete rencontre, comme un programme mono-fichier
; suppose une bande dediee) ; pas de gestion d'erreur utilisateur au-
; dela d'un code retour succes/echec (pas de message d'erreur affiche
; ici -- a la charge de l'appelant, voir spectrum/main.asm).

SA_BYTES equ 0x04C2
LD_BYTES equ 0x0556

; tape_save -- entree : HL=adresse de depart des donnees, DE=longueur.
; Sauve un en-tete CODE (nom "WRITHDECK ") puis le bloc de donnees.
; Detruit AF, BC, DE, HL, IX.
tape_save:
    ld (ts_header+11), de
    ld (ts_header+13), hl
    ld (ts_dataaddr), hl
    ld (ts_datalen), de

    scf
    ld ix, ts_header
    ld de, 17
    xor a
    call SA_BYTES

    scf
    ld ix, (ts_dataaddr)
    ld de, (ts_datalen)
    ld a, 0xFF
    call SA_BYTES
    ret

; tape_load -- entree : HL=adresse cible, DE=longueur maximale
; acceptee. Lit un en-tete puis le bloc de donnees (tronque a DE si
; l'en-tete declare une longueur plus grande). Sortie : A=1 si succes
; (BC=longueur reellement chargee), A=0 si echec (en-tete ou donnees
; illisibles -- BC=0). Detruit AF, BC, DE, HL, IX.
tape_load:
    ld (tl_target), hl
    ld (tl_maxlen), de

    scf
    ld ix, tl_header
    ld de, 17
    xor a
    call LD_BYTES
    jr nc, .fail

    ld hl, (tl_header+11)
    ld de, (tl_maxlen)
    call cp_hl_de              ; HL=longueur declaree, DE=max -> C si declaree<max
    jr c, .uselen
    ld hl, (tl_maxlen)
.uselen:
    ld (tl_declen), hl

    scf
    ld ix, (tl_target)
    ld de, (tl_declen)
    ld a, 0xFF
    call LD_BYTES
    jr nc, .fail

    ld hl, (tl_declen)
    ld b, h
    ld c, l
    ld a, 1
    ret
.fail:
    ld bc, 0
    xor a
    ret

; ============================================================
; donnees
; ============================================================
ts_header: defb 3                 ; type = CODE
           defm "WRITHDECK "      ; nom (10 caracteres)
           defw 0                 ; longueur (rempli par tape_save)
           defw 0                 ; adresse de chargement (idem)
           defw 32768             ; param2, non utilise pour CODE
ts_dataaddr: defw 0
ts_datalen:  defw 0

tl_header: defs 17
tl_target: defw 0
tl_maxlen: defw 0
tl_declen: defw 0
