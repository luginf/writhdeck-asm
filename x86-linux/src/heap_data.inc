; heap_data.inc -- variables globales de heap.asm. A inclure une seule
; fois par binaire final, dans un segment "readable writeable".
heap_inited db 0
heap_start  dd 0
heap_end    dd 0
