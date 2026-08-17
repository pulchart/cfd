# compactflash.device automount and configuration

Insert a CF card and its partitions mount by themselves; pull it and they go away again. With the driver in a Kickstart ROM you can also boot straight off the card. This guide covers both, and the `ENV:cfd.prefs` file that configures them.

The scanning and mounting itself is done by `ptable.library`, which is required for all of it. Without that library `compactflash.device` still works, but as a plain mount-only device: you mount partitions yourself through `DEVS:DOSDrivers/`. See `ptable.guide` for the library internals.

## Quick start

Three modules are involved, and automount is opt-in by whether you include the third:

- `compactflash.device`: the I/O driver.
- `ptable.library`: the partition scanner and automounter (RDB, MBR, GPT, flat FAT).
- `compactflash.automount`: boot and automount bringup. Include it only when you want autoboot or automount.

| Goal | Modules | Cold-boot autoboot |
|---|---|---|
| ROM autoboot | `compactflash.device` + `compactflash.automount` + `ptable.library` in Kickstart | available |
| Resident/on-disk, no automount | `compactflash.device` + `ptable.library` (no automount module) | no |
| On-disk automount | `LoadModule` line below | no |

For a disk install, put `compactflash.automount` and `ptable.library` in `LIBS:` and add this to your `user-startup`:

```
LoadModule LIBS:compactflash.automount LIBS:ptable.library DEVS:compactflash.device L:fat95
```

Automount is **on by default**, so nothing else is needed to try it. A config file is only for changing that; an example is shipped as `ENVARC/cfd.prefs`, copy it to `ENVARC:cfd.prefs` and `ENV:cfd.prefs`:

```
AUTOMOUNT 1
FLAGS 0
UNMOUNT FAT
CONTROL_FAT +q
```

That keeps automount on, fully unmounts only FAT volumes when the card is pulled, and passes fat95's `+q` (quiet) option to FAT mounts.

## What happens when you insert or remove a card

On insert:

- The card is scanned and every partition is published to `partition.resource`, always, even with automount off. `lsptres` lists them either way.
- With automount on, partitions that are not mounted yet are mounted.
- If you mounted a device-dostype DOSDriver by hand (for example `CFAUX`), automount pauses on each pass so that handler can claim its own partition first, then reuses it (shown as `CFa0>CFAUX`) and mounts only the others, instead of starting a second handler on the same partition.

On removal, the `UNMOUNT` key decides per filesystem:

- **Default, no `UNMOUNT` key:** every partition is fully unmounted. The handler is stopped, the DOS node removed and the memory freed. Reinserting the card mounts it fresh.
- **`UNMOUNT <fs>`:** only the listed filesystems are unmounted like that. A filesystem not listed is marked absent instead: its DOS node and handler stay in memory, and reinserting the same card reattaches it without re-initialising the handler. This is the native AmigaOS removable-media behaviour.
- **`UNMOUNT NONE`** (or any name that is not recognised) keeps every handler.

Either way the partition stays visible in `lsptres` while the card is out, shown absent, and is re-confirmed or re-published on reinsert.

Two settings only take effect on the next mount:

- `AUTOMOUNT` gates the mount step, it never unmounts. Changing `1` to `0` leaves volumes that are already mounted alone. To clear them, pull the card or reboot.
- `FLAGS` and `CONTROL` are read by a handler when it starts. Under `UNMOUNT NONE`, or for a filesystem left out of the `UNMOUNT` list, the handler survives a card swap and keeps the values it started with. List that filesystem in `UNMOUNT` and reinsert the card to apply new ones.

## Configuration: ENV:cfd.prefs

The config is read fresh on every card insert **and** every card removal, so a change applies to the next card you insert or pull, with no reboot and no rebuild. Because removal re-reads it too, a changed `UNMOUNT` applies to the very next card you pull.

It is read from the first of three places that has it:

1. `ENV:cfd.prefs` - the live copy. Once the machine is up this is always the one used, so edit it for a change to apply now.
2. `ENVARC:cfd.prefs` - the saved copy. Write it too if you want the setting to survive a reboot.
3. `SYS:Prefs/Env-Archive/cfd.prefs` - the same file by its real path.

The last two matter at boot: Startup-Sequence assigns `ENV:` and `ENVARC:` only after the automount agent has started, while `SYS:` already exists. That is how a card present at boot is mounted with your settings rather than the built-in defaults.

Format:

- One key per line, the value after whitespace. A missing key keeps its default.
- Keys are matched case-sensitively as whole words, so `FLAGS` does not match inside `FLAGS_DOS`.
- `;` or `#` starts a comment: the rest of that line is ignored, so `; FLAGS 0` really is disabled.
- The file is read up to 511 bytes.

| Key | Value | Default | Meaning |
|---|---|---|---|
| `AUTOMOUNT` | `0`/`1`, `ON`/`OFF`, `YES`/`NO` | on | Mount partitions on insert. Any other value is ignored and the default applies. |
| `FLAGS` | decimal | `0` | Mount flags applied to every mount. See the bit table below. |
| `CONTROL` | string | none | Mount CONTROL string applied to every mount. |
| `UNMOUNT` | names | all | Filesystems to fully unmount on removal. Any subset of `DOS FFS SFS PFS FAT`; a key with no recognized names (e.g. `UNMOUNT NONE`) keeps every handler. |
| `FLAGS_<fs>` | decimal | global `FLAGS` | Per-filesystem override of `FLAGS`. |
| `CONTROL_<fs>` | string | global `CONTROL` | Per-filesystem override of `CONTROL`. |

`FLAGS` bits (see also the README "Mount Flags" section):

| Bit value | Effect |
|---|---|
| 8 | serial debug output (full build) |
| 16 | enforce ATA multi-sector mode |

The filesystem names are exactly these five: `DOS`, `FFS`, `SFS`, `PFS`, `FAT`. Any other name (`NTFS`, `EXT2`, `PDS`, ...) is not recognised and is silently ignored. `PDS` in particular is not valid: PFS3's `PDS\x` DosType is already covered by `PFS`.

A per-filesystem key applies to partitions whose DosType high three bytes match: `DOS` = `DOS\x`, `FFS` = `DOS\x` fast-filesystem, `PFS` = `PFS\x` (and the `PDS\x` alias), `SFS` = `SFS\x`, `FAT` = `FAT\x`. Use the overrides when you want a setting on one filesystem only, for example serial debug on FAT mounts alone.

A CONTROL string is only meaningful for filesystems that parse one. For hot-plugged FAT cards, `CONTROL_FAT "+q"` enables fat95's quiet option, so no error requesters ("please reinsert", read or write windows) pop up when a card is pulled with pending writes; errors go back to the calling program instead. The fat95 documentation has the full option list.

## When a partition does not mount

Automount mounts a partition only when a handler for its filesystem is already in the system. It never loads a handler from `L:` by itself, so a handler file sitting unused in `L:` does not count. A partition with no handler is still scanned and listed by `lsptres`, but stays `P---` (present, not mounted); it is never falsely shown as mounted. This is the same for every filesystem: FFS, SFS, PFS, FAT and any other.

A handler becomes available in one of these ways:

- Stored in the card's RDB, typical for native FFS, SFS and PFS partitions: `ptable.library` loads it straight from the RDB, at cold boot and on a DOS-time insert alike, so an RDB card needs nothing extra.
- Built into the Kickstart ROM (for example pfs3aio, or fat95 in a custom ROM): registered by the handler's own startup at boot.
- Made resident from disk with `LoadModule` (for example adding `L:fat95` to your `LoadModule` line): becoming resident runs the handler's startup, which registers it.
- Loaded on demand when you mount a matching DOSDriver by hand: mounting one fat95 DOSDriver loads fat95 from `L:` and registers its shared FAT code, after which automount binds every other FAT partition to it.

FAT cards are the case that needs attention: MBR, GPT and whole-disk (flat) FAT cards carry no handler in their partition table, so fat95 must come from the ROM, from `LoadModule`, or from a mounted fat95 DOSDriver.

## Booting from a CF card (ROM-resident)

At Kickstart cold start, before DOS exists, the driver opens `ptable.library`, which walks the card's RDB, loads any filesystem handlers stored in it, and registers each partition:

| RDB partition flag | BootPri | Result |
|---|---|---|
| normal | >= 0 | bootable: appears in the Early Startup boot device list |
| normal | < 0 | non-bootable: mounted as a DOS volume |
| NOMOUNT (bit 1 set) | any | skipped: not mounted, not in the DOS list |

BootPri is stored in the RDB partition environment and controls boot order.

Only RDB partitions are registered at cold boot, because that runs before DOS and `cfd.prefs` cannot be read yet. MBR, GPT and flat partitions on a card present at cold boot are published to `partition.resource` and listed as `P---`; the automount agent mounts them once DOS is up, so `AUTOMOUNT`, `FLAGS` and `CONTROL_*` apply to them too. Autoboot itself does not depend on `AUTOMOUNT`, and RDB partitions registered at cold boot are never unmounted by the automount agent.

Cold-boot autoboot runs late in Kickstart's resident init, after the internal IDE (`scsi.device`) has started. That init is sequential, so if the IDE stalls at boot (no drive connected, for instance) CF autoboot never gets its turn either. The boot stub first does a single Gayle read to check for a card; an empty slot returns immediately. With a card present it tolerates slow cards by polling up to about 1.8 s; a healthy card adds no measurable delay.

`ptable.library` also registers a synthetic expansion board (Vendor ID `65535 ($FFFF)`, Product ID `1`) so the Early Startup boot menu sees the device. It shows up in tools like `ShowConfig`.

`LoadModule` cannot give you this. It makes on-disk modules resident and reboots, but only activates the *first* romtag of each file, which is why bringup lives in its own module: `compactflash.automount`'s first romtag is the after-DOS one, so `LoadModule` runs it, and from then on hotplug works as in a disk install. Cold-boot autoboot runs before DOS and needs all three modules in a real Kickstart ROM. A scripted Capitoline-based builder for a 1 MB AmigaOS 3.2.3 / 3.1 / 2.05 Kickstart lives in the companion [amigaos-kickstart-builder](https://github.com/pulchart/amigaos-kickstart-builder) repo.

## Checking what happened

`lsptres` lists `partition.resource`, which reflects the last-seen card whether or not its partitions are mounted. The first character of the `Flags` column is the media state:

| Char | Meaning |
|---|---|
| `P` | present: the card in the slot has this partition |
| `I` | invalid: the slot is still mounted, but the card currently inserted has no such partition, typically after a card swap. Shows as `I--M` and returns to `P` when the original card comes back |
| `-` | absent: no card in the drive. A kept mount whose media is gone shows `---M` |

The remaining characters are `B` bootable, `N` nomount, `M` mounted. `MFlg` is the resolved mount flags and `Ctrl` the resolved CONTROL string. A mounted volume shows as `scanname>dosname` when its real DOS name differs from the scanned name.

For a serial trace of a DOS-time mount, set `FLAGS 8` (full build, 9600 baud). A `full` build also prints the cold-boot part unconditionally, whatever the flags say, with `[CFD] boot:` for the driver and `[PT]` for the library:

```
[CFD] boot: open ptable.library ...
[CFD] boot: BootScanPartitions(compactflash.device,0)
[PT] cold boot: scanning for partitions
[PT] RDB partition table
[PT] + filesystem handler PFS v20.0
[PT] - skip  SDH10
[PT] + boot  SDH0
[PT] + mount SDH1
[PT] + mount SDH2
[PT] cold boot done, partitions registered: 3
```

## Troubleshooting

- Nothing automounts: check that `ENV:cfd.prefs` does not say `AUTOMOUNT 0` (the default is on), and that `ptable.library` is reachable, ROM-resident or in `LIBS:`.
- File-based install, card present but nothing happens: the driver is not loaded until something opens it. Add a `DEVS:DOSDrivers/CF0` entry so it loads at boot.
- Partitions listed in `lsptres` but not mounted: automount is off, or their filesystem has no handler available.
