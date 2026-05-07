# Building a Custom Kickstart ROM with cfd + ptable

A scripted ROM builder at `tools/kickstart/build_rom.py` produces a 1 MB Hyperion AmigaOS 3.2.3 Kickstart ROM that embeds `compactflash.device` and `ptable.library` directly. Such a ROM autoboots from RDB-partitioned CF cards before any disk-loaded driver is available required for cold-boot autoboot.

For mount-only use without autoboot, a regular install of `compactflash.device` and `ptable.library` into `SYS:Devs/` and `SYS:Libs/` is sufficient (see the [Autoboot / Automount (ROM-resident)](../README.md#autoboot--automount-rom-resident) section in the main README). This document is only relevant if you want to flash a custom Kickstart ROM.

## Prerequisites

The builder runs on Linux and shells out to Cloanto's Capitoline CLI tool.

- **Capitoline** at `/opt/Capitoline/`:
  - `capcli.Linux` (executable)
  - `Components/` (binary chunks shipped with Capitoline)
  - `Capitoline Hashes/` (module hash database)
- **Hyperion AmigaOS 3.2.3 Update** at `/opt/AmigaOS/Update3.2.3/`:
  - `ROMs/` containing the source ROM (A1200.47.115.rom, CDTVA500A600A2000.47.115.rom)
  - `ADFs/` containing the modules ADF (`ModulesA1200_3.2.3.adf`, `ModulesA600_3.2.3.adf`)
- **Optional** — for `rexxsyslib.library` in the E0 ROM:
  - `/opt/AmigaOS/AmigaOS3.2/adf/workbench3.2.adf` (Hyperion 3.2 Workbench ADF)
  - `xdftool` in `PATH`
- **Built driver and library** — run `make full` from the repo root first to produce `dist/full/{68000,68020}/devs/compactflash.device` and `dist/full/{68000,68020}/libs/ptable.library`. The builder picks them up automatically.

If any prerequisite is missing the script reports an error and stops; if the optional rexxsyslib step fails the script continues with a warning.

## Build

From the repo root:

```sh
tools/kickstart/build_rom.py            # build both A600 and A1200 ROMs
tools/kickstart/build_rom.py a1200      # build only A1200 ROM
tools/kickstart/build_rom.py a600       # build only A600 ROM
```

Output lands in `tools/kickstart/out/<MODEL>/`:

| File | Description |
|---|---|
| `cfd.rom` | 1 MB merged image (F8 ROM concatenated with E0 ROM) |
| `cfd.F8` | F8 half (512 KB at `0xF80000` — base AmigaOS modules + cfd) |
| `cfd.E0` | E0 half (512 KB at `0xE00000` — workbench, icon, optionally rexxsyslib) |
| `cfd.hi.bin`, `cfd.lo.bin` | (A1200 only) byteswapped halves for the A1200's two physical Kickstart chips |
| `capitoline.log` | full Capitoline build log |
| `capitoline.script` | rendered script that was fed to `capcli.Linux` |

## Flashing

- **A1200**: has two physical Kickstart chips. Flash `cfd.hi.bin` to the upper chip and `cfd.lo.bin` to the lower chip; the dual-EPROM word layout is already byteswapped for you.
- **A600**: has a single 16-bit Kickstart ROM. Flash the merged 1 MB image `cfd.rom` to the replacement chip; a 1 MB Kickstart adapter takes one chip with the merged image.

Use whatever EPROM / flash programmer you normally use; the builder produces standard binary images with no further wrapping.

## After flashing

Once the new Kickstart is in place, the cold-boot path becomes:

1. Kickstart starts, exec/dos/scsi/etc. initialise.
2. `compactflash.boot` (the cold-start stub embedded in `compactflash.device`) runs after `scsi.device`.
3. It opens `ptable.library` (now ROM-resident) and calls `BootScanRDB`.
4. `ptable.library` walks the RDB, registers any filesystem handlers it finds, and publishes each partition via `AddBootNode` (bootable) or `AddDosNode` (mountable only).

See the [Autoboot / Automount (ROM-resident)](../README.md#autoboot--automount-rom-resident) section in the main README for the partition-flag table, boot-order details, and serial-debug output samples.
