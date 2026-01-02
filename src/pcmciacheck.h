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
#define PCMCIA_ATTR     ((volatile UBYTE *)0x00A00000)
#define PCMCIA_CONFIG   ((volatile UBYTE *)0x00A00200)

/* IDE registers in PCMCIA common memory */
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

/* Read/Write mode function types */
typedef void (*ReadFunc)(UBYTE *);
typedef void (*WriteFunc)(UBYTE *);

/* Read mode functions */
void ReadMode0(UBYTE *dest);
void ReadMode1(UBYTE *dest);
void ReadMode2(UBYTE *dest);
void ReadMode3(UBYTE *dest);

/* Write mode functions */
void WriteMode0(UBYTE *src);
void WriteMode1(UBYTE *src);
void WriteMode2(UBYTE *src);
void WriteMode3(UBYTE *src);

#endif /* PCMCIACHECK_H */