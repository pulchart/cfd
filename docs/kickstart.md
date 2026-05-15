# Building a Custom Kickstart ROM with cfd + ptable

A scripted ROM builder at `tools/kickstart/kickstart.py` produces 1 MB AmigaOS 3.2.3 / 3.1 / 2.05 / 2.04 Kickstart ROMs that embed `compactflash.device` and `ptable.library` directly (except 2.04). Such a ROM autoboots from RDB-partitioned CF card in PCMCIA.

For mount-only use without autoboot, a regular install of `compactflash.device` and `ptable.library` into `SYS:Devs/` and `SYS:Libs/` is sufficient (see the [Autoboot / Automount (ROM-resident)](../README.md#autoboot--automount-rom-resident) section in the main README). This document is only relevant if you want to flash a custom Kickstart ROM.

## Prerequisites

The builder runs on Linux and shells out to Cloanto's Capitoline CLI tool.

| # | Prerequisite | Install at | Needed for |
|---|---|---|---|
| 1 | Python 3 + `jinja2` + `pyyaml` | system packages | all builds |
| 2 | Capitoline (`capcli.Linux`, `Components/`, `Capitoline Hashes/`) | `/opt/Capitoline/` | all builds |
| 3 | Hyperion AmigaOS 3.2.3 Update (`ROMs/`, `ADFs/`) | `/opt/AmigaOS/Update3.2.3/` | 3.2.3 builds |
| 4 | Workbench 3.2 ADF (`workbench3.2.adf`) | `/opt/AmigaOS/AmigaOS3.2/adf/` | 3.2.3 builds |
| 5 | AmigaOS 3.1 (`ROMs/`, `ADFs/`) | `/opt/AmigaOS/AmigaOS3.1/` | 3.1 builds |
| 6 | AmigaOS 2.05 ROM (v37.350, CRC `0x43b0df7b`) | `/opt/AmigaOS/AmigaOS2.05/ROMs/` | 2.05 build (A600) |
| 7 | AmigaOS 2.04 ROM (v37.175 A500+, CRC `0xc3bdb240`) | `/opt/AmigaOS/AmigaOS2.04/ROMs/` | 2.04 build (A500+) |
| 8 | pfs3aio | `/opt/AmigaOS/pfs/v20,0/` | all builds |
| 9 | fat95 (68000 + 68020) | `/opt/AmigaOS/fat95/3.22/{68000,68020}/` | all builds |
| 10 | Built driver + library | `dist/` (run `make full` first) | all builds |

If any required prerequisite for a target you're building is missing, the script reports an error and stops. Targets you don't build don't need their source trees.

For the technical details behind the 3.2.3 template's scantable patch (and how it differs from the Capitoline-docs `add chunk + redirect` pattern used in many community scripts), see [kickstart-scantable.md](kickstart-scantable.md).

## Build

From the repo root:

```sh
tools/kickstart/kickstart.py             # default: every variant (3.2.3 + 3.1 + 2.05 + 2.04)
tools/kickstart/kickstart.py 3.2.3       # both 3.2.3 ROMs
tools/kickstart/kickstart.py 3.1         # both 3.1 ROMs
tools/kickstart/kickstart.py 2.0x        # both 2.0x ROMs (A600-2.05 + A500plus-2.04)
tools/kickstart/kickstart.py 2.05        # A600-2.05 ROM only
tools/kickstart/kickstart.py 2.04        # A500plus-2.04 ROM only
tools/kickstart/kickstart.py a1200-3.1   # one specific model
```

Output lands in `tools/kickstart/out/<MODEL>/` where `<MODEL>` is one of
`A600-3.2.3`, `A1200-3.2.3`, `A600-3.1`, `A1200-3.1`, `A600-2.05`, `A500plus-2.04`:

| File | Description |
|---|---|
| `cfd.rom` | 1 MB merged image (F8 ROM concatenated with E0 ROM) |
| `cfd.F8` | F8 half (512 KB at `0xF80000`): base AmigaOS modules |
| `cfd.E0` | E0 half (512 KB at `0xE00000`): extra modules (rexxsyslib, pfs3aio, fat95, compactflash.device, ...) |
| `cfd.hi.bin`, `cfd.lo.bin` | (A1200 only) byteswapped halves for the A1200's two physical Kickstart chips |
| `capitoline.log` | full Capitoline build log |
| `capitoline.script` | rendered script that was fed to `capcli.Linux` |
 
## Customising the build

The set of extra modules and the per-machine config live in `tools/kickstart/kickstart.yaml`. Run `tools/kickstart/kickstart.py --help` for the full schema. Each entry in the `modules:` list uses one of these verbs:

| Verb (full signature) | Effect | Notes |
|---|---|---|
| `file: <path>` + `rom: "E0"\|"F8"` | add a file from disk | `path` absolute or repo-relative; copied into workdir and added by basename. |
| `adf: <path>` + `adf_path: <inner>` + `rom: "E0"\|"F8"` | add a lib from a specific ADF | Capitoline `loadadf "<adf>"; add ADF:/<inner>`. **`adf_path:` is case-sensitive** (capcli does exact-case lookup against ADF entries); typos fail the build via the `error:` log guard rather than silently dropping the component. |
| `adf_modules: <inner>` + `rom: "E0"\|"F8"` | add a lib from the model's modules ADF | Shorthand for `adf:` + `adf_path:` using `$ADF`; 3.2.3 only (3.1 has no modules ADF). Same case-sensitivity caveat as `adf:`. |
| `replace: <stock>` + (`with: <path>` or `adf:` + `adf_path:`) + `rom: "F8"\|"E0"` | swap a stock F8 module for a replacement binary | `rom: "F8"` substitutes at the stock slot; `rom: "E0"` suppresses the F8 line and lands the substitute in E0 (useful when it exceeds the F8 budget). |
| `skip: <stock>` | drop a stock F8 module from the build | The module isn't added anywhere.  No `rom:` (rejected). |
| `relocate: <stock>` + `rom: "E0"` | move a stock F8 module to E0 | Keeps the original content; only the ROM bank changes.  `rom: "E0"` is the only valid value. |

All verbs accept the optional filters:

- `cpu: "68000" | "68020"`: include only for the matching CPU build.
- `os:  "3.1"   | "3.2.3"`: include only for the matching OS build.

Order in the `modules:` list = order of `add` directives in the rendered Capitoline script.

## Flashing

- **A1200**: has two physical Kickstart chips. Flash `cfd.hi.bin` to the upper chip and `cfd.lo.bin` to the lower chip; the dual-EPROM word layout is already byteswapped for you.
- **A600**: has a single 16-bit Kickstart ROM. Flash the merged 1 MB image `cfd.rom` to the replacement chip.

Use whatever EPROM / flash programmer you normally use; the builder produces standard binary images with no further wrapping.

## After flashing

Once the new Kickstart is in place, the cold-boot path becomes:

1. Kickstart starts, exec/dos/scsi/etc. initialise.
2. `compactflash.boot` (the cold-start stub embedded in `compactflash.device`) runs after `scsi.device`.
3. It opens `ptable.library` (now ROM-resident) and calls `BootScanRDB`.
4. `ptable.library` walks the RDB, registers any filesystem handlers it finds, and publishes each partition via `AddBootNode` (bootable) or `AddDosNode` (mountable only).

See the [Autoboot / Automount (ROM-resident)](../README.md#autoboot--automount-rom-resident) section in the main README for the partition-flag table, boot-order details, and serial-debug output samples.
