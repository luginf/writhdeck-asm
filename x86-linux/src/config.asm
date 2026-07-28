; config.asm -- support minimal de writhd.ini/writhdeck.ini, au niveau
; de ce que writhdeck-c/src/config.c reconnait REELLEMENT (lui-meme
; n'implemente qu'un sous-ensemble du vrai fichier writhd.ini -- profils
; GUI/police/minuteur/navigateur/autosave/i18n/couleurs TUI/raccourcis y
; sont deja "ignores en Phase 1", voir son code). Ici, sous-ensemble
; reduit une fois de plus : seules les cles qui correspondent a une
; fonctionnalite REELLEMENT implementee dans ce portage minimal sont
; appliquees -- [editor] console_margin_cols/margin_cols et
; console_margin_rows/margin_rows (largeur de wrap effective + rangees
; utilisables, voir draw_editor), et [behaviour] word_goal, status_left,
; status_center, status_right (composition de la barre de statut par
; tokens, voir build_status_tokens/build_status_bar dans draw.asm).
; Tout le reste du fichier (browser_*, timer_*, autosave_*, lang,
; watch_file, markdown_support, docs_dir...) est lu sans erreur mais
; ignore, coherent avec le README (pas de navigateur, pas de minuteur,
; pas d'autosave/watch-file, pas d'i18n).
;
; Emplacement recherche, MEME PRECEDENCE que writhdeck-c/src/main.c
; (voir son commentaire round 22) : "writhd.ini" (8.3 FAT-compatible,
; pour un boot sur Toshiba Satellite 2180/disquette) dans le repertoire
; courant D'ABORD ; si absent, repli sur
; "$HOME/Documents/writhdeck/writhdeck.ini". Premier trouve gagne, pas
; de fusion des deux. Si $HOME est introuvable (variable d'environnement
; absente) ou qu'aucun des deux fichiers n'existe, les valeurs par
; defaut restent en place (memes defauts que cfg_load_defaults cote C :
; marges 6/4, word_goal 0 = desactive/masque).
;
; Attendu inclus apres buffer.asm (sys_open/sys_read/sys_close,
; buf_read_whole_file) et strutil.asm/heap.asm (malloc/free/memcpy/
; strlen), alors que le segment "readable executable" est deja actif.

SECTION_BUF_CAP = 32

; void cfg_set_string_field(dword* field_addr, const char* value) -- cdecl.
; free(*field_addr) puis *field_addr = strdup(value) -- meme discipline
; que set_field cote C (config.c) : TOUJOURS appele sur un pointeur deja
; heap-alloue (voir cfg_load_string_defaults, qui strdup les 3 defauts
; AVANT que try_load_ini ne puisse jamais appeler cette fonction) ou
; NULL (free(0) est un no-op sans danger, voir heap.asm:free -- le tout
; premier appel sur un champ encore a 0 est donc sans risque aussi).
cfg_set_string_field:
    proc_enter
    push ebx
    mov ebx, [ebp+8]
    push dword [ebx]
    call free
    add esp, 4
    push dword [ebp+12]
    call strdup
    add esp, 4
    mov [ebx], eax
    pop ebx
    proc_leave
    ret

; void cfg_load_string_defaults(void) -- cdecl. Alloue (strdup) les
; valeurs par defaut de status_left/center/right dans g_cfg_status_*
; -- memes defauts que cfg_load_defaults cote C (config.c). A appeler
; AVANT toute lecture de ces champs (cfg_init le fait en tout premier ;
; les tests qui exercent draw_editor/build_status_line sans passer par
; cfg_init doivent l'appeler eux-memes -- voir tests/test_draw.asm).
; Idempotent : un appel ulterieur libere proprement l'ancienne valeur
; (cfg_set_string_field) avant de reallouer les defauts.
cfg_load_string_defaults:
    proc_enter
    push default_status_left
    push g_cfg_status_left
    call cfg_set_string_field
    add esp, 8
    push default_status_center
    push g_cfg_status_center
    call cfg_set_string_field
    add esp, 8
    push default_status_right
    push g_cfg_status_right
    call cfg_set_string_field
    add esp, 8
    proc_leave
    ret

; void cfg_init(dword envp_ptr) -- cdecl. A appeler UNE FOIS depuis
; _start, avec l'adresse de envp[0] calculee directement depuis la pile
; d'entree du processus (voir main.asm : ce module ne sait pas la
; retrouver lui-meme, _start seul a acces a esp au tout debut). Tente
; "writhd.ini" puis le repli $HOME, applique les cles reconnues.
cfg_init:
    proc_enter
    call cfg_load_string_defaults

    mov eax, [ebp+8]
    mov [g_envp], eax

    push ini_name_short
    call try_load_ini
    add esp, 4
    test eax, eax
    jnz .done                    ; writhd.ini trouve et lu -- termine (pas de fusion)

    call build_fallback_ini_path
    test eax, eax
    jz .done                     ; pas de HOME -- rien de plus a tenter
    push g_ini_fallback_path
    call try_load_ini
    add esp, 4
.done:
    proc_leave
    ret

; --- recherche HOME dans l'environnement ---

; char* find_home_env(void) -- cdecl. Parcourt envp (g_envp, un tableau
; de pointeurs de chaines "NOM=valeur" termine par NULL) a la recherche
; du prefixe "HOME=". Renvoie un pointeur vers la valeur (dans la
; chaine d'origine, deja nul-terminee puisque c'est un suffixe de
; celle-ci -- pas de copie necessaire), ou 0 si absent. Detruit rien
; d'observable (callee-saved respectes).
find_home_env:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [g_envp]
    test esi, esi
    jz .not_found
.loop:
    mov eax, [esi]
    test eax, eax
    jz .not_found
    mov edi, eax
    mov ebx, home_prefix
    mov ecx, 5
.cmp_loop:
    mov dl, [edi]
    mov dh, [ebx]
    cmp dl, dh
    jne .next_entry
    inc edi
    inc ebx
    dec ecx
    jnz .cmp_loop
    mov eax, edi                  ; edi pointe juste apres "HOME="
    jmp .ret
.next_entry:
    add esi, 4
    jmp .loop
.not_found:
    xor eax, eax
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; int build_fallback_ini_path(void) -- cdecl. Construit
; g_ini_fallback_path = "<HOME>/Documents/writhdeck/writhdeck.ini".
; Renvoie 1 si HOME etait disponible (chemin construit), 0 sinon
; (buffer laisse tel quel -- l'appelant ne doit pas s'en servir).
build_fallback_ini_path:
    proc_enter
    call find_home_env
    test eax, eax
    jz .no_home
    push eax
    push g_ini_fallback_path
    call sb_append_str
    add esp, 8
    push ini_fallback_suffix
    push eax
    call sb_append_str
    add esp, 8
    mov byte [eax], 0
    mov eax, 1
    jmp .ret
.no_home:
    xor eax, eax
.ret:
    proc_leave
    ret

; --- chargement + analyse d'un fichier .ini ---

; int try_load_ini(const char* path) -- cdecl. Ouvre path ; si succes,
; lit tout son contenu (buf_read_whole_file, deja utilise par
; buffer_load_file) dans une copie privee +1 octet nul de garde (voir
; cfg_parse_buffer), l'analyse, libere, ferme, renvoie 1. Si path ne
; peut pas s'ouvrir, renvoie 0 sans toucher aux g_cfg_*.
try_load_ini:
    proc_enter
    sub esp, 8                    ; [ebp-4]=data brut, [ebp-8]=len
    push ebx
    push esi
    push edi
    push 0
    push O_RDONLY
    push dword [ebp+8]
    call sys_open
    add esp, 12
    mov edi, eax
    test edi, edi
    js .cant_open

    lea eax, [ebp-8]
    push eax
    push edi
    call buf_read_whole_file
    add esp, 8
    mov [ebp-4], eax
    push edi
    call sys_close
    add esp, 4

    ; copie privee +1 octet (garde nulle) : voir cfg_parse_buffer, qui
    ; peut ecrire un octet nul juste apres la derniere valeur si le
    ; fichier ne se termine pas par un saut de ligne -- buf_read_whole_file
    ; n'alloue exactement que [ebp-8] octets, ecrire a cette position
    ; SANS cette marge deborderait du bloc malloc'e (bug reel evite ici,
    ; pas juste theorique : un writhd.ini sans \n final est courant).
    mov eax, [ebp-8]
    inc eax
    push eax
    call malloc
    add esp, 4
    mov esi, eax                  ; esi = copie privee
    push dword [ebp-8]
    push dword [ebp-4]
    push esi
    call memcpy
    add esp, 12
    mov eax, [ebp-8]
    mov byte [esi+eax], 0

    push dword [ebp-4]
    call free
    add esp, 4

    push dword [ebp-8]
    push esi
    call cfg_parse_buffer
    add esp, 8

    push esi
    call free
    add esp, 4

    mov eax, 1
    jmp .ret
.cant_open:
    xor eax, eax
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void cfg_parse_buffer(char* data, dword len) -- cdecl. Analyse ligne
; par ligne (meme logique que cfg_load_ini cote C : suit la section
; [xxx] courante, split sur '=', trim espaces des deux cotes, ignore
; lignes vides/commentaires '#'/'%'), MODIFIE data en place (ecrit des
; octets nuls pour delimiter cle/valeur -- attendu sur une copie privee
; jetable, voir try_load_ini). N'applique que les cles reconnues (voir
; en-tete de fichier) ; tout le reste est silencieusement ignore, comme
; cote C.
cfg_parse_buffer:
    proc_enter
    sub esp, 28        ; -4 data -8 len -12 i(line_start) -16 ls -20 le
                        ; -24 eqpos -28 nl_pos (position BRUTE du '\n' de
                        ; cette ligne, ou len si aucun -- sauvegardee ICI,
                        ; PAS retrouvee par un nouveau scan apres coup :
                        ; le nul de fin de VALEUR (voir plus bas) peut
                        ; tomber exactement sur l'octet '\n' original
                        ; quand la ligne n'a pas d'espace de fin --
                        ; re-chercher '\n' apres l'avoir ainsi efface
                        ; aurait saute par-dessus la ligne SUIVANTE en
                        ; entier (bug reel rencontre en testant : une
                        ; 2e cle apres une 1ere sans espace de fin
                        ; n'etait jamais vue).
    push ebx
    push esi
    push edi
    mov eax, [ebp+8]
    mov [ebp-4], eax
    mov eax, [ebp+12]
    mov [ebp-8], eax
    mov dword [ebp-12], 0
    mov byte [g_cfg_section], 0

.line_loop:
    mov eax, [ebp-12]
    cmp eax, [ebp-8]
    jge .all_done

    ; j = recherche de '\n' a partir de i
    mov ecx, eax                  ; ecx = j
.find_nl:
    cmp ecx, [ebp-8]
    jge .have_j
    mov edx, [ebp-4]
    cmp byte [edx+ecx], 10
    je .have_j
    inc ecx
    jmp .find_nl
.have_j:
    mov [ebp-28], ecx             ; nl_pos, sauvegarde AVANT toute mutation
    ; le = j, sauf \r final -> le--
    mov edx, ecx
    cmp edx, [ebp-12]
    jle .no_cr
    mov ebx, [ebp-4]
    mov eax, edx
    dec eax
    cmp byte [ebx+eax], 13
    jne .no_cr
    dec edx
.no_cr:
    mov [ebp-20], edx             ; le

    ; ls = i, avance tant qu'espace
    mov eax, [ebp-12]
    mov [ebp-16], eax
.trim_left:
    mov eax, [ebp-16]
    cmp eax, [ebp-20]
    jge .trimmed_left
    mov ebx, [ebp-4]
    movzx edx, byte [ebx+eax]
    cmp edx, 0x20
    ja .trimmed_left
    inc eax
    mov [ebp-16], eax
    jmp .trim_left
.trimmed_left:

    ; le -= tant que dernier octet est un espace
.trim_right:
    mov eax, [ebp-20]
    cmp eax, [ebp-16]
    jle .trimmed_right
    mov ebx, [ebp-4]
    mov edx, eax
    dec edx
    movzx edx, byte [ebx+edx]
    cmp edx, 0x20
    ja .trimmed_right
    dec eax
    mov [ebp-20], eax
    jmp .trim_right
.trimmed_right:

    ; ligne vide ?
    mov eax, [ebp-16]
    cmp eax, [ebp-20]
    jge .next_line

    mov ebx, [ebp-4]
    add ebx, eax
    movzx edx, byte [ebx]
    cmp edx, '#'
    je .next_line
    cmp edx, '%'
    je .next_line
    cmp edx, '['
    jne .try_kv

    ; section : copier ]-delimite dans g_cfg_section
    mov esi, [ebp-16]
    inc esi                       ; apres '['
    mov edi, esi
.find_bracket:
    cmp edi, [ebp-20]
    jge .have_bracket
    mov ebx, [ebp-4]
    cmp byte [ebx+edi], ']'
    je .have_bracket
    inc edi
    jmp .find_bracket
.have_bracket:
    mov ecx, edi
    sub ecx, esi                  ; longueur du nom de section
    cmp ecx, SECTION_BUF_CAP-1
    jle .seclen_ok
    mov ecx, SECTION_BUF_CAP-1
.seclen_ok:
    mov edx, ecx                  ; edx = longueur, sauvee AVANT l'appel :
                                   ; memcpy utilise ecx comme compteur
                                   ; interne (rep movsb) et le laisse a 0
                                   ; en sortie -- caller-saved, PAS fiable
                                   ; apres l'appel (bug reel rencontre en
                                   ; testant : le premier octet de chaque
                                   ; nom de section se retrouvait ecrase
                                   ; par le nul de fin, ecrit en position
                                   ; 0 au lieu de la vraie longueur, voir
                                   ; la meme discipline dans num_to_ascii
                                   ; cote draw.asm).
    push ecx
    mov eax, [ebp-4]
    add eax, esi
    push eax
    push g_cfg_section
    call memcpy
    add esp, 12
    mov byte [g_cfg_section+edx], 0
    jmp .next_line

.try_kv:
    ; chercher '=' dans [ls, le)
    mov eax, [ebp-16]
    mov [ebp-24], eax
.find_eq:
    mov eax, [ebp-24]
    cmp eax, [ebp-20]
    jge .no_eq
    mov ebx, [ebp-4]
    cmp byte [ebx+eax], '='
    je .have_eq
    inc eax
    mov [ebp-24], eax
    jmp .find_eq
.no_eq:
    jmp .next_line
.have_eq:
    ; ke = eqpos, recule tant qu'espace (trim droit de la cle)
    mov eax, [ebp-24]
    mov ecx, eax                  ; ecx = ke
.key_trim:
    cmp ecx, [ebp-16]
    jle .key_trimmed
    mov ebx, [ebp-4]
    mov edx, ecx
    dec edx
    movzx edx, byte [ebx+edx]
    cmp edx, 0x20
    ja .key_trimmed
    dec ecx
    jmp .key_trim
.key_trimmed:
    ; cle vide -> ignorer la ligne
    mov eax, [ebp-16]
    cmp eax, ecx
    jge .next_line

    ; vs = eqpos+1, avance tant qu'espace (trim gauche de la valeur)
    mov eax, [ebp-24]
    inc eax
.val_trim:
    cmp eax, [ebp-20]
    jge .val_trimmed
    mov ebx, [ebp-4]
    movzx edx, byte [ebx+eax]
    cmp edx, 0x20
    ja .val_trimmed
    inc eax
    jmp .val_trim
.val_trimmed:

    ; nul-terminer cle (position ecx) et valeur (position [ebp-20]) --
    ; ecrase des octets de la copie privee, jamais le fichier reel.
    mov ebx, [ebp-4]
    mov byte [ebx+ecx], 0
    mov edx, [ebp-20]
    mov byte [ebx+edx], 0

    ; edi = pointeur cle, esi = pointeur valeur
    mov edi, [ebp-4]
    add edi, [ebp-16]
    mov esi, [ebp-4]
    add esi, eax

    call cfg_apply_kv

.next_line:
    ; avancer i au-dela du '\n' de CETTE ligne -- utilise nl_pos
    ; ([ebp-28]) sauvegarde en entree de l'iteration, PAS un nouveau
    ; scan (voir le commentaire au sommet de la fonction : le nul de
    ; fin de valeur peut avoir efface cet octet '\n' entre-temps).
    mov eax, [ebp-28]
    cmp eax, [ebp-8]
    jge .set_i
    inc eax
.set_i:
    mov [ebp-12], eax
    jmp .line_loop

.all_done:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; cfg_apply_kv -- entree EDI=cle (nul-terminee), ESI=valeur
; (nul-terminee), g_cfg_section=section courante. Pas cdecl (aide
; interne a cfg_parse_buffer, appelee dans son propre cadre de pile).
; IMPORTANT : streq/parse_uint preservent deja ebx/esi/edi (callee-saved,
; voir macros.inc) -- ne PAS les re-sauver "a la main" autour de leurs
; appels ici (bug reel rencontre en ecrivant cette fonction : un push
; supplementaire non compense par un pop correspondant, dans la chaine
; de comparaisons de cles, desalignait la pile jusqu'a faire "ret"
; sauter sur une adresse de retour corrompue -- silencieux la plupart
; du temps, aucune config appliquee, plutot qu'un crash systematique,
; ce qui l'a rendu difficile a repérer sans un test isolant cfg_init).
; Applique la cle si reconnue (section+nom), ignore sinon.
cfg_apply_kv:
    push ebx
    push esi
    push edi

    mov ebx, g_cfg_section

    push ebx
    push section_editor
    call streq
    add esp, 8
    test eax, eax
    jz .try_behaviour

    push edi
    push key_margin_cols_a
    call streq
    add esp, 8
    test eax, eax
    jnz .set_margin_cols
    push edi
    push key_margin_cols_b
    call streq
    add esp, 8
    test eax, eax
    jnz .set_margin_cols
    push edi
    push key_margin_rows_a
    call streq
    add esp, 8
    test eax, eax
    jnz .set_margin_rows
    push edi
    push key_margin_rows_b
    call streq
    add esp, 8
    test eax, eax
    jnz .set_margin_rows
    jmp .done

.set_margin_cols:
    push esi
    call parse_uint
    add esp, 4
    mov [g_cfg_margin_cols], eax
    jmp .done
.set_margin_rows:
    push esi
    call parse_uint
    add esp, 4
    mov [g_cfg_margin_rows], eax
    jmp .done

.try_behaviour:
    push ebx
    push section_behaviour
    call streq
    add esp, 8
    test eax, eax
    jz .done

    push edi
    push key_word_goal
    call streq
    add esp, 8
    test eax, eax
    jz .try_status_left
    push esi
    call parse_uint
    add esp, 4
    mov [g_cfg_word_goal], eax
    jmp .done

.try_status_left:
    push edi
    push key_status_left
    call streq
    add esp, 8
    test eax, eax
    jz .try_status_center
    push esi
    push g_cfg_status_left
    call cfg_set_string_field
    add esp, 8
    jmp .done

.try_status_center:
    push edi
    push key_status_center
    call streq
    add esp, 8
    test eax, eax
    jz .try_status_right
    push esi
    push g_cfg_status_center
    call cfg_set_string_field
    add esp, 8
    jmp .done

.try_status_right:
    push edi
    push key_status_right
    call streq
    add esp, 8
    test eax, eax
    jz .done
    push esi
    push g_cfg_status_right
    call cfg_set_string_field
    add esp, 8

.done:
    pop edi
    pop esi
    pop ebx
    ret

; --- utilitaires ---

; dword parse_uint(const char* s) -- cdecl. Chiffres decimaux en tete
; de s, s'arrete au premier caractere non-chiffre/nul. 0 si aucun
; chiffre -- toutes les valeurs de config lues ici (marges, objectif de
; mots) sont naturellement non negatives, pas de gestion de signe.
parse_uint:
    proc_enter
    push esi
    mov esi, [ebp+8]
    xor eax, eax
.loop:
    movzx ecx, byte [esi]
    cmp ecx, '0'
    jl .done
    cmp ecx, '9'
    jg .done
    imul eax, eax, 10
    sub ecx, '0'
    add eax, ecx
    inc esi
    jmp .loop
.done:
    pop esi
    proc_leave
    ret

; dword streq(const char* a, const char* b) -- cdecl. 1 si egales
; (octet par octet jusqu'au nul), 0 sinon.
streq:
    proc_enter
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]
.loop:
    mov al, [esi]
    mov ah, [edi]
    cmp al, ah
    jne .not_equal
    test al, al
    jz .equal
    inc esi
    inc edi
    jmp .loop
.equal:
    mov eax, 1
    jmp .ret
.not_equal:
    xor eax, eax
.ret:
    pop edi
    pop esi
    proc_leave
    ret

