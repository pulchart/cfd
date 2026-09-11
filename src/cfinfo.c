/*
 * CFInfo - CompactFlash Card Information Tool
 * 
 * Displays detailed information about CF cards in the PCMCIA slot
 * using the compactflash.device driver.
 *
 * Build: make cfinfo (requires vbcc + NDK)
 * Usage: CFInfo [unit]
 *
 */

#include "common.h"

const char version[] = MAKE_VERSION_STRING("CFInfo");

#include <exec/types.h>
#include <exec/memory.h>
#include <exec/io.h>
#include <devices/scsidisk.h>
#include <dos/dos.h>

#include <proto/exec.h>
#include <proto/dos.h>

#include <dos/dosextens.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEVICE_NAME "compactflash.device"
#define IDENTIFY_BUFFER_SIZE 512

/* SCSI commands supported by compactflash.device */
#define SCSI_TEST_UNIT_READY 0x00
#define SCSI_READ_CAPACITY   0x25
#define ATA_IDENTIFY         0xEC  /* Vendor-specific passthrough (v1.36+) */
#define CFD_GETCONFIG        0xED  /* Driver config passthrough (v1.37+) */

/* CFD_GETCONFIG response structure (extensible)
 *
 * The first field (struct_size) indicates the total structure size.
 * Future driver versions may extend this structure with more fields.
 * Clients should check struct_size before accessing fields beyond
 * the minimum known size.
 */
struct CFDConfig {
    UWORD struct_size;      /* offset 0-1: structure size (for versioning) */
    UBYTE version_major;    /* offset 2: driver major version */
    UBYTE version_minor;    /* offset 3: driver minor version */
    UWORD open_flags;       /* offset 4-5: mount Flags field */
    UWORD multi_size;       /* offset 6-7: firmware multi-sector */
    UWORD multi_size_rw;    /* offset 8-9: actual multi-sector used */
    UBYTE receive_mode;     /* offset 10: read transfer mode */
    UBYTE write_mode;       /* offset 11: write transfer mode */
    /* Future fields may be added here - check struct_size */
};

#define CFD_CONFIG_SIZE_V137 12   /* v1.37 structure size */
#define CFD_CONFIG_BUFFER_SIZE 64 /* request larger buffer for future compat */

/* IDENTIFY data word offsets */
#define ID_CONFIG       0   /* General configuration */
#define ID_CYLS         1   /* Number of cylinders */
#define ID_HEADS        3   /* Number of heads */
#define ID_SECTORS      6   /* Sectors per track */
#define ID_SERIAL       10  /* Serial number (20 chars, words 10-19) */
#define ID_FIRMWARE     23  /* Firmware revision (8 chars, words 23-26) */
#define ID_MODEL        27  /* Model number (40 chars, words 27-46) */
#define ID_MAXMULTI     47  /* Max sectors per interrupt (R/W Multiple) */
#define ID_CAPABILITIES 49  /* Capabilities */
#define ID_PIO_OLD      51  /* PIO timing mode (old) */
#define ID_MULTISECT    59  /* Multiple sector setting */
#define ID_LBA_SECTORS  60  /* Total LBA sectors (words 60-61) */
#define ID_PIO_MODES    64  /* Advanced PIO modes supported */
#define ID_CMD_SET1     82  /* Command set supported (1) */
#define ID_CMD_SET2     83  /* Command set supported (2) */
#define ID_CMD_EXT      84  /* Command set extension */
#define ID_CMD_EN1      85  /* Command set enabled (1) */
#define ID_CMD_EN2      86  /* Command set enabled (2) */
#define ID_UDMA_MODES   88  /* Ultra DMA modes */
#define ID_CFA_IDE     163  /* CF Advanced True IDE Timing */
#define ID_CFA_TIMING  164  /* CF Advanced PCMCIA I/O and Memory Timing */

struct MsgPort *mp = NULL;
struct IOStdReq *io = NULL;
UBYTE *data_buf = NULL;
UBYTE *scsi_sense = NULL;
struct SCSICmd *scsi_cmd = NULL;
UBYTE scsi_cdb[12];

/* --- console pager -------------------------------------------------
 *
 * One screenful at a time: any key continues, Q stops the rest of the
 * report. Paging is on only when input and output are the same console,
 * and only when that console reports a plausible height; a redirected
 * or silent stream scrolls as before.
 */
#define PAGE_PROMPT "-- more -- (any key, Q quits)"

static BPTR page_in, page_out;
static int page_rows;           /* usable lines per page, 0 = no paging */
static int page_left;
static int page_stop;           /* the reader asked to stop */
static char page_erase[sizeof(PAGE_PROMPT) + 1];    /* CR, blanks, CR */

/* Ask the console how tall its window is. RAW mode must already be set.
 * WINDOW STATUS REQUEST is answered by a WINDOW BOUNDS REPORT,
 * CSI <p1>;<p2>;<p3>;<p4> SP r, whose third field is the height.
 */
static int page_query_rows(void)
{
    int fields = 0, num = 0, rows = 0, guard = 40;
    UBYTE c;

    Write(page_out, "\033[ q", 4);
    while (guard--) {
        if (!WaitForChar(page_in, 200000)) return 0;   /* console stayed silent */
        if (Read(page_in, &c, 1) != 1) return 0;
        if (c == 'r') return (fields >= 3) ? rows : 0; /* too short to trust */
        if (c == ';') {
            if (++fields == 3) rows = num;
            num = 0;
            continue;
        }
        if (c < '0' || c > '9') continue;
        if (num < 1000) num = num * 10 + (c - '0');    /* absurd: stop adding */
    }
    return 0;
}

static void page_begin(void)
{
    struct FileHandle *in, *out;
    int rows;

    page_rows = page_left = page_stop = 0;
    page_in = Input();
    page_out = Output();
    if (!page_in || !page_out) return;
    if (!IsInteractive(page_in) || !IsInteractive(page_out)) return;

    /* The query is written to the output and answered on the input, so both
     * must be the same handler. Equal fh_Type means one console; a redirected
     * ">SER:" is a different port and gets neither the query nor a pause.
     */
    in = (struct FileHandle *)BADDR(page_in);
    out = (struct FileHandle *)BADDR(page_out);
    if (in->fh_Type != out->fh_Type) return;

    SetMode(page_in, 1);                /* RAW for the query and every keypress */
    rows = page_query_rows() - 1;       /* the prompt needs a line of its own */
    if (rows < 4 || rows > 200) {       /* implausible height, do not guess */
        SetMode(page_in, 0);
        return;
    }
    page_rows = page_left = rows;

    page_erase[0] = '\r';
    memset(page_erase + 1, ' ', sizeof(PAGE_PROMPT) - 1);
    page_erase[sizeof(PAGE_PROMPT)] = '\r';
}

static void page_end(void)
{
    if (!page_rows) return;
    page_rows = 0;
    SetMode(page_in, 0);                /* always hand the shell back cooked */
}

/* Call after writing one line. Returns 0 when the reader asked to stop. */
static int page_line(void)
{
    UBYTE key = '\n';

    if (!page_rows) return 1;
    if (--page_left > 0) return 1;

    fflush(stdout);                     /* the prompt bypasses stdio */
    Write(page_out, PAGE_PROMPT, sizeof(PAGE_PROMPT) - 1);
    if (Read(page_in, &key, 1) != 1) key = '\n';
    Write(page_out, page_erase, sizeof(page_erase));
    page_left = page_rows;              /* a fresh page */
    if ((key & 0xdf) == 'Q') {          /* fold case */
        page_stop = 1;
        return 0;
    }
    return 1;
}

/* printf that keeps the page accounting. No format here spans two lines,
 * so one newline in the format is one line on screen.
 */
static void pout(const char *fmt, ...)
{
    va_list ap;
    const char *c;

    if (page_stop) return;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    for (c = fmt; *c; c++)
        if (*c == '\n' && !page_line()) return;
}

/* Extract and clean a string from IDENTIFY data */
/* Note: On 68k (big-endian), ATA strings are already in correct byte order */
void GetIDString(UWORD *id_data, int start_word, int num_words, char *dest)
{
    int i;

    /* Direct copy - no byte swap needed on big-endian 68k */
    memcpy(dest, &id_data[start_word], num_words * 2);
    dest[num_words * 2] = '\0';

    /* Trim trailing spaces */
    for (i = strlen(dest) - 1; i >= 0 && dest[i] == ' '; i--) {
        dest[i] = '\0';
    }
}

/* Get ULONG from two words (little-endian) */
ULONG GetIDLong(UWORD *id_data, int word)
{
    return ((ULONG)id_data[word+1] << 16) | id_data[word];
}

/* Send a SCSI command */
BOOL DoSCSI(UBYTE cmd, ULONG length, UBYTE cmdlen)
{
    memset(scsi_cdb, 0, sizeof(scsi_cdb));
    scsi_cdb[0] = cmd;

    scsi_cmd->scsi_Data = (UWORD *)data_buf;
    scsi_cmd->scsi_Length = length;
    scsi_cmd->scsi_Command = scsi_cdb;
    scsi_cmd->scsi_CmdLength = cmdlen;
    scsi_cmd->scsi_Flags = SCSIF_READ;
    scsi_cmd->scsi_SenseData = scsi_sense;
    scsi_cmd->scsi_SenseLength = 18;
    scsi_cmd->scsi_SenseActual = 0;
    scsi_cmd->scsi_Actual = 0;

    io->io_Command = HD_SCSICMD;
    io->io_Data = scsi_cmd;
    io->io_Length = sizeof(struct SCSICmd);

    if (DoIO((struct IORequest *)io) != 0) {
        return FALSE;
    }

    return (scsi_cmd->scsi_Status == 0);
}

/* Get ATA IDENTIFY data (v1.36+ passthrough) */
BOOL DoATAIdentify(void)
{
    memset(data_buf, 0, IDENTIFY_BUFFER_SIZE);
    return DoSCSI(ATA_IDENTIFY, IDENTIFY_BUFFER_SIZE, 6);
}

/* Get driver config (v1.37+ passthrough) */
BOOL DoGetConfig(struct CFDConfig *config)
{
    memset(data_buf, 0, CFD_CONFIG_BUFFER_SIZE);
    memset(config, 0, sizeof(struct CFDConfig));

    /* Request larger buffer for future compatibility */
    if (!DoSCSI(CFD_GETCONFIG, CFD_CONFIG_BUFFER_SIZE, 6)) {
        return FALSE;
    }

    /* Copy only what we understand (our struct size) */
    memcpy(config, data_buf, sizeof(struct CFDConfig));
    return TRUE;
}

/* Test if unit is ready */
BOOL DoTestUnitReady(void)
{
    return DoSCSI(SCSI_TEST_UNIT_READY, 0, 6);
}

/* Print size in human-readable format */
void PrintSize(ULONG sectors)
{
    ULONG kb = sectors / 2;
    ULONG mb = kb / 1024;
    ULONG gb = mb / 1024;

    if (gb > 0) {
        pout("%lu.%lu GB", gb, (mb % 1024) * 10 / 1024);
    } else if (mb > 0) {
        pout("%lu.%lu MB", mb, (kb % 1024) * 10 / 1024);
    } else {
        pout("%lu KB", kb);
    }
    pout(" (%lu sectors)\n", sectors);
}

/* Print card information from IDENTIFY data */
void PrintCardInfo(UWORD *id)
{
    char model[41], serial[21], firmware[9];
    ULONG sectors;
    UWORD config, caps, pio_modes, multi;

    GetIDString(id, ID_MODEL, 20, model);
    GetIDString(id, ID_SERIAL, 10, serial);
    GetIDString(id, ID_FIRMWARE, 4, firmware);

    config = id[ID_CONFIG];
    caps = id[ID_CAPABILITIES];
    pio_modes = id[ID_PIO_MODES];
    multi = id[ID_MAXMULTI] & 0xFF;
    sectors = GetIDLong(id, ID_LBA_SECTORS);

    pout("\n");
    pout("=== CompactFlash Card Information ===\n");
    pout("\n");
    pout("Model:      %s\n", model);
    pout("Serial:     %s\n", serial);
    pout("Firmware:   %s\n", firmware);
    pout("\n");

    pout("=== Capacity ===\n");
    pout("Size:       ");
    PrintSize(sectors);
    pout("Geometry:   %u cyl, %u heads, %u sectors/track\n",
           id[ID_CYLS], id[ID_HEADS], id[ID_SECTORS]);
    pout("\n");

    pout("=== Capabilities ===\n");
    pout("LBA:        %s\n", (caps & 0x0200) ? "Yes" : "No");
    pout("DMA:        %s\n", (caps & 0x0100) ? "Yes" : "No");

    /* PIO modes */
    pout("PIO Modes:  0");
    if (id[ID_PIO_OLD] >= 1) pout(", 1");
    if (id[ID_PIO_OLD] >= 2) pout(", 2");
    if (pio_modes & 0x01) pout(", 3");
    if (pio_modes & 0x02) pout(", 4");
    pout("\n");

    /* Multi-sector */
    if (multi > 0) {
        pout("Multi-sect: Max %u sectors/interrupt\n", multi);
    } else {
        pout("Multi-sect: Not supported\n");
    }

    /* UDMA modes */
    if (id[ID_UDMA_MODES] != 0) {
        pout("UDMA Modes: ");
        if (id[ID_UDMA_MODES] & 0x01) pout("0 ");
        if (id[ID_UDMA_MODES] & 0x02) pout("1 ");
        if (id[ID_UDMA_MODES] & 0x04) pout("2 ");
        if (id[ID_UDMA_MODES] & 0x08) pout("3 ");
        if (id[ID_UDMA_MODES] & 0x10) pout("4 ");
        if (id[ID_UDMA_MODES] & 0x20) pout("5 ");
        if (id[ID_UDMA_MODES] & 0x40) pout("6 ");
        pout("\n");
    }

    pout("\n");
    pout("=== Card Type ===\n");
    pout("Removable:  %s\n", (config & 0x0080) ? "Yes" : "No");
    pout("Type:       ");
    /* Check for CompactFlash signature (0x848x) */
    if ((config & 0xFFF0) == 0x8480) {
        pout("CompactFlash\n");
    } else if ((config & 0x8000) == 0) {
        pout("ATA\n");
    } else {
        pout("ATAPI\n");
    }

    /* Command Sets / Features */
    pout("\n");
    pout("=== Features (SET FEATURES capable) ===\n");
    if (id[ID_CMD_SET1] || id[ID_CMD_SET2]) {
        UWORD cmd1 = id[ID_CMD_SET1];
        UWORD cmd2 = id[ID_CMD_SET2];
        UWORD en1 = id[ID_CMD_EN1];
        UWORD en2 = id[ID_CMD_EN2];

        pout("                   Supported  Enabled\n");

        /* Word 82 bits */
        if (cmd1 & 0x0020)
            pout("Write Cache:       Yes        %s\n", (en1 & 0x0020) ? "Yes" : "No");
        if (cmd1 & 0x0040)
            pout("Read Look-ahead:   Yes        %s\n", (en1 & 0x0040) ? "Yes" : "No");
        if (cmd1 & 0x0008)
            pout("Power Management:  Yes        %s\n", (en1 & 0x0008) ? "Yes" : "No");
        if (cmd1 & 0x0004)
            pout("Security Mode:     Yes        %s\n", (en1 & 0x0004) ? "Yes" : "No");
        if (cmd1 & 0x0001)
            pout("SMART:             Yes        %s\n", (en1 & 0x0001) ? "Yes" : "No");

        /* Word 83 bits */
        if (cmd2 & 0x0400)
            pout("48-bit LBA:        Yes        %s\n", (en2 & 0x0400) ? "Yes" : "No");
        if (cmd2 & 0x1000)
            pout("Write FUA:         Yes        %s\n", (en2 & 0x1000) ? "Yes" : "No");
        if (cmd2 & 0x0020)
            pout("PUIS:              Yes        %s\n", (en2 & 0x0020) ? "Yes" : "No");
        if (cmd2 & 0x0008)
            pout("APM:               Yes        %s\n", (en2 & 0x0008) ? "Yes" : "No");

        /* CFA specific */
        if (cmd2 & 0x4000)
            pout("CFA Features:      Yes\n");
    } else {
        pout("(not reported by card)\n");
    }

    /* CF Advanced True IDE Timing (Word 163) */
    pout("\n");
    pout("=== CF True IDE Timing (Word 163) ===\n");
    if (id[ID_CFA_IDE] & 0x8000) {
        UWORD ide = id[ID_CFA_IDE];
        UWORD pio_no_iordy = ide & 0x07;
        UWORD pio_iordy = (ide >> 3) & 0x07;
        UWORD mdma_max = (ide >> 6) & 0x07;

        /* PIO mode to cycle time lookup */
        static const char *pio_ns[] = {"600", "383", "240", "180", "120", "100", "80", "?"};

        pout("PIO (no IORDY): max=%u (%sns cycle)\n",
               (unsigned)pio_no_iordy, pio_ns[pio_no_iordy]);
        pout("PIO (IORDY):    max=%u (%sns cycle)\n",
               (unsigned)pio_iordy, pio_ns[pio_iordy]);
        if (mdma_max > 0)
            pout("Multiword DMA:  max=%u\n", (unsigned)mdma_max);
    } else {
        pout("(not reported by card)\n");
    }

    /* CF Advanced PCMCIA Timing (Word 164) */
    pout("\n");
    pout("=== CF PCMCIA Timing (Word 164) ===\n");
    if (id[ID_CFA_TIMING] & 0x8000) {
        UWORD timing = id[ID_CFA_TIMING];
        UWORD mem_max = timing & 0x07;
        UWORD mem_cur = (timing >> 3) & 0x07;
        UWORD io_max = (timing >> 6) & 0x07;
        UWORD io_cur = (timing >> 9) & 0x07;

        /* Timing mode to nanoseconds lookup (modes 6-7 are vendor-specific) */
        static const char *mode_ns[] = {"600", "250", "150", "100", "80", "50", "?", "?"};

        pout("Memory Mode:  max=%u (%sns), current=%u (%sns)\n",
               (unsigned)mem_max, mode_ns[mem_max], 
               (unsigned)mem_cur, mode_ns[mem_cur]);
        pout("I/O Mode:     max=%u (%sns), current=%u (%sns)\n",
               (unsigned)io_max, mode_ns[io_max],
               (unsigned)io_cur, mode_ns[io_cur]);
    } else {
        pout("(not reported by card)\n");
    }

    /* Gayle timing register - actual hardware setting */
    pout("\n");
    pout("=== Gayle Timing (hardware) ===\n");
    {
        volatile UBYTE *gayle = (volatile UBYTE *)0x00DAB000;
        UBYTE reg_val = *gayle;
        UBYTE speed_bits = (reg_val >> 2) & 0x03;
        const char *gayle_ns;

        /* Bits 2-3: 00=250ns, 01=150ns, 10=100ns, 11=720ns */
        switch (speed_bits) {
            case 0: gayle_ns = "250"; break;
            case 1: gayle_ns = "150"; break;
            case 2: gayle_ns = "100"; break;
            case 3: gayle_ns = "720"; break;
            default: gayle_ns = "?"; break;
        }
        pout("Memory Speed: %sns\n", gayle_ns);
    }
}

/* Print driver configuration */
void PrintDriverConfig(struct CFDConfig *cfg)
{
    pout("\n");
    pout("=== Driver Configuration ===\n");
    pout("Driver Ver:   %u.%u\n", cfg->version_major, cfg->version_minor);
    pout("Mount Flags:  %u (", cfg->open_flags);
    if (cfg->open_flags == 0) {
        pout("none");
    } else {
        int first = 1;
        if (cfg->open_flags & 1)  { pout("%scfd_first", first ? "" : ", "); first = 0; }
        if (cfg->open_flags & 2)  { pout("%sskip_sig", first ? "" : ", "); first = 0; }
        if (cfg->open_flags & 4)  { pout("%scompat", first ? "" : ", "); first = 0; }
        if (cfg->open_flags & 8)  { pout("%sserial_debug", first ? "" : ", "); first = 0; }
        if (cfg->open_flags & 16) { pout("%sforce_multi", first ? "" : ", "); first = 0; }
        if (cfg->open_flags & 32) { pout("%sno_autodetect", first ? "" : ", "); first = 0; }
    }
    pout(")\n");
    pout("Multi-sect:   FW=%u, Used=%u\n", cfg->multi_size, cfg->multi_size_rw);

    /* Transfer modes - combined R/W display */
    {
        char read_buf[16], write_buf[16];
        const char *read_mode, *write_mode;

        switch (cfg->receive_mode) {
            case 0:  read_mode = "WORD"; break;
            case 1:  read_mode = "BYTE (data)"; break;
            case 2:  read_mode = "BYTE (alt)"; break;
            case 3:  read_mode = "BYTE (alt2)"; break;
            case 4:  read_mode = "MMAP"; break;
            default: sprintf(read_buf, "mode %u", cfg->receive_mode);
                     read_mode = read_buf; break;
        }
        switch (cfg->write_mode) {
            case 0:  write_mode = "WORD"; break;
            case 1:  write_mode = "BYTE (data)"; break;
            case 2:  write_mode = "BYTE (alt)"; break;
            case 3:  write_mode = "BYTE (alt2)"; break;
            case 4:  write_mode = "MMAP"; break;
            default: sprintf(write_buf, "mode %u", cfg->write_mode);
                     write_mode = write_buf; break;
        }
        pout("R/W Mode:     %s/%s\n", read_mode, write_mode);
    }
}

void Cleanup(void)
{
    page_end();
    if (io) {
        if (io->io_Device) {
            CloseDevice((struct IORequest *)io);
        }
        DeleteIORequest((struct IORequest *)io);
    }
    if (mp) DeleteMsgPort(mp);
    if (data_buf) FreeMem(data_buf, IDENTIFY_BUFFER_SIZE);
    if (scsi_sense) FreeMem(scsi_sense, 18);
    if (scsi_cmd) FreeMem(scsi_cmd, sizeof(struct SCSICmd));
}

int main(int argc, char **argv)
{
    int unit = 0;

    page_begin();

    pout("CFInfo " STR(VERSION) " - CompactFlash Card Information\n");

    /* Parse arguments */
    if (argc > 1) {
        unit = atoi(argv[1]);
    }

    /* Allocate resources */
    mp = CreateMsgPort();
    if (!mp) {
        pout("Error: Cannot create message port\n");
        Cleanup();                      /* the console must not stay RAW */
        return 10;
    }

    io = (struct IOStdReq *)CreateIORequest(mp, sizeof(struct IOStdReq));
    if (!io) {
        pout("Error: Cannot create IO request\n");
        Cleanup();
        return 10;
    }

    data_buf = AllocMem(IDENTIFY_BUFFER_SIZE, MEMF_PUBLIC | MEMF_CLEAR);
    scsi_sense = AllocMem(18, MEMF_PUBLIC | MEMF_CLEAR);
    scsi_cmd = AllocMem(sizeof(struct SCSICmd), MEMF_PUBLIC | MEMF_CLEAR);

    if (!data_buf || !scsi_sense || !scsi_cmd) {
        pout("Error: Cannot allocate memory\n");
        Cleanup();
        return 10;
    }

    /* Open device */
    if (OpenDevice(DEVICE_NAME, unit, (struct IORequest *)io, 0) != 0) {
        pout("Error: Cannot open %s unit %d\n", DEVICE_NAME, unit);
        pout("       (Is a CF card inserted?)\n");
        Cleanup();
        return 5;
    }

    pout("Device:     %s unit %d\n", DEVICE_NAME, unit);

    /* Test unit ready */
    if (!DoTestUnitReady()) {
        pout("Error: Card not ready\n");
        Cleanup();
        return 5;
    }

    /* Get IDENTIFY data via ATA passthrough (v1.36+) */
    if (!DoATAIdentify()) {
        pout("Error: IDENTIFY command failed\n");
        pout("       (Requires compactflash.device v1.36+)\n");
        Cleanup();
        return 5;
    }

    /* Print information */
    PrintCardInfo((UWORD *)data_buf);

    /* Get driver config (v1.37+) - optional, don't fail if not supported */
    {
        struct CFDConfig cfg;
        if (DoGetConfig(&cfg)) {
            PrintDriverConfig(&cfg);
        }
    }

    Cleanup();
    return 0;
}
