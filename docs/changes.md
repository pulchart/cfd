## 20260614

<!-- COMPONENTS:BEGIN -->
_Components in this release_:

- `compactflash.device 1.44 (04.06.2026)`
- `ptable.library 1.1 (07.06.2026)`
- `CFInfo 1.37 (11.01.2026)`
- `pcmciaspeed 1.36 (02.01.2026)`
- `pcmciacheck 1.39 (22.05.2026)`
<!-- COMPONENTS:END -->

##### Packaging

Documentation-only update (no binaries changed): Release notes and original CFD history now live in this dedicated document.

## 20260609

_Components in this release_:

- `compactflash.device 1.44 (04.06.2026)` _(new)_
- `ptable.library 1.1 (07.06.2026)` _(new)_
- `CFInfo 1.37 (11.01.2026)`
- `pcmciaspeed 1.36 (02.01.2026)`
- `pcmciacheck 1.39 (22.05.2026)` _(new)_

##### CompactFlash Driver

* **Fixed a crash in the ROM-resident driver when running WHDLoad.** (Issue #56) Programs that take over the machine flush idle libraries and devices to free memory before they run. The idle ROM-resident compactflash.device looked unused, got flushed, and that corrupted the program's memory setup, causing a guru (`0x0100000F`, bad `FreeMem`). Mounting a CF card first avoided it (the filesystem then held the device open), and so did WHDLoad's `NoFlushMem` option. The driver now keeps itself in use.

* **Non-IDE PCMCIA cards (e.g. ATAPI CD/DVD adapters) are now released earlier in the identify process.** (Issue #47) Rejecting after IDENTIFY is too late: the IDENTIFY attempt could leave the card in a state where dedicated drivers (such as `telmexatapi.device`) could no longer claim it. The CIS gate reintroduced checks for a well-formed Disk Interface FUNCEXT declaring IDE before IDENTIFY runs, with up to 10 retries to tolerate unstable CIS reads. Please report if you see any CF card detection regression.

* **ATAPI handler compiled out by default.** Build with `ATAPI=1` to keep it. See [ATAPI status](../README.md#atapi-status) for details.

##### Partition Table library

* **Duplicate RDB drive names are made unique at cold boot.** (Issue #57) When two cards carry RDBs that reuse the same partition name (for example both define `DH0`), the duplicates appeared together in the early-startup boot menu. A clashing name now gets a numeric suffix (`DH0.1`, `DH0.2`, ...).

* Loads filesystem handlers stored in a compacted format (`RELOC32SHORT` relocations).

* A partition with a damaged RDB entry is skipped instead of mounted. If a card's RDB describes a partition with incomplete settings (a `DosEnvec` shorter than the `DOSTYPE` field).

* Filesystem handlers loaded from a card's RDB now appear in `FileSystem.resource` under their own name instead of `ptable.library`.

##### Tools

* **`pcmciacheck -cis`**: new option that prints a readable summary of the identification data carried by the inserted PCMCIA card (manufacturer, card type, version, etc.). Handy when you want to understand why an unusual card is or isn't accepted by the driver, or when reporting a problem card.

##### Packaging

* **Archive version is now a date (YYYYMMDD).** The release bundle ships several independently-versioned pieces (`compactflash.device`, `ptable.library`, `CFInfo`, `pcmciaspeed`, `pcmciacheck`), each on its own cadence, so a single `v1.x` number for the whole archive never matched what was actually inside.

## v1.43 (19.05.2026)

#### Driver

* **Fix hot-plug regression introduced in v1.41**: inserting or removing a CF card no longer fails to notify filesystem handlers that live in a Kickstart ROM (e.g. fat95 in a custom ROM). Affected setups saw the card mount correctly but silently skip hot-plug events after that. With `Flags = 8` the bug was visible in the serial log as a spurious `..drop stale client` line on card removal:
  ```
  [CFD] Card removed
  [CFD] ..client IS_Code=0x00E4D3AA
  [CFD] ..drop stale client at 0x403DFC00
  ```

## v1.42 (16.05.2026)

This release introduces **autoboot and automount from RDB-partitioned CF cards**.

#### Driver

* **Autoboot from RDB at cold-boot**: a bootable RDB partition on the inserted card boots straight into Workbench. All RDB partitions appear   at cold start without `DEVS:DOSDrivers/` entries. Filesystem handlers stored on the card are loaded automatically. Requires `ptable.library` to be ROM-resident; disk-only install is mountable-only without it. When a card is present and stable all loops exit on the first iteration. The worst-case extra delay (~1.8 s) is paid once on the first `OpenDevice` with no card inserted.

* **Stricter CIS gate**: as the CIS detection code improved over time, the fallback that accepted cards without a readable `CISTPL_FUNCID` was dropped. Such cards now fail the CIS gate, freeing them for their proper driver.

#### Others

* Release archive version and compactflash.device version are now tracked independently (Makefile change)
* New distribution layout: two build flavors per CPU tier in dedicated folders. `dist/full/<cpu>/` as debug-capable (serial output enabled) and `dist/small/<cpu>/` without any debug output via serial line, The `<cpu>` is `68000` for any 68k or `68020` for 68020+.

## v1.41 (18.04.2026)

This release focuses on stability and CPU compatibility improvements across both shipped CPU tiers (`68000` / `68010` and `68020+`).

#### Driver

* **IO path streamlined**: internal cleanup in the IO path (see [IO path dispatch](../README.md#io-path-dispatch))
* **The driver now ships two CPU tiers**:
  - `68020+` at `devs/68020/compactflash.device` (A1200 stock, and 68020+ accelerators: 030/040/060/080)
  - `68000` at `devs/68000/compactflash.device` (stock A600)
* **68020+ build uses native 32-bit math**: `mulu.l` / `divul.l` / `bfffo` are inlined at the call sites via macros and fully replace the 68000 compatibility routines (which are excluded from the 020+ binary). No functional change.

#### Others

* Experimental `COPYBURST` build option removed (had no effect in practice).

## v1.40 (12.04.2026)

#### Driver

* **CIS gate accepts only known CompactFlash device types** ([#38](https://github.com/pulchart/cfd/issues/38))
  - Accepts cards whose CIS reports device type `0x0D` (FUNCSPEC) or `0x05` (FLASH), the two types CompactFlash cards are known to use.
  - Other memory-card types are rejected early, so the driver no longer tries ATA IDENTIFY on cards that are not expected to behave like ATA devices and will not get stuck on them. (see [CIS gate decision](../README.md#cis-gate-decision))

#### Others

* Rebuild by vasm 2.0e

## v1.39 (10.02.2026)

#### Driver

* **Checking stability of I/O port access** ([#33](https://github.com/pulchart/cfd/issues/33)) -- Cards with unreliable data transfer are now detected and rejected to prevent data corruption. Thanks to [Freddy](https://www.amigaportal.cz/member/2607-freddy) for sending the CF card for analysis.

#### Others

* git repository restructured
* Rebuild by vasm 2.0d

## v1.38 (27.01.2026)

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

* documentation improvements

## v1.37 (17.01.2026)

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

## v1.36 (08.01.2026)

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
  - Experimental: disabled by default, compile with `GTIMING=1` to enable
  - Maps card's ATA PIO mode to Gayle PCMCIA memory timing
* **Improved code documentation**
  - Architecture overview with register conventions
  - Documented CFU structure fields
  - Added function headers with input/output/register usage

## v1.35 (31.12.2025)

* **Serial debug output** - set `Flags = 8` to enable debug messages via serial port
  - Shows card insert/remove, identification, size, and MultiSize
  - Replaces cfddebug tool with readable text-based serial output
* **Enforce multi mode** - set `Flags = 16` to force 256 sector reads/writes per IO request, even if card firmware does not support it
  - Can improve performance on capable cards (1MB/s -> 2MB/s)
  - **Warning:** May cause data corruption on unsupported cards - see [Enforce Multi Mode](../README.md#enforce-multi-mode-flag-16)
* **Simplified SD-to-CF adapter support** - cleaner retry mechanism for IDENTIFY command introduced in v1.33

## v1.34 (22.10.2025)

* Improved compatibility with >=2014 Firmware CF cards
  - Workaround for "get IDE ID" on large capacity cards
  - Multi-sector IO uses firmware reported value to improve compatibility

## Original CFD History Through v1.33

| Version | Date | Changes |
|---------|------|---------|
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
