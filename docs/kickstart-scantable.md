# 1 MB AmigaOS 3.x Kickstart: the E0 bank scantable patch

A 1 MB Kickstart spans two memory banks: F8 (0xF80000–0x1000000) and E0 (0xE00000–0xE80000). Stock 512 KB exec.library was built to scan only F8. Producing a working 1 MB ROM therefore requires teaching Exec to also scan E0 so it can find anything you put in that bank (`workbench.library`, `icon.library`, extra devices, etc.).

There are three distinct ways to do that. This document explains all three.

## Background

### How Exec finds modules in ROM

At cold boot, Exec's `InitResident()` walks a list of address ranges and searches each range for the matchword `0x4AFC` (`RTC_MATCHWORD`). Each match is the head of a `Resident` structure that names the module and points at its init routine. Modules competing for the same name resolve by version + priority.

The list of address ranges Exec walks lives inside exec.library as the **scantable**, a sequence of 32-bit `(start, end)` pairs terminated by `0xFFFFFFFF`.

### The default 3.2.x scantable

```
pair 0: (F80000, ENDSKIP)  First entry; covers exec.library's
                           own data so the scan doesn't
                           re-match the host module. Redundant
                           with pair 1 below.
pair 1: (F80000, 1000000)  entire F8 ROM bank (512 KB).
pair 2: (F00000, F80000)   F0 area (reset / diagnostics).
        FFFFFFFF           terminator.
```

`ENDSKIP` is a 32-bit value read from exec.library's ROMTAG (`rt_EndSkip`). Both pair 0 and pair 1 cover `0xF80000` onwards; pair 0 ends slightly earlier than pair 1, which makes it functionally useless once pair 1 is processed.

That redundancy is the cheap real-estate the in-place patch (pattern A below) reclaims for the new E0 entry.

### Pattern A: patch the embedded scantable in place

```
add "$SOURCEROM" exec.library
var ENDSKIP romdata $exec.library.(ROMTAG.ENDSKIP) 4
var ENDSKIP mid 2
find $exec.library 0x00F80000$ENDSKIP00F800000100000000F0000000F80000FFFFFFFF
var FIND add $ROMBASE
patch $FIND 0x00F8000001000000      # entry 0 := (F80000, 1000000)
var FIND add 8
patch $FIND 0x00E0000000E80000      # entry 1 := (E00000, E80000) NEW
var FIND add 8
patch $FIND 0x00F0000000F80000      # entry 2 := (F00000, F80000)
var FIND add 8
patch $FIND 0xFFFFFFFF              # terminator
```

What each line does:

1. `add "$SOURCEROM" exec.library`: embed stock exec.library at the top of the F8 ROM image.
2. `var ENDSKIP romdata $exec.library.(ROMTAG.ENDSKIP) 4`: read the 4-byte `rt_EndSkip` field from exec.library's ROMTAG; this is the value that appears in pair 0 of the default scantable.
3. `var ENDSKIP mid 2`: truncate to the 2-byte form that the `find` pattern uses (Capitoline's `find` matches on a byte-stream representation of the variable).
4. `find $exec.library 0x...FFFFFFFF`: locate the exact 28-byte scantable block inside exec.library by matching its full byte pattern. `FIND` is set to the matched offset.
5. `var FIND add $ROMBASE`: promote `FIND` from a module-local offset to an absolute ROM address (`0x00F8XXXX`).
6. Four `patch $FIND ... ; var FIND add 8` pairs that overwrite the 28 bytes in place with the new four entries.

Result:

```
pair 0: (F80000, 1000000) F8 bank
pair 1: (E00000, E80000)  E0 bank NEW
pair 2: (F00000, F80000)  F0 area
        FFFFFFFF          terminator
```

28 bytes in, 28 bytes out. `exec.library` stays at offset 0; every subsequent module lands at exactly the address Capitoline-from-stock would have produced.

### Pattern B: add a new scantable chunk and redirect exec.library's pointer

This is the pattern that ships in the Capitoline reference tests (e.g. `Capitoline Hashes/Tests/0x5fa4b9af.Hyperion.3.2.2.1Mb.A1200.test`, extracted from its INI envelope's `Text=...` field):

```
add "$SOURCEROM" exec.library
add Components/BinaryChunks/1Mb_Scantable.3.2.bin
var ENDSKIP romdata $exec.library.(ROMTAG.ENDSKIP) 4
var ENDSKIP mid 2
patch $1Mb_Scantable.3.2.bin.(START) 0x00F80000$ENDSKIP
var STSTART $1Mb_Scantable.3.2.bin.(START)
var STSTART add $ROMBASE
find $exec.library 0x00F80000$ENDSKIP00F800000100000000F0000000F80000FFFFFFFF
var FIND add $ROMBASE
find $exec.library $FIND
patch $FIND $STSTART
```

What each step does:

1. Add exec.library, same as pattern A.
2. Append the pre-built scantable chunk `1Mb_Scantable.3.2.bin` (ships with Capitoline under `Components/BinaryChunks/`). The chunk contains placeholder + `(F80000,1000000)(E00000,E80000)(F00000,F80000)FFFFFFFF`.
3. Read `ENDSKIP` from exec.library (same as pattern A).
4. Patch the placeholder first entry of the new chunk with `(F80000, ENDSKIP)` to mirror the original scantable's self-skip.
5. `STSTART` := absolute address of the new chunk in ROM.
6. Locate the original 28-byte scantable inside exec.library; `FIND` holds its address.
7. `find $exec.library $FIND`: look inside exec.library's code for the pointer that *references* the original scantable.  The match address replaces `FIND`.
8. `patch $FIND $STSTART`: rewrite that pointer to reference the new chunk instead.

Result: exec.library's embedded 28-byte scantable becomes unreferenced dead bytes; Exec follows the redirected pointer to the new chunk and walks the four-pair list there, which includes the E0 entry.

Functionally identical to pattern A. Structural difference: the new chunk lives **after** exec.library and adds ~32 bytes to the F8 image. Every module placed after exec.library shifts by that much.

### Pattern C: 3.1 chunk + LEA-opcode redirect

3.1 exec.library has a shorter (24-byte / 3-pair) embedded scantable:

```
pair 0: (F80000, 1000000)  entire F8 ROM bank (512 KB).
pair 1: (F00000, F80000)   F0 area.
        FFFFFFFF           terminator.
```

There is no redundant self-skip pair to recycle, so pattern A's "rewrite in place" trick is not available: inserting an E0 entry would have to grow the table and shift the rest of exec.library. And 3.1 exec.library reaches the scantable via two PC-relative `LEA X(PC),A0` opcodes rather than an indirected pointer value, so pattern B's "patch the pointer" does not apply either. The 3.1 build instead patches the **two LEA opcodes' 16-bit PC-relative displacements** to point at a newly added chunk that contains the four-entry layout.

```
add "$SOURCEROM" exec.library
add "Components/BinaryChunks/1Mb_Scantable.bin"
find $exec.library 0x00F800000100000000F0000000F80000FFFFFFFF
var FIND add $ROMBASE
var FIND mid 4
var OPCODE "LEA $FIND(PC),A0"
findopcode $exec.library "$OPCODE"
var FIND add 2
var REL $1Mb_Scantable.bin.(START)
var REL subtract $FIND
var REL mid 6
patch $FIND 0x$REL
findopcode $exec.library "$OPCODE"
var FIND add 2
var REL $1Mb_Scantable.bin.(START)
var REL subtract $FIND
var REL mid 6
patch $FIND 0x$REL
```

What each step does:

1. `add "$SOURCEROM" exec.library` then `add Components/BinaryChunks/1Mb_Scantable.bin`: embed exec.library and append the pre-built 3.1 scantable chunk (the `.bin` variant, distinct from 3.2.x's `1Mb_Scantable.3.2.bin`). The chunk already contains `(F80000,1000000)(E00000,E80000)(F00000,F80000)FFFFFFFF`.
2. `find $exec.library 0x...FFFFFFFF`: locate the 24-byte default scantable inside exec.library. `FIND` := its offset.
3. `var FIND add $ROMBASE`: absolute address `0x00F8XXXX` of the original scantable.
4. `var FIND mid 4`: keep only the low 16 bits, this is the displacement value the LEA opcodes encode.
5. `var OPCODE "LEA $FIND(PC),A0"`: build the 4-byte 68k opcode that loads exactly that address into A0. This is the byte pattern to find inside exec.library's code.
6. First `findopcode + patch` block: locate the first LEA reference (`FIND` becomes its offset), step past the 2-byte opcode word with `var FIND add 2`, compute the new PC-relative displacement `REL := chunk_start - FIND`, keep its low 24 bits with `mid 6`, and `patch $FIND 0x$REL` rewrites the displacement.
7. Second `findopcode + patch` block: same as #6 for the second LEA reference, 3.1 exec.library loads the scantable address from two different places.

Result: both LEA opcodes now address the new chunk. Exec walks the chunk's four-entry list, including the E0 range. exec.library's original 24-byte scantable becomes unreferenced dead bytes. Like pattern B, the new chunk lives after exec.library and shifts every subsequent F8 module's offset by its size.

### Trade-off: ACA1260/1240 cold boot

**ACA1260/1240** has been observed to hang at cold boot with **pattern B** when no internal IDE is attached. Pattern A boots in the same configuration. The cause is unknown.

For ROMs targeted at that hardware, prefer pattern A.


## Quick reference

### Pattern A / B / C recommendations

| AmigaOS | Use case | Recommended scantable pattern |
|---|---|---|
| 3.2.y | 1 MB ROM targeted at FS-UAE | A or B (both fine) |
| 3.2.y | 1 MB ROM targeted at stock A1200 (no accelerator) | A or B (both fine) |
| 3.2.y | 1 MB ROM targeted at ACA1234/1221lc | A or B (both fine) |
| 3.2.y | 1 MB ROM targeted at ACA1240/1260  | A (only) |
| 3.2.y | 1 MB ROM with unknown hardware mix | A  |
| 3.1 | 1 MB ROM (any target) | C |

### Extracting a runnable script from a Capitoline `.test` reference

Capitoline ships reference scripts as INI envelopes under `Capitoline Hashes/Tests/`. The runnable capcli script lives inside the `Text=...` field of the `[Description]` section, with `<br>` used
as the line separator. To extract use shell/python script:

```sh
#!/bin/bash
TEST=${1:-'/opt/Capitoline/Capitoline Hashes/Tests/0xe438d737.Hyperion.3.2.2.1Mb.A4000.test'}

python3 - "$TEST" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='latin1').read()
body = re.search(r'^Text=(.*?)(?:\n[A-Z][a-zA-Z]*=|\Z)', text, re.M | re.S).group(1)
print(body.replace('<br>', '\n'))
PY
```
