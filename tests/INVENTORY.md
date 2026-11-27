# cfd test inventory

Generated from the docstrings and `integration/scenarios.yaml` by `tests/list_tests.py`. Refresh with `make test-list-update`.

<!-- TESTS:BEGIN -->

| script | status | what it checks |
|---|---|---|
| `ata_contracts.py` | gated | ATA I/O dispatch, config bounds, geometry and media notifications. |
| `config_loader.py` | gated | The cfd.prefs loader: which source wins, empty sources and truncated input. |
| `mountcfg.py` | gated | cfd.prefs keys to the MountCfg, override rows and UNMOUNT list. |
| `rom_hunks.py` | gated | Device, automount and bundled ptable modules assemble to one CODE hunk. |

### FS-UAE integration scenarios

Run by `make test-integration` from `integration/scenarios.yaml`; [integration/README.md](integration/README.md) describes the suite. `planned` scenarios are not implemented yet.

| scenario | status | what it checks |
|---|---|---|
| `automount` | integration | default cfd.prefs: CF0 mounts on insert, reads and writes |
| `automount_off` | integration | AUTOMOUNT 0: the card is identified, nothing mounts |
| `static` | integration | AUTOMOUNT 0 and a hand mount of CF0 from a mountlist |
| `static_in_use` | integration | automounted CF0 plus a hand mount of the same partition: refused |
| `static_mount_used` | integration | MOUNT_USED 1: the hand mount of an automounted partition is let through |
| `handler_params` | integration | STACK_FAT, PRI_FAT and DOSTYPE_FAT reach the mounted node |
| `swap` | integration | the card leaves and comes back: removal seen, remounted, data intact |
| `swap_open` | integration | a file held open across the swap reads back through the same handle |
| `late_insert` | integration | the driver starts with an empty slot and the RDB card arrives later: published, formatted, written and read |
| `swap_keep` | integration | UNMOUNT NONE: CF0 kept and marked absent while the card is out, its handler serves again on insert, a file held open reads back |
| `swap_in_use` | integration | default UNMOUNT with a file open: CF0 kept on removal; the next removal without it unmounts CF0 |
| `swap_static_default` | integration | default UNMOUNT_STATIC: a hand mount serves the card, is torn down on removal and the card comes back as CF0 |
| `swap_static_keep` | integration | UNMOUNT_STATIC 0: a hand mount survives the removal, marked absent, and serves again on insert |
| `rdb` | integration | RDB with FFS and PFS3: PFS3 from the RDB, both formatted, written and read |
| `rdb_swap` | integration | the RDB card leaves and comes back: FFS and PFS3 remount, written files read back |
| `swap_partial` | integration | UNMOUNT FFS on an RDB card: the FFS partition unmounted, PFS3 kept and marked absent, both read back after the swap |
| `mbr_mix` | integration | MBR, a primary and logical partitions: FAT12, FAT16, FAT32, NTFS, exFAT |
| `gpt_mix` | integration | GPT basic data partitions: FAT12, FAT16, FAT32, NTFS, exFAT |

<!-- TESTS:END -->
