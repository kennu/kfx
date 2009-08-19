all:		kfx.vdi

clean:
		@rm -f bootloader.img kheader.img kernel.img

# Create VDI image from MBR bootsector
kfx.vdi:	bootloader.img kheader.img kernel.img
		@./mkvdi.sh
		cp kfx.img "/Users/kennu/src/bochs/kfx.img"

# Compile MBR bootsector from assembly
bootloader.img:	bootloader.asm
		@nasm -f bin -o bootloader.img bootloader.asm

# Compile kernel header from assembly
kheader.img:	kheader.asm
		@nasm -f bin -o kheader.img kheader.asm

# Compile kernel from assembly
kernel.img:	kernel.asm
		@nasm -f bin -o kernel.img kernel.asm
