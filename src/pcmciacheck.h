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
#define IDE_DATA        ((volatile UWORD *)(IDE_BASE + 0x00))
#define IDE_DATA_BYTE   ((volatile UBYTE *)(IDE_BASE + 0x00))
#define IDE_DATA_HI     ((volatile UBYTE *)(IDE_BASE + 0x10001))  /* Odd byte */
#define IDE_DATA_ALT    ((volatile UBYTE *)(IDE_BASE + 0x08))
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
#define LOG_SIZE 16384

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
void InitWritePatterns(void);
int TestWriteModes(int read_mode);
int SaveLog(const char *filename);
int DumpCIS(int speed_ns);

/* Read/Write mode function types */
typedef void (*ReadFunc)(UBYTE *);
typedef void (*WriteFunc)(UBYTE *);

/* Read mode functions */
void ReadMode0(UBYTE *dest);
void ReadMode1(UBYTE *dest);
void ReadMode2(UBYTE *dest);
void ReadMode3(UBYTE *dest);
void ReadMode4(UBYTE *dest);  /* Memory mapped */

/* Write mode functions */
void WriteMode0(UBYTE *src);
void WriteMode1(UBYTE *src);
void WriteMode2(UBYTE *src);
void WriteMode3(UBYTE *src);
void WriteMode4(UBYTE *src);  /* Memory mapped */

#endif /* PCMCIACHECK_H */