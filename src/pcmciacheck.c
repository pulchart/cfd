/*
 * pcmciacheck - PCMCIA/CF Hardware Test Tool
 *
 * Tests different data access modes (byte/word) for PCMCIA CF cards
 * and creates a diagnostic log file.
 *
 * Based on original pcmciacheck 1.17 (29.08.2002) by Torsten Jager
 * Recreated in C for compactflash.device project
 *
 * Build: make pcmciacheck (requires vbcc + NDK)
 * Usage: pcmciacheck <logfile>
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
 * Pattern-based transfer mode test (mirrors cfd.s RWTest)
 * Tests all 16 combinations of write/read modes with simple patterns
 * Returns bitfield of working mode combinations
 */
UWORD TestTransferModes(void)
{
    volatile UBYTE *a0 = (volatile UBYTE *)(IDE_BASE + 0x04);  /* IDEAddr + 4 */
    volatile UBYTE *a1 = (volatile UBYTE *)((ULONG)a0 + 0x10000); /* a0 + $10000 */
    UWORD test_pattern = 0x1234;
    UWORD working_modes = 0;
    int write_mode, read_mode, test_run;
    UWORD written_data, read_data;

    /* Test each write/read mode combination twice (like cfd.s) */
    for (test_run = 0; test_run < 2; test_run++) {
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
                    working_modes |= (1 << mode_combo);
                }

                /* Update test pattern for next iteration (like cfd.s) */
                test_pattern += 0x0202;
            }
        }
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
 * Read 256 bytes using WORD access (mode 0)
 * Matches assembly: 16 iterations × 8 word reads = 128 words = 256 bytes
 */
void ReadMode0(UBYTE *dest)
{
    volatile UWORD *src = IDE_DATA;
    UWORD *d = (UWORD *)dest;
    int i;

    for (i = 0; i < 128; i++) {
        *d++ = *src;
    }
}

/*
 * Read 256 bytes using BYTE access from data register (mode 1)
 * Matches assembly: 16 iterations × 16 byte reads = 256 bytes
 */
void ReadMode1(UBYTE *dest)
{
    volatile UBYTE *src = IDE_DATA_BYTE;
    int i;

    for (i = 0; i < 256; i++) {
        *dest++ = *src;
    }
}

/*
 * Read 256 bytes using alternating BYTE access (mode 2)
 * Reads low byte from offset 8, high byte from offset 8+0x10001
 * Matches assembly: 16 iterations × 16 byte reads = 256 bytes
 */
void ReadMode2(UBYTE *dest)
{
    volatile UBYTE *src_lo = IDE_DATA_ALT;
    volatile UBYTE *src_hi = (volatile UBYTE *)(IDE_BASE + 0x08 + 0x10001);
    int i;

    for (i = 0; i < 128; i++) {
        *dest++ = *src_lo;
        *dest++ = *src_hi;
    }
}

/*
 * Read 256 bytes using BYTE access from offset 8 (mode 3)
 * Matches assembly: 16 iterations × 16 byte reads = 256 bytes
 */
void ReadMode3(UBYTE *dest)
{
    volatile UBYTE *src = IDE_DATA_ALT;
    int i;

    for (i = 0; i < 256; i++) {
        *dest++ = *src;
    }
}

/*
 * Write 256 bytes using WORD access (mode 0)
 */
void WriteMode0(UBYTE *src)
{
    volatile UWORD *dest = IDE_DATA;
    UWORD *s = (UWORD *)src;
    int i;

    for (i = 0; i < 128; i++) {
        *dest = *s++;
    }
}

/*
 * Write 256 bytes using BYTE access (mode 1)
 */
void WriteMode1(UBYTE *src)
{
    volatile UBYTE *dest = IDE_DATA_BYTE;
    int i;

    for (i = 0; i < 256; i++) {
        *dest = *src++;
    }
}

/*
 * Write 256 bytes using alternating BYTE access (mode 2)
 */
void WriteMode2(UBYTE *src)
{
    volatile UBYTE *dest_lo = IDE_DATA_ALT;
    volatile UBYTE *dest_hi = (volatile UBYTE *)(IDE_BASE + 0x08 + 0x10001);
    int i;

    for (i = 0; i < 128; i++) {
        *dest_lo = *src++;
        *dest_hi = *src++;
    }
}

/*
 * Write 256 bytes using BYTE access from offset 8 (mode 3)
 */
void WriteMode3(UBYTE *src)
{
    volatile UBYTE *dest = IDE_DATA_ALT;
    int i;

    for (i = 0; i < 256; i++) {
        *dest = *src++;
    }
}

/*
 * Read 256 bytes using memory mapped access (mode 4)
 * Reads from PCMCIA common memory at offset 1024
 */
void ReadMode4(UBYTE *dest)
{
    volatile UWORD *src = PCMCIA_MEM_DATA;
    UWORD *d = (UWORD *)dest;
    int i;

    for (i = 0; i < 128; i++) {
        *d++ = *src++;
    }
}

/*
 * Write 256 bytes using memory mapped access (mode 4)
 * Writes to PCMCIA common memory at offset 1024
 */
void WriteMode4(UBYTE *src)
{
    volatile UWORD *dest = PCMCIA_MEM_DATA;
    UWORD *s = (UWORD *)src;
    int i;

    for (i = 0; i < 128; i++) {
        *dest++ = *s++;
    }
}

/* Function pointer arrays for read/write modes */
ReadFunc ReadModes[5] = { ReadMode0, ReadMode1, ReadMode2, ReadMode3, ReadMode4 };
WriteFunc WriteModes[5] = { WriteMode0, WriteMode1, WriteMode2, WriteMode3, WriteMode4 };

/*
 * Test read modes with IDENTIFY DEVICE command
 */
int TestReadModes(int *working_mode)
{
    int mode;
    int status;
    UBYTE *chunk_start;
    char chunk_id[5] = "rdc0";

    *working_mode = -1;

    for (mode = 0; mode < 4; mode++) {
        printf("  Testing read mode %d...", mode);
        chunk_id[3] = '0' + mode;
        chunk_start = LogPtr;

        /* Reserve space for chunk header */
        LogPtr += 8;

        /* Setup IDENTIFY DEVICE command */
        *IDE_DEVHEAD = 0xE0;  /* LBA, drive 0 */
        *IDE_COMMAND = ATA_IDENTIFY;

        status = WaitReady(30000);
        if (status < 0) {
            printf(" TIMEOUT\r\n");
            /* Timeout or card removed - write empty chunk */
            WriteChunkHeader(chunk_id, 0);
            LogPtr = chunk_start + 8;
            continue;
        }

        /* Read data in 256-byte chunks while DRQ is set */
        /* Matches assembly behavior: read 256 bytes, check DRQ, repeat */
        /* Limit to 2 chunks (512 bytes) for IDENTIFY command */
        int chunks_read = 0;
        while (status >= 0 && (status & STATUS_DRQ) && chunks_read < 2) {
            ReadModes[mode](LogPtr);
            LogPtr += 256;
            chunks_read++;
            status = *IDE_STATUS;
            if (status & STATUS_BSY) break;
        }

        /* Check for multi-sector read issue */
        BOOL has_multisector_issue = (chunks_read == 2 && (status & STATUS_DRQ));

        /* Calculate chunk size and write header */
        {
            ULONG size = LogPtr - (chunk_start + 8);
            UBYTE *save_ptr = LogPtr;
            LogPtr = chunk_start;
            WriteChunkHeader(chunk_id, size);
            LogPtr = save_ptr;

            /* Remember first working mode */
            if (size == 512 && *working_mode < 0) {
                *working_mode = mode;
            }

            /* Print status based on bytes read */
            if (size == 512) {
                printf(" OK (%lu bytes)", (unsigned long)size);
            } else {
                printf(" PARTIAL (%lu bytes)", (unsigned long)size);
            }

            /* Append multi-sector warning if detected */
            if (has_multisector_issue) {
                printf(" - WARNING: multi-sector issue detected");
            }

            printf("\r\n");
        }
    }

    /* Test mode 4 (memory mapped) - requires different config */
    {
        UBYTE orig_config = *PCMCIA_CONFIG;

        printf("  Testing read mode 4 (MMAP)...");
        chunk_id[3] = '4';
        chunk_start = LogPtr;
        LogPtr += 8;

        /* Switch to memory-mapped mode */
        *PCMCIA_CONFIG = 0x40;
        DelayMS(1);  /* Wait for config change */

        /* Setup IDENTIFY DEVICE command via memory-mapped registers */
        *MMAP_DEVHEAD = 0xE0;
        *MMAP_COMMAND = ATA_IDENTIFY;

        /* Wait for ready using memory-mapped status */
        {
            int timeout = 300;  /* 30 seconds */
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

        if (status < 0) {
            printf(" TIMEOUT\r\n");
            WriteChunkHeader(chunk_id, 0);
            LogPtr = chunk_start + 8;
        } else {
            int chunks_read = 0;
            while (status >= 0 && (status & STATUS_DRQ) && chunks_read < 2) {
                ReadMode4(LogPtr);
                LogPtr += 256;
                chunks_read++;
                status = *MMAP_STATUS;
                if (status & STATUS_BSY) break;
            }

            {
                ULONG size = LogPtr - (chunk_start + 8);
                UBYTE *save_ptr = LogPtr;
                LogPtr = chunk_start;
                WriteChunkHeader(chunk_id, size);
                LogPtr = save_ptr;
                printf(" %s (%lu bytes)\r\n", (size == 512) ? "OK" : "PARTIAL", (unsigned long)size);
            }
        }

        /* Restore I/O mode config */
        *PCMCIA_CONFIG = orig_config;
        DelayMS(1);
    }

    if (*working_mode < 0) {
        *working_mode = 0;  /* Default to mode 0 */
    }

    return 1;
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
                WriteModes[mode](pattern_ptr);
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
                    WriteMode4(pattern_ptr);
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
        BOOL has_multisector_issue = FALSE;

        while (status >= 0 && (status & STATUS_DRQ) && chunks_read < 8) { /* Max 8 chunks for 4 sectors */
            ReadModes[read_mode](LogPtr);
            LogPtr += 256;
            chunks_read++;

            /* Report progress every 2 chunks (per sector) */
            if (chunks_read % 2 == 0) {
                sectors_read++;
                printf("    Sector %d read... OK\r\n", sectors_read);
            }

            status = *IDE_STATUS;
            if (status & STATUS_BSY) break;
        }

        /* Check for multi-sector read issue */
        if (chunks_read == 8 && (status & STATUS_DRQ)) {
            has_multisector_issue = TRUE;
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

int main(int argc, char **argv)
{
    int working_read_mode;
    UBYTE orig_config;
    int enable_write_test = 0;
    char *logfile = NULL;
    int i;

    if (argc < 2) {
        printf("pcmciacheck " STR(VERSION) " - PCMCIA/CF Hardware Test Tool\r\n");
        printf("Usage: pcmciacheck [-w] <logfile>\r\n");
        printf("\r\n");
        printf("Tests different data access modes and creates diagnostic log.\r\n");
        printf("  -w  Enable write testing (WARNING: may overwrite data on sectors 1-4)\r\n");
        return 5;
    }

    /* Parse command line arguments */
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-w") == 0) {
            enable_write_test = 1;
        } else if (logfile == NULL) {
            logfile = argv[i];
        }
    }

    if (logfile == NULL) {
        printf("Error: No logfile specified\r\n");
        printf("Usage: pcmciacheck [-w] <logfile>\r\n");
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

    /* Write IFF header */
    memcpy(LogPtr, "FORM", 4);
    LogPtr += 4;
    LogPtr += 4;  /* Size placeholder */
    memcpy(LogPtr, "pcc2", 4);
    LogPtr += 4;

    /* Save and set card config */
    orig_config = *PCMCIA_CONFIG;
    *PCMCIA_CONFIG = 0x01;  /* Enable I/O mode */

    /* Run tests */
    printf("Testing read modes...\r\n");
    TestReadModes(&working_read_mode);
    printf("  Working read mode: %d\r\n", working_read_mode);

    printf("Testing transfer mode patterns (cfd.s style)...\r\n");
    LogPatternTest();

    if (enable_write_test) {
        printf("Testing write modes...\r\n");
        TestWriteModes(working_read_mode);
        printf("Write testing completed.\r\n");
    } else {
        printf("Write testing disabled (use -w to enable)\r\n");
    }

    /* Restore card config */
    printf("Restoring card configuration...\r\n");
    *PCMCIA_CONFIG = orig_config;

    /* Save log */
    printf("Saving log file...\r\n");
    SaveLog(logfile);

    printf("Test completed successfully.\r\n");
    FreeMem(LogBuffer, LOG_SIZE);
    CloseTimer();

    return 0;
}

