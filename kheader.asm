; KFX kernel header
db 'KFX'			; signature
db 20				; kernel length in blocks = 10kb
times 512 - ($ - $$) db 0	; padding until end of block
