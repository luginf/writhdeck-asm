; buffer.asm -- portage direct de writhdeck-c/src/buffer.c : tableau
; dynamique de lignes (chaines octets nul-terminees, UTF-8), avec les
; operations d'edition caractere par caractere. Depend de heap.asm
; (malloc/free/realloc), strutil.asm (memcpy/memmove/strlen/strdup) et
; utf8.asm (byte_offset/char_index/strlen). Attendu inclus alors que le
; segment "readable executable" est deja actif.
;
; Disposition de buffer_t (12 octets) :
;   +0  lines     (dword*)  -- tableau de pointeurs vers chaine C
;   +4  count     (dword)
;   +8  capacity  (dword)

BUF_LINES = 0
BUF_COUNT = 4
BUF_CAP   = 8
BUF_SIZE  = 12

O_WRONLY_CREAT_TRUNC = O_WRONLY or O_CREAT or O_TRUNC
MODE_0644 = 0x1A4

; --- petites enveloppes syscalls (I/O fichier), non exposees ailleurs ---

; dword sys_open(const char* path, dword flags, dword mode) -- cdecl
sys_open:
    proc_enter
    push ebx
    mov ebx, [ebp+8]
    mov ecx, [ebp+12]
    mov edx, [ebp+16]
    mov eax, SYS_OPEN
    int 0x80
    pop ebx
    proc_leave
    ret

; void sys_close(dword fd) -- cdecl
sys_close:
    proc_enter
    push ebx
    mov ebx, [ebp+8]
    mov eax, SYS_CLOSE
    int 0x80
    pop ebx
    proc_leave
    ret

; dword sys_read(dword fd, void* buf, dword len) -- cdecl
sys_read:
    proc_enter
    push ebx
    mov ebx, [ebp+8]
    mov ecx, [ebp+12]
    mov edx, [ebp+16]
    mov eax, SYS_READ
    int 0x80
    pop ebx
    proc_leave
    ret

; dword sys_write(dword fd, const void* buf, dword len) -- cdecl
sys_write:
    proc_enter
    push ebx
    mov ebx, [ebp+8]
    mov ecx, [ebp+12]
    mov edx, [ebp+16]
    mov eax, SYS_WRITE
    int 0x80
    pop ebx
    proc_leave
    ret

; --- aides internes sur buffer_t (non declarees dans buffer.h, mais
; utilisees par plusieurs fonctions publiques) ---

; void buf_ensure_capacity(buffer_t* buf, dword need) -- cdecl.
; INITIAL_CAP=16, doublement jusqu'a >= need (peut sauter plusieurs
; doublements d'un coup), realloc du tableau de pointeurs.
buf_ensure_capacity:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]
    mov ebx, [esi+BUF_CAP]
    cmp ebx, edi
    jae .done
    test ebx, ebx
    jnz .grow
    mov ebx, 16
    jmp .checkloop
.grow:
    shl ebx, 1
.checkloop:
    cmp ebx, edi
    jae .apply
    jmp .grow
.apply:
    mov eax, ebx
    shl eax, 2
    push eax
    push dword [esi+BUF_LINES]
    call realloc
    add esp, 8
    mov [esi+BUF_LINES], eax
    mov [esi+BUF_CAP], ebx
.done:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void buf_insert_line_at(buffer_t* buf, dword idx, char* text) -- cdecl.
buf_insert_line_at:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]
    mov eax, [esi+BUF_COUNT]
    inc eax
    push eax
    push esi
    call buf_ensure_capacity
    add esp, 8
    mov ebx, [esi+BUF_LINES]
    mov eax, [esi+BUF_COUNT]
    sub eax, edi
    shl eax, 2
    push eax
    lea ecx, [ebx+edi*4]
    push ecx
    lea ecx, [ebx+edi*4+4]
    push ecx
    call memmove
    add esp, 12
    mov ebx, [esi+BUF_LINES]
    mov ecx, [ebp+16]
    mov [ebx+edi*4], ecx
    inc dword [esi+BUF_COUNT]
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void buf_remove_line_at(buffer_t* buf, dword idx) -- cdecl. Libere
; lines[idx] et compacte le tableau.
buf_remove_line_at:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]
    mov ebx, [esi+BUF_LINES]
    push dword [ebx+edi*4]
    call free
    add esp, 4
    mov ebx, [esi+BUF_LINES]
    mov eax, [esi+BUF_COUNT]
    sub eax, edi
    dec eax
    shl eax, 2
    push eax
    lea ecx, [ebx+edi*4+4]
    push ecx
    lea ecx, [ebx+edi*4]
    push ecx
    call memmove
    add esp, 12
    dec dword [esi+BUF_COUNT]
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void buf_clear_lines(buffer_t* buf) -- cdecl. Libere chaque ligne,
; remet count a 0 (conserve le tableau/capacity).
buf_clear_lines:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov ebx, [esi+BUF_COUNT]
    xor edi, edi
.loop:
    cmp edi, ebx
    jge .after
    mov ecx, [esi+BUF_LINES]
    push dword [ecx+edi*4]
    call free
    add esp, 4
    inc edi
    jmp .loop
.after:
    mov dword [esi+BUF_COUNT], 0
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void buf_reset_to_blank(buffer_t* buf) -- cdecl. Vide puis remet une
; seule ligne vide (meme etat qu'un buffer_new()).
buf_reset_to_blank:
    proc_enter
    push esi
    mov esi, [ebp+8]
    push esi
    call buf_clear_lines
    add esp, 4
    push 1
    push esi
    call buf_ensure_capacity
    add esp, 8
    push 1
    call malloc
    add esp, 4
    mov byte [eax], 0
    mov ecx, [esi+BUF_LINES]
    mov [ecx], eax
    mov dword [esi+BUF_COUNT], 1
    pop esi
    proc_leave
    ret

; char* buf_read_whole_file(dword fd, dword* out_len) -- cdecl. Lit fd
; jusqu'a EOF/erreur dans un buffer malloc'e qui double de taille au
; besoin (depart 4096). *out_len recoit la taille lue.
buf_read_whole_file:
    proc_enter
    sub esp, 8                  ; [ebp-4]=cap, [ebp-8]=len
    push ebx
    push esi
    push edi
    mov edi, [ebp+8]              ; fd
    mov dword [ebp-4], 4096
    mov dword [ebp-8], 0
    push 4096
    call malloc
    add esp, 4
    mov esi, eax                   ; esi = data
.loop:
    mov eax, [ebp-4]
    sub eax, [ebp-8]
    push eax
    mov eax, esi
    add eax, [ebp-8]
    push eax
    push edi
    call sys_read
    add esp, 12
    cmp eax, 0
    jle .done
    add [ebp-8], eax
    mov ecx, [ebp-8]
    cmp ecx, [ebp-4]
    jne .loop
    mov eax, [ebp-4]
    shl eax, 1
    mov [ebp-4], eax
    push eax
    push esi
    call realloc
    add esp, 8
    mov esi, eax
    jmp .loop
.done:
    mov ebx, [ebp+12]
    mov eax, [ebp-8]
    mov [ebx], eax
    mov eax, esi
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; --- API publique (buffer.h) ---

; buffer_t* buffer_new(void) -- cdecl.
buffer_new:
    proc_enter
    push esi
    push BUF_SIZE
    call malloc
    add esp, 4
    mov esi, eax
    mov dword [esi+BUF_LINES], 0
    mov dword [esi+BUF_COUNT], 0
    mov dword [esi+BUF_CAP], 0
    push esi
    call buf_reset_to_blank
    add esp, 4
    mov eax, esi
    pop esi
    proc_leave
    ret

; void buffer_free(buffer_t* buf) -- cdecl.
buffer_free:
    proc_enter
    push esi
    mov esi, [ebp+8]
    test esi, esi
    jz .done
    push esi
    call buf_clear_lines
    add esp, 4
    push dword [esi+BUF_LINES]
    call free
    add esp, 4
    push esi
    call free
    add esp, 4
.done:
    pop esi
    proc_leave
    ret

; buffer_t* buffer_clone(const buffer_t* buf) -- cdecl.
buffer_clone:
    proc_enter
    sub esp, 4                    ; [ebp-4] = i
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    push BUF_SIZE
    call malloc
    add esp, 4
    mov edi, eax
    mov dword [edi+BUF_LINES], 0
    mov dword [edi+BUF_COUNT], 0
    mov dword [edi+BUF_CAP], 0
    mov ebx, [esi+BUF_COUNT]
    mov eax, ebx
    test eax, eax
    jnz .capn_ok
    mov eax, 1
.capn_ok:
    push eax
    push edi
    call buf_ensure_capacity
    add esp, 8
    mov dword [ebp-4], 0
.loop:
    mov eax, [ebp-4]
    cmp eax, ebx
    jge .after
    mov ecx, [esi+BUF_LINES]
    push dword [ecx+eax*4]
    call strdup
    add esp, 4
    mov ecx, [edi+BUF_LINES]
    mov edx, [ebp-4]
    mov [ecx+edx*4], eax
    inc dword [ebp-4]
    jmp .loop
.after:
    mov [edi+BUF_COUNT], ebx
    mov eax, edi
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; int buffer_load_file(buffer_t* buf, const char* path) -- cdecl.
buffer_load_file:
    proc_enter
    sub esp, 20                  ; -4 data, -8 len, -12 i, -16 any, -20 j
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    push 0
    push O_RDONLY
    push dword [ebp+12]
    call sys_open
    add esp, 12
    mov edi, eax
    cmp edi, 0
    jge .open_ok
    push esi
    call buf_reset_to_blank
    add esp, 4
    mov eax, -1
    jmp .ret
.open_ok:
    lea eax, [ebp-8]
    push eax
    push edi
    call buf_read_whole_file
    add esp, 8
    mov [ebp-4], eax
    push edi
    call sys_close
    add esp, 4
    push esi
    call buf_clear_lines
    add esp, 4
    mov dword [ebp-12], 0
    mov dword [ebp-16], 0
.split_loop:
    mov eax, [ebp-12]
    cmp eax, [ebp-8]
    jge .split_done
    mov ecx, eax
.find_nl:
    cmp ecx, [ebp-8]
    jge .found_j
    mov edx, [ebp-4]
    cmp byte [edx+ecx], 10
    je .found_j
    inc ecx
    jmp .find_nl
.found_j:
    mov [ebp-20], ecx
    mov ebx, ecx
    sub ebx, eax                  ; ebx = content_len = j-i
    test ebx, ebx
    jz .no_strip
    mov edx, [ebp-4]
    add edx, eax
    add edx, ebx
    dec edx
    cmp byte [edx], 13
    jne .no_strip
    dec ebx
.no_strip:
    lea eax, [ebx+1]
    push eax
    call malloc
    add esp, 4
    mov edi, eax                    ; edi = nouvelle ligne (fd n'est plus utile)
    push ebx
    mov eax, [ebp-4]
    add eax, [ebp-12]
    push eax
    push edi
    call memcpy
    add esp, 12
    mov byte [edi+ebx], 0
    push edi
    push dword [esi+BUF_COUNT]
    push esi
    call buf_insert_line_at
    add esp, 12
    mov dword [ebp-16], 1
    mov eax, [ebp-20]
    inc eax
    mov [ebp-12], eax
    jmp .split_loop
.split_done:
    cmp dword [ebp-16], 0
    jne .have_lines
    push esi
    call buf_reset_to_blank
    add esp, 4
.have_lines:
    push dword [ebp-4]
    call free
    add esp, 4
    xor eax, eax
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; int buffer_save_file(const buffer_t* buf, const char* path) -- cdecl.
buffer_save_file:
    proc_enter
    sub esp, 8                    ; -4 i, -8 octet '\n'
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    push MODE_0644
    push O_WRONLY_CREAT_TRUNC
    push dword [ebp+12]
    call sys_open
    add esp, 12
    mov edi, eax
    cmp edi, 0
    jge .open_ok
    mov eax, -1
    jmp .ret
.open_ok:
    mov ebx, [esi+BUF_COUNT]
    mov dword [ebp-4], 0
    mov byte [ebp-8], 10
.loop:
    mov eax, [ebp-4]
    cmp eax, ebx
    jge .after
    mov ecx, [esi+BUF_LINES]
    mov edx, [ecx+eax*4]
    push edx
    call strlen
    add esp, 4
    push eax
    mov ecx, [esi+BUF_LINES]
    mov edx, [ebp-4]
    mov edx, [ecx+edx*4]
    push edx
    push edi
    call sys_write
    add esp, 12
    lea eax, [ebp-8]
    push 1
    push eax
    push edi
    call sys_write
    add esp, 12
    inc dword [ebp-4]
    jmp .loop
.after:
    push edi
    call sys_close
    add esp, 4
    xor eax, eax
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; int buffer_line_char_count(const buffer_t* buf, dword line) -- cdecl.
buffer_line_char_count:
    proc_enter
    mov eax, [ebp+12]
    test eax, eax
    jl .zero
    mov ecx, [ebp+8]
    cmp eax, [ecx+BUF_COUNT]
    jge .zero
    mov ecx, [ecx+BUF_LINES]
    push dword [ecx+eax*4]
    call utf8_strlen
    add esp, 4
    jmp .ret
.zero:
    xor eax, eax
.ret:
    proc_leave
    ret

; void buffer_insert_char(buffer_t* buf, dword line, dword col, dword cp)
buffer_insert_char:
    proc_enter
    sub esp, 16                    ; -4 byte_off, -8 old_len, -12 encbuf(4), -16 new_ptr
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov eax, [ebp+12]
    test eax, eax
    jl .done
    cmp eax, [esi+BUF_COUNT]
    jge .done
    mov ecx, [esi+BUF_LINES]
    mov edi, [ecx+eax*4]
    push dword [ebp+16]
    push edi
    call utf8_byte_offset
    add esp, 8
    mov [ebp-4], eax
    push edi
    call strlen
    add esp, 4
    mov [ebp-8], eax
    lea eax, [ebp-12]
    push eax
    push dword [ebp+20]
    call utf8_encode
    add esp, 8
    mov ebx, eax                    ; ebx = enc_len
    mov ecx, [ebp-8]
    add ecx, ebx
    lea eax, [ecx+1]
    push eax
    call malloc
    add esp, 4
    mov [ebp-16], eax
    push dword [ebp-4]
    push edi
    push dword [ebp-16]
    call memcpy
    add esp, 12
    mov eax, [ebp-16]
    add eax, [ebp-4]
    push ebx
    lea ecx, [ebp-12]
    push ecx
    push eax
    call memcpy
    add esp, 12
    mov ecx, [ebp-8]
    sub ecx, [ebp-4]
    inc ecx
    push ecx
    mov eax, edi
    add eax, [ebp-4]
    push eax
    mov eax, [ebp-16]
    add eax, [ebp-4]
    add eax, ebx
    push eax
    call memcpy
    add esp, 12
    push edi
    call free
    add esp, 4
    mov ecx, [esi+BUF_LINES]
    mov eax, [ebp+12]
    mov edx, [ebp-16]
    mov [ecx+eax*4], edx
.done:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void buffer_delete_char(buffer_t* buf, dword line, dword col)
buffer_delete_char:
    proc_enter
    sub esp, 4                     ; [ebp-4] = end (byte offset)
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov eax, [ebp+12]
    test eax, eax
    jl .done
    cmp eax, [esi+BUF_COUNT]
    jge .done
    mov ecx, [esi+BUF_LINES]
    mov edi, [ecx+eax*4]
    push edi
    call utf8_strlen
    add esp, 4
    mov ebx, eax
    mov eax, [ebp+16]
    cmp eax, ebx
    jl .normal_delete

    ; col >= len : fusion avec la ligne suivante si elle existe
    mov eax, [ebp+12]
    inc eax
    cmp eax, [esi+BUF_COUNT]
    jge .done

    mov ecx, [esi+BUF_LINES]
    mov edx, [ebp+12]
    mov edx, [ecx+edx*4]
    push edx
    call strlen
    add esp, 4
    mov ebx, eax                     ; ebx = cur_len

    mov ecx, [esi+BUF_LINES]
    mov eax, [ebp+12]
    inc eax
    mov edx, [ecx+eax*4]
    push edx
    call strlen
    add esp, 4
    add eax, ebx
    inc eax
    push eax
    call malloc
    add esp, 4
    mov edi, eax                      ; edi = ligne fusionnee

    mov ecx, [esi+BUF_LINES]
    mov edx, [ebp+12]
    mov edx, [ecx+edx*4]
    push ebx
    push edx
    push edi
    call memcpy
    add esp, 12

    mov ecx, [esi+BUF_LINES]
    mov edx, [ebp+12]
    inc edx
    mov edx, [ecx+edx*4]
    push edx
    call strlen
    add esp, 4
    inc eax
    push eax
    mov ecx, [esi+BUF_LINES]
    mov edx, [ebp+12]
    inc edx
    mov edx, [ecx+edx*4]
    push edx
    mov eax, edi
    add eax, ebx
    push eax
    call memcpy
    add esp, 12

    mov ecx, [esi+BUF_LINES]
    mov eax, [ebp+12]
    push dword [ecx+eax*4]
    call free
    add esp, 4
    mov ecx, [esi+BUF_LINES]
    mov eax, [ebp+12]
    mov [ecx+eax*4], edi

    mov eax, [ebp+12]
    inc eax
    push eax
    push esi
    call buf_remove_line_at
    add esp, 8
    jmp .done

.normal_delete:
    mov eax, [ebp+16]
    push eax
    push edi
    call utf8_byte_offset
    add esp, 8
    mov ebx, eax                       ; start
    mov eax, [ebp+16]
    inc eax
    push eax
    push edi
    call utf8_byte_offset
    add esp, 8
    mov [ebp-4], eax                     ; end
    push edi
    call strlen
    add esp, 4
    mov ecx, eax
    sub ecx, [ebp-4]
    inc ecx
    push ecx
    mov eax, edi
    add eax, [ebp-4]
    push eax
    mov eax, edi
    add eax, ebx
    push eax
    call memmove
    add esp, 12
.done:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void buffer_backspace(buffer_t* buf, dword line, dword col,
;                        dword* out_line, dword* out_col)
buffer_backspace:
    proc_enter
    sub esp, 12                   ; -4 prev_char_len, -8 prev_byte_len, -12 merged
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov eax, [ebp+16]
    test eax, eax
    jnz .col_gt0

    mov eax, [ebp+12]
    test eax, eax
    jz .noop

    mov ebx, eax                    ; ebx = line courante
    dec eax
    mov ecx, [esi+BUF_LINES]
    mov edi, [ecx+eax*4]              ; edi = ligne precedente
    push edi
    call utf8_strlen
    add esp, 4
    mov [ebp-4], eax                    ; prev_char_len
    push edi
    call strlen
    add esp, 4
    mov [ebp-8], eax                     ; prev_byte_len

    mov ecx, [esi+BUF_LINES]
    mov edx, [ecx+ebx*4]
    push edx
    call strlen
    add esp, 4
    add eax, [ebp-8]
    inc eax
    push eax
    call malloc
    add esp, 4
    mov [ebp-12], eax                      ; merged ptr

    push dword [ebp-8]
    push edi
    push dword [ebp-12]
    call memcpy
    add esp, 12

    mov ecx, [esi+BUF_LINES]
    mov edx, [ecx+ebx*4]
    push edx
    call strlen
    add esp, 4
    inc eax
    push eax
    mov ecx, [esi+BUF_LINES]
    mov edx, [ecx+ebx*4]
    push edx
    mov eax, [ebp-12]
    add eax, [ebp-8]
    push eax
    call memcpy
    add esp, 12

    push edi
    call free
    add esp, 4
    mov ecx, [esi+BUF_LINES]
    mov eax, ebx
    dec eax
    mov edx, [ebp-12]
    mov [ecx+eax*4], edx

    push ebx
    push esi
    call buf_remove_line_at
    add esp, 8

    mov eax, [ebp+20]
    mov ecx, ebx
    dec ecx
    mov [eax], ecx
    mov eax, [ebp+24]
    mov ecx, [ebp-4]
    mov [eax], ecx
    jmp .ret

.noop:
    mov eax, [ebp+20]
    mov dword [eax], 0
    mov eax, [ebp+24]
    mov dword [eax], 0
    jmp .ret

.col_gt0:
    mov eax, [ebp+16]
    dec eax
    push eax
    push dword [ebp+12]
    push esi
    call buffer_delete_char
    add esp, 12
    mov eax, [ebp+20]
    mov ecx, [ebp+12]
    mov [eax], ecx
    mov eax, [ebp+24]
    mov ecx, [ebp+16]
    dec ecx
    mov [eax], ecx

.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void buffer_split_line(buffer_t* buf, dword line, dword col)
buffer_split_line:
    proc_enter
    sub esp, 8                    ; -4 byte_off, -8 head ptr
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov eax, [ebp+12]
    test eax, eax
    jl .done
    cmp eax, [esi+BUF_COUNT]
    jge .done
    mov ecx, [esi+BUF_LINES]
    mov edi, [ecx+eax*4]
    push dword [ebp+16]
    push edi
    call utf8_byte_offset
    add esp, 8
    mov [ebp-4], eax

    mov eax, edi
    add eax, [ebp-4]
    push eax
    call strdup
    add esp, 4
    mov ebx, eax                    ; ebx = tail

    mov eax, [ebp-4]
    inc eax
    push eax
    call malloc
    add esp, 4
    mov [ebp-8], eax                  ; head
    push dword [ebp-4]
    push edi
    push dword [ebp-8]
    call memcpy
    add esp, 12
    mov eax, [ebp-8]
    add eax, [ebp-4]
    mov byte [eax], 0

    push edi
    call free
    add esp, 4
    mov ecx, [esi+BUF_LINES]
    mov eax, [ebp+12]
    mov edx, [ebp-8]
    mov [ecx+eax*4], edx

    mov eax, [ebp+12]
    inc eax
    push ebx
    push eax
    push esi
    call buf_insert_line_at
    add esp, 12
.done:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; long buffer_word_count(const buffer_t* buf) -- cdecl.
buffer_word_count:
    proc_enter
    sub esp, 4                   ; [ebp-4] = total
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov dword [ebp-4], 0
    xor edi, edi
.line_loop:
    cmp edi, [esi+BUF_COUNT]
    jge .done
    mov ecx, [esi+BUF_LINES]
    mov ecx, [ecx+edi*4]
    xor edx, edx
    xor ebx, ebx
.byte_loop:
    movzx eax, byte [ecx+ebx]
    test eax, eax
    jz .line_done
    cmp al, 0x20
    je .is_space
    cmp al, 0x09
    je .is_space
    cmp al, 0x0A
    je .is_space
    cmp al, 0x0B
    je .is_space
    cmp al, 0x0C
    je .is_space
    cmp al, 0x0D
    je .is_space
    test edx, edx
    jnz .advance
    mov edx, 1
    inc dword [ebp-4]
    jmp .advance
.is_space:
    xor edx, edx
.advance:
    inc ebx
    jmp .byte_loop
.line_done:
    inc edi
    jmp .line_loop
.done:
    mov eax, [ebp-4]
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; long buffer_char_count(const buffer_t* buf) -- cdecl.
buffer_char_count:
    proc_enter
    sub esp, 4                    ; [ebp-4] = total
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov dword [ebp-4], 0
    xor edi, edi
.loop:
    cmp edi, [esi+BUF_COUNT]
    jge .after
    mov ecx, [esi+BUF_LINES]
    push dword [ecx+edi*4]
    call utf8_strlen
    add esp, 4
    add [ebp-4], eax
    inc edi
    jmp .loop
.after:
    mov eax, [esi+BUF_COUNT]
    cmp eax, 1
    jle .ret
    dec eax
    add [ebp-4], eax
.ret:
    mov eax, [ebp-4]
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; char* buffer_join(const buffer_t* buf) -- cdecl, alloue (a liberer).
buffer_join:
    proc_enter
    sub esp, 8                   ; -4 total_len, -8 pos
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov dword [ebp-4], 0
    xor edi, edi
.count_loop:
    cmp edi, [esi+BUF_COUNT]
    jge .count_done
    mov ecx, [esi+BUF_LINES]
    push dword [ecx+edi*4]
    call strlen
    add esp, 4
    add [ebp-4], eax
    inc edi
    jmp .count_loop
.count_done:
    mov eax, [esi+BUF_COUNT]
    cmp eax, 1
    jle .alloc
    dec eax
    add [ebp-4], eax
.alloc:
    mov eax, [ebp-4]
    inc eax
    push eax
    call malloc
    add esp, 4
    mov ebx, eax                    ; ebx = resultat

    xor edi, edi
    mov dword [ebp-8], 0
.fill_loop:
    cmp edi, [esi+BUF_COUNT]
    jge .fill_done
    mov ecx, [esi+BUF_LINES]
    mov edx, [ecx+edi*4]
    push edx
    call strlen
    add esp, 4
    push eax
    mov ecx, [esi+BUF_LINES]
    mov edx, [ecx+edi*4]
    push edx
    mov edx, ebx
    add edx, [ebp-8]
    push edx
    call memcpy
    add esp, 12

    mov ecx, [esi+BUF_LINES]
    mov edx, [ecx+edi*4]
    push edx
    call strlen
    add esp, 4
    add [ebp-8], eax

    mov eax, edi
    inc eax
    cmp eax, [esi+BUF_COUNT]
    jge .no_sep
    mov ecx, ebx
    add ecx, [ebp-8]
    mov byte [ecx], 10
    inc dword [ebp-8]
.no_sep:
    inc edi
    jmp .fill_loop
.fill_done:
    mov ecx, ebx
    add ecx, [ebp-8]
    mov byte [ecx], 0
    mov eax, ebx
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret
