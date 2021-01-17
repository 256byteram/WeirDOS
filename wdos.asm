;
; Z80 WeirDOS 0.4
;
; A Disk Operating System for Z80 microcomputers, implementing
; the CP/M 2.2 API and FAT12/FAT16 filesystems.
;
; Revision history:
; 0.1 (March 2015)	- Initial write
;
; 0.2 (September 2015)	- Rewrite of filesystem functions
;
; 0.3 (January 2021)	- Get 0.2 to actually work
;			- Implement write functions
;			- I left this too long
;
; 0.4 (January 2021)	- Split source file into multiple files
;			- Use of temporary labels
;
; TODO:
;	- Finish remaining unimplemented API calls
;	- Implement subdirectories
;		- Exact method of implementation undecided
;		- Maybe use 'user' areas to access directories in root
;	- Fully test FAT16 code
;	- Write a shell
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
FALSE	equ	0
TRUE	equ	NOT FALSE

BIN	equ	TRUE	; Fill area between DOS and BIOS for binaries
DEBUG	equ	FALSE	; Enable debugging routines

MEMTOP	equ	64	; Top of addressable memory (up to 64k)
CMD	equ	100h	; Load shell to here

CTRLC	equ	3
CTRLZ	equ	26

BS	equ	8
TAB	equ	9
LF	equ	10
CR	equ	13
EOF	equ	CTRLZ
ESCAP	equ	27
RUBOUT	equ	127

WARM	equ	0	; Warm boot vector
IOBYTE	equ	3	; IOBYTE address
CDISK	equ	4	; Active disk
DOSVEC	equ	5	; DOS vector

; Structure offset equates for DPB
DPBSIZ		equ	49	; Total size of structure
DPBOFF		equ	11	; Absolute offset from start of sector
BYTESPERSEC	equ	0	; (2) Bytes per sector
SECPERCLUST	equ	2	; (1) Sectors per cluster
RESERVEDSEC	equ	3	; (2) Reserved sectors
NUMFATS		equ	5	; (1) Number of FATs
ROOTENTCNT	equ	6	; (2) Root Directory Entries
TOTSEC16	equ	8	; (2) Total sectors 16-bit value
MEDIATYPE	equ	10	; (1) Media type (0xF8 fixed, 0xF0 removable)
FATSIZE		equ	11	; (2) Sectors taken by one FAT
SECPERTRK	equ	13	; (2) Sectors per track
NUMHEADS	equ	15	; (2) Number of heads
HIDDSEC		equ	17	; (4) Hidden sectors before partition
TOTSEC32	equ	21	; (4) Total sectors 32-bit value
DRVNUM		equ	25	; (1) Drive number, 80h or 0
;RESERVED		26
BOOTSIG		equ	27	; (1) Boot sig is 29h
VOLID		equ	28	; (4) Volume serial number
VOLLABEL	equ	32	; (11) Volume label (11 characters)
FILESYSTYPE	equ	43	; (8) File system type 'FAT12   ' etc

; Structure for FCB
;
; 00 F1 F2 F3 F4 F5 F6 F7 F8 T1 T2 T3 EX S1 S2 RC
; FL FL OF 00 CC CC IX IX DD DD CL CL LE LE LE LE
; CR RN RN RN
;
; 00 - user number (zero)
; Fx - File name
; Tx - File type
; EX - Extent number (zero)
; S1 - Last record byte count
; S2 - Extent number (high bits)
; RC - record count
; FL - Flags, file number high 5 bits
; OF - File number, low 8 bits
; CC - Current cluster (internal to OS)
; IX - Cluster index (internal to OS)
; DD - DOS Date
; CL - DOS Cluster
; LE - DOS Length
; CR - Current record
; RN - Random record access
USRFCB	equ	05Ch	; Location of User FCB
FCBDSK	equ	0	; Drive letter to access (0=current)
FCBNAM	equ	1	; File name
FCBEXT	equ	9	; File extension
FCBEX	equ	12	; File extent
FCBS1	equ	13	; Bytes in current record
FCBS2	equ	14	; Module number (512kB block)
FCBRC	equ	15	; Record Count
FCBFL	equ	16	; Flags and high directory entry
FCBOF	equ	18	; Low directory entry
FCBCUR	equ	20	; Current cluster
FCBIDX	equ	22	; Current cluster index
FCBTIME	equ	22	; DOS Time (shared with index)
FCBDATE	equ	24	; DOS Date
FCBCL	equ	26	; DOS Cluster
FCBLEN	equ	28	; DOS Length
FCBCR	equ	32	; Current Record
FCBRN	equ	33	; Random record to access

; Structure for FAT directory entries
; FN FN FN FN FN FN FN FN EX EX EX AT 00 C0 C1 C1
; CD CD AD AD 00 00 MT MT MD MD CL CL LN LN LN LN
;
; FN - File Name
; EX - File extension
; AT - File attributes
; C0 - Creation time 1/10th seconds
; C1 - Creation time 2 seconds
; CD - Creation date
; AD - Access date
; MT - Modification time
; MD - Modification date
; CL - Start cluster
; LN - File length
DIRNAME	equ	0		; File name
DIREXT	equ	9		; File extension
DIRATTR	equ	11		; Attributes
DIRCL	equ	26		; Start cluster
DIRLEN	equ	28		; File length

; Offset for beginning of partition start sector in MBR
PART0	equ	454		; Bytes offset for partition begin

	phase	(MEMTOP-8)*1024
	jmp	wdos		; Jump vector for compatibility

	; Main function lookup table
jtab:	dw	reload		;  0 00h Warm Boot - wdoswarm.asm
	dw	conina		;  1 01h Console input - wdosterm.asm
	dw	cout		;  2 02h Console output - "
	dw	punch		;  3 03h papertape punch - "
	dw	readera		;  4 04h papertape reader - "
	dw	list		;  5 05h List output (printer) - bios.asm
	dw	dcons		;  6 06h Direct console output - wdosterm.asm
	dw	giobyt		;  7 07h Get I/O byte - "
	dw	siobyt		;  8 08h Set I/O byte - "
	dw	print		;  9 09h Print string, '$' terminated - "
	dw	input		; 10 0Ah console line input - "
	dw	cstat		; 11 0Bh Console status - "
	dw	vers		; 12 0Ch Version number - wdos.asm
	dw	dreset		; 13 0Dh Reset disks - wdosdisk.asm
	dw	select		; 14 0Eh Select disk - "
	dw	fopen		; 15 0Fh Open file/directory - wdosfile.asm
	dw	fclose		; 16 10h Close file/directory - "
	dw	search		; 17 11h Search for file - "
	dw	next		; 18 12h Search for next occurance - "
	dw	delete		; 19 13h Delete file - "
	dw	readn		; 20 14h Read next record - "
	dw	writen		; 21 15h Write next record - "
	dw	create		; 22 16h Create file/directory - "
	dw	rename		; 23 17h Rename file/directory - "
	dw	unsupp		; 24 18h Return bitmap of logged in drives
	dw	cdrive		; 25 19h Return current drive
	dw	setdma		; 26 1Ah Set DMA address - wdosfile.asm
	dw	unsupp		; 27 1Bh Return address of allocation map
	dw	unsupp		; 28 1Ch Set current disk to R/O
	dw	unsupp		; 29 1Dh Return bitmap of R/O drives
	dw	unsupp		; 30 1Eh Set file attribs
	dw	unsupp		; 31 1Fh Retrieve DPB
	dw	unsupp		; 32 20h Get/set user number
	dw	rdrnd		; 33 21h Read Random - wdosfile.asm
	dw	wrrnd		; 34 22h Write random - "
JTOTAL	equ	($-jtab)/2+2
	
lstack:	dw	0,0,0,0		; Local stack
	dw	0,0,0,0
	dw	0,0,0,0
	dw	0,0,0,0
	dw	0,0,0,0
	dw	0,0,0,0
	dw	0,0,0,0
	dw	0,0,0,0
	dw	0,0,0,0
	dw	0,0,0,0
pstack:	dw	0		; Store program's stack pointer
param:	dw	0		; Incoming parameters from DE
rval:	dw	0		; Return value in HL
				; 0=Uninitialised, 1=FAT12, 2=FAT16
	
disk:	db	0FFh		; Current disk dpbadr points at (FF is none)
atype:	db	0		; Access type (0=data, 1=FAT)
stale:	db	0		; Data buffer has data written (1=data,2=FAT)
; Data calculated from current disk
dpbadr:	dw	0		; DPB address
bshf:	db	0		; Block shift factor
ashf:	db	0		; Allocation shift factor
pchkd:	db	0		; Indicates we've already checked partitions
fatsec:	dw	0		; First sector of FAT region
rtsect:	dw	0		; First sector of root directory region
datsec:	dw	0		; First sector of data region
poffs:	dw	0,0		; Partition offset (0 for unpartitioned)
volsiz:	dw	0		; Total volume size if <65536, else 0
ctotal:	dw	0		; Total number of clusters in volume
; Data for current location in FAT chain
recrd:	dw	0		; Current record (internal use)
index:	dw	0		; Current index of cluster (compared to FCB)
; Data for disk operations
dsect:	dw	-1,-1		; Data sector loaded
fsect:	dw	-1,-1		; FAT sector loaded
datadr:	dw	0		; Data buffer address
fatadr:	dw	0		; FAT buffer address
fatmsk:	dw	0		; Mask to clear odd/even FAT12 entries
; Disk bitmaps
logdsk:	dw	0		; Currently logged in disks bitmap MSB=A:
rodsk:	dw	0		; Current disks marked read-only MSB=A:
fatype:	dw	0		; FAT12/16 flag per disk 0=FAT12
curfat:	db	0		; FAT12/16 Flag for current disk
; Directory search data
curdir:	dw	0		; Current offset within loaded sector
diridx:	dw	0		; Current directory index (0,1,2...)
dirmax:	dw	0		; Maximum number of root entries
dirsec:	dw	0,0		; Current directory sector

dmaadr:	dw	80h		; DMA address

wdos:	sded	param		; Store parameter pointer
	lxi	h, 0
	shld	rval		; Default return value
	sspd	pstack		; Keep user SP
	lxi	sp, pstack 	; Set new one
	pushix			; Keep IX/IY
	pushiy
	lixd	param		; Point IX to parameters
	lxi	h, osret	; Return to here
	push	h
	
	; Check for allowable function calls
	mov	a, c
	cpi	JTOTAL
	jnc	unsupp		; Return if unknown (via unsupp)
	
	; Get address of function call
	mov	l, c		; H,L = 0,C (function)
	mvi	h, 0
	dad	h		; *2 for 2 bytes per entry
	lxi	d, jtab
	dad	d
	mov	e, m		; DE = address of code
	inx	h
	mov	d, m
	lhld	param		; Param to DE if needed
	xchg
	pchl			; Jump to routine

	; Restore program stack pointer and return via it
osret:	popiy			; Restore IX/IY
	popix
	lspd	pstack
	lhld	rval		; Return value
	mov	a, l
	mov	b, h
	ret
	
unsupp:	
	if	DEBUG
	call	prreg
	mvi	c, '!'
	call	list
	halt
	endif
	xra	a
	ret
	
	
	; DOS encountered an error. Print message and wait
	; for a key.
doserr:	push	d		; Keep error message to print
	call	crlf
	lda	disk		; Current disk in use
	adi	'A'		; Make it a character
	sta	diskm		; Store to message
	lxi	d, errm		; Print it
	call	print
	pop	d		; Restore error message
	call	print
	call	conin		; Wait for a key
	push	psw		; Newline
	call	crlf
	pop	psw
	cpi	CTRLC
	jz	WARM		; Warm boot
	; Else return with an error
	ori	0FFh		; Return with error
	sta	rval
	ret			; If not ctrl-c, ignore error
	

	;
	; Function 0Ch (12)
	;
	; Return version
	;
vers:	xra	a
	mov	b, a
	mvi	a, 022h
	sta	rval
	ret

	;
	; Clear data at DE for B bytes
	;
clrde:	xra	a
fill:	stax	d		; Also used to fill address with data
	inx	d
	djnz	fill
	ret	
	
clrhl:	xra	a
.1:	mov	m, a
	inx	h
	djnz	.1
	ret

	;
	; External assembler files included here
	;
	include	wdoswarm.asm
	include	wdosterm.asm
	include wdosfile.asm
	include	wdosfat.asm
	include	wdosdisk.asm
	
	
	;
	;
	; Debug
	;
	;
	if	DEBUG
prreg:	push	h
	push	d
	push	b
	push	psw
	
	lxi	h,1
	dad	sp
	mvi	b, 8	; Print stack
.1:	mov	a, m
	call	phex
	mov	a, b	; Print a space every other digit
	ani	1
	jz	.2
	mvi	c, ' '
	call	list
	lxi	d, 4
	dad	d
.2:	dcx	h
	djnz	.1

	pop	psw
	pop	b
	pop	d
	pop	h
	ret	

phex:	push	psw		; Will use A twice
	rar			; Shift upper to lower nibble
	rar
	rar
	rar
	call	phex1		; Print it
	pop	psw		; Restore original Acc
phex1:	ani	00Fh		; Mask off high nibble
	adi	090h		; Decimal adjust for ASCII
	daa
	aci	040h
	daa
	mov	c, a		; Print it
	jmp	list
	
	; Debug CRLF
dbcrlf:	mvi	c, CR
	call	list
	mvi	c, LF
	jmp	list

	endif

	; Messages
	;
	; Message followed by a 0 is non-fatal
	; Message followed by a 1 is fatal, Ctrl+C
	; must be pressed.
errm:	db	'Error on '
diskm:	db	' : $'		; Filled by doserr
nfmsg:	db	'Unable to load shell$'
datam:	db	'data error$'
selm:	db 	'no drive$'
filem:	db	'file '
ronlym:	db	'read only$'
fmtm:	db	'format$'

fcb:	db	0,'CMD     COM'
	dw	0,0,0,0,0,0,0,0,0,0,0,0
fcbi:	db	0,'           '
	dw	0,0
	db	0,'           '
	dw	0,0,0,0

; Stack to load shell
	dw	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
stack	equ	$

	
	if	BIN
	rept (MEMTOP-4)*1024-$
	db	0
	endm
	else
	org	(MEMTOP-4)*1024
	endif

	;
	; BIOS locations
	;
bios:	equ	(MEMTOP-4)*1024
wboot:	equ	bios+3
const:	equ	bios+6
conin:	equ	bios+9
conout:	equ	bios+12
list:	equ	bios+15
punch:	equ	bios+18
reader:	equ	bios+21
seldsk:	equ	bios+24
seek:	equ	bios+27
read:	equ	bios+30
write:	equ	bios+33
listst:	equ	bios+36


	end
	
