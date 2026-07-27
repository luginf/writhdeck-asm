; ui_data.inc -- stockage persistant de ui_ansi.asm. A inclure une
; seule fois par binaire final, dans un segment "readable writeable".
frame_buf  dd 0
frame_len  dd 0
frame_cap  dd 0
rows_cache dd 24
cols_cache dd 80
