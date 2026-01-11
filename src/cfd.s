; compactflash.device driver V1.36
; Copyright (C) 2009  Torsten Jager <t.jager@gmx.de>
; This file is part of cfd, a free storage device driver for Amiga.
;
; This driver is free software; you can redistribute it and/or
; modify it under the terms of the GNU Lesser General Public
; License as published by the Free Software Foundation; either
; version 2.1 of the License, or (at your option) any later version.
;
; This tool is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
; Lesser General Public License for more details.
;
; You should have received a copy of the GNU Lesser General Public
; License along with this library; if not, write to the Free Software
; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

;===========================================================================
; ARCHITECTURE OVERVIEW
;===========================================================================
;
; This driver implements a block device for CompactFlash cards connected
; via PCMCIA slot on Amiga 600/1200. It supports both ATA (CF native) and
; ATAPI protocols, as well as SD cards via SD-to-CF adapters.
;
; REGISTER CONVENTIONS (internal functions):
;   a3 = CFU pointer (CompactFlashUnit) - preserved across most calls
;   a4 = CFD pointer (CompactFlashDevice base) - preserved across most calls
;   a6 = library base (exec.library or other) - caller saves if needed
;   d0 = return value / scratch
;   d1 = scratch / parameter
;   d2-d6 = preserved (caller saves via movem if used)
;   a0-a2 = scratch / parameters
;
; KEY DATA STRUCTURES:
;   CFD (CompactFlashDevice) - device base, contains exec pointers
;   CFU (CompactFlashUnit) - per-unit state, card info, buffers
;
; TRANSFER MODES:
;   The driver supports multiple PIO transfer modes (byte/word, I/O/memory)
;   selected during card identification based on card capabilities.
;
; BUILD VARIANTS:
;   Full build (DEBUG=1): includes serial debug output (~10KB)
;   Small build (no DEBUG): minimal size (~8KB)
;   Fast PIO build (FASTPIO=1): enables PIO speed optimization (experimental)
;
;===========================================================================

;--- Version (defined by Makefile, with defaults for standalone assembly) ---
	ifnd	FILE_VERSION
FILE_VERSION	= 1
	endc
	ifnd	FILE_REVISION
FILE_REVISION	= 36
	endc

;--- Conditional compilation ---
; Define DEBUG symbol to include serial debug support
; Set via assembler command line: -DDEBUG=1
; Or uncomment the next line:
;DEBUG	= 1

; Define FASTPIO symbol to enable PIO speed optimization
; Set via assembler command line: -DFASTPIO=1
; Or uncomment the next line:
;FASTPIO	= 1

;--- from exec.library -------------------------------------

CALLEXEC macro
	move.l	CFD_ExecBase(a4),a6
	jsr	\1(a6)
	endm

CALLSAME macro
	jsr	\1(a6)			;same library as last CALLxxx
	endm

JMPEXEC	macro				;instead of CALLEXEC and rts
	move.l	CFD_ExecBase(a4),a6
	jmp	\1(a6)
	endm

INITLIST macro
	move.l	\1,(\1)
	addq.l	#4,(\1)
	clr.l	4(\1)
	move.l	\1,8(\1)
	endm

_AbsExecBase	= 4

Disable		= -120
Enable		= -126
Forbid		= -132
Permit		= -138
AddIntServer	= -168
RemIntServer	= -174
AllocMem	= -198
FreeMem		= -210
AddHead		= -240
Remove		= -252
AddTask		= -282
RemTask		= -288
FindTask	= -294
SetSignal	= -306
Wait		= -318
Signal		= -324
AllocSignal	= -330
FreeSignal	= -336
PutMsg		= -366
GetMsg		= -372
ReplyMsg	= -378
WaitPort	= -384
CloseLibrary	= -414
OpenDevice	= -444
CloseDevice	= -450
DoIO		= -456
SendIO		= -462
CheckIO		= -468
WaitIO		= -474
_AbortIO	= -480
OpenResource	= -498
TypeOfMem	= -534
OpenLibrary	= -552
CopyMem		= -624
CacheClearE	= -642
CacheControl	= -648
RawPutChar	= -516

;struct ExecBase
EXB_MemList	= 322

;struct MemHeader
MH_Lower	= 20
MH_Upper	= 24

;cache flags
CACRF_EnableD	= $00000100
CACRF_ClearD	= $00008000

;struct Node
LN_Succ		=  0
LN_Pred		=  4
LN_Type		=  8
LN_Pri		=  9
LN_Name		= 10
LN_Sizeof	= 14

;LN_Type
NT_TASK		= 1
NT_INTERRUPT	= 2
NT_DEVICE	= 3
NT_MESSAGE	= 5
NT_PROCESS	= 13

;struct MsgPort
MP_Flags	= 14
MP_SigBit	= 15
MP_SigTask	= 16
MP_MsgList	= 20
MP_Sizeof	= 34

;MP_Flags
PA_SIGNAL	= 0

;struct Message
MN_ReplyPort	= 14
MN_Length	= 18

;struct Interrupt
IS_Data		= 14
IS_Code		= 18
IS_Sizeof	= 22

;memory types
MEMF_NORM	= 0
MEMF_PUBLIC	= 1
MEMF_CLEAR	= $10000

;struct Library
LIB_Node	= 0
LIB_Flags	= 14
LIB_pad		= 15
LIB_NegSize	= 16
LIB_PosSize	= 18
LIB_Version	= 20
LIB_Revision	= 22
LIB_IdString	= 24
LIB_Sum		= 28
LIB_OpenCnt	= 32
LIB_Sizeof	= 34

;LIB_Flags
LIBF_CHANGED	= 2
LIBF_SUMUSED	= 4
LIBF_DELEXP	= 8

;function
;BeginIO	= -30

;struct Unit
UN_MsgPort	= 0
UN_Flags	= 34
UN_pad		= 35
UN_OpenCnt	= 36
UN_Sizeof	= 38

;UN_Flags
UNF_ACTIVE	= 1
UNF_INTASK	= 2

;struct Resident
RT_MatchWord	= 0
RT_MatchTag	= 2
RT_EndSkip	= 6
RT_Flags	= 10
RT_Version	= 11
RT_Type		= 12
RT_Priority	= 13
RT_Name		= 14
RT_IDString	= 18
RT_Init		= 22
RT_Sizeof	= 26

RTC_MATCHWORD	= $4afc
RTF_AUTOINIT	= $80

;struct Task
TC_Node		= 0
TC_Flags	= 14
TC_State	= 15
TC_IDNestCnt	= 16
TC_TDNestCnt	= 17
TC_SigAlloc	= 18
TC_SigWait	= 22
TC_SigRecvd	= 26
TC_SigExcept	= 30
TC_TrapAlloc	= 34
TC_TrapAble	= 36
TC_ExceptData	= 38
TC_ExceptCode	= 42
TC_TrapData	= 46
TC_TrapCode	= 50
TC_SPReg	= 54
TC_SPLower	= 58
TC_SPUpper	= 62
TC_Switch	= 66
TC_Launch	= 70
TC_MemEntry	= 74
TC_UserData	= 88
TC_Sizeof	= 92

;--- from intuition.library --------------------------------

CALLINT	macro
	move.l	IntBase(a4),a6
	jsr	\1(a6)
	endm

CloseWindow	= -72
LockPubScreen	= -510
UnlockPubScreen	= -516
OpenWindowTagList = -606

;OpenWindow Tags
WA_Left		= $80000064
WA_Top		= $80000065
WA_Width	= $80000066
WA_Height	= $80000067
WA_Title	= $8000006e
WA_CustomScreen	= $80000070
WA_Activate	= $80000089

;struct screen
SCR_Width	= 12
SCR_Height	= 14
SCR_BarHeight	= 30
SCR_WBorTop	= 35
SCR_WBorLeft	= 36
SCR_WBorRight	= 37
SCR_WBorBottom	= 38
SCR_RastPort	= 84

;struct Window
WIN_Width	= 8
WIN_Height	= 10
WIN_Screen	= 46
WIN_RastPort	= 50
WIN_BorderLeft	= 54
WIN_BorderTop	= 55
WIN_BorderRight	= 56

;struct IntuiText
IT_String	= 12
IT_Sizeof	= 20

CR		= 13
LF		= 10

;--- from trackdisk/mfm.device -----------------------------

;struct TrackdiskRequest
IO_Device	= 20
IO_Unit		= 24
IO_Command	= 28
IO_Flags	= 30
IO_Error	= 31
IO_Actual	= 32
IO_Length	= 36
IO_Data		= 40
IO_Offset	= 44
IO_SimpleSizeof	= 48

IO_ChangeNum	= 48
IO_SecLabel	= 52
IO_Sizeof	= 56

;IO_Flags
IOF_QUICK	= 1

;struct DriveGeometry
DG_SectorSize	= 0
DG_TotalSectors	= 4
DG_Cylinders	= 8
DG_CylSectors	= 12
DG_Heads	= 16
DG_TrackSectors	= 20
DG_BufMemType	= 24
DG_DeviceType	= 28
DG_Flags	= 29
DG_Reserved	= 30
DG_Sizeof	= 32

;commands
CMD_RESET	= 1
CMD_READ	= 2
CMD_WRITE	= 3
CMD_UPDATE	= 4
CMD_CLEAR	= 5
CMD_STOP	= 6
CMD_START	= 7
CMD_FLUSH	= 8
TD_MOTOR	= 9
TD_CHANGENUM	= 13
TD_CHANGESTATE	= 14
TD_PROTSTATUS	= 15
TD_GETDRIVETYPE	= 18
TD_ADDCHANGEINT	= 20
TD_REMCHANGEINT	= 21
TD_GETGEOMETRY	= 22
ETD_READ	= $8002
ETD_WRITE	= $8003
ETD_UPDATE	= $8004

;NSD and TD64 commands
NSCMD_DEVICEQUERY  = $4000
NSCMD_TD_READ64	   = $c000
NSCMD_TD_WRITE64   = $c001

;struct NSDeviceQueryResult
QR_DevQueryFormat  = 0
QR_SizeAvailable   = 4
QR_DeviceType	   = 8
QR_DeviceSubType   = 10
QR_SupportedCmds   = 12
QR_Sizeof	   = 16

;QR_DeviceType
NSDEVTYPE_TRACKDISK = 5

;error codes
IOERR_OPENFAIL	   = -1
IOERR_ABORTED	   = -2
IOERR_NOCMD	   = -3
IOERR_BADLENGTH	   = -4
TDERR_NOTSPECIFIED = 20
TDERR_NOSECHDR	   = 21
TDERR_WRITEPROT	   = 28
TDERR_DISKCHANGED  = 29
TDERR_NOMEM	   = 31
TDERR_BADUNITNUM   = 32
TDERR_DRIVEINUSE   = 34

;--- from scsi.device --------------------------------------

;struct SCSICmd
SCSI_Data	 = 0
SCSI_Length	 = 4
SCSI_Actual	 = 8
SCSI_Command	 = 12
SCSI_CmdLength	 = 16
SCSI_CmdActual	 = 18
SCSI_Flags	 = 20
SCSI_Status	 = 21
SCSI_SenseData	 = 22
SCSI_SenseLength = 26
SCSI_SenseActual = 28
SCSI_Sizeof	 = 30

;SCSI_Flags
SCSIF_WRITE	= 0
SCSIF_READ	= 1
SCSIF_AUTOSENSE	= 2

;command
HD_SCSICMD	= 28

;SCSI commands
TESTUNITREADY	= $00
REQUESTSENSE	= $03
READ06		= $08
WRITE06		= $0a
INQUIRY		= $12
READCAPACITY	= $25
READ10		= $28
WRITE10		= $2a
ATA_IDENTIFY	= $EC			;ATA IDENTIFY passthrough (vendor-specific)
CFD_GETCONFIG	= $ED			;Get driver config (vendor-specific)

;--- from timer.device -------------------------------------

;function
GetSysTime	= -66

;struct TimeRequest
TR_Seconds	= 32
TR_Micros	= 36
TR_Sizeof	= 40

;commands
TR_ADDREQUEST	= 9
TR_GETSYSTIME	= 10

;units
UNIT_VBLANK	= 1

;--- from card.resource ------------------------------------

CALLCARD macro
	move.l	CFD_CardBase(a4),a6
	jsr	\1(a6)
	endm

JMPCARD	macro				;instead of CALLCARD and rts
	move.l	CFD_CardBase(a4),a6
	jmp	\1(a6)
	endm

OwnCard		= -6
ReleaseCard	= -12
GetCardMap	= -18
BeginCardAccess	= -24
EndCardAccess	= -30
ReadCardStatus	= -36
CardResetRemove	= -42
CardMiscControl	= -48
CardAccessSpeed	= -54
CardProgramVoltage = -60
CardResetCard	= -66
CopyTuple	= -72
DeviceTuple	= -78

CardChangeCount	= -96
CardInterface	= -102

;ReadStatus()
CARD_STATUSF_CCDET	= 64
CARD_STATUSF_BVD1	= 32
CARD_STATUSF_SC		= 32
CARD_STATUSF_BVD2	= 16
CARD_STATUSF_DA		= 16
CARD_STATUSF_WR		= 8
CARD_STATUSF_BSY	= 4
CARD_STATUSF_IRQ	= 4

CARD_STATUSB_IRQ	= 2

;CardMiscControl()
CARD_ENABLEF_DIGAUDIO	= 2
CARD_DISABLEF_WP	= 8
CARD_INTF_SETCLR	= 128		;v39+
CARD_INTF_BVD1		= 32
CARD_INTF_SC		= 32
CARD_INTF_BVD2		= 16
CARD_INTF_DA		= 16
CARD_INTF_BSY		= 4
CARD_INTF_IRQ		= 4

;CardInterface()
CARD_INTERFACE_AMIGA_0	= 0

;CardProgramVoltage()
CARD_VOLTAGE_0V		= 0
CARD_VOLTAGE_5V		= 1
CARD_VOLTAGE_12V	= 2

;struct CardHandle
CAH_Node	= 0
CAH_CardRemoved = 14
CAH_CardInserted = 18
CAH_CardStatus	= 22
CAH_CardFlags	= 26
CAH_Sizeof	= 27			;!!!

;CAH_CardFlags
CARDF_RESETREMOVE	= 1
CARDF_IFAVAILABLE	= 2
CARDF_DELAYOWNERSHIP	= 4
CARDF_POSTSTATUS	= 8
CARDF_REMOVEHANDLE	= 1

;struct DeviceTData
DTD_DTsize	= 0
DTD_DTspeed	= 4
DTD_DTtype	= 8
DTD_DTflags	= 9
DTD_Sizeof	= 10

;struct CardMemoryMap
CMM_CommonMemory	= 0
CMM_AttributeMemory	= 4
CMM_IOMemory		= 8
CMM_CommonMemSize	= 12		;v39+
CMM_AttributeMemSize	= 16
CMM_IOMemSize		= 20
CMM_Sizeof		= 24

;--- the hardware brake ------------------------------------

A_Pb		= $bfe101		;Centronics data register

;--- private structs ---------------------------------------
;
; CompactFlashDevice (CFD) - Device base structure
; Extends standard Amiga device structure (36 bytes)
;
;struct CompactFlashDevice
CFD_ExecBase	= 36			;exec.library base pointer
CFD_DosBase	= 40			;dos.library base pointer
CFD_CardBase	= 44			;card.resource base pointer
CFD_SegList	= 48			;segment list for expunge
CFD_Unit	= 52			;pointer to CFU (single unit)
CFD_Sizeof	= 56

;---------------------------------------------------------------------------
; CompactFlashUnit (CFU) - Per-unit state structure
; Contains all runtime state for a PCMCIA card slot
; Passed in a3 register to most internal functions
;---------------------------------------------------------------------------
;struct CompactFlashUnit
CFU_Flags	= 38			;unit flags (CFUF_*)
CFU_Device	= 40			;back-pointer to CFD

;--- Diagnostics ---
CFU_UnitSize	= 44			;size of this struct
CFU_ResVersion	= 48			;resource version
CFU_ResRev	= 50			;resource revision
CFU_Debug	= 52			;debug flags
CFU_ActiveHacks	= 54			;active compatibility hacks
CFU_ReadErrors	= 56			;read error counter (long)
CFU_WriteErrors	= 60			;write error counter (long)

;--- Timer ---
CFU_TimeReq	= 64			;struct IORequest for timer.device

;--- Task/Signal management ---
CFU_Process	= 104			;unit process pointer
CFU_CardSig	= 108			;signal for card events
CFU_Signals2	= 112			;signal mask: timer + card
CFU_Signals3	= 116			;signal mask: timer + card + ioreq
CFU_CardHandle	= 120			;card.resource handle

;--- Interrupt servers ---
CFU_InsertInt	= 148			;card insert interrupt
CFU_RemoveInt	= 172			;card remove interrupt
CFU_StatusInt	= 196			;status change interrupt

;--- Card state ---
CFU_EventFlags	= 220			;event flags byte
				;  bit 0-1: card removed flags
				;  bit 6: timer active
CFU_IOErr	= 221			;last I/O error code
CFU_IDEStatus	= 222			;last IDE status register
CFU_IDEError	= 223			;last IDE error register

;--- Memory pointers ---
CFU_MemPtr	= 224			;PCMCIA common memory base
CFU_AttrPtr	= 228			;PCMCIA attribute memory base
CFU_IOPtr	= 232			;PCMCIA I/O space base

;--- Multi-sector settings ---
CFU_MultiSize	= 236			;sectors per interrupt (from card)
CFU_OpenFlags	= 238			;mount Flags field
				;  bit 0: "cfd first" hack
				;  bit 1: skip PCMCIA signature
				;  bit 2: compatibility mode
				;  bit 3: serial debug output (Flags=8)
				;  bit 4: enforce multi mode 256 sectors (Flags=16)
				;  bit 5: skip multi-sector override auto-detection (Flags=32)
CFUF_SERIALDEBUG = 8			;Flags = 8 enables serial debug

;--- Transfer configuration ---
CFU_DTSize	= 240			;DeviceTData size
CFU_DTSpeed	= 244			;DeviceTData speed
CFU_DTType	= 248			;DeviceTData type
CFU_DTFlags	= 249			;DeviceTData flags
CFU_CardReady	= 250			;0 during recognition/init, 1 when ready

;--- Client management ---
CFU_Clients	= 252			;struct List of disk change clients
CFU_Request	= 264			;current IORequest pointer

;--- Drive geometry ---
CFU_DriveSize	= 268			;total sectors (LBA count)
CFU_BlockSize	= 272			;bytes per sector (usually 512)

;--- Current I/O operation ---
CFU_Block	= 276			;current block number
CFU_Count	= 280			;bytes remaining
CFU_Buffer	= 284			;buffer pointer
CFU_Try		= 288			;retry counter

;--- SCSI emulation ---
CFU_SCSIState	= 290			;SCSI state machine
CFU_ConfigAddr	= 292			;card configuration address
CFU_RWFlags	= 296			;read/write flags
CFU_BlockShift	= 298			;log2(blocksize), e.g. 9 for 512

;--- Transfer modes ---
; These select PIO transfer method (byte/word, I/O mapped/memory mapped)
CFU_ReadMode	= 300			;read transfer mode
CFU_WriteMode	= 301			;write transfer mode
CFU_ReceiveMode	= 302			;receive transfer mode (for identify)
CFU_SendMode	= 303			;send transfer mode

;--- Watchdog ---
CFU_WatchInt	= 304			;watchdog interrupt
CFU_WatchTimer	= 328			;watchdog timer value

;--- IDE state ---
CFU_IDESense	= 330			;IDE sense data
CFU_unused2	= 331			;reserved
CFU_OKInts	= 332			;successful interrupt count
CFU_FastInts	= 336			;fast interrupt count
CFU_LostInts	= 340			;lost interrupt count

;--- IDE command block ---
CFU_IDEAddr	= 344			;IDE register base address
CFU_IDESet	= 348			;IDE command buffer (8 bytes)
				;  +0: Features
				;  +1: Sector Count
				;  +2: LBA Low (7:0)
				;  +3: LBA Mid (15:8)
				;  +4: LBA High (23:16)
				;  +5: Device/Head (27:24 + flags)
				;  +6: Command
				;  +7: (unused)

;--- SCSI direct ---
CFU_SCSIStruct	= 356			;SCSI command structure
CFU_PLength	= 386			;ATAPI packet length (12 or 16), 0=ATA
CFU_Packet	= 388			;ATAPI command packet

;--- IDENTIFY data ---
CFU_ConfigBlock	= 404			;512-byte IDENTIFY buffer

;--- Message port ---
CFU_TimePort	= 916			;timer reply port

;--- Termination ---
CFU_KillSig	= 952			;kill signal number
CFU_KillTask	= 956			;task to signal on kill
CFU_CacheFlags	= 960			;saved cache flags

;--- Multi-sector R/W ---
CFU_MultiSizeRW	= 964			;bytes per transfer (sectors * 512)
				;set from card or override (Flags=16)

CFU_Sizeof	= 966


;CFU_Flags
CFUF_FLUSH	= 1
CFUF_STOPPED	= 2
CFUF_TERM	= 4

;*** Lets get it on!! **************************************

Start:
	moveq.l	#0,d0
	rts				;for accidental Shell invocation

s_resident:
	dc.w	RTC_MATCHWORD
	dc.l	s_resident
	dc.l	s_codeend
	dc.b	RTF_AUTOINIT
	dc.b	FILE_VERSION
	dc.b	NT_DEVICE
	dc.b	0			;Priority
	dc.l	s_name
	dc.l	s_idstring
	dc.l	s_inittable

s_name:
	dc.b	"compactflash.device",0
	dc.b	"$VER: "
s_idstring:
	;Version string from Makefile-generated include
	include	"version.i"
	VERSION_STRING
	dc.b	LF,0
	dc.b	"� Torsten Jager",0
CardName:
	dc.b	"card.resource",0
TimerName:
	dc.b	"timer.device",0

;--- Debug message strings (used when Flags = 8) ---
	ifd	DEBUG
dbg_card_insert:
	dc.b	"[CFD] Card inserted",13,10,0
dbg_card_remove:
	dc.b	"[CFD] Card removed",13,10,0
dbg_identify:
	dc.b	"[CFD] Identifying card...",13,10,0
dbg_identify_ok:
	dc.b	"[CFD] Card identified OK",13,10,0
dbg_identify_fail:
	dc.b	"[CFD] Card identify FAILED",13,10,0
dbg_reset:
	dc.b	"[CFD] Reset",13,10,0
dbg_config:
	dc.b	"[CFD] Configuring HBA",13,10,0
dbg_tuple:
	dc.b	"[CFD] Reading tuples",13,10,0
dbg_voltage:
	dc.b	"[CFD] Setting voltage",13,10,0
dbg_rwtest:
	dc.b	"[CFD] RW test",13,10,0
dbg_getid:
	dc.b	"[CFD] Getting IDE ID",13,10,0
dbg_spinup:
	dc.b	"[CFD] Spinup",13,10,0
dbg_multimode:
	dc.b	"[CFD] Init multi mode",13,10,0
	ifd	FASTPIO
dbg_card_pio:
	dc.b	"[CFD] ..Card PIO: ",0
dbg_gayle_speed:
	dc.b	" -> Gayle: ",0
dbg_gayle_actual:
	dc.b	"[CFD] ..actual:  ",0
dbg_gayle_cardres:
	dc.b	"[CFD] ..using CardResource",13,10,0
dbg_gayle_direct:
	dc.b	"[CFD] ..using direct Gayle access",13,10,0
	endc
dbg_gayle_timing:
	dc.b	"[CFD] Gayle timing: ",13,10,0
dbg_gayle_current:
	dc.b	"[CFD] ..current: ",0
dbg_ns:
	dc.b	"ns",13,10,0
dbg_notify:
	dc.b	"[CFD] Notify clients",13,10,0
dbg_done:
	dc.b	"[CFD] ..done",13,10,0
dbg_model:
	dc.b	"[CFD] Model: ",0
dbg_serial:
	dc.b	"[CFD] Serial: ",0
dbg_firmware:
	dc.b	"[CFD] FW: ",0
dbg_ideerr:
	dc.b	"[CFD] IDE err=",0
dbg_space:
	dc.b	" ",0
dbg_identify_dump:
	dc.b	"[CFD] IDENTIFY:",13,10,0
dbg_identify_raw:
	dc.b	"[CFD] IDENTIFY (raw):",13,10,0
dbg_id_maxmulti:
	dc.b	"  Max Multi (W47):      ",0
dbg_id_caps:
	dc.b	"  Capabilities (W49):   ",0
dbg_id_multisect:
	dc.b	"  Multi Setting (W59):  ",0
dbg_id_lba:
	dc.b	"  LBA Sectors (W60-61): ",0
dbg_id_dma:
	dc.b	"  DMA Modes (W63):      ",0
dbg_id_pio:
	dc.b	"  PIO Modes (W64):      ",0
dbg_id_udma:
	dc.b	"  UDMA Modes (W88):     ",0
dbg_transfer:
	dc.b	"[CFD] Transfer: ",0
dbg_word:
	dc.b	"WORD",13,10,0
dbg_byte:
	dc.b	"BYTE",13,10,0
dbg_voltage5v:
	dc.b	"[CFD] Voltage: 5V",13,10,0
dbg_tupleconfig:
	dc.b	"[CFD] Tuple CISTPL_CONFIG found",13,10,0
dbg_tuplenone:
	dc.b	"[CFD] No tuples found",13,10,0
dbg_idestatus:
	dc.b	"[CFD] IDE status=",0
dbg_multimax:
	dc.b	"[CFD] ..card supports max multi: ",0
dbg_multiset:
	dc.b	"[CFD] ..setting multi mode to: ",0
dbg_multiok:
	dc.b	"[CFD] ..OK",13,10,0
dbg_multifail:
	dc.b	"[CFD] ..FAILED (using 1)",13,10,0
dbg_multinosup:
	dc.b	"[CFD] ..not supported",13,10,0
dbg_multisizerw:
	dc.b	"[CFD] ..multi-sector RW size: ",0
dbg_multi_test:
	dc.b	"[CFD] ..testing multi-sector capability...",13,10,0
dbg_multi_ok256:
	dc.b	"[CFD] ..DRQ issue not detected",13,10
	dc.b	"[CFD] ..auto-enabling 256 sector mode",13,10,0
dbg_multi_drq_issue:
	dc.b	"[CFD] ..DRQ issue detected, using firmware value",13,10,0
dbg_multi_skip:
	dc.b	"[CFD] ..auto-detection skipped",13,10,0
	endc
	even

s_inittable:
	dc.l	CFD_Sizeof
	dc.l	s_functable
	dc.l	0			;no InitStruct() table
	dc.l	s_initfunc

s_functable:
	dc.w	-1			;"Offsets not pointers"
	dc.w	Open-s_functable
	dc.w	Close-s_functable
	dc.w	Expunge-s_functable
	dc.w	Null-s_functable
	dc.w	BeginIO-s_functable
	dc.w	AbortIO-s_functable
	dc.w	-1

;--- for ramlib/LoadDevice() -------------------------------
; d0 <- &Device
; a0 <- SegList
; a6 <- &ExecBase
; d0 -> &Device or 0

s_initfunc:
	move.l	a4,-(sp)
	move.l	d0,a4			;&Device
	move.l	a6,CFD_ExecBase(a4)
	move.l	a0,CFD_SegList(a4)
	move.b	#NT_DEVICE,LN_Type(a4)
	lea	s_name(pc),a0
	move.l	a0,LN_Name(a4)
	move.b	#LIBF_SUMUSED+LIBF_CHANGED,LIB_Flags(a4)
	move.l	#FILE_VERSION<<16+FILE_REVISION,LIB_Version(a4)
	lea	s_idstring(pc),a0
	move.l	a0,LIB_IdString(a4)
	moveq.l	#36,d0
	lea	CardName(pc),a1
	CALLEXEC OpenResource
	move.l	d0,CFD_CardBase(a4)
	beq.s	s_if_end

	move.l	a4,d0
s_if_end:
	move.l	(sp)+,a4
	rts

;--- for exec/OpenDevice() ---------------------------------
; d0 <- Unit #
; d1 <- Flags
; a1 <- &IORequest
; a6 <- &Device

Open:
	movem.l	d2-d3/a2-a4,-(sp)
	move.l	d1,d3			;Flags
	move.l	a1,a2			;&IORequest
	move.l	a6,a4			;&Device
	tst.l	d0
	bne.s	op_badunit

	move.l	CFD_Unit(a4),d2
	bne.s	op_ok

	bsr.w	NewUnit
	move.l	d0,d2
	beq.s	op_error

	move.l	d0,CFD_Unit(a4)
op_ok:
	move.l	d2,a3			;&Unit
	or.w	d3,CFU_OpenFlags(a3)
	move.l	d2,IO_Unit(a2)
	addq.w	#1,LIB_OpenCnt(a4)
	addq.w	#1,UN_OpenCnt(a3)
	and.b	#~LIBF_DELEXP,LIB_Flags(a4)
	moveq.l	#0,d0
op_end:
	move.b	d0,IO_Error(a2)
	movem.l	(sp)+,d2-d3/a2-a4
	rts

op_badunit:
	moveq.l	#TDERR_BADUNITNUM,d0
	bra.s	op_end

op_error:
	moveq.l	#IOERR_OPENFAIL,d0
	bra.s	op_end

;--- for exec/CloseDevice() --------------------------------
; a1 <- &IORequest
; a6 <- &Device
; d0 -> SegList or 0

Close:
	movem.l	a2-a4,-(sp)
	move.l	a1,a2			;&IORequest
	move.l	a6,a4			;&Device
	move.l	IO_Unit(a2),a3		;&Unit
	moveq.l	#-1,d0
	move.l	d0,IO_Device(a2)
	move.l	d0,IO_Unit(a2)
	move.l	a3,d0
	ble.s	cl_1

	subq.w	#1,UN_OpenCnt(a3)
cl_1:
	moveq.l	#0,d0
	subq.w	#1,LIB_OpenCnt(a4)
	bgt.s	cl_end			;still needed

	moveq.l	#LIBF_DELEXP,d1
	and.b	LIB_Flags(a4),d1
	beq.s	cl_end			;may still stay

	bsr.s	Expunge			;or not
cl_end:
	movem.l	(sp)+,a2-a4
	rts

;--- for MemHandler/Expunge() ------------------------------
; a6 <- &Device
; d0 -> SegList or 0

Expunge:
	movem.l	d2/a4,-(sp)
	move.l	a6,a4			;&Device
	tst.w	LIB_OpenCnt(a4)
	beq.s	ex_now

	or.b	#LIBF_DELEXP,LIB_Flags(a4)
	moveq.l	#0,d0
	bra.s	ex_end
ex_now:
	CALLEXEC Forbid
	move.l	a4,a1
	CALLSAME Remove
	CALLSAME Permit
	move.l	CFD_Unit(a4),a1
	bsr.w	KillUnit
	move.l	CFD_SegList(a4),d2
	moveq.l	#0,d0
	move.w	LIB_NegSize(a4),d0
	move.l	a4,a1
	sub.l	d0,a1
	add.w	LIB_PosSize(a4),d0
	CALLEXEC FreeMem
	move.l	d2,d0
ex_end:
	movem.l	(sp)+,d2/a4
	rts

;--- for exec/SendIO() -------------------------------------
; a1 <- &IORequest
; a6 <- &Device

BeginIO:
	movem.l	a2-a4,-(sp)
	move.l	a1,a2			;IORequest
	move.l	IO_Unit(a2),a3		;&Unit
	move.l	a6,a4			;&Device
	bsr.s	FunctionIndex
	move.l	#$2ffffff3,d1
	btst	d0,d1
	bne.s	bio_quick

	and.b	#~IOF_QUICK,IO_Flags(a2)
	move.l	a3,a0
	move.l	a2,a1
	CALLEXEC PutMsg			;forward to daemon
bio_end:
	movem.l	(sp)+,a2-a4
	rts

bio_quick:
	or.b	#IOF_QUICK,IO_Flags(a2)
	lsl.l	#1,d0
	lea	bio_tab(pc),a6
	add.w	(a6,d0.l),a6
	jsr	(a6)
	move.b	d0,IO_Error(a2)
	bra.s	bio_end

;--- get function index ------------------------------------
; a2 <- &IORequest
; d0 -> Index 0..31

FunctionIndex:
	moveq.l	#0,d0
	move.w	IO_Command(a2),d0
	move.l	d0,d1
	cmp.w	#29,d0
	bcs.s	fi_end

	moveq.l	#29,d0
	cmp.w	#NSCMD_DEVICEQUERY,d1
	beq.s	fi_end

	moveq.l	#30,d0
	cmp.w	#NSCMD_TD_READ64,d1
	beq.s	fi_end

	moveq.l	#31,d0
	cmp.w	#NSCMD_TD_WRITE64,d1
	beq.s	fi_end

	moveq.l	#0,d0
fi_end:
	rts

bio_tab:
	dc.w	Unknown-bio_tab		;CMD_UNKNOWN
	dc.w	Null-bio_tab		;CMD_RESET
	dc.w	_Read-bio_tab		;CMD_READ
	dc.w	_Write-bio_tab		;CMD_WRITE
	dc.w	Null-bio_tab		;CMD_UPDATE
	dc.w	Null-bio_tab		;CMD_CLEAR
	dc.w	_Stop-bio_tab
	dc.w	_Start-bio_tab
	dc.w	_Flush-bio_tab
	dc.w	Null-bio_tab		;TD_MOTOR
	dc.w	Unknown-bio_tab
	dc.w	Unknown-bio_tab
	dc.w	Unknown-bio_tab
	dc.w	Unknown-bio_tab		;TD_CHANGENUM
	dc.w	_ChangeState-bio_tab	;TD_CHANGESTATE
	dc.w	_ProtStatus-bio_tab	;TD_PROTSTATUS
	dc.w	Unknown-bio_tab
	dc.w	Unknown-bio_tab
	dc.w	Unknown-bio_tab		;TD_GETDRIVETYPE
	dc.w	Unknown-bio_tab
	dc.w	_AddClient-bio_tab	;TD_ADDCHANGEINT
	dc.w	_RemClient-bio_tab	;TD_REMCHANGEINT
	dc.w	_GetGeometry-bio_tab	;TD_GETGEOMETRY
	dc.w	Unknown-bio_tab
	dc.w	Unknown-bio_tab
	dc.w	Unknown-bio_tab
	dc.w	Unknown-bio_tab
	dc.w	Unknown-bio_tab
	dc.w	_ScsiCmd-bio_tab	;HD_SCSICMD

	dc.w	_NSDInfo-bio_tab	;NSCMD_DEVICEQUERY

	dc.w	_Read64-bio_tab		;NSCMD_TD_READ64
	dc.w	_Write64-bio_tab	;NSCMD_WRITE64

bio_commands:
	dc.w	CMD_RESET
	dc.w	CMD_READ
	dc.w	CMD_WRITE
	dc.w	CMD_UPDATE
	dc.w	CMD_CLEAR
	dc.w	CMD_STOP
	dc.w	CMD_START
	dc.w	CMD_FLUSH
	dc.w	TD_MOTOR
	dc.w	TD_CHANGESTATE
	dc.w	TD_PROTSTATUS
	dc.w	TD_ADDCHANGEINT
	dc.w	TD_REMCHANGEINT
	dc.w	TD_GETGEOMETRY
	dc.w	HD_SCSICMD
	dc.w	NSCMD_DEVICEQUERY
	dc.w	"TJ"
	dc.w	NSCMD_TD_READ64
	dc.w	NSCMD_TD_WRITE64
	dc.w	0

;--- for Exec/AbortIO() ------------------------------------

AbortIO:
	movem.l	d2/a2/a6,-(sp)
	move.l	a1,a2			;&IORequest
	move.l	IO_Device(a2),a6
	move.l	CFD_ExecBase(a6),a6
	CALLSAME Forbid
	move.l	IO_Unit(a2),a0
	move.l	MP_MsgList(a0),d2
aio_loop:
	move.l	d2,a1
	move.l	(a1),d2
	beq.s	aio_end

	cmp.l	a1,a2
	bne.s	aio_loop

	CALLSAME Remove
	clr.l	IO_Actual(a2)
	move.b	#IOERR_ABORTED,IO_Error(a2)
	move.l	a2,a1
	CALLSAME ReplyMsg
	move.l	a2,d2
aio_end:
	CALLSAME Permit
	move.l	d2,d0
	movem.l	(sp)+,d2/a2/a6
	rts

;--- unused function ---------------------------------------

Unknown:
	clr.l	IO_Actual(a2)
	moveq.l	#IOERR_NOCMD,d0
	rts

;--- make new unit -----------------------------------------
; d0 <- Unit #
; d1 <- Flags
; d0 -> &Unit or 0

NewUnit:
	movem.l	d2-d4/a2-a3,-(sp)
	move.l	d0,d2
	move.l	d1,d3
	move.l	#CFU_Sizeof,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	CALLEXEC AllocMem
	move.l	d0,a3
	tst.l	d0
	beq.w	nu_end			;no memory

	move.l	a4,CFU_Device(a3)
	move.l	#CFU_Sizeof,CFU_UnitSize(a3)
	move.l	CFD_CardBase(a4),a0
	move.l	LIB_Version(a0),CFU_ResVersion(a3)
	lea	CFU_Clients(a3),a0
	INITLIST a0
	moveq.l	#2048>>8,d3
	lsl.l	#8,d3			;stack size
	moveq.l	#24,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	CALLSAME AllocMem
	move.l	d0,d2			;&MemEntry
	beq.w	nu_freeunit

	move.l	d0,a1
	move.w	#1,14(a1)
	moveq.l	#TC_Sizeof,d0
	add.l	d3,d0
	move.l	d0,20(a1)
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	CALLSAME AllocMem
	move.l	d2,a1
	move.l	d0,16(a1)
	beq.w	nu_freemementry

	move.l	d0,a2			;&Stack
	add.l	d3,a2			;&Task
	lea	s_name(pc),a0
	move.l	a0,LN_Name(a2)
	move.b	#NT_TASK,LN_Type(a2)
	move.l	a2,TC_SPUpper(a2)
	move.l	d0,TC_SPLower(a2)
	move.l	a2,a0
	move.l	a3,-(a0)
	move.l	d3,-(a0)
	move.l	a0,TC_SPReg(a2)
	lea	TC_MemEntry(a2),a0
	INITLIST a0
	lea	TC_MemEntry(a2),a0
	move.l	d2,a1
	CALLSAME AddHead
	move.l	a2,CFU_Process(a3)
	move.l	a3,TC_UserData(a2)
	moveq.l	#-1,d0
	CALLSAME AllocSignal
	move.l	d0,d4
	bmi.s	nu_freeall

	moveq.l	#0,d0
	bset	d4,d0
	move.l	d0,CFU_KillSig(a3)
	sub.l	a1,a1
	CALLSAME FindTask
	move.l	d0,CFU_KillTask(a3)
	move.l	a3,-(sp)
	move.l	a2,a1
	lea	UnitCode(pc),a2
	sub.l	a3,a3
	CALLSAME AddTask
	move.l	(sp)+,a3
	moveq.l	#0,d0
	bset	d4,d0
	CALLSAME Wait
	move.l	d4,d0
	CALLSAME FreeSignal
	tst.l	CFU_Process(a3)
	beq.s	nu_freeunit		;Task inactive
nu_end:
	move.l	a3,d0
	movem.l	(sp)+,d2-d4/a2-a3
	rts

nu_freeall:
	moveq.l	#TC_Sizeof,d0
	add.l	d3,d0
	move.l	a2,a1
	CALLSAME FreeMem
nu_freemementry:
	moveq.l	#24,d0
	move.l	d2,a1
	CALLSAME FreeMem
nu_freeunit:
	move.l	#CFU_Sizeof,d0
	move.l	a3,a1
	CALLSAME FreeMem
	sub.l	a3,a3
	bra.s	nu_end

;--- free unit ---------------------------------------------
; a1 <- &Unit or 0

KillUnit:
	movem.l	d2/a3-a4,-(sp)
	move.l	a1,d0
	beq.s	ku_end

	move.l	a1,a3			;&Unit
	move.l	CFU_Device(a3),a4	;&Device
	moveq.l	#CFUF_TERM,d0
	and.w	CFU_Flags(a3),d0
	bne.s	ku_end

	moveq.l	#-1,d0
	CALLEXEC AllocSignal
	move.l	d0,d2
	bmi.s	ku_end

	moveq.l	#0,d1
	bset	d0,d1
	move.l	d1,CFU_KillSig(a3)
	sub.l	a1,a1
	CALLSAME FindTask
	move.l	d0,CFU_KillTask(a3)
	or.w	#CFUF_STOPPED+CFUF_FLUSH+CFUF_TERM,CFU_Flags(a3)
	move.l	CFU_Signals3(a3),d0
	move.l	CFU_Process(a3),a1
	CALLSAME Signal
	move.l	CFU_KillSig(a3),d0
	CALLSAME Wait
	move.l	d2,d0
	CALLSAME FreeSignal
	move.l	#CFU_Sizeof,d0
	move.l	a3,a1
	CALLSAME FreeMem
	moveq.l	#0,d0
ku_end:
	movem.l	(sp)+,d2/a3-a4
	rts

;*** the synchronous shit **********************************
;--- suspend all work --------------------------------------

_Stop:
	or.w	#CFUF_STOPPED,CFU_Flags(a3)
	moveq.l	#0,d0
	rts

;--- reject pending requests -------------------------------

_Flush:
	or.w	#CFUF_FLUSH,CFU_Flags(a3)
	bra.s	_s_signal

;--- go on now ---------------------------------------------

_Start:
	and.w	#~CFUF_STOPPED,CFU_Flags(a3)
_s_signal:
	move.l	CFU_Signals3(a3),d0
	sub.l	CFU_Signals2(a3),d0
	move.l	CFU_Process(a3),a1
	CALLEXEC Signal
	moveq.l	#0,d0
	rts

;--- give NewStyleDevice information -----------------------

_NSDInfo:
	moveq.l	#IOERR_BADLENGTH,d0
	moveq.l	#QR_Sizeof,d1
	cmp.l	IO_Length(a2),d1
	bgt.s	_ni_end			;target buffer too small

	move.l	IO_Data(a2),d1
	beq.s	_ni_end			;no target buffer

	move.l	d1,a1			;&target
	clr.l	(a1)+			;QR_DevQueryFormat
	moveq.l	#QR_Sizeof,d0
	move.l	d0,(a1)+		;QR_SizeAvailable
	move.l	d0,IO_Actual(a2)
	move.w	#5,(a1)+		;QR_DeviceType
	clr.w	(a1)+			;QR_DeviceSubType
	lea	bio_commands(pc),a0
	move.l	a0,(a1)			;QR_SupportedCommands
	moveq.l	#0,d0
_ni_end:
	rts

;--- give geometry info ------------------------------------

_GetGeometry:
	moveq.l	#IOERR_BADLENGTH,d0
	moveq.l	#DG_Sizeof,d1
	cmp.l	IO_Length(a2),d1
	bne.s	_gg_end

	move.l	IO_Data(a2),d1
	beq.s	_gg_end

	move.l	d1,a1			;&target
	move.l	CFU_BlockSize(a3),d0
	move.l	d0,(a1)+		;DG_SectorSize
	move.l	CFU_DriveSize(a3),d0
	move.l	d0,(a1)+		;DG_TotalSectors
	moveq.l	#0,d0
	move.w	CFU_ConfigBlock+12(a3),d0
	beq.s	_gg_linear

	moveq.l	#0,d1
	move.w	CFU_ConfigBlock+6(a3),d1
	beq.s	_gg_linear

	move.l	d0,12(a1)		;DG_TrackSectors
	move.l	d1,8(a1)		;DG_Heads
	mulu.w	d0,d1
	move.l	d1,4(a1)		;DG_CylSectors
	move.l	CFU_DriveSize(a3),d0
	bsr.w	UDivMod32
	move.l	d0,(a1)			;DG_Cylinders
	add.w	#16,a1
	bra.s	_gg_bufmemtype
_gg_linear:
	move.l	CFU_DriveSize(a3),d0
	move.l	d0,(a1)+		;DG_Cylinders
	moveq.l	#1,d0
	move.l	d0,(a1)+		;DG_CylSectors
	move.l	d0,(a1)+		;DG_Heads
	move.l	d0,(a1)+		;DG_TrackSectors
_gg_bufmemtype:
	moveq.l	#1,d0
	move.l	d0,(a1)+		;DG_BufMemType
	moveq.l	#0,d0
	tst.w	CFU_PLength(a3)
	ble.s	_gg_devicetype

	moveq.l	#$3f,d0
	and.b	CFU_ConfigBlock(a3),d0
_gg_devicetype:
	move.b	d0,(a1)+		;DG_DeviceType
	move.b	#1,(a1)+		;DG_Flags = DG_REMOVABLE
	clr.w	(a1)			;DG_Reserved
	moveq.l	#DG_Sizeof,d0
	move.l	d0,IO_Actual(a2)
	moveq.l	#0,d0
_gg_end:
	rts

;--- Disk inserted? ----------------------------------------

_ChangeState:
	tst.w	CFU_CardReady(a3)
	beq.s	_cs_defer		;wait for pending disk recognition

	moveq.l	#1,d0
	tst.l	CFU_DriveSize(a3)
	beq.s	_cs_1

	moveq.l	#0,d0
_cs_1:
	move.l	d0,IO_Actual(a2)
	moveq.l	#0,d0
	rts

_cs_defer:
	and.b	#~IOF_QUICK,IO_Flags(a2)
	move.l	a3,a0
	move.l	a2,a1
	JMPEXEC PutMsg			;forward to daemon

;--- read only disk? ---------------------------------------

_ProtStatus:
	moveq.l	#0,d0
	move.l	d0,IO_Actual(a2)
Null:
	moveq.l	#0,d0
	rts

;--- add diskchange message client -------------------------

_AddClient:
	moveq.l	#IOERR_BADLENGTH,d0
	moveq.l	#IS_Sizeof,d1
	cmp.l	IO_Length(a2),d1
	bne.s	_ac_end

	tst.l	IO_Data(a2)
	beq.s	_ac_end

	addq.w	#1,LIB_OpenCnt(a4)	;safety
	move.l	d1,IO_Actual(a2)
	move.b	#NT_MESSAGE,LN_Type(a2)
	and.b	#~IOF_QUICK,IO_Flags(a2)
	CALLEXEC Forbid
	lea	CFU_Clients(a3),a0
	move.l	a2,a1
	CALLSAME AddHead
	CALLSAME Permit
	moveq.l	#0,d0
_ac_end:
	rts

;--- remove disk change message client ---------------------

_RemClient:
	CALLEXEC Forbid
	move.l	CFU_Clients(a3),d1
_rc_search:
	move.l	d1,a1
	move.l	(a1),d1
	beq.s	_rc_end			;not in list, leave alone

	cmp.l	a1,a2
	bne.s	_rc_search

	CALLSAME Remove
	and.b	#~IOF_QUICK,IO_Flags(a2)
	move.l	a2,a1
	CALLSAME ReplyMsg
	subq.w	#1,LIB_OpenCnt(a4)
_rc_end:
	CALLSAME Permit
	moveq.l	#0,d0
	rts

;*** the asynchronous shit *********************************
; a2 <- &IORequest
; d0 -> error code

;--- reset unit --------------------------------------------

;_Reset:

;--- write data --------------------------------------------

_Write:
	clr.l	IO_Actual(a2)
_Write64:
	lea	_WB2(pc),a6
	bra.s	_r_start

;--- read data ---------------------------------------------

_Read:
	clr.l	IO_Actual(a2)
_Read64:
	lea	_ReadBlocks(pc),a6
_r_start:
	move.l	d2,-(sp)
	move.w	CFU_BlockShift(a3),d2
	bmi.s	_r_odd			;Block size is not a power of 2

	move.l	IO_Actual(a2),d0
	ror.l	d2,d0
	move.l	IO_Offset(a2),d1
	lsr.l	d2,d1
	or.l	d1,d0			;Block #
	move.l	IO_Length(a2),d1
	lsr.l	d2,d1			;Block count
	move.l	IO_Data(a2),a1		;&user buffer
	jsr	(a6)			;do read/write
	lsl.l	d2,d0			;Bytes transferred
_r_end:
	move.l	d0,IO_Actual(a2)
	move.b	CFU_IOErr(a3),d0
	move.l	(sp)+,d2
	rts

_r_odd:
	move.l	CFU_BlockSize(a3),d2
	move.l	IO_Offset(a2),d1
	move.w	IO_Actual(a2),d1
	swap	d1
	divu.w	d2,d1
	move.l	d1,d0
	swap	d0
	move.w	IO_Offset(a2),d1
	divu.w	d2,d1
	move.w	d1,d0
	move.l	d0,-(sp)
	move.l	IO_Length(a2),d0
	move.l	d2,d1
	bsr.w	UDivMod32
	move.l	d0,d1
	move.l	(sp)+,d0
	move.l	IO_Data(a2),a1
	jsr	(a6)
	move.l	d2,d1
	bsr.w	UMul32
	bra.s	_r_end

;--- write back pending buffers (unused) -------------------

;_Update:

;--- invalidate pending buffers (unused) -------------------

;_Clear:

;--- SCSI direct -------------------------------------------

_ScsiCmd:
	move.l	a2,-(sp)
	moveq.l	#IOERR_BADLENGTH,d0
;	moveq.l	#SCSI_Sizeof,d1		;hdwrench.library occasionally writes..
;	cmp.l	IO_Length(a2),d1	;..a copy of SCSI_CmdLength here
;	bne.s	_sc_end

	move.l	IO_Data(a2),d1
	beq.s	_sc_end

	move.l	d1,a2			;&SCSICmd
	tst.w	CFU_PLength(a3)
	bgt.s	_sc_atapi

	cmp.w	#6,SCSI_CmdLength(a2)
	bcs.s	_sc_end

	move.l	SCSI_Command(a2),d1
	beq.s	_sc_end

	move.l	d1,a0			;&commandline
	move.b	(a0),d0
	lea	_sc_tab(pc),a1
	move.l	a1,a6
_sc_search:
	move.w	(a1)+,d1
	beq.s	_sc_unknown

	cmp.b	d0,d1
	beq.s	_sc_found

	addq.l	#2,a1
	bra.s	_sc_search
_sc_found:
	lsr.w	#8,d1
	cmp.w	SCSI_CmdLength(a2),d1
	bne.s	_sc_unknown		;wrong command line length

	move.w	d1,SCSI_CmdActual(a2)
	add.w	(a1),a6
	jsr	(a6)
	bra.s	_sc_ready
_sc_unknown:
	move.w	#$0102,d0
_sc_ready:
	move.w	d0,CFU_SCSIState(a3)
	move.b	d0,SCSI_Status(a2)
	beq.s	_sc_end

	btst	#1,SCSI_Flags(a2)
	beq.s	_sc_err2

	move.w	SCSI_SenseLength(a2),d1
	move.l	SCSI_SenseData(a2),a1
	bsr.w	_GetSense
	move.w	d0,SCSI_SenseActual(a2)
_sc_err2:
	moveq.l	#45,d0			;"general SCSI error"..
	move.b	CFU_IOErr(a3),d1
	beq.s	_sc_end

	move.b	d1,d0			;..or a more specific Code
_sc_end:
	move.l	(sp)+,a2
	clr.l	IO_Actual(a2)		;is this really needed...
	rts

_sc_atapi:
	move.l	a2,a0
	bsr.w	_Packet
	bra.s	_sc_end

_sc_tab:
	dc.w	10<<8+READ10, _Read10-_sc_tab
	dc.w	10<<8+WRITE10, _Write10-_sc_tab
	dc.w	10<<8+READCAPACITY, _ReadCapacity-_sc_tab
	dc.w	6<<8+READ06, _Read06-_sc_tab
	dc.w	6<<8+WRITE06, _Write06-_sc_tab
	dc.w	6<<8+TESTUNITREADY, _TestUnitReady-_sc_tab
	dc.w	6<<8+REQUESTSENSE, _RequestSense-_sc_tab
	dc.w	6<<8+INQUIRY, _Inquiry-_sc_tab
	dc.w	6<<8+ATA_IDENTIFY, _ATAIdentify-_sc_tab
	dc.w	6<<8+CFD_GETCONFIG, _CFDGetConfig-_sc_tab
	dc.w	0

;*** SCSI Emulation ****************************************
; a2 <- &SCSICmd
; d0 -> SCSI_Status

;--- TEST UNIT READY ---------------------------------------

_TestUnitReady:
	moveq.l	#0,d0
	tst.l	CFU_DriveSize(a3)
	bne.s	_tur_end

	move.w	#$0202,d0
_tur_end:
	rts

;--- REQUEST SENSE -----------------------------------------

_RequestSense:
	move.w	CFU_SCSIState(a3),d0
	move.l	SCSI_Length(a2),d1
	move.l	(a2),a1			;SCSI_Data
	bsr.w	_GetSense
	move.l	d0,SCSI_Actual(a2)
	moveq.l	#0,d0
	rts

;--- INQUIRY -----------------------------------------------

_Inquiry:
	moveq.l	#0,d0
	moveq.l	#56/4,d1
_iq_vs:
	move.l	d0,-(sp)		;vendor specific
	subq.w	#1,d1
	bgt.s	_iq_vs

	lea	CFU_ConfigBlock+46+8(a3),a0
	move.l	-(a0),-(sp)
	move.l	-(a0),-(sp)		;Revision
	lea	CFU_ConfigBlock+54(a3),a0
	moveq.l	#24,d1
	sub.l	d1,sp
	move.l	sp,a1
_iq_name:
	move.b	(a0)+,d0
	move.b	d0,(a1)+		;vendor, product
	cmp.w	#18,d1
	bcs.s	_iq_nnext

	cmp.b	#" ",d0
	bne.s	_iq_nnext

	subq.l	#1,a0			;pad vendor
_iq_nnext:
	subq.w	#1,d1
	bgt.s	_iq_name

	move.l	SCSI_Length(a2),d1
	moveq.l	#96,d0
	cmp.l	d1,d0
	bcc.s	_iq_1

	move.l	d0,d1			;limit to available length
_iq_1:
	move.l	d1,SCSI_Actual(a2)
	moveq.l	#-5,d0
	add.l	d1,d0
	ror.l	#8,d0
	or.b	#$20,d0
	move.l	d0,-(sp)		;info length, 16bit device
	move.l	#$00800222,-(sp)	;removable, SCSI-2, autosense
	move.l	d1,d0
	beq.s	_iq_2

	move.l	(a2),d1			;SCSI_Data
	beq.s	_iq_2

	move.l	d1,a1			;&target
	move.l	sp,a0
_iq_copy:
	move.b	(a0)+,(a1)+
	subq.w	#1,d0
	bgt.s	_iq_copy
_iq_2:
	add.w	#96,sp
	moveq.l	#0,d0
	rts

;--- ATA IDENTIFY PASSTHROUGH ------------------------------
; Returns cached 512-byte IDENTIFY data from CFU_ConfigBlock
; This is a vendor-specific extension (command $EC)
;
; Input:
;   a2 = &SCSICmd structure
;   a3 = CFU pointer
;
; Output:
;   d0 = SCSI status (0 = success)
;   SCSI_Actual = bytes copied
;   SCSI_Data buffer filled with IDENTIFY data
;
_ATAIdentify:
	move.l	SCSI_Length(a2),d1
	beq.s	_aid_end		;no buffer

	move.l	(a2),d0			;SCSI_Data
	beq.s	_aid_end		;no buffer pointer

	;Limit to 512 bytes (IDENTIFY data size)
	cmp.l	#512,d1
	bls.s	_aid_1
	move.l	#512,d1
_aid_1:
	move.l	d1,SCSI_Actual(a2)
	move.l	d0,a1			;destination
	lea	CFU_ConfigBlock(a3),a0	;source (cached IDENTIFY data)

	;Copy d1 bytes from a0 to a1
_aid_copy:
	move.b	(a0)+,(a1)+
	subq.l	#1,d1
	bgt.s	_aid_copy

_aid_end:
	moveq.l	#0,d0			;success
	rts

;--- CFD GET CONFIG ----------------------------------------
; Returns driver internal configuration
; This is a vendor-specific extension (command $ED)
;
; Input:
;   a2 = &SCSICmd structure
;   a3 = CFU pointer
;
; Output:
;   d0 = SCSI status (0 = success)
;   SCSI_Actual = bytes copied (actual struct size)
;   SCSI_Data buffer filled with config data:
;
; Structure layout (extensible - check struct_size for version):
;     Offset 0-1:  struct_size (total bytes in this structure, for versioning)
;     Offset 2:    Driver major version
;     Offset 3:    Driver minor version
;     Offset 4-5:  CFU_OpenFlags (mount Flags field)
;     Offset 6-7:  CFU_MultiSize (firmware-reported multi-sector)
;     Offset 8-9:  CFU_MultiSizeRW (actual multi-sector used)
;     Offset 10:   CFU_ReceiveMode (read transfer mode: 0=WORD, 1-3=BYTE)
;     Offset 11:   CFU_WriteMode (write transfer mode)
;     --- v1.37 structure ends here (12 bytes) ---
;     Future versions may add more fields after offset 12
;
; Clients should:
;   1. Request a large buffer (e.g., 64 bytes)
;   2. Check struct_size to know what fields are available
;   3. Only access fields within struct_size bounds
;
CFD_CONFIG_SIZE	= 12			;current structure size

_CFDGetConfig:
	move.l	SCSI_Length(a2),d1
	beq.s	_cgc_end		;no buffer

	move.l	(a2),d0			;SCSI_Data
	beq.s	_cgc_end		;no buffer pointer

	;Limit to CFD_CONFIG_SIZE bytes
	cmp.l	#CFD_CONFIG_SIZE,d1
	bls.s	_cgc_1
	move.l	#CFD_CONFIG_SIZE,d1
_cgc_1:
	move.l	d1,SCSI_Actual(a2)
	move.l	d0,a1			;destination

	;Build config data in buffer
	move.w	#CFD_CONFIG_SIZE,(a1)+	;offset 0-1: structure size (for versioning)
	move.b	#FILE_VERSION,(a1)+	;offset 2: major version
	move.b	#FILE_REVISION,(a1)+	;offset 3: minor version
	move.w	CFU_OpenFlags(a3),(a1)+	;offset 4-5: flags
	move.w	CFU_MultiSize(a3),(a1)+	;offset 6-7: firmware multi
	move.w	CFU_MultiSizeRW(a3),(a1)+ ;offset 8-9: actual multi
	move.b	CFU_ReceiveMode(a3),(a1)+ ;offset 10: read mode
	move.b	CFU_WriteMode(a3),(a1)+	;offset 11: write mode

_cgc_end:
	moveq.l	#0,d0			;success
	rts

;--- READ CAPACITY -----------------------------------------

_ReadCapacity:
	move.l	(a2),d1			;SCSI_Data
	beq.s	_rca_error		;no buffer

	moveq.l	#8,d0
	cmp.l	SCSI_Length(a2),d0
	beq.s	_rca_1
	bcc.s	_rca_error
_rca_1:
	move.l	d0,SCSI_Actual(a2)
	move.l	d1,a1			;&target
	move.l	CFU_DriveSize(a3),d0
	beq.s	_rca_nodisk

	subq.l	#1,d0
	move.l	d0,(a1)+
	move.l	CFU_BlockSize(a3),d0
	move.l	d0,(a1)
	moveq.l	#0,d0
_rca_end:
	rts

_rca_error:
	move.b	#IOERR_BADLENGTH,CFU_IOErr(a3)
	moveq.l	#2,d0
	bra.s	_rca_end

_rca_nodisk:
	move.b	#TDERR_DISKCHANGED,CFU_IOErr(a3)
	move.w	#$0202,d0
	bra.s	_rca_end

;--- WRITE06 -----------------------------------------------

_Write06:
	move.l	d2,-(sp)
	btst	#0,SCSI_Flags(a2)
	bne.s	_r06_error		;wrong data direction

	lea	_WB2(pc),a6
	bra.s	_r06_start

;--- READ06 ------------------------------------------------

_Read06:
	move.l	d2,-(sp)
	btst	#0,SCSI_Flags(a2)
	beq.s	_r06_error		;wrong data direction

	lea	_ReadBlocks(pc),a6
_r06_start:
	move.l	(a2),d1			;SCSI_Data
	beq.s	_r06_error		;no buffer

	move.l	d1,a1			;&user buffer
	move.l	SCSI_Command(a2),a0
	moveq.l	#0,d1
	move.b	4(a0),d1
	bne.s	_r06_1

	move.w	#$100,d1		;0 = 256 Blocks
_r06_1:
	move.l	SCSI_Length(a2),d0
	lsr.l	#8,d0
	lsr.l	#1,d0
	cmp.l	d1,d0
	bcc.s	_r06_2

	move.l	d0,d1			;limit to buffer size
_r06_2:
	move.l	(a0),d0
	and.l	#$001fffff,d0		;Block #
	move.l	d1,d2
	jsr	(a6)			;do read/write
	move.l	d0,d1			;blocks transferred
	lsl.l	#8,d0
	lsl.l	#1,d0
	move.l	d0,SCSI_Actual(a2)	;bytes transferred
	moveq.l	#2,d0
	cmp.l	d1,d2
	bne.s	_r06_end		;error

	moveq.l	#0,d0			;OK
_r06_end:
	move.l	(sp)+,d2
	rts

_r06_error:
	move.b	#IOERR_BADLENGTH,CFU_IOErr(a3)
	moveq.l	#2,d0
	bra.s	_r06_end

;--- WRITE10 -----------------------------------------------

_Write10:
	move.l	d2,-(sp)
	btst	#0,SCSI_Flags(a2)
	bne.s	_r10_error		;wrong data direction

	lea	_WB2(pc),a6
	bra.s	_r10_start

;--- READ10 ------------------------------------------------

_Read10:
	move.l	d2,-(sp)
	btst	#0,SCSI_Flags(a2)
	beq.s	_r10_error		;wrong data direction

	lea	_ReadBlocks(pc),a6
_r10_start:
	move.l	(a2),d1			;SCSI_Data
	beq.s	_r10_error		;no buffer

	move.l	d1,a1			;&buffer
	move.l	SCSI_Command(a2),a0
	moveq.l	#0,d1
	move.b	7(a0),d1
	lsl.w	#8,d1
	move.b	8(a0),d1		;block count
	move.l	SCSI_Length(a2),d0
	lsr.l	#8,d0
	lsr.l	#1,d0
	cmp.l	d1,d0
	bcc.s	_r10_1

	move.l	d0,d1			;limit to buffer size
_r10_1:
	move.l	2(a0),d0		;Block #
	move.l	d1,d2
	jsr	(a6)			;do read/write
	move.l	d0,d1			;blocks transferred
	lsl.l	#8,d0
	lsl.l	#1,d0
	move.l	d0,SCSI_Actual(a2)	;bytes transferred
	moveq.l	#2,d0
	cmp.l	d1,d2
	bne.s	_r10_end		;error

	moveq.l	#0,d0			;OK
_r10_end:
	move.l	(sp)+,d2
	rts

_r10_error:
	move.b	#IOERR_BADLENGTH,CFU_IOErr(a3)
	moveq.l	#2,d0
	bra.s	_r10_end

;--- build Sense Code --------------------------------------
; d0 <- internal error code << 8 + SCSI_Status
; d1 <- buffer size
; a1 <- &target
; d0 -> Sense length

_GetSense:
	cmp.w	#18,d1
	bcs.s	_gs_error

	move.l	a1,d1
	beq.s	_gs_error		;no buffer

	lea	_gs_tab(pc),a0
	lsr.w	#8,d0
	mulu.w	#6,d0
	add.l	d0,a0
	move.w	#$7000,(a1)+		;"error in last command", 0
	move.b	(a0)+,(a1)+		;Sense Key
	clr.b	(a1)+			;Information
	moveq.l	#11,d0
	move.l	d0,(a1)+		;0, 0, 0, additional length
	clr.l	(a1)+
	move.b	(a0)+,(a1)+		;Sense Code
	move.b	(a0)+,(a1)+		;Extended Sense Code
	clr.b	(a1)+			;FRU
	move.b	(a0)+,(a1)+		;Specific Information
	move.b	(a0)+,(a1)+		;byte position of error
	move.b	(a0)+,(a1)+
	moveq.l	#18,d0
_gs_end:
	rts

_gs_error:
	moveq.l	#0,d0
	bra.s	_gs_end

; Sense Key, Sense Code, Ext SenseCode, Specific Info, 2 * Error Position

_gs_tab:
	dc.b	0,   0, 0,   0, 0, 0	;all OK
	dc.b	5, $20, 0, $c0, 0, 0	;unknown command
	dc.b	2, $3a, 0,   0, 0, 0	;no disk
	dc.b	5, $21, 0, $c0, 0, 2	;invalid block #

;*** Serial Debug *******************************************
;
; Serial debug output via RawPutChar (directly to serial port)
; Enable with mount Flags = 8
;
; Usage:
;   DBGMSG <string_label>    - output string if debug enabled
;   DBGCHR <char>            - output single char if debug enabled
;   DBGNUM                   - output d0.l as hex if debug enabled
;

	ifd	DEBUG
DBGMSG	macro
	lea	\1(pc),a0
	bsr.w	_DebugStr
	endm

DBGCHR	macro
	moveq.l	#\1,d0
	bsr.w	_DebugChar
	endm

DBGNUM	macro
	bsr.w	_DebugHex
	endm
	else
DBGMSG	macro
	endm
DBGCHR	macro
	endm
DBGNUM	macro
	endm
	endc

	ifd	DEBUG
;--- _DebugChar: output single char in d0 if debug enabled ---
; d0 = character to output
; a3 = unit, a4 = device
; preserves all registers
_DebugChar:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dc_end
	movem.l	d0-d1/a0-a1/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	jsr	RawPutChar(a6)
	movem.l	(sp)+,d0-d1/a0-a1/a6
_dc_end:
	rts

;--- _DebugStr: output null-terminated string ---
; a0 = pointer to string
; a3 = unit, a4 = device
; preserves all registers
_DebugStr:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_ds_end
	movem.l	d0-d1/a0-a1/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
_ds_loop:
	moveq.l	#0,d0
	move.b	(a0)+,d0
	beq.s	_ds_done
	jsr	RawPutChar(a6)
	bra.s	_ds_loop
_ds_done:
	movem.l	(sp)+,d0-d1/a0-a1/a6
_ds_end:
	rts

;--- _DebugHex: output d0.l as 8-digit hex ---
; d0 = value to output
; a3 = unit, a4 = device
; preserves all registers
_DebugHex:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dh_end
	movem.l	d0-d3/a0-a1/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	move.l	d0,d2
	moveq.l	#7,d3			;8 digits
_dh_loop:
	rol.l	#4,d2
	moveq.l	#$0f,d0
	and.l	d2,d0
	cmp.b	#10,d0
	bcs.s	_dh_digit
	addq.b	#'A'-'0'-10,d0
_dh_digit:
	add.b	#'0',d0
	jsr	RawPutChar(a6)
	dbra	d3,_dh_loop
	movem.l	(sp)+,d0-d3/a0-a1/a6
_dh_end:
	rts

;--- _DebugNewline: output CR+LF ---
_DebugNewline:
	moveq.l	#13,d0
	bsr.s	_DebugChar
	moveq.l	#10,d0
	bra.s	_DebugChar

;--- _DebugATAStr: output ATA string ---
; a0 = pointer to ATA string
; d1 = length in bytes
; Note: uses d2 for loop counter since RawPutChar clobbers d0-d1
; Spaces are shown as dots for visibility
_DebugATAStr:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_das_end
	movem.l	d0-d2/a0-a1/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	subq.w	#1,d1
	move.w	d1,d2			;use d2 as loop counter (RawPutChar clobbers d1)
_das_loop:
	moveq.l	#0,d0
	move.b	(a0)+,d0		;read byte in normal order
	beq.s	_das_skip
	cmp.b	#' ',d0
	bcs.s	_das_skip		;skip if < space
	bne.s	_das_print		;print if > space
	moveq.l	#'.',d0			;replace space with dot
_das_print:
	jsr	RawPutChar(a6)
_das_skip:
	dbra	d2,_das_loop		;d2 is safe from RawPutChar
	movem.l	(sp)+,d0-d2/a0-a1/a6
_das_end:
	rts

;--- _DebugCardInfo: output card identification ---
; Call after successful _GetIDEID
_DebugCardInfo:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dci_end
	movem.l	d0-d1/a0,-(sp)
	
	;Model name (words 27-46, offset 54, 40 bytes)
	DBGMSG	dbg_model
	lea	CFU_ConfigBlock+54(a3),a0
	moveq.l	#40,d1
	bsr.w	_DebugATAStr
	bsr.w	_DebugNewline
	
	;Serial number (words 10-19, offset 20, 20 bytes)
	DBGMSG	dbg_serial
	lea	CFU_ConfigBlock+20(a3),a0
	moveq.l	#20,d1
	bsr.w	_DebugATAStr
	bsr.w	_DebugNewline
	
	;Firmware (words 23-26, offset 46, 8 bytes)
	DBGMSG	dbg_firmware
	lea	CFU_ConfigBlock+46(a3),a0
	moveq.l	#8,d1
	bsr.w	_DebugATAStr
	bsr.w	_DebugNewline
	
	movem.l	(sp)+,d0-d1/a0
_dci_end:
	rts

;--- _DebugHexDump: dump IDENTIFY structure (512 bytes) ---
; Outputs 32 lines of 16 bytes each with offset
_DebugHexDump:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.w	_dhd_end
	movem.l	d0-d4/a0-a1/a6,-(sp)
	
	DBGMSG	dbg_identify_raw
	
	move.l	CFD_ExecBase(a4),a6
	lea	CFU_ConfigBlock(a3),a0
	moveq.l	#0,d3			;word counter (0,8,16,...248)
	moveq.l	#31,d4			;32 lines (0-31)
	
_dhd_line:
	;print word offset (W0, W8, W16... W248)
	moveq.l	#'W',d0
	jsr	RawPutChar(a6)
	move.w	d3,d0
	bsr.w	_DebugDecimal		;output decimal number
	moveq.l	#':',d0
	jsr	RawPutChar(a6)
	moveq.l	#' ',d0
	jsr	RawPutChar(a6)
	
	;print 8 words per line
	moveq.l	#7,d2
_dhd_word:
	move.w	(a0)+,d0
	bsr.w	_DebugHexWord
	moveq.l	#' ',d0
	jsr	RawPutChar(a6)
	dbra	d2,_dhd_word
	addq.w	#8,d3			;next line starts at word+8
	
	;newline
	moveq.l	#13,d0
	jsr	RawPutChar(a6)
	moveq.l	#10,d0
	jsr	RawPutChar(a6)
	
	dbra	d4,_dhd_line
	
	movem.l	(sp)+,d0-d4/a0-a1/a6
_dhd_end:
	rts

;--- _DebugHexByte: output d0.b as 2-digit hex ---
_DebugHexByte:
	movem.l	d0-d2,-(sp)
	move.b	d0,d2
	lsr.b	#4,d0
	bsr.s	_dhb_digit
	move.b	d2,d0
	and.b	#$0f,d0
	bsr.s	_dhb_digit
	movem.l	(sp)+,d0-d2
	rts
_dhb_digit:
	cmp.b	#10,d0
	bcs.s	_dhb_09
	add.b	#'A'-10,d0
	jmp	RawPutChar(a6)
_dhb_09:
	add.b	#'0',d0
	jmp	RawPutChar(a6)

;--- _DebugIdentifyFields: show labeled IDENTIFY fields ---
; Note: uses a2 for config block pointer (DBGMSG clobbers a0)
_DebugIdentifyFields:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.w	_dif_end
	movem.l	d0/a0/a2/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	lea	CFU_ConfigBlock(a3),a2
	
	DBGMSG	dbg_identify_dump
	
	;Word 47: Max multi-sector
	DBGMSG	dbg_id_maxmulti
	move.w	94(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline
	
	;Word 49: Capabilities
	DBGMSG	dbg_id_caps
	move.w	98(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline
	
	;Word 59: Multi-sector setting
	DBGMSG	dbg_id_multisect
	move.w	118(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline
	
	;Words 60-61: LBA capacity (swap words for display)
	DBGMSG	dbg_id_lba
	move.w	122(a2),d0		;Word 61 (high)
	bsr.w	_DebugHexWord
	move.w	120(a2),d0		;Word 60 (low)
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline
	
	;Word 63: Multiword DMA
	DBGMSG	dbg_id_dma
	move.w	126(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline
	
	;Word 64: PIO modes
	DBGMSG	dbg_id_pio
	move.w	128(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline
	
	;Word 88: Ultra DMA
	DBGMSG	dbg_id_udma
	move.w	176(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline
	
	movem.l	(sp)+,d0/a0/a2/a6
_dif_end:
	rts

;--- _DebugHexWord: output d0.w as 4-digit hex ---
_DebugHexWord:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dhw_end
	movem.l	d0-d1/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	move.w	d0,d1
	lsr.w	#8,d0
	bsr.w	_DebugHexByte
	move.w	d1,d0
	bsr.w	_DebugHexByte
	movem.l	(sp)+,d0-d1/a6
_dhw_end:
	rts

;--- _DebugTransferMode: show transfer mode (WORD/BYTE) ---
_DebugTransferMode:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dtm_end
	DBGMSG	dbg_transfer
	tst.b	CFU_WriteMode(a3)
	bne.s	_dtm_byte
	DBGMSG	dbg_word
	bra.s	_dtm_end
_dtm_byte:
	DBGMSG	dbg_byte
_dtm_end:
	rts

;--- _DebugDecimal: output d0.w as decimal (0-255) ---
; Uses stack to preserve values across RawPutChar calls
_DebugDecimal:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dd_end
	movem.l	d0-d3/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	moveq.l	#0,d2
	move.w	d0,d2			;d2 = value (preserved)
	moveq.l	#0,d3			;d3 = leading zero flag
	
	;hundreds digit
	moveq.l	#0,d0
_dd_h_loop:
	cmp.w	#100,d2
	bcs.s	_dd_h_done
	sub.w	#100,d2
	addq.w	#1,d0
	bra.s	_dd_h_loop
_dd_h_done:
	tst.w	d0
	beq.s	_dd_tens
	add.b	#'0',d0
	move.w	d2,-(sp)		;save d2
	jsr	RawPutChar(a6)
	move.w	(sp)+,d2		;restore d2
	moveq.l	#1,d3			;set leading flag
	
_dd_tens:
	;tens digit
	moveq.l	#0,d0
_dd_t_loop:
	cmp.w	#10,d2
	bcs.s	_dd_t_done
	sub.w	#10,d2
	addq.w	#1,d0
	bra.s	_dd_t_loop
_dd_t_done:
	tst.w	d0
	bne.s	_dd_t_print
	tst.w	d3
	beq.s	_dd_ones		;skip leading zero
_dd_t_print:
	add.b	#'0',d0
	move.w	d2,-(sp)		;save d2
	jsr	RawPutChar(a6)
	move.w	(sp)+,d2		;restore d2
	
_dd_ones:
	;ones digit (always print)
	move.w	d2,d0
	add.b	#'0',d0
	jsr	RawPutChar(a6)
	
	movem.l	(sp)+,d0-d3/a6
_dd_end:
	rts

;--- _DebugIDEStatus: show IDE status and error registers ---
; d0 = status register value
_DebugIDEStatus:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dis_end
	movem.l	d0-d1/a0,-(sp)
	move.l	d0,d1			;save status
	DBGMSG	dbg_idestatus
	move.l	d1,d0
	bsr.w	_DebugHex
	bsr.w	_DebugNewline
	DBGMSG	dbg_ideerr
	;Read error register
	move.l	CFU_IDEAddr(a3),a0
	moveq.l	#0,d0
	move.b	2(a0),d0		;error register at offset 2
	bsr.w	_DebugHex
	bsr.w	_DebugNewline
	movem.l	(sp)+,d0-d1/a0
_dis_end:
	rts
	endc

Wait40:
	lea	CFU_TimeReq(a3),a1
	move.w	#TR_ADDREQUEST,IO_Command(a1)
	moveq.l	#0,d0
	move.l	d0,TR_Seconds(a1)
	move.l	#40000,TR_Micros(a1)	;wait 40 ms
	JMPEXEC DoIO
Wait1:
	lea	CFU_TimeReq(a3),a1
	move.w	#TR_ADDREQUEST,IO_Command(a1)
	moveq.l	#0,d0
	move.l	d0,TR_Seconds(a1)
	move.l	#100,TR_Micros(a1)	;wait 0.1 ms
	JMPEXEC DoIO

UnitCode:
Test:

;- - contact parent - - - - - - - - - - - - - - - - - - - -

	sub.l	a1,a1
	move.l	(_AbsExecBase).w,a6
	CALLSAME FindTask
	move.l	d0,a2			;&Task
	move.l	TC_UserData(a2),a3	;&CompactFlashUnit
	move.l	CFU_Device(a3),a4	;&CompactFlashDevice

;- - make signals and ports - - - - - - - - - - - - - - - -

	moveq.l	#0,d2
	moveq.l	#-1,d0
	CALLSAME AllocSignal
	bset	d0,d2
	move.l	d2,CFU_CardSig(a3)
	moveq.l	#-1,d0
	CALLSAME AllocSignal
	bset	d0,d2
	move.b	d0,CFU_TimePort+MP_SigBit(a3)
	move.l	a2,CFU_TimePort+MP_SigTask(a3)
	lea	CFU_TimePort+MP_MsgList(a3),a1
	INITLIST a1
	move.l	d2,CFU_Signals2(a3)
	moveq.l	#-1,d0
	CALLSAME AllocSignal
	bset	d0,d2
	move.b	d0,MP_SigBit(a3)
	move.l	a2,MP_SigTask(a3)
	lea	MP_MsgList(a3),a1
	INITLIST a1
	move.l	d2,CFU_Signals3(a3)

;- - timer.device - - - - - - - - - - - - - - - - - - - - -

	move.w	#TR_Sizeof,CFU_TimeReq+MN_Length(a3)
	lea	CFU_TimePort(a3),a1
	move.l	a1,CFU_TimeReq+MN_ReplyPort(a3)
	moveq.l	#UNIT_VBLANK,d0
	moveq.l	#0,d1
	lea	TimerName(pc),a0
	lea	CFU_TimeReq(a3),a1
	CALLSAME OpenDevice
	tst.b	d0
	bne.w	_t_freesignals

	move.b	#IOF_QUICK,CFU_TimeReq+IO_Flags(a3)

;- - prepare interface  - - - - - - - - - - - - - - - - - -

	CALLCARD CardInterface
	moveq.l	#CARD_INTERFACE_AMIGA_0,d1
	cmp.l	d0,d1
	bne.w	_t_freesignals		;unknown host adaptor

	CALLSAME GetCardMap
	move.l	d0,a0
	move.l	(a0)+,CFU_MemPtr(a3)
	move.l	(a0)+,CFU_AttrPtr(a3)
	move.l	(a0),CFU_IOPtr(a3)

	moveq.l	#20,d0			;normal or..
	btst	#0,CFU_OpenFlags+1(a3)
	beq.s	_t_1

	moveq.l	#119,d0			;..priority mode (PrepCard has 120)
_t_1:
	move.b	d0,CFU_CardHandle+LN_Pri(a3)
	lea	s_name(pc),a0
	move.l	a0,CFU_CardHandle+LN_Name(a3)
	lea	CFU_InsertInt(a3),a1
	move.l	a3,IS_Data(a1)
	lea	_InsertCode(pc),a0
	move.l	a0,IS_Code(a1)
	move.l	a1,CFU_CardHandle+CAH_CardInserted(a3)
	lea	CFU_RemoveInt(a3),a1
	move.l	a3,IS_Data(a1)
	lea	_RemoveCode(pc),a0
	move.l	a0,IS_Code(a1)
	move.l	a1,CFU_CardHandle+CAH_CardRemoved(a3)
	lea	CFU_StatusInt(a3),a1
	move.l	a3,IS_Data(a1)
	lea	_StatusCode(pc),a0
	move.l	a0,IS_Code(a1)
	move.l	a1,CFU_CardHandle+CAH_CardStatus(a3)
	clr.w	CFU_EventFlags(a3)	;with CFU_IOErr
	move.b	#CARDF_DELAYOWNERSHIP,CFU_CardHandle+CAH_CardFlags(a3)
	lea	CFU_CardHandle(a3),a1
	CALLSAME OwnCard

	bsr.w	_CfdFirst		;the HACK
	bsr.w	_SocketOn		;another HACK

	move.b	#NT_INTERRUPT,CFU_WatchInt+LN_Type(a3)
	move.w	#-1,CFU_WatchTimer(a3)
	lea	s_name(pc),a0
	move.l	a0,CFU_WatchInt+LN_Name(a3)
	lea	_WatchCode(pc),a0
	move.l	a0,CFU_WatchInt+IS_Code(a3)
	move.l	a3,CFU_WatchInt+IS_Data(a3)
	moveq.l	#5,d0			;display refresh interrupt (50/s)
	lea	CFU_WatchInt(a3),a1
	CALLEXEC AddIntServer

;- - report success - - - - - - - - - - - - - - - - - - - -

	move.l	CFU_KillSig(a3),d0
	move.l	CFU_KillTask(a3),a1
	CALLSAME Signal

;- - card already inserted? - - - - - - - - - - - - - - - -

	CALLCARD ReadCardStatus
	and.b	#CARD_STATUSF_CCDET,d0
	beq.w	_t_check		;no card, fine

	lea	CFU_TimeReq(a3),a1
	move.w	#TR_ADDREQUEST,IO_Command(a1)
	moveq.l	#1,d0
	move.l	d0,TR_Seconds(a1)
	clr.l	TR_Micros(a1)
	CALLEXEC SendIO			;be patient..
	move.l	CFU_Signals2(a3),d0
	CALLEXEC Wait			;..waiting for arbitration
	lea	CFU_TimeReq(a3),a1
	CALLSAME CheckIO
	tst.l	d0
	bne.s	_t_s1

	lea	CFU_TimeReq(a3),a1
	CALLEXEC _AbortIO
_t_s1:
	lea	CFU_TimeReq(a3),a1
	CALLEXEC WaitIO
	bclr	#1,CFU_EventFlags(a3)
	bne.w	_t_identify		;card inserted
	bra.s	_t_check

;- - control loop - - - - - - - - - - - - - - - - - - - - -

_t_wait:
	move.l	CFU_Signals3(a3),d0
	CALLEXEC Wait
_t_check:
	move.w	#1,CFU_CardReady(a3)
	bclr	#0,CFU_EventFlags(a3)
	bne.w	_t_disown		;card removed

	move.w	CFU_Flags(a3),d2
	lsr.w	#1,d2
	bcs.w	_t_flush		;reject pending requests

	lsr.w	#1,d2
	bcs.s	_t_wait			;we are suspended

	move.l	a3,a0
	CALLEXEC GetMsg
	move.l	d0,CFU_Request(a3)	;got request
	bne.s	_t_do

	bsr.w	ATAPIPoll		;check for removable media

	bclr	#1,CFU_EventFlags(a3)
	bne.s	_t_identify		;card inserted

	bclr	#2,CFU_EventFlags(a3)
	bne.w	_t_iswap		;media change
	bra.s	_t_wait
_t_do:
	move.l	d0,a2			;&IORequest
	clr.b	CFU_IOErr(a3)
	bsr.w	FunctionIndex
	lsl.l	#1,d0
	lea	bio_tab(pc),a6
	add.w	(a6,d0.l),a6
	jsr	(a6)			;handle and..
	move.b	d0,IO_Error(a2)
	move.l	a2,a1
	CALLEXEC ReplyMsg		;..reply request
	bra.s	_t_check

;- - examine and register new card  - - - - - - - - - - - -

_t_identify:	
	DBGMSG	dbg_card_insert
	clr.w	CFU_CardReady(a3)
	lea	CFU_CardHandle(a3),a2
	move.l	a2,a1
	CALLCARD ReadCardStatus
	and.b	#CARD_STATUSF_CCDET,d0
	beq.w	_t_ibreak		;false alert

	DBGMSG	dbg_identify
	clr.b	CFU_ActiveHacks(a3)
	clr.l	CFU_ReadErrors(a3)
	clr.l	CFU_WriteErrors(a3)
	clr.l	CFU_OKInts(a3)
	clr.l	CFU_FastInts(a3)
	clr.l	CFU_LostInts(a3)
	lea	CFU_TimeReq(a3),a1
	CALLEXEC WaitIO
	or.b	#$20,CFU_EventFlags(a3)	;Interrupt OFF
	bsr.w	Wait40			;wait 100ms for stable 5V
_t_ireset:
	btst	#2,CFU_OpenFlags+1(a3)
	bne.s	_t_ir1			;Kompatibility mode

	move.l	#$00da9000,a0
	move.b	#$ff,(a0)
	moveq.l	#10,d0
_t_ir0:
	tst.b	A_Pb
	subq.w	#1,d0
	bgt.s	_t_ir0

	move.b	#$fc,(a0)
	bra.s	_t_ir2
_t_ir1:
	move.l	a2,a1
	CALLCARD CardResetCard
_t_ir2:
	DBGMSG	dbg_reset
	moveq.l	#60,d2
_t_i1:
	subq.w	#1,d2
	bmi.s	_t_i2			;Timeout

	;bsr.w	LedOff	; debug led

	bsr.w	Wait40			;..or go on waiting
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.w	_t_ibreak

	move.l	a2,a1
	CALLCARD ReadCardStatus
	and.b	#CARD_STATUSF_BSY,d0
	bne.s	_t_i1			;card ready after resetting..
_t_i2:
	DBGMSG	dbg_config
	bsr.w	ConfigureHBA
	DBGMSG	dbg_done
	and.b	#$df,CFU_EventFlags(a3)	;Interrupt ON
	moveq.l	#600>>3,d1
	lsl.l	#3,d1
	move.l	d1,CFU_DTSpeed(a3)	;600ns = PIO 0
	lea	CFU_ConfigBlock(a3),a0	;&tuple buffer
	move.l	a2,a1
	moveq.l	#1,d1			;CISTPL_DEVICE
	moveq.l	#127,d0
	CALLCARD CopyTuple
	tst.w	d0
	beq.w	_t_iblind

	lea	CFU_ConfigBlock(a3),a0
	lea	CFU_DTSize(a3),a1
	CALLSAME DeviceTuple
	cmp.b	#$0d,CFU_DTType(a3)
	bne.w	_t_ibreak

	cmp.l	#$800,CFU_DTSize(a3)
	bcc.s	_t_ifuncid

	DBGMSG	dbg_tuple
	lea	CFU_ConfigBlock(a3),a0
	move.l	a2,a1
	moveq.l	#127,d0
	moveq.l	#$15,d1			;CISTPL_VERS_1
	CALLSAME CopyTuple
	tst.w	d0
	beq.w	_t_iblind

	lea	CFU_ConfigBlock(a3),a0
	addq.l	#1,a0
	moveq.l	#0,d0
	move.b	(a0)+,d0
	add.l	d0,a0
	move.b	#$ff,(a0)
	lea	_t_fcstr1(pc),a0
	bsr.w	CheckString
	tst.w	d0
	beq.w	_t_iblind

	lea	_t_fcstr2(pc),a0
	bsr.w	CheckString
	tst.w	d0
	beq.w	_t_iblind
	bra.s	_t_icfg
_t_ifuncid:
	lea	CFU_ConfigBlock(a3),a0
	move.l	a2,a1
	moveq.l	#$21,d1			;CISTPL_FUNCID
	moveq.l	#127,d0
	CALLCARD CopyTuple
	tst.w	d0
	beq.w	_t_iblind

	lea	CFU_ConfigBlock(a3),a0
	addq.l	#1,a0			;&TPL_Link
	cmp.b	#1,(a0)+
	bcs.w	_t_ibreak		;no tuple data

	cmp.b	#4,(a0)			;"fixed disk"
	bne.w	_t_ibreak

	lea	CFU_ConfigBlock(a3),a0
	move.l	a2,a1
	moveq.l	#$22,d1			;CISTPL_FUNCEXT
	moveq.l	#127,d0
	CALLSAME CopyTuple
	tst.w	d0
	beq.w	_t_ibreak

	lea	CFU_ConfigBlock(a3),a0
	addq.l	#1,a0
	cmp.b	#2,(a0)+
	bcs.w	_t_ibreak

	cmp.b	#1,(a0)+		;extension type 1
	bne.w	_t_ibreak

	cmp.b	#1,(a0)			;Interface = ATA
	bne.w	_t_ibreak

_t_icfg:
	DBGMSG	dbg_voltage
	moveq.l	#CARD_VOLTAGE_5V,d0
	move.l	a2,a1
	CALLCARD CardProgramVoltage
	DBGMSG	dbg_voltage5v

	DBGMSG	dbg_tuple
	lea	CFU_ConfigBlock(a3),a0
	move.l	a2,a1
	moveq.l	#$1a,d1			;CISTPL_CONFIG
	moveq.l	#127,d0
	CALLSAME CopyTuple
	tst.w	d0
	beq.s	_t_notuple
	DBGMSG	dbg_tupleconfig
	bra.s	_t_gottuple
_t_notuple:
	DBGMSG	dbg_tuplenone
	bra.w	_t_ibreak
_t_gottuple:
	lea	CFU_ConfigBlock(a3),a0
	addq.l	#1,a0
	cmp.b	#4,(a0)+
	bcs.w	_t_ibreak

	moveq.l	#3,d0
	and.b	(a0)+,d0		;address length
	addq.l	#1,a0
	move.l	d0,d1
	moveq.l	#0,d2
_t_raddr:
	move.b	(a0)+,d2		;read n bytes of address
	ror.l	#8,d2
	subq.w	#1,d0
	bpl.s	_t_raddr
_t_saddr:
	addq.w	#1,d1
	cmp.w	#4,d1
	bcc.s	_t_faddr

	lsr.l	#8,d2
	bra.s	_t_saddr
_t_iblind:
	btst	#1,CFU_OpenFlags+1(a3)
	beq.w	_t_ibreak		;Hack #2 deactivated..

	moveq.l	#$200>>3,d2		;..or try again without CIS
	lsl.l	#3,d2
	or.w	#1<<8,CFU_ActiveHacks(a3)
_t_faddr:
	cmp.l	#$00020000,d2
	bcc.w	_t_ibreak		;address out of range

	move.l	CFU_AttrPtr(a3),a2
	add.l	d2,a2
	move.l	a2,CFU_ConfigAddr(a3)
	btst	#2,CFU_OpenFlags+1(a3)
	beq.s	_t_i4

	move.b	#$80,(a2)		;soft reset ON..
	bsr.w	Wait40
	move.b	#0,(a2)			;..and OFF
	bsr.w	Wait40
_t_i4:
	move.b	#0,6(a2)		;Socket & Copy #0
	nop
	move.b	#$0f,4(a2)		;acknowledge status change
	nop
	move.b	#0,2(a2)		;turn on, 16bit, ...
	nop
	move.b	#$41,(a2)		;level mode IRQ and I/O mode 16 bytes
	bsr.w	Wait40			;wait for settle
	move.l	CFU_IOPtr(a3),CFU_IDEAddr(a3)
	lea	CFU_CardHandle(a3),a2
	move.l	CFU_DTSpeed(a3),d0
	move.l	a2,a1
	CALLCARD CardAccessSpeed
	bsr.w	ConfigureHBA
	and.b	#~4,CFU_EventFlags(a3)	;avoid double identify
_t_iswap:
	lea	CFU_CardHandle(a3),a2
	move.l	a2,a1
	CALLCARD ReadCardStatus
	and.b	#CARD_STATUSF_CCDET,d0
	beq.w	_t_ibreak

	bsr.w	BusyWait
	move.l	d0,d1			;save status
	and.b	#$a0,d0			;BSY, DWF
	beq.s	_t_itest

	ifd	DEBUG
	move.l	d1,d0
	bsr.w	_DebugIDEStatus		;show status when error
	endc
	btst	#0,CFU_ActiveHacks(a3)
	bne.w	_t_ibreak
	bra.w	_t_inodisk		;ATA removable media???
_t_itest:
	DBGMSG	dbg_rwtest
	bsr.w	RWTest			;find a working transfer mode
	DBGMSG	dbg_done
	ifd	DEBUG
	bsr.w	_DebugTransferMode	;show which transfer mode
	endc
	DBGMSG	dbg_getid
	bsr.w	_GetIDEID		;read ATA Konfiguration block
	DBGMSG	dbg_done
	move.l	d0,d2
	beq.s	_t_inodisk
	ifd	DEBUG
	bsr.w	_DebugCardInfo		;show card details
	bsr.w	_DebugIdentifyFields	;show labeled IDENTIFY fields
	bsr.w	_DebugHexDump		;dump full IDENTIFY structure
	endc
	
	btst	#6,CFU_ConfigBlock+167(a3)
	beq.s	_t_i6

	DBGMSG	dbg_spinup
	bsr.w	_SpinUp			;try waking up the drive..
	DBGMSG	dbg_done
	moveq.l	#0,d2
_t_i6:
	btst	#2,CFU_ConfigBlock+1(a3)
	beq.s	_t_i7

	moveq.l	#0,d0
	moveq.l	#1,d1
	lea	CFU_ConfigBlock(a3),a1
	bsr.w	_ReadBlocks		;..one way or the other..
	moveq.l	#0,d2
_t_i7:
	tst.l	d2
	bne.s	_t_i8

	bsr.w	_GetIDEID		;..then ask again
	move.l	d0,d2
	beq.s	_t_inodisk
_t_i8:
	subq.w	#1,d2
	bne.s	_t_iatapi

	DBGMSG	dbg_multimode
	bsr.w	_InitMultipleMode
	DBGMSG	dbg_done
	bsr.w	_OptimizePIOSpeed	;set faster PIO if flag set
	bra.s	_t_iok
_t_iatapi:
	bsr.w	ATAPIPoll		;start monitoring media removals
	bra.s	_t_iok
_t_inodisk:
	clr.l	CFU_DriveSize(a3)
_t_iok:
	DBGMSG	dbg_identify_ok
	DBGMSG	dbg_notify
	bsr.w	NotifyClients
	bra.w	_t_check

_t_ibreak:
	DBGMSG	dbg_identify_fail
	move.b	#IOF_QUICK,CFU_TimeReq+IO_Flags(a3)
	moveq.l	#0,d0
	move.l	a2,a1
	CALLCARD ReleaseCard
	bra.w	_t_check

;- - reje ct requests - - - - - - - - - - - - - - - - - - -

_t_flush:
	and.w	#~CFUF_FLUSH,CFU_Flags(a3)
	move.l	a3,a0
	CALLEXEC GetMsg
	tst.l	d0
	beq.s	_t_shutdown

	move.l	d0,a1			;&IORequest
	clr.l	IO_Actual(a1)
	move.b	#IOERR_ABORTED,IO_Error(a1)
	CALLSAME ReplyMsg
	bra.s	_t_flush

;- - unregister and free card - - - - - - - - - - - - - - -

_t_shutdown:
	btst	#2,CFU_Flags+1(a3)
	beq.w	_t_check

_t_disown:
	DBGMSG	dbg_card_remove
	clr.l	CFU_DriveSize(a3)
	clr.w	CFU_PLength(a3)
	clr.w	CFU_IDEStatus(a3)	;clear IDEStatus and IDEError
	clr.l	CFU_IDEAddr(a3)		;clear IDE address pointer
	clr.l	CFU_ConfigAddr(a3)	;clear config address
	clr.w	CFU_MultiSize(a3)	;clear multi-sector size
	clr.w	CFU_MultiSizeRW(a3)	;clear multi-sector RW size
	;Clear 512-byte IDENTIFY buffer (CFU_ConfigBlock)
	lea	CFU_ConfigBlock(a3),a0
	moveq.l	#512/4-1,d0		;128 longwords - 1
.clr_loop:
	clr.l	(a0)+
	dbf	d0,.clr_loop
	bsr.w	NotifyClients
	moveq.l	#0,d0
	lea	CFU_CardHandle(a3),a1
	CALLCARD ReleaseCard
	btst	#2,CFU_Flags+1(a3)
	beq.w	_t_check

	moveq.l	#5,d0
	lea	CFU_WatchInt(a3),a1
	CALLEXEC RemIntServer
	moveq.l	#CARDF_REMOVEHANDLE,d0
	lea	CFU_CardHandle(a3),a1
	CALLCARD ReleaseCard
	lea	CFU_TimeReq(a3),a1
	CALLEXEC WaitIO
	lea	CFU_TimeReq(a3),a1
	CALLEXEC CloseDevice
_t_freesignals:
	move.l	CFU_Signals3(a3),d2
_t_fs1:
	move.l	d2,d0
	beq.s	_t_fs2

	bsr.w	Log2
	bclr	d0,d2
	CALLEXEC FreeSignal
	bra.s	_t_fs1
_t_fs2:
	clr.l	CFU_Process(a3)		;report done
	move.l	CFU_KillSig(a3),d0
	beq.s	_t_end

	move.l	CFU_KillTask(a3),d1
	beq.s	_t_end

	move.l	d1,a1
	CALLSAME Signal
_t_end:
	sub.l	a1,a1
	JMPEXEC RemTask

_t_fcstr1:
	dc.b	"FREECOM",0
_t_fcstr2:
	dc.b	"PCCARD-IDE",0
	even

;--- check for text patterns inside tuples -----------------
; a0 <- &pattern
; d0 -> 1 (found), 0 (not)

CheckString:
	movem.l	d2-d3,-(sp)
	move.l	a0,d3			;&pattern
	lea	CFU_ConfigBlock+4(a3),a1
	cmp.b	#2,-3(a1)
	bcs.s	cst_no			;no text
cst_rescan:
	move.l	d3,a0
cst_scan:
	move.b	(a0)+,d0
	beq.s	cst_yes			;end of pattern --> Text found

	move.b	(a1)+,d1
	beq.s	cst_rescan		;end of Text

	cmp.b	#$ff,d1
	beq.s	cst_no			;end of tuple

	eor.b	d0,d1
	and.b	#$df,d1
	beq.s	cst_scan		;on mismatch..
cst_skip:
	move.b	(a1)+,d1
	beq.s	cst_rescan		;..skip remaining Text

	addq.b	#1,d1
	bne.s	cst_skip
cst_no:
	moveq.l	#0,d0
cst_end:
	movem.l	(sp)+,d2-d3
	rts

cst_yes:
	moveq.l	#1,d0
	bra.s	cst_end

;--- a Hack: cfd first -------------------------------------

_CfdFirst:
	movem.l	d2/a2,-(sp)
	btst	#0,CFU_OpenFlags+1(a3)
	beq.s	_cfdf_end		;deactivated

	moveq.l	#CFU_CardHandle,d2
	add.l	a3,d2			;&CardHandle
	CALLEXEC Disable
	move.l	d2,d1
_cfdf_scan:
	move.l	d1,a1			;look for card.resource list head
	move.l	LN_Pred(a1),d1
	bne.s	_cfdf_scan

	move.l	a1,a2			;&List
	cmp.l	(a2),d2
	beq.s	_cfdf_ok		;we are first already

	or.w	#1,CFU_ActiveHacks(a3)
	move.l	d2,a1
	CALLSAME Remove
	move.l	a2,a0
	move.l	d2,a1
	CALLSAME AddHead		;move to head
_cfdf_ok:
	CALLSAME Enable
_cfdf_end:
	movem.l	(sp)+,d2/a2
	rts

;--- another Hack: turn on socket --------------------------

_SocketOn:
	move.l	d2,-(sp)
	btst	#0,CFU_OpenFlags+1(a3)
	beq.s	_so_end

	move.b	$00da8000,d0
	btst	#0,d0
	beq.s	_so_end			;active already

	moveq.l	#0,d2
	CALLEXEC Disable
	move.l	CFD_ExecBase(a4),a1
	move.l	EXB_MemList(a1),d1
_so_entry:
	move.l	d1,a1
	move.l	(a1),d1
	beq.s	_so_stop

	move.l	MH_Lower(a1),d0
	cmp.l	#$00a60000,d0
	bcc.s	_so_entry

	move.l	MH_Upper(a1),d0
	cmp.l	#$00600001,d0
	bcs.s	_so_entry

	moveq.l	#1,d2			;shadowed by present RAM
_so_stop:
	CALLSAME Enable
	tst.l	d2
	bne.s	_so_end

	or.w	#2,CFU_ActiveHacks(a3)
	move.b	#0,$00da8000
_so_end:
	move.l	(sp)+,d2
	rts

;--- setup adaptor -----------------------------------------

ConfigureHBA:
	btst	#2,CFU_OpenFlags+1(a3)
	bne.s	ch_compatibility

	move.l	#$00da8000,a1
	btst	#0,(a1)
	bne.s	ch_end			;is turned off

	move.b	#CARD_ENABLEF_DIGAUDIO+CARD_DISABLEF_WP,(a1)
	or.b	#CARD_INTF_IRQ,$2000(a1)
	bra.s	ch_end
ch_compatibility:
	move.l	CFD_CardBase(a4),a6
	moveq.l	#CARD_DISABLEF_WP+CARD_ENABLEF_DIGAUDIO,d1
	cmp.w	#39,LIB_Version(a6)
	bcs.s	ch_1

	or.b	#CARD_INTF_SETCLR+CARD_INTF_IRQ,d1
ch_1:
	move.l	a2,a1
	CALLSAME CardMiscControl
ch_end:
	rts

;--- the Interrupt Servers ---------------------------------
; a1 <- &IS_Data = &CompactFlashUnit
; a5 <- &IS_Code

_InsertCode:
	movem.l	d0/d2/a3/a6,-(sp)
	move.l	a1,a3
	moveq.l	#2,d1
	bra.s	_ISSignal

_RemoveCode:
	movem.l	d0/d2/a3/a6,-(sp)
	move.l	a1,a3
	moveq.l	#1,d1
	bra.s	_ISSignal

_StatusCode:
	btst	#CARD_STATUSB_IRQ,d0
	beq.s	_ISEnd

	btst	#5,CFU_EventFlags(a1)
	bne.s	_ISEnd

	move.w	#CFU_OKInts,d1
_IS1:
	movem.l	d0/d2/a3/a6,-(sp)
	move.l	d1,d2
	move.l	a1,a3
	move.l	CFU_Device(a3),a6
	move.l	CFD_CardBase(a6),a6
	lea	CFU_CardHandle(a3),a1
	jsr	ReadCardStatus(a6)
	cmp.b	#4,CFU_ReceiveMode(a3)
	seq.b	d1
	eor.b	d1,d0
	and.b	#CARD_STATUSF_IRQ,d0
	beq.s	_IS2

	move.l	CFU_IDEAddr(a3),a0
	move.b	7(a0),CFU_IDEStatus(a3)	;reset Interrupt
	addq.l	#1,(a3,d2.w)
	moveq.l	#4,d1
_ISSignal:
	or.b	d1,CFU_EventFlags(a3)
	move.l	CFU_CardSig(a3),d0
	move.l	CFU_Process(a3),a1
	move.l	CFU_Device(a3),a6
	move.l	CFD_ExecBase(a6),a6
	jsr	Signal(a6)
	move.w	#-1,CFU_WatchTimer(a3)
_IS2:
	movem.l	(sp)+,d0/d2/a3/a6
_ISEnd:
	rts

_WatchCode:
	move.w	CFU_WatchTimer(a1),d0
	bmi.s	_wc_end
	bne.s	_wc_next

	move.w	#4,CFU_WatchTimer(a1)
	move.w	#CFU_LostInts,d1
	bsr.s	_IS1
	bra.s	_wc_end
_wc_next:
	subq.w	#1,d0
	move.w	d0,CFU_WatchTimer(a1)
_wc_end:
	moveq.l	#0,d0
	rts

;--- notify user -------------------------------------------

NotifyClients:
	movem.l	d2/a5,-(sp)
	CALLEXEC Forbid
	move.l	CFU_Clients(a3),d2
ncl_loop:
	move.l	d2,a5			;&IORequest
	move.l	(a5),d2
	beq.s	ncl_end			;end of List

	move.l	IO_Data(a5),a5		;&InterruptServer
	move.l	IS_Data(a5),a1
	move.l	IS_Code(a5),a5
	move.l	CFD_ExecBase(a4),a6
	jsr	(a5)
	bra.s	ncl_loop
ncl_end:
	CALLEXEC Permit
	movem.l	(sp)+,d2/a5
	rts

;--- test PCMCIA Kommunikation -----------------------------
; d0 -> bitfield telling the working modes

RWTest:
	movem.l	d2-d3,-(sp)
	move.l	CFU_IDEAddr(a3),a0
	addq.l	#4,a0
	move.l	a0,a1
	add.l	#$10000,a1
	move.w	#$1234,d2		;the bit pattern used for testing
	bsr.s	TestRun
	move.w	d0,d3
	bsr.s	TestRun
	and.w	d0,d3
	move.w	d3,CFU_RWFlags(a3)
	clr.b	CFU_ReadMode(a3)
	moveq.l	#0,d2
	moveq.l	#$000f,d0
	and.w	d3,d0
	bne.s	rwt_1

	moveq.l	#1,d2
rwt_1:
	move.b	d2,CFU_WriteMode(a3)
	move.l	d3,d0
	movem.l	(sp)+,d2-d3
	rts

TestRun:
	movem.l	d3-d5,-(sp)
	moveq.l	#0,d4
	moveq.l	#0,d5
tr_go:
	moveq.l	#$c,d0
	and.w	d4,d0
	lsr.w	#1,d0
	lea	tr_tab(pc),a6
	add.w	(a6,d0.w),a6
	jsr	(a6)			;write
	moveq.l	#3,d0
	and.w	d4,d0
	lsl.w	#1,d0
	addq.w	#8,d0
	lea	tr_tab(pc),a6
	add.w	(a6,d0.w),a6
	jsr	(a6)			;read
	cmp.w	d2,d3
	bne.s	tr_next			;inkonsistent..

	bset	d4,d5			;..or OK
tr_next:
	add.w	#$0202,d2		;new pattern
	addq.w	#1,d4
	cmp.w	#16,d4
	bcs.s	tr_go

	move.l	d5,d0
	movem.l	(sp)+,d3-d5
	rts

tr_tab:
	dc.w	_w0-tr_tab
	dc.w	_w1-tr_tab
	dc.w	_w2-tr_tab
	dc.w	_w3-tr_tab
	dc.w	_r0-tr_tab
	dc.w	_r1-tr_tab
	dc.w	_r2-tr_tab
	dc.w	_r3-tr_tab

_w0:
	move.w	d2,(a0)
	rts

_w1:
	rol.w	#8,d2
	move.b	d2,(a0)
	rol.w	#8,d2
	move.b	d2,1(a0)
	rts

_w2:
	rol.w	#8,d2
	move.b	d2,(a0)
	rol.w	#8,d2
	move.b	d2,(a1)
	rts

_w3:
	rol.w	#8,d2
	move.b	d2,(a0)
	rol.w	#8,d2
	move.b	d2,1(a1)
	rts

_r0:
	move.w	(a0),d3
	rts

_r1:
	move.b	(a0),d3
	lsl.w	#8,d3
	move.b	1(a0),d3
	rts

_r2:
	move.b	(a0),d3
	lsl.w	#8,d3
	move.b	(a1),d3
	rts

_r3:
	move.b	(a0),d3
	lsl.w	#8,d3
	move.b	1(a1),d3
	rts

;*** IDE Protokoll *****************************************
;--- wait by polling ---------------------------------------
; d0 -> IDE Status or -1

BusyWait:
	move.l	d2,-(sp)
	bsr.w	_IDEStart
	move.l	CFU_IDEAddr(a3),a0	;ignore possibly ..
	move.b	14(a0),d0		;..invalid status
	move.b	#$e0,6(a0)		;select Master
	move.b	14(a0),d0
	moveq.l	#100,d2			;30s
bw_loop:
	moveq.l	#-1,d0
	moveq.l	#3,d1
	and.b	CFU_EventFlags(a3),d1
	bne.s	bw_end			;Disk removed

	subq.w	#1,d2
	ble.s	bw_end			;time expired

	move.l	CFU_ConfigAddr(a3),a0
	move.b	#$0f,4(a0)		;acknowledge new Status
	moveq.l	#0,d0
	move.l	CFU_IDEAddr(a3),a0
	move.b	7(a0),d0
	bpl.s	bw_ok			;OK

	lea	CFU_TimeReq(a3),a1
	move.w	#TR_ADDREQUEST,IO_Command(a1)
	clr.l	TR_Seconds(a1)
	move.l	#300000,TR_Micros(a1)
	CALLEXEC DoIO
	bra.s	bw_loop
bw_ok:
	move.b	#8,14(a0)		;bit 1: free Interrupts
bw_end:
	move.l	d0,d2
	bsr.w	_IDEStop
	move.l	d2,d0
	move.l	(sp)+,d2
	rts

;--- wait for drive ----------------------------------------
; Wait for drive to become ready (BSY clear)
;
; Input:
;   a3 = CFU pointer
;
; Output:
;   CFU_IDEStatus updated with current status
;
; Notes:
;   - Polls INTRQ/READY or waits for interrupt
;   - Handles both fast (polling) and slow (wait) paths
;   - Some cards (e.g. Kingston) use READY instead of INTRQ
;
WaitReady:
	moveq.l	#7,d0
	and.b	CFU_EventFlags(a3),d0
	bne.s	ClearWaitSignal

	lea	CFU_CardHandle(a3),a1	;some cards (eg KINGSTON) use READY..
	CALLCARD ReadCardStatus		;..instead of INTRQ
	cmp.b	#4,CFU_ReceiveMode(a3)
	seq.b	d1
	eor.b	d1,d0
	and.b	#CARD_STATUSF_IRQ,d0
	beq.s	wr_2

	move.l	CFU_IDEAddr(a3),a0
	move.b	7(a0),d0
	bpl.s	wr_1			;BSY

	tst.b	A_Pb
	nop
	bra.s	WaitReady
wr_1:	
	move.b	d0,CFU_IDEStatus(a3)	;reset Interrupt
	addq.l	#1,CFU_FastInts(a3)
	bra.s	ClearWaitSignal
wr_2:
	move.w	#4,CFU_WatchTimer(a3)
	move.l	CFU_Signals2(a3),d0
	CALLEXEC Wait
	bra.s	cws_end

;--- reset wait signal -------------------------------------

ClearWaitSignal:
	move.l	CFU_Signals2(a3),d1
	moveq.l	#0,d0
	CALLEXEC SetSignal
cws_end:
	move.w	#-1,CFU_WatchTimer(a3)
	move.l	CFU_ConfigAddr(a3),a0
	move.b	#$0f,4(a0)		;a cknowledge new Status
	and.b	#~4,CFU_EventFlags(a3)
	rts

;--- start IDE ---------------------------------------------
; Begin IDE/PCMCIA access session
;
; Input:
;   a3 = CFU pointer
;
; Side effects:
;   - Calls BeginCardAccess on card.resource
;   - Disables data cache if using memory-mapped mode
;
; Notes:
;   Must be paired with _IDEStop after transfer completes
;
_IDEStart:
	cmp.b	#4,CFU_ReceiveMode(a3)
	bne.s	_ia_1

	moveq.l	#0,d0
	move.l	#CACRF_EnableD,d1
	CALLEXEC CacheControl
	move.l	d0,CFU_CacheFlags(a3)
_ia_1:
	lea	CFU_CardHandle(a3),a1
	JMPCARD BeginCardAccess

;--- stop IDE ----------------------------------------------
; End IDE/PCMCIA access session
;
; Input:
;   a3 = CFU pointer
;
; Side effects:
;   - Calls EndCardAccess on card.resource
;   - Restores data cache state if using memory-mapped mode
;
_IDEStop:
	lea	CFU_CardHandle(a3),a1
	CALLCARD EndCardAccess
	cmp.b	#4,CFU_ReceiveMode(a3)
	bne.s	_io_1

	move.l	CFU_CacheFlags(a3),d0
	move.l	#CACRF_EnableD,d1
	CALLEXEC CacheControl
_io_1:
	rts

;--- get IDE error -----------------------------------------

_IDEError:
	movem.l	d2/a2,-(sp)
	move.l	CFU_IDEAddr(a3),a0
	move.b	13(a0),CFU_IDEError(a3)
	addq.l	#2,a0
	lea	CFU_IDESet+2(a3),a2
	tst.b	CFU_WriteMode(a3)
	bne.s	_idee_1

	move.w	(a0)+,(a2)+
	move.w	(a0)+,(a2)+
	move.w	(a0),(a2)
	bra.s	_idee_2
_idee_1:
	move.l	a0,a1
	add.l	#$10001,a1
	move.b	(a0),(a2)+
	move.b	(a1),(a2)+
	move.b	2(a0),(a2)+
	move.b	2(a1),(a2)+
	move.b	4(a0),(a2)
	move.b	4(a1),1(a2)
_idee_2:
	move.w	(a2),d2
	move.w	#$e003,(a2)		;LW0, REQUEST SENSE
	bsr.s	_IDECmd
	bsr.w	WaitReady
	move.w	d2,(a2)
	moveq.l	#-1,d2
	moveq.l	#$ffffff81,d0		;BSY, ERR
	and.b	CFU_IDEStatus(a3),d0
	bne.s	_idee_done

	move.l	CFU_IDEAddr(a3),a0
	moveq.l	#0,d2
	move.b	13(a0),d2
	move.b	d2,CFU_IDESense(a3)
	moveq.l	#$7f,d0
	and.b	d2,d0
	or.b	#$40,d0
	move.b	d0,CFU_IOErr(a3)
_idee_done:
	move.l	d2,d0
	movem.l	(sp)+,d2/a2
	rts

;--- send Kommand ------------------------------------------
; Send IDE command to the drive
;
; Input:
;   a3 = CFU pointer
;   CFU_IDESet = command block (Features, SectorCount, LBA, Command)
;
; Output:
;   d0 = 1 if command sent OK, 0 if card removed/error
;   CFU_IDEStatus updated
;
; Notes:
;   - Waits for BSY clear before sending
;   - Writes command block to IDE registers
;   - Command is in CFU_IDESet+6 (byte 7 of task file)
;
_IDECmd:
	move.l	a2,-(sp)
	moveq.l	#0,d0
	move.l	CFU_IDEAddr(a3),a0
	addq.l	#7,a0
	move.l	#A_Pb,a1
	tst.b	(a1)
	nop
_idec_w1:
	tst.b	(a1)
	nop				;wait 2..5 us
	moveq.l	#3,d1
	and.b	CFU_EventFlags(a3),d1
	bne.s	_idec_end		;card removed

	move.b	(a0),d1
	bmi.s	_idec_w1		;BSY

	and.b	#$40,d1			;DRDY
	beq.s	_idec_end		;not ready

	bsr.w	ClearWaitSignal
	move.l	CFU_IDEAddr(a3),a0
	addq.l	#2,a0
	lea	CFU_IDESet+2(a3),a2
	tst.b	CFU_WriteMode(a3)
	bne.s	_idec_cmd1
;_idec_cmd0:
	move.w	(a2)+,(a0)+
	move.w	(a2)+,(a0)+
	nop				;write command register last
	move.w	(a2),(a0)
	bra.s	_idec_ok
_idec_cmd1:
	move.l	a0,a1
	add.l	#$10001,a1
	move.b	(a2)+,(a0)
	move.b	(a2)+,(a1)
	move.b	(a2)+,2(a0)
	move.b	(a2)+,2(a1)
	move.b	(a2)+,4(a0)
	nop
	move.b	(a2),4(a1)
_idec_ok:
	moveq.l	#1,d0
_idec_end:
	move.l	(sp)+,a2
	rts

;--- read drive Konfiguration ------------------------------
; Identify the connected CF/ATA/ATAPI device
;
; Input:
;   a3 = CFU pointer
;
; Output:
;   d0 = device type:
;        0 = no device / error
;        1 = ATA device (CompactFlash)
;        2 = ATAPI device (CD-ROM, etc.)
;
; Side effects:
;   - Fills CFU_ConfigBlock with 512-byte IDENTIFY data
;   - Sets CFU_DriveSize (total sectors)
;   - Sets CFU_MultiSize (sectors per interrupt)
;   - Sets CFU_PLength (0=ATA, 12/16=ATAPI packet length)
;
; Register usage:
;   d2 = return value (device type)
;   d3 = read mode counter (tries different PIO modes)
;   d4 = (scratch)
;   d5 = command word ($e0ec=IDENTIFY, $a0a1=IDENTIFY PACKET)
;   d6 = retry counter for slow SD-to-CF adapters
;   a2 = buffer pointer
;
; Flow:
;   1. Send IDENTIFY DEVICE command ($EC)
;   2. Wait for DRQ, retry up to 32 times for slow adapters
;   3. If DRQ not set after retries, try IDENTIFY PACKET DEVICE ($A1)
;   4. Read 512-byte identify data
;   5. Parse device type and set unit parameters
;
_GetIDEID:
	movem.l	d2-d6/a2,-(sp)

	;--- SD-to-CF adapter retry logic ---
	; Some SD-to-CF adapters are slow to respond to IDENTIFY command.
	; If DRQ is not set after _IDECmd, retry up to 32 times with delay.
	; See _gid_check_retry for the retry branch.
	moveq.l	#32,d6			;retry count for slow adapters

	moveq.l	#1,d0
	move.w	d0,CFU_MultiSize(a3)
	moveq.l	#512>>4,d0
	lsl.l	#4,d0
	move.l	d0,CFU_BlockSize(a3)
	move.w	#9,CFU_BlockShift(a3)
	lea	CFU_TimeReq(a3),a1
	move.w	#TR_ADDREQUEST,IO_Command(a1)
	clr.l	TR_Seconds(a1)
	move.l	#500000,TR_Micros(a1)
	CALLEXEC SendIO			; prepare Timeout
_gid_retry:
	bsr.w	_IDEStart
	move.w	#$e0ec,d5		;LBA, drive #0, IDENTIFY DEVICE
	moveq.l	#0,d3			;the read mode
_gid_command:
	move.w	d3,CFU_ReceiveMode(a3)
	clr.l	CFU_IDESet+2(a3)
	move.w	d5,CFU_IDESet+6(a3)
	bsr.w	_IDECmd
	tst.w	d0
	beq.w	_gid_error
	
	bsr.w	WaitReady
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.w	_gid_error		;card removed

	moveq.l	#$29,d0			;DF, DRQ, ERR
	and.b	CFU_IDEStatus(a3),d0
	subq.b	#8,d0			;DRQ
	beq.s	.drq_ok
	moveq.l	#0,d2			;mark: ATA not yet identified
	bra.w	_gid_check_retry	;retry for slow adapters
.drq_ok:

	lea	CFU_ConfigBlock(a3),a2
	moveq.l	#512>>8,d0
	lsl.l	#8,d0
	bsr.w	_pio_in			;read data
	move.l	CFU_IDEAddr(a3),a0
	move.l	#A_Pb,a1
	moveq.l	#120,d1
_gid_wait:
	bsr.w	Wait1
	move.b	14(a0),d0
	bpl.s	_gid_done

	subq.w	#1,d1
	bgt.s	_gid_wait
_gid_done:
	btst	#3,d0
	beq.s	_gid_found		;that is all, OK

	move.w	#$e000,CFU_IDESet+6(a3)	;NOP
	bsr.w	_IDECmd			;abort
	bsr.w	WaitReady
	cmp.b	#3,d3
	bgt.s	_gid_break
	beq.s	_gid_switch

	add.w	#$0101,d3		;try different read mode
	bra.w	_gid_command
_gid_switch:
	bsr.w	_IDEStop
	move.w	#$0404,d3
	move.w	d3,CFU_ReceiveMode(a3)
	move.l	CFU_ConfigAddr(a3),a0
	move.b	#$40,(a0)
	bsr.w	Wait40
	move.l	CFU_MemPtr(a3),CFU_IDEAddr(a3)
	bsr.w	_IDEStart
	bra.w	_gid_command
_gid_break:
	move.w	#$a0a1,d1		;drive #0, IDENTIFY PACKET DEVICE
	cmp.w	d1,d5
	beq.s	_gid_error

	move.w	d1,d5
	bra.w	_gid_command
_gid_error:
	moveq.l	#0,d5
	addq.l	#1,CFU_ReadErrors(a3)
_gid_found:
	lea	CFU_TimeReq(a3),a1
	CALLEXEC _AbortIO
	lea	CFU_TimeReq(a3),a1
	CALLEXEC WaitIO
	move.b	#IOF_QUICK,CFU_TimeReq+IO_Flags(a3)
	move.l	d5,d2
	beq.s	_gid_end

	lea	CFU_ConfigBlock(a3),a0	;fix..
	move.w	#512/2,d2
_gid_swap:
	move.w	(a0),d0
	rol.w	#8,d0
	move.w	d0,(a0)+		;..byte order
	subq.w	#1,d2
	bgt.s	_gid_swap

	cmp.w	#$a0a1,d5
	beq.s	_gid_atapi

	move.l	CFU_ConfigBlock+120(a3),d0
	swap	d0
	move.l	d0,CFU_DriveSize(a3)
	moveq.l	#1,d2			;ATA OK
	bra.s	_gid_end
_gid_atapi:
	moveq.l	#12,d1
	moveq.l	#3,d0
	and.w	CFU_ConfigBlock(a3),d0
	beq.s	_gid_a1

	moveq.l	#16,d1
_gid_a1:
	move.w	d1,CFU_PLength(a3)	;set ATAPI command length
	moveq.l	#2,d2			;ATAPI OK
	bra.s	_gid_end

;--- Retry for slow SD-to-CF adapters ---
; When DRQ not set after IDENTIFY DEVICE, retry with delay.
; If retries exhausted, try ATAPI IDENTIFY PACKET DEVICE.
_gid_check_retry:
	subq.l	#1,d6
	beq.s	_gid_break		;ATA exhausted, try ATAPI
	bsr.w	Wait40			;delay before retry
	bra.w	_gid_retry

_gid_end:
	bsr.w	_IDEStop
	move.l	d2,d0
	movem.l	(sp)+,d2-d6/a2
	rts

;--- read Blocks -------------------------------------------
; Read sectors from CF card using PIO
;
; Input:
;   d0 = starting block number (LBA)
;   d1 = byte count to read
;   a1 = destination buffer pointer
;   a3 = CFU pointer
;
; Output:
;   d0 = bytes actually read (0 on error)
;
; Register usage:
;   d2 = current block number
;   d3 = bytes remaining
;   d4 = bytes per transfer chunk
;   d5 = total bytes (for return value)
;   d6 = sectors per interrupt
;   a2 = buffer pointer
;
; Notes:
;   - Uses READ SECTORS ($21) for single-sector transfers
;   - Uses READ MULTIPLE ($C4) for multi-sector transfers
;   - Handles ATAPI via SCSI path (_rb_scsi)
;   - Retries up to 5 times on error
;
_ReadBlocks:
	movem.l	d2-d6/a2,-(sp)
	move.l	a1,a2			;&buffer
	move.l	d0,d2			;Block #
	move.l	d1,d3			;total bytes
	move.l	d1,d5
	beq.w	_rb_ready		;nothing to do

	tst.w	CFU_PLength(a3)
	bgt.w	_rb_scsi

	bsr.w	_IDEStart
_rb_swath:
	move.w	#5,CFU_Try(a3)
	move.l	d2,CFU_Block(a3)
	move.l	d3,CFU_Count(a3)
	move.l	a2,CFU_Buffer(a3)
_rb_try:
	btst	#6,CFU_EventFlags(a3)
	bne.w	_rb_starttimer
_rb_0:
	tst.l	CFU_DriveSize(a3)
	beq.w	_rb_nodisk

	moveq.l	#0,d4
	move.w	CFU_MultiSizeRW(a3),d4
	cmp.l	d4,d3
	bcc.s	_rb_1

	move.l	d3,d4			;bytes/part
_rb_1:
	lea	CFU_IDESet+2(a3),a0
	moveq.l	#0,d1
	move.w	CFU_MultiSize(a3),d1
	move.l	d1,d6			;Blocks/Interrupt
	move.b	d4,(a0)+		;Sektors
	move.b	d2,(a0)+		;LBA 7-0
	move.l	d2,d0
	lsr.l	#8,d0
	rol.w	#8,d0
	move.w	d0,(a0)+		;LBA 23-8
	lsr.l	#8,d0
	and.w	#$0f00,d0		;LBA 27-24
	subq.w	#1,d1
	beq.s	_rb_c01

	or.w	#$e0c4,d0		;"READ MULTIPLE"
	bra.s	_rb_c02
_rb_c01:
	or.w	#$e021,d0		;"READ SECTORS"
_rb_c02:
	move.w	d0,(a0)			;start!
	bsr.w	_IDECmd
	tst.w	d0
	beq.w	_rb_nodisk
_rb_block:
	cmp.l	d6,d4
	bcc.s	_rb_2

	move.l	d4,d6
_rb_2:
	bsr.w	WaitReady
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.w	_rb_nodisk		;card removed

	moveq.l	#$ffffffa9,d0		;BSY, DWF, DRQ, ERR
	and.b	CFU_IDEStatus(a3),d0
	subq.b	#8,d0			;DRQ
	bne.w	_rb_break

	move.l	CFU_IOPtr(a3),a0
	addq.l	#8,a0
	move.l	d6,d0
	move.b	CFU_ReceiveMode(a3),d1
	bne.s	_rb_lcheck

	lsl.l	#5,d0
	subq.l	#1,d0
_rb_loop0:
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	dbf	d0,_rb_loop0
_rb_lnext:
	add.l	d6,d2
	sub.l	d6,d3
	sub.l	d6,d4
	bgt.s	_rb_block

	tst.l	d3
	bgt.w	_rb_swath
_rb_stop:
	move.l	CFU_IDEAddr(a3),a0
	move.l	a0,d0
	beq.s	_rb_skip_status		;skip if IDEAddr is NULL
	move.b	14(a0),CFU_IDEStatus(a3)
_rb_skip_status:
	bsr.w	_IDEStop
	tst.b	CFU_EventFlags(a3)
	bpl.s	_rb_ready

	lea	CFU_TimeReq(a3),a1
	CALLEXEC _AbortIO		;reset Timeout
	lea	CFU_TimeReq(a3),a1
	CALLEXEC WaitIO
	and.b	#$7f,CFU_EventFlags(a3)
_rb_ready:
	move.l	a2,a1
	move.l	d5,d0
	sub.l	d3,d0
_rb_end:
	movem.l	(sp)+,d2-d6/a2
	rts

_rb_lcheck:
	lsl.l	#8,d0
	lsl.l	#1,d0
	bsr.w	_pio_in
	bra.s	_rb_lnext

_rb_break:
	move.b	#TDERR_NOSECHDR,CFU_IOErr(a3)
	bsr.w	_IDEError
	addq.l	#1,CFU_ReadErrors(a3)
	subq.w	#1,CFU_Try(a3)
	beq.s	_rb_stop

	clr.b	CFU_IOErr(a3)
	move.l	CFU_Block(a3),d2
	move.l	CFU_Count(a3),d3
	move.l	CFU_Buffer(a3),a2
	bra.w	_rb_try

_rb_nodisk:
	move.b	#TDERR_DISKCHANGED,CFU_IOErr(a3)
	bra.s	_rb_stop

_rb_starttimer:
	tst.b	CFU_EventFlags(a3)
	bpl.s	_rb_c1

	lea	CFU_TimeReq(a3),a1
	CALLEXEC WaitIO
_rb_c1:
	lea	CFU_TimeReq(a3),a1
	move.w	#TR_ADDREQUEST,IO_Command(a1)
	moveq.l	#1,d0
	clr.l	TR_Seconds(a1)
	move.l	#500000,TR_Micros(a1)
	CALLEXEC SendIO			;prepare Timeout
	or.b	#$80,CFU_EventFlags(a3)
	bra.w	_rb_0

_rb_scsi:
	moveq.l	#0,d4
	not.w	d4
	cmp.l	d4,d3
	bcc.s	_rb_s1

	move.l	d3,d4
_rb_s1:
	lea	CFU_SCSIStruct(a3),a0
	move.l	a2,(a0)+		;SCSI_Data
	move.l	d4,d0
	lsl.l	#8,d0
	lsl.l	#1,d0
	move.l	d0,(a0)+		;SCSI_Length
	clr.l	(a0)+			;SCSI_Actual
	lea	CFU_Packet(a3),a1
	move.l	a1,(a0)+		;SCSI_Command
	moveq.l	#10,d0
	swap	d0
	move.l	d0,(a0)+		;SCSI_CmdLength, _CmdActual
	move.w	#SCSIF_READ<<8,(a0)	;SCSI_Flags, _Status
	move.w	#READ10<<8,(a1)+
	move.l	d2,(a1)+
	move.l	d4,d0
	lsl.l	#8,d0
	move.l	d0,(a1)
	lea	CFU_SCSIStruct(a3),a0
	bsr.w	_Packet
	tst.b	d0
	bne.s	_rb_serror

	move.l	CFU_SCSIStruct+SCSI_Actual(a3),d0
	add.l	d0,a2
	lsr.l	#8,d0
	lsr.l	#1,d0
	sub.l	d0,d3
	bgt.s	_rb_scsi
	bra.w	_rb_ready

_rb_serror:
	move.b	#TDERR_NOTSPECIFIED,CFU_IOErr(a3)
	bra.w	_rb_ready

;--- PIO IN Transfer ---------------------------------------
; Read data from CF card using Programmed I/O
;
; Input:
;   d0 = byte count to read
;   a2 = destination buffer pointer
;   a3 = CFU pointer
;   CFU_ReceiveMode = transfer mode (0-4)
;
; Output:
;   a2 = updated buffer pointer (past data read)
;
; Transfer Modes (CFU_ReceiveMode):
;   0 = I/O Register 8, word-wise
;       Simple word reads from single PCMCIA I/O register
;   1 = I/O Register 8 + duplicates, word-wise
;       Reads from register with address increment (8KB window)
;       For cards that mirror data across address range
;   2 = I/O Registers 8 and 9, byte-wise
;       Alternating byte reads from two registers (low/high)
;       For byte-only PCMCIA implementations
;   3 = I/O Register 8, word-wise, drop every other word
;       Reads word, discards next word (for specific adapters)
;   4 = Memory mapped, word-wise
;       Direct memory access (fastest, 1KB window)
;       Requires memory-mapped PCMCIA support
;
_pio_in:
	moveq.l	#0,d1
	move.b	CFU_ReceiveMode(a3),d1
	lsl.l	#1,d1
	lea	pi_tab(pc),a1
	add.w	(a1,d1.l),a1
	jmp	(a1)
pi_tab:
	dc.w	pi_mode0-pi_tab
	dc.w	pi_mode1-pi_tab
	dc.w	pi_mode2-pi_tab
	dc.w	pi_mode3-pi_tab
	dc.w	pi_mode4-pi_tab

; I/O Register 8, word-wise
pi_mode0:
	lsr.l	#4,d0
	subq.l	#1,d0
	move.l	CFU_IOPtr(a3),a0
	addq.l	#8,a0
pi0_loop:
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	move.w	(a0),(a2)+
	dbf	d0,pi0_loop
	rts

; I/O Register 8 and Duplikates, word-wise
pi_mode1:
	move.l	d2,-(sp)
pi1_loop1:
	moveq.l	#8192>>8,d1
	lsl.l	#8,d1
	sub.l	d1,d0
	bcc.s	pi1_1

	add.l	d1,d0
	move.l	d0,d1
	moveq.l	#0,d0
pi1_1:
	lsr.l	#4,d1
	subq.l	#1,d1
	moveq.l	#16,d2
	move.l	CFU_IOPtr(a3),a0
	addq.l	#8,a0
pi1_loop2:
	move.w	(a0),(a2)+
	add.l	d2,a0
	move.w	(a0),(a2)+
	add.l	d2,a0
	move.w	(a0),(a2)+
	add.l	d2,a0
	move.w	(a0),(a2)+
	add.l	d2,a0
	move.w	(a0),(a2)+
	add.l	d2,a0
	move.w	(a0),(a2)+
	add.l	d2,a0
	move.w	(a0),(a2)+
	add.l	d2,a0
	move.w	(a0),(a2)+
	add.l	d2,a0
	dbf	d1,pi1_loop2

	tst.l	d0
	bne.s	pi1_loop1

	move.l	(sp)+,d2
	rts

;I/O Registers 8 and 9 byte-wise
pi_mode2:
	lsr.l	#4,d0
	subq.l	#1,d0
	move.l	CFU_IOPtr(a3),a0
	addq.l	#8,a0
	move.l	a0,a1
	add.l	#$10001,a1
pi2_loop:
	move.b	(a0),(a2)+
	move.b	(a1),(a2)+
	move.b	(a0),(a2)+
	move.b	(a1),(a2)+
	move.b	(a0),(a2)+
	move.b	(a1),(a2)+
	move.b	(a0),(a2)+
	move.b	(a1),(a2)+
	move.b	(a0),(a2)+
	move.b	(a1),(a2)+
	move.b	(a0),(a2)+
	move.b	(a1),(a2)+
	move.b	(a0),(a2)+
	move.b	(a1),(a2)+
	move.b	(a0),(a2)+
	move.b	(a1),(a2)+
	dbf	d0,pi2_loop
	rts

;I/O Register 8, word-wise, drop every other word
pi_mode3:
	lsr.l	#4,d0
	subq.l	#1,d0
	move.l	CFU_IOPtr(a3),a0
	addq.l	#8,a0
pi3_loop:
	move.w	(a0),(a2)+
	move.w	(a0),d1
	move.w	(a0),(a2)+
	move.w	(a0),d1
	move.w	(a0),(a2)+
	move.w	(a0),d1
	move.w	(a0),(a2)+
	move.w	(a0),d1
	move.w	(a0),(a2)+
	move.w	(a0),d1
	move.w	(a0),(a2)+
	move.w	(a0),d1
	move.w	(a0),(a2)+
	move.w	(a0),d1
	move.w	(a0),(a2)+
	move.w	(a0),d1
	dbf	d0,pi3_loop
	rts

;memory mapped transfer, word-wise
pi_mode4:
pi4_loop1:
	moveq.l	#1024>>8,d1
	lsl.l	#8,d1
	sub.l	d1,d0
	bcc.s	pi4_1

	add.l	d1,d0
	move.l	d0,d1
	moveq.l	#0,d0
pi4_1:
	lsr.l	#4,d1
	subq.l	#1,d1
	move.l	CFU_MemPtr(a3),a0
	add.w	#1024,a0
pi4_loop2:
	move.w	(a0)+,(a2)+
	move.w	(a0)+,(a2)+
	move.w	(a0)+,(a2)+
	move.w	(a0)+,(a2)+
	move.w	(a0)+,(a2)+
	move.w	(a0)+,(a2)+
	move.w	(a0)+,(a2)+
	move.w	(a0)+,(a2)+
	dbf	d1,pi4_loop2

	tst.l	d0
	bne.s	pi4_loop1
	rts

;--- PIO OUT Transfer --------------------------------------
; Write data to CF card using Programmed I/O
;
; Input:
;   d0 = byte count to write
;   a2 = source buffer pointer
;   a3 = CFU pointer
;   CFU_SendMode = transfer mode (0-4)
;
; Output:
;   a2 = updated buffer pointer (past data written)
;
; Transfer Modes (CFU_SendMode):
;   0 = I/O Register 8, word-wise
;   1 = I/O Register 8 + duplicates, word-wise (8KB window)
;   2 = I/O Registers 8 and 9, byte-wise
;   3 = (redirects to mode 1)
;   4 = Memory mapped, word-wise (1KB window)
;
; Note: Mode selection is determined during card identification
; based on card capabilities and PCMCIA hardware.
;
_pio_out:
	moveq.l	#0,d1
	move.b	CFU_SendMode(a3),d1
	lsl.l	#1,d1
	lea	po_tab(pc),a1
	add.w	(a1,d1.l),a1
	jmp	(a1)
po_tab:
	dc.w	po_mode0-po_tab
	dc.w	po_mode1-po_tab
	dc.w	po_mode2-po_tab
	dc.w	po_mode1-po_tab
	dc.w	po_mode4-po_tab

; I/O Register 8, word-wise
po_mode0:
	lsr.l	#4,d0
	subq.l	#1,d0
	move.l	CFU_IOPtr(a3),a0
	addq.l	#8,a0
po0_loop:
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	dbf	d0,po0_loop
	rts

; I/O Register 8 and Duplikates, word-wise
po_mode1:
	move.l	d2,-(sp)
po1_loop1:
	moveq.l	#8192>>8,d1
	lsl.l	#8,d1
	sub.l	d1,d0
	bcc.s	po1_1

	add.l	d1,d0
	move.l	d0,d1
	moveq.l	#0,d0
po1_1:
	lsr.l	#4,d1
	subq.l	#1,d1
	moveq.l	#16,d2
	move.l	CFU_IOPtr(a3),a0
	addq.l	#8,a0
po1_loop2:
	move.w	(a2)+,(a0)
	add.l	d2,a0
	move.w	(a2)+,(a0)
	add.l	d2,a0
	move.w	(a2)+,(a0)
	add.l	d2,a0
	move.w	(a2)+,(a0)
	add.l	d2,a0
	move.w	(a2)+,(a0)
	add.l	d2,a0
	move.w	(a2)+,(a0)
	add.l	d2,a0
	move.w	(a2)+,(a0)
	add.l	d2,a0
	move.w	(a2)+,(a0)
	add.l	d2,a0
	dbf	d1,po1_loop2

	tst.l	d0
	bne.s	po1_loop1

	move.l	(sp)+,d2
	rts

;I/O Registers 8 and 9, byte-wise
po_mode2:
	lsr.l	#4,d0
	subq.l	#1,d0
	move.l	CFU_IOPtr(a3),a0
	addq.l	#8,a0
	move.l	a0,a1
	add.l	#$10001,a1
po2_loop:
	move.b	(a2)+,(a0)
	move.b	(a2)+,(a1)
	move.b	(a2)+,(a0)
	move.b	(a2)+,(a1)
	move.b	(a2)+,(a0)
	move.b	(a2)+,(a1)
	move.b	(a2)+,(a0)
	move.b	(a2)+,(a1)
	move.b	(a2)+,(a0)
	move.b	(a2)+,(a1)
	move.b	(a2)+,(a0)
	move.b	(a2)+,(a1)
	move.b	(a2)+,(a0)
	move.b	(a2)+,(a1)
	move.b	(a2)+,(a0)
	move.b	(a2)+,(a1)
	dbf	d0,po2_loop
	rts

;memory mapped transfer, word-wise
po_mode4:
po4_loop1:
	moveq.l	#1024>>8,d1
	lsl.l	#8,d1
	sub.l	d1,d0
	bcc.s	po4_1

	add.l	d1,d0
	move.l	d0,d1
	moveq.l	#0,d0
po4_1:
	lsr.l	#4,d1
	subq.l	#1,d1
	move.l	CFU_MemPtr(a3),a0
	add.w	#1024,a0
po4_loop2:
	move.w	(a2)+,(a0)+
	move.w	(a2)+,(a0)+
	move.w	(a2)+,(a0)+
	move.w	(a2)+,(a0)+
	move.w	(a2)+,(a0)+
	move.w	(a2)+,(a0)+
	move.w	(a2)+,(a0)+
	move.w	(a2)+,(a0)+
	dbf	d1,po4_loop2

	tst.l	d0
	bne.s	po4_loop1
	rts

;--- write Blocks ------------------------------------------
; Write sectors to CF card using PIO
;
; Input:
;   d0 = starting block number (LBA)
;   d1 = byte count to write
;   a0 = source buffer pointer, or -1 for erase (zero-fill)
;   a3 = CFU pointer
;
; Output:
;   d0 = bytes actually written (0 on error)
;
; Register usage:
;   d2 = current block number
;   d3 = bytes remaining
;   d4 = bytes per transfer chunk
;   d5 = total bytes (for return value)
;   d6 = sectors per interrupt
;   a2 = buffer pointer
;
; Notes:
;   - Uses WRITE SECTORS ($31) for single-sector transfers
;   - Uses WRITE MULTIPLE ($C5) for multi-sector transfers
;   - Handles ATAPI via SCSI path (_wb_scsi)
;   - Special case: a0=-1 writes zeros (erase)
;   - Retries up to 5 times on error
;
_WB2:
	move.l	a1,a0
_WriteBlocks:
	movem.l	d2-d6/a2,-(sp)
	move.l	a0,a2			;&buffer
	move.l	d0,d2			;Block #
	move.l	d1,d3			;total bytes
	move.l	d1,d5
	beq.w	_wb_ready		;nothing to do

	tst.w	CFU_PLength(a3)
	bgt.w	_wb_scsi

	bsr.w	_IDEStart
	tst.l	CFU_DriveSize(a3)
	beq.w	_wb_nodisk
_wb_swath:
	move.w	#5,CFU_Try(a3)
	move.l	d2,CFU_Block(a3)
	move.l	d3,CFU_Count(a3)
	move.l	a2,CFU_Buffer(a3)
_wb_try:
	moveq.l	#0,d4
	move.w	CFU_MultiSizeRW(a3),d4
	cmp.l	d4,d3
	bcc.s	_wb_1

	move.l	d3,d4			;bytes/part
_wb_1:
	lea	CFU_IDESet+2(a3),a0
	moveq.l	#0,d1
	move.w	CFU_MultiSize(a3),d1
	move.l	d1,d6			;Blocks/Interrupt
	move.b	d4,(a0)+		;Sektors
	move.b	d2,(a0)+		;LBA 7-0
	move.l	d2,d0
	lsr.l	#8,d0
	rol.w	#8,d0
	move.w	d0,(a0)+		;LBA 23-8
	lsr.l	#8,d0
	and.w	#$0f00,d0
	subq.w	#1,d1
	beq.s	_wb_2

	or.w	#$e0c5,d0		;LBA 27-24 and WRITE MULTIPLE
	bra.s	_wb_3
_wb_2:
	or.w	#$e031,d0		;LBA 27-24 and WRITE SECTORS
_wb_3:
	move.l	a2,d1
	addq.l	#1,d1
	beq.w	_wb_erase		;&buffer = -1 -> erase only

	move.w	d0,(a0)			;go!
	bsr.w	_IDECmd
	tst.w	d0
	beq.w	_wb_nodisk

	move.l	CFU_IDEAddr(a3),a0
	addq.l	#8,a0
	move.l	#A_Pb,a1
	tst.b	(a1)
	nop
_wb_w2:
	tst.b	(a1)
	nop
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.w	_wb_nodisk		;card removed

	move.b	7-8(a0),d0
	bmi.s	_wb_w2			;BSY

	moveq.l	#$21,d1			;DWF and ERR
	and.b	d0,d1
	bne.w	_wb_break

	btst	#3,d0			;DRQ
	beq.s	_wb_w2
	bra.s	_wb_w3
_wb_block:
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.w	_wb_nodisk		;card removed

	moveq.l	#$29,d0			;DWF, DRQ, ERR
	and.b	CFU_IDEStatus(a3),d0
	subq.b	#8,d0			;DRQ
	bne.w	_wb_break

	move.l	CFU_IOPtr(a3),a0
	addq.l	#8,a0
_wb_w3:
	cmp.l	d6,d4
	bcc.s	_wb_w4

	move.l	d4,d6
_wb_w4:
	move.l	d6,d0
	move.b	CFU_SendMode(a3),d1
	bne.s	_wb_l1

	lsl.l	#5,d0
	subq.l	#1,d0
_wb_loop0:
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	move.w	(a2)+,(a0)
	dbf	d0,_wb_loop0
_wb_lnext:
	bsr.w	WaitReady
	add.l	d6,d2
	sub.l	d6,d3
	sub.l	d6,d4
	bgt.s	_wb_block

	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.s	_wb_nodisk		;card removed

	move.b	CFU_IDEStatus(a3),d0
	moveq.l	#$21,d1			;DF and ERR
	and.b	d0,d1
	bne.w	_wb_break

	btst	#3,d0			;DRQ
	bne.s	_wb_bump		;you want more than requested??
_wb_snext:
	tst.l	d3
	bgt.w	_wb_swath
_wb_stop:
	bsr.w	_IDEStop
_wb_ready:
	move.l	a2,a0
	move.l	d5,d0
	sub.l	d3,d0
	movem.l	(sp)+,d2-d6/a2
	rts

_wb_l1:
	lsl.l	#8,d0
	lsl.l	#1,d0
	bsr.w	_pio_out
	bra.s	_wb_lnext

_wb_erase:
	move.b	#$c0,d0			;"CFA ERASE SECTORS"
	move.w	d0,(a0)
	bsr.w	_IDECmd
	tst.w	d0
	beq.s	_wb_nodisk

	bsr.w	WaitReady
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.s	_wb_nodisk		;card removed

	moveq.l	#$ffffffa9,d0		;BSY, DWF, DRQ, ERR
	and.b	CFU_IDEStatus(a3),d0
	beq.s	_wb_eok
_wb_eerror:
	move.b	#IOERR_NOCMD,CFU_IOErr(a3)
	bsr.w	_IDEError
	bra.s	_wb_stop
_wb_eok:
	add.l	d4,d2
	sub.l	d4,d3
	bra.s	_wb_snext

_wb_nodisk:
	move.b	#TDERR_DISKCHANGED,CFU_IOErr(a3)
	bra.s	_wb_stop

_wb_bump:
	move.w	#$e000,CFU_IDESet+6(a3)	;NOP
	bsr.w	_IDECmd			;abort
	bsr.w	WaitReady
	move.b	CFU_SendMode(a3),d0
	cmp.b	#3,d0
	bgt.s	_wb_break
	beq.s	_wb_switch

	addq.b	#1,CFU_SendMode(a3)	;try different transfer mode
	bra.s	_wb_break
_wb_switch:
	bsr.w	_IDEStop
	move.w	#$0404,CFU_ReceiveMode(a3)
	move.l	CFU_ConfigAddr(a3),a0
	move.b	#$40,(a0)
	bsr.w	Wait40
	move.l	CFU_MemPtr(a3),CFU_IDEAddr(a3)
	bsr.w	_IDEStart
_wb_break:
	move.b	#TDERR_NOSECHDR,CFU_IOErr(a3)
	bsr.w	_IDEError
	addq.l	#1,CFU_WriteErrors(a3)
	subq.w	#1,CFU_Try(a3)
	beq.w	_wb_stop

	clr.b	CFU_IOErr(a3)
	move.l	CFU_Block(a3),d2
	move.l	CFU_Count(a3),d3
	move.l	CFU_Buffer(a3),a2
	bra.w	_wb_try

_wb_scsi:
	move.l	a2,d1
	add.l	#1,d1
	beq.w	_wb_eerror		;erase is IDE only

	moveq.l	#0,d4
	not.w	d4
	cmp.l	d4,d3
	bcc.s	_wb_s1

	move.l	d3,d4
_wb_s1:
	lea	CFU_SCSIStruct(a3),a0
	move.l	a2,(a0)+		;SCSI_Data
	move.l	d4,d0
	lsl.l	#8,d0
	lsl.l	#1,d0
	move.l	d0,(a0)+		;SCSI_Length
	clr.l	(a0)+			;SCSI_Actual
	lea	CFU_Packet(a3),a1
	move.l	a1,(a0)+		;SCSI_Command
	moveq.l	#10,d0
	swap	d0
	move.l	d0,(a0)+		;SCSI_CmdLength, _CmdActual
	move.w	#SCSIF_WRITE<<8,(a0)	;SCSI_Flags, _Status
	move.w	#WRITE10<<8,(a1)+
	move.l	d2,(a1)+
	move.l	d4,d0
	lsl.l	#8,d0
	move.l	d0,(a1)
	lea	CFU_SCSIStruct(a3),a0
	bsr.w	_Packet
	tst.b	d0
	bne.s	_wb_serror

	move.l	CFU_SCSIStruct+SCSI_Actual(a3),d0
	add.l	d0,a2
	lsr.l	#8,d0
	lsr.l	#1,d0
	sub.l	d0,d3
	bgt.s	_wb_scsi
	bra.w	_wb_ready

_wb_serror:
	move.b	#TDERR_NOTSPECIFIED,CFU_IOErr(a3)
	bra.w	_wb_ready

;--- set fast transfer mode --------------------------------
;d0 -> Blocks/Interrupt

_InitMultipleMode:
	bsr.w	_IDEStart
	moveq.l	#0,d1
	move.b	CFU_ConfigBlock+95(a3),d1	;word 47 bits 15:8 = MaxMulti count
	ifd	DEBUG
	move.l	d1,-(sp)
	DBGMSG	dbg_multimax
	move.l	(sp),d0
	bsr.w	_DebugDecimal
	bsr.w	_DebugNewline
	move.l	(sp)+,d1
	endc
	tst.b	d1
	beq.w	_imm_nosup		;0 = not supported

	ifd	DEBUG
	move.l	d1,-(sp)
	DBGMSG	dbg_multiset
	move.l	(sp),d0
	bsr.w	_DebugDecimal
	bsr.w	_DebugNewline
	move.l	(sp)+,d1
	endc
	lea	CFU_IDESet+2(a3),a0
	lsl.w	#8,d1
	move.w	d1,(a0)+
	moveq.l	#0,d1
	move.w	d1,(a0)+
	move.w	#$e0c6,(a0)		;"SET MULTIPLE MODE"
	bsr.w	_IDECmd
	tst.w	d0
	beq.w	_imm_error

	bsr.w	WaitReady
	moveq.l	#3,d1
	and.b	CFU_EventFlags(a3),d1
	bne.w	_imm_error		;card removed

	moveq.l	#$21,d1
	and.b	CFU_IDEStatus(a3),d1
	bne.w	_imm_error		;error or unsupported

	DBGMSG	dbg_multiok

	bsr.w	_IDEStop
	moveq.l	#0,d0
	move.b	CFU_ConfigBlock+95(a3),d0	;word 47 bits 15:8 = MaxMulti count
_imm_end:
	move.w	d0,CFU_MultiSize(a3)
	move.w	CFU_MultiSize(a3),d0
	;Set CFU_MultiSizeRW: static 256 if flag 16 (enforce multi mode), else auto-detect
	btst	#4,CFU_OpenFlags+1(a3)		;flag 16 = enforce multi mode?
	beq.s	_imm_auto_detect
	move.w	#256,CFU_MultiSizeRW(a3)	;static override
	bra.s	_imm_rw_debug

_imm_auto_detect:
	;--- Check if auto-detection is disabled (Flags=32) ---
	btst	#5,CFU_OpenFlags+1(a3)		;flag 32 = skip auto-detection?
	bne.s	_imm_rw_skip_auto		;yes, use firmware value directly

	;--- Auto-detect multi-sector capability ---
	;Test by reading 1 sector and checking if DRQ clears properly
	;If DRQ clears after reading expected data, card works correctly -> use 256
	;If DRQ stays high, card has issue -> use firmware value
	bsr.w	_TestMultiSectorIssue
	tst.b	d0
	bne.s	_imm_rw_drq_issue		;DRQ issue detected, use firmware value
	DBGMSG	dbg_multi_ok256
	move.w	#256,CFU_MultiSizeRW(a3)	;auto-detected: card works, use 256
	bra.s	_imm_rw_debug

_imm_rw_skip_auto:
	DBGMSG	dbg_multi_skip
	ifd	DEBUG
	bra.s	_imm_rw_firmware
	endc

_imm_rw_drq_issue:
	DBGMSG	dbg_multi_drq_issue
	;fall through to _imm_rw_firmware

_imm_rw_firmware:
	moveq.l	#0,d0
	move.w	CFU_MultiSize(a3),d0
	move.w	d0,CFU_MultiSizeRW(a3)		;use firmware value
_imm_rw_debug:
	ifd	DEBUG
	move.l	d0,-(sp)
	DBGMSG	dbg_multisizerw
	moveq.l	#0,d0
	move.w	CFU_MultiSizeRW(a3),d0
	bsr.w	_DebugDecimal
	bsr.w	_DebugNewline
	move.l	(sp)+,d0
	endc
	rts

_imm_nosup:
	DBGMSG	dbg_multinosup
	moveq.l	#1,d0			;default to single blocks
	bra.w	_imm_end

_imm_error:
	ifd	DEBUG
	moveq.l	#0,d0
	move.b	CFU_IDEStatus(a3),d0
	bsr.w	_DebugIDEStatus		;show what went wrong
	endc
	DBGMSG	dbg_multifail
	moveq.l	#1,d0			;default to single blocks
	bra.w	_imm_end

;--- Test Multi-Sector Capability ---------------------------
;
; Tests if the card properly clears DRQ after reading
; the expected number of sectors. Some CF/SD adapters 
; report MaxMulti=1 but actually work fine with higher
; values (DRQ clears properly after reading).
;
; Method:
;   1. Issue READ SECTORS for LBA 0, 1 sector
;   2. Read 512 bytes (1 sector)
;   3. Check if DRQ clears after reading
;
; Input:
;   a3 = CFU pointer
;   IDE access must be available
;
; Output:
;   d0 = 0 if DRQ cleared properly (card works, use 256)
;   d0 = 1 if DRQ stayed high (issue detected, use firmware value)
;
; Preserves: a2-a6, d2-d7
;
_TestMultiSectorIssue:
	movem.l	d1-d2/a0-a1,-(sp)
	DBGMSG	dbg_multi_test

	;--- Start IDE access ---
	bsr.w	_IDEStart

	;--- Issue READ SECTORS command for LBA 0, 1 sector ---
	lea	CFU_IDESet+2(a3),a0
	move.w	#$0100,(a0)+		;1 sector, LBA bits 7:0 = 0
	clr.w	(a0)+			;LBA bits 23:8 = 0
	move.w	#$e020,(a0)		;LBA mode, drive 0, READ SECTORS ($20)
	bsr.w	_IDECmd
	tst.w	d0
	beq.s	_tms_ok			;command failed, assume card works

	;--- Wait for DRQ ---
	bsr.w	WaitReady
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.s	_tms_ok			;card removed, assume ok

	moveq.l	#$29,d0			;DF, DRQ, ERR
	and.b	CFU_IDEStatus(a3),d0
	subq.b	#8,d0			;DRQ?
	bne.s	_tms_ok			;no DRQ, assume card works

	;--- Read 512 bytes (discard data) ---
	;Uses word reads, 256 iterations of 1 word = 512 bytes
	move.l	CFU_IOPtr(a3),a0
	addq.l	#8,a0			;IDE data register
	move.w	#256-1,d1		;256 word reads
_tms_read:
	move.w	(a0),d2			;read and discard
	dbf	d1,_tms_read

	;--- Check if DRQ is still set ---
	;If DRQ cleared, card works correctly
	;If DRQ still set, card has issue
	move.l	CFU_IDEAddr(a3),a0
	move.b	14(a0),d0		;read status register
	btst	#3,d0			;DRQ still set?
	beq.s	_tms_ok			;DRQ cleared = card works

	;--- DRQ still set = issue detected ---
	bsr.w	_IDEStop
	moveq.l	#1,d0			;return 1 = issue, use firmware value
	bra.s	_tms_end

_tms_ok:
	bsr.w	_IDEStop
	moveq.l	#0,d0			;return 0 = card works, use 256
_tms_end:
	movem.l	(sp)+,d1-d2/a0-a1
	rts

;--- PIO Mode to Memory Timing Mapping ---------------------
; Compile-time option: FASTPIO
;
; Maps card's ATA PIO mode capability to Gayle PCMCIA memory
; access timing. This sets the memory bus speed based on what
; the card reports it can handle.
;
; Input:
;   a3 = CFU pointer
;   CFU_ConfigBlock contains IDENTIFY data
;
; IDENTIFY Word 51 (offset 102), bits 15:8:
;   0 = PIO mode 0, 1 = PIO mode 1, 2 = PIO mode 2
;
; IDENTIFY Word 64 (offset 128):
;   Bit 0: PIO mode 3 supported (180ns cycle)
;   Bit 1: PIO mode 4 supported (120ns cycle)
;
; PIO to Gayle memory timing mapping:
;   PIO 4 (120ns) -> Gayle 100ns
;   PIO 3 (180ns) -> Gayle 150ns
;   PIO 2 (240ns) -> Gayle 250ns
;   PIO 1 (383ns) -> Gayle 250ns
;   PIO 0 (600ns) -> Gayle 720ns (default)
;
_OptimizePIOSpeed:
	ifd	FASTPIO
	DBGMSG	dbg_gayle_timing

	;Check Word 64 for advanced PIO modes (3/4)
	;d0 = Gayle speed (ns), d1 = PIO mode number
	move.w	CFU_ConfigBlock+128(a3),d0	;Word 64: advanced PIO modes
	btst	#1,d0			;PIO mode 4?
	beq.s	_ops_pio3

	;PIO mode 4: use 100ns (Gayle fastest)
	moveq.l	#4,d1			;PIO mode 4
	move.l	#100,d0			;Gayle 100ns
	bra.s	_ops_set
_ops_pio3:
	btst	#0,d0			;PIO mode 3?
	beq.s	_ops_pio2

	;PIO mode 3: use 150ns
	moveq.l	#3,d1			;PIO mode 3
	move.l	#150,d0			;Gayle 150ns
	bra.s	_ops_set
_ops_pio2:
	;Check Word 51 high byte for basic PIO modes (0/1/2)
	move.b	CFU_ConfigBlock+102(a3),d0	;Word 51 bits 15:8
	cmp.b	#2,d0			;PIO mode 2?
	bne.s	_ops_pio1

	;PIO mode 2: use 250ns
	moveq.l	#2,d1			;PIO mode 2
	move.l	#250,d0			;Gayle 250ns
	bra.s	_ops_set
_ops_pio1:
	cmp.b	#1,d0			;PIO mode 1?
	bne.w	_ops_end		;PIO 0, keep default 720ns

	;PIO mode 1: use 250ns
	moveq.l	#1,d1			;PIO mode 1
	move.l	#250,d0			;Gayle 250ns
_ops_set:
	move.l	d0,CFU_DTSpeed(a3)
	ifd	DEBUG
	movem.l	d0-d1,-(sp)
	DBGMSG	dbg_card_pio
	move.l	4(sp),d0		;PIO mode (d1)
	bsr.w	_DebugDecimal
	DBGMSG	dbg_gayle_speed
	move.l	(sp),d0			;Gayle speed (d0)
	bsr.w	_DebugDecimal
	DBGMSG	dbg_ns
	movem.l	(sp)+,d0-d1
	endc

	;Check compatibility flag to choose method
	btst	#2,CFU_OpenFlags+1(a3)	;Flags = 4?
	beq.s	_ops_direct		;not set, try direct

	;Use CardResource API (Flags = 4)
	ifd	DEBUG
	DBGMSG	dbg_gayle_cardres
	;Show current Gayle speed before changing
	DBGMSG	dbg_gayle_current
	move.l	#$00DAB000,a0
	moveq.l	#0,d0
	move.b	(a0),d0
	and.b	#$0C,d0			;mask speed bits 2-3
	bsr.w	_ops_bits_to_ns		;convert to nanoseconds
	bsr.w	_DebugDecimal
	DBGMSG	dbg_ns
	endc
	move.l	CFU_DTSpeed(a3),d0
	lea	CFU_CardHandle(a3),a1
	CALLCARD CardAccessSpeed
	bra.s	_ops_show_actual

_ops_direct:
	;Direct Gayle write to register $DAB000
	;  bits 2-3 = memory speed
	;  00 = 250ns (default), 01 = 150ns, 10 = 100ns, 11 = 720ns
	ifd	DEBUG
	DBGMSG	dbg_gayle_direct
	;Show current Gayle speed before changing
	DBGMSG	dbg_gayle_current
	move.l	#$00DAB000,a0
	moveq.l	#0,d0
	move.b	(a0),d0
	and.b	#$0C,d0			;mask speed bits 2-3
	bsr.s	_ops_bits_to_ns		;convert to nanoseconds
	bsr.w	_DebugDecimal
	DBGMSG	dbg_ns
	endc
	;Convert nanoseconds to Gayle speed bits
	move.l	CFU_DTSpeed(a3),d0
	moveq.l	#0,d1			;speed bits
	cmp.l	#150,d0
	bhi.s	_ops_d_250		;>150 = 250ns or slower
	cmp.l	#100,d0
	bhi.s	_ops_d_150		;>100 = 150ns
	moveq.l	#8,d1			;100ns = bit 3
	bra.s	_ops_d_set
_ops_d_150:
	moveq.l	#4,d1			;150ns = bit 2
	bra.s	_ops_d_set
_ops_d_250:
	cmp.l	#720,d0
	bls.s	_ops_d_set		;<=720 = 250ns (d1=0)
	moveq.l	#12,d1			;720ns = bits 2+3
_ops_d_set:
	;Write $DAB000
	;Preserve bits 0-1 (voltage), set bits 2-3 (speed)
	move.l	#$00DAB000,a0
	move.b	(a0),d0			;read current value
	and.b	#$03,d0			;keep voltage bits 0-1
	or.b	d1,d0			;add speed bits 2-3
	move.b	d0,(a0)			;write to
	;Read back and convert bits to nanoseconds
	moveq.l	#0,d0
	move.b	(a0),d0			;read back
	and.b	#$0C,d0			;mask speed bits 2-3
	bsr.s	_ops_bits_to_ns		;convert to nanoseconds

_ops_show_actual:
	ifd	DEBUG
	;d0 = actual speed selected by hardware
	move.l	d0,-(sp)
	DBGMSG	dbg_gayle_actual
	move.l	(sp)+,d0
	bsr.w	_DebugDecimal
	DBGMSG	dbg_ns
	endc
_ops_end:
	rts
	else
	;FASTPIO not compiled - read and show current Gayle speed
	ifd	DEBUG
	DBGMSG	dbg_gayle_timing
	DBGMSG	dbg_gayle_current
	move.l	#$00DAB000,a0
	moveq.l	#0,d0
	move.b	(a0),d0
	and.b	#$0C,d0			;mask speed bits 2-3
	bsr.s	_ops_bits_to_ns		;convert to nanoseconds
	bsr.w	_DebugDecimal
	DBGMSG	dbg_ns
	endc
	rts
	endc

;Convert Gayle speed bits to nanoseconds
;Input:  d0 = speed bits (0, 4, 8, or 12)
;Output: d0 = nanoseconds (250, 150, 100, or 720)
_ops_bits_to_ns:
	cmp.b	#8,d0
	beq.s	_ops_b_100
	cmp.b	#4,d0
	beq.s	_ops_b_150
	cmp.b	#12,d0
	beq.s	_ops_b_720
	move.l	#250,d0			;default 250ns (bits=0)
	rts
_ops_b_100:
	move.l	#100,d0
	rts
_ops_b_150:
	move.l	#150,d0
	rts
_ops_b_720:
	move.l	#720,d0
	rts

;--- start disk --------------------------------------------

_SpinUp:	
	bsr.w	_IDEStart
	move.l	CFU_IDEAddr(a3),a0
	move.l	#A_Pb,a1
	tst.b	(a1)
	nop
_su_wait:
	tst.b	(a1)
	nop
	move.b	7(a0),d0
	bmi.s	_su_wait		;BSY

	move.b	#7,13(a0)		;Subkommand "Spin Up"
	move.b	#$ef,7(a0)		;SET FEATURES
	bsr.w	WaitReady
	move.b	CFU_IDEStatus(a3),d0
	bra.w	_IDEStop

;--- query Disk Status -------------------------------------
; d0 -> -1 (error), 0 (no disk), 1 (inserted), 2 (new Disk)

_MediaStatus:
	move.l	d2,-(sp)
	moveq.l	#-1,d2
	bsr.w	_IDEStart
	move.l	CFU_IDEAddr(a3),a0
	move.b	7(a0),d0
	and.b	#$c0,d0			;BSY, DRDY
	cmp.b	#$40,d0			;DRDY
	bne.s	_ms_end

	move.b	#$da,7(a0)		;"GET MEDIA STATUS"
	bsr.w	WaitReady
	move.b	CFU_IDEStatus(a3),d0
	bmi.s	_ms_end

	moveq.l	#1,d2
	btst	#0,d0
	beq.s	_ms_end			;Disk OK

	move.l	CFU_IDEAddr(a3),a0
	move.b	13(a0),d0
	moveq.l	#0,d2
	btst	#1,d0			;NM
	bne.s	_ms_end			;no Disk

	moveq.l	#2,d2
	btst	#5,d0			;MC
	bne.s	_ms_end			;new Disk

	moveq.l	#-1,d2
_ms_end:
	bsr.w	_IDEStop
	move.l	d2,d0
	move.l	(sp)+,d2
	rts

;--- ATAPI!!! ATAPI! ---------------------------------------
; a0 <- &SCSIStruct
; d0 -> error code

_Packet:
	movem.l	d2-d6/a2/a5,-(sp)
	move.l	a0,a5			;&SCSIStruct
	move.l	(a5),d4			;SCSI_Data
	moveq.l	#0,d5			;no error
	move.l	SCSI_Length(a5),d6	;bytes to transfer
	move.l	SCSI_Command(a5),a0
	lea	CFU_Packet(a3),a1
	move.w	SCSI_CmdLength(a5),d1
	move.w	CFU_PLength(a3),d2
	sub.w	d1,d2
	bcc.s	_p_1

	add.w	d2,d1
	moveq.l	#0,d2
_p_1:
	move.w	d1,SCSI_CmdActual(a5)
_p_2:
	move.b	(a0)+,(a1)+		;copy command line..
	subq.w	#1,d1
	bgt.s	_p_2
	bra.s	_p_4
_p_3:
	clr.b	(a1)+			;..and maybe pad it
_p_4:
	subq.w	#1,d2
	bpl.s	_p_3

	bsr.w	_IDEStart
	or.b	#$20,CFU_EventFlags(a3)	;Interrupt response OFF
	move.l	CFU_IDEAddr(a3),a2
	move.w	#5,CFU_Try(a3)
_p_wait1:
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.w	_p_nodisk

	tst.b	A_Pb
	nop
	move.b	7(a2),d0
	bmi.s	_p_wait1		;BSY

	btst	#3,d0
	bne.s	_p_wait1		;DRQ
_p_try1:
	subq.w	#1,CFU_Try(a3)
	bmi.w	_p_error

	moveq.l	#0,d0
	move.b	d0,13(a2)		;DMA & Release OFF
	move.l	SCSI_Length(a5),d0
	moveq.l	#$7f,d1
	ror.w	#7,d1
	cmp.l	d0,d1
	bcc.s	_p_5

	move.l	d1,d0
_p_5:
	and.w	#$fffe,d0
	rol.w	#8,d0
	move.w	d0,4(a2)		;ATAPI Bytecount limit
	move.w	#$a0a0,6(a2)		;drive 0, PACKET
_p_wait2:
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.w	_p_nodisk

	tst.b	A_Pb
	nop
	move.b	7(a2),d0
	bmi.s	_p_wait2		;BSY

	moveq.l	#$21,d1			;DWF, ERR
	and.b	d0,d1
	bne.s	_p_try1

	btst	#3,d0			;DRQ
	beq.s	_p_try1

	moveq.l	#3,d0
	and.b	2(a2),d0		;I/O and C/D
	subq.b	#1,d0
	bne.s	_p_try1

	bsr.w	ClearWaitSignal
	and.b	#$df,CFU_EventFlags(a3)	;Interrupt response ON
	lea	CFU_Packet(a3),a0
	move.w	CFU_PLength(a3),d1
_p_packet:
	move.w	(a0)+,(a2)		;send kommand line
	subq.w	#2,d1
	bgt.s	_p_packet
_p_data:
	tst.l	d6
	bmi.w	_p_abort

	bsr.w	WaitReady
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.w	_p_nodisk

	move.b	CFU_IDEStatus(a3),d0
	btst	#3,d0
	beq.w	_p_ready		;no data left

	moveq.l	#0,d2
	move.b	5(a2),d2
	lsl.w	#8,d2
	move.b	4(a2),d2		;ATAPI Bytecount..
	tst.w	d2
	beq.w	_p_ready

	sub.l	d2,d6
	bcc.s	_p_d1

	add.l	d6,d2			;..limited to remaining length
	moveq.l	#-1,d6
_p_d1:
	lea	0(a2),a0
	move.l	d4,a1			;&buffer
	move.b	2(a2),d0		;ATAPI Interrupt reason
	move.b	SCSI_Flags(a5),d1
	rol.b	#1,d1
	eor.b	d1,d0
	roxr.b	#2,d0
	bcs.w	_p_error		;wrong data direction

	add.l	d2,d4			;advance &buffer
	move.l	d2,d3
	lsr.l	#4,d3
	move.l	d3,d0
	lsl.l	#4,d0
	sub.l	d0,d2
	roxr.b	#2,d1
	bcc.w	_p_w2
	bra.s	_p_r2
_p_r1:
	move.w	(a0),(a1)+		;read a lot fast..
	move.w	(a0),(a1)+
	move.w	(a0),(a1)+
	move.w	(a0),(a1)+
	move.w	(a0),(a1)+
	move.w	(a0),(a1)+
	move.w	(a0),(a1)+
	move.w	(a0),(a1)+
_p_r2:
	dbf	d3,_p_r1
	bra.s	_p_r4
_p_r3:
	move.w	(a0),(a1)+		;..and some Rest
_p_r4:
	subq.w	#2,d2
	bpl.s	_p_r3

	addq.w	#1,d2
	bne.w	_p_data

	move.w	(a0),d0
	lsr.w	#8,d0
	move.b	d0,(a1)+
	bra.w	_p_data
_p_w1:
	move.w	(a1)+,(a0)		;write
	move.w	(a1)+,(a0)
	move.w	(a1)+,(a0)
	move.w	(a1)+,(a0)
	move.w	(a1)+,(a0)
	move.w	(a1)+,(a0)
	move.w	(a1)+,(a0)
	move.w	(a1)+,(a0)
_p_w2:
	dbf	d3,_p_w1
	bra.s	_p_w4
_p_w3:
	move.w	(a1)+,(a0)
_p_w4:
	subq.w	#2,d2
	bpl.s	_p_w3

	addq.w	#1,d2
	bne.w	_p_data

	move.b	(a1)+,d0
	lsl.w	#8,d0
	move.w	d0,(a0)
	bra.w	_p_data

_p_abort:
	moveq.l	#0,d0
	move.b	d0,13(a2)
	move.b	d0,7(a2)		;NOP
_p_ready:
	clr.b	SCSI_Status(a5)
	move.b	CFU_IDEStatus(a3),d0
	and.b	#$21,d0
	beq.s	_p_stop
_p_error:
	moveq.l	#45,d5
_p_checkc:
	move.b	#2,SCSI_Status(a5)
_p_stop:
	bsr.w	_IDEStop
	sub.l	(a5),d4			;SCSI_Data
	move.l	d4,SCSI_Actual(a5)
	move.l	d5,d0
	movem.l	(sp)+,d2-d6/a2/a5
	rts

_p_nodisk:
	moveq.l	#TDERR_DISKCHANGED,d5
	bra.s	_p_checkc

;--- query ATAPI drive size --------------------------------
; d0 -> # Blocks

ATAPISize:
	bsr.w	_MediaStatus
	move.l	d0,d1
	beq.s	as_end			;no Disk
	bmi.s	as_rc			;error

	subq.l	#1,d1
	bne.s	as_rc			;new Disk

	move.l	CFU_DriveSize(a3),d1
	bne.s	as_end			;already registered
as_rc:
	lea	CFU_SCSIStruct(a3),a0
	lea	CFU_ConfigBlock+504(a3),a1
	move.l	a1,(a0)+		;SCSI_Data
	moveq.l	#8,d0
	move.l	d0,(a0)+		;SCSI_Length
	clr.l	(a0)+			;SCSI_Actual
	lea	CFU_Packet(a3),a1
	move.l	a1,(a0)+		;SCSI_Command
	move.w	#10,(a0)+		;SCSI_CmdLength
	clr.w	(a0)+			;SCSI_CmdActual
	move.w	#SCSIF_READ<<8,(a0)	;SCSI_Flags, _Status
	move.w	#READCAPACITY<<8,(a1)+
	clr.l	(a1)+
	clr.l	(a1)
	lea	CFU_SCSIStruct(a3),a0
	bsr.w	_Packet
	moveq.l	#0,d1
	tst.b	d0
	bne.s	as_end

	move.l	CFU_ConfigBlock+508(a3),d1
	move.l	d1,CFU_BlockSize(a3)
	move.l	d1,d0
	bsr.w	Log2
	bclr	d0,d1
	tst.l	d1
	beq.s	as_1

	moveq.l	#-1,d0
as_1:
	move.w	d0,CFU_BlockShift(a3)
	move.l	CFU_ConfigBlock+504(a3),d1
	addq.l	#1,d1
as_end:
	move.l	d1,d0
	rts

;--- query ATAPI media change ------------------------------

ATAPIPoll:
	tst.w	CFU_PLength(a3)
	ble.s	ap_end			;not in ATAPI mode

	lea	CFU_TimeReq(a3),a1
	CALLEXEC CheckIO
	tst.l	d0
	beq.s	ap_end			;still too early

	lea	CFU_TimeReq(a3),a1
	CALLEXEC WaitIO
	bsr.w	ATAPISize
	move.l	CFU_DriveSize(a3),d1
	cmp.l	d0,d1
	beq.s	ap_time			;still all the same

	move.l	d0,CFU_DriveSize(a3)
	bsr.w	NotifyClients
ap_time:
	lea	CFU_TimeReq(a3),a1
	move.w	#TR_ADDREQUEST,IO_Command(a1)
	moveq.l	#1,d0
	move.l	d0,TR_Seconds(a1)
	clr.l	TR_Micros(a1)
	CALLEXEC SendIO
ap_end:
	rts

;*** Some math *********************************************
; d0 *= d1

UMul32:
	movem.l	d1-d3,-(sp)
	move.w	d1,d2
	mulu.w	d0,d2
	move.l	d1,d3
	swap	d3
	mulu.w	d0,d3
	swap	d3
	clr.w	d3
	add.l	d3,d2
	swap	d0
	mulu.w	d1,d0
	swap	d0
	clr.w	d0
	add.l	d2,d0
	movem.l	(sp)+,d1-d3
	rts

; d0 /= d1, d1 = d0 mod d1

UDivMod32:
	movem.l	d2/d3,-(sp)
	swap	d1
	tst.w	d1
	bne.s	udm32_long		;Divisor > $ffff

	swap	d1
	move.w	d1,d3
	move.w	d0,d2
	clr.w	d0
	swap	d0
	divu.w	d3,d0
	move.l	d0,d1
	swap	d0
	move.w	d2,d1
	divu.w	d3,d1
	move.w	d1,d0
	clr.w	d1
	swap	d1
	movem.l	(sp)+,d2/d3
	rts

udm32_long:
	swap	d1
	move.l	d1,d3
	move.l	d0,d1
	clr.w	d1
	swap	d1
	swap	d0
	clr.w	d0
	moveq.l	#15,d2
udm32_loop:
	add.l	d0,d0
	addx.l	d1,d1
	cmp.l	d1,d3
	bhi.s	udm32_next

	sub.l	d3,d1
	addq.w	#1,d0
udm32_next:
	dbf	d2,udm32_loop

	movem.l	(sp)+,d2/d3
	rts

;--- dual Logarithm ----------------------------------------
; d0 -> ld(d0)

Log2:
	move.l	d1,-(sp)
	moveq.l	#-1,d1
lg2_loop:
	addq.l	#1,d1
	lsr.l	#1,d0
	bne.s	lg2_loop

	move.l	d1,d0
	move.l	(sp)+,d1
	rts

	cnop	0,4

s_codeend:

;*** that's it!!!! *****************************************
	end
