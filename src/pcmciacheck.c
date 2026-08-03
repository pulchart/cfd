/*
 * pcmciacheck - PCMCIA/CF Hardware Test Tool
 *
 * Tests different data access modes (byte/word) for PCMCIA CF cards
 * and creates a diagnostic log file.
 *
 * Based on original pcmciacheck 1.17 (29.08.2002) by Torsten Jager
 * Recreated in C for compactflash.device project
 *
 */


#include <exec/types.h>
#include <exec/memory.h>
#include <exec/io.h>
#include <devices/timer.h>
#include <dos/dos.h>

#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/timer.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "pcmciacheck.h"

const char version[] = MAKE_VERSION_STRING("pcmciacheck");

/* Timer globals */
struct MsgPort *TimerPort = NULL;
struct timerequest *TimerReq = NULL;
struct Device *TimerBase = NULL;

/* Log buffer */
UBYTE *LogBuffer = NULL;
UBYTE *LogPtr = NULL;

/* Test patterns */
UBYTE WritePattern[4][256];

/*
 * Sink for reads whose value is thrown away (read mode 3 consumes two
 * words per stored word). Storing into a volatile object is a side
 * effect, so neither the read nor the store can be optimised away.
 */
static volatile UWORD DiscardSink;

/* Gayle PCMCIA timings, slowest last so a sweep ends on the safest one */
const int GayleSpeeds[GAYLE_SPEED_COUNT] = { 100, 150, 250, 720 };

static UBYTE GayleSpeedBits(int ns);
static const char *GayleSpeedLabel(UBYTE cfg);

/*
 * Set the Gayle PCMCIA timing and return the previous register value
 * for GayleRestore. A speed of 0, or one that is not on the Gayle grid,
 * leaves the register alone.
 *
 * This pokes $DAB000 directly. The driver reaches the same register
 * through card.resource CardAccessSpeed, so an override here lasts only
 * as long as this program runs; it is a diagnostic, not a fix.
 */
UBYTE GayleSetSpeed(int ns)
{
    UBYTE saved = *GAYLE_CONFIG;
    UBYTE want;

    if (ns == 0) return saved;

    want = GayleSpeedBits(ns);
    if (want == 0xFF) return saved;

    *GAYLE_CONFIG = (saved & 0xF3) | want;

    return saved;
}

/* Put back a register value saved by GayleSetSpeed */
void GayleRestore(UBYTE cfg)
{
    *GAYLE_CONFIG = cfg;
}

/* Label for the timing currently programmed */
const char *GayleCurrentLabel(void)
{
    return GayleSpeedLabel(*GAYLE_CONFIG);
}

/* "100ns" style label for one of the four timings */
const char *GayleSpeedName(int ns)
{
    switch (ns) {
        case 100: return "100ns";
        case 150: return "150ns";
        case 250: return "250ns";
        case 720: return "720ns";
        default:  return "?";
    }
}

/* Timing currently programmed, in nanoseconds */
int GayleCurrentSpeed(void)
{
    switch (*GAYLE_CONFIG & 0x0C) {
        case 0x00: return 250;
        case 0x04: return 150;
        case 0x08: return 100;
        default:   return 720;
    }
}

/*
 * Pattern-based transfer mode test (mirrors cfd.s RWTest)
 * Tests all 16 combinations of write/read modes with simple patterns
 * Returns bitfield of working mode combinations
 */
UWORD TestTransferModes(void)
{
    volatile UBYTE *a0 = (volatile UBYTE *)(IDE_BASE + 0x04);  /* IDEAddr + 4 */
    volatile UBYTE *a1 = (volatile UBYTE *)((ULONG)a0 + 0x10000); /* a0 + $10000 */
    UWORD test_pattern = 0x1234;
    UWORD working_modes = 0xFFFF;
    UWORD run_modes;
    int write_mode, read_mode, test_run;
    UWORD written_data, read_data;

    /*
     * Each combination is tried twice and the two passes are ANDed, so
     * a combination has to work both times to count as working. This
     * mirrors RWTest in src/cfd.s, which runs TestRun twice and ANDs
     * the results. ORing them here would hide exactly the
     * intermittency the driver is looking for.
     */
    for (test_run = 0; test_run < 2; test_run++) {
        run_modes = 0;
        for (write_mode = 0; write_mode < 4; write_mode++) {
            for (read_mode = 0; read_mode < 4; read_mode++) {
                int mode_combo = (write_mode << 2) | read_mode;

                /* Write test pattern using selected write mode */
                switch (write_mode) {
                    case 0: /* Word write */
                        *((volatile UWORD *)a0) = test_pattern;
                        written_data = test_pattern;
                        break;
                    case 1: /* Byte write (sequential) */
                        *(a0) = (test_pattern >> 8) & 0xFF;    /* High byte first */
                        *(a0 + 1) = test_pattern & 0xFF;      /* Low byte */
                        written_data = test_pattern;
                        break;
                    case 2: /* Byte write (alternating) */
                        *(a0) = (test_pattern >> 8) & 0xFF;   /* High byte */
                        *(a1) = test_pattern & 0xFF;          /* Low byte */
                        written_data = test_pattern;
                        break;
                    case 3: /* Byte write (offset) */
                        *(a0) = (test_pattern >> 8) & 0xFF;   /* High byte */
                        *(a1 + 1) = test_pattern & 0xFF;     /* Low byte offset */
                        written_data = test_pattern;
                        break;
                }

                /* Read back using selected read mode */
                switch (read_mode) {
                    case 0: /* Word read */
                        read_data = *((volatile UWORD *)a0);
                        break;
                    case 1: /* Byte read (sequential) */
                        read_data = (*(a0) << 8) | *(a0 + 1);
                        break;
                    case 2: /* Byte read (alternating) */
                        read_data = (*(a0) << 8) | *(a1);
                        break;
                    case 3: /* Byte read (offset) */
                        read_data = (*(a0) << 8) | *(a1 + 1);
                        break;
                }

                /* Check if data matches */
                if (read_data == written_data) {
                    run_modes |= (1 << mode_combo);
                }

                /* Update test pattern for next iteration (like cfd.s) */
                test_pattern += 0x0202;
            }
        }
        working_modes &= run_modes;
    }

    return working_modes;
}

/*
 * Log pattern test results
 */
void LogPatternTest(void)
{
    UWORD modes;
    int i;

    WriteChunkHeader("ptst", 2);  /* Pattern test chunk */

    modes = TestTransferModes();

    /* Store as big-endian word */
    *LogPtr++ = (modes >> 8) & 0xFF;
    *LogPtr++ = modes & 0xFF;

    printf("  Pattern test modes: 0x%04X\r\n", modes);
}

/*
 * Open timer device for delays
 */
int OpenTimer(void)
{
    TimerPort = CreateMsgPort();
    if (!TimerPort) return 0;

    TimerReq = (struct timerequest *)CreateIORequest(TimerPort, sizeof(struct timerequest));
    if (!TimerReq) {
        DeleteMsgPort(TimerPort);
        return 0;
    }

    if (OpenDevice("timer.device", UNIT_VBLANK, (struct IORequest *)TimerReq, 0)) {
        DeleteIORequest((struct IORequest *)TimerReq);
        DeleteMsgPort(TimerPort);
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
 * Delay in milliseconds
 */
void DelayMS(ULONG ms)
{
    TimerReq->tr_node.io_Command = TR_ADDREQUEST;
    TimerReq->tr_time.tv_secs = ms / 1000;
    TimerReq->tr_time.tv_micro = (ms % 1000) * 1000;
    DoIO((struct IORequest *)TimerReq);
}

/*
 * Check if card is present
 */
int CardPresent(void)
{
    return (*GAYLE_STATUS & GAYLE_CARD_DETECT) ? 1 : 0;
}

/*
 * Wait for IDE ready (not BSY, DRDY set)
 * Returns status byte or -1 on timeout/card removed
 */
int WaitReady(int timeout_ms)
{
    int i;
    UBYTE status;

    for (i = 0; i < timeout_ms / 100; i++) {
        if (!CardPresent()) return -1;

        /* Acknowledge status */
        *((volatile UBYTE *)(0x00A00200 + 4)) = 0x0F;

        status = *IDE_STATUS;
        if (!(status & STATUS_BSY)) {
            return status;
        }

        DelayMS(100);
    }

    return -1;  /* Timeout */
}

/*
 * Wait for IDE ready through the memory-mapped status register.
 * Same contract as WaitReady, for read mode 4.
 */
static int WaitReadyMMAP(int timeout_ms)
{
    int i;
    UBYTE status;

    for (i = 0; i < timeout_ms / 100; i++) {
        if (!CardPresent()) return -1;

        status = *MMAP_STATUS;
        if (!(status & STATUS_BSY)) {
            return status;
        }

        DelayMS(100);
    }

    return -1;  /* Timeout */
}

/*
 * Issue ATA IDENTIFY and read the whole 512-byte block with one mode.
 *
 * The transfer is a single call with the full byte count, the way the
 * driver calls _pio_in, so the modes that walk an address (1 and 4)
 * see the same address sequence the driver produces. Read mode 4
 * needs the memory-mapped register window and restores PCMCIA_CONFIG
 * before returning.
 *
 * Returns 1 when the block was read, 0 on timeout or when DRQ never
 * appeared. When non-NULL, *drq_after reports whether DRQ was still
 * asserted after the transfer, which is the multi-sector symptom.
 */
static int IdentifyRead(int mode, UBYTE *dest, int *drq_after)
{
    int status;
    int mmap = (mode == 4);
    UBYTE orig_config = 0;

    if (drq_after) *drq_after = 0;

    if (mmap) {
        orig_config = *PCMCIA_CONFIG;
        *PCMCIA_CONFIG = 0x40;
        DelayMS(1);
        *MMAP_DEVHEAD = 0xE0;
        *MMAP_COMMAND = ATA_IDENTIFY;
        status = WaitReadyMMAP(30000);
    } else {
        *IDE_DEVHEAD = 0xE0;  /* LBA, drive 0 */
        *IDE_COMMAND = ATA_IDENTIFY;
        status = WaitReady(30000);
    }

    if (status < 0 || !(status & STATUS_DRQ)) {
        if (mmap) {
            *PCMCIA_CONFIG = orig_config;
            DelayMS(1);
        }
        return 0;
    }

    ReadModes[mode](dest, IDENTIFY_BYTES);

    status = mmap ? (int)*MMAP_STATUS : (int)*IDE_STATUS;
    if (drq_after) *drq_after = (status & STATUS_DRQ) ? 1 : 0;

    if (mmap) {
        *PCMCIA_CONFIG = orig_config;
        DelayMS(1);
    }

    return 1;
}

/*
 * Write IFF chunk header
 */
void WriteChunkHeader(const char *id, ULONG size)
{
    memcpy(LogPtr, id, 4);
    LogPtr += 4;

    /* Size in big-endian */
    *LogPtr++ = (size >> 24) & 0xFF;
    *LogPtr++ = (size >> 16) & 0xFF;
    *LogPtr++ = (size >> 8) & 0xFF;
    *LogPtr++ = size & 0xFF;
}

/*
 * Read mode 0: word-wise from the data port (src/cfd.s pi_mode0)
 *
 * Fixed address, one word read per stored word. This is the mode the
 * driver reports as "transfer mode: WORD".
 */
void ReadMode0(UBYTE *dest, ULONG bytes)
{
    volatile UWORD *src = IDE_DATA_PORT;
    UWORD *d = (UWORD *)dest;
    ULONG n = bytes >> 1;

    while (n--) {
        *d++ = *src;
    }
}

/*
 * Read mode 1: word-wise from the data port and its register aliases
 * (src/cfd.s pi_mode1)
 *
 * The address advances by MODE1_STRIDE per word and restarts at the
 * data port on every MODE1_SEGMENT boundary.
 */
void ReadMode1(UBYTE *dest, ULONG bytes)
{
    UWORD *d = (UWORD *)dest;

    while (bytes) {
        ULONG seg = (bytes > MODE1_SEGMENT) ? MODE1_SEGMENT : bytes;
        ULONG addr = (ULONG)IDE_DATA_PORT;
        ULONG n = seg >> 1;

        while (n--) {
            *d++ = *(volatile UWORD *)addr;
            addr += MODE1_STRIDE;
        }
        bytes -= seg;
    }
}

/*
 * Read mode 2: byte-wise, alternating data port and its odd-byte
 * alias (src/cfd.s pi_mode2)
 */
void ReadMode2(UBYTE *dest, ULONG bytes)
{
    volatile UBYTE *src_lo = IDE_DATA_PORT_B;
    volatile UBYTE *src_hi = IDE_DATA_PORT_H;
    ULONG n = bytes >> 1;

    while (n--) {
        *dest++ = *src_lo;
        *dest++ = *src_hi;
    }
}

/*
 * Read mode 3: word-wise from the data port, two reads per stored
 * word, the second discarded (src/cfd.s pi_mode3)
 *
 * For adapters whose data port hands out every word twice.
 */
void ReadMode3(UBYTE *dest, ULONG bytes)
{
    volatile UWORD *src = IDE_DATA_PORT;
    UWORD *d = (UWORD *)dest;
    ULONG n = bytes >> 1;

    while (n--) {
        *d++ = *src;
        DiscardSink = *src;     /* second read, value dropped */
    }
}

/*
 * Write mode 0: word-wise to the data port (src/cfd.s po_mode0)
 */
void WriteMode0(UBYTE *src, ULONG bytes)
{
    volatile UWORD *dest = IDE_DATA_PORT;
    UWORD *s = (UWORD *)src;
    ULONG n = bytes >> 1;

    while (n--) {
        *dest = *s++;
    }
}

/*
 * Write mode 1: word-wise to the data port and its register aliases
 * (src/cfd.s po_mode1)
 */
void WriteMode1(UBYTE *src, ULONG bytes)
{
    UWORD *s = (UWORD *)src;

    while (bytes) {
        ULONG seg = (bytes > MODE1_SEGMENT) ? MODE1_SEGMENT : bytes;
        ULONG addr = (ULONG)IDE_DATA_PORT;
        ULONG n = seg >> 1;

        while (n--) {
            *(volatile UWORD *)addr = *s++;
            addr += MODE1_STRIDE;
        }
        bytes -= seg;
    }
}

/*
 * Write mode 2: byte-wise, alternating data port and its odd-byte
 * alias (src/cfd.s po_mode2)
 */
void WriteMode2(UBYTE *src, ULONG bytes)
{
    volatile UBYTE *dest_lo = IDE_DATA_PORT_B;
    volatile UBYTE *dest_hi = IDE_DATA_PORT_H;
    ULONG n = bytes >> 1;

    while (n--) {
        *dest_lo = *src++;
        *dest_hi = *src++;
    }
}

/*
 * Write mode 3: the driver has no separate write routine for mode 3,
 * po_tab in src/cfd.s maps slot 3 onto po_mode1. Mirror that
 * rather than inventing a fifth write path.
 */
void WriteMode3(UBYTE *src, ULONG bytes)
{
    WriteMode1(src, bytes);
}

/*
 * Read mode 4: memory mapped, word-wise from the common-memory window
 * at offset 1024, restarting on every MODE4_SEGMENT boundary
 * (src/cfd.s pi_mode4)
 */
void ReadMode4(UBYTE *dest, ULONG bytes)
{
    UWORD *d = (UWORD *)dest;

    while (bytes) {
        ULONG seg = (bytes > MODE4_SEGMENT) ? MODE4_SEGMENT : bytes;
        volatile UWORD *src = PCMCIA_MEM_DATA;
        ULONG n = seg >> 1;

        while (n--) {
            *d++ = *src++;
        }
        bytes -= seg;
    }
}

/*
 * Write mode 4: memory mapped, word-wise (src/cfd.s po_mode4)
 */
void WriteMode4(UBYTE *src, ULONG bytes)
{
    UWORD *s = (UWORD *)src;

    while (bytes) {
        ULONG seg = (bytes > MODE4_SEGMENT) ? MODE4_SEGMENT : bytes;
        volatile UWORD *dest = PCMCIA_MEM_DATA;
        ULONG n = seg >> 1;

        while (n--) {
            *dest++ = *s++;
        }
        bytes -= seg;
    }
}

/* Function pointer arrays for read/write modes */
ReadFunc ReadModes[5] = { ReadMode0, ReadMode1, ReadMode2, ReadMode3, ReadMode4 };
WriteFunc WriteModes[5] = { WriteMode0, WriteMode1, WriteMode2, WriteMode3, WriteMode4 };

/* Short mode descriptions, used by the read-mode and stability reports */
const char *ReadModeNames[5] = {
    "word +8",
    "word +8 stride 16",
    "byte +8 / +8 odd",
    "word +8 read-twice",
    "MMAP word"
};

/*
 * Test read modes with IDENTIFY DEVICE command
 */
static int BlockStuck(const UBYTE *b, UWORD *value);
static int BlockAllZero(const UBYTE *b);

int TestReadModes(int *working_mode)
{
    int mode;
    UBYTE *chunk_start;
    char chunk_id[5] = "rdc0";
    int any_plausible = 0;

    *working_mode = -1;

    for (mode = 0; mode < 5; mode++) {
        int drq_after = 0;
        int stuck;
        int all_zero;
        UWORD stuck_value = 0;
        int ok;

        printf("  Testing read mode %d (%s)...", mode, ReadModeNames[mode]);
        chunk_id[3] = '0' + mode;
        chunk_start = LogPtr;

        /* Reserve space for chunk header */
        LogPtr += 8;

        ok = IdentifyRead(mode, LogPtr, &drq_after);
        if (!ok) {
            printf(" NO DATA (timeout or DRQ never set)\r\n");
            LogPtr = chunk_start;
            WriteChunkHeader(chunk_id, 0);
            continue;
        }
        all_zero = BlockAllZero(LogPtr);
        stuck = !all_zero && BlockStuck(LogPtr, &stuck_value);
        LogPtr += IDENTIFY_BYTES;

        {
            UBYTE *save_ptr = LogPtr;
            LogPtr = chunk_start;
            WriteChunkHeader(chunk_id, IDENTIFY_BYTES);
            LogPtr = save_ptr;
        }

        /*
         * Remember the first mode that delivered plausible data. An
         * empty or stuck block does not count: the write test reads back
         * through this mode, and the driver would not accept it either.
         */
        if (!stuck && !all_zero) {
            any_plausible = 1;
            if (*working_mode < 0) {
                *working_mode = mode;
            }
        }

        printf(" OK (%d bytes)", IDENTIFY_BYTES);

        if (all_zero) {
            printf(" - no data (all zeros)");
        } else if (stuck) {
            printf(" - repeated pattern 0x%04X", stuck_value);
        } else if (drq_after) {
            /*
             * DRQ still asserted after a full 512-byte IDENTIFY means
             * the card wants to hand over more than one sector. Not
             * reported for a stuck block, where the status register is
             * as unreliable as the data.
             */
            printf(" - WARNING: multi-sector issue detected");
        }

        printf("\r\n");
    }

    if (*working_mode < 0) {
        *working_mode = 0;  /* Default to mode 0 for the remaining tests */
    }

    return any_plausible;
}

/* Store a big-endian word into the log */
static void PutLogWord(UWORD v)
{
    *LogPtr++ = (v >> 8) & 0xFF;
    *LogPtr++ = v & 0xFF;
}

/* XOR fold of all words in a block, the check the driver applies */
static UWORD BlockChecksum(const UBYTE *b)
{
    const UWORD *w = (const UWORD *)b;
    UWORD x = 0;
    int i;

    for (i = 0; i < IDENTIFY_BYTES / 2; i++) {
        x ^= w[i];
    }

    return x;
}

/*
 * Count words equal to their predecessor, ignoring the 0x0000 and
 * 0x2020 padding that fills the tail of a normal IDENTIFY block.
 *
 * This describes *how* a block is corrupted: a data port that fails to
 * advance repeats whole words, which shows up here as a high count. It
 * is a characterisation, not a verdict. A healthy card can contain
 * legitimately repeated words too, so STABLE/UNSTABLE is decided by
 * comparing whole blocks, never by this number.
 */
static UWORD CountRepeatedWords(const UBYTE *b)
{
    const UWORD *w = (const UWORD *)b;
    UWORD n = 0;
    int i;

    for (i = 1; i < IDENTIFY_BYTES / 2; i++) {
        if (w[i] == w[i - 1] && w[i] != 0x0000 && w[i] != 0x2020) {
            n++;
        }
    }

    return n;
}

/*
 * Stuck data port: words 0, 10 and 60 all carry the same value.
 *
 * A port that never advances returns one value for every read, so the
 * block is garbage even though it is perfectly repeatable. Repeating
 * the read cannot detect it, which is why this check exists next to the
 * stability test rather than inside it.
 *
 * This is the same three-word rule the driver applies before it
 * compares anything, so the verdict here predicts the driver's
 * "FAILED (repeated pattern)" rejection.
 *
 * Returns 1 when stuck, and stores the repeated value in *value.
 */
static int BlockStuck(const UBYTE *b, UWORD *value)
{
    const UWORD *w = (const UWORD *)b;

    if (value) *value = w[0];

    return (w[0] == w[10] && w[0] == w[60]) ? 1 : 0;
}

/*
 * Every word zero. The transfer produced nothing at all, which is a
 * different fault from a port latched at some value, and it is worth
 * saying so: reporting "repeated pattern 0x0000" alongside a repeated
 * word count of zero (the counter ignores 0x0000 padding) says two
 * contradictory things about the same block.
 *
 * The driver does not draw this distinction, its _PatternCheck would
 * call an all-zero block a repeated pattern. The tool separates them
 * because it describes one mode at a time rather than judging the card.
 */
static int BlockAllZero(const UBYTE *b)
{
    const UWORD *w = (const UWORD *)b;
    int i;

    for (i = 0; i < IDENTIFY_BYTES / 2; i++) {
        if (w[i]) return 0;
    }

    return 1;
}

/*
 * Measure one mode: read IDENTIFY `runs` times and compare the blocks.
 *
 * IDENTIFY is static data on the card, so reading it repeatedly through
 * the same mode has to return the same bytes every time. When it does
 * not, the data path is corrupting the transfer, and that is what the
 * driver rejects a card for with "FAILED (data mismatch)".
 *
 * A stuck port is the other failure the driver rejects, and it is
 * repeatable, so it is recorded separately; callers weigh it first, in
 * the same order the driver checks it.
 *
 * Only two blocks are held at a time, the reference and the current
 * run, so the cost is 1 KB regardless of the run count.
 */
static void MeasureStability(int mode, int runs, StabResult *r)
{
    static UBYTE ref[IDENTIFY_BYTES];
    static UBYTE cur[IDENTIFY_BYTES];
    int have_ref = 0;
    int run, i, j;

    memset(r, 0, sizeof(*r));
    r->first_diff = -1;

    for (run = 0; run < runs; run++) {
        /*
         * The first run that actually delivers a block becomes the
         * reference. Run 0 failing must not leave an empty reference
         * for the rest to be compared against.
         */
        UBYTE *dest = have_ref ? cur : ref;

        if (!IdentifyRead(mode, dest, NULL)) {
            continue;
        }
        r->read_ok++;
        r->run_ok[run] = 1;
        r->ok_mask |= 1UL << run;
        r->cks[run] = BlockChecksum(dest);

        if (!have_ref) {
            have_ref = 1;
            r->identical++;               /* the reference matches itself */
            r->repeats = CountRepeatedWords(ref);
            r->all_zero = BlockAllZero(ref);
            /*
             * An all-zero block satisfies the stuck rule too, so keep
             * the two mutually exclusive: all-zero wins, and the stuck
             * flag means a port latched at a real value.
             */
            r->stuck = !r->all_zero && BlockStuck(ref, &r->stuck_value);
            continue;
        }

        if (memcmp(cur, ref, IDENTIFY_BYTES) == 0) {
            r->identical++;
        } else {
            const UWORD *a = (const UWORD *)ref;
            const UWORD *b = (const UWORD *)cur;
            int differ = 0;

            for (i = 0; i < IDENTIFY_BYTES / 2; i++) {
                if (a[i] != b[i]) {
                    if (r->first_diff < 0 || i < r->first_diff) r->first_diff = i;
                    differ++;
                }
            }
            if (differ > r->worst_differ) r->worst_differ = differ;
        }
    }

    /*
     * Distinct checksums seen. This can under-count, two different
     * blocks can fold to the same XOR, which is exactly the weakness of
     * a checksum compared to a byte comparison.
     */
    for (i = 0; i < runs; i++) {
        int seen = 0;
        if (!r->run_ok[i]) continue;      /* a failed read has no checksum */
        for (j = 0; j < i; j++) {
            if (r->run_ok[j] && r->cks[j] == r->cks[i]) { seen = 1; break; }
        }
        if (!seen) r->distinct++;
    }
}

/*
 * Classify a measurement. An empty block and a stuck port are weighed
 * before stability, because both are repeatable and would otherwise
 * read as STABLE.
 */
static int StabVerdict(const StabResult *r, int runs)
{
    if (r->read_ok == 0) return STAB_NODATA;
    if (r->all_zero) return STAB_ZERO;
    if (r->stuck) return STAB_STUCK;
    if (r->identical == r->read_ok && r->read_ok == runs) return STAB_STABLE;
    return STAB_UNSTABLE;
}

/*
 * Per-mode IDENTIFY read stability report.
 *
 * The read-mode test cannot see either failure, it only checks that a
 * block arrived. This is the test that can confirm or refute the
 * driver's verdict, so it uses the same modes and the same 512-byte
 * single-call transfer the driver uses.
 *
 * The driver takes the first mode that delivers a block, so the lowest
 * numbered mode that delivered one here is the mode whose verdict
 * decides the card. Note that is not the same as the first mode with
 * *plausible* data: on a stuck card the driver does take mode 0, gets
 * garbage, and rejects the card.
 */
int TestReadStability(int runs)
{
    StabResult res;
    int mode;
    int bad_modes = 0;
    int used_mode = -1;
    int used_verdict = STAB_NODATA;

    if (runs < STAB_RUNS_MIN) runs = STAB_RUNS_MIN;
    if (runs > STAB_RUNS_MAX) runs = STAB_RUNS_MAX;

    printf("Testing IDENTIFY read stability (%d runs per mode)...\r\n", runs);

    for (mode = 0; mode < 5; mode++) {
        StabResult *r = &res;
        int verdict;
        int i;

        MeasureStability(mode, runs, r);
        verdict = StabVerdict(r, runs);

        if (used_mode < 0 && r->read_ok > 0) {
            used_mode = mode;
            used_verdict = verdict;
        }
        if (verdict != STAB_STABLE) bad_modes++;

        printf("  mode %d (%-18s) ", mode, ReadModeNames[mode]);

        switch (verdict) {
        case STAB_NODATA:
            printf("NO DATA\r\n");
            break;

        case STAB_ZERO:
            printf("NOT USABLE (all zeros, nothing was read)\r\n");
            break;

        case STAB_STUCK:
            /*
             * The raw value is printed first because that is what the
             * driver's "FAILED (repeated pattern ...)" message carries,
             * it reports the word before the byte swap. The swapped
             * value is the one that looks like ATA data to a reader.
             */
            printf("STUCK     repeated pattern 0x%04X (ATA 0x%04X), %d repeated word(s)\r\n",
                   r->stuck_value,
                   (UWORD)((r->stuck_value << 8) | (r->stuck_value >> 8)),
                   (int)r->repeats);
            break;

        case STAB_STABLE:
            printf("STABLE    %d/%d identical, xor %04X, %d repeated word(s)\r\n",
                   r->identical, runs, r->cks[0], (int)r->repeats);
            break;

        default:
            printf("UNSTABLE\r\n");
            printf("     %d/%d read, %d/%d identical, %d distinct checksum(s)\r\n",
                   r->read_ok, runs, r->identical, r->read_ok, r->distinct);
            if (r->first_diff >= 0) {
                printf("     first difference at word %d, up to %d of %d words differ\r\n",
                       r->first_diff, r->worst_differ, IDENTIFY_BYTES / 2);
            }
            printf("     %d repeated word(s) in the reference block\r\n",
                   (int)r->repeats);
            printf("     xor:");
            for (i = 0; i < runs; i++) {
                if (r->run_ok[i]) printf(" %04X", r->cks[i]);
                else              printf(" ----");
            }
            printf("\r\n");
            break;
        }

    }

    if (used_mode < 0) {
        printf("  No mode delivered a block.\r\n");
        return 1;
    }

    /*
     * Only the mode the driver actually uses decides whether the card is
     * usable. The driver tries modes 0 to 3 in order and falls back to 4
     * last, so a failure in a later mode is never reached once an
     * earlier one works, and must not be reported as a bad card.
     */
    printf("  Driver uses mode %d: %s\r\n", used_mode,
           used_verdict == STAB_STABLE ? "stable" : "NOT stable");

    if (used_verdict == STAB_STABLE) {
        if (bad_modes) {
            printf("  %d other mode(s) are not usable here, which does not\r\n",
                   bad_modes);
            printf("  affect the card: the driver never falls back to them.\r\n");
        }
    } else if (used_verdict == STAB_STUCK) {
        printf("  The card is not readable in this setup; the driver\r\n");
        printf("  rejects it with \"FAILED (repeated pattern)\".\r\n");
    } else if (used_verdict == STAB_UNSTABLE) {
        printf("  The card's data path is not bit-stable in this setup;\r\n");
        printf("  the driver rejects it with \"FAILED (data mismatch)\".\r\n");
    } else {
        printf("  That mode returned no usable data.\r\n");
    }

    return used_verdict == STAB_STABLE ? 0 : 1;
}

/*
 * Run the stability test at every Gayle PCMCIA timing and print a
 * matrix, one row per read mode.
 *
 * The point is to find out whether the timing is the variable at all.
 * If a card is unstable at 250ns and stable at 720ns, the bus is being
 * driven faster than the card can follow; if every column looks the
 * same, timing is not what is wrong. Either answer is worth having.
 *
 * The timing is restored before returning. Note that $DAB000 is
 * documented as the PCMCIA *memory* speed, while read modes 0 to 3 use
 * I/O space, so it is possible for those columns not to move at all.
 */
int SweepReadStability(int runs)
{
    /*
     * Abbreviated verdicts so the columns line up. Mode names are left
     * out of the matrix: they run to 18 characters, which is what pushed
     * the columns out of alignment, and they are listed in the guide.
     */
    static const char *verdict_short[5] = {
        "NODATA", "ZEROS", "STUCK", "UNSTAB", "STABLE"
    };
    UBYTE saved = *GAYLE_CONFIG;
    int used_mode = -1;
    int speed, mode;

    if (runs < STAB_RUNS_MIN) runs = STAB_RUNS_MIN;
    if (runs > STAB_RUNS_MAX) runs = STAB_RUNS_MAX;

    printf("Testing IDENTIFY read stability at each Gayle timing (%d runs per mode)...\r\n",
           runs);

    /*
     * Cells are padded except in the last column, so the columns line up
     * without leaving trailing blanks on every line.
     */
    printf("        ");
    for (speed = 0; speed < GAYLE_SPEED_COUNT; speed++) {
        const char *name = GayleSpeedName(GayleSpeeds[speed]);

        if (speed + 1 < GAYLE_SPEED_COUNT) printf("  %-6s", name);
        else                               printf("  %s", name);
    }
    printf("\r\n");

    /*
     * Loop modes inside speeds, so the timing is programmed once per
     * column instead of once per cell.
     */
    {
        int results[GAYLE_SPEED_COUNT][5];

        for (speed = 0; speed < GAYLE_SPEED_COUNT; speed++) {
            GayleSetSpeed(GayleSpeeds[speed]);
            DelayMS(1);

            for (mode = 0; mode < 5; mode++) {
                StabResult r;

                MeasureStability(mode, runs, &r);
                results[speed][mode] = StabVerdict(&r, runs);
            }
        }

        GayleRestore(saved);
        DelayMS(1);

        /*
         * The driver takes the first mode that delivers a block, so the
         * lowest numbered mode that produced anything in any column is
         * the row whose verdict decides the card.
         */
        for (mode = 0; mode < 5 && used_mode < 0; mode++) {
            for (speed = 0; speed < GAYLE_SPEED_COUNT; speed++) {
                if (results[speed][mode] != STAB_NODATA) {
                    used_mode = mode;
                    break;
                }
            }
        }

        for (mode = 0; mode < 5; mode++) {
            printf("  mode %d", mode);
            for (speed = 0; speed < GAYLE_SPEED_COUNT; speed++) {
                const char *v = verdict_short[results[speed][mode]];

                if (speed + 1 < GAYLE_SPEED_COUNT || mode == used_mode)
                    printf("  %-6s", v);
                else
                    printf("  %s", v);
            }
            if (mode == used_mode) printf("  <- driver uses this");
            printf("\r\n");
        }

        printf("  Gayle timing restored to %s\r\n", GayleCurrentLabel());

        /*
         * Only the driver's own mode decides whether the card is usable,
         * so the summary is about that row alone.
         */
        {
            int good = 0;
            int bad = 0;

            if (used_mode < 0) {
                printf("  No mode delivered a block at any timing.\r\n");
                return 1;
            }

            for (speed = 0; speed < GAYLE_SPEED_COUNT; speed++) {
                if (results[speed][used_mode] == STAB_STABLE) good++;
                else                                          bad++;
            }

            if (bad == 0) {
                printf("  Mode %d is stable at every timing.\r\n", used_mode);
                return 0;
            }

            if (good == 0) {
                printf("  Mode %d is stable at no timing, so the timing is not\r\n",
                       used_mode);
                printf("  what is wrong with this card.\r\n");
                return 1;
            }

            printf("  Mode %d is stable only at:", used_mode);
            for (speed = 0; speed < GAYLE_SPEED_COUNT; speed++) {
                if (results[speed][used_mode] == STAB_STABLE) {
                    printf(" %s", GayleSpeedName(GayleSpeeds[speed]));
                }
            }
            printf("\r\n");
            printf("  The card cannot follow the faster settings. Note the\r\n");
            printf("  driver programs the timing itself, this cannot pin it.\r\n");
            return 1;
        }
    }
}

/*
 * Initialize write test patterns
 */
void InitWritePatterns(void)
{
    int i;
    UBYTE val;

    /* Pattern 0: ascending bytes 0x00-0xFF */
    for (i = 0; i < 256; i++) {
        WritePattern[0][i] = i;
    }

    /* Pattern 1: descending bytes 0xFF-0x00 */
    for (i = 0; i < 256; i++) {
        WritePattern[1][i] = 255 - i;
    }

    /* Pattern 2: alternating 0x55/0xAA */
    for (i = 0; i < 256; i++) {
        WritePattern[2][i] = (i & 1) ? 0xAA : 0x55;
    }

    /* Pattern 3: all 0x00 */
    memset(WritePattern[3], 0, 256);
}

/*
 * Test write modes
 */
int TestWriteModes(int read_mode)
{
    int mode;
    int status;
    ULONG bytes_written[5];
    UBYTE *chunk_start;
    int sector;

    printf("  Initializing write patterns...\r\n");
    InitWritePatterns();

    /* Write test - write 4 sectors with different modes */
    for (mode = 0; mode < 4; mode++) {
        printf("  Testing write mode %d (sector %d)...", mode, mode + 1);
        bytes_written[mode] = 0;

        /* Setup WRITE SECTORS command */
        *IDE_SECCOUNT = 1;          /* 1 sector */
        *IDE_SECNUM = mode + 1;     /* LBA 1-4 */
        *IDE_CYLLO = 0;
        *IDE_CYLHI = 0;
        *IDE_DEVHEAD = 0xE0;        /* LBA, drive 0 */

        status = WaitReady(5000);
        if (status < 0 || !CardPresent()) {
            printf(" TIMEOUT\r\n");
            continue;
        }
        if (!(status & STATUS_DRDY)) {
            printf(" NOT READY\r\n");
            continue;
        }

        *IDE_COMMAND = ATA_WRITE;

        /* Wait for DRQ */
        status = WaitReady(5000);
        if (status < 0) {
            printf(" NO DRQ\r\n");
            continue;
        }

        /* Write in 256-byte chunks while DRQ is set */
        {
            UBYTE *pattern_ptr = WritePattern[mode];
            int chunk = 0;

            while (status >= 0 && (status & STATUS_DRQ)) {
                WriteModes[mode](pattern_ptr, 256);
                bytes_written[mode] += 256;
                chunk++;

                /* Alternate between pattern[mode] and pattern[(mode+1)%4] */
                pattern_ptr = WritePattern[(mode + chunk) % 4];

                status = *IDE_STATUS;
                if (status & STATUS_BSY) {
                    status = WaitReady(5000);
                }
            }
        }
        printf(" %lu bytes\r\n", (unsigned long)bytes_written[mode]);
    }

    /* Test mode 4 (memory mapped) write */
    {
        UBYTE orig_config = *PCMCIA_CONFIG;

        printf("  Testing write mode 4 MMAP (sector 5)...");
        bytes_written[4] = 0;

        /* Switch to memory-mapped mode */
        *PCMCIA_CONFIG = 0x40;
        DelayMS(1);

        /* Setup WRITE SECTORS command via memory-mapped registers */
        *((volatile UBYTE *)(PCMCIA_MEM + 0x02)) = 1;           /* SECCOUNT = 1 */
        *((volatile UBYTE *)(PCMCIA_MEM + 0x03 + 0x10000)) = 5; /* SECNUM = 5 */
        *((volatile UBYTE *)(PCMCIA_MEM + 0x04)) = 0;           /* CYLLO */
        *((volatile UBYTE *)(PCMCIA_MEM + 0x05 + 0x10000)) = 0; /* CYLHI */
        *MMAP_DEVHEAD = 0xE0;

        /* Wait for ready */
        {
            int timeout = 50;
            status = -1;
            while (timeout > 0) {
                UBYTE s = *MMAP_STATUS;
                if (!(s & STATUS_BSY) && (s & STATUS_DRDY)) {
                    status = s;
                    break;
                }
                DelayMS(100);
                timeout--;
            }
        }

        if (status < 0) {
            printf(" TIMEOUT\r\n");
        } else {
            *MMAP_COMMAND = ATA_WRITE;

            /* Wait for DRQ */
            {
                int timeout = 50;
                status = -1;
                while (timeout > 0) {
                    UBYTE s = *MMAP_STATUS;
                    if (!(s & STATUS_BSY)) {
                        status = s;
                        break;
                    }
                    DelayMS(100);
                    timeout--;
                }
            }

            if (status >= 0 && (status & STATUS_DRQ)) {
                UBYTE *pattern_ptr = WritePattern[0];
                int chunk = 0;

                while (status >= 0 && (status & STATUS_DRQ)) {
                    WriteMode4(pattern_ptr, 256);
                    bytes_written[4] += 256;
                    chunk++;
                    pattern_ptr = WritePattern[chunk % 4];
                    status = *MMAP_STATUS;
                    if (status & STATUS_BSY) {
                        int timeout = 50;
                        while (timeout > 0 && (*MMAP_STATUS & STATUS_BSY)) {
                            DelayMS(100);
                            timeout--;
                        }
                        status = *MMAP_STATUS;
                    }
                }
            }
            printf(" %lu bytes\r\n", (unsigned long)bytes_written[4]);
        }

        /* Restore I/O mode config */
        *PCMCIA_CONFIG = orig_config;
        DelayMS(1);
    }

    printf("  Writing test summary...\r\n");
    /* Write wcln chunk - bytes written per mode */
    WriteChunkHeader("wcln", 20);  /* 5 modes x 4 bytes */
    for (mode = 0; mode < 5; mode++) {
        *LogPtr++ = (bytes_written[mode] >> 24) & 0xFF;
        *LogPtr++ = (bytes_written[mode] >> 16) & 0xFF;
        *LogPtr++ = (bytes_written[mode] >> 8) & 0xFF;
        *LogPtr++ = bytes_written[mode] & 0xFF;
    }

    /* Read back and verify - wcda chunk */
    printf("  Reading back 4 sectors for verification...\r\n");
    chunk_start = LogPtr;
    LogPtr += 8;  /* Reserve for header */

    /* Read 4 sectors back */
    *IDE_SECCOUNT = 4;
    *IDE_SECNUM = 1;
    *IDE_CYLLO = 0;
    *IDE_CYLHI = 0;
    *IDE_DEVHEAD = 0xE0;
    *IDE_COMMAND = ATA_READ;

    status = WaitReady(5000);
    if (status < 0) {
        printf("  TIMEOUT\r\n");
    } else {
        /* Read all sectors with multi-sector protection */
        int chunks_read = 0;
        int sectors_read = 0;
        int sector_bad = 0;

        while (status >= 0 && (status & STATUS_DRQ) && chunks_read < 8) { /* Max 8 chunks for 4 sectors */
            int wmode = chunks_read / 2;    /* sector n was written by write mode n */
            int half = chunks_read % 2;

            ReadModes[read_mode](LogPtr, 256);

            /*
             * Compare against what the write test put there. Write
             * mode m fills sector m+1 with WritePattern[m] followed by
             * WritePattern[(m+1) % 4], one pattern per 256-byte chunk.
             * Only meaningful when that sector took the full 512
             * bytes, otherwise the contents are undefined.
             */
            if (bytes_written[wmode] == 512) {
                const UBYTE *want = WritePattern[(wmode + half) % 4];
                int i;

                for (i = 0; i < 256; i++) {
                    if (LogPtr[i] != want[i]) sector_bad++;
                }
            }

            LogPtr += 256;
            chunks_read++;

            /* Report per sector, once both halves are in */
            if (half == 1) {
                sectors_read++;
                if (bytes_written[wmode] != 512) {
                    printf("    Sector %d read... not verified (write wrote %lu bytes)\r\n",
                           sectors_read, (unsigned long)bytes_written[wmode]);
                } else if (sector_bad == 0) {
                    printf("    Sector %d read... OK, data matches\r\n", sectors_read);
                } else {
                    printf("    Sector %d read... MISMATCH, %d of 512 bytes differ\r\n",
                           sectors_read, sector_bad);
                }
                sector_bad = 0;
            }

            status = *IDE_STATUS;
            if (status & STATUS_BSY) break;
        }

        /* Check for multi-sector read issue */
        if (chunks_read == 8 && (status & STATUS_DRQ)) {
            printf("  WARNING: Multi-sector read issue detected (DRQ still set after 4 sectors)\r\n");
        }

        printf("  Verification completed (%d sectors, %d chunks)\r\n", sectors_read, chunks_read);
    }

    /* Write wcda chunk header */
    {
        ULONG size = LogPtr - (chunk_start + 8);
        UBYTE *save_ptr = LogPtr;
        LogPtr = chunk_start;
        WriteChunkHeader("wcda", size);
        LogPtr = save_ptr;
    }

    return 1;
}

/*
 * Save log file
 */
int SaveLog(const char *filename)
{
    BPTR fh;
    ULONG total_size;
    LONG written;

    /* Calculate total size and update FORM header */
    total_size = LogPtr - LogBuffer - 8;
    LogBuffer[4] = (total_size >> 24) & 0xFF;
    LogBuffer[5] = (total_size >> 16) & 0xFF;
    LogBuffer[6] = (total_size >> 8) & 0xFF;
    LogBuffer[7] = total_size & 0xFF;

    fh = Open((STRPTR)filename, MODE_NEWFILE);
    if (!fh) {
        printf("Cannot open log file: %s\r\n", filename);
        return 0;
    }

    written = Write(fh, LogBuffer, LogPtr - LogBuffer);
    Close(fh);

    if (written != (LogPtr - LogBuffer)) {
        printf("Write error\r\n");
        return 0;
    }

    printf("Log saved: %s (%lu bytes)\r\n", filename, (unsigned long)(LogPtr - LogBuffer));
    return 1;
}

/*
 * CIS tuple-name lookup for human-readable output.
 */
static const char *TupleName(UBYTE code)
{
    switch (code) {
        case CISTPL_NULL:          return "CISTPL_NULL";
        case CISTPL_DEVICE:        return "CISTPL_DEVICE";
        case CISTPL_LONGLINK_MFC:  return "CISTPL_LONGLINK_MFC";
        case CISTPL_CHECKSUM:      return "CISTPL_CHECKSUM";
        case CISTPL_LONGLINK_A:    return "CISTPL_LONGLINK_A";
        case CISTPL_LONGLINK_C:    return "CISTPL_LONGLINK_C";
        case CISTPL_LINKTARGET:    return "CISTPL_LINKTARGET";
        case CISTPL_NO_LINK:       return "CISTPL_NO_LINK";
        case CISTPL_VERS_1:        return "CISTPL_VERS_1";
        case CISTPL_ALTSTR:        return "CISTPL_ALTSTR";
        case CISTPL_JEDEC_C:       return "CISTPL_JEDEC_C";
        case CISTPL_JEDEC_A:       return "CISTPL_JEDEC_A";
        case CISTPL_CONFIG:        return "CISTPL_CONFIG";
        case CISTPL_CFTABLE_ENTRY: return "CISTPL_CFTABLE_ENTRY";
        case CISTPL_DEVICE_OC:     return "CISTPL_DEVICE_OC";
        case CISTPL_MANFID:        return "CISTPL_MANFID";
        case CISTPL_FUNCID:        return "CISTPL_FUNCID";
        case CISTPL_FUNCE:         return "CISTPL_FUNCE (FUNCEXT)";
        case CISTPL_VERS_2:        return "CISTPL_VERS_2";
        case CISTPL_ORG:           return "CISTPL_ORG";
        case CISTPL_END:           return "CISTPL_END";
        default:                   return "(unknown)";
    }
}

static const char *DeviceTypeName(UBYTE type)
{
    switch (type) {
        case 0x0: return "NULL";
        case 0x1: return "ROM";
        case 0x2: return "OTPROM";
        case 0x3: return "EPROM";
        case 0x4: return "EEPROM";
        case 0x5: return "FLASH";
        case 0x6: return "SRAM";
        case 0x7: return "DRAM";
        case 0xD: return "FUNCSPEC";
        case 0xE: return "EXTEND";
        default:  return "?";
    }
}

static const char *FuncIDName(UBYTE id)
{
    switch (id) {
        case 0:  return "MULTIFUNCTION";
        case 1:  return "MEMORY";
        case 2:  return "SERIAL";
        case 3:  return "PARALLEL";
        case 4:  return "FIXED_DISK";
        case 5:  return "VIDEO";
        case 6:  return "NETWORK_LAN";
        case 7:  return "AIMS";
        case 8:  return "SCSI";
        default: return "?";
    }
}

/*
 * Device speed, bits 2..0 of the device-info byte. Three bits only,
 * bit 3 of that byte is WPS and is not part of this field. Code 7
 * means one or more extended speed bytes follow, ahead of the size
 * byte.
 */
static const char *DeviceSpeedName(UBYTE n)
{
    switch (n & 0x07) {
        case 0x0: return "no info";
        case 0x1: return "250ns";
        case 0x2: return "200ns";
        case 0x3: return "150ns";
        case 0x4: return "100ns";
        case 0x5: return "(reserved)";
        case 0x6: return "(reserved)";
        default:  return "extended";
    }
}

/*
 * Extended speed byte: bit 7 is a continuation flag, bits 6..3 select
 * a mantissa, bits 2..0 an exponent. Returns the speed in
 * nanoseconds, or 0 when the encoding is out of range.
 *
 * Example, the byte 0x4A used by the cards in issue #67: mantissa
 * index 9 = 4.0, exponent index 2 = 100ns, so 400ns.
 */
static ULONG DecodeExtSpeed(UBYTE b)
{
    /* mantissa x 10, index 0 is not defined by the spec */
    static const UWORD mant10[16] = {
        0, 10, 12, 13, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 70, 80
    };
    /* exponent unit in tenths of a nanosecond, capped at 1ms */
    static const ULONG unit10[8] = {
        10UL,          /* 1ns    */
        100UL,         /* 10ns   */
        1000UL,        /* 100ns  */
        10000UL,       /* 1us    */
        100000UL,      /* 10us   */
        1000000UL,     /* 100us  */
        10000000UL,    /* 1ms    */
        100000000UL    /* 10ms   */
    };
    UWORD m = mant10[(b >> 3) & 0x0F];
    ULONG u = unit10[b & 0x07];

    if (m == 0) return 0;

    return (ULONG)m * u / 100UL;
}

/* CISTPL_DEVICE size byte: bits 7..3 = (address_units - 1), bits
 * 2..0 = unit-size code. Returns size in bytes (matches the value
 * the OS DeviceTuple call stores in CFU_DTSize).
 */
static ULONG DecodeDeviceSize(UBYTE sz)
{
    static const ULONG unit_bytes[8] = {
        512UL,        /* 0: 512 B   */
        2048UL,       /* 1: 2 KiB   */
        8192UL,       /* 2: 8 KiB   */
        32768UL,      /* 3: 32 KiB  */
        131072UL,     /* 4: 128 KiB */
        524288UL,     /* 5: 512 KiB */
        2097152UL,    /* 6: 2 MiB   */
        0UL           /* 7: reserved */
    };
    ULONG units = ((sz >> 3) & 0x1F) + 1UL;
    return units * unit_bytes[sz & 0x07];
}

/*
 * Read one CIS byte at logical offset n.
 * PCMCIA cards in 8-bit attribute access put CIS bytes at every other
 * byte address; the odd bytes are aliased / undefined. Walk by 2.
 */
static UBYTE CisByte(int offset)
{
    return PCMCIA_ATTR[offset * 2];
}

/*
 * Map a nanosecond value to the Gayle $DAB000 bits 2-3 encoding.
 * Returns 0xFF for unsupported values.
 */
static UBYTE GayleSpeedBits(int ns)
{
    switch (ns) {
        case 250: return 0x00;
        case 150: return 0x04;
        case 100: return 0x08;
        case 720: return 0x0C;
        default:  return 0xFF;
    }
}

/*
 * Decode the current Gayle PCMCIA speed bits to a human label.
 */
static const char *GayleSpeedLabel(UBYTE cfg)
{
    switch (cfg & 0x0C) {
        case 0x00: return "250ns";
        case 0x04: return "150ns";
        case 0x08: return "100ns";
        case 0x0C: return "720ns";
    }
    return "?";
}

/*
 * Decode a device-info byte plus the size byte that follows it.
 *
 * Layout of the device-info byte (PC Card standard):
 *   bits 7..4  device type
 *   bit  3     WPS, write-protect switch active
 *   bits 2..0  device speed, code 7 means extended speed bytes follow
 *
 * When the speed code is 7, one or more extended speed bytes sit
 * between the device-info byte and the size byte, each with bit 7 set
 * when a further byte follows. Skipping them is what made earlier
 * versions read an extended speed byte as the size byte.
 *
 * data_off points at the device-info byte, avail is how many bytes of
 * the tuple are left from there.
 */
static void DecodeDeviceInfo(int data_off, int avail)
{
    static const char *unit_name[8] = {
        "512B", "2K", "8K", "32K", "128K", "512K", "2M", "reserved"
    };
    UBYTE t;
    UBYTE speed;
    int off = data_off;
    int used = 1;

    if (avail < 1) return;

    t = CisByte(off++);
    speed = t & 0x07;

    printf("    type=0x%X (%s), wps=%d, speed=0x%X (%s)\r\n",
           (t >> 4) & 0xF, DeviceTypeName((t >> 4) & 0xF),
           (t & 0x08) ? 1 : 0,
           speed, DeviceSpeedName(speed));

    if (speed == 0x07) {
        /* Extended speed, chained while bit 7 stays set */
        for (;;) {
            UBYTE e;
            ULONG ns;

            if (used >= avail) return;
            e = CisByte(off++);
            used++;

            ns = DecodeExtSpeed(e);
            if (ns) {
                printf("    ext-speed=0x%02X (%lu ns)\r\n", (int)e, ns);
            } else {
                printf("    ext-speed=0x%02X (reserved encoding)\r\n", (int)e);
            }

            if (!(e & 0x80)) break;
        }
    }

    if (used < avail) {
        UBYTE sz = CisByte(off);
        ULONG nb = DecodeDeviceSize(sz);
        ULONG units = ((sz >> 3) & 0x1F) + 1UL;
        UBYTE ucode = sz & 0x07;
        printf("    size=0x%08lX (%lu B), size_code=0x%02X  "
               "(units=%lu, unit=0x%X=%s)\r\n",
               nb, nb, (int)sz, units, (int)ucode, unit_name[ucode]);
    }
}

/* CISTPL_DEVICE: device-info byte first */
static void DecodeDevice(int data_off, UBYTE link)
{
    DecodeDeviceInfo(data_off, (int)link);
}

/*
 * CISTPL_DEVICE_OC: one "other conditions" byte comes first, then the
 * same device-info layout. Decoding it as a plain CISTPL_DEVICE, as
 * earlier versions did, shifted every field by one byte.
 *
 * Other-conditions byte:
 *   bits 1..0  Vcc used, 0 = 5V, 1 = 3.3V, 2 = X.XV
 *   bit  2     MWAIT honoured
 *   bit  7     another other-conditions byte follows
 */
static void DecodeDeviceOC(int data_off, UBYTE link)
{
    static const char *vcc_name[4] = { "5V", "3.3V", "X.XV", "(reserved)" };
    int off = data_off;
    int used = 0;

    while (used < (int)link) {
        UBYTE oc = CisByte(off++);
        used++;

        printf("    other-cond=0x%02X (Vcc=%s, mwait=%d)\r\n",
               (int)oc, vcc_name[oc & 0x03], (oc & 0x04) ? 1 : 0);

        if (!(oc & 0x80)) break;
    }

    DecodeDeviceInfo(off, (int)link - used);
}

static void DecodeFuncID(int data_off, UBYTE link)
{
    UBYTE id;
    if (link < 1) return;
    id = CisByte(data_off);
    printf("    function=0x%02X (%s)\r\n", id, FuncIDName(id));
    if (link >= 2)
        printf("    sysinit=0x%02X\r\n", CisByte(data_off + 1));
}

static void DecodeFuncE(int data_off, UBYTE link)
{
    UBYTE type, iface;
    const char *iname;
    if (link < 1) {
        printf("    (no data)\r\n");
        return;
    }
    type = CisByte(data_off);
    printf("    extension_type=0x%02X", type);
    if (type == 1 && link >= 2) {
        iface = CisByte(data_off + 1);
        iname = "?";
        if (iface == 0) iname = "(undefined)";
        else if (iface == 1) iname = "IDE";
        printf(" (Disk Interface), interface=0x%02X (%s)", iface, iname);
    }
    printf("\r\n");
}

static void DecodeVers1(int data_off, UBYTE link)
{
    int i, line, in_str;
    UBYTE c;
    if (link < 2) return;
    printf("    major=%d, minor=%d\r\n",
           (int)CisByte(data_off), (int)CisByte(data_off + 1));
    line = 0;
    i = 2;
    while (i < link) {
        printf("    string[%d]: \"", line++);
        in_str = 1;
        while (i < link && in_str) {
            c = CisByte(data_off + i++);
            if (c == 0 || c == 0xFF) {
                in_str = 0;
            } else if (c >= 32 && c < 127) {
                putchar(c);
            } else {
                printf("\\x%02X", c);
            }
        }
        printf("\"\r\n");
        if (i < link && CisByte(data_off + i - 1) == 0xFF) break;
    }
}

static void DecodeManfID(int data_off, UBYTE link)
{
    UWORD mfg, prod;
    if (link < 4) return;
    mfg  = CisByte(data_off) | (CisByte(data_off + 1) << 8);
    prod = CisByte(data_off + 2) | (CisByte(data_off + 3) << 8);
    printf("    manufacturer=0x%04X, product=0x%04X\r\n", mfg, prod);
}

static void HexDumpTuple(int data_off, UBYTE link)
{
    int i;
    if (link == 0) return;
    printf("    data:");
    for (i = 0; i < link && i < 32; i++) {
        if (i > 0 && (i % 16) == 0) printf("\r\n         ");
        printf(" %02X", CisByte(data_off + i));
    }
    if (link > 32) printf(" ...");
    printf("\r\n");
}

/*
 * Walk the PCMCIA attribute-memory CIS and print each tuple in
 * human-readable form. Direct memory read at 0x00A00000, no
 * card.resource interaction, no OwnCard, no arbitration with
 * compactflash.device or other handlers. Safe to run on cards that
 * make the regular driver path hang.
 *
 * speed_ns: 0 leaves Gayle PCMCIA timing untouched; 100/150/250/720
 * temporarily overrides $DAB000 bits 2-3 for the duration of the scan
 * (restored on return). Useful for diagnosing cards whose CIS reads
 * are unstable at the default speed - rerun -cis with each value and
 * compare results.
 *
 * Tuple stride: each CIS byte is at attribute_base + n*2 (PCMCIA 8-bit
 * attribute access aliases odd bytes). Walk terminates on CISTPL_END
 * or after 32 tuples / 512 logical bytes - whichever comes first.
 */
int DumpCIS(int speed_ns)
{
    int pos = 0;
    int count = 0;
    UBYTE code, link;
    UBYTE saved_cfg = 0;
    int changed = 0;

    if (!CardPresent()) {
        printf("No card inserted (GAYLE CCDET clear).\r\n");
        return 5;
    }

    if (speed_ns != 0) {
        UBYTE want = GayleSpeedBits(speed_ns);
        if (want == 0xFF) {
            printf("Invalid Gayle PCMCIA speed %d (use 100, 150, 250, or 720)\r\n",
                   speed_ns);
            return 5;
        }
        saved_cfg = *GAYLE_CONFIG;
        *GAYLE_CONFIG = (saved_cfg & 0xF3) | want;
        changed = 1;
    }

    printf("CIS dump (direct read from PCMCIA attribute memory at 0x%08lX):\r\n",
           (ULONG)PCMCIA_ATTR);
    printf("Gayle PCMCIA timing: %s%s\r\n",
           GayleSpeedLabel(*GAYLE_CONFIG),
           changed ? " (override)" : " (current)");
    printf("\r\n");

    while (pos < 512 && count < 32) {
        code = CisByte(pos);

        if (code == CISTPL_END) {
            printf("0x%03X: 0x%02X %s\r\n", pos, code, TupleName(code));
            goto done;
        }
        if (code == CISTPL_NULL) {
            pos += 1;  /* NULL has no link byte */
            continue;
        }

        link = CisByte(pos + 1);
        printf("0x%03X: 0x%02X %s (length=%d)\r\n",
               pos, (int)code, TupleName(code), (int)link);

        switch (code) {
            case CISTPL_DEVICE:
                DecodeDevice(pos + 2, link);
                break;
            case CISTPL_DEVICE_OC:
                DecodeDeviceOC(pos + 2, link);
                break;
            case CISTPL_FUNCID:
                DecodeFuncID(pos + 2, link);
                break;
            case CISTPL_FUNCE:
                DecodeFuncE(pos + 2, link);
                break;
            case CISTPL_VERS_1:
            case CISTPL_VERS_2:
                DecodeVers1(pos + 2, link);
                break;
            case CISTPL_MANFID:
                DecodeManfID(pos + 2, link);
                break;
            default:
                HexDumpTuple(pos + 2, link);
                break;
        }

        pos += 2 + link;
        count++;
    }

    printf("\r\n(end of dump - %s)\r\n",
           count >= 32 ? "tuple limit reached" : "buffer limit reached");

done:
    if (changed) {
        *GAYLE_CONFIG = saved_cfg;
    }
    return 0;
}

/*
 * Standalone IDENTIFY read-stability run, the -identify mode.
 *
 * Console only, no log file, like -cis. This is the test worth repeating
 * on a suspect card, so it is reachable on its own instead of only as
 * part of the full battery: raising the run count or trying another
 * timing does not mean sitting through the read-mode, pattern and write
 * tests again.
 *
 * Needs the card in I/O configuration, which the full run sets up too,
 * and puts it back afterwards.
 */
int IdentifyStability(int speed, int sweep, int runs)
{
    UBYTE orig_config;
    UBYTE gayle_saved;
    int rc;

    if (!OpenTimer()) {
        printf("Cannot open timer.device\r\n");
        return 10;
    }

    if (!CardPresent()) {
        printf("No card inserted.\r\n");
        CloseTimer();
        return 5;
    }

    printf("pcmciacheck " STR(VERSION) " - IDENTIFY read stability\r\n");

    gayle_saved = GayleSetSpeed(speed);
    if (!sweep) {
        printf("Gayle PCMCIA timing: %s%s\r\n", GayleCurrentLabel(),
               speed ? " (override)" : " (current)");
    }

    orig_config = *PCMCIA_CONFIG;
    *PCMCIA_CONFIG = 0x01;              /* I/O mode */

    rc = sweep ? SweepReadStability(runs) : TestReadStability(runs);

    *PCMCIA_CONFIG = orig_config;
    GayleRestore(gayle_saved);
    CloseTimer();

    return rc;
}

int main(int argc, char **argv)
{
    int working_read_mode;
    UBYTE orig_config;
    int enable_write_test = 0;
    int gayle_speed = 0;              /* 0 = leave the current setting */
    int gayle_sweep = 0;
    UBYTE gayle_saved;
    char *logfile = NULL;
    int i;

    if (argc < 2) {
        printf("pcmciacheck " STR(VERSION) " - PCMCIA/CF Hardware Test Tool\r\n");
        printf("Usage: pcmciacheck [-w] [-s <speed>] <logfile>\r\n");
        printf("       pcmciacheck -identify [speed] [-r <runs>]\r\n");
        printf("       pcmciacheck -cis [speed]\r\n");
        printf("\r\n");
        printf("Tests different data access modes and creates diagnostic log.\r\n");
        printf("  -w           Enable write testing (WARNING: may overwrite data on sectors 1-5)\r\n");
        printf("  -s <speed>   Gayle PCMCIA timing for the run: 100|150|250|720, or\r\n");
        printf("               'all' to repeat the capture at each of them and log\r\n");
        printf("               every timing. Not combinable with -w. Restored on exit.\r\n");
        printf("               Diagnostic only, the driver programs this register\r\n");
        printf("               itself via card.resource.\r\n");
        printf("\r\n");
        printf("  -identify [speed] [-r <runs>]\r\n");
        printf("               Read IDENTIFY several times per mode and compare, the\r\n");
        printf("               check the driver makes before accepting a card. Console\r\n");
        printf("               only, no log file. Optional speed = 100|150|250|720, or\r\n");
        printf("               'all' to test at each of them and print a matrix.\r\n");
        printf("               -r sets the runs per mode (%d..%d, default %d).\r\n",
               STAB_RUNS_MIN, STAB_RUNS_MAX, STAB_RUNS_DEFAULT);
        printf("\r\n");
        printf("  -cis [speed] Dump PCMCIA CIS tuples from attribute memory and exit.\r\n");
        printf("               Optional speed = 100|150|250|720 overrides Gayle PCMCIA\r\n");
        printf("               memory timing for the scan (default: current setting).\r\n");
        return 5;
    }

    /* -cis: standalone CIS dump, no logfile, no transfer-mode tests */
    if (strcmp(argv[1], "-cis") == 0) {
        int speed = 0;
        if (argc > 2) {
            if (strcmp(argv[2], "100") == 0) speed = 100;
            else if (strcmp(argv[2], "150") == 0) speed = 150;
            else if (strcmp(argv[2], "250") == 0) speed = 250;
            else if (strcmp(argv[2], "720") == 0) speed = 720;
            else {
                printf("Invalid Gayle PCMCIA speed '%s' (use 100, 150, 250, or 720)\r\n",
                       argv[2]);
                return 5;
            }
        }
        return DumpCIS(speed);
    }

    /* -identify: standalone read-stability run, no logfile */
    if (strcmp(argv[1], "-identify") == 0) {
        int speed = 0;
        int sweep = 0;
        int runs = STAB_RUNS_DEFAULT;

        for (i = 2; i < argc; i++) {
            if (strcmp(argv[i], "-r") == 0) {
                if (i + 1 >= argc) {
                    printf("Error: -r needs a run count\r\n");
                    return 5;
                }
                runs = atoi(argv[++i]);
                if (runs < STAB_RUNS_MIN || runs > STAB_RUNS_MAX) {
                    printf("Invalid run count '%s' (use %d..%d)\r\n",
                           argv[i], STAB_RUNS_MIN, STAB_RUNS_MAX);
                    return 5;
                }
            } else if (strcmp(argv[i], "all") == 0) {
                sweep = 1;
            } else {
                int j;
                speed = atoi(argv[i]);
                for (j = 0; j < GAYLE_SPEED_COUNT; j++) {
                    if (GayleSpeeds[j] == speed) break;
                }
                if (j == GAYLE_SPEED_COUNT) {
                    printf("Invalid Gayle PCMCIA speed '%s' (use 100, 150, 250, 720 or all)\r\n",
                           argv[i]);
                    return 5;
                }
            }
        }

        return IdentifyStability(speed, sweep, runs);
    }

    /* Parse command line arguments */
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-w") == 0) {
            enable_write_test = 1;
        } else if (strcmp(argv[i], "-s") == 0) {
            if (i + 1 >= argc) {
                printf("Error: -s needs a speed\r\n");
                return 5;
            }
            i++;
            if (strcmp(argv[i], "all") == 0) {
                gayle_sweep = 1;
            } else {
                int j;
                gayle_speed = atoi(argv[i]);
                for (j = 0; j < GAYLE_SPEED_COUNT; j++) {
                    if (GayleSpeeds[j] == gayle_speed) break;
                }
                if (j == GAYLE_SPEED_COUNT) {
                    printf("Invalid Gayle PCMCIA speed '%s' (use 100, 150, 250 or 720)\r\n",
                           argv[i]);
                    return 5;
                }
            }
        } else if (logfile == NULL) {
            logfile = argv[i];
        }
    }

    if (logfile == NULL) {
        printf("Error: No logfile specified\r\n");
        printf("Usage: pcmciacheck [-w] [-s <speed>] <logfile>\r\n");
        printf("       pcmciacheck -identify [speed] [-r <runs>]\r\n");
        printf("       pcmciacheck -cis [speed]\r\n");
        return 5;
    }

    /*
     * Writing sectors 1-5 once per timing gains nothing, and the mode the
     * read-back uses can differ between timings, which would leave the
     * verification result ambiguous.
     */
    if (enable_write_test && gayle_sweep) {
        printf("-w cannot be combined with -s all: the write test would rewrite\r\n");
        printf("sectors 1-5 at each timing. Run them separately.\r\n");
        return 5;
    }

    if (!OpenTimer()) {
        printf("Cannot open timer.device\r\n");
        return 10;
    }

    /* Check for card */
    if (!CardPresent()) {
        printf("No card inserted.\r\n");
        CloseTimer();
        return 5;
    }

    /* Allocate log buffer */
    LogBuffer = AllocMem(LOG_SIZE, MEMF_PUBLIC | MEMF_CLEAR);
    if (!LogBuffer) {
        printf("Cannot allocate memory\r\n");
        CloseTimer();
        return 10;
    }

    LogPtr = LogBuffer;

    printf("pcmciacheck " STR(VERSION) " - Testing card...\r\n");

    /*
     * Gayle PCMCIA timing. Pinned for the whole run when -s <speed> was
     * given, restored before returning. The sweep programs it per column
     * and restores it itself.
     */
    gayle_saved = GayleSetSpeed(gayle_speed);
    printf("Gayle PCMCIA timing: %s%s\r\n", GayleCurrentLabel(),
           gayle_speed ? " (override)" : " (current)");

    /* Write IFF header */
    memcpy(LogPtr, "FORM", 4);
    LogPtr += 4;
    LogPtr += 4;  /* Size placeholder */
    /*
     * pcc3: read modes now mirror the driver's transfer modes, so the
     * per-mode blocks are not comparable with pcc2 logs.
     */
    memcpy(LogPtr, "pcc3", 4);
    LogPtr += 4;

    /* Save and set card config */
    orig_config = *PCMCIA_CONFIG;
    *PCMCIA_CONFIG = 0x01;  /* Enable I/O mode */

    /*
     * With -s all the capture repeats at every Gayle timing, so the log
     * can show a fault that only appears at some of them. Each pass
     * opens with its own gspd chunk, which makes gspd the group marker:
     * a reader walking the chunks in order starts a new timing group at
     * every gspd. A single-timing run writes exactly one group, so the
     * layout is unchanged for it.
     */
    for (i = 0; i < (gayle_sweep ? GAYLE_SPEED_COUNT : 1); i++) {
        int this_speed = gayle_speed;

        if (gayle_sweep) {
            this_speed = GayleSpeeds[i];
            GayleSetSpeed(this_speed);
            DelayMS(1);
            printf("\r\nGayle PCMCIA timing: %s (override)\r\n",
                   GayleCurrentLabel());
        }

        /*
         * gspd: the timing this group used in nanoseconds, and whether
         * -s chose it (1) or it is the system's own setting (0).
         */
        WriteChunkHeader("gspd", 4);
        PutLogWord((UWORD)GayleCurrentSpeed());
        PutLogWord((UWORD)(this_speed ? 1 : 0));

        printf("Testing read modes...\r\n");
        if (TestReadModes(&working_read_mode)) {
            printf("  Working read mode: %d\r\n", working_read_mode);
        } else {
            /*
             * Nothing plausible came back in any mode. Saying "working
             * read mode: 0" here would contradict that; mode 0 is only
             * carried forward so the remaining tests have something to
             * use.
             */
            printf("  Working read mode: none, no mode returned plausible data\r\n");
            printf("  (using mode %d for the remaining tests)\r\n", working_read_mode);
        }

        printf("Testing transfer mode patterns (cfd.s style)...\r\n");
        LogPatternTest();
    }

    if (enable_write_test) {
        printf("Testing write modes...\r\n");
        TestWriteModes(working_read_mode);
        printf("Write testing completed.\r\n");
    } else {
        printf("Write testing disabled (use -w to enable)\r\n");
    }

    /* Restore card config and Gayle timing */
    printf("Restoring card configuration...\r\n");
    *PCMCIA_CONFIG = orig_config;
    GayleRestore(gayle_saved);

    /* Save log */
    printf("Saving log file...\r\n");
    SaveLog(logfile);

    printf("Test completed successfully.\r\n");
    FreeMem(LogBuffer, LOG_SIZE);
    CloseTimer();

    return 0;
}

