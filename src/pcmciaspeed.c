/*
 * pcmciaspeed - PCMCIA Memory Access Timing Benchmark
 *
 * Measures memory access timing for Chip RAM and PCMCIA at different
 * Gayle speed settings.
 *
 * Inspired by original pcmciaspeed 1.00 (19.06.2002) by Torsten Jager
 *
 * Build: make pcmciaspeed (requires vbcc + NDK)
 * Usage: pcmciaspeed
 */

#include "common.h"

const char version[] = MAKE_VERSION_STRING("pcmciaspeed");

#include <exec/types.h>
#include <exec/memory.h>
#include <exec/io.h>
#include <devices/timer.h>
#include <hardware/cia.h>

#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/timer.h>

#include <stdio.h>

/* Gayle control register for PCMCIA timing */
#define GAYLE_CONTROL   0x00DAB000

/* PCMCIA memory window */
#define PCMCIA_ATTR     0x00A00000  /* Attribute memory */
#define PCMCIA_COMMON   0x00600000  /* Common memory */

/* Number of iterations for timing loop */
#define TIMING_LOOPS    500

/* Timer globals */
struct MsgPort *TimerPort = NULL;
struct timerequest *TimerReq = NULL;
struct Device *TimerBase = NULL;

/* Gayle speed bits to nanoseconds */
const char *speed_names[] = { "250", "150", "100", "720" };

int OpenTimer(void)
{
    TimerPort = CreateMsgPort();
    if (!TimerPort) return 0;

    TimerReq = (struct timerequest *)CreateIORequest(TimerPort, sizeof(struct timerequest));
    if (!TimerReq) {
        DeleteMsgPort(TimerPort);
        return 0;
    }

    if (OpenDevice("timer.device", UNIT_ECLOCK, (struct IORequest *)TimerReq, 0)) {
        DeleteIORequest((struct IORequest *)TimerReq);
        DeleteMsgPort(TimerPort);
        printf("Could not open timer.device\r\n");
        return 0;
    }

    TimerBase = TimerReq->tr_node.io_Device;
    return 1;
}

void CloseTimer(void)
{
    if (TimerReq) {
        CloseDevice((struct IORequest *)TimerReq);
        DeleteIORequest((struct IORequest *)TimerReq);
    }
    if (TimerPort) {
        DeleteMsgPort(TimerPort);
    }
}

/*
 * Measure memory access time in nanoseconds
 * Reads from the specified address TIMING_LOOPS times
 */
ULONG MeasureAccess(volatile UBYTE *addr)
{
    struct EClockVal start, end;
    ULONG freq;
    ULONG i;
    volatile UBYTE dummy;
    ULONG ticks;

    /* Get E-Clock frequency */
    freq = ReadEClock(&start);

    /* Timing loop */
    ReadEClock(&start);
    for (i = 0; i < TIMING_LOOPS; i++) {
        dummy = *addr;
        dummy = *addr;
        dummy = *addr;
        dummy = *addr;
        dummy = *addr;
        dummy = *addr;
        dummy = *addr;
        dummy = *addr;
    }
    ReadEClock(&end);

    /* Calculate elapsed ticks */
    ticks = end.ev_lo - start.ev_lo;

    /* Convert to nanoseconds per access */
    /* ns = (ticks * 1,000,000,000) / (freq * TIMING_LOOPS * 8) */
    /* Simplified to avoid overflow: */
    /* ns = (ticks * 1000) / (freq * TIMING_LOOPS * 8 / 1000000) */

    if (freq > 0 && ticks > 0) {
        /* E-Clock is typically ~709379 Hz on PAL, ~715909 on NTSC */
        /* Each tick is about 1.4 microseconds */
        ULONG total_accesses = TIMING_LOOPS * 8;
        ULONG ns_per_tick = 1000000000UL / freq;
        ULONG total_ns = ticks * ns_per_tick;
        return total_ns / total_accesses;
    }

    return 0;
}

/*
 * Test PCMCIA at all 4 Gayle speed settings
 */
void TestPCMCIA(const char *name, volatile UBYTE *base_addr)
{
    volatile UBYTE *gayle = (volatile UBYTE *)GAYLE_CONTROL;
    UBYTE orig_gayle;
    ULONG times[4];
    int speed;

    /* Gayle speed bits to register value mapping */
    /* bits 2-3: 00=250ns, 01=150ns, 10=100ns, 11=720ns */
    static const UBYTE speed_bits[4] = { 0, 4, 8, 12 };

    /* Save original Gayle setting */
    orig_gayle = *gayle;

    /* Test each speed setting */
    for (speed = 0; speed < 4; speed++) {
        UBYTE new_val = (orig_gayle & 0xF3) | speed_bits[speed];
        *gayle = new_val;

        /* Small delay for Gayle to settle */
        { volatile int i; for(i=0; i<100; i++); }

        times[speed] = MeasureAccess(base_addr);
    }

    /* Restore original Gayle setting */
    *gayle = orig_gayle;

    /* Print results as table row */
    printf("%-14s %5lu   %5lu   %5lu   %5lu\r\n",
           name,
           (unsigned long)times[0],
           (unsigned long)times[1],
           (unsigned long)times[2],
           (unsigned long)times[3]);
}

/*
 * Measure Chip RAM as baseline
 */
void TestChipRAM(void)
{
    UBYTE *chip;
    ULONG time_ns;

    chip = AllocMem(256, MEMF_CHIP);
    if (!chip) {
        printf("Could not allocate Chip RAM\r\n");
        return;
    }

    time_ns = MeasureAccess((volatile UBYTE *)chip);
    printf("Chip RAM: %lu ns\r\n", (unsigned long)time_ns);

    FreeMem(chip, 256);
}

int main(void)
{
    if (!OpenTimer()) {
        return 10;
    }

    printf("PCMCIA Memory Access Timing Benchmark\r\n");
    printf("=====================================\r\n\r\n");

    /* Measure Chip RAM baseline */
    TestChipRAM();
    printf("\r\n");

    /* Print table header with Gayle modes */
    printf("               Gayle timing (access time in ns)\r\n");
    printf("Memory Type    250ns   150ns   100ns   720ns\r\n");
    printf("-------------- ------  ------  ------  ------\r\n");

    /* Test PCMCIA at different address ranges:
     * - Common Memory ($600000): Main data area, used for disk I/O
     * - Attribute Memory ($A00000): Card configuration/CIS data
     * - Even/Odd addresses: Test byte alignment effects
     */
    TestPCMCIA("Common $600k", (volatile UBYTE *)PCMCIA_COMMON);
    TestPCMCIA("Common $601k", (volatile UBYTE *)(PCMCIA_COMMON + 0x1000));
    TestPCMCIA("Attrib $A00k", (volatile UBYTE *)PCMCIA_ATTR);
    TestPCMCIA("Attrib $A01k", (volatile UBYTE *)(PCMCIA_ATTR + 0x1000));

    printf("\r\nNotes:\r\n");
    printf("- Common Memory: Used for data transfer (disk I/O)\r\n");
    printf("- Attrib Memory: Card configuration (CIS tuples)\r\n");
    printf("- Even/Odd: Tests byte alignment effects\r\n");

    CloseTimer();
    return 0;
}

