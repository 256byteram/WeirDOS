;
; Z80 WeirDOS 0.4
;
; wdosfile.asm
;
; High level file and directory routines
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
	;
	; Function 0Fh (15)
	;
	; Open file
	;
fopen:	call	search
	rnz
	lded	param		; User FCB as destination
	lhld	dmaadr
	inx	d		; Don't overwrite drive code
	inx	h
	lxi	b, 31		; Copy directory entry from DMA address
	ldir
fopena:	lhld	diridx		; Store directory index to FCB
	stx	l, FCBOF
	mvi	a, 0Fh
	ana	h
	stx	a, FCBFL
	ret
	
	;
	; Function 10h (16)
	;
	; Close file
	;
fclose:	call	selfcb		; Select disk
	sta	rval		; error?
	rnz
	ldx	a, FCBFL	; Flags
	ani	040h		; File changed?
	jz	nochg		; No change
	ldx	l, FCBOF	; File directory entry
	ldx	a, FCBFL	; Flags and high directory entry
	ani	00Fh		; Mask off flags
	mov	h, a		; HL becomes directory entry
	lxi	d, 0		; Shift into DE
	mvi	b, 4		; *16
fclos1:	dad	h
	xchg
	dadc	h
	xchg
	djnz	fclos1
	mov	d, e		; DE=sect/16 i.e. (sect*16)/256
	mov	e, h
	dad	h		; *32
	mvi	a, 1		; Mask through LSB in H
	ana	h
	mov	h, a
	xchg
	lbcd	rtsect		; Directory root sector
	dad	b
	; HL = sector to retrieve
	; DE = offset in sector for directory entry
	push	d		; Root directory only for now...
	lxi	d, 0
	xra	a
	call	dskrd
	pop	d		; Retrieve offset in sector from stack
	lhld	datadr		; Get data address
	dad	d		; Add the two
	xchg
	lhld	param		; Get FCB location
	lxi	b, FCBCL	; Offset to cluster
	dad	b
	xchg
	dad	b		; Also need to offset destination
	xchg
	lxi	b, 6		; 6 bytes to copy
	ldir			; Copy to data area
	lxi	h, stale
	mov	a, m
	ori	1
	mov	m, a
	call	dflush
	call	fflush
nochg:	lhld	param
	lxi	d, FCBEX	; Clear from FCBEX onwards
	dad	d
	mvi	b, 23		; Clear 23 bytes
	
clear:	xra	a
clearl:	mov	m, a
	inx	h
	djnz	clearl
	ret
	
	;
	; Function 11h (17)
	;
	; Search for first directory entry in FCB
	;
search:	call	selfcb		; Select drive from FCB
	lxi	h, 0
	shld	diridx
	lhld	rtsect		; Get current root sector
	shld	dirsec		; Initialize current directory sector
	lxi	h, 0
	shld	dirsec+2
	
	; Finish search with next-entry function
	
	;
	; Function 12h (18)
	;
	; Search for next occurance of file in FCB
	;
	; Returns 
	;
next:	lhld	diridx		; Get current directory number
	lbcd	dirmax		; Compare directory entry maximum
	ora	a
	dsbc	b
	jnc	.nf		; dirmax <= diridx, return
	lhld	diridx		; Get current directory number
	mvi	b, 4		; Divide by 16 to get sector offset
.1:	ora	a		; (16 entries per 512 byte sector)
	rarr	h		; (Change for different sector sizes?)
	rarr	l
	djnz	.1
	lxi	d, 0		; Clear MSW
	lbcd	dirsec		; Current root directory sector
	dad	b
	xchg			; Low sector address to DE
	lbcd	dirsec+2	; Add carry (just in case)
	dadc	b
	xchg			; Low to HL, high to DE
	xra	a		; Load data sector
	call	dskrd
	sta	rval
	rnz			; error
	lda	diridx		; Low byte of current directory to A
	ani	00Fh		; 16 entries per sector
	add	a		; Shift 5 times
	add	a
	add	a
	add	a
	add	a
	mov	l, a		; Becomes low byte offset
	mvi	a, 0		; Add carry to 0
	adc	a
	mov	h, a		; Becomes high byte in offset
	shld	curdir		; Current directory offset in sector
	lded	datadr		; Data buffer address
	dad	d		; Add offset in sector
	; HL now points to the current directory entry
	mov	a, m		; Get first character of entry
	ora	a		; End of directory (byte is zero)
	jrz	.nf		; No further entries are to be found
	cpi	0E5h		; Erased?
	jrz	.erasd		; Go to next entry
	lded	param		; Get FCB to DE to compare
	inx	d		; Point at filename in FCB
	mvi	b, 11		; 11 characters to compare
.nextl:	ldax	d		; Character from FCB
	cpi	'?'		; Ignore?
	jrz	.nxt		; Go to next character
	cmp	m		; Compare to directory entry
	jrz	.nxt		; Match, next character
	; No match, go to next entry
.erasd:	lhld	diridx		; Increment directory entry
	inx	h
	shld	diridx		; Save it
	jmp	next		; And do it again
.nxt:	inx	d		; Next bytes
	inx	h
	djnz	.nextl		; Loop until end of filename
	; Found a match, convert to CP/M directory entry
	call	cnvcpm
	lhld	diridx		; Increment to next entry
	inx	h
	shld	diridx
	xra	a
	ret			; Return with 0
.nf:	ori	0FFh		; No further directory entries
	sta	rval
	ret


	;
	; Function 13h (19)
	;
	; Delete file
	;
delete:	call	search		; Search for the file
	sta	rval
	rnz			; File not found
	lhld	curdir		; Directory offset in in sector
	lded	datadr		; Data buffer
	dad	d
	; Mark DOS entry as deleted
	mvi	m, 0E5h
	lxi	h, stale
	mvi	a, 1		; Set data as stale
	ora	m
	mov	m, a
	ret			; rval already set to 0

	;
	; Function 21h (33)
	; Read random
	;
rdrnd:	call	calcr
	
	;
	;
	; Function 14h (20)
	;
	; Read next record
	;
readn:	call	filrec		; Fill buffer with current record
	sta	rval
	rnz			; Return on error
	lded	dmaadr		; Get DMA address
	lxi	b, 128		; 128 bytes
	ldir			; Copy it
	call	increc		; Increment to next record
	ret
	
	
	;
	; Function 22h (34)
	; Write random
	;
wrrnd:	call	calcr

	; Function 15h (21)
	;
	; Write next record
	;
writen:	call	filrec		; Fill buffer with current record
	jrz	.1		; Jump if not EOF or error
	cpi	1
	sta	rval		; Keep error
	rnz			; Return with error
	call	append
	call	grecrd		; Need to load new record
.1:	xchg			; HL already has destination address
	lhld	dmaadr		; Source is DMA address
	lxi	b, 128		; 128 bytes
	ldir
	lxi	h, stale
	mvi	a, 1
	ora	m
	mov	m, a
	call	increc		; Increment to next record
	call	fgrow		; Grow the file length if needed
	mvi	a, 040h		; Flags
	orx	FCBFL
	stx	a, FCBFL
	xra	a
	sta	rval		; rval may be set to EOF
	ret
	
	;
	; Function 16h (22)
	;
	; Create a file
create:	call	search		; Overwrite existing file or make new file
	lhld	curdir		; Directory offset in in sector
	lded	datadr		; Data buffer
	dad	d
	; Convert FCB to a DOS directory entry
	xchg			; Destination in DE
	lhld	param		; Source is user FCB
	inx	h		; Skip over FCBDSK
	lxi	b, 11		; Copy filename, 11 bytes
	ldir
	mvi	b, 21		; (8-bit clear function)
	call	clrde		; Clear rest of directory entry
	mvi	b, 21		; Initialise user FCB
	call	clrhl
	lda	stale
	ora	1		; Data is stale
	sta	stale
	call	dflush
	xra	a		; No error
	sta	rval		; search also sets rval
	jmp	fopena		; Tidy up FCB and return
	
	
	;
	; Function 17h (23)
	;
	; Rename
	;
rename:	call	search		; Find file to rename
	rnz			; File not found
	lhld	curdir
	lded	datadr
	dad	d		; Address in data buffer of directory entry
	xchg
	lhld	param		; param+16 = name to rename to
	lbcd	16
	dad	b
	mvi	b, 11		; Copy 11 bytes
	ldir
	lhld	stale
	mov	a, m
	ora	1
	mov	m, a
	call	dflush
	xra	a
	sta	rval
	ret
	
	; Function 19h (25)
	;
	; Return current drive in A
cdrive:	lda	CDISK
	sta	rval
	ret
	
	;
	; Function 1Ah (26)
	;
	; Set DMA address
setdma:	sded	dmaadr		; Easy
	ret


	;
	; Function 23h (35)
	;
	; Return record count in FCB
	;
fsize:	ldx	a, FCBLEN+1	; Divide FCBLEN by 128
	ldx	l, FCBLEN+2
	ldx	h, FCBLEN+3
	ora	a		; clear carry
	rarr	h
	rarr	l
	rar
	stx	a, FCBRN
	stx	l, FCBRN+1
	stx	h, FCBRN+2
	ret
	

	;
	; Calculate the CR/EX/S2 data from the random record
	; FCB entry.
	;
calcr:	ldx	a, FCBRN	; First random entry
	ani	07Fh		; 0-127
	stx	a, FCBCR	; Store to CR
	ldx	l, FCBRN	; Bytes 1, 2 to HL
	ldx	h, FCBRN+1
	dad	h		; Shift left 1
	mov	a, h		; A = (Record/128)%256
	ani	01Fh		; %32
	stx	a, FCBEX	; Store to EX
	ldx	l, FCBRN+1	; Bytes 2, 3 to HL
	ldx	h, FCBRN+2
	dad	h
	dad	h
	dad	h
	dad	h
	mov	a, h		; A = (Record/4096)%256
	ani	03Fh		; %64
	stx	a, FCBS2	; S2
	ret


	
	; Grow FCBLEN if the current record pointer is
	; bigger than it.
fgrow:	call	fillen
	ldx	a, FCBLEN
	sub	l
	ldx	a, FCBLEN+1
	sbc	h
	ldx	a, FCBLEN+2
	sbc	e
	ldx	a, FCBLEN+3
	sbc	d
	rnc		; No carry if FCBLEN < current file length
	stx	l, FCBLEN
	stx	h, FCBLEN+1
	stx	e, FCBLEN+2
	stx	d, FCBLEN+3
	ret
	
	
	
	;
	; Calculate the file length in the FCB from the
	; current record being accessed. Result in DE:HL
	;
fillen:	call	calrec		; Get the current record
	; Multiply record by 128
	; First by 256
	mov	d, e
	mov	e, h
	mov	h, l
	mvi	l, 0
	; Then divide by 2
	xra	a
	rarr	d
	rarr	e
	rarr	h
	rarr	l
	ret

	; Convert DOS directory entry to CP/M directory entry
	; at DMA address.
	; Dependant on  [diridx]
cnvcpm:	lded	curdir
	lhld	datadr		; Address of current buffer
	dad	d		; Add them
	lded	dmaadr		; Send to DMA address buffer
	xra	a		; User number is always 0
	stax	d
	inx	d		; DE offs 1
	lxi	b, 11		; Copy 11 characters for filename
	ldir			; DE offs 12
	mvi	b, 4		; Clear extent data
	call	clrde		; DE offs 16
	lda	diridx+1	; High byte of current directory entry
	ori	080h		; Set MSB
	stax	d		; byte 16..18: FL, FL, OF
	inx	d
	stax	d
	inx	d
	lda	diridx
	stax	d
	inx	d		; DE offs 19
	mvi	b, 5		; Clear Current cluster
	call	clrde		; DE offs 24
	; DOS Time, Date, Initial FAT entry, size
	lxi	b, 13		; HL lags by 13 still, update to Time etc
	dad	b
	lxi	b, 8		; Copy 8 bytes (date, clust, size)
	ldir
	mvi	b, 128-32	; Fill remainder of buffer
	mvi	a, 0E5h
	call	fill
	pushix
	lixd	dmaadr		; Point IX at DMA address to
	call	updext		; update extent data and return
	popix			; Restore IX
	ret


	
	;
	; Load CR/EX/S2 and convert to a record number
	; returned in DEHL
	; 
calrec:	ldx	l, FCBCR	; Get CR
	ldx	h, FCBEX	; Get EX
	ldx	e, FCBS2	; Get S2
	xra	a		; Clear carry and A
	rarr	h		; Shift EX right by 1
	rar			; Shift carry to MSB
	ora	l		; Combine with CR
	mov	l, a		; Copy back to L
	mvi	b, 4		; Shift S2 4 times
	xra	a		; Clear carry and A
getshd:	rarr	e		; Shift E to A
	rar
	djnz	getshd
	ora	h		; Combine with EX
	mov	h, a		; Result back to H
	mvi	d, 0		; Nothing in D
	ret

	; Increment to next record.
	; FDBCR incremented mod 128
	; FCBEX carried mod 32
	; FCBS2 carried
	; 20 bits total, so 1M records per file
increc: mvi	a, 127
	inrx	FCBCR
	cmpx	FCBCR		; Overflowed to 128?
	rnc			; If it hasn't, we're done
	mvix	0, FCBCR	; clear it
	mvi	a, 31
	inrx	FCBEX
	cmpx	FCBEX
	rnc
	mvix	0, FCBEX
	inrx	FCBS2
	ret
	
	; Update extent in FCB at IX. 
updext:	ldx	l, FCBLEN+1	; 2nd byte of size
	ldx	h, FCBLEN+2	; 3rd byte
	dad	h		; Shift twice
	dad	h
	mov	a, h		; A = HL / 16384 % 256
	; A contains total extents used by file
	cmpx	FCBEX		; Compare total extents with user's
	jz	xequal		; Extents are equal
	jc	xgthan		; User's is higher
	mvix	128, FCBRC	; Store 128 records in extent
	ret
xgthan:	mvix	0, FCBRC	; 0 records in extent
	ret
xequal:	ldx	l, FCBLEN	; Divide by 128
	ldx	h, FCBLEN+1
	dad	h
	mov	a, h
	inr	a		; Increment, starting at 1
	ani	07Fh		; Mask off MSB
	stx	a, FCBRC	; Store records in this extent
	ret
	
	;
	; Calculate FCB from FCB's random record entry
	;
setrnd:	ldx	l, FCBRN
	ldx	h, FCBRN+1
	ldx	e, FCBRN+2
	mvi	d, 0
	mov	a, l
	ani	07Fh		; Bits 6..0
	stx	a, FCBCR	; Store CR
	dad	h		; Shift bits left
	xchg
	dadc	h
	xchg
	mov	a, h		; Reading bits 7..11
	ani	01Fh		; Bits 4..0
	stx	a, FCBEX	; Store EX
	mvi	b, 3		; Shift 3 times (total of 4)
setrn1:	dad	h
	xchg
	dadc	h
	xchg
	djnz	setrn1
	stx	e, FCBS2	; Store S2
	ret

