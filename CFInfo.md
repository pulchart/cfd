# CFInfo - CompactFlash Card Information Tool

CFInfo displays detailed information about CF cards in the PCMCIA slot using the `compactflash.device` driver.

**Requires:** compactflash.device v1.36+

## Usage

```
CFInfo          ; Show info for unit 0
CFInfo 1        ; Show info for unit 1
```

## Example Output

```
CFInfo 1.36 (02.01.2026) - CompactFlash Card Information
Device:     compactflash.device unit 0

=== CompactFlash Card Information ===

Model:      TS16GCF133
Serial:     G64126022013C4120210
Firmware:   20180926

=== Capacity ===

Size:       15.2 GB (31522736 sectors)
Geometry:   30401 cyl, 16 heads, 63 sectors/track

=== Capabilities ===

LBA:        Yes
DMA:        No
PIO Modes:  0, 1, 2, 3, 4
Multi-sect: Max 1 sectors/interrupt

=== Card Type ===

Removable:  Yes
Type:       CompactFlash

=== Features (SET FEATURES capable) ===
                   Supported  Enabled
Write Cache:       Yes        No
Read Look-ahead:   Yes        Yes
Power Management:  Yes        No

=== CF True IDE Timing (Word 163) ===
PIO (no IORDY): max=4 (120ns cycle)
PIO (IORDY):    max=4 (120ns cycle)
Multiword DMA:  max=2

=== CF PCMCIA Timing (Word 164) ===
Memory Mode:  max=3 (100ns), current=0 (600ns)
I/O Mode:     max=3 (100ns), current=0 (600ns)
```

## Field Reference

### Basic Information

| Field | Source | Description |
|-------|--------|-------------|
| Model | Words 27-46 | Card model name (40 chars) |
| Serial | Words 10-19 | Serial number (20 chars) |
| Firmware | Words 23-26 | Firmware revision (8 chars) |

### Capacity

| Field | Source | Description |
|-------|--------|-------------|
| Size | Words 60-61 | Total LBA sectors |
| Geometry | Words 1, 3, 6 | Cylinders, heads, sectors/track |

### Capabilities

| Field | Source | Description |
|-------|--------|-------------|
| LBA | Word 49, bit 9 | Logical Block Addressing support |
| DMA | Word 49, bit 8 | DMA transfer support |
| PIO Modes | Word 51, 64 | Supported PIO modes (0-4) |
| Multi-sect | Word 47 | Max sectors per READ/WRITE MULTIPLE |

### Card Type

| Field | Value | Description |
|-------|-------|-------------|
| Removable | Yes | CF cards, MicroDrives (bit 7 of Word 0) |
| Removable | No | Fixed drives (rare via PCMCIA) |
| Type | CompactFlash | Word 0 = 0x848x (CF signature) |
| Type | ATA | Word 0 bit 15 = 0 (some SD adapters) |
| Type | ATAPI | Word 0 bit 15 = 1 (optical drives) |

## SET FEATURES Capable

Features that can be enabled/disabled using ATA SET FEATURES command (0xEF):

| Feature | Subcommand | Description |
|---------|------------|-------------|
| Write Cache | 0x02 / 0x82 | Enable/disable write caching |
| Read Look-ahead | 0xAA / 0x55 | Enable/disable read prefetch |
| Power Management | 0x05 / 0x85 | Enable/disable power management |
| APM | 0x05 (subcode) | Advanced Power Management level |
| PUIS | 0x09 / 0x89 | Power-Up In Standby |
| Security Mode | - | ATA Security (password protection) |
| SMART | - | Self-Monitoring Analysis |
| 48-bit LBA | - | Support for drives >128GB |
| Write FUA | - | Force Unit Access (bypass cache) |
| CFA Features | - | CompactFlash Association extensions |

## CF True IDE Timing (Word 163)

PIO timing modes for True IDE interface:

| Mode | Cycle Time | Description |
|------|------------|-------------|
| 0 | 600ns | Default, slowest |
| 1 | 383ns | |
| 2 | 240ns | Standard ATA PIO 2 |
| 3 | 180ns | ATA PIO 3 |
| 4 | 120ns | ATA PIO 4, fast |
| 5 | 100ns | CF-specific, very fast |
| 6 | 80ns | CF-specific, ultra fast |

**Fields:**
- **PIO (no IORDY)**: Maximum PIO mode without flow control
- **PIO (IORDY)**: Maximum PIO mode with IORDY flow control
- **Multiword DMA**: Maximum Multiword DMA mode (0-2)

## CF PCMCIA Timing (Word 164)

PCMCIA memory and I/O timing modes (what Amiga Gayle chip controls):

| Mode | Cycle Time | Gayle Support |
|------|------------|---------------|
| 0 | 600ns | Yes (720ns closest) |
| 1 | 250ns | Yes |
| 2 | 150ns | Yes |
| 3 | 100ns | Yes (fastest Gayle) |
| 4 | 80ns | No (too fast for Gayle) |
| 5 | 50ns | No (too fast for Gayle) |
| 6-7 | ? | Vendor-specific/reserved |

**Fields:**
- **Memory Mode max**: Fastest memory timing card supports
- **Memory Mode current**: Currently configured memory timing
- **I/O Mode max**: Fastest I/O timing card supports
- **I/O Mode current**: Currently configured I/O timing

**Note:** If `current < max`, the card could potentially run faster if the host (Gayle) supports it. The experimental `FASTPIO=1` compile option attempts to optimize this.

## Technical Notes

### ATA IDENTIFY Command

CFInfo uses a vendor-specific SCSI passthrough (command 0xEC) added in v1.36 to retrieve the cached ATA IDENTIFY data from the driver.

### Word 0 (General Configuration)

```
Bit 15:    0 = ATA device, 1 = ATAPI device
Bit 7:     1 = Removable media
Bits 15-8: 0x84 = CompactFlash signature (0x848x)
```

### Gayle PCMCIA Timing Register ($DAB000)

The Amiga Gayle chip controls PCMCIA timing via register $DAB000, bits 2-3:

| Bits | Speed |
|------|-------|
| 00 | 250ns |
| 01 | 150ns |
| 10 | 100ns |
| 11 | 720ns |
