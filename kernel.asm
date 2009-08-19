; KFX kernel - The bootloader loads this to 0x08:10000 and jumps here.
[bits 32]
[org 0x10000]
kernel_boot:
	call sub_clear_screen
	call check_a20
	mov esi, msg_kernel_boot
	call sub_printl
	cmp dword [kernel_magic], 0xcaccaac0
	je magic_ok
	mov esi, msg_kernel_bad_magic
	call sub_prints
	mov esi, [kernel_magic]
	mov cx, 4
	call sub_printhexs
	call sub_newl
	jmp kernel_panic
	magic_ok:
	mov esi, msg_kernel_booted
	call sub_printl
	
	mov cl, 0
keyboard_loop:
	inc cl
	mov al, cl
	in al, 0x64
	and al, 0x01
	jz keyboard_loop
read_keyboard:
	in al, 0x60
	mov bl, al
	and bl, 0x80
	jnz read_keyboard
read_keyboard_down:
	and eax, 0x7f
	mov bl, al
	mov esi, keyboard_map
	add esi, eax
	mov al, [esi]
	or al, al
	jz keyboard_unknown_key
	cmp al, 13
	je keyboard_enter
keyboard_ascii_key:						; process ascii key, ascii in AL, scancode in BL
	mov ecx, [command_pos]
	mov [command_buffer+ecx], al
	inc byte [command_pos]
	call sub_printc
	call sub_flush
	jmp keyboard_loop
keyboard_unknown_key:						; process unknown key, scancode in BL
	mov al, '<'
	call sub_printc
	mov al, bl
	call sub_printhexc
	mov al, '>'
	call sub_printc
	call sub_flush
	jmp keyboard_loop
keyboard_enter:							; process enter pressed
	call sub_newl
	call parse_command
	mov byte [command_pos], 0
	jmp keyboard_loop

parse_command:
	mov esi, msg_unknown_command
	call sub_prints
	mov ecx, [command_pos]
	mov byte [command_buffer+ecx], 0
	mov esi, command_buffer
	call sub_printl
	ret

; Hang
kernel_panic:
	mov esi, msg_kernel_panic
	call sub_printl
kernel_panic_halt:
	hlt
	jmp kernel_panic_halt

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Subroutines
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

check_a20:
	push eax
	push ebx
	mov word [0x7dfe], 0xaa55
	mov word [0x107dfe], 0x0000
	mov word ax, [0x7dfe]
	cmp ax, 0xaa55
	je a20_is_enabled
	call a20_enable
	jmp check_a20
	a20_is_enabled:
	check_a20_done:
	pop ebx
	pop eax
	ret

empty_8042:
	in al, 0x64				; 8042 status port
	test al, 2				; is input buffer full?
	jnz empty_8042				; yes, loop
	ret

empty_8042_2:
	in al, 0x64				; 8042 status port
	test al, 1				; is input buffer full?
	jnz empty_8042_2			; yes, loop
	ret

a20_enable:
	call empty_8042
	mov al, 0xad
	out 0x64, al
	call empty_8042
	mov al, 0xd0
	out 0x64, al
	call empty_8042_2
	in al, 0x60
	push eax
	call empty_8042
	mov al, 0xd1
	out 0x64, al
	call empty_8042
	pop eax
	or al, 2
	out 0x60, al
	call empty_8042
	mov al, 0xae
	out 0x64, al
	call empty_8042
	ret

; Update cursor to VGA

sub_updatecursor:
	push eax
	push ecx
	push edx
	mov cx, [console_cursor]
	shr cx, 1				; divide by 2
	mov dx, 0x3d4
	mov al, 15
	out dx, al
	mov dx, 0x3d5
	mov al, cl
	out dx, al
	mov dx, 0x3d4
	mov al, 14
	out dx, al
	mov dx, 0x3d5
	mov al, ch
	out dx, al
	pop edx
	pop ecx
	pop eax
	ret

; Flush current text buffer to VGA
sub_flush:
	pushf
	push ecx
	mov ecx, 4000
	mov esi, console_buffer
	mov edi, 0xb8000
	cld
	rep movsb
	call sub_updatecursor
	pop ecx
	popf
	ret

; Clear textmode screen
sub_clear_screen:
	push eax
	push ecx
	push edi
	mov edi, console_buffer				; clear screen buffer
	mov ecx, 2000
	mov ax, 0x1700
	rep stosw
	xor ecx, ecx					; move cursor to 0,0
	mov [console_cursor], ecx
	pop edi
	pop ecx
	pop eax
	call sub_flush
	ret

sub_scroll_line:
	push eax
	push ecx
	push esi
	push edi
	mov eax, [console_cursor]			; get current cursor
	sub eax, 160					; move it one row upwards
	mov [console_cursor], eax			; store new cursor
	mov ecx, 4000-160				; move n-1 rows of screen buffer
	mov esi, console_buffer
	add esi, 160
	mov edi, console_buffer
	rep movsb
	mov ecx, 80					; clear last row of screen buffer
	mov edi, console_buffer
	add edi, 4000-160
	mov ax, 0x1700
	rep stosw
	pop edi
	pop esi
	pop ecx
	pop eax
	ret

; Goto beginning of next line
sub_newl:
	pushf
	push eax
	push ebx
	push ecx
	push edx
	mov eax, [console_cursor]		; get current cursor position
	xor edx, edx
	mov ebx, 160
	div ebx					; divide by 160 => eax contains row, edx column
	inc eax					; add one row
	xor edx, edx
	mul ebx					; multiply by 160 => eax contains new position
	mov [console_cursor], eax		; set new cursor position
	cmp eax, 4000
	jne sub_newl_no_scroll
	call sub_scroll_line
	sub_newl_no_scroll:
	pop edx
	pop ecx
	pop ebx
	pop eax
	popf
	call sub_flush
	ret

; Print char
; AL=char
sub_printc:
	push ebx
	push esi
	mov ebx, [console_cursor]
	mov esi, console_buffer
	add esi, ebx
	mov byte [esi], al
	inc esi
	mov byte [esi], 0x17
	inc ebx
	inc ebx
	mov [console_cursor], ebx
	cmp ebx, 4000
	jne sub_printc_no_scroll
	call sub_scroll_line
	sub_printc_no_scroll:
	pop esi
	pop ebx
	ret

; Print string
; ESI=string start
sub_prints:
	pushf
	push eax
	push esi
	sub_prints_next:
	mov al, [esi]
	cmp al, 0
	je sub_prints_done
	call sub_printc
	inc esi
	jmp sub_prints_next
	sub_prints_done:
	pop esi
	pop eax
	popf
	ret

; Print string and newline
; ESI=string start
sub_printl
	call sub_prints
	call sub_newl
	ret

; Print hex nibble
; AL=nibble
sub_printhexnib:
	push eax
	and al, 0x0f
	cmp al, 0x0a
	jge sub_printhexnib_letter
	add al, '0'
	jmp sub_printhexnib_move
sub_printhexnib_letter:
	add al, 'a'-0x0a
sub_printhexnib_move:
	call sub_printc
	pop eax
	ret

; Print hex char (byte)
; AL=byte
sub_printhexc:
	push eax
	push edx
	mov dl, al
	shr al, 4
	call sub_printhexnib
	mov al, dl
	call sub_printhexnib
	pop edx
	pop eax
	ret

; Print hex string with BIOS
; SI=data
; CX=len
sub_printhexs:
	push ecx
	push esi
	or ecx, ecx
	jz sub_printhexs_exit
	sub_printhexs_next:
	mov al, [esi]
	call sub_printhexc
	inc esi
	dec cx
	jz sub_printhexs_exit
	jmp sub_printhexs_next
	sub_printhexs_exit:
	pop esi
	pop ecx
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Data
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

msg_kernel_boot db 'KFX kernel booting...', 0
msg_kernel_bad_magic db 'Bad kernel magic: ', 0
msg_kernel_booted db 'Kernel booted successfully.', 0
msg_kernel_panic db 'Panic - System halted.', 0
msg_key_down db 'Key down: ', 0
msg_key_up db 'Key up: ', 0
msg_unknown_command db 'Unknown command: ', 0
keyboard_map db 0, 27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '+', 0, 0, 0
db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', 0, '^', 13, 0
db 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 0, 0, 0x27, 0, 0
db 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '-'
times 255-($-keyboard_map) db 0
console_cursor dd 0
console_buffer times 2000 dw 0
command_buffer times 256 db 0
command_pos db 0

; Pad to 10k
times 10236 - ($-$$) db 0
kernel_magic dd 0xcaccaac0

; Pad to 10MB
times 10079*1024 - ($-$$) db 0

