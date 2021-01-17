;
; Z80 WeirDOS 0.4
;
; bsect.asm
;
; Boot sector for FAT12 or FAT16 volumes
;
; Assumes 512 bytes-per-sector
;
; Accesses hardware directly. Will need to be modified depending
; on system hardware.
;
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

ENTRY	equ	07C00h		; Location of boot code
SYSTEM	equ	0100h		; Load system to here
FATTYPE	equ	12		; 12 or 16
SECSIZE	equ	512		; Physical sector size
PBYTES	equ	1440*512	; Number of bytes in partition
ALSIZE	equ	1024		; Allocation size
RESERV	equ	1		; Reserved sectors (from start of partition)
NUMFATS	equ	2		; Number of FATs
ROOTENT	equ	512		; Number of root directory entries
PSECTS	equ	PBYTES/SECSIZE	; Sectors in partition
MEDIA	equ	REMOV		; FIXED or REMOV (removable) media type
FATSIZ	equ	(PSECTS*FATTYPE)/(ALSIZE*8)	; Size in sectors of one FAT
SECPTRK	equ	9		; Sectors per track
NUMHEAD	equ	2		; Number of heads
HIDDSEC	equ	0		; Sectors before start of partition
				; (0 for unpartitioned)
				
DBUFF	equ	ENTRY-512

CRT$DAT	equ	020h	; console data
CRT$ST	equ	021h	; console status
CRT$CTL	equ	021h	; console control

CRT$TXD	equ	01h	; transmit flag mask
CRT$RXD	equ	02h	; receive flag mask

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

FIXED	equ	0F8h
REMOV	equ	0F0h
FALSE	equ	0
TRUE	equ	NOT FALSE
	
	phase	ENTRY
	
	db	0EBh		; 8086 JMP, Z80 XCHG
	jr	boot		; Begin
	
oem:	db	"WDOS0.2 "	; 3
bps:	dw	SECSIZE		; 11
spclus:	db	ALSIZE/SECSIZE	; 13
begin:	dw	RESERV		; 14
fats:	db	NUMFATS		; 16
roots:	dw	ROOTENT		; 17
	if	PSECTS GT 65535
	dw	0		; 19
	else
	dw	PSECTS	; Size in sectors
	endif
	db	MEDIA		; 21
fatlen:	dw	FATSIZ		; 22
spt:	dw	SECPTRK		; 24
heads:	dw	NUMHEAD		; 26
				; 28
offs32:	dw	HIDDSEC AND 0FFFFh
	dw	HIDDSEC / 10000h
	if	PSECTS LT 65536
	dw	0,0		; 32
	else
	dw	PSECTS AND 0FFFFh
	dw	PSECTS / 10000h
	endif
	db	080h		; 36 Drive type
	db	0		; 37 Reserved
	db	029h		; 38 Extended BPB
	db	01h,23h,45h,67h	; 39 Volume serial number
	db	"NO NAME    "	; 43 Volume name
	db	"FAT",FATTYPE/10+'0',FATTYPE MOD 10 + '0'
	db	"   "

rtsec:	dw	0,0		; Root dir sector (absolute)
datsec:	dw	0,0		; Read from this sector (absolute)
dma:	dw	0		; Write to this address
	
boot:	lxi	sp, DBUFF	; Stack below data buffer
	; First determine where the root directory is
	lhld	fatlen		; Length of single FAT
	xchg			; To DE
	lda	fats		; Number of FATs to B
	mov	b, a
	lxi	h, 0
mult:	dad	d		; Add DE B times
	djnz	mult
	xchg			; Total to DE
	lhld	begin		; Add reserved
	dad	d
	xchg
	lhld	offs32		; Get partition start offset
	dad	d
	shld	rtsec
	push	h		; Keep low sector
	lhld	offs32+2	; Add the carry
	lxi	d, 0
	dadc	d
	shld	rtsec+2
	xchg			; HL (high sector) to DE
	lxi	h, DBUFF	; Initialize destination address
	shld	dma
	pop	h		; Low sector to HL
	call	read
	lxi	d, rderr
	jnz	hang
	; Determine entry for system file
	lxi	h, DBUFF
	lxi	d, osname
	mvi	b, 11		; 11 characters to compare
cmpl:	ldax	d
	cmp	m
	jnz	nfound
	inx	d
	inx	h
	djnz	cmpl
	; System file exists
	lxi	d, 15		; Increment HL to first FAT cluster
	dad	d
	mov	e, m		; DE becomes first FAT cluster
	inx	h
	mov	d, m
	dcx	d		; Subtract 2
	dcx	d
	lda	spclus		; Sectors per cluster
	mov	b, a		; To B to count
	lxi	h, 0		; clear accumulator (16 bit)
sectl:	dad	d
	djnz	sectl
	push	h		; Keep offset in data region
	; Add the root directory offset and root size
	lhld	roots		; Root entries (usually 512)
	mvi	b, 4		; Divide by 16 (512 bytes / 32 entries = 16)
shiftl:	ora	a		; Clear carry
	mov	a, h
	rra
	mov	h, a
	mov	a, l
	rra
	mov	l, a
	djnz	shiftl
	xchg
	lhld	rtsec
	dad	d
	shld	datsec		; Data sector to load from
	lxi	d,0
	lhld	rtsec+2
	dadc	d
	shld	datsec+2
	mvi	b, 10		; TODO: Fix to calculate sectors to load
	lxi	h, SYSTEM	; Load to here
	shld	dma
	lhld	datsec
	lded	datsec+2
load:	push	b
	call	read
	pop	b
	lxi	d, rderr
	jnz	hang
	lda	dma+1		; Load high byte of DMA
	adi	2		; Increment by 2*256=512
	sta	dma+1
	lhld	datsec
	lded	datsec+2
	inx	h
	shld	datsec
	djnz	load
	jmp	SYSTEM
	
nfound:	lxi	d, nberr
hang:	in	CRT$ST
	ani	CRT$TXD
	jz	hang
	ldax	d
	inx	d
	ora	a
	jz	halt
	out	CRT$DAT
	jmp	hang

halt:	hlt
	
	; Extract C/H/S from absolute address
read:	ora	l		; Don't divide by zero
	ora	h
	jrnz	chs16
	inr	a		; DE (cyl), C (head) = 0, A (sect) = 1
	jr	rread
chs16:	lda	spt		; Get sector count from DPB
	call	div16 		; Divide 16-bit LBA by SPT
	inr	a		; A contains sector on track
	push	psw
	lda	heads		; Divide LBA/SPT again by heads
	call	div16
	mov	c, a		; move head to C (remainder in A)
	pop	psw		; Restore sector 
rread:	out	FD$SEC
	xra	a
	ora	c		; Head
	mvi	a, TB$DENS	; double density
	jrz	seek1
	mvi	a, TB$DENS OR TB$SIDE
seek1:	out	FD$CTRL		; Set side
	mov	a, l		; seek to L (cylinder)
	out	FD$DATA
fdwait:	in	FD$STAT
	ani	FD$BUSY
	jrnz	fdwait
	mvi	a, FD$SEEK
	out	FD$CMD
	lxi	b, FD$DATA	; B = 0 (counts 256) C = port
	mvi	a, FD$READ
	lhld	dma
	out	FD$CMD
rdwait:	in	FD$STAT
	ani	FD$DRQ
	jrz	rdwait
	inir			; Read 512 bytes
	inir
	xra	a
	ret

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

rderr:	db	"Error loading system",0
nberr:	db	"System not found",0
osname:	db	"WDOS    SYS"

	defs	100		; Calculated manually argh
	dw	0AA55h
	end
	
