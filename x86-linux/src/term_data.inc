; term_data.inc -- stockage persistant de term.asm. A inclure une seule
; fois par binaire final, dans un segment "readable writeable".
orig_termios rb 36
raw_termios  rb 36
