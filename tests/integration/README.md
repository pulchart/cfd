# Integration tests

compactflash.device, ptable.library and fat95 under AmigaOS 3.1 and 3.2.3 in FS-UAE, on an emulated PCMCIA IDE card.

## Running

```
make test-integration                                # every scenario on every OS profile
make test-integration IT="--os 3.1 --scenario swap"
tests/integration/run.py --list                      # scenarios with a one-line description
tests/integration/run.py --config FILE               # another configuration (default: config.yaml here, or $CFD_IT_CONFIG)
tests/integration/run.py --work DIR                  # a new directory for this run
```

`make test-integration` builds the guest tools (`tools/devinfo.c`, `tools/holdfile.c`) first; run.py alone needs `make devinfo holdfile`. The run first prints its plan: whether the fat95 build mounts exFAT, and per OS profile the scenarios it runs or why the profile is skipped. Exit code 0 when every scenario that ran passes. Each run gets a new directory under `work`; nothing is written into the source tree outside it.

## Configuration

`config.yaml` holds the inputs that are not part of the repository. A relative path starts at the repository root, so `../fat95` is a checkout beside this one.

`os` names the OS profiles; every scenario runs on each. A profile whose files are missing is skipped.

| Key | Content |
|---|---|
| `kickstart` | A1200 Kickstart; a `.F8` half takes the `.E0` half beside it |
| `commands_adf` | AmigaOS disks the boot disk takes its C: commands from, searched in order |
| `workbench_adf` | AmigaOS disk with `System/Format` |
| `cpu` | FS-UAE CPU, default `68020` |
| `fsuae` | extra FS-UAE lines, default none |

Builds and paths:

| Key | Content |
|---|---|
| `cfd` | checkout with a built `dist/`, default this repository |
| `ptable`, `lsptres` | ptable.library and lsptres builds |
| `fat95`, `lsfsres` | fat95 and lsfsres builds; a fat95 with exFAT is recognised by its binary |
| `pfs3` | pfs3aio handler for the RDB card |

Optional parameters:

| Key | Default | Meaning |
|---|---|---|
| `work` | `build/integration` | directory for the runs |
| `fsuae` | `fs-uae` | FS-UAE binary |
| `vasm` | `vasmm68k_mot` | assembler for the guest tools |
| `wait` | `10` | seconds the guest waits for the automount |
| `limit` | `180` | seconds before a scenario counts as hung |

## Scenarios

`scenarios.yaml` lists them: cfd.prefs keys, the card layout, the AmigaDOS steps as named fragments and the check set. The check sets are in `scenarios.py`.

| Scenario | Checks |
|---|---|
| `automount` | default `cfd.prefs`: CF0 mounts, `lsptres` shows it mounted with `CONTROL_FAT`, payload reads back, a written file lands on the image |
| `automount_off` | `AUTOMOUNT 0`: the card is identified, nothing mounts |
| `static` | `AUTOMOUNT 0` and a hand mount of CF0 from a mountlist |
| `static_in_use` | a hand mount of an automounted partition is refused, object in use |
| `static_mount_used` | `MOUNT_USED 1` lets that hand mount through |
| `handler_params` | `STACK_FAT`, `PRI_FAT` and `DOSTYPE_FAT` reach the mounted node |
| `swap` | the card leaves and comes back: removal and insertion seen, CF0 mounted again, data intact |
| `swap_open` | `swap` with the payload held open by `holdfile`: the same handle reads it whole after the swap |
| `rdb` | RDB with FFS and PFS3: PFS3 loaded from the RDB, both formatted, written and read |
| `mbr_mix` | MBR with a primary and logical partitions: FAT12, FAT16 and FAT32 mount and read and write; NTFS is published and refused; exFAT mounts with a fat95 that has it, is refused otherwise |
| `gpt_mix` | the same file systems in GPT basic data partitions |

## Host tools

FS-UAE, xvfb-run, amitools (`xdftool`, `rdbtool`), sfdisk, mkfs.fat, mtools, mkntfs, mkfs.exfat, gzip, vasm, vbcc with `NDK/` as for `make`, Python 3 with PyYAML.

## Phases

1. Plan: the OS profiles that run, the profiles that are skipped.
2. Preparation: a boot disk with the C: commands from `commands_adf` (compressed update files are unpacked), Format, lsptres, lsfsres, compactflash.device, ptable.library and fat95, and the guest tools: `cardout`, `cardin`, `noreq` assembled with vasm, `devinfo` and `holdfile` from make (`tools/*.c`).
3. Per scenario: a card image, `cfd.prefs`, the scenario steps and the files they need, in the host directory the guest sees as `OUT:`.
4. Boot: the Startup-Sequence runs the steps; the guest writes its findings to `OUT:`.
5. Checks: on `OUT:`, the serial log (`FLAGS 8`) and the card image.

FS-UAE is started a second time when it exits or the guest has not begun its steps within 60 seconds.

## Emulation

- FS-UAE options: controller `scide`, `uae_pcmcia = true`.
- Floppies run at 8x (`floppy_drive_speed = 800`).
- Fast RAM at most 4 MB: 8 MB Zorro II overlaps the PCMCIA window and card.resource does not start.
- `HANDLER_FAT` in `cfd.prefs`; without it FAT partitions are published but not mounted.
- A swap is the Gayle disable bit set and cleared from the guest (`cardout`, `cardin`).
- `noreq` turns requesters off for the shell, so a missing volume fails a step instead of blocking the run.

## Not covered

- A card that stays out of the slot. card.resource answers the disable bit with a removal, re-enables the slot and reports an insertion, so the mount worker always finds the card in the slot and keeps the mounts; `UNMOUNT` and `UNMOUNT_STATIC` are not tested. Setting the bit again does not help: every write repeats that cycle. The scenarios that need it are listed under `planned` in `scenarios.yaml` and in [../INVENTORY.md](../INVENTORY.md).
- CIS routing: UAE generates its own card CIS.
- SFS.
