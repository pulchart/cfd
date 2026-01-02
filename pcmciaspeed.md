# pcmciaspeed

PCMCIA Memory Access Timing Benchmark tool.

## Usage

```
pcmciaspeed          ; Display on screen
pcmciaspeed >SER:    ; Send output to serial port
```

No arguments required. The tool measures memory access timing at different Gayle speed settings.

## Example Output

```
PCMCIA Memory Access Timing Benchmark
=====================================

Chip RAM: 672 ns

               Gayle timing (access time in ns)
Memory Type    250ns   150ns   100ns   720ns
-------------- ------  ------  ------  ------
Common $600k     708     707     379    1130
Common $601k     708     708     378    1130
Attrib $A00k     848     848     870    1130
Attrib $A01k     848     869     848    1131

Notes:
- Common Memory: Used for data transfer (disk I/O)
- Attrib Memory: Card configuration (CIS tuples)
```

## Understanding the Output

### Chip RAM vs PCMCIA

These are **independent measurements, NOT additive**.

| Measurement | What it measures | Path |
|-------------|------------------|------|
| **Chip RAM** | CPU → Amiga bus → Chip RAM | Contended with custom chips (DMA) |
| **PCMCIA** | CPU → Gayle → PCMCIA slot → CF card | Separate path through Gayle |

### Gayle Timing Settings

The column headers (250ns, 150ns, 100ns, 720ns) are the Gayle PCMCIA memory timing settings controlled via register `$DAB000` bits 2-3:

| Bits 2-3 | Speed |
|----------|-------|
| 10 | 100ns |
| 01 | 150ns |
| 00 | 250ns |
| 11 | 720ns |

### Memory Types

| Memory Type | Address | Purpose |
|-------------|---------|---------|
| **Common** | $600000 | Main data area - used for disk I/O |
| **Attrib** | $A00000 | Card configuration (CIS tuples) |

The tool tests at base address and +$1000 offset to verify consistent timing.

### Interpreting Results

```
Chip RAM: 672ns       ← System baseline memory speed
PCMCIA @ 100ns: 378ns ← Fastest CF access
PCMCIA @ 720ns: 1130ns ← Slowest setting
```

## Measurement Method

- Uses `timer.device` ECLOCK for precise timing
- Performs 500 iterations × 8 reads per test
- Calculates nanoseconds per memory access
