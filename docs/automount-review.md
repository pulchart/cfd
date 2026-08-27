# Automount feature review

This document catalogues the expected behaviour of the automount feature, scenario by scenario, as verified on real hardware. Each scenario is written as steps plus the expected outcome, so it doubles as a test case: if the machine behaves differently, that is a defect worth reporting. The expectations themselves are not immutable - one can change when it turns out to hide a defect, a logical contradiction, or a technical limitation - but any such change lands here and in the release notes, never silently.

Observation tools: `lsptres` lists `partition.resource` (flag pictures like `P--M-` are explained in its guide), serial lines like `[PT] ...` come from a full build at 9600 baud, and `FLAGS 8` in `ENV:cfd.prefs` adds the driver's `[MW]`/`[MA]` lines. The configuration keys are documented in `automount.guide`.

## Cards mentioned in this document

- **RDB-PFS**: an RDB-partitioned card with at least one mountable partition named `DH0` (PFS3, FFS or similar).
- **RDB-PFS-2**: a second RDB card whose partition is also named `DH0`, but with a different start block and size.
- **GPT-FAT**: a GPT card with two or more FAT partitions.
- **MBR-FAT**: an MBR card with one or more FAT partitions.

Any FAT-formatted card works where a scenario says "MBR-FAT or GPT-FAT"; the specific layouts only matter where a scenario calls for them (several partitions, a name clash).

## 1. Basic automount

1. Default `cfd.prefs` (`AUTOMOUNT 1`, `CONTROL_FAT -d-D+q`; add `FLAGS 8` for the serial trace).
2. Insert RDB-PFS.
3. Pull it and insert MBR-FAT or GPT-FAT.
4. Read and write a file on each mounted volume.
5. Pull the card and reinsert it.

Expected: every insert scans and publishes all partitions to `partition.resource`, even with `AUTOMOUNT 0` (`lsptres` lists them either way). RDB partitions mount under their on-disk names (e.g. `DH0`), FAT partitions as `CF0`, `CF1`, ... The volumes are read/write. On removal the mounts are torn down or kept per the `UNMOUNT` policy; reinserting mounts the card again.

```
Name         Device        Unit Part Src Pri DosType    Text Flags  MFlg Ctrl
------------ ------------- ---- ---- --- --- ---------- ---- ----- ----- ----------
CF0          compactflash.    0    0 GPT   0 0x464154FF FAT. P--M-     0 -d-D+q
CF1          compactflash.    0    1 GPT   0 0x464154FF FAT. P--M-     0 -d-D+q
```

## 2. Scheme swap in one slot

`UNMOUNT NONE` in the prefs.

1. Insert RDB-PFS, let `DH0` mount.
2. Pull it.
3. Insert MBR-FAT or GPT-FAT in the same slot.
4. `lsptres`.

Expected: the old `DH0` row goes invalid (`I--M-`, its handler still owns the mount); the FAT partition appears as a NEW row (`CF0`). A mounted entry is never rewritten across partition schemes. Under the default `UNMOUNT` the old mount is torn down on the next removal; under `UNMOUNT NONE` it stays until its own card returns.

## 3. Two cards with the same RDB name

`UNMOUNT NONE` in the prefs.

1. Insert RDB-PFS (`DH0` mounts).
2. Pull it (the row goes `---M-`, kept).
3. Insert RDB-PFS-2 (also `DH0`, different start and size).
4. `dir DH0:` and `dir DH0.1:`.

Expected: the second mount is uniquified: `lsptres` shows `DH0>DH0.1`, `Assign` lists both names, and `DH0.1:` reads the second card. Two DOS devices with one name must never appear.

## 4. Reuse of a same-named hand mountlist

1. No card in the slot. Mount a fat95 auto-detect DOSDriver named `CF0` by hand (`compactflash.device` unit 0, `LowCyl = 0`).
2. Insert MBR-FAT or GPT-FAT.

Expected: the automount finds the existing node and reuses it instead of creating a duplicate: the serial shows `[PT] reusing handler CF0`, one handler serves the partition, `Assign` lists `CF0` once, and no `CF0.1` appears. Only auto-detect nodes (`LowCyl = 0`) are reused; a fixed-geometry node belongs to its own partition and is left alone.

## 5. Name dedup and the partition selector

Force a name clash the reuse cannot resolve, so the automount uniquifies to `CF0.1`.

1. Mount a dummy DOSDriver named `CF0` by hand on an unrelated device (a small RAM or file handler mountlist), so the name is already taken.
2. Insert GPT-FAT.
3. `lsptres`: the automount node is named `CF0.1`.
4. Read a known file from `CF0.1:`.

Expected: `CF0.1` serves the FIRST FAT partition - the `.1` dedup suffix never shifts fat95's trailing-digit partition selector. The second partition mounts as `CF1` (no clash), and a suffixed `CF1.N` would likewise serve the second.

## 6. No cfd.prefs anywhere

1. Remove `cfd.prefs` from `ENV:`, `ENVARC:` and `SYS:Prefs/Env-Archive`.
2. Insert MBR-FAT or GPT-FAT; watch the serial for the delay before `[MW] config: src=0`.
3. Pull the card and insert it again.

Expected: the roughly 2 s source retry is paid on the first insert only; every later insert goes straight through with just the settle delay, using the built-in defaults.

## 7. Configuration parser edges

1. Put this exact `cfd.prefs` (unterminated quote, 9-digit hex):

```
AUTOMOUNT 1
FLAGS 8
CONTROL_FAT "+q
UNMOUNT NONE
DOSTYPE_FAT 0x4D5344001
HANDLER_FAT L:CrossDOSFileSystem
```

2. Insert MBR-FAT or GPT-FAT, then `lsptres`.

Expected: the quoted value ends at its line, so `Ctrl` reads `+q` and the following lines stay keys; the serial shows `dostype=4D534400` (hex parsing stops after 8 digits); the partition mounts through `L:CrossDOSFileSystem` with DosType `0x4D534400 MSD.`.

## 8. Static mounts and UNMOUNT_STATIC

1. Boot without a card. `Mount CFAUX:` (a fat95 auto-detect DOSDriver) and `dir CFAUX:` so the handler is running.
2. Insert MBR-FAT or GPT-FAT.
3. Pull the card.
4. Put `UNMOUNT_STATIC 0` in `ENV:cfd.prefs`, reinsert the card (the policy is stamped during the mount pass), pull it again.
5. Reinsert once more.
6. `Assign CFAUX: DISMOUNT`.

Expected: (2) the running handler claims the partition first and the automount backs off: `lsptres` shows `CF0>CFAUX` with the fifth flag `s` (static, follows `UNMOUNT`), no automount `CF0` appears. (3) By default the static mount is torn down like everything else (`[PT] unmounted CF0`); the next card is automounted under the synthesized name. (4) With `UNMOUNT_STATIC 0` the row shows `S` and the pull keeps the mount: `[PT] static mount kept`, row `---MS`, `Assign` still lists `CFAUX`. (5) The same handler reattaches. The `s`/`S` letter always shows what the next removal will do; a changed key takes effect on the next insert. (6) A cleanly shut down mount unregisters itself and the partition is free again (see scenario 11); a handler that disappears without an accepted `ACTION_DIE` leaves the partition claimed until a reboot, a fresh `Mount`, or the next card removal under a tearing `UNMOUNT` policy cleans the leftover.

```
Name         Device        Unit Part Src Pri DosType    Text Flags  MFlg Ctrl
------------ ------------- ---- ---- --- --- ---------- ---- ----- ----- ----------
CF0>CFAUX    compactflash.    0    0 GPT   0 0x464154FF FAT. P--Ms     0 -d-D
```

## 9. One partition, one handler

1. Insert MBR-FAT or GPT-FAT, let the automount mount `CF0`.
2. `Mount CFAUX:` (auto-detect DOSDriver on the same device) and `dir CFAUX:`.
3. Pull the card; `dir CFAUX:` again.
4. `MOUNT CFAUX: SHUTDOWN`, then `ASSIGN CFAUX: DISMOUNT`; put `MOUNT_USED 1` in `ENV:cfd.prefs`; reinsert the card.
5. Repeat step 2, then `lsptres`.
6. `MOUNT CFAUX: SHUTDOWN`, then `lsptres`.
7. `ASSIGN CFAUX: DISMOUNT`, repeat step 2, then pull the card and `lsptres`; reinsert.

Expected: (2) the `Mount` command itself succeeds (it only adds the DOS node; the handler starts on the first reference), but the claim is refused: `dir CFAUX:` reports `object is in use` (error 202), the serial shows no second `[PT] mounted as`, `lsptres` keeps the single `CF0` row, and the Workbench icons do not fight. (3) With the card out the error returns to a plain no-disk (error 226) and the automount retires `CF0` under the default policy. (4) The leftover hand node must go before the reinsert: with it still in place the automount adopts the `CFAUX` handler for the whole partition (scenario 4) instead of mounting its own `CF0`, and the extra-mount state below never appears. After the clean unmount (scenario 11) the reinsert automounts `CF0` again. (5) With `MOUNT_USED 1` the second mount succeeds at your own risk: two handlers cache one volume, reading mostly works, any write corrupts it. The extra mount appears as its own `lsptres` row next to the owner's, serial `[PT] mounted as CFAUX`:

```
Name         Device        Unit Part Src Pri DosType    Text Flags  MFlg Ctrl
------------ ------------- ---- ---- --- --- ---------- ---- ----- ----- ----------
CF0          compactflash.    0    0 GPT   0 0x464154FF FAT. P--M-     0 -d-D+q
CF0>CFAUX    compactflash.    0    0 GPT   0 0x464154FF FAT. P--Ms     0
```

The owner's row is never overlaid. Never write in that state. (6) The extra handler's clean shutdown removes its own row (`[PT] unregistered CF0`); the owner's row stays. `Mount CFAUX:` alone would now report the device is already mounted: `SHUTDOWN` keeps the DOS node (scenario 11). (7) After the dismount the extra mount repeats cleanly (two rows again); pulling the card with both mounts live retires each row on its own, the serial shows two `[PT] unmounted CF0` lines under the default policy and `lsptres` empties:

```
[PT] card removed, media absent
[PT] unmounting partitions
[PT] unmounted CF0
[PT] unmounted CF0

Name         Device        Unit Part Src Pri DosType    Text Flags  MFlg Ctrl
------------ ------------- ---- ---- --- --- ---------- ---- ----- ----- ----------
```

The reinsert then automounts a single `CF0` (`P--M-`) again.

## 10a. Flush with the automount set loaded

Requires the modules loaded from disk, not from ROM. A task lister (Scout, or a CLI one) shows the `CF.MountAgent` task the driver runs per unit; any first `OpenDevice` starts it.

Setup: `LoadModule LIBS:compactflash.automount LIBS:ptable.library DEVS:compactflash.device L:fat95`.

1. Boot with the set loaded; confirm the `CF.MountAgent` task exists.
2. Insert a card, let it mount, pull it (default `UNMOUNT`, everything torn down).
3. `Avail FLUSH` twice.
4. Insert a card.

Expected: the flush is a NO-OP for the driver. The automount module keeps the device open permanently, so it can never expunge: `CF.MountAgent` survives the flush and the later insert mounts normally. (Removing the automount set is not a runtime operation; it takes a reboot without the `LoadModule` line.)

## 10b. Driver expunge without the automount module

Setup: no `LoadModule`; `compactflash.device` in `DEVS:`, `ptable.library` in `LIBS:`, `L:fat95`, a hand `CFAUX` DOSDriver.

1. Insert a FAT card, `Mount CFAUX:`, `dir CFAUX:` - the device open starts the unit and its `CF.MountAgent`.
2. `MOUNT CFAUX: SHUTDOWN`, then `ASSIGN CFAUX: DISMOUNT` (scenario 11) - the handler exits and closes the device.
3. `Avail FLUSH` twice.
4. `Mount CFAUX:` and `dir CFAUX:` again.

Expected: with nothing holding the device, the flush expunges the driver cleanly - the agent is handshaked down before the unit, no `CF.MountAgent` task remains, and nothing crashes. `ptable.library` (pulled from `LIBS:` by the auto-detect mount) refuses to expunge while `partition.resource` exists, so the resource never points into freed memory, `lsptres` keeps working, and a second copy of the resource can never appear. The re-mount then loads everything afresh and works.

## 11. Clean hand unmount (MOUNT SHUTDOWN + ASSIGN DISMOUNT)

AmigaOS Mount documents `MOUNT <dev>: SHUTDOWN && ASSIGN <dev>: DISMOUNT` as the clean way to unmount a volume by hand; this scenario verifies it against a static mount. The behaviour rests on the filesystem handler, not on the automount: `SHUTDOWN` works only as well as the handler's `ACTION_DIE` support (Mount's own help notes that not all handlers can be shut down). The expectations below describe fat95; a different handler that refuses or misbehaves here is that handler's defect to report and fix.

1. As in scenario 8: `Mount CFAUX:`, `dir CFAUX:`, insert MBR-FAT or GPT-FAT so the hand handler claims the partition (`CF0>CFAUX`).
2. Open a window on `CFAUX:` (or hold a lock), then `MOUNT CFAUX: SHUTDOWN`.
3. Close the window, `MOUNT CFAUX: SHUTDOWN` again.
4. `dir CFAUX:`.
5. `MOUNT CFAUX: SHUTDOWN && ASSIGN CFAUX: DISMOUNT`.
6. Pull the card and reinsert it.

Expected: (2) the shutdown is refused with `object is in use` while anything holds the volume; the handler keeps serving. (3) The shutdown is accepted silently and the handler exits a moment later; the device node stays (`Assign` still lists `CFAUX`), and the handler unregisters its mount on the way out, so the `lsptres` row returns to `CF0` `P----`. Repeating the command then reports device not mounted (no live handler to ask). (4) The handler restarts from the kept node and claims the partition again (`CF0>CFAUX`). (5) Both commands run (the shutdown returns success); the name is unlinked and the entry stays published-only, so the partition is free: a fresh `Mount CFAUX:` works, and (6) after a pull and reinsert the automount mounts it as `CF0`. Only a handler that disappears without an accepted `ACTION_DIE` leaves the entry claimed; the next card removal under a tearing `UNMOUNT` policy cleans such a leftover gracefully.
