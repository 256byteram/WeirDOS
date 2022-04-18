# WeirDOS

Released under the GPL v3

**Requirements:**
   - zmac macro assembler <http://48k.ca/zmac.html>  
   - mtools <https://www.gnu.org/software/mtools/>  
   - Z80 Emulator for debugging <http://www.z80.info/z80emu.htm#EMU_CPU_W32>  
   - GNU Make utility

Z80 Emulator is a Windows program, but works fine under Wine on Linux.

**Build on Linux:**  
Should be as simple as typing 'make'. It will generate
a 720k DD disk image that can be booted in ZEMU.

Building with 'make debug' will include the -DDEBUG flag when assembling.

**Command Line Interface:**
The CLI is extremely basic at the moment. The following commands are implemented:
   - TYPE
   - DIR

TYPE sends the contents of a file to the console. DIR shows a directory listing.

Transient commands can be executed by typing the name of the .COM file.

**TODO:**
   - Debug on real hardware
   - Build option for Windows

