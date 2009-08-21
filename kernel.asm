; KFX kernel - The bootloader loads this to 0x0800:0000 and jumps to 0008
[bits 16]
[org 0x8000]				; use absolute origin 0x8000 (32k)

kernel_header:				; header is 8 bytes
	db 'KFX', 0			; signature 4 bytes
	db kernel_length		; kernel length 1 byte in blocks
	db 0				; padding 3 bytes
	db 0
	db 0

boot_16:				; kernel code starts here in 16-bit real mode
	cli				; disable interrupts
	push es				; show red boot screen
	mov ax, 0xb800
	mov es, ax
	mov ax, 0x4700
	mov edi, 0x0000
	mov ecx, 2000
	cld
	rep stosw
	pop es
	lgdt [gdt32_desc]		; load 32-bit Global Descriptor Table
	lidt [idt32_desc]		; load 32-bit Interrupt Descriptor Table
	mov eax, cr0			; set bit 0 (PE) of CR0 (protected environment enable)
	or eax, 0x00000001
	mov eax, 0x00000011
	mov cr0, eax
	mov eax, cr4			; set bit 5 (PAE) of CR4 (physical address extension)
	or eax, 0x00000020
	mov cr4, eax
	jmp KERNEL32_CODE32:init_32	; long jump to 32-bit code

[bits 32]
init_32:				; protected mode 32-bit code starts here
	mov ax, KERNEL32_DATA
	mov ds, ax			; update data segment
	mov es, ax			; update alt1 data segment
	mov fs, ax			; update alt2 data segment
	mov gs, ax			; update alt3 data segment
	mov ss, ax			; update stack segment
	mov esp, 0x00040000		; stack pointer at 0x00040000 (256k)
	in al, 0x92			; Fast enable A20
	or al, 2
	out 0x92, al
	jmp boot_32

check_longmode:
	mov eax, 80000000h		; Extended-function 8000000h. 
	cpuid				; Is largest extended function 
	cmp eax, 80000000h		; any function > 80000000h? 
	jbe no_long_mode		; If not, no long mode. 
	mov eax, 80000001h		; Extended-function 8000001h. 
	cpuid				; Now EDX = extended-features flags. 
	bt edx, 29			; Test if long mode is supported. 
	jnc no_long_mode		; Exit if not supported. 
	jmp boot_32

no_long_mode:				; CPU won't support 64-bit mode
	mov byte [0xb8000], '3'
	mov byte [0xb8002], '2'
	hlt
	jmp $

boot_32:
	cld
	mov ax, 0x6700			; show yellow boot screen
	mov edi, 0xb8000
	mov ecx, 2000
	rep stosw

init_pml4_table:			; initialize page map level 4 pointers
	cld
	mov edi, pml4_table		; clear everything with zeroes
	xor eax, eax
	mov ecx, 1024			; 1024 x 32 bits (512 entries)
	rep stosd
	mov edi, pml4_table		; first entry points to pdp_table
	mov eax, pdp_table
	or eax, 0x00000007		; ..., cachedis(0), wrthru(0), user(1), r/w(1), present(1)
	stosd
	xor eax, eax			; zero higher 32 bits
	stosd

init_pdp_table:				; initialize page directory pointers
	cld
	mov edi, pdp_table		; clear everything with zeroes
	xor eax, eax
	mov ecx, 1024			; 1024 x 32 bits (512 entries)
	rep stosd
	mov edi, pdp_table		; first entry points to page_directory
	mov eax, page_directory
	or eax, 0x00000007		; ..., cachedis(0), wrthru(0), user(1), r/w(1), present(1)
	stosd
	xor eax, eax
	stosd				; zero higher 32 bits

init_page_directory:			; initialize page directory
	cld
	mov edi, page_directory		; clear everything with zeroes
	xor eax, eax
	mov ecx, 1024			; 1024 x 32 bit (512 entries)
	rep stosd
	mov edi, page_directory		; first entry points to identity_table
	mov eax, identity_table
	or eax, 0x00000007		; ..., cachedis(0), wrthru(0), user(1), r/w(1), present(1)
	stosd
	xor eax, eax			; zero higher 32 bits
	stosd

init_identity_table:			; identity table will map first 1MB to itself
	cld
	mov edi, identity_table		; clear everything with zeroes
	xor eax, eax
	mov ecx, 1024			; 1024 x 32 bit (512 entries)
	rep stosd
	mov edi, identity_table		; generate 512 entries
	mov ecx, 512
	mov ebx, 0x00000000		; use ebx for the increasing pointer (0k, 4k, 8k..)
	init_identity_loop:
	mov eax, ebx			; lower 32 bits of entry
	or eax, 0x00000007		; ..., cachedis(0), wrthru(0), user(1), r/w(1), present(1)
	stosd
	xor eax, eax			; higher 32 bits of entry
	stosd
	add ebx, 0x1000			; increment in 4k blocks
	dec ecx
	jnz init_identity_loop

enter_long_mode:
	cld
	mov ax, 0x7f00			; show gray boot screen
	mov edi, 0xb8000
	mov ecx, 2000
	rep stosw
	
	; Step 1: EFER.LME=1 (enable long mode)
	mov byte [0xb8000], '1'
	mov ecx, 0x0c0000080		; specify EFER MSR
	rdmsr				; read EFER MSR into EAX
	or eax, 0x00000100		; set bit 8 (LME) of EFER (IA-32e mode enable)
	wrmsr				; write EFER MSR from EAX
	
	; Step 2: CR3=PML4 (store PML4 address)
	mov byte [0xb8000], '2'
	mov eax, pml4_table
	mov cr3, eax			; store Page Map Level 4 Table address in CR3
	
	; Step 3: LGDT GDT64 (load 64-bit GDT)
	mov byte [0xb8000], '3'
	lgdt [gdt64_desc]
	
	; Step 4: CR0.PG=1 (enable paging)
	mov byte [0xb8000], '4'
	mov eax, cr0			; set bit 31 (PG) of CR0 (enable paging)
	or eax, 0x80000000
	mov cr0, eax
	
	; 32-bit compatibility mode. Next instruction must be long jump to 64-bit code.
	jmp KERNEL64_CODE:boot_64	; long jump to 64-bit code

[bits 64]
boot_64:				; long mode 64-bit code starts here
	;mov rsp, 0x00040000		; stack pointer at 0x00040000 (256k)
	;lgdt [gdt64_desc]		; load 64-bit GDT
	;lidt [idt64_desc]		; load 64-bit IDT
	mov byte [0xb8000], '5'
	;sti				; re-enable interrupts

kernel_64:
	mov ax, 0x1700			; show blue boot screen
	call sub_clear_screen
	mov byte [0x00000000000b8000], ':'
	mov byte [0x00000000000b8002], '-'
	mov byte [0x00000000000b8004], ')'
	jmp $
	mov esi, msg_kernel_boot
	call sub_printl
	cmp dword [kernel_magic], 0xcaccaac0	; make sure whole kernel loaded
	je magic_ok
	mov esi, msg_kernel_bad_magic
	call sub_prints
	mov esi, [kernel_magic]
	mov cx, 4
	call sub_printhexs
	call sub_newl
	magic_ok:
	mov esi, msg_kernel_booted
	call sub_printl
	jmp kernel_panic
	
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

; Update cursor to VGA

sub_updatecursor:
	push rax
	push rcx
	push rdx
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
	pop rdx
	pop rcx
	pop rax
	ret

; Flush current text buffer to VGA
sub_flush:
	pushf
	push rcx
	mov ecx, 4000
	mov esi, console_buffer
	mov edi, 0xb8000
	cld
	rep movsb
	call sub_updatecursor
	pop rcx
	popf
	ret

; Clear textmode screen, AX=0x1700 for standard color
sub_clear_screen:
	push rax
	push rcx
	push rdi
	mov edi, console_buffer				; clear screen buffer
	mov ecx, 2000
	rep stosw
	xor ecx, ecx					; move cursor to 0,0
	mov [console_cursor], ecx
	pop rdi
	pop rcx
	pop rax
	call sub_flush
	ret

sub_scroll_line:
	push rax
	push rcx
	push rsi
	push rdi
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
	pop rdi
	pop rsi
	pop rcx
	pop rax
	ret

; Goto beginning of next line
sub_newl:
	pushf
	push rax
	push rbx
	push rcx
	push rdx
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
	pop rdx
	pop rcx
	pop rbx
	pop rax
	popf
	call sub_flush
	ret

; Print char
; AL=char
sub_printc:
	push rbx
	push rsi
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
	pop rsi
	pop rbx
	ret

; Print string
; ESI=string start
sub_prints:
	pushf
	push rax
	push rsi
	sub_prints_next:
	mov al, [esi]
	cmp al, 0
	je sub_prints_done
	call sub_printc
	inc esi
	jmp sub_prints_next
	sub_prints_done:
	pop rsi
	pop rax
	popf
	ret

; Print string and newline
; ESI=string start
sub_printl:
	call sub_prints
	call sub_newl
	ret

; Print hex nibble
; AL=nibble
sub_printhexnib:
	push rax
	and al, 0x0f
	cmp al, 0x0a
	jge sub_printhexnib_letter
	add al, '0'
	jmp sub_printhexnib_move
sub_printhexnib_letter:
	add al, 'a'-0x0a
sub_printhexnib_move:
	call sub_printc
	pop rax
	ret

; Print hex char (byte)
; AL=byte
sub_printhexc:
	push rax
	push rdx
	mov dl, al
	shr al, 4
	call sub_printhexnib
	mov al, dl
	call sub_printhexnib
	pop rdx
	pop rax
	ret

; Print hex string
; SI=data
; CX=len
sub_printhexs:
	push rcx
	push rsi
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
	pop rsi
	pop rcx
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

align 8
idt32_desc:				; Interrupt Descriptor Table info
	dw 0x0000			; IDT length (16-bit)
	dd 0x00000000			; IDT location (32-bit)

align 8
gdt32:
gdt32_null:
	dq 0x0000000000000000		; null segment

KERNEL32_CODE16 equ $-gdt32
gdt32_code16:				; 16-bit code segment with base 0x00000000 limit 0xfffff * 4kb = 4GB
	dw 0xffff			; segment limiter bits 0-15
	dw 0x0000			; base address bits 0-15
	db 0x00				; base address bits 16-23
	db 10011010b			; present(1), privilege(00), data/code(1), code(1), conform(0), readable(1), access(0)
	db 10001111b			; granularity(1), 32bitmode(1) reserved(0), prog(0), segment limiter bits 16-19 (1111)
	db 0x00				; base address bits 24-31

KERNEL32_CODE32 equ $-gdt32
gdt32_code32:				; 32-bit code segment with base 0x00000000 limit 0xfffff * 4kb = 4GB
	dw 0xffff			; segment limiter bits 0-15
	dw 0x0000			; base address bits 0-15
	db 0x00				; base address bits 16-23
	db 10011010b			; present(1), privilege(00), data/code(1), code(1), conform(0), readable(1), access(0)
	db 11001111b			; granularity(1), 32bitmode(1) reserved(0), prog(0), segment limiter bits 16-19 (1111)
	db 0x00				; base address bits 24-31


KERNEL32_DATA equ $-gdt32
gdt32_data:				; Data segment with base 0x00000000 limit 0xfffff * 4kb = 4GB
	dw 0xffff			; segment limiter bits 0-15
	dw 0x0000			; base address bits 0-15
	db 0x00				; base address bits 16-23
	db 10010010b			; present(1), privilege(00), data/code(1), data(0), direction(0), writable(1), access(0)
	db 11001111b			; granularity(1), 32bitmode(1), reserved(0), prog(0), segment limiter bits 16-19 (1111)
	db 0x00				; base address bits 24-31

gdt32_end:

align 8
gdt32_desc:				; Global Descriptor Table info
	dw gdt32_end - gdt32 - 1	; GDT32 length (16 bit)
	dd gdt32			; GDT32 location (32 bit)

align 8
idt64_desc:				; Interrupt Descriptor Table info
	dw 0x0000			; IDT length (16-bit)
	dq 0x0000000000000000		; IDT location (64-bit)

align 8
gdt64:
gdt64_null:
	dq 0x0000000000000000		; null segment

KERNEL64_CODE equ $-gdt64
gdt64_code:				; Code segment
	dw 0x0000			; segment-limit-15-0
	dw 0x0000			; base-address-15-0
	db 0x00				; base-address-23-16
	db 10011000b			; P(1), DPL(00), always(11), C(0), R(0), A(0), base-address-23-16(0)
	db 00100000b			; G(0), CS.D(0), CS.L(1), AVL(0), segment-limit-19-16(0)
	db 0x00				; base-address-31-24

KERNEL64_DATA equ $-gdt64
gdt64_data:				; Data segment
	dw 0x0000			; segment-limit-15-0
	dw 0x0000			; base-address-15-0
	db 0x00				; base-address-23-16
	db 10010000b			; P(1), DPL(00), always(10), C(0), R(0), A(0), base-address-23-16(0)
	db 00000000b			; G(0), CS.D(0), CS.L(0), AVL(0), segment-limit-19-16(0)
	db 0x00				; base-address-31-24

gdt64_end:
gdt64_desc:
	dw gdt64_end - gdt64 - 1	; 64-bit Global Descriptor Table info
	dq gdt64

times 20480-4 - ($-$$) db 0		; pad to 20kb - 2 bytes
kernel_magic dd 0xcaccaac0		; add kernel magic at end
kernel_length equ (($-kernel_header)/512)+2	; calculate kernel length macro

; Paging table data area, not loaded into memory, just reserved.
; These tables must be 4kb aligned in memory

align 4096
pml4_table:				; Page Map Level 4 Table (loc 0x0d000)
times 512 dq 0				; 512 x 64-bit entries (initialized in code)

align 4096
pdp_table:				; Page Directory Pointer Table (loc 0x0e000)
times 512 dq 0				; 512 x 64-bit entries (initialized in code)

align 4096
page_directory:				; Page Directory (loc 0x0f000)
times 512 dq 0				; 512 x 64-bit entries (initialized in code)

align 4096
identity_table:				; Identity Page Pable (loc 0x10000)
times 512 dq 0				; 512 x 64-bit entries (initialized in code)


; Pad to 10MB
times 10079*1024 + 512 - ($-$$) db 0

