; draw_data.inc -- donnees de draw.asm. A inclure une seule fois par
; binaire final, dans un segment "readable writeable".
draft_label db '[draft]', 0
slash_label db '/', 0

; --- build_status_tokens : noms de tokens reconnus + libelles ---
str_tok_filename  db 'filename', 0
str_tok_dirty     db 'dirty', 0
str_tok_ln        db 'ln', 0
str_tok_col       db 'col', 0
str_tok_words     db 'words', 0
str_tok_chars     db 'chars', 0
str_tok_goal      db 'goal', 0
str_tok_clock     db 'clock', 0
str_tok_space     db 'space', 0
str_tok_timer     db 'timer', 0
str_tok_workspace db 'workspace', 0
str_tok_sel       db 'sel', 0
str_tok_help_bar  db 'help_bar', 0

dirty_suffix  db ' [+]', 0
ln_prefix     db '  Ln ', 0
col_prefix    db '  Col ', 0
sb_two_spaces db '  ', 0
single_space  db ' ', 0

; tampons de travail statiques (programme mono-thread, non reentrant --
; meme convention que toc_line_buf/prompt_render_buf dans main.asm).
st_piece_buf   rb 256
st_left_buf    rb 256
st_center_buf  rb 256
st_right_buf   rb 256
st_fields_buf  rb SF_SIZE

STATUS_BUF_CAP = 512
status_buf rb STATUS_BUF_CAP
