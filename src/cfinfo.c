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
        printf("%lu.%lu GB", gb, (mb % 1024) * 10 / 1024);
    } else if (mb > 0) {
        printf("%lu.%lu MB", mb, (kb % 1024) * 10 / 1024);
    } else {
        printf("%lu KB", kb);
    }
    printf(" (%lu sectors)\r\n", sectors);
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

    printf("\r\n");
    printf("=== CompactFlash Card Information ===\r\n");
    printf("\r\n");
    printf("Model:      %s\r\n", model);
    printf("Serial:     %s\r\n", serial);
    printf("Firmware:   %s\r\n", firmware);
    printf("\r\n");

    printf("=== Capacity ===\r\n");
    printf("Size:       ");
    PrintSize(sectors);
    printf("Geometry:   %u cyl, %u heads, %u sectors/track\r\n",
           id[ID_CYLS], id[ID_HEADS], id[ID_SECTORS]);
    printf("\r\n");

    printf("=== Capabilities ===\r\n");
    printf("LBA:        %s\r\n", (caps & 0x0200) ? "Yes" : "No");
    printf("DMA:        %s\r\n", (caps & 0x0100) ? "Yes" : "No");

    /* PIO modes */
    printf("PIO Modes:  0");
    if (id[ID_PIO_OLD] >= 1) printf(", 1");
    if (id[ID_PIO_OLD] >= 2) printf(", 2");
    if (pio_modes & 0x01) printf(", 3");
    if (pio_modes & 0x02) printf(", 4");
    printf("\r\n");

    /* Multi-sector */
    if (multi > 0) {
        printf("Multi-sect: Max %u sectors/interrupt\r\n", multi);
    } else {
        printf("Multi-sect: Not supported\r\n");
    }

    /* UDMA modes */
    if (id[ID_UDMA_MODES] != 0) {
        printf("UDMA Modes: ");
        if (id[ID_UDMA_MODES] & 0x01) printf("0 ");
        if (id[ID_UDMA_MODES] & 0x02) printf("1 ");
        if (id[ID_UDMA_MODES] & 0x04) printf("2 ");
        if (id[ID_UDMA_MODES] & 0x08) printf("3 ");
        if (id[ID_UDMA_MODES] & 0x10) printf("4 ");
        if (id[ID_UDMA_MODES] & 0x20) printf("5 ");
        if (id[ID_UDMA_MODES] & 0x40) printf("6 ");
        printf("\r\n");
    }

    printf("\r\n");
    printf("=== Card Type ===\r\n");
    printf("Removable:  %s\r\n", (config & 0x0080) ? "Yes" : "No");
    printf("Type:       ");
    /* Check for CompactFlash signature (0x848x) */
    if ((config & 0xFFF0) == 0x8480) {
        printf("CompactFlash\r\n");
    } else if ((config & 0x8000) == 0) {
        printf("ATA\r\n");
    } else {
        printf("ATAPI\r\n");
    }

    /* Command Sets / Features */
    printf("\r\n");
    printf("=== Features (SET FEATURES capable) ===\r\n");
    if (id[ID_CMD_SET1] || id[ID_CMD_SET2]) {
        UWORD cmd1 = id[ID_CMD_SET1];
        UWORD cmd2 = id[ID_CMD_SET2];
        UWORD en1 = id[ID_CMD_EN1];
        UWORD en2 = id[ID_CMD_EN2];

        printf("                   Supported  Enabled\r\n");

        /* Word 82 bits */
        if (cmd1 & 0x0020)
            printf("Write Cache:       Yes        %s\r\n", (en1 & 0x0020) ? "Yes" : "No");
        if (cmd1 & 0x0040)
            printf("Read Look-ahead:   Yes        %s\r\n", (en1 & 0x0040) ? "Yes" : "No");
        if (cmd1 & 0x0008)
            printf("Power Management:  Yes        %s\r\n", (en1 & 0x0008) ? "Yes" : "No");
        if (cmd1 & 0x0004)
            printf("Security Mode:     Yes        %s\r\n", (en1 & 0x0004) ? "Yes" : "No");
        if (cmd1 & 0x0001)
            printf("SMART:             Yes        %s\r\n", (en1 & 0x0001) ? "Yes" : "No");

        /* Word 83 bits */
        if (cmd2 & 0x0400)
            printf("48-bit LBA:        Yes        %s\r\n", (en2 & 0x0400) ? "Yes" : "No");
        if (cmd2 & 0x1000)
            printf("Write FUA:         Yes        %s\r\n", (en2 & 0x1000) ? "Yes" : "No");
        if (cmd2 & 0x0020)
            printf("PUIS:              Yes        %s\r\n", (en2 & 0x0020) ? "Yes" : "No");
        if (cmd2 & 0x0008)
            printf("APM:               Yes        %s\r\n", (en2 & 0x0008) ? "Yes" : "No");

        /* CFA specific */
        if (cmd2 & 0x4000)
            printf("CFA Features:      Yes\r\n");
    } else {
        printf("(not reported by card)\r\n");
    }

    /* CF Advanced True IDE Timing (Word 163) */
    printf("\r\n");
    printf("=== CF True IDE Timing (Word 163) ===\r\n");
    if (id[ID_CFA_IDE] & 0x8000) {
        UWORD ide = id[ID_CFA_IDE];
        UWORD pio_no_iordy = ide & 0x07;
        UWORD pio_iordy = (ide >> 3) & 0x07;
        UWORD mdma_max = (ide >> 6) & 0x07;

        /* PIO mode to cycle time lookup */
        static const char *pio_ns[] = {"600", "383", "240", "180", "120", "100", "80", "?"};

        printf("PIO (no IORDY): max=%u (%sns cycle)\r\n",
               (unsigned)pio_no_iordy, pio_ns[pio_no_iordy]);
        printf("PIO (IORDY):    max=%u (%sns cycle)\r\n",
               (unsigned)pio_iordy, pio_ns[pio_iordy]);
        if (mdma_max > 0)
            printf("Multiword DMA:  max=%u\r\n", (unsigned)mdma_max);
    } else {
        printf("(not reported by card)\r\n");
    }

    /* CF Advanced PCMCIA Timing (Word 164) */
    printf("\r\n");
    printf("=== CF PCMCIA Timing (Word 164) ===\r\n");
    if (id[ID_CFA_TIMING] & 0x8000) {
        UWORD timing = id[ID_CFA_TIMING];
        UWORD mem_max = timing & 0x07;
        UWORD mem_cur = (timing >> 3) & 0x07;
        UWORD io_max = (timing >> 6) & 0x07;
        UWORD io_cur = (timing >> 9) & 0x07;

        /* Timing mode to nanoseconds lookup (modes 6-7 are vendor-specific) */
        static const char *mode_ns[] = {"600", "250", "150", "100", "80", "50", "?", "?"};

        printf("Memory Mode:  max=%u (%sns), current=%u (%sns)\r\n",
               (unsigned)mem_max, mode_ns[mem_max], 
               (unsigned)mem_cur, mode_ns[mem_cur]);
        printf("I/O Mode:     max=%u (%sns), current=%u (%sns)\r\n",
               (unsigned)io_max, mode_ns[io_max],
               (unsigned)io_cur, mode_ns[io_cur]);
    } else {
        printf("(not reported by card)\r\n");
    }

    /* Gayle timing register - actual hardware setting */
    printf("\r\n");
    printf("=== Gayle Timing (hardware) ===\r\n");
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
        printf("Memory Speed: %sns\r\n", gayle_ns);
    }
}

/* Print driver configuration */
void PrintDriverConfig(struct CFDConfig *cfg)
{
    printf("\r\n");
    printf("=== Driver Configuration ===\r\n");
    printf("Driver Ver:   %u.%u\r\n", cfg->version_major, cfg->version_minor);
    printf("Mount Flags:  %u (", cfg->open_flags);
    if (cfg->open_flags == 0) {
        printf("none");
    } else {
        int first = 1;
        if (cfg->open_flags & 1)  { printf("%scfd_first", first ? "" : ", "); first = 0; }
        if (cfg->open_flags & 2)  { printf("%sskip_sig", first ? "" : ", "); first = 0; }
        if (cfg->open_flags & 4)  { printf("%scompat", first ? "" : ", "); first = 0; }
        if (cfg->open_flags & 8)  { printf("%sserial_debug", first ? "" : ", "); first = 0; }
        if (cfg->open_flags & 16) { printf("%sforce_multi", first ? "" : ", "); first = 0; }
        if (cfg->open_flags & 32) { printf("%sno_autodetect", first ? "" : ", "); first = 0; }
    }
    printf(")\r\n");
    printf("Multi-sect:   FW=%u, Used=%u\r\n", cfg->multi_size, cfg->multi_size_rw);

    /* Transfer modes - combined R/W display */
    {
        char read_buf[16], write_buf[16];
        const char *read_mode, *write_mode;

        switch (cfg->receive_mode) {
            case 0:  read_mode = "WORD"; break;
            case 1:  read_mode = "BYTE (data)"; break;
            case 2:  read_mode = "BYTE (alt)"; break;
            case 3:  read_mode = "BYTE (alt2)"; break;
            default: sprintf(read_buf, "mode %u", cfg->receive_mode);
                     read_mode = read_buf; break;
        }
        switch (cfg->write_mode) {
            case 0:  write_mode = "WORD"; break;
            case 1:  write_mode = "BYTE (data)"; break;
            case 2:  write_mode = "BYTE (alt)"; break;
            case 3:  write_mode = "BYTE (alt2)"; break;
            default: sprintf(write_buf, "mode %u", cfg->write_mode);
                     write_mode = write_buf; break;
        }
        printf("R/W Mode:     %s/%s\r\n", read_mode, write_mode);
    }
}

void Cleanup(void)
{
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

    printf("CFInfo " STR(VERSION) " - CompactFlash Card Information\r\n");

    /* Parse arguments */
    if (argc > 1) {
        unit = atoi(argv[1]);
    }

    /* Allocate resources */
    mp = CreateMsgPort();
    if (!mp) {
        printf("Error: Cannot create message port\r\n");
        return 10;
    }

    io = (struct IOStdReq *)CreateIORequest(mp, sizeof(struct IOStdReq));
    if (!io) {
        printf("Error: Cannot create IO request\r\n");
        Cleanup();
        return 10;
    }

    data_buf = AllocMem(IDENTIFY_BUFFER_SIZE, MEMF_PUBLIC | MEMF_CLEAR);
    scsi_sense = AllocMem(18, MEMF_PUBLIC | MEMF_CLEAR);
    scsi_cmd = AllocMem(sizeof(struct SCSICmd), MEMF_PUBLIC | MEMF_CLEAR);

    if (!data_buf || !scsi_sense || !scsi_cmd) {
        printf("Error: Cannot allocate memory\r\n");
        Cleanup();
        return 10;
    }

    /* Open device */
    if (OpenDevice(DEVICE_NAME, unit, (struct IORequest *)io, 0) != 0) {
        printf("Error: Cannot open %s unit %d\r\n", DEVICE_NAME, unit);
        printf("       (Is a CF card inserted?)\r\n");
        Cleanup();
        return 5;
    }

    printf("Device:     %s unit %d\r\n", DEVICE_NAME, unit);

    /* Test unit ready */
    if (!DoTestUnitReady()) {
        printf("Error: Card not ready\r\n");
        Cleanup();
        return 5;
    }

    /* Get IDENTIFY data via ATA passthrough (v1.36+) */
    if (!DoATAIdentify()) {
        printf("Error: IDENTIFY command failed\r\n");
        printf("       (Requires compactflash.device v1.36 or later)\r\n");
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
