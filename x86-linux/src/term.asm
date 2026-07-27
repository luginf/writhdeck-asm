; term.asm -- mode raw du terminal (termios via ioctl), taille de la
; fenetre (TIOCGWINSZ), et attente courte sur stdin (poll) utilisee pour
; distinguer une touche Echap isolee d'une sequence ANSI (voir
; ui_ansi.asm:ui_read_event). Pas de gestion de SIGWINCH (simplification
; assumee : la taille du terminal est de toute facon relue a chaque
; frame par la boucle principale -- voir main.asm -- donc un
; redimensionnement est pris en compte des la frappe suivante, meme sans
; interrompre un read() bloquant). Depend de heap.asm (aucun, pur
; syscalls) -- attendu inclus alors que le segment "readable executable"
; est deja actif.

SYS_IOCTL = 54
SYS_POLL  = 168

TCGETS      = 0x5401
TCSETSF     = 0x5404
TIOCGWINSZ  = 0x5413

; Disposition struct termios (i386 Linux, asm-generic/termbits.h) :
TERMIOS_IFLAG = 0
TERMIOS_OFLAG = 4
TERMIOS_CFLAG = 8
TERMIOS_LFLAG = 12
TERMIOS_LINE  = 16
TERMIOS_CC    = 17
TERMIOS_SIZE  = 36
VTIME_IDX = 5
VMIN_IDX  = 6

; Masques (valeurs octales usuelles de termbits.h, converties en hexa) :
; ICRNL|IXON|BRKINT|INPCK|ISTRIP = 0400|02000|02|020|040 (octal) = 0x532
IFLAG_RAW_MASK = 0x532
; OPOST = 01 (octal) = 0x1
OFLAG_RAW_MASK = 0x1
; ECHO|ICANON|ISIG|IEXTEN = 010|02|01|0100000 (octal) = 0x800B
LFLAG_RAW_MASK = 0x800B

; dword term_ioctl(dword fd, dword request, void* argp) -- cdecl.
term_ioctl:
    proc_enter
    push ebx
    mov ebx, [ebp+8]
    mov ecx, [ebp+12]
    mov edx, [ebp+16]
    mov eax, SYS_IOCTL
    int 0x80
    pop ebx
    proc_leave
    ret

; dword term_poll(void* fds, dword nfds, dword timeout_ms) -- cdecl.
term_poll:
    proc_enter
    push ebx
    mov ebx, [ebp+8]
    mov ecx, [ebp+12]
    mov edx, [ebp+16]
    mov eax, SYS_POLL
    int 0x80
    pop ebx
    proc_leave
    ret

; int term_get_winsize(dword* rows_out, dword* cols_out) -- cdecl, lit
; la taille du terminal via TIOCGWINSZ sur le fd de sortie standard (1).
; Renvoie 0 si succes, -1 sinon (rows_out/cols_out inchanges).
term_get_winsize:
    proc_enter
    sub esp, 8                  ; struct winsize locale (8 octets)
    lea eax, [ebp-8]
    push eax
    push TIOCGWINSZ
    push 1
    call term_ioctl
    add esp, 12
    test eax, eax
    jnz .fail
    movzx ecx, word [ebp-8]        ; ws_row
    mov edx, [ebp+8]
    mov [edx], ecx
    movzx ecx, word [ebp-6]          ; ws_col
    mov edx, [ebp+12]
    mov [edx], ecx
    xor eax, eax
    jmp .ret
.fail:
    mov eax, -1
.ret:
    proc_leave
    ret

; int term_poll_stdin(dword timeout_ms) -- cdecl. Renvoie 1 si un octet
; est disponible sur stdin avant expiration, 0 sinon.
term_poll_stdin:
    proc_enter
    sub esp, 8                   ; struct pollfd locale : {fd,events,revents}
    mov dword [ebp-8], 0
    mov word [ebp-4], 1              ; POLLIN
    mov word [ebp-2], 0
    lea eax, [ebp-8]
    push dword [ebp+8]
    push 1
    push eax
    call term_poll
    add esp, 12
    cmp eax, 0
    jg .ready
    xor eax, eax
    jmp .ret
.ready:
    mov eax, 1
.ret:
    proc_leave
    ret

; int term_enable_raw(void) -- cdecl. Sauvegarde le termios courant
; (orig_termios) et bascule stdin en raw (pas d'echo/canonique/signaux,
; VMIN=1/VTIME=0 -- lecture bloquante octet par octet). Renvoie 0/-1.
term_enable_raw:
    proc_enter
    push orig_termios
    push TCGETS
    push 0
    call term_ioctl
    add esp, 12
    test eax, eax
    jz .get_ok
    mov eax, -1
    jmp .ret
.get_ok:
    push 36
    push orig_termios
    push raw_termios
    call memcpy
    add esp, 12

    mov eax, dword [raw_termios+TERMIOS_IFLAG]
    and eax, not IFLAG_RAW_MASK
    mov dword [raw_termios+TERMIOS_IFLAG], eax

    mov eax, dword [raw_termios+TERMIOS_OFLAG]
    and eax, not OFLAG_RAW_MASK
    mov dword [raw_termios+TERMIOS_OFLAG], eax

    mov eax, dword [raw_termios+TERMIOS_LFLAG]
    and eax, not LFLAG_RAW_MASK
    mov dword [raw_termios+TERMIOS_LFLAG], eax

    mov byte [raw_termios+TERMIOS_CC+VTIME_IDX], 0
    mov byte [raw_termios+TERMIOS_CC+VMIN_IDX], 1

    push raw_termios
    push TCSETSF
    push 0
    call term_ioctl
    add esp, 12
    test eax, eax
    jz .set_ok
    mov eax, -1
    jmp .ret
.set_ok:
    xor eax, eax
.ret:
    proc_leave
    ret

; void term_disable_raw(void) -- cdecl. Restaure le termios d'origine.
term_disable_raw:
    proc_enter
    push orig_termios
    push TCSETSF
    push 0
    call term_ioctl
    add esp, 12
    proc_leave
    ret

; dword term_read_byte(void) -- cdecl. Lecture bloquante d'un octet sur
; stdin. Renvoie l'octet (0..255) ou -1 (EOF/erreur).
term_read_byte:
    proc_enter
    sub esp, 4
    lea eax, [ebp-4]
    push 1
    push eax
    push 0
    call sys_read
    add esp, 12
    cmp eax, 1
    je .got
    mov eax, -1
    jmp .ret
.got:
    movzx eax, byte [ebp-4]
.ret:
    proc_leave
    ret

; dword term_read_byte_timeout(dword timeout_ms) -- cdecl. Comme
; term_read_byte, mais renvoie -1 si rien n'arrive dans timeout_ms.
term_read_byte_timeout:
    proc_enter
    push dword [ebp+8]
    call term_poll_stdin
    add esp, 4
    test eax, eax
    jnz .have_data
    mov eax, -1
    jmp .ret
.have_data:
    call term_read_byte
.ret:
    proc_leave
    ret
