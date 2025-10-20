# compactflash.device
AmigaOS compactflash.device driver for CompactFlash cards in PCMCIA 

*Author*: Torsten Jager (t.jager@gmx.de); v1.32 (18.11.2009)
*Patched by*:  Paul Carter (); 1.33 (1.1.2017)

# Purpose

Read and write your digital photos, mp3 files etc. directly from CompactFlash cards as used by many mobile devices.

The OS supplied "carddisk.device" appeared to be unable to understand CF cards. I already had bought that adapter card, so I decided to write a suitable alternative myself.

# New

Finally I put this under LGPL :-)) Not plain GPL because an Amiga device driver is primarily used by the non-free OS to extend its functionality. Thus bundling the 2
should be possible. The preassembled binaries serve to make plain users life easier but you may rebuild them yourself now with AsmOne or something like that.

Added transfer mode autoconfiguration. Major API rework and optimizations for use in kickstart ROMs. Added more detailled error messages.

# A word on hardware

you will need a special adapter card labelled "CompactFlash to PCMCIA", to "PC Card" or to "ATA". It looks like a normal 5mm PCMCIA card with a smaller slot for CF cards at the front side.

There are two types of such adapters sold in good computer stores, for "CF Type 1" and "CF type 2" cards. The only two differences: "CF Type 2" adapters can also cope with thicker CF cards, like those expensive "MicroDrive"
harddisks; and b) they cost more. Mine is a "CF Type 1" which I got for EUR 10 (but I also saw the same model for the double price...).

* Some testing results:
```
16Mbyte card (Hitachi): 1.0 Mb/s read, 600 kb/s write.
64Mbyte card (PQI): 1.4 Mb/s read, 1.0 Mb/s write.
128 Mbyte card (Samsung): 2.1 Mb/s read, 1.4 Mb/s write.
2Gbyte card (Sandisk): 2.1 Mb/s read, 1.7 Mb/s write.
4Gbyte card (Kingston): 2.2 Mb/s read, 1.9 Mb/s write.
```

* Good news everyone

I got positive testing reports from CompactFlash, IBM MicroDrive, Sony MemoryStick and - taadaa! - SmartMedia adapter :^)) It may be required to re-insert the adapter after plugging the
memory card into it. Only for CompactFlash and MicroDrive, the plugging order is irrelevant.


# Another word on hardware

Commodore back then introduced the Amiga PCMCIA port before (!) the official PCMCIA standard was released. As a consequence, it is not fully compatible. Your results may vary on your actual hardware combination, including memory card, adapter, Amiga model, its chipset revision, and accelerator board model. In any case, your adapter MUST support old 16bit PC-CARD mode. Models who are 32bit CARDBUS only won`t work.

In conjunction with aminet/disk/misc/fat95.lha v3.09+, cfd can now use CF card`s built-in erase function if available. Erase is performed by the card implicitely on writes, but some cards remember the erased state and do faster write cycles afterwards. See also the fat95/english/readme.too file on that purpose.

Besides the usual AmigaOS error codes, there are some additional ones:
```
  73        Miscellanous Error
  96        Invalid Command
  97        Invalid CHS Address (Head or Sector number wrong)
  111        Invalid LBA Address (too large)
  117, 118    Supply or generated voltage out of tolerance
  81        Uncorrectable checksum
  88        Corrected read error
  69, 112-116, 119, 126    Self test or diagnosis failed
  80, 84    Sector ID not found
  122        Spare sectors exhausted
  95        Data transfer error, command aborted
  76, 120, 123, 124, 127 Media format corrupt
  67        Write or erase failed
  98        Command needs more supply power than currently allowed
  103        Media is write protected
```

# WARNING

"CompactFlash" is (TM) by CompactFlash Association ;-)


# System requirements

* AMIGA 1200 or 600, OS 2.0+
* "CompactFlash to PCMCIA/ATA" adapter card, see adapter.jpg for an example
* fat95 file system (disk/misc/fat95.lha)

# Installation
```
Copy cfd/devs/compactflash.device to DEVS:
```
Have fat95 installed on your system. Mount the drive by double-clicking cfd/devs/CF0.

If you run OS 3.5+: 
```
Copy cfd/def_CF0.info sys:prefs/env-archive/sys
Copy cfd/def_CF0.info env:sys
```

# Problems

If some trouble occurs, like cards not recognized by cfd, please:
* report exact hardware type.
* mount CF0: if not already done.
* insert that very card.
* wait at least 1 second (yes, honestly).
* take cfd/c/cfddebug and type into a shell
```
cfddebug ram:cfdlog
```
* send ro `t.jager@gmx.de (Torsten Jager)` the binary file just created (about 4 kbytes). I promise there are no passwords and such in it.

In case there is another PCMCIA driver (eg. a network card driver) blocking the card socket, try setting the CF0 mountlist entry "Flags" to
```
Flags = 1    /* enable "cfd first" hack */
```
Damaged or simply not quite officially standardized cards may sometimes cooperate using
```
Flags = 2    /* skip invalid PCMCIA signature */
```

# History
* v1.01    02/2002    First experiments.
* v1.02    03/2002    Minimal exec command set to work with filesystems.
* v1.03    03/2002    Added auto-repeat for faulty CF cards. 
* v1.04    03/2002    Removed numerous bugs. Added quiet shutdown if non-CF cards are inserted.
* v1.05    03/2002    Added TD64 and SCSI emulation support.
* v1.06    03/2002    Card interface moved to PCMCIA I/O address space.
* v1.07    04/2002    Added debug tool and disk icon.
* v1.08    04/2002    Changed interrupt handling. Made read access a bit faster.
* v1.09    05/2002    Added "cfd first" hack. Added SCSI 6 byte read/write commands.
* v1.10    05/2002    Added PCMCIA status change handling.
* v1.11    06/2002    Fixed SCSI "Inquiry" command emulation. Set card programming voltage to 5VDC.
* v1.12    06/2002    Added slowed down transfer mode. Added PCMCIA speed check tool.
* v1.13    06/2002    Removed slowdown again, didn't fix the problem. Added "double read" and "double write" workarounds. Added read/write check tool.
* v1.14    07/2002    Removed "double write" kludge again (was unnecessary). Added ready check befor command issueing.
* v1.15    08/2002    Added ATAPI support.
* v1.16    08/2002    Added transfer mode testing module. Set word access as default.
* v1.17    08/2002    Added transfer mode autosense. Disabled card´s address decoder.
* v1.18    09/2002    Added "forced card socket activation" hack.
* v1.19    10/2002    New option: accept cards without valid signature.
* v1.20    10/2002    Fixed ATAPI bug. Added spinup from standby mode.
* v1.21    04/2003    Fixed "multiple mode" bug. Added "write multiple" support. Added PCMCIA soft reset. Added CFA_ERASE support.
* v1.22    05/2003    Added alternative card socket resetting code.
* v1.23    06/2003    Added IDE interrupt enabling.
* v1.24    10/2003    Trying to add support for a certain CDROM adapter, who unfortunately turned out to be CARDBUS.
* v1.25    07/2004    Added interrupt watchdog, avoiding occasional "lock-ups".
* v1.27    02/2009    Added fast interrupt support for Kingston and similar cards.
* v1.28    04/2009    First attempt to make cfd ROMable.
* v1.29    11/2009    Added transfer mode autoconfiguration. New "dd" version including speed gauge and performance test.
* v1.30    11/2009    Major API rework and optimizations for use in kickstart ROMs.
* v1.31    11/2009    Fixed bug in "memory mapped" mode. Further optimizations.
* v1.32    11/2009    Added more detailled error messages. 04/2014    Removed "dd" as it is part of "fat95". Finally made this open source.
* v1.33    1/2017     Makes init routie more reliable.  Cards that previously would, Not work might now start to work.  Tested with a variety of SD cards in an SD to CF adapter and now all SD cards initialise properly and work reliably.  Cheap storage now available for all Succesfully tested 32gb SD cards with fat95 v3.18. See ADAPTER2.JPG for the type of adapter used.

Have Fun!
