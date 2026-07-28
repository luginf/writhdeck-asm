; sys.inc -- appels systeme Linux i386 utilises par ce projet.
;
; ABI syscall i386 : eax = numero, arguments dans ebx, ecx, edx, esi, edi,
; ebp (dans cet ordre), int 0x80, retour dans eax (valeur negative dans
; -4095..-1 = -errno). Voir arch/x86/entry/syscalls/syscall_32.tbl du noyau.

SYS_EXIT    = 1
SYS_READ    = 3
SYS_WRITE   = 4
SYS_OPEN    = 5
SYS_CLOSE   = 6
SYS_UNLINK  = 10
SYS_TIME    = 13
SYS_BRK     = 45

O_RDONLY    = 0
O_WRONLY    = 1
O_CREAT     = 0x40
O_TRUNC     = 0x200

; syscallN num, arg1, ..., argN -- charge les arguments puis declenche
; l'interruption. Les arguments sont deplaces dans l'ordre a1,a2,a3,... :
; ne JAMAIS passer un registre qu'un argument precedent vient d'ecraser
; (ex. ne pas passer "ebx" comme a2 alors que a1 va dans ebx) -- charger
; d'abord les valeurs a risque dans esi/edi/eax au site d'appel si besoin.
macro syscall0 num
{
    mov eax, num
    int 0x80
}

macro syscall1 num, a1
{
    mov ebx, a1
    mov eax, num
    int 0x80
}

macro syscall2 num, a1, a2
{
    mov ebx, a1
    mov ecx, a2
    mov eax, num
    int 0x80
}

macro syscall3 num, a1, a2, a3
{
    mov ebx, a1
    mov ecx, a2
    mov edx, a3
    mov eax, num
    int 0x80
}
