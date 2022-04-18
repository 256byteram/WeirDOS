#
# Z80 WeirDOS 0.4
#
# Makefile
#
#
# A Disk Operating System for Z80 microcomputers, implementing
# the CP/M 2.2 API and FAT12/FAT16 filesystems.
#
# Coptright (C) 2021 Alexis Kotlowy
#
# This file is part of WeirDOS (aka WDOS)
#
# WeirDOS is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# WeirDOS is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with WeirDOS.  If not, see <https://www.gnu.org/licenses/>.
#

DFLAGS=BIN
MAC=zmac
MACFLAGS=-8 --dri --zmac --oo cim,lst -I. --od . $(addprefix -D,$(DFLAGS))

# Additional files to copy to image
OSFILES=LICENSE.TXT option/*.*
# output disk image
DISKIMG=wdos.img

# Dependencies for WDOS source file
DEPS+=Z80.lib wdosterm.asm wdoswarm.asm
DEPS+=wdosfile.asm wdosdisk.asm wdosfat.asm
DEPS+=NOTICE.TXT
# Target system binary image
SYS=WDOS.SYS
# CLI binary
CLI=CLI.COM
# CLI dependencies
CLIDEPS=cli.asm
# WDOS system memory image
CIM=wdos.cim
# Binary file for WDOS loader
BCOPY=bcopy.cim
# BIOS memory image
BIOS=bios.cim
# Floppy disk image boot sector
BSECT=bsect.cim

all: $(DISKIMG)
debug: DFLAGS+=DEBUG
debug: $(DISKIMG)

%.cim: %.asm $(DEPS)
	$(MAC) $(MACFLAGS) $<


%.COM: $(CLIDEPS)
	$(MAC) $(MACFLAGS) $<
	mv $(basename $<).cim $(basename $@).COM

$(DISKIMG): $(SYS) $(BSECT) $(CLI) $(OSFILES)
	mformat -B $(BSECT) -f 720 -C -i $(DISKIMG)
	mcopy -i $(DISKIMG) $(SYS) ::
	mattrib -i $(DISKIMG) +r +h +s $(SYS)
	mcopy -i $(DISKIMG) $(CLI) ::
ifneq ($(OSFILES),)
	mcopy -i $(DISKIMG) $(OSFILES) ::
endif


$(SYS): $(CIM) $(BCOPY) $(BIOS)
	cat $(BCOPY) $(CIM) $(BIOS) > $@

.PHONY: clean

clean:
	rm -f $(SYS) $(CLI) *.cim *.lst $(DISKIMG)
	
