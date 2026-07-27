; editor.asm -- portage direct de writhdeck-c/src/editor.c : etat
; d'edition (buffer + curseur + undo/redo) par-dessus buffer.asm.
; Attendu inclus alors que le segment "readable executable" est deja
; actif, apres heap.asm/strutil.asm/utf8.asm/buffer.asm.
;
; Disposition de editor_t (52 octets) :
;   +0  buf         (buffer_t*)
;   +4  filepath    (char* ou 0)
;   +8  dirty       (dword)
;   +12 cy          (dword signe)
;   +16 cx          (dword signe)
;   +20 scroll_row  (dword)
;   +24 sticky_col  (dword signe, -1 = non fixee)
;   +28 undo_items  (undo_entry_t*)
;   +32 undo_count  (dword)
;   +36 undo_cap    (dword)
;   +40 redo_items  (undo_entry_t*)
;   +44 redo_count  (dword)
;   +48 redo_cap    (dword)
;
; undo_entry_t (12 octets) : {buf:buffer_t*, cy:dword, cx:dword}
; wrap_row_t   (12 octets) : {logical_line:dword, start_char:dword, len_chars:dword}
; -- meme taille que undo_entry_t : ed_arr_ensure_capacity (croissance
; par doublement, depart 8) est reutilisee telle quelle pour le tableau
; de wrap_row_t dans editor_wrap.

EDITOR_BUF         = 0
EDITOR_FILEPATH    = 4
EDITOR_DIRTY       = 8
EDITOR_CY          = 12
EDITOR_CX          = 16
EDITOR_SCROLL      = 20
EDITOR_STICKY      = 24
EDITOR_UNDO_ITEMS  = 28
EDITOR_UNDO_COUNT  = 32
EDITOR_UNDO_CAP    = 36
EDITOR_REDO_ITEMS  = 40
EDITOR_REDO_COUNT  = 44
EDITOR_REDO_CAP    = 48
EDITOR_SIZE        = 52

UNDO_ENTRY_BUF  = 0
UNDO_ENTRY_CY   = 4
UNDO_ENTRY_CX   = 8
UNDO_ENTRY_SIZE = 12

WRAP_ROW_SIZE = 12

EDITOR_UNDO_MAX = 100

; --- aides internes ---

; void ed_arr_ensure_capacity(dword* items_field_addr, dword* cap_field_addr,
;                              dword need) -- cdecl. Generique : marche pour
; undo_items/redo_items (editor_t) ET pour le tableau wrap_row_t
; (editor_wrap), les trois ayant des elements de 12 octets. Depart 8,
; doublement jusqu'a >= need.
ed_arr_ensure_capacity:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov edi, [ebp+12]
    mov ebx, [edi]
    mov ecx, [ebp+16]
    cmp ebx, ecx
    jae .done
    test ebx, ebx
    jnz .grow
    mov ebx, 8
    jmp .checkloop
.grow:
    shl ebx, 1
.checkloop:
    cmp ebx, ecx
    jae .apply
    jmp .grow
.apply:
    imul eax, ebx, UNDO_ENTRY_SIZE
    push eax
    push dword [esi]
    call realloc
    add esp, 8
    mov [esi], eax
    mov [edi], ebx
.done:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void ed_clamp_cursor(editor_t* ed) -- cdecl. cy clampe a [0,count-1],
; cx clampe a [0, line_char_count(cy)] -- ne touche pas sticky_col.
ed_clamp_cursor:
    proc_enter
    push esi
    mov esi, [ebp+8]
    mov eax, [esi+EDITOR_BUF]
    mov ecx, [eax+BUF_COUNT]
    dec ecx
    cmp dword [esi+EDITOR_CY], 0
    jge .cy_ge0
    mov dword [esi+EDITOR_CY], 0
.cy_ge0:
    mov eax, [esi+EDITOR_CY]
    cmp eax, ecx
    jle .cy_le_max
    mov [esi+EDITOR_CY], ecx
.cy_le_max:
    push dword [esi+EDITOR_CY]
    push dword [esi+EDITOR_BUF]
    call buffer_line_char_count
    add esp, 8
    mov ecx, eax
    cmp dword [esi+EDITOR_CX], 0
    jge .cx_ge0
    mov dword [esi+EDITOR_CX], 0
.cx_ge0:
    mov eax, [esi+EDITOR_CX]
    cmp eax, ecx
    jle .done
    mov [esi+EDITOR_CX], ecx
.done:
    pop esi
    proc_leave
    ret

; --- API publique (editor.h) ---

; editor_t* editor_new(void) -- cdecl.
editor_new:
    proc_enter
    push esi
    push EDITOR_SIZE
    call malloc
    add esp, 4
    mov esi, eax
    call buffer_new
    mov [esi+EDITOR_BUF], eax
    mov dword [esi+EDITOR_FILEPATH], 0
    mov dword [esi+EDITOR_DIRTY], 0
    mov dword [esi+EDITOR_CY], 0
    mov dword [esi+EDITOR_CX], 0
    mov dword [esi+EDITOR_SCROLL], 0
    mov dword [esi+EDITOR_STICKY], -1
    mov dword [esi+EDITOR_UNDO_ITEMS], 0
    mov dword [esi+EDITOR_UNDO_COUNT], 0
    mov dword [esi+EDITOR_UNDO_CAP], 0
    mov dword [esi+EDITOR_REDO_ITEMS], 0
    mov dword [esi+EDITOR_REDO_COUNT], 0
    mov dword [esi+EDITOR_REDO_CAP], 0
    mov eax, esi
    pop esi
    proc_leave
    ret

; void editor_undo_clear(editor_t* ed) -- cdecl. Vide les deux piles
; (libere chaque buffer_t clone), sans toucher aux tableaux/capacites.
editor_undo_clear:
    proc_enter
    push esi
    push edi
    mov esi, [ebp+8]
    xor edi, edi
.u_loop:
    cmp edi, [esi+EDITOR_UNDO_COUNT]
    jge .u_done
    mov eax, [esi+EDITOR_UNDO_ITEMS]
    imul ecx, edi, UNDO_ENTRY_SIZE
    add eax, ecx
    push dword [eax+UNDO_ENTRY_BUF]
    call buffer_free
    add esp, 4
    inc edi
    jmp .u_loop
.u_done:
    mov dword [esi+EDITOR_UNDO_COUNT], 0
    xor edi, edi
.r_loop:
    cmp edi, [esi+EDITOR_REDO_COUNT]
    jge .r_done
    mov eax, [esi+EDITOR_REDO_ITEMS]
    imul ecx, edi, UNDO_ENTRY_SIZE
    add eax, ecx
    push dword [eax+UNDO_ENTRY_BUF]
    call buffer_free
    add esp, 4
    inc edi
    jmp .r_loop
.r_done:
    mov dword [esi+EDITOR_REDO_COUNT], 0
    pop edi
    pop esi
    proc_leave
    ret

; void editor_free(editor_t* ed) -- cdecl.
editor_free:
    proc_enter
    push esi
    mov esi, [ebp+8]
    push dword [esi+EDITOR_BUF]
    call buffer_free
    add esp, 4
    cmp dword [esi+EDITOR_FILEPATH], 0
    je .no_fp
    push dword [esi+EDITOR_FILEPATH]
    call free
    add esp, 4
.no_fp:
    push esi
    call editor_undo_clear
    add esp, 4
    push dword [esi+EDITOR_UNDO_ITEMS]
    call free
    add esp, 4
    push dword [esi+EDITOR_REDO_ITEMS]
    call free
    add esp, 4
    push esi
    call free
    add esp, 4
    pop esi
    proc_leave
    ret

; int editor_load(editor_t* ed, const char* path) -- cdecl.
editor_load:
    proc_enter
    push esi
    mov esi, [ebp+8]
    cmp dword [esi+EDITOR_FILEPATH], 0
    je .no_free
    push dword [esi+EDITOR_FILEPATH]
    call free
    add esp, 4
.no_free:
    push dword [ebp+12]
    call strdup
    add esp, 4
    mov [esi+EDITOR_FILEPATH], eax
    push dword [ebp+12]
    push dword [esi+EDITOR_BUF]
    call buffer_load_file
    add esp, 8
    push eax
    mov dword [esi+EDITOR_CY], 0
    mov dword [esi+EDITOR_CX], 0
    mov dword [esi+EDITOR_SCROLL], 0
    mov dword [esi+EDITOR_DIRTY], 0
    mov dword [esi+EDITOR_STICKY], -1
    pop eax
    pop esi
    proc_leave
    ret

; int editor_save(editor_t* ed) -- cdecl.
editor_save:
    proc_enter
    push esi
    mov esi, [ebp+8]
    cmp dword [esi+EDITOR_FILEPATH], 0
    jne .have_fp
    mov eax, -1
    jmp .ret
.have_fp:
    push dword [esi+EDITOR_FILEPATH]
    push dword [esi+EDITOR_BUF]
    call buffer_save_file
    add esp, 8
    test eax, eax
    jnz .ret
    mov dword [esi+EDITOR_DIRTY], 0
.ret:
    pop esi
    proc_leave
    ret

; void editor_insert_codepoint(editor_t* ed, dword cp) -- cdecl.
editor_insert_codepoint:
    proc_enter
    push esi
    mov esi, [ebp+8]
    push dword [ebp+12]
    push dword [esi+EDITOR_CX]
    push dword [esi+EDITOR_CY]
    push dword [esi+EDITOR_BUF]
    call buffer_insert_char
    add esp, 16
    inc dword [esi+EDITOR_CX]
    mov dword [esi+EDITOR_DIRTY], 1
    pop esi
    proc_leave
    ret

; void editor_enter(editor_t* ed) -- cdecl.
editor_enter:
    proc_enter
    push esi
    mov esi, [ebp+8]
    push dword [esi+EDITOR_CX]
    push dword [esi+EDITOR_CY]
    push dword [esi+EDITOR_BUF]
    call buffer_split_line
    add esp, 12
    inc dword [esi+EDITOR_CY]
    mov dword [esi+EDITOR_CX], 0
    mov dword [esi+EDITOR_DIRTY], 1
    pop esi
    proc_leave
    ret

; void editor_backspace(editor_t* ed) -- cdecl.
editor_backspace:
    proc_enter
    sub esp, 8                  ; -4 new_cy, -8 new_cx
    push esi
    mov esi, [ebp+8]
    cmp dword [esi+EDITOR_CY], 0
    jne .proceed
    cmp dword [esi+EDITOR_CX], 0
    jne .proceed
    jmp .ret
.proceed:
    lea eax, [ebp-8]
    push eax
    lea eax, [ebp-4]
    push eax
    push dword [esi+EDITOR_CX]
    push dword [esi+EDITOR_CY]
    push dword [esi+EDITOR_BUF]
    call buffer_backspace
    add esp, 20
    mov eax, [ebp-4]
    mov [esi+EDITOR_CY], eax
    mov eax, [ebp-8]
    mov [esi+EDITOR_CX], eax
    mov dword [esi+EDITOR_DIRTY], 1
.ret:
    pop esi
    proc_leave
    ret

; void editor_delete(editor_t* ed) -- cdecl.
editor_delete:
    proc_enter
    push esi
    mov esi, [ebp+8]
    push dword [esi+EDITOR_CY]
    push dword [esi+EDITOR_BUF]
    call buffer_line_char_count
    add esp, 8
    cmp dword [esi+EDITOR_CX], eax
    jl .do_delete
    mov eax, [esi+EDITOR_BUF]
    mov eax, [eax+BUF_COUNT]
    dec eax
    cmp dword [esi+EDITOR_CY], eax
    jl .do_delete
    jmp .ret
.do_delete:
    push dword [esi+EDITOR_CX]
    push dword [esi+EDITOR_CY]
    push dword [esi+EDITOR_BUF]
    call buffer_delete_char
    add esp, 12
    mov dword [esi+EDITOR_DIRTY], 1
.ret:
    pop esi
    proc_leave
    ret

; void editor_move_left(editor_t* ed) -- cdecl.
editor_move_left:
    proc_enter
    push esi
    mov esi, [ebp+8]
    cmp dword [esi+EDITOR_CX], 0
    jle .try_prev
    dec dword [esi+EDITOR_CX]
    jmp .ret
.try_prev:
    cmp dword [esi+EDITOR_CY], 0
    jle .ret
    dec dword [esi+EDITOR_CY]
    push dword [esi+EDITOR_CY]
    push dword [esi+EDITOR_BUF]
    call buffer_line_char_count
    add esp, 8
    mov [esi+EDITOR_CX], eax
.ret:
    pop esi
    proc_leave
    ret

; void editor_move_right(editor_t* ed) -- cdecl.
editor_move_right:
    proc_enter
    push esi
    mov esi, [ebp+8]
    push dword [esi+EDITOR_CY]
    push dword [esi+EDITOR_BUF]
    call buffer_line_char_count
    add esp, 8
    cmp dword [esi+EDITOR_CX], eax
    jl .advance
    mov ecx, [esi+EDITOR_BUF]
    mov ecx, [ecx+BUF_COUNT]
    dec ecx
    cmp dword [esi+EDITOR_CY], ecx
    jge .ret
    inc dword [esi+EDITOR_CY]
    mov dword [esi+EDITOR_CX], 0
    jmp .ret
.advance:
    inc dword [esi+EDITOR_CX]
.ret:
    pop esi
    proc_leave
    ret

; void editor_move_home(editor_t* ed) -- cdecl.
editor_move_home:
    proc_enter
    mov eax, [ebp+8]
    mov dword [eax+EDITOR_CX], 0
    proc_leave
    ret

; void editor_move_end(editor_t* ed) -- cdecl.
editor_move_end:
    proc_enter
    push esi
    mov esi, [ebp+8]
    push dword [esi+EDITOR_CY]
    push dword [esi+EDITOR_BUF]
    call buffer_line_char_count
    add esp, 8
    mov [esi+EDITOR_CX], eax
    pop esi
    proc_leave
    ret

; void editor_move_pgup(editor_t* ed, dword page_size) -- cdecl.
editor_move_pgup:
    proc_enter
    push esi
    mov esi, [ebp+8]
    mov eax, [esi+EDITOR_CY]
    sub eax, [ebp+12]
    mov [esi+EDITOR_CY], eax
    push esi
    call ed_clamp_cursor
    add esp, 4
    pop esi
    proc_leave
    ret

; void editor_move_pgdn(editor_t* ed, dword page_size) -- cdecl.
editor_move_pgdn:
    proc_enter
    push esi
    mov esi, [ebp+8]
    mov eax, [esi+EDITOR_CY]
    add eax, [ebp+12]
    mov [esi+EDITOR_CY], eax
    push esi
    call ed_clamp_cursor
    add esp, 4
    pop esi
    proc_leave
    ret

; void editor_set_cursor(editor_t* ed, dword cy, dword cx) -- cdecl.
editor_set_cursor:
    proc_enter
    push esi
    mov esi, [ebp+8]
    mov eax, [ebp+12]
    mov [esi+EDITOR_CY], eax
    mov eax, [ebp+16]
    mov [esi+EDITOR_CX], eax
    push esi
    call ed_clamp_cursor
    add esp, 4
    pop esi
    proc_leave
    ret

; void editor_move_word_right(editor_t* ed) -- cdecl. Seul ' ' (0x20)
; compte comme separateur, jamais la tabulation (voir editor.h).
editor_move_word_right:
    proc_enter
    sub esp, 12                 ; -4 len, -8 line_ptr, -12 cx
    push esi
    mov esi, [ebp+8]
    push dword [esi+EDITOR_CY]
    push dword [esi+EDITOR_BUF]
    call buffer_line_char_count
    add esp, 8
    mov [ebp-4], eax

    mov eax, [esi+EDITOR_BUF]
    mov eax, [eax+BUF_LINES]
    mov ecx, [esi+EDITOR_CY]
    mov eax, [eax+ecx*4]
    mov [ebp-8], eax

    mov eax, [esi+EDITOR_CX]
    mov [ebp-12], eax

.skip_word:
    mov eax, [ebp-12]
    cmp eax, [ebp-4]
    jge .skip_spaces
    push eax
    push dword [ebp-8]
    call utf8_byte_offset
    add esp, 8
    mov ecx, [ebp-8]
    movzx eax, byte [ecx+eax]
    cmp al, ' '
    je .skip_spaces
    inc dword [ebp-12]
    jmp .skip_word

.skip_spaces:
    mov eax, [ebp-12]
    cmp eax, [ebp-4]
    jge .after
    push eax
    push dword [ebp-8]
    call utf8_byte_offset
    add esp, 8
    mov ecx, [ebp-8]
    movzx eax, byte [ecx+eax]
    cmp al, ' '
    jne .after
    inc dword [ebp-12]
    jmp .skip_spaces

.after:
    mov eax, [ebp-12]
    cmp eax, [ebp-4]
    jl .store
    mov eax, [esi+EDITOR_BUF]
    mov ecx, [eax+BUF_COUNT]
    dec ecx
    cmp dword [esi+EDITOR_CY], ecx
    jge .store
    inc dword [esi+EDITOR_CY]
    mov dword [ebp-12], 0
.store:
    mov eax, [ebp-12]
    mov [esi+EDITOR_CX], eax
    pop esi
    proc_leave
    ret

; long editor_word_count(const editor_t* ed) -- cdecl.
editor_word_count:
    proc_enter
    mov eax, [ebp+8]
    push dword [eax+EDITOR_BUF]
    call buffer_word_count
    add esp, 4
    proc_leave
    ret

; void editor_push_undo(editor_t* ed) -- cdecl.
editor_push_undo:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    push dword [esi+EDITOR_BUF]
    call buffer_clone
    add esp, 4
    mov ebx, eax

    mov eax, [esi+EDITOR_UNDO_COUNT]
    inc eax
    push eax
    lea eax, [esi+EDITOR_UNDO_CAP]
    push eax
    lea eax, [esi+EDITOR_UNDO_ITEMS]
    push eax
    call ed_arr_ensure_capacity
    add esp, 12

    mov eax, [esi+EDITOR_UNDO_ITEMS]
    mov ecx, [esi+EDITOR_UNDO_COUNT]
    imul ecx, ecx, UNDO_ENTRY_SIZE
    add eax, ecx
    mov [eax+UNDO_ENTRY_BUF], ebx
    mov ecx, [esi+EDITOR_CY]
    mov [eax+UNDO_ENTRY_CY], ecx
    mov ecx, [esi+EDITOR_CX]
    mov [eax+UNDO_ENTRY_CX], ecx
    inc dword [esi+EDITOR_UNDO_COUNT]

    mov eax, [esi+EDITOR_UNDO_COUNT]
    cmp eax, EDITOR_UNDO_MAX
    jle .no_evict
    mov eax, [esi+EDITOR_UNDO_ITEMS]
    push dword [eax+UNDO_ENTRY_BUF]
    call buffer_free
    add esp, 4
    mov eax, [esi+EDITOR_UNDO_COUNT]
    dec eax
    imul eax, eax, UNDO_ENTRY_SIZE
    push eax
    mov eax, [esi+EDITOR_UNDO_ITEMS]
    add eax, UNDO_ENTRY_SIZE
    push eax
    push dword [esi+EDITOR_UNDO_ITEMS]
    call memmove
    add esp, 12
    dec dword [esi+EDITOR_UNDO_COUNT]
.no_evict:

    xor edi, edi
.clear_redo_loop:
    cmp edi, [esi+EDITOR_REDO_COUNT]
    jge .clear_redo_done
    mov eax, [esi+EDITOR_REDO_ITEMS]
    imul ecx, edi, UNDO_ENTRY_SIZE
    add eax, ecx
    push dword [eax+UNDO_ENTRY_BUF]
    call buffer_free
    add esp, 4
    inc edi
    jmp .clear_redo_loop
.clear_redo_done:
    mov dword [esi+EDITOR_REDO_COUNT], 0

    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; int editor_undo(editor_t* ed) -- cdecl.
editor_undo:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    cmp dword [esi+EDITOR_UNDO_COUNT], 0
    jne .proceed
    xor eax, eax
    jmp .ret
.proceed:
    push dword [esi+EDITOR_BUF]
    call buffer_clone
    add esp, 4
    mov ebx, eax

    mov eax, [esi+EDITOR_REDO_COUNT]
    inc eax
    push eax
    lea eax, [esi+EDITOR_REDO_CAP]
    push eax
    lea eax, [esi+EDITOR_REDO_ITEMS]
    push eax
    call ed_arr_ensure_capacity
    add esp, 12

    mov eax, [esi+EDITOR_REDO_ITEMS]
    mov ecx, [esi+EDITOR_REDO_COUNT]
    imul ecx, ecx, UNDO_ENTRY_SIZE
    add eax, ecx
    mov [eax+UNDO_ENTRY_BUF], ebx
    mov ecx, [esi+EDITOR_CY]
    mov [eax+UNDO_ENTRY_CY], ecx
    mov ecx, [esi+EDITOR_CX]
    mov [eax+UNDO_ENTRY_CX], ecx
    inc dword [esi+EDITOR_REDO_COUNT]

    dec dword [esi+EDITOR_UNDO_COUNT]
    mov eax, [esi+EDITOR_UNDO_ITEMS]
    mov ecx, [esi+EDITOR_UNDO_COUNT]
    imul ecx, ecx, UNDO_ENTRY_SIZE
    add eax, ecx
    mov edi, eax

    push dword [esi+EDITOR_BUF]
    call buffer_free
    add esp, 4
    mov eax, [edi+UNDO_ENTRY_BUF]
    mov [esi+EDITOR_BUF], eax
    mov eax, [edi+UNDO_ENTRY_CY]
    mov [esi+EDITOR_CY], eax
    mov eax, [edi+UNDO_ENTRY_CX]
    mov [esi+EDITOR_CX], eax
    mov dword [esi+EDITOR_DIRTY], 1
    mov eax, 1
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; int editor_redo(editor_t* ed) -- cdecl. Symetrique de editor_undo,
; MAIS sans re-verifier EDITOR_UNDO_MAX en poussant sur la pile undo
; (asymetrie volontaire du C -- voir plan).
editor_redo:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    cmp dword [esi+EDITOR_REDO_COUNT], 0
    jne .proceed
    xor eax, eax
    jmp .ret
.proceed:
    push dword [esi+EDITOR_BUF]
    call buffer_clone
    add esp, 4
    mov ebx, eax

    mov eax, [esi+EDITOR_UNDO_COUNT]
    inc eax
    push eax
    lea eax, [esi+EDITOR_UNDO_CAP]
    push eax
    lea eax, [esi+EDITOR_UNDO_ITEMS]
    push eax
    call ed_arr_ensure_capacity
    add esp, 12

    mov eax, [esi+EDITOR_UNDO_ITEMS]
    mov ecx, [esi+EDITOR_UNDO_COUNT]
    imul ecx, ecx, UNDO_ENTRY_SIZE
    add eax, ecx
    mov [eax+UNDO_ENTRY_BUF], ebx
    mov ecx, [esi+EDITOR_CY]
    mov [eax+UNDO_ENTRY_CY], ecx
    mov ecx, [esi+EDITOR_CX]
    mov [eax+UNDO_ENTRY_CX], ecx
    inc dword [esi+EDITOR_UNDO_COUNT]

    dec dword [esi+EDITOR_REDO_COUNT]
    mov eax, [esi+EDITOR_REDO_ITEMS]
    mov ecx, [esi+EDITOR_REDO_COUNT]
    imul ecx, ecx, UNDO_ENTRY_SIZE
    add eax, ecx
    mov edi, eax

    push dword [esi+EDITOR_BUF]
    call buffer_free
    add esp, 4
    mov eax, [edi+UNDO_ENTRY_BUF]
    mov [esi+EDITOR_BUF], eax
    mov eax, [edi+UNDO_ENTRY_CY]
    mov [esi+EDITOR_CY], eax
    mov eax, [edi+UNDO_ENTRY_CX]
    mov [esi+EDITOR_CX], eax
    mov dword [esi+EDITOR_DIRTY], 1
    mov eax, 1
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; int editor_find(editor_t* ed, const char* term) -- cdecl.
editor_find:
    proc_enter
    sub esp, 20                  ; -4 n, -8 i, -12 li, -16 line_ptr, -20 from_byte
    push esi
    mov esi, [ebp+8]
    mov eax, [ebp+12]
    test eax, eax
    jz .not_found
    cmp byte [eax], 0
    jz .not_found

    mov eax, [esi+EDITOR_BUF]
    mov eax, [eax+BUF_COUNT]
    mov [ebp-4], eax
    mov dword [ebp-8], 0
.loop:
    mov eax, [ebp-8]
    cmp eax, [ebp-4]
    jge .not_found
    mov eax, [esi+EDITOR_CY]
    add eax, [ebp-8]
    xor edx, edx
    div dword [ebp-4]
    mov [ebp-12], edx

    mov eax, [esi+EDITOR_BUF]
    mov eax, [eax+BUF_LINES]
    mov ecx, [ebp-12]
    mov eax, [eax+ecx*4]
    mov [ebp-16], eax

    cmp dword [ebp-8], 0
    jne .from_zero
    mov eax, [esi+EDITOR_CX]
    inc eax
    push eax
    push dword [ebp-16]
    call utf8_byte_offset
    add esp, 8
    mov [ebp-20], eax
    jmp .have_from
.from_zero:
    mov dword [ebp-20], 0
.have_from:
    push dword [ebp+12]
    mov eax, [ebp-16]
    add eax, [ebp-20]
    push eax
    call ascii_stristr
    add esp, 8
    test eax, eax
    jz .cont

    mov ecx, eax
    sub ecx, [ebp-16]
    push ecx
    push dword [ebp-16]
    call utf8_char_index
    add esp, 8
    mov ecx, [ebp-12]
    mov [esi+EDITOR_CY], ecx
    mov [esi+EDITOR_CX], eax
    mov eax, 1
    jmp .ret
.cont:
    inc dword [ebp-8]
    jmp .loop
.not_found:
    xor eax, eax
.ret:
    pop esi
    proc_leave
    ret

; int editor_replace_all(editor_t* ed, const char* term, const char* repl)
editor_replace_all:
    proc_enter
    sub esp, 40                 ; -4 term_len -8 repl_len -12 total -16 li
                                 ; -20 cnt -24 line_ptr -28 new_line
                                 ; -32 src/scratch -36 dst -40 remaining
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov eax, [ebp+12]
    test eax, eax
    jz .zero_ret
    cmp byte [eax], 0
    jz .zero_ret

    push dword [ebp+12]
    call strlen
    add esp, 4
    mov [ebp-4], eax

    push dword [ebp+16]
    call strlen
    add esp, 4
    mov [ebp-8], eax

    mov dword [ebp-12], 0
    mov dword [ebp-16], 0
.line_loop:
    mov edi, [esi+EDITOR_BUF]
    mov eax, [ebp-16]
    cmp eax, [edi+BUF_COUNT]
    jge .after_lines

    mov eax, [edi+BUF_LINES]
    mov ecx, [ebp-16]
    mov eax, [eax+ecx*4]
    mov [ebp-24], eax

    mov dword [ebp-20], 0
    mov eax, [ebp-24]
    mov [ebp-32], eax
.count_match_loop:
    push dword [ebp+12]
    push dword [ebp-32]
    call ascii_stristr
    add esp, 8
    test eax, eax
    jz .count_done
    inc dword [ebp-20]
    add eax, [ebp-4]
    mov [ebp-32], eax
    jmp .count_match_loop
.count_done:

    cmp dword [ebp-20], 0
    jne .has_matches
    jmp .next_line
.has_matches:
    push dword [ebp-24]
    call strlen
    add esp, 4
    mov ecx, [ebp-8]
    sub ecx, [ebp-4]
    cmp ecx, 0
    jge .extra_ok
    xor ecx, ecx
.extra_ok:
    imul ecx, [ebp-20]
    add eax, ecx
    inc eax
    push eax
    call malloc
    add esp, 4
    mov [ebp-28], eax

    mov eax, [ebp-24]
    mov [ebp-32], eax
    mov eax, [ebp-28]
    mov [ebp-36], eax
    mov eax, [ebp-20]
    mov [ebp-40], eax
.rebuild_loop:
    cmp dword [ebp-40], 0
    jle .rebuild_done
    push dword [ebp+12]
    push dword [ebp-32]
    call ascii_stristr
    add esp, 8
    mov ebx, eax
    sub ebx, [ebp-32]
    push ebx
    push dword [ebp-32]
    push dword [ebp-36]
    call memcpy
    add esp, 12
    mov eax, [ebp-36]
    add eax, ebx
    mov [ebp-36], eax

    push dword [ebp-8]
    push dword [ebp+16]
    push dword [ebp-36]
    call memcpy
    add esp, 12
    mov eax, [ebp-36]
    add eax, [ebp-8]
    mov [ebp-36], eax

    mov eax, [ebp-32]
    add eax, ebx
    add eax, [ebp-4]
    mov [ebp-32], eax

    dec dword [ebp-40]
    jmp .rebuild_loop
.rebuild_done:
    push dword [ebp-32]
    call strlen
    add esp, 4
    inc eax
    push eax
    push dword [ebp-32]
    push dword [ebp-36]
    call memcpy
    add esp, 12

    push dword [ebp-24]
    call free
    add esp, 4
    mov edi, [esi+EDITOR_BUF]
    mov eax, [edi+BUF_LINES]
    mov ecx, [ebp-16]
    mov edx, [ebp-28]
    mov [eax+ecx*4], edx

    mov eax, [ebp-12]
    add eax, [ebp-20]
    mov [ebp-12], eax

.next_line:
    inc dword [ebp-16]
    jmp .line_loop

.after_lines:
    cmp dword [ebp-12], 0
    jle .ret_total
    mov dword [esi+EDITOR_DIRTY], 1
.ret_total:
    mov eax, [ebp-12]
    jmp .ret
.zero_ret:
    xor eax, eax
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void editor_wrap(const editor_t* ed, dword width, wrap_row_t** out_rows,
;                   dword* out_count) -- cdecl.
editor_wrap:
    proc_enter
    sub esp, 40                 ; -4 width -8 rows_ptr -12 rows_cap
                                 ; -16 rows_count -20 li -24 len
                                 ; -28 line_ptr -32 start -36 take -40 p
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov eax, [ebp+12]
    cmp eax, 1
    jge .width_ok
    mov eax, 1
.width_ok:
    mov [ebp-4], eax

    mov edi, [esi+EDITOR_BUF]
    mov eax, [edi+BUF_COUNT]
    mov ebx, eax
    shl eax, 1
    add eax, 8
    mov [ebp-12], eax
    imul eax, eax, WRAP_ROW_SIZE
    push eax
    call malloc
    add esp, 4
    mov [ebp-8], eax
    mov dword [ebp-16], 0

    mov dword [ebp-20], 0
.line_loop:
    mov eax, [ebp-20]
    cmp eax, ebx
    jge .lines_done

    mov eax, [edi+BUF_LINES]
    mov ecx, [ebp-20]
    mov eax, [eax+ecx*4]
    mov [ebp-28], eax
    push eax
    call utf8_strlen
    add esp, 4
    mov [ebp-24], eax

    cmp dword [ebp-24], 0
    jne .nonempty_line
    mov eax, [ebp-16]
    inc eax
    push eax
    lea eax, [ebp-12]
    push eax
    lea eax, [ebp-8]
    push eax
    call ed_arr_ensure_capacity
    add esp, 12
    mov eax, [ebp-8]
    mov ecx, [ebp-16]
    imul ecx, ecx, WRAP_ROW_SIZE
    add eax, ecx
    mov ecx, [ebp-20]
    mov [eax], ecx
    mov dword [eax+4], 0
    mov dword [eax+8], 0
    inc dword [ebp-16]
    jmp .next_line

.nonempty_line:
    mov dword [ebp-32], 0
.split_loop:
    mov eax, [ebp-32]
    cmp eax, [ebp-24]
    jge .next_line

    mov eax, [ebp-24]
    sub eax, [ebp-32]              ; remaining
    mov ecx, [ebp-4]
    cmp eax, ecx
    jle .take_is_remaining
    mov eax, ecx
.take_is_remaining:
    mov [ebp-36], eax

    mov ecx, [ebp-24]
    sub ecx, [ebp-32]
    cmp eax, ecx
    jge .have_take

    mov eax, [ebp-32]
    add eax, [ebp-36]
    dec eax
    mov [ebp-40], eax
.search_space:
    mov eax, [ebp-40]
    cmp eax, [ebp-32]
    jle .have_take
    push eax
    push dword [ebp-28]
    call utf8_byte_offset
    add esp, 8
    mov ecx, [ebp-28]
    movzx edx, byte [ecx+eax]
    cmp dl, ' '
    je .found_space
    dec dword [ebp-40]
    jmp .search_space
.found_space:
    mov eax, [ebp-40]
    sub eax, [ebp-32]
    mov [ebp-36], eax
.have_take:
    mov eax, [ebp-16]
    inc eax
    push eax
    lea eax, [ebp-12]
    push eax
    lea eax, [ebp-8]
    push eax
    call ed_arr_ensure_capacity
    add esp, 12
    mov eax, [ebp-8]
    mov ecx, [ebp-16]
    imul ecx, ecx, WRAP_ROW_SIZE
    add eax, ecx
    mov ecx, [ebp-20]
    mov [eax], ecx
    mov ecx, [ebp-32]
    mov [eax+4], ecx
    mov ecx, [ebp-36]
    mov [eax+8], ecx
    inc dword [ebp-16]

    mov eax, [ebp-32]
    add eax, [ebp-36]
    mov [ebp-32], eax

.skip_spaces_wrap:
    mov eax, [ebp-32]
    cmp eax, [ebp-24]
    jge .split_loop
    push eax
    push dword [ebp-28]
    call utf8_byte_offset
    add esp, 8
    mov ecx, [ebp-28]
    movzx edx, byte [ecx+eax]
    cmp dl, ' '
    jne .split_loop
    inc dword [ebp-32]
    jmp .skip_spaces_wrap

.next_line:
    inc dword [ebp-20]
    jmp .line_loop

.lines_done:
    mov eax, [ebp+16]
    mov ecx, [ebp-8]
    mov [eax], ecx
    mov eax, [ebp+20]
    mov ecx, [ebp-16]
    mov [eax], ecx

    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; dword editor_cursor_visual_row(const wrap_row_t* rows, dword count,
;                                 dword cy, dword cx) -- cdecl.
editor_cursor_visual_row:
    proc_enter
    push ebx
    push esi
    push edi
    mov esi, [ebp+8]
    mov ebx, [ebp+20]
    mov edi, 0
.loop:
    cmp edi, [ebp+12]
    jge .fallback
    mov eax, edi
    imul eax, eax, WRAP_ROW_SIZE
    add eax, esi
    mov ecx, [eax]
    cmp ecx, [ebp+16]
    jne .cont
    mov ecx, [eax+4]
    mov edx, ecx
    add edx, [eax+8]
    mov ecx, edi
    inc ecx
    cmp ecx, [ebp+12]
    jge .is_last_true
    push eax
    mov eax, ecx
    imul eax, eax, WRAP_ROW_SIZE
    add eax, esi
    mov eax, [eax]
    cmp eax, [ebp+16]
    pop eax
    jne .is_last_true
    jmp .is_last_false
.is_last_true:
    cmp ebx, [eax+4]
    jl .cont
    cmp ebx, edx
    jg .cont
    jmp .match
.is_last_false:
    cmp ebx, [eax+4]
    jl .cont
    cmp ebx, edx
    jge .cont
    jmp .match
.cont:
    inc edi
    jmp .loop
.match:
    mov eax, edi
    jmp .ret
.fallback:
    cmp dword [ebp+12], 0
    jg .fallback_nonzero
    xor eax, eax
    jmp .ret
.fallback_nonzero:
    mov eax, [ebp+12]
    dec eax
.ret:
    pop edi
    pop esi
    pop ebx
    proc_leave
    ret

; void editor_move_up(editor_t* ed, dword width) -- cdecl.
editor_move_up:
    proc_enter
    sub esp, 8                  ; -4 rows_ptr, -8 rows_count
    push esi
    mov esi, [ebp+8]
    lea eax, [ebp-8]
    push eax
    lea eax, [ebp-4]
    push eax
    push dword [ebp+12]
    push esi
    call editor_wrap
    add esp, 16

    push dword [esi+EDITOR_CX]
    push dword [esi+EDITOR_CY]
    push dword [ebp-8]
    push dword [ebp-4]
    call editor_cursor_visual_row
    add esp, 16
    test eax, eax
    jle .free_only

    cmp dword [esi+EDITOR_STICKY], 0
    jge .have_sticky
    mov ecx, eax
    imul ecx, ecx, WRAP_ROW_SIZE
    add ecx, [ebp-4]
    mov edx, [ecx+4]
    mov ecx, [esi+EDITOR_CX]
    sub ecx, edx
    mov [esi+EDITOR_STICKY], ecx
.have_sticky:
    dec eax
    mov ecx, eax
    imul ecx, ecx, WRAP_ROW_SIZE
    add ecx, [ebp-4]
    mov edx, [esi+EDITOR_STICKY]
    cmp edx, 0
    jge .off_ge0
    xor edx, edx
.off_ge0:
    mov eax, [ecx+8]
    cmp edx, eax
    jle .off_ok
    mov edx, eax
.off_ok:
    mov eax, [ecx]
    mov [esi+EDITOR_CY], eax
    mov eax, [ecx+4]
    add eax, edx
    mov [esi+EDITOR_CX], eax
.free_only:
    push dword [ebp-4]
    call free
    add esp, 4
    pop esi
    proc_leave
    ret

; void editor_move_down(editor_t* ed, dword width) -- cdecl.
editor_move_down:
    proc_enter
    sub esp, 8
    push esi
    mov esi, [ebp+8]
    lea eax, [ebp-8]
    push eax
    lea eax, [ebp-4]
    push eax
    push dword [ebp+12]
    push esi
    call editor_wrap
    add esp, 16

    push dword [esi+EDITOR_CX]
    push dword [esi+EDITOR_CY]
    push dword [ebp-8]
    push dword [ebp-4]
    call editor_cursor_visual_row
    add esp, 16
    mov ecx, eax
    inc ecx
    cmp ecx, [ebp-8]
    jge .free_only

    cmp dword [esi+EDITOR_STICKY], 0
    jge .have_sticky
    mov ecx, eax
    imul ecx, ecx, WRAP_ROW_SIZE
    add ecx, [ebp-4]
    mov edx, [ecx+4]
    mov ecx, [esi+EDITOR_CX]
    sub ecx, edx
    mov [esi+EDITOR_STICKY], ecx
.have_sticky:
    inc eax
    mov ecx, eax
    imul ecx, ecx, WRAP_ROW_SIZE
    add ecx, [ebp-4]
    mov edx, [esi+EDITOR_STICKY]
    cmp edx, 0
    jge .off_ge0
    xor edx, edx
.off_ge0:
    mov eax, [ecx+8]
    cmp edx, eax
    jle .off_ok
    mov edx, eax
.off_ok:
    mov eax, [ecx]
    mov [esi+EDITOR_CY], eax
    mov eax, [ecx+4]
    add eax, edx
    mov [esi+EDITOR_CX], eax
.free_only:
    push dword [ebp-4]
    call free
    add esp, 4
    pop esi
    proc_leave
    ret
