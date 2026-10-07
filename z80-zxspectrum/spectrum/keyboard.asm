; keyboard.asm -- lecture de la matrice clavier ZX Spectrum (port $FE,
; 8 demi-rangees de 5 touches, actif a l'etat bas) et decodage vers des
; evenements abstraits. Specifique Spectrum (matrice/ports propres a
; cette machine) : ne fait PAS partie de core/.
;
; Le clavier Spectrum n'a ni fleches, ni Ctrl, ni Echap, ni Tab dedies
; (40 touches). Mapping retenu (voir plan, confirme avec l'utilisateur) :
;   CAPS SHIFT + 5/6/7/8 = gauche/bas/haut/droite (convention EDIT du
;                          ROM Spectrum, deja familiere)
;   CAPS SHIFT + 0       = Suppr/retour arriere (idem convention ROM)
;   SYMBOL SHIFT + S/Q/Z/Y = Sauver/Quitter/Annuler/Refaire (a la place
;                          d'un Ctrl+lettre qui n'existe pas ici)
;   SYMBOL SHIFT + quelques autres touches = ponctuation courante
;                          (virgule, point, point-virgule, guillemet,
;                          =, +, -, !@#$%&'()_ sur la rangee des
;                          chiffres) -- pas la table complete des
;                          symboles Sinclair (simplification assumee :
;                          les lettres reservees aux commandes
;                          ci-dessus perdent leur symbole d'origine).
;
; Lecture d'une demi-rangee : IN A,(C) avec B=octet haut du port
; (l'octet bas C=$FE est fixe), bits 0-4 du resultat = les 5 touches,
; ACTIF BAS (0=enfoncee).

KEY_NONE   equ 0
KEY_CHAR   equ 1
KEY_ENTER  equ 2
KEY_DELETE equ 3
KEY_LEFT   equ 4
KEY_RIGHT  equ 5
KEY_UP     equ 6
KEY_DOWN   equ 7
KEY_SAVE   equ 8
KEY_QUIT   equ 9
KEY_UNDO   equ 10
KEY_REDO   equ 11

; ZX_ARROWS_VIA_CAPS -- fleches via CAPS SHIFT+5/6/7/8 (convention EDIT
; du ROM). Desactive par defaut : le clavier 48K/128 standard n'a de
; toute facon AUCUNE touche flechee physique -- cette combinaison etait
; un pis-aller, et son ambiguite avec les chiffres 5/6/7/8 forcait un
; anti-rebond specifique (cout reel, et une source de bugs) rien que
; pour simuler des fleches inexistantes. CAPS+0 (Suppr/retour arriere)
; reste actif quel que soit ce reglage -- ce n'est pas une fleche.
; A activer (1) seulement pour une cible qui a de vraies touches
; flechees (ex. ZX Spectrum 128 Investronica, pave numerique dedie).
; Definissable par le fichier appelant (DEFINE + IFNDEF, avant l'include) :
; tests/test_keyboard.asm le force a 1 pour continuer a verifier ce
; decodage, meme si la cible reelle (spectrum/main.asm) l'expedie
; desactive.
    IFNDEF ZX_ARROWS_VIA_CAPS
        DEFINE ZX_ARROWS_VIA_CAPS 0
    ENDIF

; keyb__readrow -- entree B=octet haut du port ; sortie A=bits0-4
; (les autres bits ne sont pas fiables, toujours les masquer si besoin
; ailleurs -- ici les appelants ne testent que bit0-4 via BIT). Detruit
; AF, BC.
keyb__readrow:
    ld c, 0xFE
    in a, (c)
    ret

; keyb__apply_case -- entree C=lettre MAJUSCULE, kb_caps deja lu.
; Sortie : A=KEY_CHAR, C=lettre (majuscule si CAPS SHIFT enfoncee,
; minuscule sinon). Detruit AF.
keyb__apply_case:
    ld a, (kb_caps)
    or a
    jr nz, .keep_upper
    ld a, c
    add a, 32
    ld c, a
.keep_upper:
    ld a, KEY_CHAR
    ret

; keyb__read_shifts -- remplit kb_caps/kb_sym (0 ou 1). Detruit AF, BC.
keyb__read_shifts:
    ld b, 0xFE
    call keyb__readrow
    bit 0, a
    jr nz, .no_caps
    ld a, 1
    jr .have_caps
.no_caps:
    xor a
.have_caps:
    ld (kb_caps), a

    ld b, 0x7F
    call keyb__readrow
    bit 1, a
    jr nz, .no_sym
    ld a, 1
    jr .have_sym
.no_sym:
    xor a
.have_sym:
    ld (kb_sym), a
    ret

; --- une routine par demi-rangee : sortie A=KEY_NONE(0) si rien
; d'enfonce dans cette rangee, sinon A=type, C=caractere (si
; type=KEY_CHAR). Detruit AF, BC (et HL n'est pas utilise). ---

; Rangee 0 ($FEFE) : CAPS SHIFT, Z, X, C, V. SYM+Z = annuler.
keyb__row0:
    ld b, 0xFE
    call keyb__readrow
    ld (kb_rowval), a
keyb__row0_decode:
    ; point d'entree "decodage seul" (kb_rowval/kb_caps/kb_sym deja
    ; poses) -- utilise par les tests pour injecter un etat clavier
    ; sans passer par le port reel (voir tests/test_keyboard.*).
    bit 1, a
    jr nz, .no_z
    ld a, (kb_sym)
    or a
    jr z, .z_letter
    ld a, KEY_UNDO
    ret
.z_letter:
    ld c, 'Z'
    jp keyb__apply_case
.no_z:
    ld a, (kb_rowval)
    bit 2, a
    jr nz, .no_x
    ld c, 'X'
    jp keyb__apply_case
.no_x:
    ld a, (kb_rowval)
    bit 3, a
    jr nz, .no_c
    ld c, 'C'
    jp keyb__apply_case
.no_c:
    ld a, (kb_rowval)
    bit 4, a
    jr nz, .none0
    ld c, 'V'
    jp keyb__apply_case
.none0:
    xor a
    ret

; Rangee 1 ($FDFE) : A, S, D, F, G. SYM+S = sauver.
keyb__row1:
    ld b, 0xFD
    call keyb__readrow
    ld (kb_rowval), a
keyb__row1_decode:

    bit 0, a
    jr nz, .no_a
    ld c, 'A'
    jp keyb__apply_case
.no_a:
    ld a, (kb_rowval)
    bit 1, a
    jr nz, .no_s
    ld a, (kb_sym)
    or a
    jr z, .s_letter
    ld a, KEY_SAVE
    ret
.s_letter:
    ld c, 'S'
    jp keyb__apply_case
.no_s:
    ld a, (kb_rowval)
    bit 2, a
    jr nz, .no_d
    ld c, 'D'
    jp keyb__apply_case
.no_d:
    ld a, (kb_rowval)
    bit 3, a
    jr nz, .no_f
    ld c, 'F'
    jp keyb__apply_case
.no_f:
    ld a, (kb_rowval)
    bit 4, a
    jr nz, .none1
    ld c, 'G'
    jp keyb__apply_case
.none1:
    xor a
    ret

; Rangee 2 ($FBFE) : Q, W, E, R, T. SYM+Q = quitter.
keyb__row2:
    ld b, 0xFB
    call keyb__readrow
    ld (kb_rowval), a

    bit 0, a
    jr nz, .no_q
    ld a, (kb_sym)
    or a
    jr z, .q_letter
    ld a, KEY_QUIT
    ret
.q_letter:
    ld c, 'Q'
    jp keyb__apply_case
.no_q:
    ld a, (kb_rowval)
    bit 1, a
    jr nz, .no_w
    ld c, 'W'
    jp keyb__apply_case
.no_w:
    ld a, (kb_rowval)
    bit 2, a
    jr nz, .no_e
    ld c, 'E'
    jp keyb__apply_case
.no_e:
    ld a, (kb_rowval)
    bit 3, a
    jr nz, .no_r
    ld c, 'R'
    jp keyb__apply_case
.no_r:
    ld a, (kb_rowval)
    bit 4, a
    jr nz, .none2
    ld c, 'T'
    jp keyb__apply_case
.none2:
    xor a
    ret

; Rangee 3 ($F7FE) : 1,2,3,4,5. CAPS+5=GAUCHE (seule combinaison CAPS
; retenue sur cette rangee). SYM+1..5 = ! @ # $ %.
keyb__row3:
    ld b, 0xF7
    call keyb__readrow
    ld (kb_rowval), a
keyb__row3_decode:

    IF ZX_ARROWS_VIA_CAPS
    ld a, (kb_caps)
    or a
    jr z, .not_caps3
    ld a, (kb_rowval)
    bit 4, a
    jr nz, .none3
    ld a, KEY_LEFT
    ret
.not_caps3:
    ENDIF
    ld a, (kb_rowval)
    bit 0, a
    jr nz, .no_1
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .digit1
    ld c, '!'
    ret
.digit1:
    ld c, '1'
    ret
.no_1:
    ld a, (kb_rowval)
    bit 1, a
    jr nz, .no_2
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .digit2
    ld c, '@'
    ret
.digit2:
    ld c, '2'
    ret
.no_2:
    ld a, (kb_rowval)
    bit 2, a
    jr nz, .no_3
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .digit3
    ld c, '#'
    ret
.digit3:
    ld c, '3'
    ret
.no_3:
    ld a, (kb_rowval)
    bit 3, a
    jr nz, .no_4
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .digit4
    ld c, '$'
    ret
.digit4:
    ld c, '4'
    ret
.no_4:
    ld a, (kb_rowval)
    bit 4, a
    jr nz, .none3
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .digit5
    ld c, '%'
    ret
.digit5:
    ld c, '5'
    ret
.none3:
    xor a
    ret

; Rangee 4 ($EFFE) : 0,9,8,7,6. CAPS+0=SUPPR, CAPS+8=DROITE,
; CAPS+7=HAUT, CAPS+6=BAS (bit 1 -- 9 -- ignoree sous CAPS, pas de
; mapping choisi). SYM+0..6 = _ ) ( ' &.
keyb__row4:
    ld b, 0xEF
    call keyb__readrow
    ld (kb_rowval), a
keyb__row4_decode:

    ld a, (kb_caps)
    or a
    jr z, .not_caps4
    ld a, (kb_rowval)
    bit 0, a
    jr nz, .caps_no0
    ld a, KEY_DELETE
    ret
.caps_no0:
    IF ZX_ARROWS_VIA_CAPS
    ld a, (kb_rowval)
    bit 2, a
    jr nz, .caps_no8
    ld a, KEY_RIGHT
    ret
.caps_no8:
    ld a, (kb_rowval)
    bit 3, a
    jr nz, .caps_no7
    ld a, KEY_UP
    ret
.caps_no7:
    ld a, (kb_rowval)
    bit 4, a
    jr nz, .none4
    ld a, KEY_DOWN
    ret
    ELSE
    jr .not_caps4
    ENDIF

.not_caps4:
    ld a, (kb_rowval)
    bit 0, a
    jr nz, .no_0
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .digit0
    ld c, '_'
    ret
.digit0:
    ld c, '0'
    ret
.no_0:
    ld a, (kb_rowval)
    bit 1, a
    jr nz, .no_9
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .digit9
    ld c, ')'
    ret
.digit9:
    ld c, '9'
    ret
.no_9:
    ld a, (kb_rowval)
    bit 2, a
    jr nz, .no_8
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .digit8
    ld c, '('
    ret
.digit8:
    ld c, '8'
    ret
.no_8:
    ld a, (kb_rowval)
    bit 3, a
    jr nz, .no_7
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .digit7
    ld c, 39            ; apostrophe '
    ret
.digit7:
    ld c, '7'
    ret
.no_7:
    ld a, (kb_rowval)
    bit 4, a
    jr nz, .none4
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .digit6
    ld c, '&'
    ret
.digit6:
    ld c, '6'
    ret
.none4:
    xor a
    ret

; Rangee 5 ($DFFE) : P, O, I, U, Y. SYM+P=", SYM+O=;, SYM+Y=refaire.
keyb__row5:
    ld b, 0xDF
    call keyb__readrow
    ld (kb_rowval), a

    bit 0, a
    jr nz, .no_p
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .p_letter
    ld c, '"'
    ret
.p_letter:
    ld c, 'P'
    jp keyb__apply_case
.no_p:
    ld a, (kb_rowval)
    bit 1, a
    jr nz, .no_o
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .o_letter
    ld c, ';'
    ret
.o_letter:
    ld c, 'O'
    jp keyb__apply_case
.no_o:
    ld a, (kb_rowval)
    bit 2, a
    jr nz, .no_i
    ld c, 'I'
    jp keyb__apply_case
.no_i:
    ld a, (kb_rowval)
    bit 3, a
    jr nz, .no_u
    ld c, 'U'
    jp keyb__apply_case
.no_u:
    ld a, (kb_rowval)
    bit 4, a
    jr nz, .none5
    ld a, (kb_sym)
    or a
    jr z, .y_letter
    ld a, KEY_REDO
    ret
.y_letter:
    ld c, 'Y'
    jp keyb__apply_case
.none5:
    xor a
    ret

; Rangee 6 ($BFFE) : ENTER, L, K, J, H. SYM+L='=', SYM+K='+', SYM+J='-'.
keyb__row6:
    ld b, 0xBF
    call keyb__readrow
    ld (kb_rowval), a

    bit 0, a
    jr nz, .no_enter
    ld a, KEY_ENTER
    ret
.no_enter:
    ld a, (kb_rowval)
    bit 1, a
    jr nz, .no_l
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .l_letter
    ld c, '='
    ret
.l_letter:
    ld c, 'L'
    jp keyb__apply_case
.no_l:
    ld a, (kb_rowval)
    bit 2, a
    jr nz, .no_k
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .k_letter
    ld c, '+'
    ret
.k_letter:
    ld c, 'K'
    jp keyb__apply_case
.no_k:
    ld a, (kb_rowval)
    bit 3, a
    jr nz, .no_j
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .j_letter
    ld c, '-'
    ret
.j_letter:
    ld c, 'J'
    jp keyb__apply_case
.no_j:
    ld a, (kb_rowval)
    bit 4, a
    jr nz, .none6
    ld c, 'H'
    jp keyb__apply_case
.none6:
    xor a
    ret

; Rangee 7 ($7FFE) : SPACE, SYMBOL SHIFT, M, N, B. SYM+M='.', SYM+N=','.
keyb__row7:
    ld b, 0x7F
    call keyb__readrow
    ld (kb_rowval), a

    bit 0, a
    jr nz, .no_space
    ld a, KEY_CHAR
    ld c, ' '
    ret
.no_space:
    ld a, (kb_rowval)
    bit 2, a
    jr nz, .no_m
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .m_letter
    ld c, '.'
    ret
.m_letter:
    ld c, 'M'
    jp keyb__apply_case
.no_m:
    ld a, (kb_rowval)
    bit 3, a
    jr nz, .no_n
    ld a, (kb_sym)
    or a
    ld a, KEY_CHAR
    jr z, .n_letter
    ld c, ','
    ret
.n_letter:
    ld c, 'N'
    jp keyb__apply_case
.no_n:
    ld a, (kb_rowval)
    bit 4, a
    jr nz, .none7
    ld c, 'B'
    jp keyb__apply_case
.none7:
    xor a
    ret

; keyb__scan_once -- lit l'etat des majuscules puis les 8 rangees,
; renvoie le premier evenement trouve (A=type, C=caractere le cas
; echeant), ou A=KEY_NONE si rien n'est enfonce. Memorise aussi dans
; kb_last_port l'octet haut du port de la rangee ou l'evenement a ete
; trouve (utilise par keyb_wait_key pour n'attendre QUE cette rangee-la
; au relachement -- voir plus bas). Detruit AF, BC.
keyb__scan_once:
    call keyb__read_shifts

    call keyb__row0
    or a
    jr nz, .found0
    call keyb__row1
    or a
    jr nz, .found1
    call keyb__row2
    or a
    jr nz, .found2
    call keyb__row3
    or a
    jr nz, .found3
    call keyb__row4
    or a
    jr nz, .found4
    call keyb__row5
    or a
    jr nz, .found5
    call keyb__row6
    or a
    jr nz, .found6
    call keyb__row7
    or a
    jr nz, .found7
    ret                      ; A=0 (KEY_NONE), rien d'enfonce nulle part
.found7:                    ; touche produite en rangee 7 (port $7FFE)
    push af
    ld a, 0x7F
    ld (kb_last_port), a
    pop af
    ret
.found0:                    ; rangee 0 (port $FEFE)
    push af
    ld a, 0xFE
    ld (kb_last_port), a
    pop af
    ret
.found1:                    ; rangee 1 (port $FDFE)
    push af
    ld a, 0xFD
    ld (kb_last_port), a
    pop af
    ret
.found2:                    ; rangee 2 (port $FBFE)
    push af
    ld a, 0xFB
    ld (kb_last_port), a
    pop af
    ret
.found3:                    ; rangee 3 (port $F7FE)
    push af
    ld a, 0xF7
    ld (kb_last_port), a
    pop af
    ret
.found4:                    ; rangee 4 (port $EFFE)
    push af
    ld a, 0xEF
    ld (kb_last_port), a
    pop af
    ret
.found5:                    ; rangee 5 (port $DFFE)
    push af
    ld a, 0xDF
    ld (kb_last_port), a
    pop af
    ret
.found6:                    ; rangee 6 (port $BFFE)
    push af
    ld a, 0xBF
    ld (kb_last_port), a
    pop af
    ret

; keyb_wait_key -- lecture BLOQUANTE d'une touche : attend qu'une
; touche produise un evenement, puis attend que ce meme evenement ne
; soit plus decodable avant de renvoyer (evite un "orage" de
; repetitions -- un seul evenement par appui physique). Attend
; seulement la touche/combinaison DECODEE, PAS le relachement complet
; des 40 touches du clavier : bug reel corrige -- l'ancienne version
; appelait keyb__any_pressed (relachement TOTAL exige), ce qui bloquait
; l'editeur des que l'utilisateur enchainait les frappes assez vite
; pour qu'une touche suivante soit deja enfoncee avant que la
; precedente ne soit totalement relachee (a peu pres n'importe quelle
; frappe rapide, Entree/Suppr y compris -- symptome rapporte : "ca
; bloque en fin de ligne", "backspace ne fonctionne pas").
; Sortie : A=type (KEY_*), C=caractere si type=KEY_CHAR. Detruit AF,
; BC, DE, HL.
keyb_wait_key:
.wait_press:
    call keyb__scan_once
    or a
    jr z, .wait_press

    ; anti-rebond CIBLE : 2 touches d'une combinaison (CAPS SHIFT+0,
    ; SYM SHIFT+S...) ne sont jamais enfoncees a l'exact meme instant --
    ; sans un court delai de confirmation, on peut lire "0 seul"
    ; (chiffre) une fraction de seconde avant que CAPS SHIFT ne soit vu
    ; enfonce, et interpreter une combinaison comme un caractere simple
    ; (bug reel rencontre en testant : CAPS+0 tapait parfois '0' au
    ; lieu de faire Retour arriere). Mais appliquer ce delai a CHAQUE
    ; frappe (toute premiere version de ce correctif) ralentissait
    ; sensiblement la frappe normale (symptome rapporte : "ca oublie
    ; des lettres si on tape vite", regression reelle par rapport a
    ; l'ecran BASIC). Le delai n'est donc applique QUE pour les touches
    ; reellement ambigues : ENTREE et les caracteres ordinaires (sans
    ; second sens CAPS/SYM) valident immediatement, sans aucun cout --
    ; comme la frappe native BASIC.
    cp KEY_ENTER
    jr z, .no_debounce
    cp KEY_CHAR
    jr nz, .debounce            ; touche speciale (fleche/suppr/sauver/quitter/annuler/refaire)
    ld b, a                     ; sauver le type (KEY_CHAR) -- 'a' va servir au test du caractere
    ld a, c
    call keyb__is_risky_char
    ld a, b                     ; restaurer le type avant de continuer (A doit contenir le type ici)
    jr nc, .no_debounce         ; caractere ordinaire, pas d'ambiguite -> valider tout de suite
.debounce:
    ; Boucle d'attente calibree en T-states (PAS de HALT/interruptions
    ; -- voir _start pour pourquoi) : quelques ms suffisent largement
    ; pour que les doigts finissent d'enfoncer une combinaison
    ; volontaire, puis on relit l'etat stabilise avant de se decider.
    call keyb__settle_delay
    call keyb__scan_once
    or a
    jr z, .wait_press           ; plus rien decodable (relache avant confirmation) -> reprendre
.no_debounce:
    ld (kw_type), a
    ld a, c
    ld (kw_char), a
    ; Attend le relachement -- mais SEULEMENT de la rangee ($FE + kb_last_port,
    ; 5 touches) qui a produit l'evenement, pas des 40 touches du
    ; clavier entier (bug reel corrige : en frappe rapide, une touche
    ; suivante d'une AUTRE rangee est presque toujours deja enfoncee
    ; avant que la precedente ne soit relachee -- "chevauchement"
    ; normal de la frappe -- et si on exige le silence total du
    ; clavier, cette touche suivante peut etre entierement enfoncee
    ; PUIS relachee pendant qu'on attend, et donc jamais vue : elle
    ; disparait purement et simplement. Ne surveiller que la rangee
    ; d'origine resout ce cas, qui est le cas courant -- il reste un
    ; cas plus rare non couvert : deux touches de la MEME rangee
    ; enchainees tres vite).
.wait_release:
    ld a, (kb_last_port)
    ld b, a
    ld c, 0xFE
    in a, (c)
    and 0x1F
    cp 0x1F
    jr nz, .wait_release
    ld a, (kw_char)
    ld c, a
    ld a, (kw_type)
    ret

; keyb__is_risky_char -- entree A=caractere. Sortie : carry POSITIONNE
; si ce caractere correspond a une touche ayant aussi un sens CAPS/SYM
; different (0,5,6,7,8,Z,S,Q,Y) -- ambigu en cas de detection un peu
; trop tot, merite l'anti-rebond. Carry EFFACE sinon (caractere sans
; second sens, aucune ambiguite possible). Detruit AF.
keyb__is_risky_char:
    cp '0'
    jr z, .risky
    IF ZX_ARROWS_VIA_CAPS
    cp '5'
    jr z, .risky
    cp '6'
    jr z, .risky
    cp '7'
    jr z, .risky
    cp '8'
    jr z, .risky
    ENDIF
    cp 'Z'
    jr z, .risky
    cp 'z'
    jr z, .risky
    cp 'S'
    jr z, .risky
    cp 's'
    jr z, .risky
    cp 'Q'
    jr z, .risky
    cp 'q'
    jr z, .risky
    cp 'Y'
    jr z, .risky
    cp 'y'
    jr z, .risky
    or a
    ret
.risky:
    scf
    ret

; keyb__settle_delay -- attente calibree (~5ms a 3.5MHz), boucle pure,
; PAS de HALT/interruptions (voir _start). Detruit AF, BC.
keyb__settle_delay:
    ld bc, 700
.loop:
    dec bc
    ld a, b
    or c
    jr nz, .loop
    ret

; ============================================================
; donnees
; ============================================================
kb_caps:      defb 0
kb_sym:       defb 0
kb_rowval:    defb 0
kb_last_port: defb 0
kw_type:      defb 0
kw_char:      defb 0
