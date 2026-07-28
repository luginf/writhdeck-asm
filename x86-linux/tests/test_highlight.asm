; test_highlight.asm -- portage direct des scenarios de
; writhdeck-c/tests/test_highlight.c : classify_line (titre/commentaire/
; liste, precedences, repli Markdown), heading_level (niveau + titre
; extrait, fermeture asymetrique), build_toc (Markdown+txt2tags
; melanges, cas sans titre). Voir src/highlight.asm pour le portage
; lui-meme.
format ELF executable
entry _start

include '../src/sys.inc'
include '../src/macros.inc'

segment readable executable

include 'tap.inc'
include '../src/heap.asm'
include '../src/strutil.asm'
include '../src/utf8.asm'
include '../src/buffer.asm'
include '../src/highlight.asm'

; dword str_eq(const char* a, const char* b) -- aide de test uniquement
; (pas dans src/), meme helper que tests/test_buffer.asm.
str_eq:
    proc_enter
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]
.loop:
    mov al, [esi]
    mov ah, [edi]
    cmp al, ah
    jne .neq
    test al, al
    jz .eq
    inc esi
    inc edi
    jmp .loop
.eq:
    mov eax, 1
    jmp .ret
.neq:
    xor eax, eax
.ret:
    pop edi
    pop esi
    proc_leave
    ret

; macro d'assertion uniquement pour ce fichier de test : compare eax a
; la valeur attendue, TAP_FAIL (et exit 1) si different.
macro ASSERT_EAX expected, msg
{
    local .ok
    cmp eax, expected
    je .ok
    TAP_FAIL msg
    .ok:
}

; idem, mais compare deux chaines (str_eq) plutot qu'un entier dans eax.
macro ASSERT_STR actual_ptr, expected_ptr, msg
{
    local .ok
    push expected_ptr
    push actual_ptr
    call str_eq
    add esp, 8
    test eax, eax
    jnz .ok
    TAP_FAIL msg
    .ok:
}

_start:
    ; --- classify_line : titre (marqueur "=") ---
    push 0
    push marker_pct
    push marker_eq
    push line_titre_simple
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_HEADING, 'titre simple'

    push 0
    push marker_pct
    push marker_eq
    push line_titre_espaces
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_HEADING, 'titre avec espaces de tete/fin'

    push 0
    push marker_pct
    push marker_eq
    push line_titre_sans_espace
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_HEADING, 'sans espace autour du contenu'

    push 0
    push marker_pct
    push marker_eqeq
    push line_titre_niveau2
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_HEADING, "marqueur configure a plusieurs caracteres ('==')"

    push 0
    push marker_pct
    push marker_eq
    push line_titre_vide
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, 'contenu vide -> pas un titre'

    push 0
    push marker_pct
    push marker_eq
    push line_texte_normal
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, 'ligne normale'

    push 0
    push marker_pct
    push marker_eq
    push line_titre_pas_ferme
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, 'marqueur non referme -> pas un titre'
    TAP_OK 'heading'

    ; --- heading_marker vide desactive la detection ---
    push 0
    push marker_pct
    push marker_empty
    push line_titre_simple
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, 'heading_marker vide desactive la detection'
    TAP_OK 'heading_disabled'

    ; --- commentaire ---
    push 0
    push marker_pct
    push marker_eq
    push line_commentaire_simple
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_COMMENT, 'commentaire simple'

    push 0
    push marker_pct
    push marker_eq
    push line_commentaire_sans_espace
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_COMMENT, "commentaire sans espace apres le marqueur"

    push 0
    push marker_pct
    push marker_eq
    push line_commentaire_indente
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, 'espace de tete AVANT le marqueur -- pas reconnu'

    push 0
    push marker_pct
    push marker_eq
    push line_commentaire_milieu
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, 'marqueur au milieu de ligne -- pas un commentaire'
    TAP_OK 'comment'

    ; --- comment_marker vide desactive la detection ---
    push 0
    push marker_empty
    push marker_eq
    push line_commentaire_ligne
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, 'comment_marker vide desactive la detection'
    TAP_OK 'comment_disabled'

    ; --- liste ---
    push 0
    push marker_pct
    push marker_eq
    push line_liste_simple
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_LIST, 'liste simple'

    push 0
    push marker_pct
    push marker_eq
    push line_liste_indentee
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_LIST, 'liste avec indentation'

    push 0
    push marker_pct
    push marker_eq
    push line_liste_sans_espace
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, 'tiret sans espace apres -- pas une liste'

    push 0
    push marker_pct
    push marker_eq
    push line_liste_milieu
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, 'tiret au milieu -- pas une liste'
    TAP_OK 'list'

    ; --- titres Markdown (actifs seulement si markdown_support) ---
    push 1
    push marker_pct
    push marker_eq
    push line_md_titre1
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_HEADING, "un '#' -> titre quand markdown_support actif"

    push 1
    push marker_pct
    push marker_eq
    push line_md_titre6
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_HEADING, "six '#' -> toujours un titre"

    push 1
    push marker_pct
    push marker_eq
    push line_md_sans_espace
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, "pas d'espace apres '#' -> pas un titre"

    push 1
    push marker_pct
    push marker_eq
    push line_md_titre7
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, "sept '#' -> pas un titre (max 6)"

    push 1
    push marker_pct
    push marker_eq
    push line_md_indente
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_HEADING, 'espaces de tete tolerees'
    TAP_OK 'markdown_heading_recognized_when_enabled'

    push 0
    push marker_pct
    push marker_eq
    push line_md_titre1
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, "'#' ignore quand markdown_support inactif"
    TAP_OK 'markdown_heading_ignored_when_disabled'

    ; --- liste Markdown ('*') ---
    push 1
    push marker_pct
    push marker_eq
    push line_md_liste
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_LIST, "'*' reconnu comme liste quand markdown_support actif"

    push 1
    push marker_pct
    push marker_eq
    push line_md_liste_sans_espace
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, "'*' sans espace -- pas une liste"

    push 0
    push marker_pct
    push marker_eq
    push line_md_liste
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_NORMAL, "'*' ignore quand markdown_support inactif"

    push 1
    push marker_pct
    push marker_eq
    push line_liste_simple
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_LIST, 'le tiret reste reconnu meme avec markdown_support actif'
    TAP_OK 'markdown_list_recognized_when_enabled'

    ; --- le marqueur configure est toujours essaye avant Markdown ---
    push 1
    push marker_pct
    push marker_eq
    push line_titre_simple
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_HEADING, "le marqueur configure l'emporte toujours"

    push 1
    push marker_pct
    push marker_eq
    push line_md_titre1
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_HEADING, 'Markdown sert de repli si le marqueur ne matche pas'
    TAP_OK 'markdown_heading_tried_only_after_configured_marker_fails'

    ; --- precedences ---
    push 0
    push marker_eq
    push marker_eq
    push line_titre_simple
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_HEADING, 'titre l emporte sur un commentaire quand les deux marqueurs coincident'
    TAP_OK 'precedence_heading_over_comment'

    push 0
    push marker_dash
    push marker_eq
    push line_liste_simple
    call classify_line
    add esp, 16
    ASSERT_EAX LINE_COMMENT, 'commentaire l emporte sur une apparence de liste quand les marqueurs coincident'
    TAP_OK 'precedence_comment_over_list'

    ; --- heading_level : niveau + titre extrait ---
    push 256
    push test_title_buf
    push 0
    push marker_eq
    push line_titre_simple
    call heading_level
    add esp, 20
    ASSERT_EAX 1, 'niveau 1'
    ASSERT_STR test_title_buf, str_titre, 'titre extrait sans les marqueurs'

    push 256
    push test_title_buf
    push 0
    push marker_eq
    push line_titre_niveau2
    call heading_level
    add esp, 20
    ASSERT_EAX 2, 'niveau 2 (marqueur double)'
    ASSERT_STR test_title_buf, str_titre_niveau2, 'titre extrait, niveau 2'

    push 256
    push test_title_buf
    push 0
    push marker_eq
    push line_titre_niveau3
    call heading_level
    add esp, 20
    ASSERT_EAX 3, 'niveau 3'

    push 256
    push test_title_buf
    push 0
    push marker_eq
    push line_texte_normal
    call heading_level
    add esp, 20
    ASSERT_EAX 0, 'pas un titre -> niveau 0'
    cmp byte [test_title_buf], 0
    je @f
    TAP_FAIL 'title_out vide quand ce n est pas un titre'
@@:
    TAP_OK 'heading_level_basic'

    ; --- fermeture asymetrique : niveau determine par l'ouverture seule ---
    push 256
    push test_title_buf
    push 0
    push marker_eq
    push line_titre_asymetrique
    call heading_level
    add esp, 20
    ASSERT_EAX 2, 'niveau determine par l ouverture seule (2), pas la fermeture (1)'
    ASSERT_STR test_title_buf, str_titre, 'titre correct malgre la fermeture asymetrique'
    TAP_OK 'heading_level_asymmetric_closing'

    ; --- heading_marker vide -> jamais un titre ---
    push 256
    push test_title_buf
    push 0
    push marker_empty
    push line_titre_simple
    call heading_level
    add esp, 20
    ASSERT_EAX 0, 'heading_marker vide -> jamais un titre'
    TAP_OK 'heading_level_disabled'

    ; --- heading_level : repli Markdown ---
    push 256
    push test_title_buf
    push 1
    push marker_eq
    push line_md_titre1
    call heading_level
    add esp, 20
    ASSERT_EAX 1, "niveau 1 (un '#')"
    ASSERT_STR test_title_buf, str_titre, "titre Markdown extrait sans le '#'"

    push 256
    push test_title_buf
    push 1
    push marker_eq
    push line_md_titre3
    call heading_level
    add esp, 20
    ASSERT_EAX 3, "niveau 3 (trois '#')"
    ASSERT_STR test_title_buf, str_sous_titre, 'titre correct au niveau 3'

    push 256
    push test_title_buf
    push 0
    push marker_eq
    push line_md_titre1
    call heading_level
    add esp, 20
    ASSERT_EAX 0, "'#' ignore quand markdown_support inactif"

    push 256
    push test_title_buf
    push 1
    push marker_eq
    push line_md_titre7
    call heading_level
    add esp, 20
    ASSERT_EAX 0, "sept '#' -> pas un titre"
    TAP_OK 'heading_level_markdown'

    ; --- build_toc : Markdown et txt2tags coexistent ---
    call buffer_new
    mov esi, eax

    mov eax, [esi+BUF_LINES]
    push dword [eax]
    call free
    add esp, 4
    push str_chapitre_md
    call strdup
    add esp, 4
    mov ecx, [esi+BUF_LINES]
    mov [ecx], eax

    push 0
    push esi
    call buffer_line_char_count
    add esp, 8
    push eax
    push 0
    push esi
    call buffer_split_line
    add esp, 12

    mov eax, [esi+BUF_LINES]
    push dword [eax+4]
    call free
    add esp, 4
    push str_chapitre_t2t
    call strdup
    add esp, 4
    mov ecx, [esi+BUF_LINES]
    mov [ecx+4], eax

    lea eax, [test_toc_count]
    push eax
    lea eax, [test_toc_entries]
    push eax
    push 1
    push marker_eq
    push esi
    call build_toc
    add esp, 20

    mov eax, [test_toc_count]
    ASSERT_EAX 2, 'les deux syntaxes de titre coexistent dans le meme document'

    mov edx, [test_toc_entries]
    mov eax, [edx+TOC_LINE]
    cmp eax, 0
    je @f
    TAP_FAIL 'toc[0].line'
@@:
    mov eax, [edx+TOC_LEVEL]
    cmp eax, 1
    je @f
    TAP_FAIL 'toc[0].level'
@@:
    lea eax, [edx+TOC_TITLE]
    push str_chapitre_md_title
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'toc[0].title (Markdown)'
@@:
    mov edx, [test_toc_entries]
    add edx, TOC_ENTRY_SIZE
    mov eax, [edx+TOC_LINE]
    cmp eax, 1
    je @f
    TAP_FAIL 'toc[1].line'
@@:
    mov eax, [edx+TOC_LEVEL]
    cmp eax, 1
    je @f
    TAP_FAIL 'toc[1].level'
@@:
    lea eax, [edx+TOC_TITLE]
    push str_chapitre_t2t_title
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'toc[1].title (txt2tags)'
@@:
    push dword [test_toc_entries]
    call free
    add esp, 4
    push esi
    call buffer_free
    add esp, 4
    TAP_OK 'build_toc_markdown'

    ; --- build_toc : trois titres sur quatre lignes, niveaux corrects ---
    call buffer_new
    mov esi, eax

    mov eax, [esi+BUF_LINES]
    push dword [eax]
    call free
    add esp, 4
    push str_chapitre_un_t2t
    call strdup
    add esp, 4
    mov ecx, [esi+BUF_LINES]
    mov [ecx], eax
    push 0
    push esi
    call buffer_line_char_count
    add esp, 8
    push eax
    push 0
    push esi
    call buffer_split_line
    add esp, 12

    mov eax, [esi+BUF_LINES]
    push dword [eax+4]
    call free
    add esp, 4
    push str_paragraphe
    call strdup
    add esp, 4
    mov ecx, [esi+BUF_LINES]
    mov [ecx+4], eax
    push 1
    push esi
    call buffer_line_char_count
    add esp, 8
    push eax
    push 1
    push esi
    call buffer_split_line
    add esp, 12

    mov eax, [esi+BUF_LINES]
    push dword [eax+8]
    call free
    add esp, 4
    push str_sous_section_t2t
    call strdup
    add esp, 4
    mov ecx, [esi+BUF_LINES]
    mov [ecx+8], eax
    push 2
    push esi
    call buffer_line_char_count
    add esp, 8
    push eax
    push 2
    push esi
    call buffer_split_line
    add esp, 12

    mov eax, [esi+BUF_LINES]
    push dword [eax+12]
    call free
    add esp, 4
    push str_chapitre_deux_t2t
    call strdup
    add esp, 4
    mov ecx, [esi+BUF_LINES]
    mov [ecx+12], eax

    lea eax, [test_toc_count]
    push eax
    lea eax, [test_toc_entries]
    push eax
    push 0
    push marker_eq
    push esi
    call build_toc
    add esp, 20

    mov eax, [test_toc_count]
    ASSERT_EAX 3, 'trois titres trouves sur quatre lignes'

    mov edx, [test_toc_entries]
    mov eax, [edx+TOC_LINE]
    cmp eax, 0
    je @f
    TAP_FAIL 'premiere entree : ligne'
@@:
    mov eax, [edx+TOC_LEVEL]
    cmp eax, 1
    je @f
    TAP_FAIL 'premiere entree : niveau'
@@:
    lea eax, [edx+TOC_TITLE]
    push str_chapitre_un
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'premiere entree : titre'
@@:
    mov edx, [test_toc_entries]
    add edx, TOC_ENTRY_SIZE
    mov eax, [edx+TOC_LINE]
    cmp eax, 2
    je @f
    TAP_FAIL 'deuxieme entree : ligne'
@@:
    mov eax, [edx+TOC_LEVEL]
    cmp eax, 2
    je @f
    TAP_FAIL 'deuxieme entree : niveau'
@@:
    lea eax, [edx+TOC_TITLE]
    push str_sous_section
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'deuxieme entree : titre'
@@:
    mov edx, [test_toc_entries]
    mov eax, TOC_ENTRY_SIZE
    imul eax, eax, 2
    add edx, eax
    mov eax, [edx+TOC_LINE]
    cmp eax, 3
    je @f
    TAP_FAIL 'troisieme entree : ligne'
@@:
    mov eax, [edx+TOC_LEVEL]
    cmp eax, 1
    je @f
    TAP_FAIL 'troisieme entree : niveau'
@@:
    lea eax, [edx+TOC_TITLE]
    push str_chapitre_deux
    push eax
    call str_eq
    add esp, 8
    test eax, eax
    jnz @f
    TAP_FAIL 'troisieme entree : titre'
@@:
    push dword [test_toc_entries]
    call free
    add esp, 4
    push esi
    call buffer_free
    add esp, 4
    TAP_OK 'build_toc'

    ; --- build_toc : aucun titre -> count == 0 ---
    call buffer_new
    mov esi, eax
    mov eax, [esi+BUF_LINES]
    push dword [eax]
    call free
    add esp, 4
    push str_juste_du_texte
    call strdup
    add esp, 4
    mov ecx, [esi+BUF_LINES]
    mov [ecx], eax

    lea eax, [test_toc_count]
    push eax
    lea eax, [test_toc_entries]
    push eax
    push 0
    push marker_eq
    push esi
    call build_toc
    add esp, 20

    mov eax, [test_toc_count]
    ASSERT_EAX 0, "aucune entree quand le document n'a pas de titre"

    push dword [test_toc_entries]
    call free
    add esp, 4
    push esi
    call buffer_free
    add esp, 4
    TAP_OK 'build_toc_no_headings'

    syscall1 SYS_EXIT, 0

segment readable writeable
include '../src/heap_data.inc'

marker_eq    db '=', 0
marker_eqeq  db '==', 0
marker_pct   db '%', 0
marker_dash  db '-', 0
marker_empty db 0

line_titre_simple            db '= Titre =', 0
line_titre_espaces           db '  = Titre =  ', 0
line_titre_sans_espace       db '=Titre=', 0
line_titre_niveau2           db '== Titre niveau 2 ==', 0
line_titre_niveau3           db '=== Niveau 3 ===', 0
line_titre_vide              db '= =', 0
line_texte_normal            db 'texte normal', 0
line_titre_pas_ferme          db '= pas ferme', 0
line_titre_asymetrique        db '== Titre =', 0

line_commentaire_simple       db '% un commentaire', 0
line_commentaire_sans_espace  db "%pas d'espace", 0
line_commentaire_indente      db '  % indente', 0
line_commentaire_milieu       db 'texte % pas un commentaire', 0
line_commentaire_ligne        db '% ligne', 0

line_liste_simple             db '- item', 0
line_liste_indentee           db '  - item indente', 0
line_liste_sans_espace        db '-sans espace', 0
line_liste_milieu             db 'texte - pas une liste', 0

line_md_titre1                db '# Titre', 0
line_md_titre3                db '### Sous-titre', 0
line_md_titre6                db '###### Niveau 6', 0
line_md_titre7                db '####### Trop', 0
line_md_sans_espace           db '#Titre', 0
line_md_indente               db '  # Indente', 0
line_md_liste                 db '* item', 0
line_md_liste_sans_espace     db '*sans espace', 0

str_titre           db 'Titre', 0
str_titre_niveau2    db 'Titre niveau 2', 0
str_sous_titre       db 'Sous-titre', 0

str_chapitre_md       db '# Chapitre Markdown', 0
str_chapitre_t2t      db '= Chapitre txt2tags =', 0
str_chapitre_md_title  db 'Chapitre Markdown', 0
str_chapitre_t2t_title db 'Chapitre txt2tags', 0

str_chapitre_un_t2t    db '= Chapitre un =', 0
str_paragraphe         db 'Un paragraphe normal, pas un titre.', 0
str_sous_section_t2t   db '== Sous-section ==', 0
str_chapitre_deux_t2t  db '= Chapitre deux =', 0
str_chapitre_un        db 'Chapitre un', 0
str_sous_section       db 'Sous-section', 0
str_chapitre_deux      db 'Chapitre deux', 0

str_juste_du_texte     db 'juste du texte, aucun titre', 0

test_title_buf   rb 256
test_toc_entries dd 0
test_toc_count   dd 0
