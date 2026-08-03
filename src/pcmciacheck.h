/*
 * pcmciacheck.h - PCMCIA/CF Hardware Test Tool Header
 *
 * Function prototypes and definitions for pcmciacheck
 */

#ifndef PCMCIACHECK_H
#define PCMCIACHECK_H

#include <exec/types.h>

/* Hardware register addresses */
#define GAYLE_STATUS    ((volatile UBYTE *)0x00DA8000)
#define GAYLE_CONFIG    ((volatile UBYTE *)0x00DAB000)  /* bits 2-3 = PCMCIA memory speed */
#define PCMCIA_ATTR     ((volatile UBYTE *)0x00A00000)
#define PCMCIA_CONFIG   ((volatile UBYTE *)0x00A00200)

/* PCMCIA memory spaces */
#define PCMCIA_MEM      0x00600000  /* Common memory base (for mode 4) */
#define PCMCIA_MEM_DATA ((volatile UWORD *)(PCMCIA_MEM + 0x400))  /* Data at offset 1024 */

/* IDE registers in PCMCIA memory-mapped mode (mode 4) */
#define MMAP_DEVHEAD    ((volatile UBYTE *)(PCMCIA_MEM + 0x06))
#define MMAP_COMMAND    ((volatile UBYTE *)(PCMCIA_MEM + 0x07 + 0x10000))
#define MMAP_STATUS     ((volatile UBYTE *)(PCMCIA_MEM + 0x0E))

/* IDE registers in PCMCIA I/O space (modes 0-3) */
#define IDE_BASE        0x00A20000

/*
 * Data port. Every transfer mode in the driver reads and writes
 * through CFU_DataPort, which is the PCMCIA I/O base + 8
 * (src/cfd.s). The task-file data register at offset 0 is never
 * used by the driver, so it is not tested here either.
 */
#define IDE_DATA_PORT   ((volatile UWORD *)(IDE_BASE + 0x08))
#define IDE_DATA_PORT_B ((volatile UBYTE *)(IDE_BASE + 0x08))
#define IDE_DATA_PORT_H ((volatile UBYTE *)(IDE_BASE + 0x08 + 0x10001))

/*
 * Transfer-mode geometry, mirroring src/cfd.s:
 *   mode 1 walks the register aliases with a 16-byte stride and
 *     restarts at the data port every 8192 bytes (pi_mode1)
 *   mode 4 restarts at the memory window every 1024 bytes
 *     (pi_mode4)
 */
#define MODE1_STRIDE    16
#define MODE1_SEGMENT   8192
#define MODE4_SEGMENT   1024

#define IDE_ERROR       ((volatile UBYTE *)(IDE_BASE + 0x01 + 0x10000))
#define IDE_SECCOUNT    ((volatile UBYTE *)(IDE_BASE + 0x02))
#define IDE_SECNUM      ((volatile UBYTE *)(IDE_BASE + 0x03 + 0x10000))
#define IDE_CYLLO       ((volatile UBYTE *)(IDE_BASE + 0x04))
#define IDE_CYLHI       ((volatile UBYTE *)(IDE_BASE + 0x05 + 0x10000))
#define IDE_DEVHEAD     ((volatile UBYTE *)(IDE_BASE + 0x06))
#define IDE_COMMAND     ((volatile UBYTE *)(IDE_BASE + 0x07 + 0x10000))
#define IDE_STATUS      ((volatile UBYTE *)(IDE_BASE + 0x0E))

/* ATA commands */
#define ATA_IDENTIFY    0xEC
#define ATA_READ        0x20
#define ATA_WRITE       0x30

/* Status bits */
#define STATUS_BSY      0x80
#define STATUS_DRDY     0x40
#define STATUS_DRQ      0x08
#define STATUS_ERR      0x01

/* Gayle card detect bit */
#define GAYLE_CARD_DETECT 0x40

/* Log buffer size */
#define LOG_SIZE 32768

/* IDENTIFY block size, one sector */
#define IDENTIFY_BYTES 512

/* IDENTIFY read-stability test */
#define STAB_RUNS_DEFAULT 5
#define STAB_RUNS_MIN     2
#define STAB_RUNS_MAX     32

/*
 * Verdicts, ordered worst first, so a sweep can keep the worst result
 * for a mode by taking the minimum.
 */
#define STAB_NODATA   0
#define STAB_ZERO     1   /* block arrived but is all zeros: nothing read */
#define STAB_STUCK    2
#define STAB_UNSTABLE 3
#define STAB_STABLE   4

/* Gayle PCMCIA timings in nanoseconds, $DAB000 bits 2-3 */
#define GAYLE_SPEED_COUNT 4
extern const int GayleSpeeds[GAYLE_SPEED_COUNT];

/* One mode's stability measurement */
typedef struct {
    int   read_ok;                  /* runs that delivered a block */
    int   identical;                /* runs byte-identical to the reference */
    int   distinct;                 /* distinct checksums among those */
    int   first_diff;               /* first differing word, -1 if none */
    int   worst_differ;             /* most words differing in one run */
    int   stuck;                    /* reference block is one repeated word */
    int   all_zero;                 /* reference block is entirely zeros */
    ULONG ok_mask;                  /* bit per run that delivered */
    UWORD repeats;                  /* repeated words in the reference */
    UWORD stuck_value;              /* the repeated word, as read */
    UWORD cks[STAB_RUNS_MAX];
    UBYTE run_ok[STAB_RUNS_MAX];
} StabResult;

/* CIS tuple codes (subset, PCMCIA spec) */
#define CISTPL_NULL          0x00
#define CISTPL_DEVICE        0x01
#define CISTPL_LONGLINK_MFC  0x06
#define CISTPL_CHECKSUM      0x10
#define CISTPL_LONGLINK_A    0x11
#define CISTPL_LONGLINK_C    0x12
#define CISTPL_LINKTARGET    0x13
#define CISTPL_NO_LINK       0x14
#define CISTPL_VERS_1        0x15
#define CISTPL_ALTSTR        0x16
#define CISTPL_JEDEC_C       0x18
#define CISTPL_JEDEC_A       0x19
#define CISTPL_CONFIG        0x1A
#define CISTPL_CFTABLE_ENTRY 0x1B
#define CISTPL_DEVICE_OC     0x1C
#define CISTPL_MANFID        0x20
#define CISTPL_FUNCID        0x21
#define CISTPL_FUNCE         0x22  /* aka FUNCEXT */
#define CISTPL_VERS_2        0x40
#define CISTPL_ORG           0x46
#define CISTPL_END           0xFF

/* Function prototypes */
void WriteChunkHeader(const char *id, ULONG size);
int OpenTimer(void);
void CloseTimer(void);
void DelayMS(ULONG ms);
int CardPresent(void);
int WaitReady(int timeout_ms);
UWORD TestTransferModes(void);
void LogPatternTest(void);
int TestReadModes(int *working_mode);
int TestReadStability(int runs);
int SweepReadStability(int runs);
int IdentifyStability(int speed, int sweep, int runs);
UBYTE GayleSetSpeed(int ns);
void GayleRestore(UBYTE cfg);
const char *GayleCurrentLabel(void);
const char *GayleSpeedName(int ns);
int GayleCurrentSpeed(void);
void InitWritePatterns(void);
int TestWriteModes(int read_mode);
int SaveLog(const char *filename);
int DumpCIS(int speed_ns);

/*
 * Read/Write mode function types.
 *
 * The byte count is passed in, like the driver's _pio_in / _pio_out
 * (d0 = byte count), so each mode can do its own segmentation over a
 * whole transfer instead of being called once per fixed-size chunk.
 */
typedef void (*ReadFunc)(UBYTE *dest, ULONG bytes);
typedef void (*WriteFunc)(UBYTE *src, ULONG bytes);

/* Read mode functions, mirroring pi_mode0..pi_mode4 in src/cfd.s */
void ReadMode0(UBYTE *dest, ULONG bytes);
void ReadMode1(UBYTE *dest, ULONG bytes);
void ReadMode2(UBYTE *dest, ULONG bytes);
void ReadMode3(UBYTE *dest, ULONG bytes);
void ReadMode4(UBYTE *dest, ULONG bytes);  /* Memory mapped */

/* Write mode functions, mirroring po_mode0..po_mode4 in src/cfd.s */
void WriteMode0(UBYTE *src, ULONG bytes);
void WriteMode1(UBYTE *src, ULONG bytes);
void WriteMode2(UBYTE *src, ULONG bytes);
void WriteMode3(UBYTE *src, ULONG bytes);
void WriteMode4(UBYTE *src, ULONG bytes);  /* Memory mapped */

/* Mode dispatch tables and names, indexed by mode number */
extern ReadFunc ReadModes[5];
extern WriteFunc WriteModes[5];
extern const char *ReadModeNames[5];

#endif /* PCMCIACHECK_H */