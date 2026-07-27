; draw_data.inc -- donnees de draw.asm. A inclure une seule fois par
; binaire final, dans un segment "readable writeable".
draft_label db '[draft]', 0
sep1_label  db ' | line ', 0
slash_label db '/', 0
col_label   db ' col ', 0
star_label  db ' *', 0

status_buf rb 512
