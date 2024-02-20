org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

start:
    jmp main


;
; Prints a string to the screen
; Parameters:
;   ds:si - pointer to the string
;
puts:
    push si
    push ax

.loop:
    lodsb           ; load the next byte from ds:si into al and increment si
    or al, al       ; set the zero flag if al is zero
    jz .done        ; if al is zero, we are done
    mov ah, 0x0E    ; int 0x10 teletype function which outputs al to the screen
    mov bh, 0x00    ; page number needs to be set to 0
    int 0x10
    jmp .loop

.done:
    pop ax
    pop si
    ret

;
; Main entry point
;
main:
    ; setup data segments
    mov ax, 0x0000
    mov ds, ax  ; data segment is set to 0x0000 because we are in real mode
    mov es, ax  ; extra segment is set to 0x0000 because we are in real mode

    ; setup stack
    mov ss, ax  ; stack segment is set to 0x0000 because we are in real mode
    mov sp, 0x7C00  ; stack grows downwards and starts at 0x7C00 to prevent overwriting bootloader

    mov si, msg_hello
    call puts

    hlt

.halt:
    jmp .halt


msg_hello: 
    db 'Hello, World!', ENDL, 0

times 510-($-$$) db 0
dw 0xAA55