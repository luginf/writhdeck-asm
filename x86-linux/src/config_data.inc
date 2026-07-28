; config_data.inc -- donnees de config.asm. A inclure une seule fois
; par binaire final, dans un segment "readable writeable" (g_cfg_*
; sont mutees a l'execution -- les garder dans le segment "readable
; executable" aurait ete une ecriture dans une page non inscriptible,
; piege reel evite ici, pas juste theorique, voir la meme discipline
; que draw_data.inc/heap_data.inc/term_data.inc/ui_data.inc).
home_prefix           db 'HOME='
ini_name_short        db 'writhd.ini', 0
ini_fallback_suffix   db '/Documents/writhdeck/writhdeck.ini', 0
section_editor        db 'editor', 0
section_behaviour     db 'behaviour', 0
key_margin_cols_a     db 'console_margin_cols', 0
key_margin_cols_b     db 'margin_cols', 0
key_margin_rows_a     db 'console_margin_rows', 0
key_margin_rows_b     db 'margin_rows', 0
key_word_goal         db 'word_goal', 0
key_status_left       db 'status_left', 0
key_status_center     db 'status_center', 0
key_status_right      db 'status_right', 0

; memes defauts que cfg_load_defaults cote C (config.c) -- voir
; build_status_tokens (draw.asm) pour la signification de chaque
; token.
default_status_left   db 'workspace filename dirty sel ln col words chars', 0
default_status_center db 0
default_status_right  db 'help_bar clock', 0

g_envp             dd 0
g_cfg_margin_cols   dd 6    ; memes defauts que cfg_load_defaults cote C
g_cfg_margin_rows   dd 4
g_cfg_word_goal     dd 0    ; 0 = desactive/masque dans la barre de statut
; g_cfg_status_left/center/right : toujours des pointeurs heap-allouee
; (strdup), jamais directement vers default_status_* -- voir
; cfg_load_string_defaults/cfg_set_string_field (config.asm). Valent 0
; tant que cfg_load_string_defaults n'a pas encore tourne (tout code
; qui lit ces champs, y compris les tests, doit l'appeler d'abord).
g_cfg_status_left   dd 0
g_cfg_status_center dd 0
g_cfg_status_right  dd 0
g_cfg_section       rb SECTION_BUF_CAP
g_ini_fallback_path rb 512
