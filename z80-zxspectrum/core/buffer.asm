; buffer.asm -- stockage et edition du texte, independant de la
; plateforme (pas d'adresse ecran, pas de port clavier). Portage adapte
; de writhdeck-c/src/buffer.c et du portage x86 (writhdeck-asm/src/
; buffer.asm), mais avec un MODELE MEMOIRE different : pas de tas/
; malloc (irrealiste sur 48 Ko), un seul buffer de texte contigu
; (TEXTBUF) + une table d'offsets de debut de ligne (LINETAB), plutot
; qu'un tableau de pointeurs vers des lignes allouees individuellement.
;
; Consequence agreable de ce modele : "couper une ligne" (Enter) et
; "fusionner deux lignes" (Suppr/Retour arriere en bout de ligne)
; deviennent de simples cas particuliers d'inserer/supprimer un octet
; (l'octet LINE_END lui-meme) -- pas besoin de routines separees de
; scission/fusion de chaines comme cote x86.
;
; Convention : chaque routine documente ses propres entrees/sorties
; registre par registre (pas de convention d'appel uniforme, peu
; idiomatique en Z80). Aucune instruction hors Z80 pur (pas de Z80N)
; pour rester compatible avec un futur portage Amstrad CPC.
;
; IMPORTANT : LINETAB[i] et TEXTEND contiennent des ADRESSES ABSOLUES
; (dans TEXTBUF..TEXTBUF+TEXTBUF_SIZE), PAS des offsets relatifs a
; TEXTBUF -- puisque TEXTBUF est une adresse fixe connue a l'assemblage,
; travailler en adresses absolues evite un "+TEXTBUF" a chaque usage.
; buffer_init initialise donc TEXTEND et LINETAB[0] a TEXTBUF (pas 0).

    include "layout.inc"

; ============================================================
; cp_hl_de -- compare HL a DE (non signe), ne modifie ni HL ni DE.
; Sortie (flags) : carry set si HL<DE ; zero set si HL==DE ;
; ni l'un ni l'autre si HL>DE. Detruit AF.
; ============================================================
cp_hl_de:
    ld a, h
    cp d
    ret nz
    ld a, l
    cp e
    ret

; ============================================================
; buf_insert_byte -- insere un octet dans TEXTBUF a une adresse donnee.
; Entree : HL = adresse d'insertion (dans [TEXTBUF, TEXTEND]), A = octet
; Detruit : AF, BC, DE, HL
; ============================================================
buf_insert_byte:
    ld (tmp_pos), hl
    ld (tmp_byte), a

    ld hl, (TEXTEND)
    ld de, (tmp_pos)
    or a
    sbc hl, de              ; HL = longueur a decaler (TEXTEND - tmp_pos)
    ld a, h
    or l
    jr z, .no_shift
    ld b, h
    ld c, l                 ; BC = longueur
    ld hl, (TEXTEND)
    dec hl                  ; HL = source = TEXTEND-1 (dernier octet valide)
    ld de, (TEXTEND)        ; DE = dest = TEXTEND
    lddr
.no_shift:
    ld hl, (tmp_pos)
    ld a, (tmp_byte)
    ld (hl), a

    ld hl, (TEXTEND)
    inc hl
    ld (TEXTEND), hl

    ld a, (tmp_byte)
    cp LINE_END
    jr z, .insert_new_line
    call bl__inc_entries_above_tmp_pos
    ret
.insert_new_line:
    call bl__splice_new_line_entry
    ret

; ============================================================
; buf_delete_byte -- supprime l'octet a une adresse donnee.
; Entree : HL = adresse a supprimer (doit etre < TEXTEND)
; Sortie : A = octet qui vient d'etre supprime
; Detruit : AF, BC, DE, HL
; ============================================================
buf_delete_byte:
    ld (tmp_pos), hl
    ld a, (hl)
    ld (tmp_byte), a

    ld hl, (TEXTEND)
    ld de, (tmp_pos)
    inc de
    or a
    sbc hl, de              ; HL = longueur a decaler (TEXTEND - (tmp_pos+1))
    ld a, h
    or l
    jr z, .no_shift
    ld b, h
    ld c, l                 ; BC = longueur
    ld hl, (tmp_pos)
    inc hl                  ; HL = source = tmp_pos+1
    ld de, (tmp_pos)        ; DE = dest = tmp_pos
    ldir
.no_shift:
    ld hl, (TEXTEND)
    dec hl
    ld (TEXTEND), hl

    ld a, (tmp_byte)
    cp LINE_END
    jr z, .remove_line
    call bl__dec_entries_above_tmp_pos
    jr .finish
.remove_line:
    call bl__remove_line_entry
.finish:
    ld a, (tmp_byte)
    ret

; ------------------------------------------------------------
; bl__inc_entries_above_tmp_pos -- incremente de 1 chaque entree de
; LINETAB strictement superieure a tmp_pos (insertion d'un octet
; normal, sans creer de nouvelle ligne). Detruit AF, BC, DE, HL.
; ------------------------------------------------------------
bl__inc_entries_above_tmp_pos:
    xor a
    ld (bl_idx), a
.loop:
    ld a, (bl_idx)
    ld b, a
    ld a, (LINECOUNT)
    cp b
    ret z
    ld h, 0
    ld l, b
    add hl, hl
    ld de, LINETAB
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)              ; DE = valeur de l'entree
    dec hl                  ; HL = &LINETAB[idx] (octet bas)
    push hl
    ld hl, (tmp_pos)
    call cp_hl_de           ; HL=tmp_pos, DE=entree -> C si entree>tmp_pos
    pop hl
    jr c, .do_inc
    jr .next
.do_inc:
    inc de
    ld (hl), e
    inc hl
    ld (hl), d
.next:
    ld a, (bl_idx)
    inc a
    ld (bl_idx), a
    jr .loop

; ------------------------------------------------------------
; bl__dec_entries_above_tmp_pos -- symetrique, decremente de 1 chaque
; entree strictement superieure a tmp_pos (suppression d'un octet
; normal). Detruit AF, BC, DE, HL.
; ------------------------------------------------------------
bl__dec_entries_above_tmp_pos:
    xor a
    ld (bl_idx), a
.loop:
    ld a, (bl_idx)
    ld b, a
    ld a, (LINECOUNT)
    cp b
    ret z
    ld h, 0
    ld l, b
    add hl, hl
    ld de, LINETAB
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    dec hl
    push hl
    ld hl, (tmp_pos)
    call cp_hl_de           ; C si entree>tmp_pos
    pop hl
    jr c, .do_dec
    jr .next
.do_dec:
    dec de
    ld (hl), e
    inc hl
    ld (hl), d
.next:
    ld a, (bl_idx)
    inc a
    ld (bl_idx), a
    jr .loop

; ------------------------------------------------------------
; bl__splice_new_line_entry -- insere une nouvelle entree LINETAB de
; valeur (tmp_pos+1) a la position qui garde la table triee, decale et
; incremente les entrees suivantes. LINECOUNT += 1. Suppose que
; l'appelant a deja verifie LINECOUNT<MAX_LINES (voir buffer_split_line).
; Detruit AF, BC, DE, HL.
; ------------------------------------------------------------
bl__splice_new_line_entry:
    xor a
    ld (bl_idx), a
    xor a
    ld (bl_k), a
.scan:
    ld a, (bl_idx)
    ld b, a
    ld a, (LINECOUNT)
    cp b
    jr z, .scan_done
    ld h, 0
    ld l, b
    add hl, hl
    ld de, LINETAB
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)              ; DE = entree
    push de
    ld hl, (tmp_pos)
    call cp_hl_de           ; HL=tmp_pos, DE=entree -> C si tmp_pos<entree
    pop de
    jr c, .not_le           ; tmp_pos<entree -> entree n'est PAS <= tmp_pos
    ld a, (bl_k)
    inc a
    ld (bl_k), a
.not_le:
    ld a, (bl_idx)
    inc a
    ld (bl_idx), a
    jr .scan
.scan_done:

    ld a, (LINECOUNT)
    ld (bl_idx), a          ; bl_idx = LINECOUNT (indice source = bl_idx-1)
.shift:
    ld a, (bl_idx)
    ld b, a
    ld a, (bl_k)
    cp b
    jr z, .shift_done
    ld a, (bl_idx)
    dec a
    ld b, a                 ; B = indice source = bl_idx-1
    ld h, 0
    ld l, b
    add hl, hl
    ld de, LINETAB
    add hl, de              ; HL = &LINETAB[idx-1] (source)
    ld e, (hl)
    inc hl
    ld d, (hl)              ; DE = valeur source
    inc de
    ld a, (bl_idx)
    ld h, 0
    ld l, a
    add hl, hl
    ld bc, LINETAB
    add hl, bc              ; HL = &LINETAB[idx] (destination)
    ld (hl), e
    inc hl
    ld (hl), d
    ld a, (bl_idx)
    dec a
    ld (bl_idx), a
    jr .shift
.shift_done:

    ld a, (bl_k)
    ld h, 0
    ld l, a
    add hl, hl
    ld de, LINETAB
    add hl, de
    ld de, (tmp_pos)
    inc de
    ld (hl), e
    inc hl
    ld (hl), d

    ld a, (LINECOUNT)
    inc a
    ld (LINECOUNT), a
    ret

; ------------------------------------------------------------
; bl__remove_line_entry -- retire de LINETAB l'entree valant
; (tmp_pos+1) (la ligne qui disparait par fusion), decale et
; decremente les entrees suivantes. LINECOUNT -= 1. Detruit AF, BC,
; DE, HL.
; ------------------------------------------------------------
bl__remove_line_entry:
    ld hl, (tmp_pos)
    inc hl
    ld (bl_target), hl
    xor a
    ld (bl_idx), a
.scan:
    ld a, (bl_idx)
    ld b, a
    ld h, 0
    ld l, b
    add hl, hl
    ld de, LINETAB
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)              ; DE = LINETAB[idx]
    ld hl, (bl_target)
    call cp_hl_de           ; Z si HL(bl_target)==DE(entree)
    jr z, .found
    ld a, (bl_idx)
    inc a
    ld (bl_idx), a
    jr .scan
.found:
    ; bl_idx = indice K a retirer
.shift:
    ld a, (bl_idx)
    inc a
    ld b, a                 ; B = idx+1 (indice source)
    ld a, (LINECOUNT)
    cp b
    jr z, .shift_done
    ld h, 0
    ld l, b
    add hl, hl
    ld de, LINETAB
    add hl, de              ; HL = &LINETAB[idx+1] (source)
    ld e, (hl)
    inc hl
    ld d, (hl)              ; DE = valeur source
    dec de
    ld a, (bl_idx)
    ld h, 0
    ld l, a
    add hl, hl
    ld bc, LINETAB
    add hl, bc              ; HL = &LINETAB[idx] (destination)
    ld (hl), e
    inc hl
    ld (hl), d
    ld a, (bl_idx)
    inc a
    ld (bl_idx), a
    jr .shift
.shift_done:
    ld a, (LINECOUNT)
    dec a
    ld (LINECOUNT), a
    ret

; ============================================================
; API publique
; ============================================================

; buffer_init -- reinitialise a un document vide (1 ligne vide).
buffer_init:
    ld hl, TEXTBUF          ; LINETAB/TEXTEND sont des ADRESSES ABSOLUES
    ld (TEXTEND), hl        ; (pas des offsets relatifs) -- documente en
    ld a, 1                 ; tete de fichier.
    ld (LINECOUNT), a
    ld hl, TEXTBUF
    ld (LINETAB), hl
    ret

; buffer_line_addr -- entree A=ligne ; sortie HL=LINETAB[ligne].
; Detruit AF, DE, HL.
buffer_line_addr:
    ld l, a
    ld h, 0
    add hl, hl
    ld de, LINETAB
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ex de, hl
    ret

; buffer_line_length -- entree A=ligne ; sortie HL=longueur (en octets).
; Detruit AF, BC, DE, HL.
buffer_line_length:
    ld (ll_line), a
    call buffer_line_addr
    ld (ll_start), hl

    ld a, (LINECOUNT)
    dec a
    ld b, a
    ld a, (ll_line)
    cp b
    jr z, .last_line

    ld a, (ll_line)
    inc a
    call buffer_line_addr
    ld de, (ll_start)
    or a
    sbc hl, de
    dec hl
    ret
.last_line:
    ld hl, (TEXTEND)
    ld de, (ll_start)
    or a
    sbc hl, de
    ret

; buffer_insert_char -- entree A=ligne, HL=colonne (en octets), C=car.
; Detruit AF, BC, DE, HL.
buffer_insert_char:
    push hl
    push bc
    call buffer_line_addr
    pop bc
    pop de
    add hl, de
    ld a, c
    jp buf_insert_byte

; buffer_split_line -- entree A=ligne, HL=colonne. Coupe la ligne en
; deux a la colonne donnee (insere un octet LINE_END). Refuse
; silencieusement si LINECOUNT a deja atteint MAX_LINES.
; Detruit AF, BC, DE, HL.
buffer_split_line:
    ld b, a
    ld a, (LINECOUNT)
    cp MAX_LINES
    ret nc
    push hl
    ld a, b
    call buffer_line_addr
    pop de
    add hl, de
    ld a, LINE_END
    jp buf_insert_byte

; buffer_delete_char -- entree A=ligne, HL=colonne. Si colonne est en
; fin de ligne et qu'une ligne suivante existe, fusionne (comme Suppr
; en fin de ligne cote x86) ; si c'est la derniere ligne, ne fait rien.
; Detruit AF, BC, DE, HL.
buffer_delete_char:
    ld (dc_line), a
    ld (dc_col), hl

    ld a, (dc_line)
    call buffer_line_length
    ld (dc_len), hl

    ld hl, (dc_col)
    ld de, (dc_len)
    call cp_hl_de           ; C: col<len ; Z: col==len ; sinon col>len
    jr c, .normal

    ld a, (LINECOUNT)
    dec a
    ld b, a
    ld a, (dc_line)
    cp b
    ret z                   ; derniere ligne -> rien a faire

    ld a, (dc_line)
    call buffer_line_addr
    ld de, (dc_len)
    add hl, de
    jp buf_delete_byte

.normal:
    ld a, (dc_line)
    call buffer_line_addr
    ld de, (dc_col)
    add hl, de
    jp buf_delete_byte

; buffer_backspace -- entree A=ligne, HL=colonne.
; Sortie : A=nouvelle ligne, HL=nouvelle colonne (inchangees si aucun
; effet, tout debut de document). Detruit BC, DE (et AF/HL via l'usage
; normal des sorties).
buffer_backspace:
    ld (bs_line), a
    ld (bs_col), hl

    ld a, h
    or l
    jr nz, .col_gt0

    ld a, (bs_line)
    or a
    ret z                   ; ligne==0 et col==0 -> rien a faire

    dec a
    ld (bs_prevline), a
    call buffer_line_length
    ld (bs_prevlen), hl

    ld a, (bs_prevline)
    call buffer_line_addr
    ld de, (bs_prevlen)
    add hl, de
    call buf_delete_byte

    ld a, (bs_prevline)
    ld hl, (bs_prevlen)
    ret

.col_gt0:
    ld a, (bs_line)
    ld hl, (bs_col)
    dec hl
    call buffer_delete_char
    ld a, (bs_line)
    ld hl, (bs_col)
    dec hl
    ret

; buffer_word_count -- sortie HL = nombre de mots (sequences d'octets
; non-espace separees par des espaces/tabulations/LINE_END). Detruit
; AF, BC, DE, HL.
buffer_word_count:
    xor a
    ld (wc_inword), a
    ld bc, 0
    ld hl, TEXTBUF
.loop:
    push bc
    ld de, (TEXTEND)
    call cp_hl_de
    pop bc
    jr nc, .done            ; HL>=TEXTEND -> fini
    ld a, (hl)
    cp ' '
    jr z, .is_space
    cp 9
    jr z, .is_space
    cp 10
    jr z, .is_space
    cp 11
    jr z, .is_space
    cp 12
    jr z, .is_space
    cp 13
    jr z, .is_space
    ld a, (wc_inword)
    or a
    jr nz, .advance
    ld a, 1
    ld (wc_inword), a
    inc bc
    jr .advance
.is_space:
    xor a
    ld (wc_inword), a
.advance:
    inc hl
    jr .loop
.done:
    ld h, b
    ld l, c
    ret

; buffer_char_count -- sortie HL = nombre total de caracteres (incluant
; les separateurs de ligne, coherent avec le format fichier). TEXTEND
; est une adresse absolue (voir en-tete du fichier) : le compte est
; simplement TEXTEND-TEXTBUF, une seule source de verite, pas de calcul
; separe par ligne. Detruit AF, DE.
buffer_char_count:
    ld hl, (TEXTEND)
    ld de, TEXTBUF
    or a
    sbc hl, de
    ret

; buffer_rebuild_linetab -- reconstruit LINETAB/LINECOUNT en scannant
; TEXTBUF[0..TEXTEND) (deja rempli par ailleurs -- chargement cassette
; futur, ou mise en place d'un scenario de test). Detruit AF, BC, DE, HL.
buffer_rebuild_linetab:
    xor a
    ld (LINECOUNT), a
    ld hl, TEXTBUF
    ld (rl_linestart), hl
.loop:
    ld a, (LINECOUNT)
    ld b, a
    ld h, 0
    ld l, b
    add hl, hl
    ld de, LINETAB
    add hl, de
    ld de, (rl_linestart)
    ld (hl), e
    inc hl
    ld (hl), d
    ld a, (LINECOUNT)
    inc a
    ld (LINECOUNT), a

    ld hl, (rl_linestart)
.scan:
    ld de, (TEXTEND)
    call cp_hl_de
    jr nc, .end_of_buffer
    ld a, (hl)
    cp LINE_END
    jr z, .found_end
    inc hl
    jr .scan
.found_end:
    inc hl
    ld (rl_linestart), hl
    jr .loop
.end_of_buffer:
    ret

; ============================================================
; donnees
; ============================================================
    ; scratch (variables de travail internes, non reentrantes -- un
    ; seul appel en cours a la fois, comme tout ce programme)
tmp_pos:      defw 0
tmp_byte:     defb 0
bl_idx:       defb 0
bl_k:         defb 0
bl_target:    defw 0
ll_line:      defb 0
ll_start:     defw 0
dc_line:      defb 0
dc_col:       defw 0
dc_len:       defw 0
bs_line:      defb 0
bs_col:       defw 0
bs_prevline:  defb 0
bs_prevlen:   defw 0
wc_inword:    defb 0
rl_linestart: defw 0

    ; etat du document
TEXTEND:      defw 0
LINECOUNT:    defb 0
LINETAB:      defs MAX_LINES*2
TEXTBUF:      defs TEXTBUF_SIZE
