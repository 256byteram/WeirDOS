;
; Z80 WeirDOS 0.4
;
; wdoswarm.asm
;
; Loads and jumps to the command line interpreter.
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
	; Function 0
	; Reload shell, execute.
	;
exit:	mvi	c, '^'		; Print ^C when user terminates command
	call	conout
	mvi	c, 'C'
	call	conout
reload:	lxi	sp, stack
	call	crlf

	lxi	h, fcb		; Default FCB
	lxi	d, fcbi		; Intermediate FCB
	lxi	b, 36
	ldir
	
selok:	lxi	d, fcbi
	mvi	c, 15		; Open
	call	wdos
	inr	a		; FFh becomes 0
	jz	nofile
	lxi	d, 080h		; DMA address
	mvi	c, 26
	call	wdos
	lxi	d, CMD		; Load to here
rloop:	push	d
	lxi	d, fcbi
	mvi	c, 20		; Read next
	call	wdos
	pop	d
	lxi	h, 080h		; From 080h
	lxi	b, 128		; 128 bytes to copy
	ldir
	cpi	1		; At EOF, execute it
	jz	goshel
	ora	a
	jnz	nofile
	jmp	rloop

goshel:	lxi	d, fcbi		; Close file
	mvi	c, 16
	call	wdos
	jmp	CMD		; Jump to it

nofile:	lxi	d, nfmsg
	mvi	c, 9
	call	wdos
	call	conin
	jmp	reload


