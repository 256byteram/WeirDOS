;
; Z80 WeirDOS 0.4
;
; bios.asm
;
; BIOS for WeirDOS on the Z80 Emulator.
;
; A Disk Operating System for Z80 microcomputers, implementing
; the CP/M 2.2 API and FAT12/FAT16 filesystems.
;
; Coptright (C) 2021 Alexis Kotlowy
;
; This file is part of WeirDOS (aka WDOS)
;
; WeirDOS is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; WeirDOS is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with WeirDOS.  If not, see <https://www.gnu.org/licenses/>.
;

	maclib	Z80

MEMTOP	equ	64	; Top of addressable memory (up to 64k)
TOTAL	equ	2	; Total number of drives in system

FALSE	equ	0
TRUE	equ	NOT FALSE

REAL	equ	TRUE	; True to build the disk version
			; False for bootstrapping version


ROMBIOS	equ	0FFF8h	; Entry to ROM BIOS
DOSORG	equ	(MEMTOP-8)*1024
BIOS	equ	(MEMTOP-4)*1024
USRFCB	equ	05Ch

WARM	equ	00h
IOBYTE	equ	03h
CDISK	equ	04h	;current disk number
WDOS	equ	05h

DPBSIZ	equ	49	; Size in bytes of each DPB
;
LF	equ	10
CR	equ	13

CRT$DAT	equ	020h	; console data
CRT$ST	equ	021h	; console status
CRT$CTL	equ	021h	; console control
TTY$DAT	equ	024h
TTY$ST	equ	025h
TTY$CTL	equ	025h

CRT$TXD	equ	01h	; transmit flag mask
CRT$RXD	equ	02h	; receive flag mask
TTY$TXD	equ	01h	; transmit flag mask
TTY$RXD	equ	02h	; receive flag mask

FD$CMD	equ	008h	; WD177x command
FD$STAT	equ	008h	; status
FD$TRK	equ	009h	; track
FD$SEC	equ	00Ah	; sector
FD$DATA	equ	00Bh	; data
FD$CTRL	equ	00Ch	; Tarbell control port for FDC

; FDC commands 
FD$REST	equ	008h
FD$SEEK	equ	018h
FD$STEP	equ	028h
FD$SIN	equ	048h
FD$SOUT	equ	068h
FD$READ	equ	088h
FD$WRIT	equ	0A8h
FD$WTRK	equ	0F0h
FD$IRQ	equ	0D0h
; FDC status register
FD$BUSY	equ	001h
FD$DRQ	equ	002h
FD$LOST	equ	004h
FD$CRC	equ	008h
FD$RNF	equ	010h
FD$REC	equ	010h
FD$WF	equ	020h
FD$RT	equ	040h
FD$WP	equ	040h
FD$NR	equ	080h
; Tarbell control port
TB$DENS	equ	008h
TB$DS0	equ	010h
TB$DS1	equ	020h
TB$SIDE	equ	040h
TB$DRQ	equ	080h

; Fixed disk ports
HD$LOW	equ	0C8h	; low byte of parameter
HD$HIGH	equ	0C9h	; high byte of parameters
HD$REG	equ	0CAh	; Register select

; Fixed disk registers
HD$CMD	equ	000h	; Command (8-bit)
HD$STAT	equ	008h	; Status (8-bit)
HD$EX1	equ	009h	; Extended Status 1 (8-bit)
HD$EX2	equ	00Ah	; Extended Status 2 (8-bit)
HD$DMA	equ	010h	; DMA address (16-bit)
HD$BANK	equ	011h	; DMA bank (8-bit)
HD$SEL	equ	018h	; Drive select (8-bit)
HD$CLK	equ	019h	; Clock speed select HD/8"/5"/3" (8-bit)
HD$CYL	equ	020h	; Cylinder select (16-bit)
HD$HEAD	equ	021h	; Head select (8-bit)
HD$TRK	equ	022h	; Track select (16-bit)
HD$DEN	equ	023h	; Density select (8-bit)
HD$SECT	equ	024h	; Sector select (16-bit)

; Fixed disk commands
HD$NULL	equ	080h	; NULL command (CHS enabled)
HD$READ	equ	0C1h	; Read command (CHS, ignore common memory start)
HD$WRIT	equ	0C2h	; Write command

; DPB offsets
DPB$SIZ	equ	49	; Size in bytes of each DPB
DPB$OFF	equ	11	; Offset in bytes of DPB from start of sector
DPB$BPS equ	0	; Bytes per sector
DPB$SPC	equ	2	; Sectors per cluster
DPB$RLS	equ	3	; Reserved logical sectors
DPB$NF	equ	5	; Number of FATs
DPB$RD	equ	6	; Root directory entries
DPB$TLS	equ	8	; Total logical sectors
DPB$MD	equ	10	; Media descriptor
DPB$LSF	equ	11	; Logical sectors per FAT
DPB$SPT	equ	13	; Physical sectors per track
DPB$HD	equ	15	; Number of physical heads

	phase	bios

	jmp	boot		; cold start
wboote	jmp	wboot		; warm start
	jmp	const		; console status
	jmp	conin		; console character in
	jmp	conout		; console character out
	jmp	list		; list character out
	jmp	punch		; punch character out
	jmp	reader		; reader character out
	jmp	seldsk		; select disk
	jmp	seek		; Seek to LBA
	jmp	read		; read disk
	jmp	write		; write disk
	jmp	listst		; return list status

driver	dw	adrv, bdrv		; Points to available drivers

;adrv	dw	fsel, fseek, fread, fwrite	; Routine table for floppy drive
adrv	dw	hsel, hseek, hread, hwrite	; Routine table for hard drive
bdrv	dw	hsel, hseek, hread, hwrite	; Routine table for hard drive

current	dw	adrv			; Current drive table in use

boot	lxi	sp, bstack
	xra	a
	sta	CDISK		; select disk zero
	mvi	a, 001h		; Init IOBYTE
	sta	IOBYTE
	lxi	d, bmesg
	call	print
	
	; Reset the WDOS vectors, load shell.
wboot	mvi	a, 0C3h		; C3 is JMP
	sta	0		; Warm boot vector
	lxi	h, wboote
	shld	1		; Vector
	sta	5
	lxi	h, DOSORG
	shld	6
	mvi	c, 0		; Terminate through WDOS
	jmp	WDOS

const	lda	IOBYTE
	ani	003h
	jz	serst		; Serial status
	jmp	crtstat		; Else CRT status

conin	lda	IOBYTE
	ani	003h
	jz	serin		; Serial port
	jmp	crtin		; Or console

conout	lda	IOBYTE
	ani	003h
	jz	serout		; Serial port
	jmp	crtout		; Or console

list:	lda	IOBYTE
	ani	0C0h
	jz	serout
	jmp	crtout

listst	lda	IOBYTE
	ani	0C0h
	jz	serst
	jmp	crtstat

punch	lda	IOBYTE
	ani	030h
	jz	serout
	jmp	crtout

reader	lda	IOBYTE
	ani	00Ch
	jz	serin
	;jmp	crtin

; Device drivers follow

; CRT input from keyboard
crtin	in	CRT$ST
	and	CRT$RXD
	jz	crtin
	in	CRT$DAT
	ret
	
; CRT keyboard status
crtstat	in	CRT$ST
	and	CRT$RXD
	ret

; CRT output
crtout	in	CRT$ST
	ani	CRT$TXD
	jz	crtout
	mov	a, c
	out	CRT$DAT
	ret

; Serial input
serin	in	TTY$ST
	ani	TTY$RXD
	jz	serin
	in	TTY$DAT
	ret
	
; Serial input status
serst	in	TTY$ST
	and	TTY$RXD
	ret

; Serial output
serout	in	TTY$ST
	ani	TTY$TXD
	jz	serout
	mov	a, c
	out	TTY$DAT
	ret

	; Print a null-terminated string from DE
print	ldax	d
	inx	d
	ora	a
	rz
	push	d
	mov	c, a
	call	conout
	pop	d
	jmp	print


	; Dispatch for select disk
seldsk	lhld	current
	lxi	d, 0		; Entry 0
	jr	go


	; Seek routine dispatch
seek:	push	d		; Push LBA to stack (DE and HL are clobbered)
	push	h
	lhld	current		; Current driver table
	lxi 	d, 2		; Entry 1
	jr	go
	
	; Read routine dispatch
read:	lhld	current		; Current driver table
	lxi	d, 4		; Entry 2
	jr	go

	; Write routine dispatch
write:	lhld	current		; Current driver table
	lxi	d, 6		; Entry 3
	;jr	go	
	; Fall through

go	dad	d
	mov	e, m		; Get the address of seek routine
	inx	h
	mov	d, m
	xchg			; Go
	pchl

	;
	; SELDSK selects a new device to access
	; Should check for media if removable
	;
	; Enters with: C = disk to select
	; Returns with: HL = 00 if disk doesn't exist
	;                    or address of DPB location
	;
	
hsel	mvi	a, HD$CMD	; Send a NULL command to the controller
	out	HD$REG
	mvi	a, HD$NULL
	out	HD$LOW

	mvi	a, HD$SEL
	out	HD$REG
	mov	a, c		; Select correct disk
	out	HD$LOW
	
	mvi	a, HD$CMD	; Send a NULL command to the controller
	out	HD$REG
	mvi	a, HD$NULL
	out	HD$LOW
	; Fall through to DPB calculation
	
	; Calculate DPB buffer address
fsel	lxi	h, 0		; Default error state
	mov	a, c
	cpi	TOTAL		; Total drives in BIOS
	rnc			; Invalid drive
	
	lxi	h, driver
	lxi	d, 2		; 2 bytes per entry
.l1	ora	a		; Compare to 0 at start of loop
	jrz	.sel1
	dcr	a		; Decrement count
	dad	d		; Increment pointer
	jr	.l1
	
.sel1	mov	a, m		; Get the address table pointed to
	inx	h
	mov	h, m
	mov	l, a
	shld	current		; Store as current
	
	mov	a, c		; Current disk in acc
	lxi	h, dpbtab	; Start here
	lxi	d, DPBSIZ	; Increment by this much
.l2	ora	a
	jrz	.sel2
	dcr	a
	dad	d
	jr	.l2

.sel2	shld	curdpb		; Store for CHS conversion
	ret


	;
	; Floppy drive seek to LBA sector on stack
	;
fseek	pop	h		; Pop DEHL address off stack from dispatch
	pop	d
	call	tochs
	out	FD$SEC
	xra	a
	ora	c		; Head
	mvi	a, TB$DENS	; double density
	jrz	fseek1
	mvi	a, TB$DENS OR TB$SIDE
fseek1	out	FD$CTRL		; Set side
	mov	a, l		; seek to L (cylinder)
	out	FD$DATA
	call	fdwait
	mvi	a, FD$SEEK
	out	FD$CMD
	xra	a
	ret

	;
	; Wait for FDC to become available;
	;
fdwait:	in	FD$STAT
	ani	FD$BUSY
	jrnz	fdwait
	ret
	
	
	; Floppy drive read
	;
	; Read absolute sector to a local buffer, return
	; with that buffer address.
	;
	; Enters with: A = 0 = data buffer. 1 = FAT buffer
	;            
	; Returns with: A = 0 for no error, 1 on error
	;               HL = address of buffer
	;
	; Buffer size needs to accommodate a single sector.
	; WDOS assumes 512-byte media but can be expanded to use
	; the size indicated in the DPB (TODO).
fread:	call	getbuf
	push	h

	call	fdwait
	lxi	b, FD$DATA	; B = 0 (counts 256) C = port
	mvi	a, FD$READ
	out	FD$CMD
rdwait:	in	FD$STAT
	mov	d, a		; Hold I/O read in D temporarily
	ani	FD$RNF OR FD$NR	; error?
	mvi	a, 1		; Jump on error with A set
	jrnz	rdx
	mov	a, d
	ani	FD$DRQ
	jrz	rdwait
	inir			; Read 512 bytes
	inir
	xra	a		; No error
rdx:	pop	h
	ret
	
	; Floppy drive write
	;
	; Write sector to currently selected drive.
	; Seek needs to be called before hand.
	;
	; Enters with: A = 0 = data buffer, 1 = FAT buffer
	;
	; Returns with: A = 0 no error, 1 = error, 2 = read-only
	;
	; 
fwrite	call	getbuf
	push	h
	
	call	fdwait
	lxi	b, FD$DATA	; B = 0, C = port
	mvi	a, FD$WRIT
	out	FD$CMD
wrwait:	in	FD$STAT
	mov	d, a
	ani	FD$WP		; Write protect?
	mvi	a, 2
	jrnz	wrx
	mov	a, d
	ani	FD$RNF OR FD$NR	; Other error?
	mvi	a, 1	
	jrnz	wrx
	mov	a, d
	ani	FD$DRQ
	jrz	wrwait
	outir			; Write 512 bytes
	outir
	xra	a
wrx:	pop	h
	ret

	; Determine what buffer to store data to
getbuf	lxi	h, datab
	ora	a
	rz
	lxi	h, fatb
	xra	a
	ret


	;
	; Fixed drive seek to LBA sector on stack
	;
hseek	pop	h		; Pop DEHL address off stack from dispatch
	pop	d
	call	tochs		; Returns: Cyl in HL, sector in A, head in C
	mov	b, a
	
	mvi	a, HD$CYL	; Select cylinder register
	out	HD$REG
	mov	a, l
	out	HD$LOW
	mov	a, h
	out	HD$HIGH
	
	mvi	a, HD$HEAD	; Select head register
	out	HD$REG
	mov	a, c
	out	HD$LOW
	
	mvi	a, HD$SECT	; Select sector register
	out	HD$REG
	mov	a, b
	out	HD$LOW
	
	xra	a
	ret
	
	; Fixed drive read
	;
	; Read absolute sector to a local buffer, return
	; with that buffer address.
	;
	; Enters with: A = 0 = data buffer. 1 = FAT buffer
	;            
	; Returns with: A = 0 for no error, 1 on error
	;               HL = address of buffer
	;
	; Buffer size needs to accommodate a single sector.
	; WDOS assumes 512-byte media but can be expanded to use
	; the size indicated in the DPB (TODO).
hread:	call	getbuf
	mvi	a, HD$DMA	; Set DMA address
	out	HD$REG
	mov	a, l
	out	HD$LOW
	mov	a, h
	out	HD$HIGH
	mvi	a, HD$CMD
	out	HD$REG
	mvi	a, HD$READ
	out	HD$LOW
	
	mvi	a, HD$STAT
	out	HD$REG
	in	HD$LOW
	ora	a
	ret
	
	; Fixed drive write
	;
	; Write sector to currently selected drive.
	; Seek needs to be called before hand.
	;
	; Enters with: A = 0 = data buffer, 1 = FAT buffer
	;
	; Returns with: A = 0 no error, 1 = error, 2 = read-only
	;
	; 
hwrite	call	getbuf
	mvi	a, HD$DMA	; Set DMA address
	out	HD$REG
	mov	a, l
	out	HD$LOW
	mov	a, h
	out	HD$HIGH
	mvi	a, HD$CMD
	out	HD$REG
	mvi	a, HD$WRIT
	out	HD$LOW
	
	mvi	a, HD$STAT
	out	HD$REG
	in	HD$LOW
	ora	a
	ret


; Convert LBA to CHS
; Requires: LBA in DEHL
; Returns: Cyl in HL, sector in A, head in C
;
; CYL = LBA / SPT / HEADS
; HEAD = (LBA / SPT) MOD HEADS
; SECT = LBA MOD SPT
;
tochs:	mov	a, e
	ora	d
	jrnz	tochs32
	; 16-bit division because of 16-bit LBA (quicker)
	mov	a, l		; Don't divide by zero
	ora	h
	jrnz	chs16
	mov	c, a		; C = 0
	inr	a		; DE (cyl), C (head) = 0, A (sect) = 1
	ret
chs16:	pushix
	lixd	curdpb
	ldx	a, DPB$SPT	; Get sector count from DPB
	call	div16 		; Divide 16-bit LBA by SPT
	inr	a		; A contains sector on track
	push	psw
	ldx	a, DPB$HD	; Divide LBA/SPT again by heads
	call	div16
	mov	c, a		; move head to C (remainder in A)
	pop	psw		; Restore sector 
	popix
	ret
	
	
tochs32:
	halt
	jmp	tochs32

; Divide HL by A, remainder in A. Saves BC
;
div16:	push	bc
	mov	c, a
	xra	a
	mvi	b, 16
div16l:	dad	h
	ral
	jrc	$+5
	cp	c
	jrc	$+3
	sub	c
	inr	l
	djnz	div16l
	pop	bc
	ret
	
		
; Divide DEHL by A.
; Remainder in A
div32:	;push	bc
	mov	c, a
	xra	a
	mvi	b, 32
div32l:	dad	h
	ralr	e
	ralr	d
	ral
	jrc	$+5
	cmp	c
	jrc	$+3
	sub	c
	inc	l
	djnz	div32l
	;pop	bc
	ret

;
;
; Debug
;
;
	ifdef   DEBUG
prreg	push	h
	push	d
	push	b
	push	psw
	
	lxi	h,1
	dad	sp
	mvi	b, 8	; Print stack
prrl	mov	a, m
	call	phex
	mov	a, b	; Print a space every other digit
	ani	1
	jz	prrl1
	mvi	c, ' '
	call	conout
	lxi	d, 4
	dad	d
prrl1	dcx	h
	djnz	prrl

	mvi	c, LF
	call	conout
	mvi	c, CR
	call	conout

	pop	psw
	pop	b
	pop	d
	pop	h
	ret	
	
	; Print A as a two digit hexadecimal number
phex	push	psw		; Will use A twice
	rar			; Shift upper to lower nibble
	rar
	rar
	rar
	call	phex1		; Print it
	pop	psw		; Restore original Acc
phex1	ani	00Fh		; Mask off high nibble
	adi	090h		; Decimal adjust for ASCII
	daa
	aci	040h
	daa
	mov	c, a		; Print it
	jmp	conout
	endif
	
	if	NOT REAL
	; Default FCB to load
fcbi	db	0,'           '
	dw	0,0
	db	0,'           ',
	dw	0,0,0,0
fcblen	equ	$-fcbi
	endif

	; Boot message
bmesg:
        db	cr		; To start NOTICE on blank line
	incbin	NOTICE.TXT
	db	0
	; Boot stack can overwrite banner
curdpb	dw	0
	; BIOS Stack
	dw	0,0,0,0,0,0,0,0
bstack	equ	$

; Disk Parameter Blocks and buffers
;
; These are left uninitialized and filled by WDOS from
; the current media. 49 bytes need to be allocated per
; drive.
;
	; Data buffers
datab	equ	$	; Data buffer
fatb	equ	datab+512	; FAT buffer
	; The rest of RAM is allocated to DPB blocks
dpbtab	equ	fatb+512
	end
