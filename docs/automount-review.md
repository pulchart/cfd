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

Expected: (2) the running handler claims the partition first and the automount backs off: `lsptres` shows `CF0>CFAUX` with the fifth flag `s` (static, follows `UNMOUNT`), no automount `CF0` appears. (3) By default the static mount is torn down like everything else (`[PT] unmounted CF0`); the next card is automounted under the synthesized name. (4) With `UNMOUNT_STATIC 0` the row shows `S` and the pull keeps the mount: `[PT] static mount kept`, row `---MS`, `Assign` still lists `CFAUX`. (5) The same handler reattaches. The `s`/`S` letter always shows what the next removal will do; a changed key takes effect on the next insert. (6) A hand-removed mount leaves the partition claimed in the resource until a reboot or a fresh `Mount`.

```
Name         Device        Unit Part Src Pri DosType    Text Flags  MFlg Ctrl
------------ ------------- ---- ---- --- --- ---------- ---- ----- ----- ----------
CF0>CFAUX    compactflash.    0    0 GPT   0 0x464154FF FAT. P--Ms     0 -d-D
```

## 9. One partition, one handler

1. Insert MBR-FAT or GPT-FAT, let the automount mount `CF0`.
2. `Mount CFAUX:` (auto-detect DOSDriver on the same device) and `dir CFAUX:`.
3. Pull the card; `dir CFAUX:` again.
4. Put `MOUNT_USED 1` in `ENV:cfd.prefs`, reinsert the card, repeat step 2.

Expected: (2) the second mount fails and accesses report `object is in use` (error 202); the serial shows no second `[PT] mounted as`; `lsptres` keeps the single `CF0` row; the Workbench icons do not fight. (3) With the card out the error returns to a plain no-disk. (4) With `MOUNT_USED 1` the second mount succeeds at your own risk: two handlers cache one volume, reading mostly works, any write corrupts it, and `partition.resource` keeps the original `CF0` registration (no `[PT] mounted as CFAUX`). Never write in that state.

## 10. Teardown lifecycle (disk-loaded modules)

Requires `compactflash.device` and `ptable.library` loaded from disk, not from ROM.

1. `LoadModule` the automount set; confirm a `CF.MountAgent` task exists (e.g. in Scout).
2. Insert a card, let it mount, pull it (default `UNMOUNT`, everything torn down).
3. Close anything holding the device, then `Avail FLUSH` twice.
4. Insert a card.

Expected: the flush expunges the driver cleanly - the mount agent is handshaked down first, no `CF.MountAgent` task remains, and the later insert must not crash. `ptable.library` refuses to expunge while `partition.resource` exists, so the resource never points into freed memory and a second copy of it can never appear.
