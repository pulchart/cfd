# compactflash.device automount and configuration

This guide covers autoboot and automount for `compactflash.device`, and the `ENV:cfd.prefs` configuration file. The partition scanning and mounting itself is done by `ptable.library` (see its own `ptable.guide` for the library internals); this document is the user-facing reference.

## What automount does

`compactflash.device` reconciles `partition.resource` against the inserted card and (optionally) mounts its partitions. There are two stages:

- Cold-boot autoboot (ROM-resident only): at Kickstart cold start, before DOS exists, the driver opens `ptable.library`, which walks the RDB on the card, loads any filesystem handlers stored in the RDB, and registers each partition as either bootable (appears in the Early Startup boot menu) or mountable-only. This is what lets you boot straight from an RDB-partitioned CF card.
- DOS-time (runtime) hotplug: after the machine is up, inserting a card scans it (RDB, MBR, GPT, or whole-disk flat) and publishes each partition into `partition.resource`; if automount is enabled the partitions are then mounted. Removing a card marks them absent (keep the filesystem handler) or unmounts (dismount filesystem handler) them, per the configured policy.

`ptable.library` is required for both. Without it the device still works as a plain mount-only device (mount partitions yourself via `DEVS:DOSDrivers/`), but autoboot and automount are unavailable.

## Filesystem handlers

Automount mounts a partition only when a handler for its filesystem is already present in the system. It never loads a filesystem handler from `L:` by itself, so a handler file sitting unused in `L:` does not count. When no handler is available for a partition's filesystem, the partition is still scanned and listed by `lsptres`, but stays `P---` (present, not mounted); it is never falsely shown mounted. This applies to every filesystem the same way: FFS, SFS, PFS, FAT and any other.

A handler becomes available in one of these ways:

- Stored in the card's RDB (typical for native FFS, SFS and PFS partitions): `ptable.library` loads it straight from the RDB, both at cold boot and on a DOS-time insert, so an RDB card needs nothing extra.
- Built into the Kickstart ROM (for example pfs3aio, or fat95 in a custom ROM): registered by the handler's own startup at boot.
- Made resident from disk with `LoadModule` (for example adding `L:fat95` to your `LoadModule` line): becoming resident runs the handler's startup, which registers it.
- Loaded on demand when you mount a matching DOSDriver by hand: mounting one fat95 DOSDriver, for instance, loads fat95 from `L:` and registers its shared FAT code, after which automount binds every other FAT partition to it.

FAT cards are the case that needs attention: MBR, GPT and whole-disk (flat) FAT cards carry no handler in their partition table, so fat95 must be provided by the ROM, `LoadModule`, or a mounted fat95 DOSDriver. Native FFS/SFS/PFS partitions on an RDB card carry their handler in the RDB, so they mount with no extra step.

## Modules and deployment

There are three modules, and boot/automount is opt-in by whether you include the third:

- `compactflash.device`: the I/O driver. On its own it is a plain mount-only device.
- `ptable.library`: the partition scanner and automounter (RDB, MBR, GPT, flat FAT).
- `compactflash.automount`: optional boot/automount bringup. It carries two romtags: a cold-boot one (scans the card's RDB and registers partitions for autoboot, ROM only) and an after-DOS one (opens the device once DOS is up, which starts the card-detect interrupt and the automount agent). Include it only when you want autoboot or automount.

Typical setups:

| Goal | Modules | Cold-boot autoboot |
|---|---|---|
| ROM autoboot | `compactflash.device` + `compactflash.automount` + `ptable.library` in Kickstart | available |
| Resident/on-disk, no automount | `compactflash.device` + `ptable.library` (no automount module) | no |
| On-disk automount | `LoadModule LIBS:compactflash.automount LIBS:ptable.library DEVS:compactflash.device` (+ `L:fat95`) | no |

`AUTOMOUNT` defaults **on everywhere** (ROM-resident and on-disk alike). Disable it with `AUTOMOUNT 0` in `ENV:cfd.prefs`; the resident driver re-reads that file on every card insert, so the setting takes effect without a rebuild. An explicit `AUTOMOUNT 0`/`1` always takes precedence over the default. An example config is shipped as `ENVARC/cfd.prefs` (copy it to `ENVARC:cfd.prefs` and `ENV:cfd.prefs`).

The prefs are read from the first of three sources that has them: `ENV:cfd.prefs` (via `GetVar`), then `ENVARC:cfd.prefs`, then `SYS:Prefs/Env-Archive/cfd.prefs`. The third one covers the boot window: Startup-Sequence assigns `ENV:` and `ENVARC:` only after the after-DOS bringup that starts the automount agent, while `SYS:` already exists at that point. A card present at boot is therefore mounted with your prefs applied (`AUTOMOUNT`, `FLAGS`, `CONTROL_*`), not the built-in defaults. Once Startup-Sequence has run, `ENV:` is the source, so a change there applies to the next insert.

The cold-boot `RTF_COLDSTART` scan runs before DOS exists and cannot read `cfd.prefs`. It therefore registers **RDB partitions only**, the autoboot chain: bootable ones as boot-menu entries, the rest as mountable volumes, exactly as before. MBR, GPT and flat (superfloppy) partitions found at cold boot are published into `partition.resource` but not mounted there; the DOS-time automount mounts them once the prefs are known, so `AUTOMOUNT`, `FLAGS` and `CONTROL_*` apply to them on a ROM-resident system too. Cold-boot RDB *autoboot* does not depend on `AUTOMOUNT`, and RDB partitions registered at cold boot are never unmounted by the automount agent.

Other notes:

- Even with automount off, an inserted card is still scanned and published to `partition.resource`, so `lsptres` lists the partitions; they are just not mounted.
- When you mount a device-dostype DOSDriver by hand (e.g. `CFAUX`), it serves its own partition. Automount pauses on each pass so that handler can claim its partition first, then reuses it (shown as `CFa0>CFAUX`) and mounts only the other partitions, rather than starting a second handler on the same one.

### On-disk automount via LoadModule

`LoadModule` (AmigaOS 3.x) makes on-disk modules resident and reboots. It activates only the *first* romtag of each file, which is why boot/automount lives in its own module: `compactflash.automount`'s first romtag is the after-DOS one, so `LoadModule` runs it. It opens the device once DOS is up, bringing up the card-detect interrupt and the automount agent; from then on hotplug works as in a disk install. Put `compactflash.automount` (and `ptable.library`) in `LIBS:` and add to `user-startup-sequence`:

```
LoadModule LIBS:compactflash.automount LIBS:ptable.library DEVS:compactflash.device L:fat95
```

This does not give cold-boot RDB autoboot (booting straight off a CF card): that runs before DOS and needs `compactflash.device` + `compactflash.automount` + `ptable.library` in a real Kickstart ROM (see the companion kickstart-builder). `LoadModule` cannot provide it.

### Building your own ROM

A scripted Capitoline-based ROM builder for a 1 MB AmigaOS 3.2.3 / 3.1 / 2.05 Kickstart with `compactflash.device` + `ptable.library` embedded lives in the companion [amigaos-kickstart-builder](https://github.com/pulchart/amigaos-kickstart-builder) repo.

## ENV:cfd.prefs reference

Configuration is read at mount time from the first source that has it: `ENV:cfd.prefs`, then `ENVARC:cfd.prefs`, then `SYS:Prefs/Env-Archive/cfd.prefs`. Once the machine is up that is always the live `ENV:` copy, so update `ENV:cfd.prefs` for a change to apply now, and write `ENVARC:cfd.prefs` too if you want it to survive a reboot. The two file paths are what the first mount after boot uses, before Startup-Sequence has assigned `ENV:`. The driver re-reads the config on every card insert and every card removal, so a change takes effect the next time you insert or remove a card, with no reboot or rebuild needed. Because removal is re-read too, a changed `UNMOUNT` applies to the very next card you pull. The format is one key per line, the value following the key after whitespace; keys are matched case-sensitively as whole words (so `FLAGS` does not match inside `FLAGS_DOS`). A missing key keeps its default.

Lines can be commented out with `;` or `#`: everything from that character to the end of the line is ignored, so `; FLAGS 0` really is disabled. An example you can copy is shipped as `ENVARC/cfd.prefs`. The config is read up to 511 bytes.

| Key | Value | Default | Meaning |
|---|---|---|---|
| `AUTOMOUNT` | `0`/`1`, `ON`/`OFF`, `YES`/`NO` | on | Mount partitions on insert. Any other value is ignored and the default applies. |
| `FLAGS` | decimal | `0` | Mount flags applied to every mount. See the bit table below. |
| `CONTROL` | string | none | Mount CONTROL string applied to every mount. |
| `UNMOUNT` | names | all | Filesystems to fully unmount on removal (see "Removable-media model"). Any subset of `DOS FFS SFS PFS FAT`; a key with no recognized names (e.g. `UNMOUNT NONE`) keeps every handler. |
| `FLAGS_<fs>` | decimal | global `FLAGS` | Per-filesystem override of `FLAGS`. `<fs>` is one of `DOS FFS SFS PFS FAT`. |
| `CONTROL_<fs>` | string | global `CONTROL` | Per-filesystem override of `CONTROL`. |

`FLAGS` bits (see also the README "Mount Flags" section for the full description):

| Bit value | Effect |
|---|---|
| 8 | serial debug output (full build) |
| 16 | enforce ATA multi-sector mode |

The filesystem names understood in `UNMOUNT`, `FLAGS_<fs>` and `CONTROL_<fs>` are exactly these five, and no others: `DOS`, `FFS`, `SFS`, `PFS`, `FAT`. Any other name (`NTFS`, `EXT2`, `PDS`, ...) is not recognised and is silently ignored, taking no effect. In particular `PDS` is not a valid name: PFS3's `PDS\x` DosType is already covered by the `PFS` name, so use `PFS` for it.

A per-filesystem key applies to partitions whose DosType high three bytes match: `DOS` = `DOS\x`, `FFS` = `DOS\x` fast-filesystem, `PFS` = `PFS\x` (and the `PDS\x` alias), `SFS` = `SFS\x`, `FAT` = `FAT\x`. Use the per-FS overrides when, for example, you want serial debug only on FAT mounts.

Tip for hot-plugged FAT cards: `CONTROL_FAT "+q"` enables fat95's quiet option, so no error requesters ("please reinsert" / read / write windows) can pop up when a card is pulled with pending writes; errors are returned to the calling program instead. See the fat95 documentation for the full option list.

### Example

```
AUTOMOUNT 1
FLAGS 0
UNMOUNT FAT
CONTROL_FAT +q
```

This keeps automount on (the default, listed for clarity), restricts the removal policy so only FAT volumes are fully unmounted when the card is pulled (PFS and others keep their handler, see below), and passes the `+q` (quiet) option to FAT (fat95) mounts only. Note that a CONTROL string is only meaningful for filesystems that parse one.

## Removable-media model

- Insert: the card is scanned and its partitions are published to `partition.resource` (always, even when automount is off). With automount on, partitions that are not yet mounted are mounted.
- Remove, default (no `UNMOUNT` key): every partition is fully unmounted (handler stopped, DOS node removed, memory freed). Its `partition.resource` line is kept and shown absent, so the partition is still listed; reinserting the card mounts it fresh.
- Remove, `UNMOUNT <fs>`: only partitions of the listed filesystems are unmounted as above. A filesystem not listed is marked absent instead: its DOS node and handler are kept in memory, and reinserting the same card reattaches it without re-initialising the handler (the native AmigaOS removable-media behaviour). `UNMOUNT NONE` (no recognized names) keeps every handler.

Either way the partition stays visible in `lsptres` (shown absent) while the card is out, and is re-confirmed or re-published on reinsert.

`AUTOMOUNT` gates only the mount step; it does not unmount. Changing `AUTOMOUNT 1` to `0` does not unmount volumes already mounted. To clear them, pull the card (the default removal policy unmounts them) or reboot.

The same applies to `FLAGS` and `CONTROL`: a handler reads them when it starts, so a changed `CONTROL_<fs>` reaches a partition only when that partition is mounted again. Under `UNMOUNT NONE`, or for a filesystem left out of the `UNMOUNT` list, the handler is kept across a card swap and keeps the values it started with. List the filesystem in `UNMOUNT` and reinsert the card to apply a new one.

## Cold-boot autoboot details (ROM-resident)

How each RDB partition is handled at cold boot:

| RDB partition flag | BootPri | Result |
|---|---|---|
| normal | >= 0 | bootable: appears in the Early Startup boot device list |
| normal | < 0 | non-bootable: mounted as a DOS volume |
| NOMOUNT (bit 1 set) | any | skipped: not mounted, not in the DOS list |

BootPri is stored in the RDB partition environment and controls boot order.

Only RDB partitions are registered at cold boot. MBR, GPT and flat partitions on a card present at cold boot are published to `partition.resource` and listed by `lsptres` as not mounted (`P---`); the automount agent mounts them once DOS is up and `cfd.prefs` is readable.

The driver's cold-boot autoboot runs late in Kickstart's resident init, after the internal IDE (`scsi.device`) has started. Because that init is sequential, if the IDE stalls at boot (for example no drive connected), CF autoboot never gets its turn and does not trigger either. The boot stub first does a single Gayle read to check for a card; an empty slot returns immediately. With a card present it tolerates slow cards by polling up to about 1.8 s total; a healthy card adds no measurable delay.

`ptable.library` also registers a synthetic expansion board (Vendor ID `65535 ($FFFF)`, Product ID `1`) so the Early Startup boot menu sees the device; it shows up in tools like `ShowConfig`.

### Serial debug at cold boot

A `full` build emits unconditional serial output at cold boot (9600 baud), regardless of the mountlist `Flags` setting. `compactflash.device` uses the `[CFD] boot:` prefix and `ptable.library` uses `[PT]`:

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

## Inspecting with lsptres

`lsptres` lists `partition.resource`, which reflects the last-seen card whether or not partitions are mounted. The `Flags` column first char is `P` present, `I` invalid, or `-` absent. `I` means the slot is still mounted (its handler and DOS node are kept in memory), but the card currently in the slot has no such partition, typically after a card swap; it shows as `I--M` and returns to `P` when the original card is reinserted. A slot with no card in the drive at all reads `-`, so a kept mount whose media is simply gone shows `---M`. The remaining chars are `B` bootable, `N` nomount, `M` mounted. `MFlg` is the resolved mount flags and `Ctrl` the resolved CONTROL string. A mounted volume shows as `scanname>dosname` when its real DOS name differs from the scanned name.

## Troubleshooting

- Nothing automounts: check that `ENV:cfd.prefs` does not say `AUTOMOUNT 0` (the default is on), and that `ptable.library` is reachable (ROM-resident, or in `LIBS:` for DOS-time mounts).
- File-based, card present but nothing happens: the driver is not loaded until something opens it. Add a `DEVS:DOSDrivers/CF0` entry so it loads at boot.
- Partitions listed in `lsptres` but not mounted: automount is off, or they are a non-FAT filesystem with no handler available.
- Want serial trace of a DOS-time mount: set `FLAGS 8` (full build).
