;
; Z80 WeirDOS 0.4
;
; bcopy.asm
;
; Bootstrap function for WeirDOS.
;
; The WDOS system image and BIOS is appended to this binary.
; It copies it to its runtime location and jumps to the cold
; boot routine in the BIOS.
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


MEMTOP	equ	64		; Top of memory (up to 64k)
NEWORG	equ	(MEMTOP-8)*1024
COLD	equ	(MEMTOP-4)*1024

	phase	100h

	lxi	d, NEWORG	; copy to here
	lxi	h, begin
	lxi	b, 2000h	; Copy this much
	ldir
	jmp	COLD
	nop			; Make 16 bytes
	nop
begin	equ	$

	end
