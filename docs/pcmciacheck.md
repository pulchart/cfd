# pcmciacheck - PCMCIA/CF Hardware Test Tool

## Overview

`pcmciacheck` is a diagnostic tool for testing PCMCIA CompactFlash card compatibility with Amiga systems. It tests the same read/write modes used by the `compactflash.device` driver to determine which data access modes work correctly with your CF card, helping identify potential compatibility issues before using the card with the `compactflash.device` driver.

- **Multiple Access Mode Testing**: Tests 5 different read modes and 5 write modes (including memory-mapped)
- **Pattern-Based Compatibility Testing**: Mirrors the `cfd.s` driver's RWTest functionality  
- **Safe Operation**: Write testing requires explicit `-w` flag to prevent accidental data loss
- **Detailed Progress Reporting**: Real-time status output suitable for serial redirection
- **IFF Log Format**: Creates structured log files for analysis
- **Hardware Detection**: Automatic card presence detection and timeout handling

## Usage

```
pcmciacheck [-w] <logfile>
```

Options:
- **`<logfile>`**: Output file for test results (IFF format)
- **`-w`**: Enable write testing (WARNING: overwrites sectors 1-4 on the CF card)

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

## Test Results Interpretation

### Read Mode Results

The tool tests 5 different read access modes:

- **Mode 0**: Word access (16-bit reads via I/O space)
- **Mode 1**: Sequential byte access  
- **Mode 2**: Alternating byte access
- **Mode 3**: Offset byte access
- **Mode 4 (MMAP)**: Memory mapped word access (uses PCMCIA common memory)

Mode 4 uses a different PCMCIA configuration (memory-mapped instead of I/O) and is tested separately from modes 0-3.

**Result Types:**
- **OK (512 bytes)**: Full IDENTIFY data read successfully
- **PARTIAL (256 bytes)**: Only partial data read (indicates compatibility issues)
- **TIMEOUT**: Card not responding

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

### Write Mode Results (with -w flag)

Shows bytes successfully written per mode and verification results:

```
Testing write mode 0 (sector 1)... 512 bytes
Testing write mode 1 (sector 2)... 512 bytes
```

## Output Examples

### Successful Test Run (Normal Card)

```
pcmciacheck 1.36 - Testing card...
Testing read modes...
  Testing read mode 0... OK (512 bytes)
  Testing read mode 1... PARTIAL (256 bytes)  
  Testing read mode 2... PARTIAL (256 bytes)
  Testing read mode 3... PARTIAL (256 bytes)
  Working read mode: 0
Testing transfer mode patterns (cfd.s style)...
  Pattern test modes: 0xBBBB
Write testing disabled (use -w to enable)
Restoring card configuration...
Saving log file...
Log saved: RAM:test.log (1334 bytes)
Test completed successfully.
```

### Multi-Sector Issue Detection

```
pcmciacheck 1.36 - Testing card...
Testing read modes...
  Testing read mode 0... (DRQ still set - multi-sector issue) WARNING (512 bytes)
  Testing read mode 1... (DRQ still set - multi-sector issue) WARNING (512 bytes)
  Testing read mode 2... (DRQ still set - multi-sector issue) WARNING (512 bytes)
  Testing read mode 3... (DRQ still set - multi-sector issue) WARNING (512 bytes)
  Working read mode: 0
Testing transfer mode patterns (cfd.s style)...
  Pattern test modes: 0xBBBB
Testing write modes...
  Reading back 4 sectors for verification...
    Sector 1 read... OK
    Sector 2 read... OK
    Sector 3 read... OK
    Sector 4 read... OK
  WARNING: Multi-sector read issue detected (DRQ still set after 4 sectors)
  Verification completed (4 sectors, 8 chunks)
Write testing completed.
Log saved: RAM:test.log (4182 bytes)
Test completed successfully.
```

### Error Conditions

- **"No card inserted"**: PCMCIA card not detected
- **"Cannot open timer.device"**: System resource issue
- **"Cannot allocate memory"**: Insufficient RAM
- **"TIMEOUT"**: Card not responding to commands

## Log File Format

The tool creates IFF-format log files with the following chunks:

- **FORM/pcc2**: Main container
- **rdc0-rdc3**: IDENTIFY data for each read mode
- **ptst**: Pattern test results (2 bytes)
- **wcln**: Write byte counts (16 bytes, with -w flag)
- **wcda**: Write verification data (with -w flag)

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

### Multi-Sector Read Issues

**Identification:** 
- Displays "(DRQ still set - multi-sector issue)" message
- Verification phase shows multi-sector read warning

**Root Cause:** Issue addressed by driver v1.34+ multi-sector read fixes. Cards incorrectly keep DRQ asserted after multi-sector read commands.

**Solutions:**
- **Recommended:** Use driver v1.34+ which properly handles this issue
- **Avoid:** Do NOT use `Flags = 16` in driver v1.35+ for these cards (multi-sector override)
- **Configuration:** See README.md "Enforce Multi Mode" section for detailed workarounds
