;
; Z80 WeirDOS 0.4
;
; cli.asm
;
; Command Line Interpreter for WeirDOS
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

	maclib	Z80

; WDOS commands
cout	equ	2		; Console out
print	equ	9		; Print $ terminated
binput	equ	10		; Buffered console input
cstat	equ	11		; Console status
dreset	equ	13		; Disk reset
openf	equ	15		; Open file
closef	equ	16		; Close file
search	equ	17		; Search for first file
next	equ	18		; Search for next file
readn	equ	20		; Read next
setdma	equ	26		; Set DMA

cdisk	equ	4
wdos	equ	5
fcb1	equ	05Ch		; Default FCB
fcb2	equ	fcb1+16		; Second parameter
defdma	equ	080h		; Default DMA address
tpa	equ	0100h		; Transient Program Area

cmdlen	equ	70		; length of command line string

cr	equ	13
lf	equ	10
eof	equ	26		; EOF character marker
	
	org	tpa
	
entry:	jmp	init

	;
	; This chunk of code is copied below WDOS
	; to load the transient program.
	;
	; It can only use relative code within the function.
	;
boot:	lxi	h, tpa
	push	h
	
.1:	xchg			; DMA from HL to DE
	mvi	c, setdma
	call	wdos
	
	lhld	wdos+1
	lxi	d, -35		; Move back to start of FCB
	dad	d
	xchg			; DE contains transient FCB
	mvi	c, readn
	call	wdos
	
	ora	a
	jrnz	.2
	
	pop	h		; Increment DMA
	lxi	d, 80h
	dad	d
	push	h
	jr	.1

.2:	pop	h		; Remove DMA from stack
	cpi	1		; EOF?
	jnz	0		; error
	mvi	e, lf		; New line after program loaded
	mvi	c, cout
	call	wdos
	
	lxi	d, defdma	; Set default buffer address after loading
	mvi	c, setdma
	call	wdos
	
	lxi	h, 0		; Warm start should program RET
	push	h
	jmp	tpa
	
	; Load transient programs with this FCB
	db	0,"           ",0,0,0
	dw	0,0,0,0,0,0,0,0,0,0
	
bootx	equ	$

btvec:	dw	0		; Boot vector
blank:	db	0,"           ",0,0,0,0
	db	0,"           ",0,0,0,0
	

crlf:	mvi	e, cr
	mvi	c, cout
	call	wdos
	mvi	e, lf
	mvi	c, cout
	jmp	wdos
	

	;
	; Initialise environment
	;
	;
init:	lhld	wdos+1		; Get top of TPA
	lxi	b, bootx-boot	; Size of boot loader
	dsbc	b		; Address to copy bootloader to
	shld	btvec		; Keep to jump to
	sphl			; Also initialize the stack
	xchg			; Destination from HL to DE
	lxi	h, boot		; Source of boot loader
	ldir			; Copy it
	
	
cli:	lxi	h, blank	; Blank FCB
	lxi	d, fcb1		; Default FCB
	lxi	b, 32		; copy it
	ldir	
	call	crlf
	lda	cdisk		; Print current disk for prompt
	adi	'A'
	mov	e, a		; Print it
	mvi	c, cout
	call	wdos
	
	mvi	e, '>'
	mvi	c, cout
	call	wdos
	
	lxi	h, defdma	; Clear default buffer
	mvi	m, cmdlen	; Length of command line
	inx	h
	mvi	m, 0
	
	lxi	d, defdma	; Set default buffer address
	mvi	c, setdma
	call	wdos
	
	lxi	d, 0		; Read command into default buffer
	mvi	c, binput
	call	wdos
	
	
	; Interpret command. String length in B, which
	; is decremented as the string pointer is incremented.
	;
	lxi	h, defdma+1
	mov	b, m
	inx	h
	call	upper		; Uppercase that string
	jz	cli		; No input
	
	lhld	wdos+1
	lxi	d, -35		; Move back to start of FCB
	dad	d
	xchg
	lxi	h, defdma+1
	mov	b, m
	inx	h
	xchg			; DE = user string, HL = FCB
	call	skipwh		; Skip whitespace
	jz	cli		; No input
	call	tofcb
	call	skipwh
	lxi	h, fcb1		; Parameter 1
	call	tofcb
	call	skipwh
	lxi	h, fcb2
	call	tofcb
	lhld	wdos+1
	lxi	d, -34		; Point at filename in FCB
	dad	d
	xchg			; String at DE
	call	intern
	jnz	trans
	lxi	d, cli
	push	d
	pchl
	;
	; Attempt to load a transient program
	;
trans:	lhld	wdos+1		; Get FCB at top of memory
	lxi	d, -26		; Count backwards from end of memory
	dad	d
	mvi	m, 'C'		; Search for .COM
	inx	h
	mvi	m, 'O'
	inx	h
	mvi	m, 'M'
	lxi	d, -11
	dad	d
	xchg
	mvi	c, openf
	call	wdos
	ora	a
	jnz	nofile		; Error
	lhld	btvec		; Get boot vector
	pchl			; Jump to it
	


	;
	; Make the command buffer at HL upper case, remove control chrs
	;
upper:	mov	a, b
	ora	a		; Don't bother with a null string
	rz
.1:	mov	a, m
	cpi	'`'		; Lower case letter?
	jrc	.2
	ani	0DFh		; Remove lower case bit
.2:	cpi	' '		; Control character?
	jrnc	.3
	mvi	a, ' '		; Replaced with space
.3:	mov	m, a
	inx	h
	djnz	.1
	ori	0FFh		; Non-zero for valid input
	ret
	

	;
	; Read string to a FCB filename
	;
	; HL points at FCB to fill to. DE to string to read from
	;
tofcb:	inx	h
	call	clrfil
	mvi	c, 8		; 8 characters for first part
.1:	mov	a, b		; Count string length
	ora	a
	rz
	dcr	b
	ldax	d
	inx	d
	cpi	' '		; End of parameter?
	rz
	cpi	'.'		; Dot moves to next section
	jrz	.3
	cpi	'*'
	jrz	.2
	mov	m, a
	inx	h
	dcr	c
	jrz	.3		; End of first 8 characters?
	jr	.1
	
	; Fill rest of FCB with question marks
.2:	mov	a, c
	ora	a
	jz	.1		; 8 character count ended?
	mvi	m, '?'
	inx	h
	dcr	c
	jr	.2

	; Move FCB pointer across to file extension
.3:	push	b		; Add C to HL, saving B
	mvi	b, 0
	dad	b
	pop	b
	mvi	c, 3		; Will need to count 3 characters
	jr	.1

	
	;
	; Clear filename at HL to spaces. Saves BC, HL
	;
clrfil:	push	h
	push	b
	mvi	b, 11
.1:	mvi	m, ' '
	inx	h
	djnz	.1
	pop	b
	pop	h
	ret

	
	;
	; Read in from DE++ until character is not whitespace
	;
	; Returns with Z set if the end of the string is found
	; DE points at next valid character
	; 
skipw1:	inx	d
	dcr	b
	; Enter here
skipwh:	mov	a, b		; Make sure there's a string there
	ora	a
	rz	
	ldax	d
	cpi	' '
	rnz
	jr	skipw1
	
	;
	; Search for an internal command, compared to user string at DE
	; If found, return with its vector in HL, Z
	; If not found, return with NZ
	;
intern:	lxi	h, intcmd	; Get total number of commands
	mov	c, m
	inx	h		; Point at first command
.1:	push	d		; Keep user pointer for loop
	push	b		; Keep string position
	call	strcmp
	jrz	.2
	pop	b
	pop	d		; Restore user pointer
	dcr	c
	jrnz	.1
	ori	0FFh
	ret			; Return with Z if string not found
.2	pop	h		; Discard previously saved values
	pop	h
	lda	intcmd		; Get total number of commands
	sub	c		; Subtract command count
	mov	l, a		; to HL
	mvi	h, 0
	dad	h		; *2
	lxi	d, intvec	; Vectors
	dad	d
	mov	a, m
	inx	h
	mov	h, m
	mov	l, a
	xra	a
	ret
	
	;
	; String compare.
	; 
	; User string at DE
	; System string at HL
	; 
	; Returns with zero if string is found
	;
	
strcmp:	ldax	d
	cmp	m
	jrnz	.2
	inx	d
	inx	h
	djnz	strcmp
	xra	a		; String found
	ret
	
.2:	mvi	a, '$'		; End of string at HL?
	cmp	m
	inx	h
	jrnz	.4		; No, skip to next string and return
	ldax	d		; Whitespace at user string?
	cpi	' '
	rz			; Found string
.5:	ori	0FFh
	ret			; Return with Z flag clear

.4:	cmp	m		; Skip to next system string
	inx	h
	jrnz	.4
	jr	.5
	

	; Internal command structure
	;
intcmd:	db	2

	db	"DIR$"
	db	"TYPE$"


intvec:	dw	dir
	dw	type
	
	;
	; Display directory
	;
	; If FCB is uninitialized (spaces) it is filled with '?'
	;
	;
dir:	lxi	h, fcb1+1
	mov	a, m
	cpi	' '
	jrnz	.3
	; The FCB has no file specified
	lxi	h, fcb1+1
	mvi	b, 11
.4:	mvi	m, '?'
	inx	h
	djnz	.4
	
.3:	mvi	c, dreset	; Reset disks in case of disk change
	call	wdos
	lxi	d, fcb1		; Initial search
	mvi	c, search
	call	wdos
	ora	a
	jnz	nofile		; Print message on no-file
	mvi	b, 1
	push	b
.loop:	pop	b
	djnz	.2
	push	psw
	call	crlf
	pop	psw
	mvi	b, 5
.2:	cpi	0FFh		; Return at end of directory
	rz
	push	b
	lxi	h, defdma+12
	mvi	m, ' '
	inx	h
	mvi	m, ':'
	inx	h
	mvi	m, ' '
	inx	h
	mvi	m, '$'		; Make directory entry printable
	lxi	d, defdma+1
	mvi	c, print
	call	wdos
	lxi	d, fcb1
	mvi	c, next
	call	wdos
	jr	.loop		; Loop

	
	;
	; Type the file in FCB to the console
	;
type:	lxi	d, defdma	; Load to default DMA
	mvi	c, setdma
	call	wdos
	lxi	d, fcb1		; Open it
	mvi	c, openf
	call	wdos
	ora	a
	jnz	nofile		; Message if file not found
	
.loop:	lxi	d, fcb1
	mvi	c, readn
	call	wdos
	ora	a
	rnz
	lxi	h, defdma
	mvi	b, 128		; 128 characters to print
.pr:	mov	a, m
	cpi	eof
	rz			; Return on EOF character
	push	b
	push	h
	mvi	c, cout		; Feed chars to console
	mov	e, a		; Character to print
	call	wdos
	
	pop	h
	pop	b
	inx	h
	djnz	.pr
	jr	.loop		; Continue printing blocks
	
nofile:	lxi	d, nf
	mvi	c, print
	call	5
	ret
	
	
nf:	db	10,"No file$"
