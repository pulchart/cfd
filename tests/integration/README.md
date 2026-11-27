# Integration tests

compactflash.device, ptable.library and fat95 on an emulated PCMCIA IDE card in FS-UAE, under the OS of an [amiga-fsuae](https://github.com/pulchart/container-amiga-fsuae) image: AROS, ApolloOS, and AmigaOS 3.1 and 3.2.3 from local images.

## Running

```
make                                                 # the driver set, once
make test-integration                                # every scenario on AROS and ApolloOS
make test-integration IT_OS=3.2.3 IT="--scenario swap"
tests/integration/run.py --list                      # scenarios with a one-line description
```

`make test-integration` builds the guest tools in the toolchain image, then runs `run.py --os NAME` in the image of each OS in `IT_OS` (default `aros apolloos`; `3.2.3` and `3.1` need the local AmigaOS images), one after another, in `build/integration/<date>/<os>`. `IT` passes options to run.py, such as `--scenario`, `--config FILE` or `--work DIR`. Exit code 0 when every scenario passes.

## Configuration

`config.yaml` holds the settings. A relative path starts at the repository root, so `../fat95` is a checkout beside this one. The image brings the OS: `AMIGA_SYSTEM`, `AMIGA_KICKSTART` and `AMIGA_KICKSTART_EXT`.

`os` names the OS profiles:

| Key | Content |
|---|---|
| `setpatch` | `false` when the OS has no SetPatch |
| `cpu` | FS-UAE CPU, default `68020` |
| `prefs` | `cfd.prefs` keys on top of the base set, under a scenario's own |
| `copy` | command that moves files between `OUT:` and the card, default `Copy` |
| `fsuae` | extra FS-UAE lines, default none |

Builds, by default from this repository's `dist/` and from releases fetched into `build/deps` with their SHA-256 checked:

| Key | Default |
|---|---|
| `cfd`, `cfinfo`, `ptable`, `lsptres` | `dist/` of this repository (`make`) |
| `fat95`, `lsfsres`, `dd` | the fat95 v20261115 release; a fat95 with exFAT is recognised by its binary |
| `pfs3` | the pfs3aio 20261119-1 release (020, gcc13), the handler for the RDB card |

Optional parameters:

| Key | Default | Meaning |
|---|---|---|
| `work` | `build/integration` | directory for the runs |
| `fsuae` | `fs-uae` | FS-UAE binary |
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

## Phases

1. Preparation: a copy of the image's system directory as the boot volume, with Format in `C:`, lsptres, lsfsres, dd, compactflash.device, ptable.library, fat95 and `noreq`. The guest tools come from make: `devinfo` and `holdfile` (`tools/*.c`), `cardout`, `cardin` and `noreq` (`tools/*.asm`).
3. Per scenario: a card image, `cfd.prefs` in the boot volume's `Prefs/Env-Archive`, which the driver reads when `ENV:` has none, and the scenario steps with the files they need in the host directory the guest sees as `OUT:`.
4. Boot: the Startup-Sequence runs the steps; the guest writes its findings to `OUT:`.
5. Checks: on `OUT:`, the serial log (`FLAGS 8`) and the card image.

FS-UAE is started a second time when it exits or the guest has not begun its steps within 60 seconds.

## Emulation

- FS-UAE options: controller `scide`, `uae_pcmcia = true`.
- Fast RAM at most 4 MB: 8 MB Zorro II overlaps the PCMCIA window and card.resource does not start.
- `HANDLER_FAT` in `cfd.prefs`; without it FAT partitions are published but not mounted.
- A swap is the Gayle disable bit set and cleared from the guest (`cardout`, `cardin`).
- `noreq` turns requesters off for the shell, so a missing volume fails a step instead of blocking the run.
- AROS `Copy` to and from the FS-UAE host directory (`OUT:`) fails; the AROS and ApolloOS profiles set `copy: dd`.

## Not covered

- A card that stays out of the slot. card.resource answers the disable bit with a removal, re-enables the slot and reports an insertion, so the mount worker always finds the card in the slot and keeps the mounts; `UNMOUNT` and `UNMOUNT_STATIC` are not tested. Setting the bit again does not help: every write repeats that cycle. The scenarios that need it are listed under `planned` in `scenarios.yaml` and in [../INVENTORY.md](../INVENTORY.md).
- CIS routing: UAE generates its own card CIS.
- SFS.
- NTFS volumes are a boot sector only: the check is that nothing mounts them.
