; test_draw.asm -- exercice draw_editor() directement (sans terminal
; reel : ui_clear_line/ui_put_str/ui_refresh ne font que des read/write
; sur les fd standards, qui marchent tout aussi bien vers un pipe/fichier
; -- seul ui_init/term_enable_raw exige un vrai tty). Sert a isoler un
; crash eventuel sans avoir a passer par un pty.
format ELF executable
entry _start

include '../src/sys.inc'
include '../src/macros.inc'

segment readable executable

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

_start:
    ; g_cfg_status_left/center/right doivent pointer vers une valeur
    ; heap-allouee (jamais 0) avant le premier appel a build_status_line
    ; -- voir cfg_load_string_defaults (config.asm). Ce test n'appelle
    ; pas cfg_init (pas d'envp ici), donc l'appel direct est necessaire.
    call cfg_load_string_defaults

    call editor_new
    mov esi, eax

    push 'h'
    push esi
    call editor_insert_codepoint
    add esp, 8
    push 'i'
    push esi
    call editor_insert_codepoint
    add esp, 8

    push 24
    push 80
    push esi
    call draw_editor
    add esp, 12

    syscall1 SYS_EXIT, 0

segment readable writeable
include '../src/heap_data.inc'
include '../src/term_data.inc'
include '../src/ui_data.inc'
include '../src/draw_data.inc'
include '../src/config_data.inc'
