; macros.inc -- conventions communes a tout le projet.
;
; Convention d'appel : cdecl minimal. Arguments empiles de droite a
; gauche avant "call", l'appelant nettoie la pile ensuite (add esp, N).
; Retour entier/pointeur dans eax. ebx, esi, edi, ebp preserves par
; l'appelee (callee-saved) ; eax, ecx, edx libres (caller-saved).
;
; Acces aux arguments depuis le corps d'une procedure, apres proc_enter :
;   [ebp+8]  = premier argument
;   [ebp+12] = deuxieme argument
;   [ebp+16] = troisieme argument
;   ... (chaque argument occupe 4 octets, pile 32 bits)
; Pas de macro "arg"/"local" nommee ici par choix : ce projet reste de
; l'assembleur ecrit a la main, la macro ne fait que factoriser le
; prologue/epilogue repetitif, pas les acces eux-memes.

macro proc_enter
{
    push ebp
    mov ebp, esp
}

; A utiliser juste avant "ret" (pas de nettoyage de pile ici : cdecl,
; c'est l'appelant qui nettoie ses propres arguments apres le "call").
macro proc_leave
{
    mov esp, ebp
    pop ebp
}
