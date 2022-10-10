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
seldsk	equ	14		; Select disk
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
	
entry:	jmp	cli


nf:	db	10,"No file",0
btvec:	dw	0		; Boot vector

curfcb:	db	0		; Current FCB pointed at by state machine (bootstrap, FCB1, FCB2)
btfcb:	dw	0		; Boot FCB
xfcb1:	dw	fcb1		; FCB 1
xfcb2:	dw	fcb2		; FCB 2

blank:	db	0,"           ",0,0,0,0
	db	0,"           ",0,0,0,0
	db	0,0,0,0
pdir:	db	"        .    : ",0

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
	lxi	d, -(bootx-bootfcb)	; Move back to start of FCB
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
	
	lhld	wdos+1		; Close the file
	lxi	d, -(bootx-bootfcb)
	dad	d
	xchg
	mvi	c, closef
	call	wdos
	
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
bootfcb	db	0,"        COM",0,0,0
	dw	0,0,0,0,0,0,0,0,0,0
	db	0
bootx	equ	$

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
cli:	lhld	wdos+1		; Get top of TPA
	lxi	b, bootx-boot	; Size of boot loader
	ora	a		; Clear carry
	dsbc	b		; Address to copy bootloader to
	shld	btvec		; Keep to jump to
	sphl			; Also initialize the stack
	xchg			; Destination from HL to DE
	lxi	h, boot		; Source of boot loader
	ldir			; Copy it
	xchg
	lxi	b, -(bootx-bootfcb)		; Move back to start of transient FCB
	dad	b
	shld	btfcb		; Keep this location
	
	lxi	d, dirsp	; Loading data to here
	mvi	c, setdma
	call	wdos
	
	lxi	h, blank	; Blank FCB
	lded	xfcb1		; Default FCB
	lxi	b, 36		; copy it
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
	
	lxi	h, cmdbuf	; Clear default buffer
	mvi	m, cmdlen	; Length of command line
	inx	h
	mvi	m, 0
	
	lxi	d, cmdbuf	; Read command into default buffer
	mvi	c, binput
	call	wdos
	
	
	; Interpret command. String length in B, which
	; is decremented as the string pointer is incremented.
	;
	lxi	h, cmdbuf+1
	mov	b, m
	inx	h
	call	upper		; Uppercase that string
	jz	cli		; No input
	
	lxi	h, cmdbuf+1
	mov	b, m
	inx	h		; HL = user string, DE = FCB
	xchg
	
	;
	; String state machine
	;
	; A = current character
	; B = characters remaining in user input
	; C = character within FCB (MSB indicates whitespace was found)
	; DE = string pointer
	; HL = Current FCB pointer
	;
	lhld	btfcb
	inx	h		; Point at first character of FCB
	xra	a		; Reset memory parameters
	sta	curfcb
	mvi	c, 0	
smwhit:	bit	7, c		; Already on whitespace?
	jnz	sm		; Yes, continue
	mov	a, c		; Still processing transient FCB?
	ora	a		; (MSB already checked)
	jz	sm		; Yes, continue
	
	mvi	c, 080h		; Flag for whitespace, reset SM
	lda	curfcb		; FCB 1 or 2?
	cpi	3		; Only have boot FCB, FCB1, FCB2 to choose from
	jnc	smend		; Terminate if higer than that
	
	lhld	xfcb1		; Load FCB1, check to see if we're on it
	inx	h		; Point at first character
	inr	a
	sta	curfcb
	cpi	1
	jz	sm		; We're up to FCB2
	lhld	xfcb2
	inx	h		; Point at first character
	
sm:	xra	a
	ora	b		; Last character?
	jrnz	smcont
	
	; Determine action on end of line here
smend:	lda	curfcb
	ora	a		; on boot FCB?
	jnz	cmdex		; No, execute command	
	xra	a		; C == 0?
	cmp	c
	jz	setdef		; Change default drive
	jmp	cmdex		; Execute command

smcont:	ldax	d		; Get current character
	inx	d
	dcr	b		; Count character
	cpi	'!'		; White space (space and control characters)
	jrc	smwhit

	res	7, c		; No longer on whitespace
	cpi	'*'		; Wildcard
	jrz	wildc
	cpi	'.'		; File extension
	jrz	dot
	cpi	':'		; Drive change
	jrz	drive
	mov	m, a
	inc	c
	inx	h
	jr	sm

wildc:	mvi	a, 8		; Currently on 8th character?
	cmp	c
	jrz	sm
	mvi	a, 12		; Alternatively, at end of filename?
	cmp	c
	jrz	sm
	mvi	m, '?'		; Question mark to FCB
	inx	h
	inc	c
	jr	wildc

dot:	mvi	a, 9
dotl:	inc	c
	cmp	c
	jrnc	sm
	inx	h
	jr	dotl
	
drive:	mvi	a, 1		; Must be second character (0 based)
	cmp	c
	jrnz	sm		; Is not second character, ignore
	dcx	h		; Get last character from FCB
	mov	a, m
	sui	'@'		; Drive from 1 to 16
	dcx	h		; Point at drive specifier
	mov	m, a
	inx	h		; Point at first character
	mvi	c, 0		; Also point to first character here
	jr	sm
	
	;
	; Set the default drive
	;
setdef:	dcx	h
	mov	a, m
	dec	a		; 0..15 from 1..16
	mov	e, a
	mvi	c, seldsk	; Change default disk
	call	wdos
	jmp	cli

	
	; Attempt to execute command
cmdex:	call	intern
	jrz	cmdex1		; Found internal command	
	;
	; Attempt to load a transient program
	;
	lded	btfcb		; FCB at top of memory
	mvi	c, openf
	call	wdos
	ora	a
	jnz	nofile		; Error
	
	lhld	btvec		; Get boot vector
cmdex1:	pchl			; Jump to it
	


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
	; Copy the command tail to the DMA area (80h)
	; Don't clobber registers
	;
gettail:
	push	b
	push	d
	push	h

	lxi	h, defdma	; Store length
	mov	m, b
	inx	h
	mov	a, b
	ora	a
	jrz	.1		; Nothing to copy
	
	mov	c, b	; Set length
	mvi	b, 0
	xchg		; For LDIR
	ldir		; Copy it
	
.1:	pop	h
	pop	d
	pop	b
	ret
	
	;
	; Search for an internal command, compared to string at boot FCB
	; If found, return with its vector in HL, Z
	; If not found, return with NZ
	;
intern:	lded	btfcb		; Boot FCB
	inx	d
	lxi	h, intcmd	; Get total number of commands
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
	
.2:	xra	a		; End of string at HL?
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

	db	"DIR",0
	db	"TYPE",0


intvec:	dw	dir
	dw	type
	
	;
	; Display directory
	;
	; If FCB is uninitialized (spaces) it is filled with '?'
	;
	;
dir:	lhld	xfcb1
	inx	h
	mov	a, m
	cpi	' '
	jrnz	.3
	; The FCB has no file specified
	mvi	b, 11
.4:	mvi	m, '?'
	inx	h
	djnz	.4
	
.3:	mvi	c, dreset	; Reset disks in case of disk change
	call	wdos
	lded	xfcb1		; Initial search
	mvi	c, search
	call	wdos
	ora	a
	jnz	nofile		; Print message on no-file
	mvi	b, 6		; Initialise
.loop:	djnz	.2
	push	psw
	call	crlf
	pop	psw
	mvi	b, 5		; 5 entries per line
.2:	cpi	0FFh		; Return at end of directory
	rz
	
	push	b		; Keep file count
	lda	dirsp+10	; Address of hidden file attribute
	add	a
	jrnc	.pdir		; Print file if not hidden
	
	pop	b		; Cancel out decrement at start of loop
	inr	b
	push	b
	jr	.ndir		; Do not print directory entry
		
.pdir:	lxi	d, pdir		; Copy filename to print buffer
	lxi	h, dirsp+1
	lxi	b, 8
	ldir
	inx	d		; Copy extension to print buffer after dot
	lxi	b, 3
	ldir
	
	lxi	d, pdir
	call	printz
	
.ndir	lxi	d, fcb1
	mvi	c, next
	call	wdos
	pop	b
	jr	.loop		; Loop

	
	;
	; Type the file in FCB to the console
	;
type:	lxi	d, dirsp	; Load to default DMA
	mvi	c, setdma
	call	wdos
	lded	xfcb1		; Open it
	mvi	c, openf
	call	wdos
	ora	a
	jnz	nofile		; Message if file not found
	
.loop:	lded	xfcb1
	mvi	c, readn
	call	wdos
	ora	a
	rnz
	lxi	h, dirsp
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
	;jmp	printz
	;ret
	
	
	;
	; Print a null terminated string
	;
printz:	ldax	d
	inx	d
	ora	a
	rz
	push	d
	mov	e, a
	mvi	c, cout
	call	wdos
	pop	d
	jr	printz

cmdbuf:	defs	80		; Command line buffer
dirsp:	defs	128		; Directory search space (DMA)

