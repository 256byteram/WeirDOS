;
; Z80 WeirDOS 0.4
;
; wdosfat.asm
;
; Low level FAT and cluster routines
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
	; Append a new cluster to the end of the file.
	; 
append:	ldx	c, FCBCUR	; Get current cluster
	ldx	b, FCBCUR+1
	mov	a, c		; Current cluster zero?
	ora	b
	jrnz	.1		; Good to append new cluster
	; start new file
	call	freef		; BC = 0, start search at beginning
	rnz			; Return on disk full
	stx	c, FCBCUR	; Current free cluster to FCB
	stx	b, FCBCUR+1
	stx	c, FCBCL	; Update DOS cluster
	stx	b, FCBCL+1
	
	mov	l, c		; Write -1 to that cluster
	mov	h, b
	jr	.2
	
.1:	push	b		; Keep FCBCUR
	call	freef		; Find next free location after it
	pop	h		; Pop FCBCUR to change it to next cluster
	rnz
	stx	c, FCBCUR	; Current free cluster to FCB
	stx	b, FCBCUR+1
	ldx	a, FCBIDX	; Increment FCBIDX
	adi	1
	stx	a, FCBIDX
	ldx	a, FCBIDX+1
	aci	0
	stx	a, FCBIDX+1
	mov	e, c		; Write new cluster to previous one
	mov	d, b
	push	b		; Keep the new cluster value
	call	setfat
	pop	h		; Write -1 to new cluster
.2:	lxi	d, -1		; Write EOF cluster
	jmp	setfat		; Return through setfat

	;
	; Search for an unused cluster, returned in BC
	;
freef:	lhld	ctotal		; Compare against total clusters in disk
	ora	a
	dsbc	b		; Will leave a carry if disk full
	jrc	.1		; Full
	mov	l, c		; Copy counter to HL
	mov	h, b
	call	getfat		; Get value at that cluster
	mov	a, l		; Is the entry zero?
	ora	h
	rz			; Return with BC if entry is zero
	inx	b		; Next cluster
	jr	freef

.1:	mvi	a, 2		; Disk full
	ora	a		; set flags
	ret
	
	;
	; Fill the data buffer with current sector,
	; Returns HL pointing at the record
	; A non-zero on error (HL won't be valid)
	;
filrec:	call	selfcb		; Select disks
	call	getidx		; Calculate FAT index
	call	gclust		; Get that cluster
	rnz			; Return on EOF
	;jmp	grecrd		; Get record from cluster if not EOF
				; and return
	
	; Load from disk the sector containing the record in [recrd],
	; in the cluster [IX+FCBCUR]. Returns HL containing the buffer
	; address of the requested record.
grecrd:	ldx	l, FCBCUR
	ldx	h, FCBCUR+1
	dcx	h		; Cluster is always offset by 2
	dcx	h
	lda	ashf		; Allocation shift factor
	mov	b, a		; Shift count in B
	lxi	d, 0		; Shift into DE
.1:	dad	h
	xchg
	dadc	h
	xchg
	djnz	.1
	; Add data sector to cluster sector
	lbcd	datsec		; Root data sector
	dad	b
	lxi	b, 0		; Add carry to DE
	xchg
	dadc	b
	xchg
	push	d		; Root sector of cluster
	push	h		; to stack, high first
	; Calculate sector offset within cluster
	lda	bshf		; Get BSF
	mov	b, a		; Count in B
	lhld	recrd		; Current record
.2:	rarr	h
	rarr	l
	djnz	.2
	push	h		; Keep shifted record
	lda	ashf		; Calculate mask from ASF
	mov	b, a
	lxi	h, 1		; Shift HL
.3:	dad	h
	djnz	.3
	dcx	h		; Becomes mask for record
	pop	d		; Restore shifted record
	mov	a, l		; Mask DE with HL
	ana	e
	mov	l, a
	mov	a, h
	ana	d
	mov	h, a
	pop	d		; Restore low root sector
	dad	d		; Add sector offset containing the record
	pop	b		; Add high word to DE with carry
	lxi	d, 0
	xchg
	dadc	b
	xchg
	
	xra	a
	pushix
	call	dskrd		; Read it
	popix
	rnz
	lxi	h, 1		; Shift 1 in HL BSF times
	lda	bshf
	mov	b, a
.4:	dad	h
	djnz	.4
	dcx	h		; minus one becomes mask
	lda	recrd		; Only need low byte
	ana	l		; Mask record
	lxi	h, 0		; multiply A by 128 to HL
	rar
	rarr	l
	mov	h, a		; Record offset in HL
	lded	datadr		; Data address
	dad	d		; Add to record address
	xra	a		; no error
	ret

	; Calculate the cluster indexed from the number at [index]
	; If [index] is higher than the FCB index, the cluster chain
	; is stepped until they match. If it's less than, the index
	; is reset and the cluster chain is stepped as previously.
	; If they're equal, no change is made.
	;
	; If [index] == 0, the cluster from the directory entry is loaded
	; Returns with A=1 if requested index is beyond EOF.
	; Returns with FCBCUR equal to the cluster containing the record.
	; Stores requested index to 
	
gclust:	lbcd	index		; Target index to BC
	ldx	e, FCBIDX	; Current index to DE
	ldx	d, FCBIDX+1
	ldx	l, FCBCUR
	ldx	h, FCBCUR+1
	mov	a, l		; Current cluster valid?
	ora	h
	jrnz	.3
	ldx	l, FCBCL	; Restart cluster chain
	ldx	h, FCBCL+1
	stx	l, FCBCUR
	stx	h, FCBCUR+1
	ora	l		; Does the file even have a start cluster?
	ora	h
	jrnz	.3		; File has valid start cluster
	inr	a		; Flag EOF and return
	ret

.2:	inx	d		; Increment current index
.3:	push	d		; Just need gt/lt/eq, don't need the result
	xchg			; Subtract BC from DE for compare
	dsbc	b		; 
	xchg
	pop	d
	jrc	.5		; Jump if target is bigger than current
	jrnz	.4		; Jump if target is less than current
	stx	e, FCBIDX	; Equal. Update index
	stx	d, FCBIDX+1
	stx	l, FCBCUR	; Store new cluster associated with index
	stx	h, FCBCUR+1
	xra	a		; No error
	ret
	
.4:	ldx	l, FCBCL	; Restart cluster chain if less than
	ldx	h, FCBCL+1
	stx	l, FCBCUR
	stx	h, FCBCUR+1
	lxi	d, 0		; Current index is 0
	jr	.3		; Recompare (in case target is 0)
.5:	call	getfat		; Step the cluster chain
	mvi	a, 0FFh		; Set up to compare against EOF cluster
	jrc	.6		; Carry set on FAT12 filesystem
	; Check FAT16 cluster
	cmp	l
	jrnz	.2		; If not EOF, compare indexes again
	cmp	h
	jrnz	.2
	jr	.7
	; Compare FAT12
.6:	cmp	l
	jrnz	.2
	mvi	a, 00Fh
	cmp	h
	jrnz	.2
	; If target and requested index don't match here,
	; requested index is beyond EOF. If they match,
	; the requested index is the last one in the file.
.7:	xchg			; DE to HL for subtraction
	xra	a		; Clear zero
	dsbc	b		; Subtract BC from DE
	mvi	a, 0		; No error
	rnc
	inr	a		; Else return with EOF error
	ret


	;
	; Set the FAT cluster in HL to DE
	;
setfat:	lda	curfat		; Is it FAT12 or FAT16?
	cpi	1
	jrz	setf12
	cpi	2
	jrz	setf16
setfail:
	xra	a
	dcr	a
	ret
	
setf16:	push	d		; Keep data
	call	find16
	pop	b
	jrnz	setfail
	mov	m, c		; Write data
	inx	h
	mov	m, b
	; Set flag in stale
setfx:	lhld	stale
	mvi	a, 2
	ora	m
	mov	m, a
	xra	a		; No error
	ret
	
setf12:	lxi	b, 0F000h	; Default mask
	sbcd	fatmsk
	mvi	a, 0Fh		; Clear top 4 bits for 12-bit value
	ana	d
	mov	d, a
	mov	a, l		; Odd or even entry?
	rar
	jnc	.even		; Set even
	xchg			; Shift data to write
	dad	h
	dad	h
	dad	h
	dad	h
	xchg
	lxi	b, 000Fh	; New mask
	sbcd	fatmsk
.even:	push	d		; Save data to write
	mov	e, l		; Copy to requested cluster to DE
	mov	d, h
	xra	a		; Clear carry
	rarr	h		; Divide cluster by two
	rarr	l
	dad	d		; Add original plus half (multiply by 1.5)
	push	h
	call	find12		; Find low byte
	pop	d		; location to write
	pop	b		; data to write
	rnz			; Return on error
	lda	fatmsk		; Low byte of mask
	ana	m		; Mask off old data
	ora	c		; Add new data
	mov	m, a
	lxi	h, stale	; Set stale
	mvi	a, 2
	ora	m
	mov	m, a
	xchg			; DE (contains location to write) to HL
	inx	h		; Next byte
	push	b		; Data to write
	call	find12
	pop	b
	rnz			; Return on error
	lda	fatmsk+1	; high byte of mask
	ana	m		; Mask off old data
	ora	b		; Add new data (high byte)
	mov	m, a
	lxi	h, stale	; Set stale again (sector boundary)
	mvi	a, 2
	ora	m
	mov	m, a
	xra	a
	ret
	
	;
	; Get the sector which contains the FAT cluster entry requested
	; in HL. Returns with HL containing the data at that entry.
	; i.e. step the chain.
	;
getfat: push	b
	push	d		; Keep BCDE for other routines
	lda	curfat		; Load a FAT12 or FAT16 entry
	cpi	1
	jrz	getf12		; 1=FAT12
	cpi	2
	jrz	getf16		; 2=FAT16
getfail:
	pop	d
	pop	b
	xra	a		; Return with error
	dcr	a
	ret	
	; Get from FAT16
getf16:	call	find16		; Find the FAT16 cluster
	jrnz	getfail		; Error
	mov	e, m		; Get the entry
	inx	h
	mov	d, m
	xchg			; To HL
	xra	a		; No error, return with C clear
getfok:	pop	d
	pop	b
	ret
	
	; Get from FAT12
getf12:	mov	e, l		; Copy to requested cluster to DE
	mov	d, h
	xra	a		; Clear carry
	rarr	h		; Divide cluster by two
	rarr	l
	dad	d		; Add original plus half (multiply by 1.5)
	push	h
	push	d		; keep requested cluster
	call	find12		; Get first byte
	pop	d		; Get requested back to DE
	mov	c, m		; get low byte to C
	pop	h
	rnz			; Return on error
	push	d		; Save requested
	inx	h		; Next byte
	push	b
	call	find12
	pop	b		; Low byte of data stored here
	pop	d		; Retrieve requested for odd/even check
	rnz			; Error?
	mov	b, m		; Load high byte from table
	mov	l, c		; Word loaded from table to HL
	mov	h, b
	rarr	e		; Odd or even cluster entry?
	jrnc	.4		; Jump on even, no shift
	mvi	b, 4		; Shift 4 times
	xra	a
.3:	rarr	h
	rarr	l
	djnz	.3
.4:	mvi	a, 0Fh		; Mask off high byte
	ana	h
	mov	h, a
	stc			; Carry set on FAT12 return
	jr	getfok
	
	;
	; Find a FAT16 cluster in HL. Point to it in memory at HL
	;
find16:	push	h		; Keep cluster
	mov	l, h		; HL becomes sector to load
	mvi	h, 0
	lded	fatsec		; First FAT sector in partition
	dad	d		; Add reserved to sector to load
	lxi	d, 0		; DEHL is the sector to load in partition
	mvi	a, 1
	call	dskrd		; Read it
	pop	h		; Restore cluster
	rnz			; Error
	mvi	h, 0		; Clear high byte, low is current entry
	dad	h		; *2 for address in table
	lded	fatadr		; buffer address
	dad	d		; Add the two
	xra	a		; No error
	ret
	
	
	;
	; Find the location of a byte in the FAT12 table, pointed to in HL
	; This needs to be run twice to get two bytes of a FAT12 entry
	; (sector boundaries) and the result will need to be shifted.
	;
find12:	push	h		; Keep cluster offset
	mov	e, h		; HL divided by 256
	xra	a		; Clear A, carry
	mov	d, a
	rarr	e		; Divide by 2 (total 512)
	lhld	fatsec		; Origin of FAT sectors
	dad	d		; Add sector offset
	lxi	d, 0		; Load sector DEHL (FIX)
	mvi 	a, 1
	call	dskrd		; Read the sector
	pop	h		; Cluster offset back to HL
	rnz			; Disk error
	mvi	a, 1		; Make cluster offset between 0..511
	ana	h
	mov	h, a
	lded	fatadr		; Offset+data address
	dad	d
	xra	a		; No error
	ret
	
	; Calculate FAT index from CR/EX/S2 in FCB, returned in [index].
	; Return record within that cluster to load in [recrd]
getidx:	lxi	h, bshf		; Block shift factor
	mov	a, m
	lxi	h, ashf		; Allocation shift factor
	add	m		; Add the two
	mov	b, a
	; B contains shift factor to convert the current 128 byte
	; record into a FAT index + record number.
	push	b		; Keep it
	call	calrec
	; EHL now contains the record number
	pop	b		; Get shift factor back
	xra	a		; Record in cluster is in A:C
	mvi	c, 080h		; Set MSB as flag for final shift
.1:	ora	a
	rarr	e
	rarr	h
	rarr	l
	rarr	c
	rar
	djnz	.1		; Loop B times
	shld	index		; Store index
	; Loop until flag set previously in C is in carry
	; Also shifts carry from previous loop
.2:	rarr	c
	jrnc	.2
	lxi	h, recrd	; Store CA to recrd
	mov	m, c
	inx	h
	mov	m, a
	xra	a
	ret


