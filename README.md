# compactflash.device

AmigaOS compactflash.device driver for CompactFlash cards in PCMCIA. Fork of the original driver by Torsten Jager.

## Download

**GitHub**: [Releases](https://github.com/pulchart/cfd/releases)

## Purpose

Read and write your digital photos, MP3 files, and other media directly from CompactFlash cards, as used by many mobile devices.

The AmigaOS-supplied `carddisk.device` appeared to be unable to properly handle CF cards. This driver provides a suitable alternative.

### Personal Note

Improvements to this driver are developed in my free time. If you'd like to support ongoing maintenance and experimentation, you can do so on [Ko-fi](https://ko-fi.com/jaroslavpulchart).

You can also follow project planning and updates here: [Planning for 2026](https://ko-fi.com/post/Planning-for-2026-S6S81S7IZH).

### Community Links

- **English Amiga Forum Thread:** [Discussion Thread](https://eab.abime.net/showthread.php?t=121575) user questions and troubleshooting.
- **Aminet CFD Advanced Search:** [CFD releases (m68k, AmigaOS)](https://aminet.net/search?type=advanced&name=cfd&q_path=AND&path%5B%5D=driver&q_date=AND&o_date=equal&date=&q_desc=OR&desc=&q_readme=AND&readme=&q_content=AND&content=&q_arch=AND&arch%5B%5D=m68k-amigaos&search=search) shows all CFD packages, including v1.34+.

## What's New in

### v1.38-dev

#### Driver

Reworks CIS handling to avoid side effects with non-storage PCMCIA cards (e.g. WiFi) and restores PCMCIA (Gayle) timing setup.

* **CIS gate (PCMCIA card type filter)** ([#25](https://github.com/pulchart/cfd/issues/25))
  - Reads `CISTPL_FUNCID` (when available) and rejects non-disk cards early to avoid interfering with other PCMCIA devices (e.g. WiFi).
  - If `CISTPL_FUNCID` is missing/unreadable, the driver continues for compatibility (some CF cards/adapters do not provide reliable CIS tuples).

* **PCMCIA (Gayle) timing setup**
  - Restores access timing setup from `CISTPL_DEVICE` via `CardAccessSpeed` (v1.37 didn't program timing based on CIS speed).

#### Tools

* **pcmciacheck simplifies test output**

#### Others

TBD

### v1.37

#### Driver

* **Improved card detection reliability**
  - Fixes unreliable CopyTuple CIS reads by using the card's ATA IDENTIFY data instead. Seen with Transcend CF 133 4GB (Firmware 20110407) and ACA1234.
  - The config address is still read from the card CIS when available, with an automatic fallback to the standard address.
  - `Flags = 2` is deprecated (the fallback is now automatic).

* **Autodetect multi-sector override capability**
  - Driver estimates by simple test during init if multi-sector override works
  - If test passes (DRQ clears properly), 256 sector mode is enabled for best performance
  - If test fails (DRQ stays high), falls back to firmware-reported value for compatibility
  - `Flags = 16` still available as manual override to force 256 sector mode
  - `Flags = 32` skips auto-detection and uses firmware-reported value directly
  - Debug output shows detection result: "DRQ issue not detected" / "DRQ issue detected"

* **CFD_GETCONFIG command (0xED)**
  - New SCSI passthrough command to retrieve driver internal configuration

#### Tools

* **CFInfo shows driver configuration**
  - Displays mount flags, multi-sector settings (firmware vs actual)
  - Requires driver v1.37+ for config display (card info still works with v1.36+)

* **pcmciacheck tests all 5 transfer modes**
  - Added mode 4 (MMAP) memory-mapped transfer testing

#### Others

* Typo fixes throughout documentation

### v1.36

#### Driver

* **MuForce hit fix when using Format** ([#8](https://github.com/pulchart/cfd/issues/8))
  - Fixed memory access issue detected by MuForce during disk formatting operations
* **Clear stale card data on removal**
  - CFU_IDEStatus, CFU_IDEError, CFU_IDEAddr, CFU_ConfigAddr cleared when card is removed
  - CFU_MultiSize, CFU_MultiSizeRW cleared to reset multi-sector settings
  - 512-byte IDENTIFY buffer (CFU_ConfigBlock) fully cleared - prevents stale model/serial/firmware/capacity data
  - Prevents returning stale data when no card is present or after card swap
* **SD-to-CF adapter retry fix**
  - when ATA IDENTIFY retries exhaust (regression in v1.33), now tries ATAPI IDENTIFY PACKET DEVICE before giving up (as v1.32)
  - Fixes potential hang on SD-to-CF adapters
* **Implement ATA_IDENTIFY command**
  - retrieve the cached ATA IDENTIFY data from the driver

#### Tools

* **CFInfo utility**
  - displays card model, serial, firmware, capacity, and capabilities
* **pcmciaspeed utility**
  - Recreated PCMCIA memory access timing benchmark tool
* **pcmciacheck utility**
  - Recreated PCMCIA check tool

#### Others

* **AmigaGuide documentation**
  - Native Amiga .guide files included in release
* **Gayle memory timing**
  - Experimental: disabled by default, compile with `FASTPIO=1` to enable
  - Maps card's ATA PIO mode to Gayle PCMCIA memory timing
* **Improved code documentation**
  - Architecture overview with register conventions
  - Documented CFU structure fields
  - Added function headers with input/output/register usage

### v1.35

* **Serial debug output** - set `Flags = 8` to enable debug messages via serial port
  - Shows card insert/remove, identification, size, and MultiSize
  - Replaces cfddebug tool with readable text-based serial output
* **Enforce multi mode** - set `Flags = 16` to force 256 sector reads/writes per IO request, even if card firmware does not support it
  - Can improve performance on capable cards (1MB/s → 2MB/s)
  - **Warning:** May cause data corruption on unsupported cards - see Enforce Multi Mode section below
* **Simplified SD-to-CF adapter support** - cleaner retry mechanism for IDENTIFY command introduced in v1.33

### v1.34

* Improved compatibility with >4GB CF cards
  - Workaround for "get IDE ID" on large capacity cards
  - Multi-sector IO uses firmware reported value to improve compatibility

## System Requirements

* Amiga 1200 or 600 (A1200 tested)
* AmigaOS 2.0+ (tested with 3.2.3)
* CF-to-PCMCIA adapter or SD-to-CF adapter (see [Hardware Notes](#hardware-notes))
* fat95 file system (disk/misc/fat95.lha)

## Installation

Two versions of the driver are provided:

| File | Size | Description |
|------|------|-------------|
| `compactflash.device` | ~10.3 KB | Driver with debug to serial console flag support |
| `compactflash.device.small` | ~8.3 KB | Driver without debug to serial console support |

Choose the version you need:
- Use the **full version** if you need serial debug output (`Flags = 8`)
- Use the **small version** for minimal memory footprint

```
Copy devs/compactflash.device to DEVS:
Copy c/CFInfo to C:
```
(or `compactflash.device.small`, renamed to `compactflash.device`)

Have fat95 installed on your system. Mount the drive by double-clicking `devs/CF0`.

For OS 3.5+:
```
Copy def_CF0.info sys:prefs/env-archive/sys
Copy def_CF0.info env:sys
```

## Hardware Notes

You will need a special adapter card labelled "CompactFlash to PCMCIA", "PC Card" or "ATA". It looks like a normal 5mm PCMCIA card with a smaller slot for CF cards at the front side (see [images/cf-pcmcia-adapter.jpg](images/cf-pcmcia-adapter.jpg)).

There are two types of such adapters:
* **CF Type 1** - for standard thickness CF cards
* **CF Type 2** - also supports thicker cards like MicroDrive (costs more)

Alternatively, you can use an SD-to-CF adapter with SD cards (see [images/sd-cf-adapter.jpg](images/sd-cf-adapter.jpg)).

Tested with CompactFlash cards (16MB, 4GB, 8GB, 16GB, 32GB, 64GB) and SD cards via SD-to-CF adapter (SanDisk, Samsung MicroSD).

**Note:** Commodore introduced the Amiga PCMCIA port before the official PCMCIA standard was released. Your results may vary depending on your hardware combination. Your adapter **MUST** support old 16bit PC-CARD mode. 32bit CARDBUS-only adapters won't work.

In conjunction with fat95 v3.09+, cfd can use CF card's built-in erase function if available.

## Mount Flags

Set in CF0 mountlist. Flags can be combined (e.g., `Flags = 9` for cfd first + serial debug).

| Flag | Value | Description |
|------|-------|-------------|
| `cfd first` | 1 | Enable "cfd first" hack for PCMCIA conflicts with other drivers |
| `skip signature` | 2 | **unused** (v1.37+) - was "skip invalid PCMCIA signature" - as fallback happens automatically |
| `compatibility` | 4 | Use CardResource OS API instead of direct chipset access |
| `serial debug` | 8 | Output initialization messages to serial port at 9600 baud (v1.35+ full build) |
| `enforce multi mode` | 16 | Force 256 sector transfers regardless of card's reported capability (v1.35+) |
| `skip override auto-detect` | 32 | Skip multi-sector override auto-detection, use firmware value (v1.37+) |

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
[CFD] CIS gate
[CFD] ..DEVICE: type=0x0D speed=400ns size=0x00000800
[CFD] ..FUNCID: 0x04
[CFD] ..RESULT: accept
[CFD] ..CONFIG: addr=0x00000200
(or: [CFD] ..CONFIG: default (0x200))
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
...
W248: 0000 0000 0000 0000 0000 0000 0000 0000 
[CFD] Init multi mode
[CFD] ..card supports max multi: 1
[CFD] ..setting multi mode to: 1
[CFD] ..OK
[CFD] ..testing multi-sector capability...
[CFD] ..DRQ issue not detected
[CFD] ..auto-enabling 256 sector mode
[CFD] ..multi-sector RW size: 256
[CFD] ..done
[CFD] Card identified OK
[CFD] Notify clients
[CFD] Card removed
```

### Enforce Multi Mode (Flag 16)

Read and Write IO path will use 256 sectors for single IO regardless of what the card supports in Multiple Sector Mode if this flag is set (same behaviour as v1.33). The IO sector count can be limited by `MaxTransfer` (0x200 = 1 sector per IO) value in CF0 file.

**Warning:** Verify your card is capable before using for real data. Set the flag and read any text file from CF card (e.g., `type CF0:cfd.s`). The content should not contain repeating 32-byte pattern after first 512 bytes. See [images/multimode-issue.jpg](images/multimode-issue.jpg) for an example of what broken output looks like on unsupported cards.

**Note:** As of v1.37, the driver uses a simple initialization test to automatically detect multi-sector operation and enables it when test pass. This flag is now only needed as a manual override if auto-detection fails for your specific card. Set Flags = 32 if detection does not work correctly with your card to disable auto-detection entirely.

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

## Transfer Modes

The driver auto-detects the transfer mode during card initialization by testing which PCMCIA access methods work reliably:

| Mode | Description |
|------|-------------|
| WORD | 16-bit word access to PCMCIA I/O register. Standard mode for most CF cards. |
| BYTE (data) | 8-bit byte access with high/low bytes at adjacent addresses. For cards that don't support 16-bit transfers. |
| BYTE (alt) | 8-bit byte access with high/low bytes at separate I/O addresses. For specific adapter configurations. |
| BYTE (alt2) | 8-bit byte access via alternate register. Rarely used fallback mode. |
| MMAP | Memory mapped word access. Direct memory transfer (requires PCMCIA memory mapping). |

Most CF cards work with WORD mode. The driver tests write/read patterns during initialization and falls back to BYTE modes if 16-bit access fails. The selected mode is shown in serial debug output as `[CFD] Transfer: WORD` or similar.

## Tools

### CFInfo

Displays card information (requires driver v1.36+). With driver v1.37+, it also shows the driver configuration. See [CFInfo.md](docs/CFInfo.md) for a detailed field reference.

### pcmciaspeed

PCMCIA memory access timing benchmark. See [pcmciaspeed.md](docs/pcmciaspeed.md) for detailed documentation.

### pcmciacheck

PCMCIA CompactFlash card compatibility testing tool. Tests the same read/write modes used by the driver to validate card compatibility. See [pcmciacheck.md](docs/pcmciacheck.md) for detailed documentation.

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

1. Set `Flags = 8` in CF0 mountlist to enable serial debug
2. Connect serial cable and monitor (9600 baud)
3. Mount CF0:
4. Insert the card
5. Check serial output for `[CFD]` messages
6. Report the serial log along with your hardware details

## History

| Version | Date | Changes |
|---------|------|---------|
| v1.38 | 01/2026 | TBD |
| v1.37 | 01/2026 | IDENTIFY-based detection, auto multi-sector override, CFInfo mount flags display |
| v1.36 | 01/2026 | CFInfo tool, pcmciacheck/pcmciaspeed tools, MuForce fix, stale data cleanup |
| v1.35 | 12/2025 | Serial debug (Flags=8), enforce multi mode (Flags=16), SD-to-CF support simplification |
| v1.34 | 10/2025 | Improved compatibility with >4GB CF cards (Jaroslav Pulchart) |
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
* **vbcc** - C compiler for CFInfo tool (optional, [compilers.de/vbcc](http://www.compilers.de/vbcc.html))
* **NDK** - AmigaOS NDK headers for CFInfo (optional, [aminet.net NDK3.2](https://aminet.net/package/dev/misc/NDK3.2R4))
* **lha** - For creating release archives (optional)

### NDK Setup (for CFInfo)

Extract NDK to project directory:
```bash
mkdir NDK && cd NDK && lha x ~/Downloads/NDK3.2.lha
```

### Quick Start

```bash
# Build all (driver + CFInfo)
make

# Build with custom tool paths (prefix), the binaries are in prefix/bin/...
make VASM_HOME=/path/to/vasm VBCC_HOME=/path/to/vbcc

# Verbose output
make V=1
```

### Build Options

| Option | Description |
|--------|-------------|
| `V=1` | Verbose output (show full compiler messages) |
| `FASTPIO=1` | Enable Gayle timing optimization (experimental) |
| `COPYBURST=1` | Enable MOVEM transfers (experimental) |
| `VASM_HOME=` | vasm installation path (default: /opt/vbcc) |
| `VBCC_HOME=` | vbcc installation path (default: /opt/vbcc) |

### Build Targets

| Target | Description |
|--------|-------------|
| `make` | Build driver (full + small) and CFInfo |
| `make full` | Build full version only (with debug support) |
| `make small` | Build small version only (no debug) |
| `make tools` | Build utilitties (requires vbcc + NDK) |
| `make fastpio` | Build with Gayle timing optimization (experimental) |
| `make release` | Create Aminet LHA archive |
| `make checksums` | Show file sizes and checksums |
| `make clean` | Remove built files |
| `make help` | Show all available targets |

### Cross-Compilation Notes

The assembly source uses Motorola 68k syntax compatible with both ASMPro (Amiga) and vasm (Linux/cross).

```bash
# Manual vasm invocation
vasmm68k_mot -Fhunkexe -m68020 -nosym -DDEBUG=1 -o compactflash.device src/cfd.s

# Manual vbcc invocation (CFInfo)
vc +aos68k -O2 -c99 -INDK/Include_H -o CFInfo src/cfinfo.c
```

## License

GNU Lesser General Public License v2.1

## Trademark

"CompactFlash" is (TM) by CompactFlash Association
