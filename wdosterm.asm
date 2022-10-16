;
; Z80 WeirDOS 0.4
;
; wdosterm.asm
;
; Routines for terminal (console) I/O
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



crlf:	mvi	c, CR
	call	conout
	mvi	c, LF
	jmp	conout
	
	; Stub for conin
conina:	call	conin		; Get character as requrested
	sta	rval		; Set return value
	ret

	; Stub for reader
readera	call	reader		; Get character as requrested
	sta	rval		; Set return value
	ret
	

	;
	; Function 02h (2)
	;
	; Console output
cout:	call	const
	jrz	.1
.wait	call	conin
	cpi	CTRLS		; XOFF
	jrz	.wait
	cpi	CTRLC		; ^C
	jz	exit		; Terminate program
.1:	lded	param
	mov	c, e
	jmp	conout
	
	;
	; Function 06h (6)
	;
	; Directo console I/O
	; E = 0FFh
dcons:	mov	a, e	; For compare
	cpi	0FFh
	jnz	cout
	; Else we input a character
	call	const
	ora	a
	rz		; Return if no character available
	call	conin	; Else get it and return
	sta	rval
	ret
	
	;
	; Function 09h (9)
	;
	; Print. Terminates on '$' in string.
	; Changes A, DE.
	; A returns with '$'. DE returns pointing
	; at the end of the string.
print:	ldax	d
	inx	d
	cpi	'$'
	rz
	push	d
	mov	c, a
	call	conout
	pop	d
	jr	print
	

	; Function 0Ah (10)
	;
	; Buffered Console Input
	; Enter with DE as buffer location
iredo:	mvi	c, '\'	; Start a new line
	call	conout
	call	crlf
input:	lhld	param	; Parameters location
	mov	a, l
	ora	h
	jnz	inp1
	lhld	dmaadr	; DE=0, use DMA address
	shld	param
inp1:	mov	b, m	; Buffer size in B
	inx	h	; Buffer length
	inx	h	; Point at bytes to store
	mvi	c, 0	; Buffer count in C
inpl:	push	h
	push	b
	call	conin
	pop	b
	pop	h
	mov	d, a	; Keep received character in D
	
	cpi	' '	; Control character?
	jc	ictrl
	
istore:	mov	a, c	; Compare B to C
	cmp	b
	jnc	inpl	; Jump if B >= C, discard character
	mov	m, d	; Store character
	inr	c	; Increment character count
	inx	h	; Next memory location
	push	h
	push	b
	mov	c, d	; Print character in C
	mov	a, d	; Don't re-echo control characters
	cpi	' '
	cnc	conout
	pop	b
	pop	h
	jmp	inpl	; Continue

ictrl:	cpi	RUBOUT
	jz	inpbs
	cpi	BS
	jz	inpbs
	cpi	CR
	jz	inpcr
	cpi	ESCAP	; Redo?
	jz	iredo
	; Else, print caret and character
	push	b	; Count in C
	push	d	; Character in D
	mvi	c, '^'	; Print a caret
	call	conout
	pop	d	; Restore character
	push	d
	mov	a, d	; Make it visible
	adi	'@'
	mov	c, a	; Print it
	call	conout
	pop	d
	pop	b
	mov	a, d
	cpi	CTRLC	; Reboot on ctrl-C
	jz	reload
	jmp	istore	; Store D
	
inpbs:	mov	a, c	; Do nothing if at character 0
	ora	a
	jz	inpl
	dcr	c	; Decrement character count
	dcx	h	; Decrement character pointer
	mov	a, m
	cpi	TAB	; Erase a tab (7 characters plus control)
	cz	inptab
	cpi	' '	; Erase two characters if it's a control
	cc	inpclr
	call	inpclr	; Erase normal character
	jmp	inpl

inptab:	push	psw
	mvi	b, 7
inptl:	call	inpclr
	djnz	inptl
	pop	psw
	ret
	
	; Clear the previous character
inpclr:	push	h
	push	b
	mvi	c, 8	; Rubout character
	call	conout
	mvi	c, ' '
	call	conout
	mvi	c, 8
	call	conout
	pop	b
	pop	h
	ret

inpcr:	lhld	param	; Get parameters location
	inx	h	; Point at length
	mov	m, c	; Store character count
	mvi	c, CR	; emit CR on exit
	jmp	conout

	
	
	
	;
	; Function 0Bh (11)
	;
	; Console status
	;
cstat:	call	const	; A=status
	sta	rval	; A=L=status
	ret
	

	
	; Function 07h (7)
	;
	; Return I/O Byte
giobyt:	lda	IOBYTE
	sta	rval
	ret
	
	
	; Function 08h (8)
	;
	; Set I/O byte from E
siobyt:	mov	a, e
	sta	IOBYTE
	ret
	
