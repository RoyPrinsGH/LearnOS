org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A


;
; FAT12 header
;
jmp short start
nop
bdb_oem:                    db "MSWIN4.1"
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_number_of_fats:         db 2
bdb_root_entries:           dw 0xE0
bdb_total_sectors:          dw 2880
bdb_media_descriptor:       db 0xF0
bdb_sectors_per_fat:        dw 9
bdb_sectors_per_track:      dw 18
bdb_number_of_heads:        dw 2
bdb_hidden_sectors:         dd 0
bdb_total_sectors_big:      dd 0

;
; Extended boot sector
;
ebr_drive_number:           db 0
ebr_reserved:               db 0
ebr_signature:              db 0x29
ebr_volume_id:              dd 0x12345678
ebr_volume_label:           db 'LEARNOS    '
ebr_file_system:            db 'FAT12   '


start:
    jmp main


;
; Prints a string to the screen
;
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
    mov ds, ax      ; data segment is set to 0x0000 because we are in real mode
    mov es, ax      ; extra segment is set to 0x0000 because we are in real mode

    ; setup stack
    mov ss, ax      ; stack segment is set to 0x0000 because we are in real mode
    mov sp, 0x7C00  ; stack grows downwards and starts at 0x7C00 to prevent overwriting bootloader

    ; read something from disk
    mov [ebr_drive_number], dl
    mov ax, 0x1
    mov cl, 0x1
    mov bx, 0x7E00
    call disk_read

    ; print hello world
    mov si, msg_hello
    call puts

    hlt

floppy_error:
    mov si, floppy_error_msg
    call puts
    jmp wait_for_key

wait_for_key:
    mov ah, 0
    int 0x16
    jmp 0xFFFF:0x0000

.halt:
    cli
    hlt


;;;;;;;;;;;;;;;;;
; Disk routines ;
;;;;;;;;;;;;;;;;;

;
; Converts a logical block address to a CHS address
;
; Parameters:
;   ax - logical block address
;
; Returns:
;   cx [bits 0-5] - sector
;   cx [bits 6-15] - cylinder
;   dh - head
;
lba_to_chs:
    push ax
    push dx

    xor dx, dx                          ; clear dx
    div word [bdb_sectors_per_track]    ; ax = lba / sectors_per_track, dx = lba % sectors_per_track
    inc dx                              ; add 1 to dx to make it 1-based
    mov cx, dx                          ; cx = sector
    xor dx, dx                          ; clear dx
    div word [bdb_number_of_heads]      ; ax = (lba / sectors_per_track) / number_of_heads, dx = (lba / sectors_per_track) % number_of_heads
    mov dh, dl                          ; dh = head
    mov ch, al                          ; ch = cylinder high byte
    shl ah, 6                           ; shift ah left 6 bits
    or  cl, ah                          ; cl = cylinder low byte

    pop ax
    mov dl, al                          ; Restore dl
    pop ax
    ret

;
; Reads a sector from the disk
;
; Parameters:
;   ax - logical block address
;   cl - number of sectors to read
;   dl - drive number
;   es:bx - buffer to read the sector into
;
disk_read:

    push ax
    push bx
    push cx
    push dx
    push di

    push cx
    call lba_to_chs
    pop ax
    mov ah, 0x02        ; int 0x13 read sectors function
    mov di, 3           ; retry count

.retry:
    pusha               ; save all registers
    stc
    int 0x13
    jnc .success

    ; handle error
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    jmp floppy_error

.success:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax

    ret

;
; Resets the disk
;
; Parameters:
;   dl - drive number
;
disk_reset:
    pusha
    mov ah, 0x00        ; int 0x13 reset disk system function
    stc
    int 0x13
    jc floppy_error
    popa
    ret


msg_hello:          db 'Hello, World!', ENDL, 0
floppy_error_msg:   db 'Floppy error', ENDL, 0

times 510-($-$$) db 0
dw 0xAA55