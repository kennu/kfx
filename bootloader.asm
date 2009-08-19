; MBR boot loader
[bits 16]			; 16-bit code
[org 0x7c00]
;jmp 0x07c0:initialize_bios
cli
jmp 0x0000:initialize_bios

; Routines

; Print character with BIOS
PrintCharacter:
	mov ah, 0x0E
	mov bh, 0x00
	mov bl, 0x07
	int 0x10
	ret

; Print string with BIOS
PrintString:
next_character:
	mov al, [si]
	inc si
	or al, al
	jz exit_function
	call PrintCharacter
	jmp next_character
exit_function:
	ret

PrintHexNibble:
	and al, 0x0f
	cmp al, 0x0a
	jge hex_letter
	add al, '0'
	jmp hex_move_on
hex_letter:
	add al, 'a'-0x0a
hex_move_on:
	call PrintCharacter
	ret

PrintHexByte:
	mov dl, al
	shr al, 4
	call PrintHexNibble
	mov al, dl
	call PrintHexNibble
	ret

; Print hex string with BIOS
; SI=data
; CX=len
PrintHex:
	or cx, cx
	jz exit_hex
next_hex:
	mov al, [ds:si]
	call PrintHexByte
	inc si
	dec cx
	jz exit_hex
	jmp next_hex
exit_hex:
	ret

; Goto new line
NewLine:
	mov ah, 0x03			; get cursor pos
	xor bh, bh
	int 0x10
	mov ah, 0x02			; set cursor pos
	xor bh, bh
	inc dh
	xor dl, dl
	int 0x10
	ret

; Print string with newline
PrintLine:
	call PrintString
	call NewLine
	ret

; Data (up to 440 bytes)
WelcomeString db 'Starting from disk ', 0
ErrorString db 'Error: ', 0

BootDrive db 0x00

; Capture some BIOS info
initialize_bios:
	xor ax, ax
	mov ds, ax
	mov es, ax
	mov [BootDrive], dl

; Initialize screen text mode
initialize_screen:

; Show welcome message
show_welcome:
	mov si, WelcomeString
	call PrintString
	mov al, [BootDrive]
	call PrintHexByte
	mov al, ':'
	call PrintCharacter
	mov ax, cs
	shr ax, 8
	call PrintHexByte
	mov ax, cs
	call PrintHexByte
	call NewLine

load_kernel_header:
	; Load kernel header at end of our code
	mov ah, 0x02				; read sectors from drive
	mov al, 0x01				; sectors to read
	mov ch, 0x00				; track
	mov cl, 0x02				; sector
	mov dh, 0x00				; head
	mov dl, [BootDrive]			; drive
	mov bx, ds
	mov es, bx				; buffer address
	mov bx, kernel_header			; buffer address
	int 0x13
	jnc load_kernel_code			; on success, load the code
	mov si, ErrorString
	call PrintString
	mov al, ah
	call PrintHexByte
	jmp $					; hang after failing

load_kernel_code:
	; Load kernel code into 0x1000:0000
	mov ah, 0x02				; read sectors from drive
	mov al, [kernel_header+3]		; sectors to read
	mov ch, 0x00				; track
	mov cl, 0x03				; sector
	mov dh, 0x00				; head
	mov dl, [BootDrive]			; drive
	mov bx, 0x1000
	mov es, bx				; buffer address
	mov bx, 0x0000				; buffer address
	int 0x13
	jnc boot_kernel_code
	mov si, ErrorString
	call PrintString
	mov al, ah
	call PrintHexByte
	jmp $					; hang after failing

boot_kernel_code:
	mov dl, [BootDrive]			; store boot drive in dl

kernel_enter_protected:
	;lidt [idt_desc]				; load IDT
	lgdt [gdt_desc]				; load GDT
	cli
	mov eax, cr0				; set bit 1 of CR0 (protected mode enable)
	or eax, 0x01
	mov cr0, eax
	jmp KERNEL_CODE:boot_32			; long jump to boot, 0x08 = first segment (code) identifier

boot_32:
[bits 32]
	mov ax, KERNEL_DATA
	mov ds, ax				; update proper data segment
	mov es, ax				; update proper alt1 data segment
	mov fs, ax				; update proper alt2 data segment
	mov gs, ax				; update proper alt3 data segment
	mov ss, ax				; update proper stack segment
	mov esp, 0x40000
	jmp KERNEL_CODE:0x10000

align 4

idt_desc:
	dw 0x0000
	dw 0x0000
	dw 0x0000

align 4

gdt:
gdt_null:
	dd 0x00000000				; null segment
	dd 0x00000000

KERNEL_CODE equ $-gdt
gdt_code:					; Code segment with base 0x00000000 limit 0xfffff * 4kb = 4GB
	dw 0xffff				; segment limiter bits 0-15
	dw 0x0000				; base address bits 0-15
	db 0x00					; base address bits 16-23
	db 10011010b				; present(1), privilege(00), data/code(1), code(1), conform(0), readable(1), access(0)
	db 11001111b				; granularity(1), 32bitsize(1) reserved(0), prog(0), segment limiter bits 16-19 (1111)
	db 0x00					; base address bits 24-31

KERNEL_DATA equ $-gdt
gdt_data:					; Data segment with base 0x00000000 limit 0xfffff * 4kb = 4GB
	dw 0xffff				; segment limiter bits 0-15
	dw 0x0000				; base address bits 0-15
	db 0x00					; base address bits 16-23
	db 10010010b				; present(1), privilege(00), data/code(1), data(0), conform(0), readable(1), access(0)
	db 11001111b				; granularity(1), 32bitsize(1), reserved(0), prog(0), segment limiter bits 16-19 (1111)
	db 0x00					; base address bits 24-31

INTERRUPTS equ $-gdt
gdt_interrupts:					; Interrupt segment with base 0x00000000
	dw 0xffff				; segment limiter bits 0-15
	dw 0x1000				; base address bits 0-15
	db 0x00					; base address bits 16-23
	db 10011110b				; present(1), privilege(00), data/code(1), code(1), conform(1), readable(1), access(0)
	db 11001111b				; granularity(1), 32bitsize(1), reserved(0), prog(0), segment limiter bits 16-19 (1111)
	db 0x00					; base address bits 24-31

gdt_end:

gdt_desc:
	dw gdt_end - gdt - 1
	dd gdt

times 510 - ($ - $$) db 0		; filler to 510 bytes

; Boot signature (fills to 512 bytes)
dw 0xaa55

; End of boot sector

kernel_header:
