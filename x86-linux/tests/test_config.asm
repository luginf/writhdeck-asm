; test_config.asm -- exercice config.asm : parse_uint/streq (utilitaires),
; cfg_parse_buffer/cfg_apply_kv (sections, alias de cles, commentaires
; '#'/'%', lignes vides, cles inconnues ignorees, derniere cle gagne en
; cas de doublon, dernier octet sans saut de ligne final), find_home_env/
; build_fallback_ini_path (repli $HOME), et try_load_ini de bout en
; bout sur un vrai fichier temporaire. N'exerce PAS cfg_init lui-meme
; (qui a besoin de envp tel que _start le calcule depuis la pile brute
; du processus, voir main.asm) -- g_envp est arme directement ici pour
; les tests find_home_env/build_fallback_ini_path.
format ELF executable
entry _start

include '../src/sys.inc'
include '../src/macros.inc'

segment readable executable

include 'tap.inc'
include '../src/heap.asm'
include '../src/strutil.asm'
include '../src/utf8.asm'
include '../src/term.asm'
include '../src/buffer.asm'
include '../src/highlight.asm'
include '../src/editor.asm'
include '../src/ui_ansi.asm'
include '../src/draw.asm'
include '../src/config.asm'

; dword str_eq(const char* a, const char* b) -- aide de test uniquement.
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

; void sys_unlink_helper(const char* path) -- aide de test uniquement.
sys_unlink_helper:
    proc_enter
    push ebx
    mov ebx, [ebp+8]
    mov eax, SYS_UNLINK
    int 0x80
    pop ebx
    proc_leave
    ret

; void reset_cfg(dword margin_cols, dword margin_rows, dword word_goal)
; -- aide de test uniquement : arme des sentinelles avant chaque
; scenario pour verifier precisement ce que cfg_parse_buffer a
; effectivement touche (une cle non reconnue/absente NE DOIT PAS
; modifier la valeur en place).
reset_cfg:
    proc_enter
    mov eax, [ebp+8]
    mov [g_cfg_margin_cols], eax
    mov eax, [ebp+12]
    mov [g_cfg_margin_rows], eax
    mov eax, [ebp+16]
    mov [g_cfg_word_goal], eax
    proc_leave
    ret

; void parse_ini_source(const char* src) -- aide de test uniquement.
; Copie src dans un tampon prive +1 octet de garde (meme discipline que
; try_load_ini) et appelle cfg_parse_buffer dessus -- evite d'ecrire
; directement dans un litteral du segment executable (cfg_parse_buffer
; mute son tampon en place).
parse_ini_source:
    proc_enter
    sub esp, 4                    ; [ebp-4] = len
    push ebx
    push esi
    mov ebx, [ebp+8]
    push ebx
    call strlen
    add esp, 4
    mov [ebp-4], eax
    inc eax
    push eax
    call malloc
    add esp, 4
    mov esi, eax
    push dword [ebp-4]
    push ebx
    push esi
    call memcpy
    add esp, 12
    mov eax, [ebp-4]
    mov byte [esi+eax], 0

    push dword [ebp-4]
    push esi
    call cfg_parse_buffer
    add esp, 8

    push esi
    call free
    add esp, 4
    pop esi
    pop ebx
    proc_leave
    ret

_start:
    ; g_cfg_status_left/center/right doivent etre heap-allouees avant
    ; tout appel a cfg_set_string_field (qui free() la valeur courante)
    ; -- voir config.asm:cfg_load_string_defaults.
    call cfg_load_string_defaults

    ; --- parse_uint ---
    push num_123
    call parse_uint
    add esp, 4
    cmp eax, 123
    je @f
    TAP_FAIL 'parse_uint: "123" -> 123'
@@:
    push num_0
    call parse_uint
    add esp, 4
    cmp eax, 0
    je @f
    TAP_FAIL 'parse_uint: "0" -> 0'
@@:
    push num_none
    call parse_uint
    add esp, 4
    cmp eax, 0
    je @f
    TAP_FAIL 'parse_uint: aucun chiffre en tete -> 0'
@@:
    push num_trailing
    call parse_uint
    add esp, 4
    cmp eax, 42
    je @f
    TAP_FAIL 'parse_uint: "42abc" -> 42 (arret au premier non-chiffre)'
@@:
    TAP_OK 'parse_uint'

    ; --- streq ---
    push str_foo_b
    push str_foo_a
    call streq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'streq: chaines identiques -> 1'
@@:
    push str_bar
    push str_foo_a
    call streq
    add esp, 8
    cmp eax, 0
    je @f
    TAP_FAIL 'streq: chaines differentes -> 0'
@@:
    push str_foo_prefix
    push str_foo_a
    call streq
    add esp, 8
    cmp eax, 0
    je @f
    TAP_FAIL 'streq: prefixe seul -> 0 (pas egal)'
@@:
    TAP_OK 'streq'

    ; --- cfg_parse_buffer : cles reconnues, alias longs, commentaires,
    ; lignes vides, cle inconnue ignoree dans la meme section ---
    push 333
    push 222
    push 111
    call reset_cfg
    add esp, 12
    push ini_full
    call parse_ini_source
    add esp, 4
    mov eax, [g_cfg_margin_cols]
    cmp eax, 3
    je @f
    TAP_FAIL 'cfg_parse_buffer: console_margin_cols = 3'
@@:
    mov eax, [g_cfg_margin_rows]
    cmp eax, 2
    je @f
    TAP_FAIL 'cfg_parse_buffer: console_margin_rows = 2'
@@:
    mov eax, [g_cfg_word_goal]
    cmp eax, 500
    je @f
    TAP_FAIL 'cfg_parse_buffer: word_goal = 500 (cle inconnue ignoree, pas de crash)'
@@:
    TAP_OK 'cfg_parse_buffer_full'

    ; --- alias courts (margin_cols/margin_rows) ---
    push 0
    push 0
    push 0
    call reset_cfg
    add esp, 12
    push ini_short_aliases
    call parse_ini_source
    add esp, 4
    mov eax, [g_cfg_margin_cols]
    cmp eax, 7
    je @f
    TAP_FAIL 'cfg_parse_buffer: alias court margin_cols = 7'
@@:
    mov eax, [g_cfg_margin_rows]
    cmp eax, 1
    je @f
    TAP_FAIL 'cfg_parse_buffer: alias court margin_rows = 1'
@@:
    mov eax, [g_cfg_word_goal]
    cmp eax, 0
    je @f
    TAP_FAIL 'cfg_parse_buffer: word_goal absent -> reste a la sentinelle (0)'
@@:
    TAP_OK 'cfg_parse_buffer_short_aliases'

    ; --- sections/cles entierement inconnues : rien ne doit bouger ---
    push 333
    push 222
    push 111
    call reset_cfg
    add esp, 12
    push ini_unknown_sections
    call parse_ini_source
    add esp, 4
    mov eax, [g_cfg_margin_cols]
    cmp eax, 111
    je @f
    TAP_FAIL 'cfg_parse_buffer: section inconnue -> margin_cols inchange'
@@:
    mov eax, [g_cfg_margin_rows]
    cmp eax, 222
    je @f
    TAP_FAIL 'cfg_parse_buffer: section inconnue -> margin_rows inchange'
@@:
    mov eax, [g_cfg_word_goal]
    cmp eax, 333
    je @f
    TAP_FAIL 'cfg_parse_buffer: section inconnue -> word_goal inchange'
@@:
    TAP_OK 'cfg_parse_buffer_unknown_sections'

    ; --- derniere ligne SANS saut de ligne final ---
    push 0
    push 0
    push 0
    call reset_cfg
    add esp, 12
    push ini_no_trailing_nl
    call parse_ini_source
    add esp, 4
    mov eax, [g_cfg_word_goal]
    cmp eax, 42
    je @f
    TAP_FAIL 'cfg_parse_buffer: derniere ligne sans saut de ligne final -> quand meme lue'
@@:
    TAP_OK 'cfg_parse_buffer_no_trailing_newline'

    ; --- cle en double : la derniere occurrence l'emporte ---
    push 0
    push 0
    push 0
    call reset_cfg
    add esp, 12
    push ini_duplicate_key
    call parse_ini_source
    add esp, 4
    mov eax, [g_cfg_word_goal]
    cmp eax, 20
    je @f
    TAP_FAIL 'cfg_parse_buffer: cle en double -> la derniere valeur gagne'
@@:
    TAP_OK 'cfg_parse_buffer_duplicate_key'

    ; --- find_home_env ---
    mov dword [g_envp], fake_envp_with_home
    call find_home_env
    push home_value
    push eax
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'find_home_env: HOME trouve dans envp'
@@:

    mov dword [g_envp], fake_envp_without_home
    call find_home_env
    test eax, eax
    jz @f
    TAP_FAIL 'find_home_env: pas de HOME -> 0'
@@:
    TAP_OK 'find_home_env'

    ; --- build_fallback_ini_path ---
    mov dword [g_envp], fake_envp_with_home
    call build_fallback_ini_path
    cmp eax, 1
    je @f
    TAP_FAIL 'build_fallback_ini_path: HOME present -> renvoie 1'
@@:
    push expected_fallback_path
    push g_ini_fallback_path
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_fallback_ini_path: chemin construit correctement'
@@:

    mov dword [g_envp], fake_envp_without_home
    call build_fallback_ini_path
    test eax, eax
    jz @f
    TAP_FAIL 'build_fallback_ini_path: pas de HOME -> renvoie 0'
@@:
    TAP_OK 'build_fallback_ini_path'

    ; --- try_load_ini : fichier absent -> 0, sans toucher aux g_cfg_* ---
    push 333
    push 222
    push 111
    call reset_cfg
    add esp, 12
    push missing_ini_path
    call try_load_ini
    add esp, 4
    test eax, eax
    jz @f
    TAP_FAIL 'try_load_ini: fichier absent -> renvoie 0'
@@:
    mov eax, [g_cfg_margin_cols]
    cmp eax, 111
    je @f
    TAP_FAIL 'try_load_ini: fichier absent -> g_cfg_margin_cols inchange'
@@:
    TAP_OK 'try_load_ini_missing_file'

    ; --- try_load_ini : vrai fichier sur disque, bout en bout ---
    push MODE_0644
    push O_WRONLY_CREAT_TRUNC
    push tmp_ini_path
    call sys_open
    add esp, 12
    mov ebx, eax
    push ini_full_len
    push ini_full
    push ebx
    call sys_write
    add esp, 12
    push ebx
    call sys_close
    add esp, 4

    push 0
    push 0
    push 0
    call reset_cfg
    add esp, 12
    push tmp_ini_path
    call try_load_ini
    add esp, 4
    cmp eax, 1
    je @f
    TAP_FAIL 'try_load_ini: fichier present -> renvoie 1'
@@:
    mov eax, [g_cfg_margin_cols]
    cmp eax, 3
    je @f
    TAP_FAIL 'try_load_ini: margin_cols lu depuis le fichier reel'
@@:
    mov eax, [g_cfg_word_goal]
    cmp eax, 500
    je @f
    TAP_FAIL 'try_load_ini: word_goal lu depuis le fichier reel'
@@:

    push tmp_ini_path
    call sys_unlink_helper
    add esp, 4
    TAP_OK 'try_load_ini_real_file'

    ; --- status_left/status_center/status_right : lus depuis l'ini ---
    push ini_status_bar
    call parse_ini_source
    add esp, 4
    push str_status_left_expected
    push dword [g_cfg_status_left]
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'cfg_parse_buffer: status_left lu depuis l ini'
@@:
    push str_status_center_expected
    push dword [g_cfg_status_center]
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'cfg_parse_buffer: status_center lu depuis l ini'
@@:
    push str_status_right_expected
    push dword [g_cfg_status_right]
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'cfg_parse_buffer: status_right lu depuis l ini'
@@:
    TAP_OK 'cfg_parse_buffer_status_bar_keys'

    ; --- build_status_tokens : filename (brouillon puis nomme) ---
    mov dword [st_fields_buf+SF_FILENAME], 0
    push st_fields_buf
    push str_tok_filename
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    push draft_label
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_tokens: filename vide -> [draft]'
@@:
    mov dword [st_fields_buf+SF_FILENAME], test_filename_value
    push st_fields_buf
    push str_tok_filename
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    push test_filename_value
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_tokens: filename nomme'
@@:
    TAP_OK 'build_status_tokens_filename'

    ; --- dirty ---
    mov dword [st_fields_buf+SF_DIRTY], 0
    push st_fields_buf
    push str_tok_dirty
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    cmp byte [st_piece_buf], 0
    je @f
    TAP_FAIL 'build_status_tokens: dirty=0 -> rien'
@@:
    mov dword [st_fields_buf+SF_DIRTY], 1
    push st_fields_buf
    push str_tok_dirty
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    push dirty_suffix
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_tokens: dirty=1 -> " [+]"'
@@:
    TAP_OK 'build_status_tokens_dirty'

    ; --- ln/col/words/chars ---
    mov dword [st_fields_buf+SF_LINE1], 5
    mov dword [st_fields_buf+SF_TOTAL], 10
    mov dword [st_fields_buf+SF_COL1], 3
    mov dword [st_fields_buf+SF_WORDS], 7
    mov dword [st_fields_buf+SF_CHARS], 42
    mov dword [st_fields_buf+SF_GOAL], 0

    push st_fields_buf
    push str_tok_ln
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    push str_ln_expected
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_tokens: ln -> "  Ln 5/10"'
@@:
    push st_fields_buf
    push str_tok_col
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    push str_col_expected
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_tokens: col -> "  Col 3  " (pad a 3)'
@@:
    push st_fields_buf
    push str_tok_words
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    push str_words_expected
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_tokens: words -> "  7w"'
@@:
    push st_fields_buf
    push str_tok_chars
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    push str_chars_expected
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_tokens: chars -> "  42c"'
@@:
    TAP_OK 'build_status_tokens_ln_col_words_chars'

    ; --- goal : masque si 0, sinon "  words/goal" ---
    push st_fields_buf
    push str_tok_goal
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    cmp byte [st_piece_buf], 0
    je @f
    TAP_FAIL 'build_status_tokens: goal=0 -> rien'
@@:
    mov dword [st_fields_buf+SF_GOAL], 100
    push st_fields_buf
    push str_tok_goal
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    push str_goal_expected
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_tokens: goal=100, words=7 -> "  7/100"'
@@:
    TAP_OK 'build_status_tokens_goal'

    ; --- space, token inconnu recopie tel quel, workspace/sel/help_bar/timer no-op ---
    push st_fields_buf
    push str_tok_space
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    push single_space
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_tokens: space -> " "'
@@:
    push st_fields_buf
    push str_tok_pipe
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    push str_tok_pipe
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_tokens: token inconnu "|" recopie tel quel'
@@:
    push st_fields_buf
    push str_tokens_noop
    push 256
    push st_piece_buf
    call build_status_tokens
    add esp, 16
    cmp byte [st_piece_buf], 0
    je @f
    TAP_FAIL 'build_status_tokens: workspace/sel/help_bar/timer -> rien du tout'
@@:
    TAP_OK 'build_status_tokens_space_unknown_noop'

    ; --- build_status_bar : left/right seuls, puis avec centre ---
    push str_bar_right_cd
    push str_bar_empty
    push str_bar_left_ab
    push 10
    push 32
    push st_piece_buf
    call build_status_bar
    add esp, 24
    push str_bar_expected_no_center
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_bar: left+right, centre vide'
@@:

    push str_bar_right_cd
    push str_bar_center_mid
    push str_bar_left_ab
    push 11
    push 32
    push st_piece_buf
    call build_status_bar
    add esp, 24
    push str_bar_expected_with_center
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_bar: left+centre+right, largeur suffisante'
@@:

    ; centre trop large pour l'espace disponible -> ignore, juste des espaces
    push str_bar_right_cd
    push str_bar_center_mid
    push str_bar_left_ab
    push 6
    push 32
    push st_piece_buf
    call build_status_bar
    add esp, 24
    push str_bar_expected_center_too_wide
    push st_piece_buf
    call str_eq
    add esp, 8
    cmp eax, 1
    je @f
    TAP_FAIL 'build_status_bar: centre ignore si l espace restant est trop etroit'
@@:
    TAP_OK 'build_status_bar'

    syscall1 SYS_EXIT, 0

segment readable writeable
include '../src/heap_data.inc'
include '../src/term_data.inc'
include '../src/ui_data.inc'
include '../src/draw_data.inc'
include '../src/config_data.inc'

num_123        db '123', 0
num_0          db '0', 0
num_none       db 'abc', 0
num_trailing   db '42abc', 0

str_foo_a      db 'foo', 0
str_foo_b      db 'foo', 0
str_bar        db 'bar', 0
str_foo_prefix db 'foobar', 0

ini_full db '[editor]', 10, \
             'console_margin_cols = 3', 10, \
             'console_margin_rows = 2', 10, \
             10, \
             '# un commentaire', 10, \
             '% un autre commentaire', 10, \
             '[behaviour]', 10, \
             'word_goal = 500', 10, \
             'unknown_key = ignored', 10, 0
ini_full_len = $ - ini_full - 1

ini_short_aliases db '[editor]', 10, \
                      'margin_cols=7', 10, \
                      'margin_rows=1', 10, 0

ini_unknown_sections db '[timer]', 10, \
                         'duration = 25', 10, \
                         '[browser]', 10, \
                         'sort = name', 10, 0

ini_no_trailing_nl db '[behaviour]', 10, 'word_goal = 42', 0

ini_duplicate_key db '[behaviour]', 10, \
                      'word_goal = 10', 10, \
                      'word_goal = 20', 10, 0

home_prefix_env       db 'HOME=/home/testuser', 0
other_env              db 'SHELL=/bin/bash', 0
home_value              db '/home/testuser', 0
expected_fallback_path db '/home/testuser/Documents/writhdeck/writhdeck.ini', 0

fake_envp_with_home    dd other_env, home_prefix_env, 0
fake_envp_without_home dd other_env, 0

missing_ini_path db 'tests/this_config_does_not_exist.ini', 0
tmp_ini_path     db 'tests/tmp_config_test.ini', 0

; --- status_left/status_center/status_right (ini) ---
ini_status_bar db '[behaviour]', 10, \
                   'status_left = filename dirty', 10, \
                   'status_center = ln', 10, \
                   'status_right = clock help_bar', 10, 0
str_status_left_expected   db 'filename dirty', 0
str_status_center_expected db 'ln', 0
str_status_right_expected  db 'clock help_bar', 0

; --- build_status_tokens ---
test_filename_value db 'myfile.txt', 0
str_ln_expected      db '  Ln ', '5', '/', '10', 0
str_col_expected      db '  Col ', '3', '  ', 0
str_words_expected     db '  ', '7', 'w', 0
str_chars_expected      db '  ', '42', 'c', 0
str_goal_expected        db '  ', '7', '/', '100', 0
str_tok_pipe               db '|', 0
str_tokens_noop             db 'workspace sel help_bar timer', 0

; --- build_status_bar ---
str_bar_left_ab   db 'AB', 0
str_bar_center_mid db 'MID', 0
str_bar_right_cd    db 'CD', 0
str_bar_empty        db 0
str_bar_expected_no_center       db 'AB      CD', 0
str_bar_expected_with_center     db 'AB  MID  CD', 0
str_bar_expected_center_too_wide db 'AB  CD', 0
