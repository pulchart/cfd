# compactflash.device automount and configuration

Insert a CF card and its partitions mount by themselves; pull it and they go away again. With the driver in a Kickstart ROM you can also boot straight off the card. This guide covers both, and the `ENV:cfd.prefs` file that configures them.

The scanning and mounting itself is done by `ptable.library`, which is required for all of it. Without that library `compactflash.device` still works, but as a plain mount-only device: you mount partitions yourself through `DEVS:DOSDrivers/`. See `ptable.guide` (shipped with the ptable.library archive) for the library internals. The expected behaviour of the whole feature is catalogued scenario by scenario in `automount-review.guide` ([automount-review.md](automount-review.md)).

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
CONTROL_FAT -d-D+q
```

That keeps automount on, fully unmounts every supported filesystem when the card is pulled (the default, since there is no `UNMOUNT` key), and passes fat95 `-d-D+q`: no extra date stamps as file comments, and the quiet option so a pulled card does not raise requesters.

## What happens when you insert or remove a card

On insert:

- The card is scanned and every partition is published to `partition.resource`, always, even with automount off. `lsptres` lists them either way.
- With automount on, partitions that are not mounted yet are mounted.
- If you mounted a device-dostype DOSDriver by hand (for example `CFAUX`), automount pauses on each pass so that handler can claim its own partition first, then reuses it (shown as `CF0>CFAUX`) and mounts only the others, instead of starting a second handler on the same partition.

On removal, the `UNMOUNT` key decides per filesystem:

- **Default, no `UNMOUNT` key:** every partition of a supported filesystem (`DOS`/`FFS`/`SFS`/`PFS`/`FAT`) is fully unmounted; anything else is kept and marked absent. The handler is stopped, the DOS node removed and the memory freed. Reinserting the card mounts it fresh.
- **`UNMOUNT <fs>`:** only the listed filesystems are unmounted like that. A filesystem not listed is marked absent instead: its DOS node and handler stay in memory, and reinserting the same card reattaches it without re-initialising the handler. This is the native AmigaOS removable-media behaviour.
- **`UNMOUNT NONE`** (or any name that is not recognised) keeps every handler.

A partition can also be served by your own mountlist instead of an automount-built node: either your hand `DEVS:DOSDrivers` handler claimed the card itself (`CF0>CFAUX`), or the automount adopted your node because the names matched. `lsptres` marks these rows in the fifth Flags position: `s` when the mount follows the `UNMOUNT` policy (the default: pull the card and it is torn down with everything else, and the next card is automounted under the synthesized name), `S` when `UNMOUNT_STATIC 0` protects it.

With `UNMOUNT_STATIC 0` the mount is kept on removal and marked absent like `UNMOUNT NONE` (`[PT] static mount kept` on serial), and reinserting a card puts the same handler back in service. You mounted it, so only you remove it. To remove it by hand, `MOUNT CFAUX: SHUTDOWN && ASSIGN CFAUX: DISMOUNT` is the clean idiom: the handler unregisters its mount on the way out and the partition is the automount's (or a fresh `Mount`'s) again. A handler that disappears without an accepted shutdown leaves the partition claimed until a reboot, a fresh `Mount`, or the next card removal under a tearing `UNMOUNT` policy, which cleans the leftover.

The other way around, a hand mount over a partition the automount (or any other handler) already serves is refused: the new handler reports `object in use` and the existing mount stays alone on the partition. `MOUNT_USED 1` overrides that deliberately, at your own risk: reading through the second mount mostly works, any write corrupts the volume, and `partition.resource` keeps showing the original mount. The policy is stamped into the partition entries during the mount pass on insert, which is what `lsptres` shows and what the removal obeys, so a changed `UNMOUNT_STATIC` applies to cards inserted afterwards, not to the very next pull.

Under `UNMOUNT NONE`, or for a filesystem left out of the list, the partition stays visible in `lsptres` while the card is out, shown absent. A fully unmounted partition is removed from the resource and re-published on the next insert.

A card that is still in use is not unmounted. A filesystem cannot give up a volume something holds a lock on, an open Workbench window on it being the usual case, because the volume node has to stay in the DOS list for that lock to remain valid. It declines, and the partition is kept and marked absent exactly as `UNMOUNT NONE` would leave it, so its handler stays in service. Close the window, or whatever else is holding the volume, and the next removal unmounts it. A full ptable.library build prints the refusal on serial unconditionally; `FLAGS 8` adds the driver's `[MW]`/`[MA]` lines around it.

These settings only take effect on the next mount:

- `AUTOMOUNT` gates the mount step, it never unmounts. Changing `1` to `0` leaves volumes that are already mounted alone. To clear them, pull the card or reboot.
- `FLAGS` and `CONTROL` are read by a handler when it starts. Under `UNMOUNT NONE`, or for a filesystem left out of the `UNMOUNT` list, the handler survives a card swap and keeps the values it started with. List that filesystem in `UNMOUNT` and reinsert the card to apply new ones.
- `UNMOUNT_STATIC` and `MOUNT_USED` are stamped into the partition entries during the mount pass on insert; a change applies to cards inserted afterwards. `lsptres` always shows the stamped `UNMOUNT_STATIC` state (`S`/`s`), which is exactly what the next removal will do.

## Configuration: ENV:cfd.prefs

The config is read fresh on every card insert **and** every card removal, so a change applies to the next card you insert or pull, with no reboot and no rebuild. Because removal re-reads it too, a changed `UNMOUNT` applies to the very next card you pull.

It is read from the first of three places that has it:

1. `ENV:cfd.prefs` - the live copy. Once the machine is up this is always the one used, so edit it for a change to apply now.
2. `ENVARC:cfd.prefs` - the saved copy. Write it too if you want the setting to survive a reboot.
3. `SYS:Prefs/Env-Archive/cfd.prefs` - the same file by its real path.

The last two matter at boot: Startup-Sequence assigns `ENV:` and `ENVARC:` only after the automount agent has started, while `SYS:` already exists. That is how a card present at boot is mounted with your settings rather than the built-in defaults.

Format:

- One key per line, the value after whitespace. A missing key keeps its default.
- Keys are matched case-sensitively as whole words, so `FLAGS` does not match inside `FLAGS_DOS`. The search covers the whole file, not just line starts: a key name appearing as a whole word inside another key's value is picked up too, so do not use key names or the `UNMOUNT` filesystem names inside unquoted values.
- `;` or `#` starts a comment: the rest of that line is ignored, so `; FLAGS 0` really is disabled.
- The file is read up to 511 bytes.

| Key | Value | Default | Meaning |
|---|---|---|---|
| `AUTOMOUNT` | `0`/`1`, `ON`/`OFF`, `YES`/`NO` | on | Mount partitions on insert. Only the first letter decides (`N`/`0` off, `Y`/`1` on, `O`+`N`/`F`), so e.g. `NEVER` reads as off; anything else is ignored and the default applies. |
| `FLAGS` | decimal | `0` | Mount flags applied to every mount. See the bit table below. |
| `CONTROL` | string | none | Mount CONTROL string applied to every mount. At most 31 characters. |
| `UNMOUNT` | names | all | Filesystems to fully unmount on removal. Any subset of `DOS FFS SFS PFS FAT`; a key with no recognized names (e.g. `UNMOUNT NONE`) keeps every handler. |
| `UNMOUNT_STATIC` | `0`/`1`, `ON`/`OFF`, `YES`/`NO` | on | `0` exempts hand-mounted (`DEVS:DOSDrivers`) partitions from `UNMOUNT`: on removal they are kept and marked absent, the handler stays in service (`S` in `lsptres`). Default `1`: they are unmounted like everything else (`s`). Takes effect on the next insert. |
| `MOUNT_USED` | `0`/`1`, `ON`/`OFF`, `YES`/`NO` | off | `1` lets a hand `DEVS:DOSDrivers` mount claim a partition another handler already serves, at your own risk: two handlers cache one FAT volume, reading mostly works, any write corrupts it. Default `0`: such a mount is refused and reports `object in use`. Takes effect on the next insert. |
| `FLAGS_<fs>` | decimal | global `FLAGS` | Per-filesystem override of `FLAGS`. |
| `CONTROL_<fs>` | string | global `CONTROL` | Per-filesystem override of `CONTROL`. |
| `DOSTYPE_FAT` | hex | detected | Mount MBR/GPT FAT partitions as this DosType instead of the detected one. See [Choosing the FAT filesystem](#choosing-the-fat-filesystem). |
| `HANDLER_FAT` | string | none | Where to load the FAT handler from when it is not already in `FileSystem.resource`, e.g. `L:CrossDOSFileSystem`. At most 23 characters. |

`FLAGS` bits (see also the README "Mount Flags" section):

| Bit value | Effect |
|---|---|
| 8 | serial debug output (full build) |
| 16 | enforce ATA multi-sector mode |

The filesystem names are exactly these five: `DOS`, `FFS`, `SFS`, `PFS`, `FAT`. Any other name (`NTFS`, `EXT2`, `PDS`, ...) is not recognised and is silently ignored. `PDS` in particular is not valid: PFS3's `PDS\x` DosType is already covered by `PFS`.

A per-filesystem key applies to partitions whose DosType high three bytes match: `DOS` = `DOS\x`, `FFS` = `DOS\x` fast-filesystem, `PFS` = `PFS\x` (and the `PDS\x` alias), `SFS` = `SFS\x`, `FAT` = `FAT\x`. Use the overrides when you want a setting on one filesystem only, for example serial debug on FAT mounts alone.

A CONTROL string is only meaningful for filesystems that parse one. For hot-plugged FAT cards, `CONTROL_FAT "+q"` enables fat95's quiet option, so no error requesters ("please reinsert", read or write windows) pop up when a card is pulled with pending writes; errors go back to the calling program instead. The fat95 documentation has the full option list.

## Choosing the FAT filesystem

MBR and GPT FAT partitions are mounted for **fat95** by default. Two keys change that, and they do separate jobs:

- **`DOSTYPE_FAT`** sets the DosType the node is mounted with. That is what selects the filesystem, because a handler is bound by DosType.
- **`HANDLER_FAT`** says where to load the handler from, and is used **only** if nothing in `FileSystem.resource` already serves that DosType.

So to hand FAT cards to CrossDOS:

```
AUTOMOUNT 1
DOSTYPE_FAT 0x4D534400
HANDLER_FAT L:CrossDOSFileSystem
```

`0x4D534400` is `MSD\0`, the CrossDOS DosType for FAT on media with no partition table. Both keys are needed today: CrossDOSFileSystem is a file in `L:`, and on a machine with fat95 it never registers itself in `FileSystem.resource`, so without `HANDLER_FAT` there is nothing to bind and the partition stays `P----`. If a FAT handler is ever resident with its own DosType, drop the `HANDLER_FAT` line and the `DOSTYPE_FAT` line alone is enough.

`HANDLER_FAT` is useful on its own too. On a machine where fat95 is neither in ROM nor already registered, this loads it from disk for the ordinary auto-detect mount:

```
HANDLER_FAT L:fat95
```

Things worth knowing:

- **CrossDOS handles the same FAT variants fat95 does**, so this is a real choice and not a restricted one: FAT32 and long filenames (VFAT) arrived in CrossDOS 45.4 and AmigaOS 3.2 ships 45.39.
- **`DOSTYPE_FAT` pins the mount to one partition's block range**, because a handler told which filesystem to be is not one auto-detecting its own partition. So unlike the default it does not follow a card swap by itself: keep the default `UNMOUNT` policy (or list `FAT`) with it, so the node is torn down and rebuilt for the next card. `HANDLER_FAT` on its own does not change this - it only says where the code comes from, so auto-detect stays intact.
- **A wrong value does not silently fall back.** If nothing serves the DosType you named and no handler path resolves, the partition stays published but unmounted, listed by `lsptres` as `P----`. On a full build `FLAGS 8` prints the parsed number as `dostype=4D534400` in the worker trace, which is the quickest way to spot a typo. `lsptres` shows the outcome in its `DosType` column.
- **Changing either key needs a card pull**, or a reboot under `UNMOUNT NONE`. Until the old node goes away its handler is still bound to that partition, and you do not want two handlers caching the same blocks.
- This is about MBR and GPT cards only. RDB partitions always use the filesystem recorded on the card, and nothing here applies at cold boot, where `cfd.prefs` cannot be read yet.

## When a partition does not mount

Automount mounts a partition only when a handler for its filesystem is already in the system. Unless you gave it a `HANDLER_FAT` path (see [Choosing the FAT filesystem](#choosing-the-fat-filesystem)), it does not load a handler from `L:` by itself, so a handler file sitting unused in `L:` does not count. A partition with no handler is still scanned and listed by `lsptres`, but stays `P----` (present, not mounted); it is never falsely shown as mounted. This is the same for every filesystem: FFS, SFS, PFS, FAT and any other.

A handler becomes available in one of these ways:

- Stored in the card's RDB, typical for native FFS, SFS and PFS partitions: `ptable.library` loads it straight from the RDB, at cold boot and on a DOS-time insert alike, so an RDB card needs nothing extra.
- Built into the Kickstart ROM (for example pfs3aio, or fat95 in a custom ROM): registered by the handler's own startup at boot.
- Made resident from disk with `LoadModule` (for example adding `L:fat95` to your `LoadModule` line): becoming resident runs the handler's startup, which registers it.
- Loaded on demand when you mount a matching DOSDriver by hand: mounting one fat95 DOSDriver loads fat95 from `L:` and registers its shared FAT code, after which automount binds every other FAT partition to it.

FAT cards are the case that needs attention: MBR, GPT and whole-disk (flat) FAT cards carry no handler in their partition table, so fat95 must come from the ROM, from `LoadModule`, or from a mounted fat95 DOSDriver.

## Booting from a CF card (ROM-resident)

At Kickstart cold start, before DOS exists, the driver opens `ptable.library`, which walks the card's RDB, loads any filesystem handlers stored in it, and registers each partition:

| RDB partition flag | Result |
|---|---|
| bootable (bit 0 set) | appears in the Early Startup boot device list |
| bootable clear | mounted as a DOS volume, not offered as a boot device |
| NOMOUNT (bit 1 set) | skipped: not mounted, not in the DOS list |

Both flags live in the RDB partition entry and are set by the partitioning tool that created it. BootPri, stored in the partition environment, does not decide bootability; it orders the boot list.

Only RDB partitions are registered at cold boot, because that runs before DOS and `cfd.prefs` cannot be read yet. MBR, GPT and flat partitions on a card present at cold boot are published to `partition.resource` and listed as `P----`; the automount agent mounts them once DOS is up, so `AUTOMOUNT`, `FLAGS` and `CONTROL_*` apply to them too. Autoboot itself does not depend on `AUTOMOUNT`. Removal is not special either: pull the card and the partitions registered at cold boot follow the same `UNMOUNT` policy as any other, so the default unmounts them and `UNMOUNT NONE` keeps their handlers.

Cold-boot autoboot runs late in Kickstart's resident init, after the internal IDE (`scsi.device`) has started. That init is sequential, so if the IDE stalls at boot (no drive connected, for instance) CF autoboot never gets its turn either. The boot stub first does a single Gayle read to check for a card; an empty slot returns immediately. With a card present it tolerates slow cards by polling the media state for up to 5 s; a healthy card adds no measurable delay.

`ptable.library` also registers a synthetic expansion board (Vendor ID `65535 ($FFFF)`, Product ID `1`) so the Early Startup boot menu sees the device. It shows up in tools like `ShowConfig`.

`LoadModule` cannot give you this. It makes on-disk modules resident and reboots, but only activates the *first* romtag of each file, which is why bringup lives in its own module: `compactflash.automount`'s first romtag is the after-DOS one, so `LoadModule` runs it, and from then on hotplug works as in a disk install. Cold-boot autoboot runs before DOS and needs all three modules in a real Kickstart ROM. A scripted Capitoline-based builder for a 1 MB AmigaOS 3.2.3 / 3.1 / 2.05 Kickstart lives in the companion [amigaos-kickstart-builder](https://github.com/pulchart/amigaos-kickstart-builder) repo.

## Checking what happened

`lsptres` lists `partition.resource`, which reflects the last-seen card whether or not its partitions are mounted. The first character of the `Flags` column is the media state:

| Char | Meaning |
|---|---|
| `P` | present: the card in the slot has this partition |
| `I` | invalid: the slot is still mounted, but the card currently inserted has no such partition, typically after a card swap. Shows as `I--M-` and returns to `P` when the original card comes back |
| `-` | absent: no card in the drive. A kept mount whose media is gone shows `---M-` |

The remaining characters are `B` bootable, `N` nomount, `M` mounted. `MFlg` is the resolved mount flags and `Ctrl` the resolved CONTROL string. A mounted volume shows as `scanname>dosname` when its real DOS name differs from the scanned name.

For a serial trace of a DOS-time mount, set `FLAGS 8` (full build, 9600 baud). A `full` build also prints the cold-boot part unconditionally, whatever the flags say, with `[CFD] boot:` for the driver and `[PT]` for the library:

```
[CFD] boot: open ptable.library ...
[CFD] boot: BootScanPartitions(compactflash.device,0)
[PT] cold boot: scanning for partitions
[PT] RDB partition table
[PT] + filesystem handler PFS v20.0
[PT] - skip  SDH10 (no-mount) (MAC\0, 32 MB)
[PT] + boot  SDH0 (PFS\3, 512 MB)
[PT] + mount SDH1 (PFS\3, 1024 MB)
[PT] + mount SDH2 (PFS\3, 495 MB)
[PT] cold boot done, partitions registered: 3
```

## Troubleshooting

- Nothing automounts: check that `ENV:cfd.prefs` does not say `AUTOMOUNT 0` (the default is on), and that `ptable.library` is reachable, ROM-resident or in `LIBS:`.
- File-based install, card present but nothing happens: the driver is not loaded until something opens it. Add a `DEVS:DOSDrivers/CF0` entry so it loads at boot.
- Partitions listed in `lsptres` but not mounted: automount is off, or their filesystem has no handler available.
