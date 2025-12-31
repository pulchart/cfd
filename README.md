# compactflash.device

AmigaOS compactflash.device driver for CompactFlash cards in PCMCIA

**Fork** of the original driver by Torsten Jager, with improvements for >4GB cards.

| Version | Author | Date |
|---------|--------|------|
| v1.32 | Torsten Jager | 18.11.2009 |
| v1.33 | Paul Carter | 1.1.2017 |
| v1.34 | Jaroslav Pulchart | 22.10.2025 |
| v1.35 | Jaroslav Pulchart | 31.12.2025 |

## Download

* **Aminet (v1.34)**: [driver/media/cfd134](https://aminet.net/package/driver/media/cfd134)
* **GitHub**: [Releases](https://github.com/pulchart/cfd/releases)

## What's New in v1.35

* **Serial debug output** - set `Flags = 8` to enable debug messages via serial port
  - Shows card insert/remove, identification, size, and MultiSize
  - Replaces cfddebug tool with readable text-based serial output
* **Enforce multi mode** - set `Flags = 16` to force 256 sector reads/writes per IO request, even if card firmware does not support it
  - Can improve performance on capable cards (1MB/s → 2MB/s)
  - **Warning:** May cause data corruption on unsupported cards - see Enforce Multi Mode section below
* **Simplified SD-to-CF adapter support** - cleaner retry mechanism for IDENTIFY command

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
* "CompactFlash to PCMCIA/ATA" adapter card (see images/adapter.jpg)
* fat95 file system (disk/misc/fat95.lha)

## Installation

Two versions of the driver are provided:

| File | Size | Description |
|------|------|-------------|
| `compactflash.device` | ~10.5 KB | Full version with serial debug support |
| `compactflash.device.nodebug` | ~8.3 KB | Smaller version without debug code |

Choose the version you need:
- Use the **full version** if you need serial debug output (`Flags = 8`)
- Use the **small version** for minimal memory footprint

```
Copy devs/compactflash.device to DEVS:
```
(or `compactflash.device.nodebug`, renamed to `compactflash.device`)

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

### Important Notes

Commodore introduced the Amiga PCMCIA port before the official PCMCIA standard was released. As a consequence, it is not fully compatible. Your results may vary depending on your hardware combination. Your adapter **MUST** support old 16bit PC-CARD mode. 32bit CARDBUS-only adapters won't work.

In conjunction with fat95 v3.09+, cfd can use CF card's built-in erase function if available.

## Mount Flags

Set in CF0 mountlist. Flags can be combined (e.g., `Flags = 9` for cfd first + serial debug).

| Flag | Value | Description |
|------|-------|-------------|
| cfd first | 1 | Enable "cfd first" hack for PCMCIA conflicts |
| skip signature | 2 | Skip invalid PCMCIA signature check |
| compatibility | 4 | Compatibility mode |
| serial debug | 8 | Enable serial debug output (v1.35+) |
| enforce multi mode | 16 | Issues 256 sector read/write for each IO (v1.35+) |

### Example: Enable serial debug
```
Flags = 8
```
Then monitor serial port (e.g., `screen /dev/ttyUSB0 9600` or `minicom -b 9600 -o -D /dev/ttyUSB0`) to see:
```
[CFD] Card inserted
[CFD] Identifying card...
[CFD] Reset
[CFD] Configuring HBA
[CFD] ..done
[CFD] Setting voltage
[CFD] Voltage: 5V
[CFD] Reading tuples
[CFD] Tuple CISTPL_CONFIG found
[CFD] RW test
[CFD] ..done
[CFD] Transfer: WORD
[CFD] Getting IDE ID
[CFD] ..done
[CFD] Model: TS4GCF133...............................
[CFD] Serial: G68120052383AC0700C7
[CFD] FW: 20110407
[CFD] IDENTIFY:
  Max Multi (W47):      8001
  Capabilities (W49):   0200
  Multi Setting (W59):  0100
  LBA Sectors (W60-61): 00777E70
  DMA Modes (W63):      0000
  PIO Modes (W64):      0003
  UDMA Modes (W88):     0000
[CFD] IDENTIFY (raw):
W0: 848A 1E59 0000 0010 0000 0240 003F 0077 
W8: 7E70 0000 4736 3831 3230 3035 3233 3833 
W16: 4143 3037 3030 4337 0002 0002 0004 3230 
W24: 3131 3034 3037 5453 3447 4346 3133 3320 
W32: 2020 2020 2020 2020 2020 2020 2020 2020 
W40: 2020 2020 2020 2020 2020 2020 2020 8001 
W48: 0000 0200 0000 0200 0000 0003 1E59 0010 
W56: 003F 7E70 0077 0100 7E70 0077 0000 0000 
W64: 0003 0000 0000 0078 0078 0000 0000 0000 
W72: 0000 0000 0000 0000 0000 0000 0000 0000 
W80: 0000 0000 702A 500C 4000 0000 0004 4000 
W88: 0000 0001 0000 0000 FFFE 0040 0000 0000 
W96: 0000 0000 0000 0000 0000 0000 0000 0000 
W104: 0000 0000 0000 0000 0000 0000 0000 0000 
W112: 0000 0000 0000 0000 0000 0000 0000 0000 
W120: 0000 0000 0000 0000 0000 0000 0000 0000 
W128: 0001 0000 0000 0000 0000 0000 0000 0000 
W136: 0000 0000 0000 0000 0000 0000 0000 0000 
W144: 0000 0000 0000 0000 0000 0000 0000 0000 
W152: 0000 0000 0000 0000 0000 0000 0000 0000 
W160: 81F4 0000 0000 0000 891B 0000 0000 0000 
W168: 0000 0000 0000 0000 0000 0000 0000 0000 
W176: 0000 0000 0000 0000 0000 0000 0000 0000 
W184: 0000 0000 0000 0000 0000 0000 0000 0000 
W192: 0000 0000 0000 0000 0000 0000 0000 0000 
W200: 0000 0000 0000 0000 0000 0000 0000 0000 
W208: 0000 0000 0000 0000 0000 0000 0000 0000 
W216: 0000 0000 0000 0000 0000 0000 0000 0000 
W224: 0000 0000 0000 0000 0000 0000 0000 0000 
W232: 0000 0000 0000 0000 0000 0000 0000 0000 
W240: 0000 0000 0000 0000 0000 0000 0000 0000 
W248: 0000 0000 0000 0000 0000 0000 0000 0000 
[CFD] Init multi mode
[CFD] ..card supports max multi: 1
[CFD] ..setting multi mode to: 1
[CFD] ..OK
[CFD] ..override multi size: 256
[CFD] ..done
[CFD] Card identified OK
[CFD] Notify clients
[CFD] Card removed
```

### Enforce Multi Mode (Flag 16)

Read and Write IO path will use 256 sectors for single IO regardless of what the card supports in Multiple Sector Mode if this flag is set (same behaviour as v1.33). The IO sector count can be limited by `MaxTransfer` (0x200 = 1 sector per IO) value in CF0 file.

**Warning:** Verify your card is capable before using for real data. Set the flag and read any text file from CF card (e.g., `type CF0:readme.txt`). The content should not contain repeating 32-byte pattern after first 512 bytes. See `images/multimode.issue.jpg` for an example of what broken output looks like on unsupported cards.

```
Flags = 16
```

Combine with serial debug for testing:
```
Flags = 24
```

```
Flags = 16
MaxTransfer = 0x10000   /* 128 sectors per IO (64 KB) */
```

```
Flags = 24
MaxTransfer = 0x10000   /* debug + enforce mode, 128 sectors per IO */
```

**Tested configurations (author's experience - your results may vary):**
| Card Type | Capacity | Enforce Multi Mode |
|-----------|----------|-------------------|
| SD-to-CF adapter (SanDisk) | 32GB | ✓ Works |
| SD-to-CF adapter (Samsung) | 32GB, 64GB | ✓ Works |
| CF cards | ≤4GB | ✓ Works |
| CF cards | >4GB | ✗ Not working |

### Speed Test Results

Retaken from readme of version 1.32/1.33. Those versions behave as if **Enforce Multi Mode** is enabled.

| Card | Read | Write |
|------|------|-------|
| 16MB Hitachi | 1.0 MB/s | 600 KB/s |
| 64MB PQI | 1.4 MB/s | 1.0 MB/s |
| 128MB Samsung | 2.1 MB/s | 1.4 MB/s |
| 2GB Sandisk | 2.1 MB/s | 1.7 MB/s |
| 4GB Kingston | 2.2 MB/s | 1.9 MB/s |

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
1. Set `Flags = 8` in CF0 mountlist to enable serial debug
2. Connect serial cable and monitor (9600 baud)
3. Mount CF0: if not already done
4. Insert the card
5. Wait at least 1 second
6. Check serial output for `[CFD]` messages
7. Report the serial log along with your hardware details

## History

| Version | Date | Changes |
|---------|------|---------|
| v1.35 | 12/2025 | Debug via serial line, enforce multi mode, SD-to-CF fix (Jaroslav Pulchart) |
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

## Building from Source

### Requirements

* **vasm** - Portable 68k assembler ([sun.hasenbraten.de/vasm](http://sun.hasenbraten.de/vasm/))
* **lha** - For creating release archives (optional)

### Quick Start

```bash
# Build both versions
make

# Build only full version
make debug

# Build only small version (no debug)
make small

# Show checksums
make checksums

# Create Aminet release archive
make release
```

### Build Targets

| Target | Description |
|--------|-------------|
| `make` | Build both full and small versions |
| `make full` | Build full version only |
| `make small` | Build nodebug version only |
| `make release` | Create Aminet LHA archive |
| `make checksums` | Show file sizes and checksums |
| `make clean` | Remove built device files |
| `make distclean` | Remove all generated files |

### Output Files

| File | Description |
|------|-------------|
| `devs/compactflash.device` | With serial debug support (`Flags = 8`) |
| `devs/compactflash.device.nodebug` | Minimal, no debug code |

### Cross-Compilation

The source uses Motorola 68k syntax compatible with both ASMPro (Amiga) and vasm (Linux):

```bash
vasmm68k_mot -Fhunkexe -m68020 -nosym -DDEBUG=1 -o compactflash.device src/cfd.s
```

## License

GNU Lesser General Public License v2.1

## Trademark

"CompactFlash" is (TM) by CompactFlash Association

---

Have Fun!
