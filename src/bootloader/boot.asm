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

;
; Main entry point
;
start:
    ; setup data segments
    mov ax, 0
    mov ds, ax      ; data segment is set to 0x0000 because we are in real mode
    mov es, ax      ; extra segment is set to 0x0000 because we are in real mode

    ; setup stack
    mov ss, ax      ; stack segment is set to 0x0000 because we are in real mode
    mov sp, 0x7C00  ; stack grows downwards and starts at 0x7C00 to prevent overwriting bootloader

    ; some BIOSes might start the disk at 0x7E00
    push es
    push word .after
    retf

.after:
    ; read something from disk
    mov [ebr_drive_number], dl

    ; print loading message
    mov si, msg_loading
    call print_string

    ; read drive parameters
    push es
    mov ah, 8
    int 0x13
    jc floppy_error
    pop es

    and cl, 0x3F    ; clear the high two bits of cl
    xor ch, ch
    mov [bdb_sectors_per_track], cx

    inc dh
    mov [bdb_number_of_heads], dh

    ; read the root directory
    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_number_of_fats]
    xor bh, bh
    mul bx
    add ax, [bdb_reserved_sectors]
    push ax

    mov ax, [bdb_root_entries]
    shl ax, 5
    xor dx, dx
    div word [bdb_bytes_per_sector]

    test dx, dx
    jz .root_dir_after
    inc ax

.root_dir_after:
    mov cl, al
    pop ax
    mov dl, [ebr_drive_number]
    mov bx, buffer
    call disk_read

    ; search for kernel.bin
    xor bx, bx
    mov di, buffer

.search_kernel:
    mov si, file_kernel_bin
    mov cx, 11
    push di
    repe cmpsb
    pop di
    je .kernel_found
    add di, 32
    inc bx
    cmp bx, [bdb_root_entries]
    jl .search_kernel
        
    call debug_print
    ; kernel not found
    jmp floppy_error

.kernel_found:
    mov ax, [di + 26]
    mov [kernel_cluster], ax

    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    call disk_read

    mov bx, KERNEL_LOAD_SEG
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:
    mov ax, [kernel_cluster]
    add ax, 31

    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]

    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx

    mov si, buffer
    add si, ax
    mov ax, [ds:si]

    or dx, dx
    jz .even

.odd:
    shr ax, 4
    jmp .next_cluster_after

.even:
    and ax, 0x0FFF

.next_cluster_after:
    cmp ax, 0xFF8
    jae .read_finished
    mov [kernel_cluster], ax
    jmp .load_kernel_loop

.read_finished:
    mov dl, [ebr_drive_number]
    mov ax, KERNEL_LOAD_SEG
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEG:KERNEL_LOAD_OFFSET

    jmp wait_for_key

    cli
    hlt

floppy_error:
    mov si, msg_floppy_error
    call print_string
    jmp wait_for_key

debug_print:
    push si
    mov si, msg_debug_print
    call print_string
    pop si
    ret

wait_for_key:
    mov ah, 0
    int 0x16
    jmp 0xFFFF:0


;;;;;;;;;;;;;;;;;;;;;
; Standard routines ;
;;;;;;;;;;;;;;;;;;;;;

;
; Prints a string to the screen
;
; Parameters:
;   ds:si - pointer to the string
;
print_string:
    push si
    push ax

.loop:
    lodsb           ; load the next byte from ds:si into al and increment si
    or al, al       ; set the zero flag if al is zero
    jz .done        ; if al is zero, we are done
    mov ah, 0x0E    ; int 0x10 teletype function which outprint_string al to the screen
    mov bh, 0    ; page number needs to be set to 0
    int 0x10
    jmp .loop

.done:
    pop ax
    pop si
    ret


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
    mov ah, 2           ; int 0x13 read sectors function
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
    mov ah, 0           ; int 0x13 reset disk system function
    stc
    int 0x13
    jc floppy_error
    popa
    ret

msg_loading:            db 'Loading LearnOS...', ENDL, 0
msg_floppy_error:       db 'Floppy error', ENDL, 0
msg_debug_print:        db 'Debug print', ENDL, 0
file_kernel_bin:        db 'KERNEL  BIN'
kernel_cluster:         dw 0

KERNEL_LOAD_SEG         equ 0x2000
KERNEL_LOAD_OFFSET      equ 0

times 510-($-$$) db 0
dw 0xAA55

buffer: