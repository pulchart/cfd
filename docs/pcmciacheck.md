# pcmciacheck - PCMCIA/CF Hardware Test Tool

## Overview

`pcmciacheck` is a diagnostic tool for testing PCMCIA CompactFlash card compatibility with Amiga systems. It tests the same read/write modes used by the `compactflash.device` driver to determine which data access modes work correctly with your CF card, helping identify potential compatibility issues before using the card with the `compactflash.device` driver.

- **Multiple Access Mode Testing**: Tests 5 different read modes and 5 write modes (including memory-mapped)
- **IDENTIFY Read Stability**: Reads the same sector several times per mode and compares the results, the check the driver applies before it accepts a card
- **Pattern-Based Compatibility Testing**: Mirrors the `cfd.s` driver's RWTest functionality  
- **Safe Operation**: Write testing requires explicit `-w` flag to prevent accidental data loss
- **Detailed Progress Reporting**: Real-time status output suitable for serial redirection
- **IFF Log Format**: Creates structured log files for analysis
- **Hardware Detection**: Automatic card presence detection and timeout handling

## Usage

```
pcmciacheck [-w] [-s <speed>] <logfile>
pcmciacheck -identify [speed] [-r <runs>]
pcmciacheck -cis [speed]
```

The tool has three modes. The default run exercises the transfer modes
and writes an IFF log. `-identify` and `-cis` are focused checks that
print to the console and write nothing.

Options:
- **`<logfile>`**: Output file for test results (IFF format)
- **`-w`**: Enable write testing (WARNING: overwrites sectors 1-5 on the CF card)
- **`-s <speed>`**: Gayle PCMCIA timing to use for the run, `100`, `150`,
  `250` or `720` nanoseconds, or `all` to repeat the capture at each of them
  and log every timing. Cannot be combined with `-w`. The previous setting is
  restored on exit. See
  [Trying other Gayle timings](#trying-other-gayle-timings).
- **`-identify [speed] [-r <runs>]`**: Read IDENTIFY several times per mode
  and compare the blocks, the check the driver makes before it accepts a
  card. Console only. The optional speed is `100`, `150`, `250`, `720`, or
  `all` to test at each of them and print a matrix. `-r` sets the runs per
  mode, 2 to 32, default 5. See
  [Checking data path read stability](#checking-data-path-read-stability).
- **`-cis [speed]`**: Dump the PCMCIA Card Information Structure (CIS) tuples from
  attribute memory and exit. Read-only, does not use `card.resource` or
  `compactflash.device`, so it can be used to inspect cards that hang the
  regular driver path. The optional `speed` is `100`, `150`, `250` or `720`
  and overrides the Gayle PCMCIA memory timing for the duration of the scan
  only; the previous setting is restored on exit. Without it the current
  setting is used.

Examples:

**Read-only testing (safe):**
```
pcmciacheck RAM:test.log
```

**Full testing with write verification:**
```
pcmciacheck -w RAM:test.log
```

**Serial output redirection:**
```
pcmciacheck -w >SER: RAM:test.log
```

**Dump CIS tuples (no driver interaction):**
```
pcmciacheck -cis
pcmciacheck -cis >RAM:card.cis
```

The CIS dump decodes the common tuples (`CISTPL_DEVICE`, `CISTPL_FUNCID`,
`CISTPL_FUNCE`, `CISTPL_VERS_1`, `CISTPL_MANFID`, ...) and hex-dumps any
others. Useful for diagnosing cards that the driver mis-identifies, or
that cause the driver's probe path to hang.

Sample `CISTPL_DEVICE` decode:

```
0x000: 0x01 CISTPL_DEVICE (length=4)
    type=0xD (FUNCSPEC), wps=1, speed=0x1 (250ns)
    size=0x00000800 (2048 B), size_code=0x01  (units=1, unit=0x1=2K)
```

The device-info byte carries the device type in bits 7-4, the
write-protect-switch flag in bit 3, and the speed in bits 2-0. Speed
code `0x7` means the real access time is in one or more extended speed
bytes that sit between the device-info byte and the size byte, so those
cards decode like this:

```
0x000: 0x01 CISTPL_DEVICE (length=4)
    type=0xD (FUNCSPEC), wps=1, speed=0x7 (extended)
    ext-speed=0x4A (400 ns)
    size=0x00000800 (2048 B), size_code=0x01  (units=1, unit=0x1=2K)
```

The `size=` line is the decoded byte count (units * unit-size); it
matches the value the OS `DeviceTuple` call stores in cfd's
`CFU_DTSize`. `size_code` is the raw CIS byte for cross-reference.

`CISTPL_DEVICE_OC` describes the same device under other operating
conditions and starts with an extra "other conditions" byte, which is
reported separately before the device info:

```
0x006: 0x1C CISTPL_DEVICE_OC (length=4)
    other-cond=0x02 (Vcc=X.XV, mwait=0)
    type=0xD (FUNCSPEC), wps=1, speed=0x1 (250ns)
    size=0x00000800 (2048 B), size_code=0x01  (units=1, unit=0x1=2K)
```


## Checking CIS read stability

CIS is static data in the card's attribute memory, so running
`pcmciacheck -cis` several times in succession (without removing or
re-inserting the card) should produce **byte-for-byte identical
output every time**. If consecutive runs disagree, the PCMCIA
attribute-memory read path is producing random bit-flips, and the
driver's CIS gate may reject the card on a corrupted run even though
its I/O path is unaffected.

Observed so far on the **A1200 + ACA1234** combination with certain
CF cards (notably Transcend TS4GCF133 with manfid=0x004F). Bare A1200
and ACA1240 / ACA1260 on the same card are unaffected. Gayle's PCMCIA
memory-speed register (`$DAB000` bits 2-3) does not remediate this:
100ns, 150ns, 250ns, and 720ns all produce the same instability.

**Stable run** (a healthy reading; every run looks like this):

```
0x017: 0x15 CISTPL_VERS_1 (length=24)
    major=4, minor=1
    string[0]: "TRANSCEND"
    string[1]: "TS4GCF133"
0x031: 0x21 CISTPL_FUNCID (length=2)
    function=0x04 (FIXED_DISK)
    sysinit=0x01
0x035: 0x22 CISTPL_FUNCE (FUNCEXT) (length=2)
    extension_type=0x01 (Disk Interface), interface=0x01 (IDE)
```

**Unstable runs** (same card, same insertion; three further
consecutive runs, excerpts showing the kind of corruption seen):

FUNCID length byte flipped (0x02 to 0x00), making the parser walk
into the data and treat the next bytes as fresh tuple codes:

```
0x031: 0x21 CISTPL_FUNCID (length=0)
0x033: 0x04 (unknown) (length=1)
    data: 22
0x036: 0x02 (unknown) (length=1)
    data: 01
```

VERS_1 strings garbled by random bit flips:

```
0x017: 0x15 CISTPL_VERS_1 (length=24)
    major=0, minor=1
    string[0]: "TPA@S@E@D"
    string[1]: "T"
    string[2]: "4GCF133"
```

FUNCEXT interface byte flipped from IDE (0x01) to undefined (0x00),
which is enough to make a strict CIS gate refuse the card:

```
0x035: 0x22 CISTPL_FUNCE (FUNCEXT) (length=2)
    extension_type=0x01 (Disk Interface), interface=0x00 ((undefined))
```

When opening an issue about a card that the driver mis-identifies or
rejects, capture and attach **several `-cis` runs back-to-back** so
the failure mode is visible. A single dump cannot distinguish "card's
CIS is genuinely malformed" from "attribute-memory reads are unstable
on this host"; the multi-run capture can.

## Checking data path read stability

The read-mode test only tells you that the PCMCIA path works at all: the
card accepted IDENTIFY and a block came back. It does not look at the
content. A card can pass every read mode and still hand over different
bytes on every read, and that is what corrupts filesystems.

IDENTIFY is static data on the card, so reading it repeatedly through the
same mode has to return the same bytes every time. That is what
`-identify` does, `-r <runs>` times per mode, comparing the blocks:

```
pcmciacheck -identify
pcmciacheck -identify -r 20
pcmciacheck -identify 720
pcmciacheck -identify all
```

It is its own mode rather than part of the default run because it is the
check worth repeating on a suspect card, and raising the run count or
trying another timing should not mean sitting through the read-mode,
pattern and write tests again. Nothing is written to disk.

The test reports the same two failures the driver rejects a card for:

```
[CFD] Getting IDE ID ... FAILED (repeated pattern 8A84)
[CFD] Getting IDE ID ... FAILED (data mismatch)
```

A healthy card:

```
Testing IDENTIFY read stability (5 runs per mode)...
  mode 0 (word +8           ) STABLE    5/5 identical, xor 3C11, 0 repeated word(s)
  mode 1 (word +8 stride 16 ) STABLE    5/5 identical, xor 3C11, 0 repeated word(s)
  mode 2 (byte +8 / +8 odd  ) STABLE    5/5 identical, xor 3C11, 0 repeated word(s)
  mode 3 (word +8 read-twice) STABLE    5/5 identical, xor 3C11, 0 repeated word(s)
  mode 4 (MMAP word         ) STABLE    5/5 identical, xor 3C11, 0 repeated word(s)
  Driver uses mode 0: stable
```

### Only the driver's own mode decides

The driver tries read modes 0, 1, 2 and 3 in order and falls back to
mode 4 last, so it uses the first one that works. A mode further down
that list is never reached once an earlier one works, and a failure
there says nothing about the card.

The report therefore names the mode the driver would use and judges the
card on that one alone:

```
  mode 4 (MMAP word         ) NOT USABLE (all zeros, nothing was read)
  Driver uses mode 0: stable
  1 other mode(s) are not usable here, which does not
  affect the card: the driver never falls back to them.
```

That is a working card. It is common for read mode 4 to be unusable,
since memory-mapped access is not wired up the same way on every
adapter.

A block that comes back entirely zero is reported as `NOT USABLE (all
zeros)` rather than as a repeated pattern: nothing arrived at all, which
is a different fault from a port latched at a value. The driver does not
draw that distinction, its own check would call an all-zero block a
repeated pattern, but the driver is judging a card while this line is
describing one mode.

A stuck data port, returning one word for every read:

```
  mode 0 (word +8           ) STUCK     repeated pattern 0x8A84 (ATA 0x848A), 255 repeated word(s)
  Driver uses mode 0: NOT stable
  The card is not readable in this setup; the driver
  rejects it with "FAILED (repeated pattern)".
```

Repeating the read cannot find this on its own, because a stuck port is
perfectly repeatable: five reads give five identical blocks. It is
therefore checked separately, and before the comparison, in the same
order the driver checks it. The `xor 0000` such a card produces is a
giveaway as well, since a block of identical words folds to zero.

An unstable data path:

```
  mode 0 (word +8           ) UNSTABLE
     5/5 read, 1/5 identical, 5 distinct checksum(s)
     first difference at word 1, up to 126 of 256 words differ
     33 repeated word(s) in the reference block
     xor: 6D97 3C11 7F3F 0ED5 F396
```

How to read that:

- **identical** is the verdict. Anything below the full run count means
  the same sector read back differently, so the data path is losing
  integrity.
- **distinct checksum(s)** is the number of different XOR folds seen. It
  can under-count, since two different blocks can fold to the same
  value.
- **first difference at word N** is where the blocks start to diverge.
- **repeated word(s)** counts words equal to the one before them,
  ignoring the `0x0000` and `0x2020` padding. A high count means whole
  words are being repeated, which happens when the data port does not
  advance to the next word. This describes *how* the block is corrupted;
  it is not the verdict, because a healthy card can contain repeated
  words of its own.
- **repeated pattern 0xNNNN** is the stuck value as it was read from the
  port, the same number the driver prints. The value in brackets is the
  byte-swapped one, which is what the word means as ATA data.
- **xor** lists the per-run folds so they can be compared with the
  driver's own numbers.

A mode that is not usable at all reports `NO DATA`.

Errors are random by nature, so a clean result is not proof. Raise
`-r` and run the tool a few times before concluding a card is fine.

## Trying other Gayle timings

Both the default run and `-identify` accept a Gayle PCMCIA timing
(`$DAB000` bits 2-3) to use, and restore the previous setting on exit:
`-s <speed>` for the default run, a speed argument for `-identify`.

Both also accept `all`, and the two answer different questions:

| | what it gives you |
|---|---|
| `pcmciacheck -identify all` | the verdict per mode and timing, as a matrix on the console |
| `pcmciacheck -s all <logfile>` | the raw IDENTIFY blocks for every timing, in the log |

Use the first to see whether timing is the variable. Use the second when
the answer needs to be analysed later or attached to a bug report, since
the log then carries the actual bytes each mode returned at each timing,
not just a verdict. `-s all` cannot be combined with `-w`: rewriting
sectors 1 to 5 once per timing gains nothing, and the mode the read-back
uses can differ between timings.

`-identify all` runs the stability test at each of the four timings and
prints a matrix:

```
pcmciacheck -identify all

Testing IDENTIFY read stability at each Gayle timing (5 runs per mode)...
          100ns   150ns   250ns   720ns
  mode 0  UNSTAB  UNSTAB  UNSTAB  STABLE  <- driver uses this
  mode 1  UNSTAB  UNSTAB  UNSTAB  STABLE
  mode 2  STABLE  STABLE  STABLE  STABLE
  mode 3  UNSTAB  UNSTAB  UNSTAB  STABLE
  mode 4  ZEROS   ZEROS   ZEROS   ZEROS
  Gayle timing restored to 250ns
  Mode 0 is stable only at: 720ns
  The card cannot follow the faster settings. Note the
  driver programs the timing itself, this cannot pin it.
```

The verdicts are abbreviated so the columns line up: `STABLE`, `UNSTAB`,
`STUCK`, `ZEROS`, `NODATA`. The modes are the ones listed under
[Read Mode Results](#read-mode-results).

A card that becomes stable at a slower timing is being driven faster
than it can follow. A matrix where every column reads the same says
timing is not the variable, which is just as useful to know. As in the
single-run report, only the driver's own row decides the verdict.

Two things to keep in mind:

- **This is a diagnostic, not a fix.** The driver programs the same
  register itself through `card.resource`, so an override here lasts
  only while `pcmciacheck` runs. A card that only works at 720ns in this
  test will not thereby work under the driver.
- **`$DAB000` is documented as the PCMCIA *memory* timing**, and read
  modes 0 to 3 use I/O space. It is possible for those rows not to move
  at all across the sweep. Read mode 4 uses common memory and is the one
  most likely to respond.

A sweep issues four times as many IDENTIFY commands as a normal run, so
lower `-r` if it takes too long. Past experience is mixed: the CIS
instability documented above was not remediated by any of the four
settings.

## Test Results Interpretation

### Read Mode Results

The tool tests the driver's 5 read modes, so a mode number here means the
same thing as the mode the driver reports in its `transfer mode:` line:

| Mode | Access |
|------|--------|
| 0 | word reads from the data port |
| 1 | word reads walking the register aliases |
| 2 | byte reads alternating the data port and its odd-byte alias |
| 3 | word reads, two per stored word, the second discarded |
| 4 (MMAP) | word reads from PCMCIA common memory |

Mode 3 exists for adapters whose data port hands out every word twice.
Mode 4 switches the card to memory-mapped configuration for the transfer
and restores the previous configuration afterwards.

Each mode reads the whole 512-byte block in one transfer, as the driver
does.

**Result Types:**
- **OK (512 bytes)**: IDENTIFY data read
- **NO DATA (timeout or DRQ never set)**: the card did not deliver a block in this mode
- **repeated pattern 0xNNNN**: the block is one word repeated, so the data
  port is stuck
- **no data (all zeros)**: a block arrived but every word is zero, so
  nothing was actually read
- **WARNING: multi-sector issue detected**: DRQ was still asserted after a
  full 512-byte IDENTIFY, so the card wants to hand over more than one
  sector. Not reported for a stuck or empty block, where the status
  register is as unreliable as the data.

Neither a stuck nor an empty block is chosen as the working read mode,
because the write test reads back through it, and if no mode delivers
plausible data the tool says so.

### Pattern Test Results

The pattern test returns a 16-bit hexadecimal value representing working write/read mode combinations:

```
Pattern test modes: 0xBBBB
```

Each bit represents a write/read mode combination:
- Bit position = (write_mode × 4) + read_mode
- 1 = working combination, 0 = failed combination

**Example Interpretation:**
`0xBBBB` = `1011 1011 1011 1011` binary means:
- Most combinations work except read mode 2 (alternating byte access)
- This is a common hardware limitation on some CF cards

Each combination is tried twice and has to work both times to be
reported as working, the same rule the driver applies.

### Write Mode Results (with -w flag)

Shows bytes successfully written per mode:

```
Testing write mode 0 (sector 1)... 512 bytes
Testing write mode 1 (sector 2)... 512 bytes
```

Write modes 0 to 3 write one sector each at LBA 1 to 4, write mode 4
(MMAP) writes LBA 5. Write modes 1 and 3 use the same access pattern, as
they do in the driver, so their results are identical.

The read-back then compares each sector against the pattern the write
test put there and reports how many bytes differ:

```
    Sector 1 read... OK, data matches
    Sector 2 read... MISMATCH, 37 of 512 bytes differ
```

A sector whose write did not take the full 512 bytes is reported as
`not verified`, because its expected content is undefined.

## Output Examples

### Successful Test Run (Normal Card)

```
pcmciacheck 2.0 - Testing card...
Testing read modes...
  Testing read mode 0 (word +8)... OK (512 bytes)
  Testing read mode 1 (word +8 stride 16)... OK (512 bytes)
  Testing read mode 2 (byte +8 / +8 odd)... OK (512 bytes)
  Testing read mode 3 (word +8 read-twice)... OK (512 bytes)
  Testing read mode 4 (MMAP word)... OK (512 bytes)
  Working read mode: 0
Testing transfer mode patterns (cfd.s style)...
  Pattern test modes: 0xBBBB
Write testing disabled (use -w to enable)
Restoring card configuration...
Saving log file...
Log saved: RAM:test.log (2742 bytes)
Test completed successfully.
```

### Unstable Data Path

The card below passes every read mode and still fails, because no two
reads of the same sector agree. This is the case the driver rejects, and
it takes `-identify` to see it.

```
pcmciacheck -identify

pcmciacheck 2.0 - IDENTIFY read stability
Gayle PCMCIA timing: 250ns (current)
Testing IDENTIFY read stability (5 runs per mode)...
  mode 0 (word +8           ) UNSTABLE
     5/5 read, 1/5 identical, 5 distinct checksum(s)
     first difference at word 1, up to 126 of 256 words differ
     33 repeated word(s) in the reference block
     xor: 6D97 3C11 7F3F 0ED5 F396
  mode 1 (word +8 stride 16 ) UNSTABLE
     ...
  mode 4 (MMAP word         ) UNSTABLE
     5/5 read, 1/5 identical, 5 distinct checksum(s)
     first difference at word 1, up to 89 of 256 words differ
     19 repeated word(s) in the reference block
     xor: 6A0E BBEC FADF C5E8 898C
  Driver uses mode 0: NOT stable
  The card's data path is not bit-stable in this setup;
  the driver rejects it with "FAILED (data mismatch)".
```

### Multi-Sector Issue Detection

```
pcmciacheck 2.0 - Testing card...
Testing read modes...
  Testing read mode 0 (word +8)... OK (512 bytes) - WARNING: multi-sector issue detected
  Testing read mode 4 (MMAP word)... OK (512 bytes)
  Working read mode: 0
Testing transfer mode patterns (cfd.s style)...
  Pattern test modes: 0xBBBB
Testing write modes...
  Reading back 4 sectors for verification...
    Sector 1 read... OK, data matches
    Sector 2 read... OK, data matches
    Sector 3 read... OK, data matches
    Sector 4 read... OK, data matches
  WARNING: Multi-sector read issue detected (DRQ still set after 4 sectors)
  Verification completed (4 sectors, 8 chunks)
Write testing completed.
Log saved: RAM:test.log (4790 bytes)
Test completed successfully.
```

### Error Conditions

- **"No card inserted"**: PCMCIA card not detected
- **"Cannot open timer.device"**: System resource issue
- **"Cannot allocate memory"**: Insufficient RAM
- **"TIMEOUT"**: Card not responding to commands

## Log File Format

The tool creates IFF-format log files with the following chunks:

- **FORM/pcc3**: Main container
- **gspd**: Gayle timing this group used, two big-endian words: the speed in
  nanoseconds, and 1 when `-s` chose it or 0 when it is the system's own
  setting
- **rdc0-rdc4**: IDENTIFY data for each read mode, 512 bytes each, or empty when the mode returned nothing
- **ptst**: Pattern test results (2 bytes)
- **wcln**: Write byte counts (20 bytes, 5 modes x 4, with -w flag)
- **wcda**: Write read-back data (with -w flag)

`gspd` starts a timing group: everything up to the next `gspd` was
captured at the timing it names. A normal run writes one group, about
2.6 KB. `-s all` writes four, one per timing, about 10.5 KB, so a reader
walking the chunks in order sees `gspd rdc0..rdc4 ptst` four times.

`-identify` and `-cis` write no log at all, they only print.

The container type is `pcc3` because the read modes now mirror the
driver's transfer modes. Per-mode blocks in a `pcc2` log came from
different register addresses and are not comparable with these.

## Serial Line Usage

For remote monitoring or headless systems, redirect output to serial:

```
pcmciacheck -w >SER: RAM:test.log
```

The progress output uses `\r\n` line endings and structured formatting optimized for serial terminals.

## Technical Details

### Hardware Registers

- **Gayle Controller**: 0x00DA8000 (card detection)
- **PCMCIA Config**: 0x00A00200 (I/O mode control)
- **IDE Base**: 0x00A20000 (ATA register access)

### Test Methodology

The tool implements the same transfer mode detection algorithm used by the `compactflash.device` driver:

1. **IDENTIFY Command**: Tests basic card communication
2. **Pattern Testing**: Validates read/write mode combinations
3. **Sector Verification**: Confirms write operations (with -w flag)

## Troubleshooting

### pcmciacheck says the modes are OK but the driver rejects the card

The two verdicts cover different things, so they can both be right.

`read mode ... OK` means only that the PCMCIA path works and a block
arrived. It says nothing about whether the bytes are correct.

The driver additionally checks the content. It refuses a card whose data
port returns one word over and over

```
[CFD] Getting IDE ID ... FAILED (repeated pattern 8A84)
```

and one whose repeated reads of the same sector disagree

```
[CFD] Getting IDE ID ... FAILED (data mismatch)
```

because random bit errors on the data path corrupt files just as
happily as they corrupt IDENTIFY.

Run `-identify` to see the same thing the driver sees, and raise `-r` if
nothing shows up on the first attempt:

```
pcmciacheck -identify
pcmciacheck -identify -r 20
```

If the mode the driver uses reports `STUCK` or `UNSTABLE`, the driver's
rejection is correct and the card is not safe to mount in that machine.
A failure in one of the other modes does not condemn the card, because
the driver never falls back to them.

If the driver's mode is `STABLE` across repeated invocations and the
driver still rejects the card, that is worth reporting as an issue, with
the console output attached.

Note that repeated `-cis` dumps test the attribute-memory read path,
which is separate from the data path. A stable CIS does not imply a
stable data path.

### Multi-Sector Read Issues

**Identification:** 
- Displays "(DRQ still set - multi-sector issue)" message
- Verification phase shows multi-sector read warning

**Root Cause:** Issue addressed by driver v1.34+ multi-sector read fixes. Cards incorrectly keep DRQ asserted after multi-sector read commands.

**Solutions:**
- **Recommended:** Use driver v1.34+ which properly handles this issue
- **Avoid:** Do NOT use `Flags = 16` in driver v1.35+ for these cards (multi-sector override)
- **Configuration:** See README.md "Enforce Multi Mode" section for detailed workarounds
