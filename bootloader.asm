; NASM MBR boot loader by Kenneth Falck 2009
[bits 16]				; 16-bit code
[org 0x7c00]				; BIOS loads us at 0x07c0:0000
jmp 0x0000:initialize_bios		; reset code segment to 0x0000 with long jump

KERNELAREA equ 0x0800			; kernel is loaded in memory at 32k

initialize_bios:
	xor ax, ax
	mov ds, ax			; reset data segments to 0x0000
	mov es, ax
	mov [bootdrive], dl		; store boot drive
	mov si, welcome			; print welcome string
	call print
	jmp load_kernel_header		; proceed to load kernel

printc:					; Print char in AL with BIOS
	mov ah, 0x0e			; op 0x0e
	mov bh, 0x00			; page number
	mov bl, 0x07			; color
	int 0x10			; INT 10 - BIOS print char
	ret

print:					; Print string in SI with BIOS
	mov al, [si]
	inc si
	or al, al
	jz exit_function		; end at NUL
	call printc
	jmp print
	exit_function:
	ret

data:
	welcome db 'Loading', 0	; welcome message
	error db 'Error', 0		; error message
	bootdrive db 0x00		; original BIOS boot drive

load_kernel_header:			; Load first block of kernel into 0x0800:0000
	mov al, '.'
	call printc
	mov ah, 0x02			; read sectors from drive
	mov al, 0x01			; sectors to read
	mov ch, 0x00			; track
	mov cl, 0x02			; sector
	mov dh, 0x00			; head
	mov dl, [bootdrive]		; drive
	mov bx, KERNELAREA
	mov es, bx			; buffer segment
	mov bx, 0			; buffer address
	int 0x13			; INT 13 - BIOS load sector
	jnc load_kernel_code		; on success, load the code
	mov si, error
	call print
	jmp $				; hang after failing

load_kernel_code:			; Load rest of kernel blocks into 0x0800:0200
	mov al, '.'
	call printc
	push ds
	mov bx, KERNELAREA		; print kernel signature
	mov ds, bx
	mov si, 0x0000
	call print
	pop ds
	mov bx, KERNELAREA		; read kernel length from 0x0800:0004
	mov es, bx
	mov al, [es:0x0004]
	dec al
	push ax
	add al, 'A'			; print length for debugging
	call printc
	pop ax
	mov ah, 0x02			; read sectors from drive
	mov ch, 0x00			; track
	mov cl, 0x03			; sector
	mov dh, 0x00			; head
	mov dl, [bootdrive]		; drive
	mov bx, 0x0800
	mov es, bx			; buffer segment
	mov bx, 512			; buffer address
	int 0x13			; INT 13 - BIOS load sector
	jnc boot_kernel_code
	mov si, error
	call print
	jmp $				; hang after failing

boot_kernel_code:
	mov al, '!'
	call printc
	mov dl, [bootdrive]		; store boot drive in dl
	mov ax, 0			; reset data segments
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax
	jmp 0x0000:0x8008		; long jump to kernel boot code

times 510 - ($ - $$) db 0		; filler to 510 bytes
dw 0xaa55				; boot signature (fills to 512 bytes)

