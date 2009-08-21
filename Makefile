all:		kfx.vdi

clean:
		@rm -f bootloader.img kernel.img

# Create VDI image from MBR bootsector
kfx.vdi:	bootloader.img kernel.img
		@./mkvdi.sh
		cp kfx.img "/Users/kennu/src/bochs/kfx.img"

# Compile MBR bootsector from assembly
bootloader.img:	bootloader.asm
		@/opt/local/bin/nasm -f bin -o bootloader.img bootloader.asm

# Compile kernel from assembly
kernel.img:	kernel.asm
		@/opt/local/bin/nasm -f bin -o kernel.img kernel.asm
