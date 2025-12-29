# compactflash.device

AmigaOS compactflash.device driver for CompactFlash cards in PCMCIA

**Fork** of the original driver by Torsten Jager, with improvements for >4GB cards.

| Version | Author | Date |
|---------|--------|------|
| v1.32 | Torsten Jager | 18.11.2009 |
| v1.33 | Paul Carter | 1.1.2017 |
| v1.34 | Jaroslav Pulchart | 22.10.2025 |

## Download

* **Aminet**: [driver/media/cfd134](https://aminet.net/package/driver/media/cfd134)
* **GitHub**: [Releases](https://github.com/pulchart/cfd/releases)

## What's New in v1.34

* Made >4GB CompactFlash cards usable
  - Workaround for "get IDE ID" on large capacity cards
  - Limited multi-sector IOs for reliability on >4GB cards
* Tested with AmigaOS 3.2.3

## Purpose

Read and write your digital photos, mp3 files etc. directly from CompactFlash cards as used by many mobile devices.

The OS supplied "carddisk.device" appeared to be unable to understand CF cards. This driver provides a suitable alternative.

## System Requirements

* Amiga 1200 or 600
* AmigaOS 2.0+ (tested with 3.2.3)
* "CompactFlash to PCMCIA/ATA" adapter card (see adapter.jpg)
* fat95 file system (disk/misc/fat95.lha)

## Installation

```
Copy devs/compactflash.device to DEVS:
```

Have fat95 installed on your system. Mount the drive by double-clicking `devs/CF0`.

For OS 3.5+:
```
Copy def_CF0.info sys:prefs/env-archive/sys
Copy def_CF0.info env:sys
```

## Hardware Notes

You will need a special adapter card labelled "CompactFlash to PCMCIA", "PC Card" or "ATA". It looks like a normal 5mm PCMCIA card with a smaller slot for CF cards at the front side.

There are two types of such adapters:
* **CF Type 1** - for standard thickness CF cards
* **CF Type 2** - also supports thicker cards like MicroDrive (costs more)

### Compatibility

Positive testing reports from:
* CompactFlash
* IBM MicroDrive
* Sony MemoryStick (with adapter)
* SmartMedia (with adapter)

It may be required to re-insert the adapter after plugging the memory card into it. Only for CompactFlash and MicroDrive, the plugging order is irrelevant.

### Speed Test Results

Retaken from readme of version 1.32/1.33:

| Card | Read | Write |
|------|------|-------|
| 16MB Hitachi | 1.0 MB/s | 600 KB/s |
| 64MB PQI | 1.4 MB/s | 1.0 MB/s |
| 128MB Samsung | 2.1 MB/s | 1.4 MB/s |
| 2GB Sandisk | 2.1 MB/s | 1.7 MB/s |
| 4GB Kingston | 2.2 MB/s | 1.9 MB/s |

### Important Notes

Commodore introduced the Amiga PCMCIA port before the official PCMCIA standard was released. As a consequence, it is not fully compatible. Your results may vary depending on your hardware combination. Your adapter **MUST** support old 16bit PC-CARD mode. 32bit CARDBUS-only adapters won't work.

In conjunction with fat95 v3.09+, cfd can use CF card's built-in erase function if available.

## Workarounds

### PCMCIA conflicts with other drivers
```
Flags = 1    /* enable "cfd first" hack */
```

### Cards without valid PCMCIA signature
```
Flags = 2    /* skip invalid PCMCIA signature */
```


## Error Codes

Besides the usual AmigaOS error codes, there are some additional ones:

| Code | Description |
|------|-------------|
| 67 | Write or erase failed |
| 73 | Miscellaneous Error |
| 76, 120, 123, 124, 127 | Media format corrupt |
| 80, 84 | Sector ID not found |
| 81 | Uncorrectable checksum |
| 88 | Corrected read error |
| 95 | Data transfer error, command aborted |
| 96 | Invalid Command |
| 97 | Invalid CHS Address |
| 98 | Command needs more power than allowed |
| 103 | Media is write protected |
| 111 | Invalid LBA Address (too large) |
| 69, 112-116, 119, 126 | Self test or diagnosis failed |
| 117, 118 | Voltage out of tolerance |
| 122 | Spare sectors exhausted |

## Troubleshooting

Report issues at: https://github.com/pulchart/cfd/issues

If cards are not recognized:
1. Mount CF0: if not already done
2. Insert the card
3. Wait at least 1 second
4. Run: `cfddebug ram:cfdlog`
5. Report the log file along with your hardware details

*Note: cfddebug log processing was valid for original maintainer and previous releases.*

## History

| Version | Date | Changes |
|---------|------|---------|
| v1.34 | 10/2025 | >4GB CF card support (Jaroslav Pulchart) |
| v1.33 | 1/2017 | Init reliability fix, SD card adapter support (Paul Carter) |
| v1.32 | 11/2009 | Error messages, open source release (Torsten Jager) |
| v1.31 | 11/2009 | Fixed "memory mapped" mode bug |
| v1.30 | 11/2009 | Major API rework for kickstart ROMs |
| v1.29 | 11/2009 | Transfer mode autoconfiguration |
| v1.28 | 04/2009 | First ROMable attempt |
| v1.27 | 02/2009 | Fast interrupt support for Kingston cards |
| v1.25 | 07/2004 | Interrupt watchdog |
| v1.24 | 10/2003 | CARDBUS investigation |
| v1.23 | 06/2003 | IDE interrupt enabling |
| v1.22 | 05/2003 | Alternative card socket reset |
| v1.21 | 04/2003 | Write multiple, PCMCIA soft reset, CFA_ERASE |
| v1.20 | 10/2002 | ATAPI fix, spinup from standby |
| v1.19 | 10/2002 | Accept cards without valid signature |
| v1.18 | 09/2002 | Forced card socket activation |
| v1.17 | 08/2002 | Transfer mode autosense |
| v1.16 | 08/2002 | Transfer mode testing, word access default |
| v1.15 | 08/2002 | ATAPI support |
| v1.14 | 07/2002 | Ready check before commands |
| v1.13 | 06/2002 | Double read workaround |
| v1.12 | 06/2002 | Slowed transfer mode, PCMCIA speed tool |
| v1.11 | 06/2002 | SCSI Inquiry fix, 5VDC programming voltage |
| v1.10 | 05/2002 | PCMCIA status change handling |
| v1.09 | 05/2002 | "cfd first" hack, SCSI 6-byte commands |
| v1.08 | 04/2002 | Interrupt handling, faster reads |
| v1.07 | 04/2002 | Debug tool and disk icon |
| v1.06 | 03/2002 | PCMCIA I/O address space |
| v1.05 | 03/2002 | TD64 and SCSI emulation |
| v1.04 | 03/2002 | Bug fixes, quiet shutdown |
| v1.03 | 03/2002 | Auto-repeat for faulty cards |
| v1.02 | 03/2002 | Minimal exec command set |
| v1.01 | 02/2002 | First experiments |

## License

GNU Lesser General Public License v2.1

## Trademark

"CompactFlash" is (TM) by CompactFlash Association

---

Have Fun!
