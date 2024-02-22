org 0
bits 16

%define ENDL 0x0D, 0x0A

start:
    mov si, msg_hello
    call puts

    cli
    hlt

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

msg_hello: db 'Hello, World!', ENDL, 0