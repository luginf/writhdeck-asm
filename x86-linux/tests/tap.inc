; tap.inc -- mini harnais de tests, miroir volontaire de tests/tap.h
; cote C : le premier echec affiche un message et arrete tout de suite
; (exit 1), pas de compteur global ni de protocole TAP complet.
;
;   TAP_OK 'message'   -- affiche "ok: message\n"
;   TAP_FAIL 'message' -- affiche "ECHEC: message\n" puis exit(1)
;
; Le message est encode inline dans le flux de code (avec un saut par
; dessus les octets de la chaine) : pas besoin de strlen ni de segment
; de donnees separe pour ca.

macro TAP_OK msg
{
    local .str, .after
    jmp .after
    .str db 'ok: ', msg, 10
    .after:
    push .after - .str
    push .str
    call tap__write_stdout
    add esp, 8
}

macro TAP_FAIL msg
{
    local .str, .after
    jmp .after
    .str db 'ECHEC: ', msg, 10
    .after:
    push .after - .str
    push .str
    call tap__write_stdout
    add esp, 8
    syscall1 SYS_EXIT, 1
}

; tap__write_stdout(ptr, len) -- cdecl
tap__write_stdout:
    proc_enter
    push ebx
    mov ecx, [ebp+8]
    mov edx, [ebp+12]
    mov ebx, 1
    mov eax, SYS_WRITE
    int 0x80
    pop ebx
    proc_leave
    ret
