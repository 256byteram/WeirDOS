;
; Z80 WeirDOS 0.4
;
; wdosdisk.asm
;
; Low level disk I/O routines.
;
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

	;
	; Function 0Dh (13)
	;
	; Reset disks.
	;
dreset:	call	dflush		; Flush buffers
	call	fflush
	lxi	h, 0		; Reset all disk flags
	shld	logdsk
	shld	rodsk
	dcx	h
	shld	dsect		; No sector loaded
	shld	dsect+2
	shld	fsect
	shld	fsect+2
	lxi	h, disk		; Set to a nonsense disk
	mvi	m, 0FFh
	ret			; Return without error

	;
	; Function 0Eh (14)
	;
	; Select disk
	;
select: push	d		; Keep E
	mov	c, e		; Select disk in E
	call	seldsk
	pop	d		; Restore E
	mov	a, l		; HL = 0?
	ora	h
	mvi	a, 0FFh		; Return invalid
	rz
	shld	dpbadr
	mov	a, e
	sta	disk		; Pointing at this disk internally
	call	login		; Log new disk in
	lda	disk
	sta	CDISK
	ret

	
	;
	; Function 1Fh (31)
	;
	; Return address of DOS DPB
	;
getdpb:	lhld	dpbadr
	shld	rval
	ret

	

	; Disk read. Flushes currently loaded sectors if needed,
	; reads requested sector of selected partition.
	;
	; Enters with DEHL as 32-bit LBA for sector to read
	; Returns with A non-zero on error
	; Updates [datadr], [fatadr] as necessary
dskrd:	sta	atype		; Keep access type
	lxiy	dsect		; IY points at current sector data
	ora	a
	jrz	.1		; If data, keep pointing at DATA sector
	lxiy	fsect		; Else load FAT sector
.1:	lbcd	poffs		; Current partition offset to BC
	dad	b		; Add to HL
	xchg
	lbcd	poffs+2		; Add high word, carry to DE
	dadc	b
	xchg
	ldy	a, 0
	cmp	l
	jnz	.2
	ldy	a, 1
	cmp	h
	jnz	.2
	ldy	a, 2
	cmp	e
	jnz	.2
	ldy	a, 3
	cmp	d
	jnz	.2
	xra	a
	ret			; No change in sector to load
	
.2:	push	d		; Flush if flagged as written
	push	h
	lda	atype
	ora	a
	cz	dflush		; Flush data or FAT buffers
	lda	atype
	ora	a
	cnz	fflush
	pop	h
	pop	d
	sty	l, 0		; Record new sector loaded
	sty	h, 1
	sty	e, 2
	sty	d, 3
	call	seek		; Seek to that sector
	lda	atype		; Get access type
	call	read		; Read it
	lxi	d, datam	; Load error message if error occured
	ora	a
	cnz	doserr		; Return if error occured
	lda	atype		; Store address depending on access type
	ora	a
	jz	.3		; Store to either data or FAT address
	shld	fatadr
	xra	a		; No error
	ret	
.3:	shld	datadr
	xra	a
	ret

	; Report errors when writing
dskwr:	call	write
	rz			; No error
	lxi	d, ronlym
	cpi	2		; Data error
	jz	doserr		; Report any errors (returns)
	lxi	d, datam
	jmp	doserr
	

	;
	; Disk flush routines.
	;
	; fflush determines if the loaded FAT sector should be
	; written back to disk.
	;
	; dflush is the same for directory and file data.
	;
	;

fflush:	lda	stale		; Is the FAT buffer marked as stale?
	ani	2
	rz			; Return if not
	liyd	dpbadr		; Need to get some data from the DPB
	ldy	b, DPB$NUMFATS	; Get number of FATs to loop
	lhld	fsect		; First sector to DEHL
	lded	fsect+2
	jr	.2
	
.1:	push	b
	ldy	c, DPB$FATSIZE	; Add FATSIZE to current sector
	ldy	b, DPB$FATSIZE+1
	dad	b
	lxi	b, 0
	xchg
	dadc	b
	xchg
	pop	b
	
.2:	push	h
	push	d
	push	b
	call	seek
	mvi	a, 1		; Write FAT
	call	dskwr
	pop	b
	pop	d
	pop	h
	djnz	.1		; Loop for all FATs
	
	lxi	h, stale
	mvi	a, 1		; Mask through data stale flag
	ana	m
	mov	m, a
	ret

	;
	; Directory/file flush
	;
dflush:	lda	stale		; Is the data bufer stale?
	ani	1
	rz			; Return if not
	lhld	dsect
	lded	dsect+2
	call	seek
	xra	a		; Write data
	call	dskwr
	lxi	h, stale
	mvi	a, 2		; Mask through FAT stale flag
	ana	m
	mov	m, a
	ret
	
	

	;
	; Initialize partition information
	;
	;
login:	lxi	h, -1		; Not pointing at any sector on new disk
	shld	dsect
	shld	dsect+2
	shld	fsect
	shld	fsect+2
	lxi	h, 0		; Read first sector
	lxi	d, 0
	shld	poffs		; Clear partition offset
	xra	a
	call	dskrd
	sta	rval
	rnz			; Return with disk error
	lhld	datadr
	mov	a, m		; Get first byte of MBR
	cpi	0EBh		; Should be this if valid
	jrnz	.1		; Else check for partitions
	lxi	d, DPB$OFF	; Point HL to begining of DPB
	dad	d
	lded	dpbadr		; Get DPB location
	lxi	b, DPB$SIZ	; Total size
	ldir
	jr	intdsk		; Return through intdsk

.1:	lxi	d, fmtm		; Format error
	lda	pchkd		; Checked partitions already?
	ora	a
	cnz	doserr
	; Else load first partition. HL contains datadr
	; TODO: Handle multiple partitions
	lxi	d, PART0
	dad	d
	lxi	d, poffs	; Store to partition offset
	lxi	b, 4
	ldir
	mvi	a, 1		; Flag as checked
	sta	pchkd
	jr	login		; Try again
	
	;
	; Initialise data for current medium to memory.
	; - Block Shift Factor
	; - Allocation Shift Factor
	; - FAT region origin
	; - Root directory region origin
	; - Data region origin
	; - FAT12 or FAT16
	;
intdsk:	liyd	dpbadr
	ldy	a, DPB$BYTESPERSEC+1	; bytes-per-sector/256 in A
	mvi	b, 0
.1:	rar
	inr	b		; Count number of shifts in B
	jnc	.1
	lxi	h, bshf		; Block shift factor
	mov	m, b
	ldy	a, DPB$SECPERCLUST	; Get sectors per cluster
	mvi	b, -1		; Count starting at -1, always increments to 0
.2:	rar
	inr	b
	jnc	.2
	lxi	h, ashf		; Allocation shift factor
	mov	m, b
	; Initialize fatsec
	ldy	l, DPB$RESERVEDSEC
	ldy	h, DPB$RESERVEDSEC+1
	shld	fatsec
	push	h		; Keep while calculating FAT size
	; Initialize rtsect
	ldy	e, DPB$FATSIZE
	ldy	d, DPB$FATSIZE+1
	ldy	b, DPB$NUMFATS	; Multiply FATSIZE by NUMFATS
	lxi	h, 0		; Result in HL
.3:	dad	d
	djnz	.3
	pop	d		; Restore fatsec to DE
	dad	d		; Add for rtsect
	shld	rtsect
	push	h		; Keep rtsect
	; Initialize datsec. [bshf] is for shifting 128 byte records to
	; the physical sector size, bshf+2 shifts 32 byte directory entries
	; to physical sector size.
	lda	bshf
	adi	2
	mov	b, a
	ldy	l, DPB$ROOTENTCNT	; Total root entries
	ldy	h, DPB$ROOTENTCNT+1
	shld	dirmax		; Keep it for directory search
.4:	ora	a		; Clear carry
	rarr	h
	rarr	l
	djnz	.4
	; HL contains the number of root directory sectors
	pop	d		; Retrieve rtsect to DE
	dad	d		; Add root directory size
	shld	datsec		; Data region first sector	
	; Initialize volsec for FAT12/16 determination
	; FAT12 is true if (volsiz-datsec)>>ashf < 4085
	lxi	d, 0		; high word 0 by default
	ldy	l, DPB$TOTSEC16
	ldy	h, DPB$TOTSEC16+1
	mov	a, l		; Is the field populated?
	ora	h
	jrnz	.small
	ldy	l, DPB$TOTSEC32
	ldy	h, DPB$TOTSEC32+1
	ldy	e, DPB$TOTSEC32+2
	ldy	d, DPB$TOTSEC32+3
	
.small:	shld	volsiz
	sded	volsiz+2
	push	h		; Keep for FAT type calculation
	push	d
	; Determine how many clusters there are on the disk
	ldy	a, DPB$SECPERCLUST	; Get sectors per cluster
	rar			; Start by shifting. Detects 1 SPC
.5:	jrc	.6		; 
	rarr	d
	rarr	e
	rarr	h
	rarr	l
	ora	a
	rar
	jr	.5
.6:	shld	ctotal		; Save total clusters
	pop	d
	pop	h	
	mov	a, e		; DEHL = 0?
	ora	d		; Also clears carry
	ora	l
	ora	h
	jrnz	.isfat		; Jump if HL!=0 - volume valid
	sta	curfat		; A=0, FAT is uninitialised
	lxi	d, fmtm
	call	doserr
	mvi	a, 2		; Set A for invalid media error
	ora	a		; Set Z flag
	ret
.isfat:	lbcd	datsec
	dsbc	b		; Subtract datsec from volsize
	lxi	b, 0
	xchg
	dsbc	b
	xchg
	
	lda	ashf		; Divide it by ashf
	mov	b, a
.7:	ora	a
	rarr	d
	rarr	e
	rarr	h
	rarr	l
	djnz	.7
	lxi	b, 4085		; Maximum number of clusters in FAT12 volume
	xra	a
	dsbc	b		; Subtract (compare)
	cmc			; 0=FAT12, 1=FAT16
	ral			; Shift carry into cleared accumulator
	inr	a		; 1=FAT12, 2=FAT16
	sta	curfat		
	xra	a
	ret
	
	
	;
	; Select disk from FCB
	; Returns A non-zero on error
	;
selfcb:	ldx	a, FCBDSK	; Get disk to load from
	ora	a		; Zero?
	jnz	.1		; Select the drive in A
	lda	CDISK		; Set to current disk
	inr	a		; Increment for FCB
	stx	a, FCBDSK
.1:	dcr	a		; Decrement for Select
	lxi	h, disk		; Is selected the same as current disk?
	cmp	m
	jrnz	.2		; Need to change the disk
	xra	a		; No error
	ret			; Return if same
	
.2:	push	h
	push	psw
	call	dflush		; Flush old buffers
	call	fflush
	pop	psw
	pop	h
	
	mov	m, a		; Store new disk
	mov	c, a
	call	seldsk		; Select it
	lxi	d, selm		; Select error message
	mov	a, l		; HL = 0?
	ora	h
	cz	doserr		; If so, no device
	shld	dpbadr		; Store DPB address
	jmp	login
	
	
	
