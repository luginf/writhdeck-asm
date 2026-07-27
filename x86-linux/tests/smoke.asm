; smoke.asm -- verifie la chaine fasm -> ELF32 -> execution sur cette
; machine avant d'investir dans le reste (voir plan, etape 1).
format ELF executable
entry _start

include '../src/sys.inc'

segment readable executable

_start:
    syscall3 SYS_WRITE, 1, msg, msg_len
    syscall1 SYS_EXIT, 0

segment readable writeable

msg db 'writhdeck-asm: smoke test ok', 10
msg_len = $ - msg
