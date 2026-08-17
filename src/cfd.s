; compactflash.device driver
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
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
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
; via PCMCIA slot on Amiga 600/1200. It supports both ATA (CF native) as well
; as SD cards via SD-to-CF adapters.
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
;   Full build (DEBUG=1): includes serial debug output (~10 KB)
;   Small build (no DEBUG): minimal binary size (~8 KB)
;   Gayle timing (GTIMING=1): enables Gayle timing mapping based on CF PIO mode capabilities (experimental)
;
;===========================================================================

;--- Conditional compilation ---
; Define DEBUG symbol to include serial debug support
; Set via assembler command line: -DDEBUG=1
; Or uncomment the next line:
;DEBUG	= 1

; Define GTIMING symbol to enable PIO speed optimization
; Set via assembler command line: -DGTIMING=1
; Or uncomment the next line:
;GTIMING	= 1

; --- Includes ---
	include	"cfd_version.i"
	include	"cfd_debug.i"
	include	"ptable_pub.i"		;from the ptable submodule (-I extern/ptable/src)
	include	"cfd_pub.i"		;CFD/CFU offsets shared with compactflash.automount

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

	include	"lib/umul32.i"
	include	"lib/log2.i"
	include	"lib/udivmod32.i"

_AbsExecBase	= 4

;SysBase offsets (subset)
SB_DeviceList	= 350			;ExecBase->DeviceList head

FindResident	= -96
InitResident	= -102
Disable		= -120
Enable		= -126
Forbid		= -132
Permit		= -138
FindName	= -276
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

;-- dos.library (worker reads the config var)
DosGetVar	= -906
Delay		= -198			;dos.library
DosOpen		= -30			;dos.library
DosClose	= -36			;dos.library
DosRead		= -42			;dos.library
MODE_OLDFILE	= 1005
GVF_GLOBAL_ONLY	= $100
GVF_BINARY_VAR	= $400
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
NT_UNKNOWN	= 0
NT_TASK		= 1
NT_INTERRUPT	= 2
NT_DEVICE	= 3
NT_MSGPORT	= 4
NT_MESSAGE	= 5
NT_RESOURCE	= 8
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
MEMF_REVERSE	= $40000			;AllocMem from top of free pool

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
RT_INIT		= $16			;Resident.rt_Init offset (dos.library init fn)
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

;--- SCSI device command interface -------------------------

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

; Tuple codes
CISTPL_DEVICE	= $01
CISTPL_CFTABLE	= $1b
CISTPL_CONFIG	= $1a
CISTPL_FUNCID	= $21

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
;CFD_Unit	= 52			-> cfd_pub.i (shared with compactflash.automount)
; CFD extension for autoboot cooperation with ptable.library. Always
; present so the build is autoboot-capable in ROM without any
; compile-time toggle. When ptable.library is not loaded the slot
; stays zero (CFD allocation is MEMF_CLEAR).
;
;   offset  size  field
;     56     1    CFD_BootDone   one-shot re-entry guard set by the
;                                RTF_COLDSTART stub before its scan opens
;                                the device (the open spawns the MountAgent,
;                                which reads this flag)
;     57     1    CFD_DosReady   set by the RTF_AFTERDOS hook when
;                                System-Startup reports DOS functional
;                                (step 13, see NDK system-startup.doc);
;                                the MountAgent defers all work until set
;CFD_BootDone	= 56			-> cfd_pub.i (shared with compactflash.automount)
;CFD_DosReady	= 57			-> cfd_pub.i (shared with compactflash.automount)
CFD_Sizeof	= 60

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
				;  bit 1: unused, was "skip PCMCIA signature"
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

;--- Runtime-bound I/O handlers (see _BindIOHandlers header for dispatch flow) ---
; Set once probing converges and rebind on any later mode change.
; Called from _rb_block / _wb_block with:
;   d0 = byte count, a2 = buffer, a3 = CFU
; Handler returns via rts with a2 advanced. All data registers may
; be clobbered. Points at one of pi_mode0..pi_mode4 / po_mode0..po_mode4.
CFU_Pad966	= 966			;alignment padding (2 bytes)
CFU_ReadBlockFn	= 968			;bound read-block handler (longword)
CFU_WriteBlockFn = 972			;bound write-block handler (longword)

;--- Pre-baked I/O data-port pointer ---
; = CFU_IOPtr + 8. PIO I/O-space handlers (pi_mode0..3, po_mode0..3)
; load this directly instead of recomputing the +8 every call.
; Written alongside CFU_IOPtr at probe time.
CFU_DataPort	= 976			;PCMCIA I/O base + 8 (longword)

;--- DOS-time automount agent (per unit) ---
; A small Exec task spawned at unit startup. The unit task signals it
; on card insert/remove (after NotifyClients); the agent reconciles the
; partition.resource via ptable.library v2 (Scan/Mount/Unmount) outside
; the Forbid window that NotifyClients runs under.
;CFU_MountAgent	= 980			-> cfd_pub.i (shared with compactflash.automount)
;CFU_MountSig	= 984			-> cfd_pub.i (shared with compactflash.automount)
CFU_MountDone	= 988			;worker-done signal mask (agent's bit)

CFU_Sizeof	= 992


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
	dc.l	s_codeend		;EndSkip: end of this module (boot/automount
					;bringup lives in compactflash.automount)
	dc.b	RTF_AUTOINIT
	dc.b	FILE_VERSION
	dc.b	NT_DEVICE
	dc.b	PRI_CFD_DEVICE		;see ptable_pub.i for priority rationale
	dc.l	s_name
	dc.l	s_idstring
	dc.l	s_inittable

s_name:
	dc.b	"compactflash.device",0
	dc.b	"$VER: "
s_idstring:
	;Version string from Makefile-generated include
	VERSION_STRING
	dc.b	LF,0
	dc.b	"(c) Torsten Jager",0
CardName:
	dc.b	"card.resource",0
TimerName:
	dc.b	"timer.device",0

;--- Debug message strings (used when Flags = 8) ---
	ifd	DEBUG
dbg_version:
	dc.b	"[CFD] "
	VERSION_STRING
	dc.b	13,10,0
dbg_card_insert:
	dc.b	"[CFD] Card inserted",13,10,0
dbg_card_remove:
	dc.b	"[CFD] Card removed",13,10,0
dbg_id:
	dc.b	"[CFD] Identifying card...",13,10,0
dbg_id_ok:
	dc.b	"[CFD] Card identified OK",13,10,0
dbg_id_done_pre:
	dc.b	" ... done (",0
dbg_id_done_post:
	dc.b	")",13,10,0
dbg_id_ata:
	dc.b	"ATA",0
dbg_id_atapi:
	dc.b	"ATAPI",0
dbg_id_timeout:
	dc.b	"timeout",0

dbg_reset:
	dc.b	"[CFD] Reset",13,10,0
dbg_config:
	dc.b	"[CFD] Configuring HBA",13,10,0
dbg_voltage:
	dc.b	"[CFD] Setting voltage",13,10,0

dbg_rwtest:
	dc.b	"[CFD] RW test",13,10,0
dbg_transfer:
	dc.b	"[CFD] ..done, transfer mode: ",0
dbg_word:
	dc.b	"WORD",0
dbg_byte:
	dc.b	"BYTE",0
dbg_rwtest_nomode:
	dc.b	" (no working mode)",0

dbg_spinup:
	dc.b	"[CFD] Spinup",13,10,0
dbg_multimode:
	dc.b	"[CFD] Init multi mode",13,10,0
	ifd	GTIMING
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
dbg_notify_call:
	dc.b	"[CFD] ..client IS_Code=0x",0
dbg_notify_drop:
	dc.b	"[CFD] ..drop stale client at 0x",0
dbg_done:
	dc.b	"[CFD] ..done",13,10,0
dbg_ideerr:
	dc.b	"[CFD] IDE err=",0

dbg_id_get:
	dc.b	"[CFD] Getting IDE ID",0
dbg_id_garbage:
	dc.b	" ... FAILED (repeated pattern ",0
dbg_id_garbage_end:
	dc.b	")",13,10,0
dbg_id_mismatch:
	dc.b	" ... FAILED (data mismatch)",13,10,0
dbg_id_model:
	dc.b	"  Model: ",0
dbg_id_serial:
	dc.b	"  Serial: ",0
dbg_id_firmware:
	dc.b	"  FW: ",0
dbg_id_raw:
	dc.b	"[CFD] IDENTIFY (raw):",13,10,0
dbg_id_maxmulti:
	dc.b	"  Max Multi (W47): ",0
dbg_id_caps:
	dc.b	"  Capabilities (W49): ",0
dbg_id_multisect:
	dc.b	"  Multi Setting (W59): ",0
dbg_id_lba:
	dc.b	"  LBA Sectors (W60-61): ",0
dbg_id_dma:
	dc.b	"  DMA Modes (W63): ",0
dbg_id_pio:
	dc.b	"  PIO Modes (W64): ",0
dbg_id_udma:
	dc.b	"  UDMA Modes (W88): ",0

dbg_voltage5v:
	dc.b	"[CFD] Voltage: 5V",13,10,0

dbg_cis_scan:
	dc.b	"[CFD] CIS gate",13,10,0
dbg_cis_funcid:
	dc.b	"[CFD] ..FUNCID: 0x",0
dbg_cis_device:
	dc.b	"[CFD] ..DEVICE: type=0x",0
dbg_cis_device_speed:
	dc.b	" speed=",0
dbg_cis_device_size:
	dc.b	"ns size=0x",0
dbg_cis_gate_accept:
	dc.b	"[CFD] ..RESULT: accept",13,10,0
dbg_cis_gate_reject:
	dc.b	"[CFD] ..RESULT: reject -> ReleaseCard",13,10,0
dbg_cis_funcext_absent:
	dc.b	"[CFD] ..FUNCEXT: absent",13,10,0
dbg_cis_funcext_link:
	dc.b	"[CFD] ..FUNCEXT: link=0x",0
dbg_cis_funcext_type:
	dc.b	", type=0x",0
dbg_cis_funcext_iface:
	dc.b	", ifc=0x",0
dbg_cis_config:
	dc.b	"[CFD] ..CONFIG: addr=0x",0
dbg_cis_config_end:
	dc.b	13,10,0
dbg_cis_config_fallback:
	dc.b	"[CFD] ..CONFIG: default (0x200)",13,10,0

dbg_id_failed_release:
	dc.b	"[CFD] IDENTIFY failed -> ReleaseCard",13,10,0
dbg_idestatus:
	dc.b	"[CFD] IDE status=",0
dbg_multimax:
	dc.b	"[CFD] ..max multi: ",0
dbg_multiset:
	dc.b	"[CFD] ..set multi: ",0
dbg_multiok:
	dc.b	", OK",13,10,0
dbg_multifail:
	dc.b	", FAILED",13,10,0
dbg_multinosup:
	dc.b	"[CFD] ..not supported",13,10,0
dbg_multirw:
	dc.b	"[CFD] ..done, multi RW: ",0
dbg_multi_ovr_ok:
	dc.b	"[CFD] ..override test: OK",13,10,0
dbg_multi_ovr_fail:
	dc.b	"[CFD] ..override test: failed",13,10,0
dbg_multi_ovr_skip:
	dc.b	"[CFD] ..override test: skipped",13,10,0
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
	move.l	a4,d0			;card.resource opened lazily in NewUnit
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

	bsr	NewUnit
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

	bsr	Expunge			;or not
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
	move.l	CFD_Unit(a4),a1
	bsr	KillUnit
	tst.l	d0
	bne.s	ex_defer		;KillUnit failed: defer expunge

	CALLEXEC Forbid
	move.l	a4,a1
	CALLSAME Remove
	CALLSAME Permit
	move.l	CFD_SegList(a4),d2
	moveq.l	#0,d0
	move.w	LIB_NegSize(a4),d0
	move.l	a4,a1
	sub.l	d0,a1
	add.w	LIB_PosSize(a4),d0
	CALLEXEC FreeMem
	move.l	d2,d0
	bra.s	ex_end
ex_defer:
	or.b	#LIBF_DELEXP,LIB_Flags(a4)
	moveq.l	#0,d0			;exec retries via Close once OpenCnt drops
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
	bsr	FunctionIndex
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
	add.l	d0,d0			;*2 via add.l (faster than lsl.l #1)
	lea	bio_tab(pc),a6
	add.w	(a6,d0.w),a6		;d0 high bits cleared above, .w is 68000-safe
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

	moveq.l	#36,d0
	lea	CardName(pc),a1
	CALLEXEC OpenResource
	move.l	d0,CFD_CardBase(a4)
	beq.w	nu_freeunit		;card.resource unavailable

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
	sub.l	d3,a1			;a2 was &Task, alloc base = a2 - d3 (stack)
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
	beq.s	ku_ok			;NULL: nothing to do = success

	move.l	a1,a3			;&Unit
	move.l	CFU_Device(a3),a4	;&Device
	moveq.l	#CFUF_TERM,d0
	and.w	CFU_Flags(a3),d0
	bne.s	ku_ok			;already terminated = success

	moveq.l	#-1,d0
	CALLEXEC AllocSignal
	move.l	d0,d2
	bmi.s	ku_fail			;signal pool exhausted -> defer

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
ku_ok:
	moveq.l	#0,d0			;success
	bra.s	ku_end
ku_fail:
	moveq.l	#-1,d0			;tell Expunge to defer
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
	UDIVMOD32
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
	clr.l	IO_Actual(a2)		;CMD_READ: high32 = 0 (32-bit only)
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
	UDIVMOD32
	move.l	d0,d1
	move.l	(sp)+,d0
	move.l	IO_Data(a2),a1
	jsr	(a6)
	move.l	d2,d1
	UMUL32
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
	ifd	ATAPI
	tst.w	CFU_PLength(a3)
	bgt.s	_sc_atapi
	endc

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
	bsr	_GetSense
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

	ifd	ATAPI
_sc_atapi:
	move.l	a2,a0
	bsr	_Packet
	bra.s	_sc_end
	endc

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
; SCSI TEST UNIT READY command - check if device is ready
;
; Input:
;   a2 = &SCSICmd structure
;   a3 = CFU pointer
;
; Output:
;   d0 = SCSI status
;        0x0000 = success (unit ready)
;        0x0202 = CHECK CONDITION (no disk or not ready)
;
; Notes:
;   - Checks if drive is present (CFU_DriveSize != 0)
;   - Returns success if disk is present and ready
;   - Returns CHECK CONDITION if no disk or drive size is zero
;
_TestUnitReady:
	moveq.l	#0,d0
	tst.l	CFU_DriveSize(a3)
	bne.s	_tur_end

	move.w	#$0202,d0
_tur_end:
	rts

;--- REQUEST SENSE -----------------------------------------
; SCSI REQUEST SENSE command - return sense data
;
; Input:
;   a2 = &SCSICmd structure
;   a3 = CFU pointer
;
; Output:
;   d0 = SCSI status (0 = success)
;   SCSI_Actual = bytes of sense data returned
;   SCSI_Data = sense data buffer (filled by _GetSense)
;
; Notes:
;   - Returns sense data for previous CHECK CONDITION
;   - Uses CFU_SCSIState to determine sense key
;   - Calls _GetSense to format sense data
;   - Always returns success (sense data indicates error)
;
_RequestSense:
	move.w	CFU_SCSIState(a3),d0
	move.l	SCSI_Length(a2),d1
	move.l	(a2),a1			;SCSI_Data
	bsr	_GetSense
	move.l	d0,SCSI_Actual(a2)
	moveq.l	#0,d0
	rts

;--- INQUIRY -----------------------------------------------
; SCSI INQUIRY command - return device identification
;
; Input:
;   a2 = &SCSICmd structure
;   a3 = CFU pointer
;
; Output:
;   d0 = SCSI status (0 = success)
;   SCSI_Actual = bytes transferred
;   SCSI_Data = INQUIRY response data (if buffer provided)
;
; Notes:
;   - Builds SCSI INQUIRY response from IDE IDENTIFY data
;   - Extracts vendor, product, and revision from CFU_ConfigBlock
;   - Returns up to 96 bytes of INQUIRY data
;   - Device type: 0x00 (direct access, disk)
;   - Qualifier: 0x20 (device connected, LUN 0)
;   - Flags: removable, SCSI-2, auto-sense supported
;   - Pads vendor name if needed
;
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
	add.l	d0,d0			;*2 via add.l (faster than lsl.l #1)
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
	add.l	d0,d0			;*2 via add.l (faster than lsl.l #1)
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
	move.l	(a0),d0
	move.l	d0,CFU_IOPtr(a3)
	addq.l	#8,d0
	move.l	d0,CFU_DataPort(a3)	;pre-baked +8 for PIO I/O handlers

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

	bsr	_CfdFirst		;the HACK
	bsr	_SocketOn		;another HACK

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

	bsr	_SpawnMountAgent	;DOS-time automount worker (best-effort)

;- - card already inserted? - - - - - - - - - - - - - - - -
;   Poll CCDET for up to 1s on cold boot: GAYLE VCC and the
;   PCMCIA card-detect line may not be electrically stable
;   the moment OwnCard returns.

	moveq.l	#25,d2			;25 x 40ms = 1s
_t_ccdet_poll:
	lea	CFU_CardHandle(a3),a2
	move.l	a2,a1
	CALLCARD ReadCardStatus
	and.b	#CARD_STATUSF_CCDET,d0
	bne.s	_t_have_ccdet
	bsr	Wait40
	subq.w	#1,d2
	bne.s	_t_ccdet_poll
	bra.w	_t_check		;no card after 1s
_t_have_ccdet:

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
	bne.w	_t_identify		;card inserted (insert IRQ fired)

;-- Cold-boot fallback: the insert IRQ may not have arrived
;   inside the 1s arbitration window. Re-read CCDET; if the
;   card is still physically present, force identify anyway.
;   _t_identify itself re-reads CCDET and bails to _t_ibreak
;   if the slot is empty, so this is safe.
	lea	CFU_CardHandle(a3),a2
	move.l	a2,a1
	CALLCARD ReadCardStatus
	and.b	#CARD_STATUSF_CCDET,d0
	bne.w	_t_identify		;still present -> identify
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

	ifd	ATAPI
	bsr	ATAPIPoll		;check for removable media
	endc

	bclr	#1,CFU_EventFlags(a3)
	bne.s	_t_identify		;card inserted

	bclr	#2,CFU_EventFlags(a3)
	bne.w	_t_iswap		;media change
	bra.s	_t_wait
_t_do:
	move.l	d0,a2			;&IORequest
	clr.b	CFU_IOErr(a3)
	bsr	FunctionIndex
	add.l	d0,d0			;*2 via add.l (faster than lsl.l #1)
	lea	bio_tab(pc),a6
	add.w	(a6,d0.w),a6		;d0 high bits cleared in FunctionIndex, .w is 68000-safe
	jsr	(a6)			;handle and..
	move.b	d0,IO_Error(a2)
	move.l	a2,a1
	CALLEXEC ReplyMsg		;..reply request
	bra.s	_t_check

;- - examine and register new card  - - - - - - - - - - - -

;===========================================================
; Card-insert accept/reject flow.
;
; === the CIS gate (DEVICE / FUNCID / FUNCEXT) decides
;     accept/reject using CIS attribute-memory reads ONLY
;     before the gate accepts. ===
;
;            +------------------+
;            | Reset, Voltage   |
;            +------------------+
;                    |
;                    v
;            +------------------+
;            | DEVICE type ?    |---- other non-zero type
;            | (10x retry on    |     ------------------> REJECT
;            |  NULL/absent)    |
;            +------------------+
;             |              |
;     0x0D /  |              | NULL/absent
;     0x05    |              v
;     skips   |   +------------------+
;     FUNCID  |   | FUNCID == 0x04 ? |---- no
;             |   +------------------+     ------------> REJECT
;             |              | yes
;             v              v
;            +------------------+
;            | FUNCEXT IDE ?    |---- absent / malformed / non-IDE
;            | (10x retry)      |     ------------> REJECT
;            +------------------+              (..RESULT: reject
;                    | yes                       -> ReleaseCard,
;                    v                            no IDE register
;             ..RESULT: accept                    touch)
;
;     ===== below this line: IDE / CCR registers modified =====
;
;                    |
;                    v
;            +------------------+
;            | CIS CONFIG addr  |   (10x retry,
;            | + HBA setup      |    fallback 0x200;
;            |                  |    writes CCR: Socket+Copy,
;            |                  |    IRQ mode, transfer speed)
;            +------------------+
;                    |
;                    v
;            +------------------+
;            | RW test          |
;            +------------------+
;                    |
;                    v
;            +------------------+
;            | IDENTIFY DEVICE  |
;            +------------------+
;                    |
;                    v
;             d0 = 1 ATA -----> ACCEPT  (NotifyClients)
;             d0 = 0 timeout -> _t_identify_failed (ReleaseCard)
;             d0 = 2 ATAPI ---> _t_iatapi          (+atapi build)
;                            -> _t_identify_failed (-atapi build,
;                                                   handler not in)
;
; The ATAPI build flag (default 0) compiles in or out the
; ATAPI handler at _t_iatapi. -atapi releases ATAPI cards
; classified by IDENTIFY so a dedicated ATAPI driver can
; claim them; +atapi routes ATAPI cards through the handler.
;===========================================================

_t_identify:
	DBGMSG	dbg_version
	DBGMSG	dbg_card_insert
	clr.w	CFU_CardReady(a3)
	lea	CFU_CardHandle(a3),a2
	move.l	a2,a1
	CALLCARD ReadCardStatus
	and.b	#CARD_STATUSF_CCDET,d0
	beq.w	_t_ibreak		;false alert

	DBGMSG	dbg_id
	clr.b	CFU_ActiveHacks(a3)
	clr.l	CFU_ReadErrors(a3)
	clr.l	CFU_WriteErrors(a3)
	clr.l	CFU_OKInts(a3)
	clr.l	CFU_FastInts(a3)
	clr.l	CFU_LostInts(a3)
	lea	CFU_TimeReq(a3),a1
	CALLEXEC WaitIO
	or.b	#$20,CFU_EventFlags(a3)	;Interrupt OFF
	bsr	Wait40			;wait 100ms for stable 5V
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

	bsr	Wait40			;..or go on waiting
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.w	_t_ibreak

	move.l	a2,a1
	CALLCARD ReadCardStatus
	and.b	#CARD_STATUSF_BSY,d0
	bne.s	_t_i1			;card ready after resetting..
_t_i2:
	DBGMSG	dbg_config
	bsr	ConfigureHBA
	DBGMSG	dbg_done
	and.b	#$df,CFU_EventFlags(a3)	;Interrupt ON
	moveq.l	#600>>3,d1
	lsl.l	#3,d1
	move.l	d1,CFU_DTSpeed(a3)	;600ns = PIO 0

	DBGMSG	dbg_voltage
	moveq.l	#CARD_VOLTAGE_5V,d0
	move.l	a2,a1
	CALLCARD CardProgramVoltage
	DBGMSG	dbg_voltage5v

	; CIS gate report
	DBGMSG	dbg_cis_scan

	; Read CISTPL_DEVICE. On cold boot the card sometimes hasn't
	; finished populating its attribute memory yet and returns an
	; all-zero "NULL/hole" tuple (type=0x00). Retry up to 10 times
	; (~400ms) before giving up and falling through to FUNCID.
	moveq.l	#10,d2
_t_dev_retry:
	lea	CFU_ConfigBlock(a3),a0
	lea	CFU_CardHandle(a3),a1
	moveq.l	#CISTPL_DEVICE,d1
	moveq.l	#127,d0
	CALLCARD CopyTuple
	tst.w	d0
	beq.w	_t_devtuple_skip	;tuple read failed -> FUNCID
	lea	CFU_ConfigBlock(a3),a0
	lea	CFU_DTSize(a3),a1
	CALLCARD DeviceTuple
	tst.b	CFU_DTType(a3)
	bne.s	_t_dev_have		;real type seen -> stop retrying
	bsr	Wait40
	subq.w	#1,d2
	bne.s	_t_dev_retry
_t_dev_have:
	; DeviceTuple fills CFU_DTType/CFU_DTSpeed/CFU_DTSize.
	; We use CFU_DTSpeed later for CardAccessSpeed (timing setup).
	ifd	DEBUG
	; CFU_DTType(a3) values (CISTPL_DEVICE "device type" nibble):
	;  0x0 = NULL (no device / hole)
	;  0x1 = ROM
	;  0x2 = OTPROM (one-time programmable ROM)
	;  0x3 = EPROM
	;  0x4 = EEPROM
	;  0x5 = FLASH
	;  0x6 = SRAM
	;  0x7 = DRAM
	;  0xD = FUNCSPEC (function-specific memory)
	;  0xE = EXTEND (extended device type follows)
	; Note: CFcards show 0xD and 0x5.
	DBGMSG	dbg_cis_device
	moveq.l	#0,d0
	move.b	CFU_DTType(a3),d0
	bsr	_DebugHexByte
	DBGMSG	dbg_cis_device_speed
	move.l	CFU_DTSpeed(a3),d0
	bsr	_DebugDecimal32
	DBGMSG	dbg_cis_device_size
	move.l	CFU_DTSize(a3),d0
	bsr	_DebugHex
	bsr	_DebugNewline
	endc

	; Accept only whitelisted CISTPL_DEVICE types expected to behave
	; like ATA devices: 0x0D (FUNCSPEC) and 0x05 (FLASH).
	; Only if CISTPL_DEVICE is unavailable do we fall back to FUNCID.
	cmp.b	#$0d,CFU_DTType(a3)	;FUNCSPEC
	beq.s	_t_cis_gate_accept
	cmp.b	#$05,CFU_DTType(a3)	;FLASH
	beq.s	_t_cis_gate_accept
	tst.b	CFU_DTType(a3)
	beq.w	_t_devtuple_skip	;NULL tuple -> consult FUNCID
	bra.w	_t_cis_reject		;non-zero, non-whitelisted -> reject
_t_devtuple_skip:

	; Fallback CIS gate by FUNCID if CISTPL_DEVICE is unavailable:
	; - if FUNCID == 0x04 (Fixed Disk) => accept
	; - otherwise (missing / unreadable / non-disk) => reject
	lea	CFU_ConfigBlock(a3),a0
	lea	CFU_CardHandle(a3),a1
	moveq.l	#CISTPL_FUNCID,d1
	moveq.l	#127,d0
	CALLCARD CopyTuple
	tst.w	d0
	beq.w	_t_cis_reject		;missing/unreadable => reject

	lea	CFU_ConfigBlock(a3),a0
	addq.l	#1,a0			;-> link
	cmp.b	#1,(a0)+		;need at least 1 byte of data
	bcs.w	_t_cis_reject		;short tuple => reject
	moveq.l	#0,d2
	move.b	(a0),d2			;FUNCID
	ifd	DEBUG
	DBGMSG	dbg_cis_funcid
	move.l	d2,d0
	bsr	_DebugHexByte
	bsr	_DebugNewline
	endc
	cmp.b	#4,d2			;0x04 = Fixed Disk
	beq.s	_t_cis_funcid_ok
	bra.w	_t_cis_reject

_t_cis_funcid_ok:
_t_cis_gate_accept:
	;-- Require CISTPL_FUNCEXT to declare IDE ----------------------
	; After DEVICE/FUNCID tentatively accept, demand a well-formed
	; FUNCEXT (0x22) with TPLFE_TYPE=1 (Disk Interface) and
	; Interface=1 (IDE). Absent, malformed, or non-IDE rejects
	; the card before IDENTIFY. Retry the read up to 10 times to
	; tolerate CIS attribute-memory read instability on hardware
	; like A1200 + ACA1234 (mirrors the CISTPL_CONFIG retry).
	moveq.l	#10,d6			;FUNCEXT retry counter
_t_cis_funcext_retry:
	lea	CFU_ConfigBlock(a3),a0
	lea	CFU_CardHandle(a3),a1
	moveq.l	#$22,d1			;CISTPL_FUNCEXT
	moveq.l	#127,d0
	CALLCARD CopyTuple
	tst.w	d0
	beq.w	_t_cis_funcext_again	;absent -> retry

	;-- Read link, TPLFE_TYPE, Interface into d2/d3/d4 (default 0).
	lea	CFU_ConfigBlock(a3),a0
	addq.l	#1,a0			;-> link byte
	moveq.l	#0,d2
	move.b	(a0)+,d2		;d2 = link
	moveq.l	#0,d3
	moveq.l	#0,d4
	tst.b	d2
	beq.s	_t_cis_funcext_dump	;link=0: no data bytes
	move.b	(a0)+,d3		;d3 = TPLFE_TYPE
	cmp.b	#2,d2
	bcs.s	_t_cis_funcext_dump	;link=1: no Interface byte
	move.b	(a0),d4			;d4 = Interface

_t_cis_funcext_dump:
	ifd	DEBUG
	DBGMSG	dbg_cis_funcext_link
	move.l	d2,d0
	bsr	_DebugHexByte
	DBGMSG	dbg_cis_funcext_type
	move.l	d3,d0
	bsr	_DebugHexByte
	DBGMSG	dbg_cis_funcext_iface
	move.l	d4,d0
	bsr	_DebugHexByte
	bsr	_DebugNewline
	endc

	ifd	FUNCEXT_VOTING
	;-- Voting: enforce link >= 2, type == 1, iface == 1 (IDE).
	cmp.b	#2,d2
	bcs.w	_t_cis_funcext_again
	cmp.b	#1,d3
	bne.w	_t_cis_funcext_again
	cmp.b	#1,d4
	bne.w	_t_cis_funcext_again
	endc

_t_cis_funcext_accept:
	bra.w	_t_cis_gate_end

_t_cis_funcext_again:
	subq.w	#1,d6
	beq.s	_t_cis_funcext_giveup
	tst.b	A_Pb			;E-clock tick (~1us) between retries
	nop
	bra.w	_t_cis_funcext_retry

_t_cis_funcext_giveup:
	ifd	DEBUG
	DBGMSG	dbg_cis_funcext_absent
	endc
	ifd	FUNCEXT_VOTING
	bra.w	_t_cis_reject
	else
	bra.s	_t_cis_funcext_accept
	endc

_t_cis_reject:
	DBGMSG	dbg_cis_gate_reject
	bra.w	_t_ibreak

_t_cis_gate_end:
	DBGMSG	dbg_cis_gate_accept

	; Try to locate CISTPL_CONFIG tuple for config register address.
	; On cold boot the CIS attribute memory may parse OK structurally
	; but every byte still reads as zero, yielding addr=0. Retry the
	; read up to 10 times before falling back to 0x200.
	; Sets CFU_ConfigAddr and leaves a2 pointing at the CCR base.
	moveq.l	#10,d3
_t_cfg_retry:
	moveq.l	#CISTPL_CONFIG,d1
	lea	CFU_ConfigBlock(a3),a0
	lea	CFU_CardHandle(a3),a1
	moveq.l	#127,d0
	CALLCARD CopyTuple
	tst.w	d0
	beq.s	_t_cfg_again		;CopyTuple failed -> retry

	; Parse CopyTuple buffer: [0]=code [1]=link [2..]=data
	lea	CFU_ConfigBlock(a3),a0
	addq.l	#1,a0			;skip tuple code
	cmp.b	#4,(a0)+		;check tuple data length
	bcs.s	_t_cfg_again		;invalid length -> retry

	moveq.l	#3,d0
	and.b	(a0)+,d0		;address length (1-4 bytes) - 1
	addq.l	#1,a0			;skip reserved byte
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
	bcc.s	_t_cfg_check_addr

	lsr.l	#8,d2
	bra.s	_t_saddr
_t_cfg_check_addr:
	tst.l	d2
	bne.s	_t_gotconfig		;non-zero address -> accept
_t_cfg_again:
	subq.w	#1,d3
	beq.s	_t_config_fallback	;retries exhausted -> fallback
	bsr	Wait1
	bra.s	_t_cfg_retry
_t_gotconfig:
	ifd	DEBUG
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_t_gotconfig_skip
	DBGMSG	dbg_cis_config
	move.l	d2,d0			;output config address
	bsr	_DebugHex
	DBGMSG	dbg_cis_config_end
_t_gotconfig_skip:
	endc
	bra.s	_t_faddr
_t_config_fallback:
	; Fallback to standard config address 0x200
	; This is the standard PCMCIA configuration register address
	; Used when CopyTuple fails or CISTPL_CONFIG is invalid
	DBGMSG	dbg_cis_config_fallback
	moveq.l	#$200>>3,d2
	lsl.l	#3,d2
	or.w	#1<<8,CFU_ActiveHacks(a3)	;mark as fallback config address
_t_faddr:
	cmp.l	#$00020000,d2
	bcc.w	_t_ibreak		;address out of range

	move.l	CFU_AttrPtr(a3),a2
	add.l	d2,a2
	move.l	a2,CFU_ConfigAddr(a3)

	btst	#2,CFU_OpenFlags+1(a3)
	beq.s	_t_i4

	move.b	#$80,(a2)		;soft reset ON..
	bsr	Wait40
	move.b	#0,(a2)			;..and OFF
	bsr	Wait40
_t_i4:
	move.b	#0,6(a2)		;Socket & Copy #0
	nop
	move.b	#$0f,4(a2)		;acknowledge status change
	nop
	move.b	#0,2(a2)		;turn on, 16bit, ...
	nop
	move.b	#$41,(a2)		;level mode IRQ and I/O mode 16 bytes
	bsr	Wait40			;wait for settle
	move.l	CFU_IOPtr(a3),CFU_IDEAddr(a3)
	lea	CFU_CardHandle(a3),a2
	move.l	CFU_DTSpeed(a3),d0
	move.l	a2,a1
	CALLCARD CardAccessSpeed
	bsr	ConfigureHBA
	and.b	#~4,CFU_EventFlags(a3)	;avoid double identify
_t_iswap:
	lea	CFU_CardHandle(a3),a2
	move.l	a2,a1
	CALLCARD ReadCardStatus
	and.b	#CARD_STATUSF_CCDET,d0
	beq.w	_t_ibreak

	bsr	BusyWait
	move.l	d0,d1			;save status
	and.b	#$a0,d0			;BSY, DWF
	beq.s	_t_itest

	ifd	DEBUG
	move.l	d1,d0
	bsr	_DebugIDEStatus		;show status when error
	endc
	btst	#0,CFU_ActiveHacks(a3)
	bne.w	_t_ibreak
	bra.w	_t_inodisk		;ATA removable media???

_t_itest:
	DBGMSG	dbg_rwtest
	bsr	RWTest			;find a working transfer mode
	ifd	DEBUG
	bsr	_DebugTransferMode	;d0 = RWTest result, show which transfer mode
	endc
	bsr	_GetIDEID		;read ATA config block; logs "Getting IDE ID ... done (type)"
	move.l	d0,d2
	tst.l	d2
	beq.w	_t_identify_failed	;IDENTIFY failed -> release card (avoid blocking others)

	; Skip CIS-tuple validation: IDENTIFY-based identification is
	; sufficient for ATA CompactFlash and avoids unreliable
	; CopyTuple behavior on some adapters.

	; Validate IDENTIFY data:
	;   d0 = 1 -> ATA, continue with CompactFlash signature check
	;   d0 = 2 -> ATAPI, route to the _t_iatapi handler in +atapi
	;             builds; release the card otherwise (should already
	;             have been caught by the pre-IDENTIFY task-file
	;             signature gate, this is the residual safety net).
	;   d0 = other -> reject (unknown response shape)
	cmp.l	#2,d0
	ifd	ATAPI
	beq.w	_t_iatapi
	else
	beq.w	_t_identify_failed	;ATAPI -> release (handler not compiled in)
	endc
	cmp.l	#1,d0
	bne.w	_t_inodisk		;unknown response shape, reject

	; Optional: Verify CompactFlash signature in IDENTIFY word 0
	; Bits 15:12 = 0x848x indicates CompactFlash card
	move.w	CFU_ConfigBlock(a3),d0	;word 0: General configuration
	and.w	#$fff0,d0		;mask bits 15:12
	cmp.w	#$8480,d0		;CompactFlash signature?
	beq.s	_t_icf_ok		;yes, CompactFlash card

	; Not CompactFlash signature, but check if it's still ATA device
	; Bit 15 = 0 means ATA device (1 = ATAPI)
	btst	#15,CFU_ConfigBlock(a3)
	ifd	ATAPI
	bne.w	_t_iatapi		;ATAPI variant -> ATAPI handler
	else
	bne.w	_t_identify_failed	;ATAPI variant -> release the card
	endc

_t_icf_ok:
	ifd	DEBUG
	bsr	_DebugCardInfo		;show card details
	bsr	_DebugIdentifyFields	;show labeled IDENTIFY fields
	bsr	_DebugHexDump		;dump full IDENTIFY structure
	endc
	
	btst	#6,CFU_ConfigBlock+167(a3)
	beq.s	_t_i6

	DBGMSG	dbg_spinup
	bsr	_SpinUp			;try waking up the drive..
	DBGMSG	dbg_done
	moveq.l	#0,d2
_t_i6:
	btst	#2,CFU_ConfigBlock+1(a3)
	beq.s	_t_i7

	moveq.l	#0,d0
	moveq.l	#1,d1
	lea	CFU_ConfigBlock(a3),a1
	bsr	_ReadBlocks		;..one way or the other..
	moveq.l	#0,d2
_t_i7:
	tst.l	d2
	bne.s	_t_i8

	bsr	_GetIDEID		;..then ask again
	move.l	d0,d2
	beq.s	_t_inodisk
_t_i8:
	subq.w	#1,d2
	ifd	ATAPI
	bne.s	_t_iatapi
	else
	bne.w	_t_identify_failed	;ATAPI / unknown -> release the card
	endc

	DBGMSG	dbg_multimode
	bsr	_InitMultipleMode
	bsr	_OptimizePIOSpeed	;set faster PIO if flag set
	bra.s	_t_iok
	ifd	ATAPI
_t_iatapi:
	bsr	ATAPIPoll		;start monitoring media removals
	bra.s	_t_iok
	endc
_t_inodisk:
	clr.l	CFU_DriveSize(a3)
_t_iok:
	DBGMSG	dbg_id_ok
	DBGMSG	dbg_notify
	bsr	NotifyClients
	bsr	_MountAgentSignal	;wake automount agent (insert/no-disk)
	bra.w	_t_check

_t_identify_failed:
	DBGMSG	dbg_id_failed_release
	bra.w	_t_ibreak

_t_ibreak:
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
	clr.l	CFU_ReadBlockFn(a3)	;unbind hot-path handlers so a stray
	clr.l	CFU_WriteBlockFn(a3)	; IO that slips past the state machine
					; hits the NULL-guard in _rb_try/_wb_try
	;Clear 512-byte IDENTIFY buffer (CFU_ConfigBlock)
	lea	CFU_ConfigBlock(a3),a0
	moveq.l	#512/4-1,d0		;128 longwords - 1
.clr_loop:
	clr.l	(a0)+
	dbf	d0,.clr_loop
	bsr	NotifyClients
	bsr	_MountAgentSignal	;wake automount agent (teardown)
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

	LOG2
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

;===========================================================
; DOS-time automount agent
;
; Spawned per unit by _SpawnMountAgent at unit startup. Waits on
; CFU_MountSig; on each wake (the unit task signals it after
; NotifyClients on insert/remove) it reconciles partition.resource
; via ptable.library v2:
;     card present -> ScanPartitions + MountPartitions
;     card absent  -> UnmountPartitions
; Both LVOs are idempotent, so a coalesced or stale wake is harmless.
;
; The agent is a bare Exec Task. The worker process reads ENV:ptable.prefs
; (AUTOMOUNT / FLAGS / UNMOUNT) and applies it.
;===========================================================

;-- _MountAgentSignal: wake the agent if it is up. a3=&Unit, a4=&Dev.
_MountAgentSignal:
	movem.l	d0/d1/a1/a6,-(sp)
	move.l	CFU_MountSig(a3),d0
	beq.s	_masig_done
	move.l	CFU_MountAgent(a3),d1
	beq.s	_masig_done
	move.l	d1,a1
	CALLEXEC Signal
_masig_done:
	movem.l	(sp)+,d0/d1/a1/a6
	rts

;-- _SpawnMountAgent: create the agent task (best-effort). a3=&Unit,
;   a4=&Dev. Mirrors NewUnit's task allocation (MemList + stack/Task +
;   AddTask), minus the startup handshake. On failure CFU_MountAgent
;   stays 0 and the device simply has no automount.
MA_STACK	= 4096

; Settle (dos ticks, 50/s) the mount worker waits after scanning before it
; mounts, so a device-dostype handler that just opened us (and triggered this
; pass) can claim its partition via RegisterPartition first - the worker then
; reuses it instead of double-mounting.
MOUNT_SETTLE_TICKS = 50

_SpawnMountAgent:
	movem.l	d2-d3/a2,-(sp)
	moveq.l	#MA_STACK>>8,d3
	lsl.l	#8,d3			;d3 = agent stack size
	moveq.l	#24,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	CALLEXEC AllocMem
	move.l	d0,d2			;&MemList
	beq.w	_sma_out
	move.l	d0,a1
	move.w	#1,14(a1)		;ml_NumEntries = 1
	moveq.l	#TC_Sizeof,d0
	add.l	d3,d0
	move.l	d0,20(a1)		;me_Length = Task + stack
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	CALLEXEC AllocMem
	move.l	d2,a1
	move.l	d0,16(a1)		;me_Addr = stack base
	beq.w	_sma_freeml
	move.l	d0,a2			;&stack
	add.l	d3,a2			;&Task (top of stack)
	lea	MAgentName(pc),a0
	move.l	a0,LN_Name(a2)
	move.b	#NT_TASK,LN_Type(a2)
	move.l	a2,TC_SPUpper(a2)
	move.l	d0,TC_SPLower(a2)
	move.l	a2,TC_SPReg(a2)		;initial SP = top of stack
	lea	TC_MemEntry(a2),a0
	INITLIST a0
	lea	TC_MemEntry(a2),a0
	move.l	d2,a1
	CALLEXEC AddHead		;MemList -> task (RemTask frees it)
	move.l	a3,TC_UserData(a2)	;&Unit
	move.l	a2,CFU_MountAgent(a3)
	move.l	a3,-(sp)		;preserve &Unit across AddTask
	move.l	a2,a1
	lea	_MountAgentEntry(pc),a2
	sub.l	a3,a3			;finalPC = 0
	CALLEXEC AddTask
	move.l	(sp)+,a3
	DBGMSG	dbg_ma_spawn
	bra.s	_sma_out
_sma_freeml:
	moveq.l	#24,d0
	move.l	d2,a1
	CALLEXEC FreeMem
_sma_out:
	movem.l	(sp)+,d2-d3/a2
	rts

;-- dos.library pieces for the worker-process launch. AddDosNode with
;   ADNF_STARTPROC, LockDosList/RemDosEntry and ACTION_DIE are process-
;   only DOS calls; running them from the bare agent task made dos read
;   Process fields past the end of the Task struct (first hardware test:
;   garbage-pointer storm + guru 8000 0003). The agent therefore only
;   catches events; the DOS work runs in a short-lived worker process.
;   CreateNewProc is documented callable from a task (dos autodoc) when
;   nothing needs inheriting; every inheritable tag is given explicitly.
DOS_CreateNewProc = -498

NP_Dummy	= $80000000+1000
NP_Seglist	= NP_Dummy+1
NP_FreeSeglist	= NP_Dummy+2
NP_Input	= NP_Dummy+4
NP_Output	= NP_Dummy+5
NP_CloseInput	= NP_Dummy+6
NP_CloseOutput	= NP_Dummy+7
NP_CurrentDir	= NP_Dummy+10
NP_StackSize	= NP_Dummy+11
NP_Name		= NP_Dummy+12
NP_Priority	= NP_Dummy+13
NP_WindowPtr	= NP_Dummy+15
NP_CopyVars	= NP_Dummy+17

MW_TAGBYTES	= 26*4			;13 TagItem pairs incl TAG_DONE

;-- _MountAgentEntry: the agent task body.
;   a3=&Unit, a4=&Dev, d5=wake mask, d4=done mask, d7=dos base.
;   Pure event catcher: waits for the unit task's Signal, makes sure
;   dos.library is up, then runs one CF.MountWork process and waits for
;   its done-Signal (serialises workers; coalesced events just rerun).
_MountAgentEntry:
	move.l	(_AbsExecBase).w,a6
	sub.l	a1,a1
	jsr	FindTask(a6)
	move.l	d0,a0
	move.l	TC_UserData(a0),a3	;&Unit
	move.l	CFU_Device(a3),a4	;&Dev (for CALLEXEC)
	moveq.l	#0,d4
	moveq.l	#0,d5
	moveq.l	#0,d7
;-- allocate the wake + worker-done signals in this task
	moveq.l	#-1,d0
	CALLEXEC AllocSignal
	cmp.b	#-1,d0
	beq.w	_ma_die
	bset	d0,d5			;d5 = wake mask
	moveq.l	#-1,d0
	CALLEXEC AllocSignal
	cmp.b	#-1,d0
	beq.w	_ma_die
	bset	d0,d4			;d4 = done mask
	move.l	d4,CFU_MountDone(a3)
	move.l	d5,CFU_MountSig(a3)	;publish last: signals valid now

;-- Disk-loaded driver: CFD_BootDone == 0 means the RTF_COLDSTART stub never
;   ran, so DOS is up already (the agent is spawned by the device open the
;   RTF_AFTERDOS hook does). Mark DOS ready here. On a ROM boot the stub sets
;   CFD_BootDone before its scan opens the device, so this branch is not taken
;   pre-DOS and the AFTERDOS gate stays in charge.
	tst.b	CFD_BootDone(a4)
	bne.s	_ma_loop
	move.b	#1,CFD_DosReady(a4)
;-- file-based load: no AFTERDOS hook to kick us, and the unit task's
;   startup card-detect signalled before our wake signal existed (lost).
;   Self-signal so the first loop reconciles a card already in the slot.
	bsr	_MountAgentSignal

_ma_loop:
	move.l	d5,d0
	CALLEXEC Wait
	ifd	DEBUG
	move.l	CFU_DriveSize(a3),d0
	bne.s	_ma_wk_in
	DBGMSG	dbg_ma_wake_out
	bra.s	_ma_wk_done
_ma_wk_in:
	DBGMSG	dbg_ma_wake_in
_ma_wk_done:
	endc
;-- Defer everything until System-Startup reports DOS functional (the
;   RTF_AFTERDOS hook sets CFD_DosReady and re-signals us, so deferred
;   events are reprocessed). The agent must never call dos.library
;   while System-Startup is still building it: the first hardware test
;   raced it (CreateNewProc into a half-built DOS, wild jump to PC=8).
	tst.b	CFD_DosReady(a4)
	beq.w	_ma_loop
	bsr	_ma_dos_open		;d7 = DOSBase (opened once, kept)
	DBGMSG	dbg_ma_dos
	tst.l	d7
	beq.w	_ma_loop		;cannot happen post-AFTERDOS; be safe
;-- launch the worker process (tag list built on the stack; the seglist
;   BPTR must be computed at runtime, so no static table)
	moveq.l	#0,d1
	move.l	d1,-(sp)		;TAG_DONE data (unread)
	move.l	d1,-(sp)		;TAG_DONE
	move.l	d1,-(sp)		;NP_CopyVars = FALSE
	move.l	#NP_CopyVars,-(sp)
	moveq.l	#-1,d0
	move.l	d0,-(sp)		;NP_WindowPtr = -1 (no requesters)
	move.l	#NP_WindowPtr,-(sp)
	move.l	d1,-(sp)		;NP_CurrentDir = 0
	move.l	#NP_CurrentDir,-(sp)
	move.l	d1,-(sp)		;NP_CloseOutput = FALSE
	move.l	#NP_CloseOutput,-(sp)
	move.l	d1,-(sp)		;NP_CloseInput = FALSE
	move.l	#NP_CloseInput,-(sp)
	move.l	d1,-(sp)		;NP_Output = 0
	move.l	#NP_Output,-(sp)
	move.l	d1,-(sp)		;NP_Input = 0
	move.l	#NP_Input,-(sp)
	move.l	#8192,-(sp)		;NP_StackSize
	move.l	#NP_StackSize,-(sp)
	move.l	d1,-(sp)		;NP_Priority = 0
	move.l	#NP_Priority,-(sp)
	pea	MWorkName(pc)		;NP_Name
	move.l	#NP_Name,-(sp)
	move.l	d1,-(sp)		;NP_FreeSeglist = FALSE (ROM seglist!)
	move.l	#NP_FreeSeglist,-(sp)
	lea	_ma_fakeseg(pc),a0
	move.l	a0,d0
	lsr.l	#2,d0
	move.l	d0,-(sp)		;NP_Seglist = BPTR(fake ROM seglist)
	move.l	#NP_Seglist,-(sp)
	move.l	sp,d1			;d1 = tag list
	move.l	d7,a6
	jsr	DOS_CreateNewProc(a6)
	lea	MW_TAGBYTES(sp),sp
	tst.l	d0
	bne.s	_ma_worker_ok
	DBGMSG	dbg_ma_run_fail
	bra.w	_ma_loop		;no memory: retry on next event
_ma_worker_ok:
;-- wait for the worker to finish (one at a time)
	move.l	d4,d0
	CALLEXEC Wait
	bra.w	_ma_loop

;-- _ma_dos_open: d7 = DOSBase, opened once and kept. Only called
;   after CFD_DosReady, so a single OpenLibrary suffices (no polling).
_ma_dos_open:
	movem.l	d0/a1,-(sp)
	tst.l	d7
	bne.s	_mado_done		;already open
	moveq.l	#36,d0
	lea	MAgentDosName(pc),a1
	CALLEXEC OpenLibrary
	move.l	d0,d7
_mado_done:
	movem.l	(sp)+,d0/a1
	rts

;-- _ma_die: setup failed; clear identity and remove self.
_ma_die:
	clr.l	CFU_MountSig(a3)
	clr.l	CFU_MountDone(a3)
	clr.l	CFU_MountAgent(a3)
	tst.l	d5
	beq.s	_ma_die_2
	move.l	d5,d0
	LOG2
	CALLEXEC FreeSignal
_ma_die_2:
	tst.l	d4
	beq.s	_ma_die_rt
	move.l	d4,d0
	LOG2
	CALLEXEC FreeSignal
_ma_die_rt:
	sub.l	a1,a1
	JMPEXEC	RemTask

;-- Fake seglist for NP_Seglist: BPTR -> the next-BPTR longword; DOS
;   starts execution 4 bytes after it. Lives in ROM, never freed
;   (NP_FreeSeglist = FALSE).
	cnop	0,4
	dc.l	16			;fake segment length (never freed)
_ma_fakeseg:
	dc.l	0			;next segment = none
	jmp	_MountWorkEntry(pc)

;-- _MountWorkEntry: the worker, a real DOS process. Looks up the
;   device by name (single unit), reconciles partition.resource against
;   the live card state via ptable.library v2, signals the agent, exits.
_MountWorkEntry:
	movem.l	d2-d7/a2-a6,-(sp)
	lea	-CFG_SIZEOF(sp),sp	;config frame
	move.l	sp,a5			;a5 = config frame base
	move.l	(_AbsExecBase).w,a6
	jsr	Forbid(a6)
	lea	SB_DeviceList(a6),a0
	lea	s_name(pc),a1		;"compactflash.device"
	jsr	FindName(a6)
	move.l	d0,d2
	jsr	Permit(a6)
	tst.l	d2
	beq.w	_mw_out			;device gone: nothing to do
	move.l	d2,a4			;&Dev (for CALLEXEC / DBGMSG)
	move.l	CFD_Unit(a4),d0
	beq.w	_mw_out
	move.l	d0,a3			;&Unit
;-- open ptable.library v2; without it there is nothing to reconcile
	moveq.l	#2,d0
	lea	RdbLibName(pc),a1	;"ptable.library"
	CALLEXEC OpenLibrary
	move.l	d0,d6
	ifd	DEBUG
	bne.s	_mw_haveLib
	DBGMSG	dbg_mw_pt_fail
	bra.w	_mw_done
_mw_haveLib:
	DBGMSG	dbg_mw_pt
	else
	beq.w	_mw_done
	endc
	bsr	_mwReadConfig		;cfd.prefs -> a5 frame
	ifd	DEBUG
	move.w	CFG_MountCfg+mc_Flags+2(a5),d0	;global FLAGS -> gate so worker trace shows
	or.w	d0,CFU_OpenFlags(a3)
	DBGMSG	dbg_mw_cfg_b
	moveq.l	#0,d0
	move.b	CFG_Source(a5),d0	;CFGSRC_*
	DBGDEC
	DBGMSG	dbg_mw_cfg_rd
	move.l	CFG_DbgRead(a5),d0
	DBGDEC
	DBGMSG	dbg_mw_cfg_am
	moveq.l	#0,d0
	move.b	CFG_AutoMount(a5),d0
	DBGDEC
	DBGMSG	dbg_mw_cfg_fl
	move.l	CFG_MountCfg+mc_Flags(a5),d0
	DBGDEC
	tst.b	CFG_AmBad(a5)
	beq.s	_mw_dbg_trunc
	DBGMSG	dbg_mw_cfg_ambad
_mw_dbg_trunc:
	tst.b	CFG_Trunc(a5)
	beq.s	_mw_dbg_cfgend
	DBGMSG	dbg_mw_cfg_trunc
_mw_dbg_cfgend:
	DBGNL
	endc
	tst.l	CFU_DriveSize(a3)
	beq.w	_mw_unmount
;-- card present: always scan/publish so the partitions show in lsptres
;   (partition.resource only, no DOS nodes); mount only if automount is on.
	DBGMSG	dbg_mw_scan_b
	move.l	d6,a6
	lea	s_name(pc),a1
	moveq.l	#0,d0			;unit 0 (the only unit)
	jsr	_LVOScanPartitions(a6)
	DBGMSG	dbg_mw_scan_a
	DBGDEC
	DBGNL
	tst.b	CFG_AutoMount(a5)
	beq.w	_mw_close		;automount off: published for lsptres, not mounted
;-- settle: let an in-flight handler mount (a device-dostype DOSDriver that just
;   opened us) register its partition before we mount, so MountPartitions reuses
;   it (PEB_MOUNTED) instead of starting a second handler on the same partition.
	moveq.l	#0,d0			;any version
	lea	MAgentDosName(pc),a1
	CALLEXEC OpenLibrary
	tst.l	d0
	beq.s	_mw_settled
	move.l	d0,d2			;d2 = DOSBase (preserved across Delay)
	move.l	d0,a6
	move.l	#MOUNT_SETTLE_TICKS,d1
	jsr	Delay(a6)
	move.l	d2,a1
	CALLEXEC CloseLibrary
_mw_settled:
	DBGMSG	dbg_mw_mnt_b
	move.l	d6,a6
	lea	s_name(pc),a1
	moveq.l	#0,d0
	lea	CFG_MountCfg(a5),a0	;MountCfg -> per-partition Flags/Control
	jsr	_LVOMountPartitions(a6)
	DBGMSG	dbg_mw_mnt_a
	DBGDEC
	DBGNL
	bra.s	_mw_close
_mw_unmount:
;-- CFU_DriveSize is also 0 while a card sits in the slot unidentified, e.g.
;   during bringup. Read the live Gayle card-detect line ($DA8000 bit 6, set =
;   card present) and leave the mounts alone in that case; the unit task
;   signals the agent again when the identify finishes.
	btst.b	#6,$00DA8000
	beq.s	_mw_umnt_go
	DBGMSG	dbg_mw_umnt_wait
	DBGNL
	bra.s	_mw_close
_mw_umnt_go:
;-- card removed: empty UNMOUNT list -> MarkAbsent (keep node + handler);
;   non-empty -> UnmountPartitions(prefixList) (unmount the listed filesystems).
	DBGMSG	dbg_mw_umnt_b
	move.l	d6,a6
	lea	s_name(pc),a1
	moveq.l	#0,d0
	lea	CFG_Prefixes(a5),a0
	tst.l	(a0)			;empty prefix list?
	bne.s	_mw_detach
	jsr	_LVOMarkAbsent(a6)
	bra.s	_mw_detach_dbg
_mw_detach:
	jsr	_LVOUnmountPartitions(a6)
_mw_detach_dbg:
	DBGMSG	dbg_mw_umnt_a
	DBGDEC
	DBGNL
_mw_close:
	move.l	d6,a1
	CALLEXEC CloseLibrary
_mw_done:
;-- wake the agent (it serialises on this)
	move.l	CFU_MountDone(a3),d0
	beq.s	_mw_out
	move.l	CFU_MountAgent(a3),d1
	beq.s	_mw_out
	move.l	d1,a1
	CALLEXEC Signal
_mw_out:
	lea	CFG_SIZEOF(sp),sp	;release config frame
	movem.l	(sp)+,d2-d7/a2-a6
	moveq.l	#0,d0
	rts

;===========================================================
; _mwReadConfig: read ENV:cfd.prefs into the config frame via GetVar (global,
; binary so multi-line is read whole) and build a MountCfg. Line-oriented,
; exact whole-word keys: AUTOMOUNT / FLAGS / CONTROL / UNMOUNT (global) plus
; FLAGS_<fs> / CONTROL_<fs> per-dostype overrides. A missing var or key keeps
; the default (flags 0, no control). AUTOMOUNT defaults on everywhere (ROM and
; file-based alike); opt out with AUTOMOUNT 0 in cfd.prefs. UNMOUNT defaults to
; all supported filesystems; an UNMOUNT key with no recognized names (e.g.
; UNMOUNT NONE) keeps handlers on removal instead.
; In : a5 = config frame. Preserves a3/a4/a5/d6/d7.
;===========================================================
CFG_BUFSZ	= 512
CFG_OVMAX	= 6			;max override rows
CFG_NCTL	= 8			;control-pool slots (global + per-FS)
CFG_CTLSZ	= 32			;bytes per control slot

;-- CFG_Source values
CFGSRC_NONE	= 0			;no prefs found: built-in defaults
CFGSRC_ENV	= 1			;ENV:cfd.prefs (GetVar)
CFGSRC_ENVARC	= 2			;ENVARC:cfd.prefs
CFGSRC_ARCHIVE	= 3			;SYS:Prefs/Env-Archive/cfd.prefs

CFG_Buf		= 0			;config text buffer (0..CFG_BUFSZ-1)
CFG_Prefixes	= 512			;UNMOUNT dostype list, 0-terminated (8 longs)
CFG_AutoMount	= 544			;byte (1 = automount on)
CFG_CtlNext	= 545			;byte (control slots used)
CFG_OvNext	= 546			;byte (override rows used)
CFG_Source	= 547			;byte CFGSRC_*
CFG_AmBad	= 548			;byte (1 = AUTOMOUNT value not recognized)
CFG_Trunc	= 549			;byte (1 = prefs filled the buffer)
CFG_DbgRead	= 552			;long bytes read (-1 = no prefs found)
CFG_MountCfg	= 556			;MountCfg (mc_Flags/mc_Control/mc_Overrides)
CFG_Overrides	= 568			;(CFG_OVMAX+1) override rows * ovr_Sizeof
CFG_Controls	= 680			;CFG_NCTL control C-string slots * CFG_CTLSZ
CFG_SIZEOF	= 936

;-- _mwLoadPrefs: read cfd.prefs into CFG_Buf from the first source that has
;   it: ENV: (GetVar), ENVARC:cfd.prefs, SYS:Prefs/Env-Archive/cfd.prefs.
;   Startup-Sequence assigns ENV:/ENVARC: after the RTF_AFTERDOS bringup that
;   starts the worker, so at the first automount only the SYS: path resolves;
;   dos.library assigns SYS: at boot. On that first pass with a card present
;   the cascade is retried before falling back to the built-in defaults.
;   In : a2 = DOSBase, a3 = &Unit, a4 = &Dev, a5 = config frame
;   Out: d3 = bytes read, or -1 if no source has it; CFG_Source set
PREFS_STEP	= 10			;ticks between retries (1/5 s)
PREFS_TRIES	= 10			;~2 s total budget
_mwLoadPrefs:
	movem.l	d0-d2/d4-d7/a0-a1/a6,-(sp)
	moveq.l	#PREFS_TRIES,d7		;d7 = remaining tries
_mlp_try:
;-- 1. ENV: via GetVar, binary so newlines are kept
	move.l	a2,a6
	lea	s_cfgname(pc),a0
	move.l	a0,d1			;name "cfd.prefs" (bare, no ENV:)
	lea	CFG_Buf(a5),a0
	move.l	a0,d2			;buffer
	move.l	#CFG_BUFSZ-1,d3
	move.l	#GVF_GLOBAL_ONLY!GVF_BINARY_VAR,d4
	jsr	DosGetVar(a6)
	move.l	d0,d3
	moveq.l	#CFGSRC_ENV,d6
	tst.l	d3
	bgt.s	_mlp_got
;-- 2. ENVARC:cfd.prefs
	lea	s_envarc_prefs(pc),a0
	bsr	_mwLoadFile
	move.l	d0,d3
	moveq.l	#CFGSRC_ENVARC,d6
	tst.l	d3
	bgt.s	_mlp_got
;-- 3. the same file before Startup-Sequence assigns ENVARC:
	lea	s_env_archive(pc),a0
	bsr	_mwLoadFile
	move.l	d0,d3
	moveq.l	#CFGSRC_ARCHIVE,d6
	tst.l	d3
	bgt.s	_mlp_got
;-- no source yet: retry on the first pass with a card present
	tst.b	CFD_PrefsReady(a4)
	bne.s	_mlp_none
	tst.l	CFU_DriveSize(a3)
	beq.s	_mlp_none
	subq.w	#1,d7
	beq.s	_mlp_none
	move.l	a2,a6
	moveq.l	#PREFS_STEP,d1
	jsr	Delay(a6)
	bra.w	_mlp_try
_mlp_none:
	moveq.l	#-1,d3
	clr.b	CFG_Source(a5)		;CFGSRC_NONE
	bra.s	_mlp_out
_mlp_got:
	move.b	d6,CFG_Source(a5)
	move.b	#1,CFD_PrefsReady(a4)	;resolved once: later passes do not retry
_mlp_out:
	movem.l	(sp)+,d0-d2/d4-d7/a0-a1/a6
	rts

;-- _mwLoadFile: read a prefs file into CFG_Buf.
;   In : a0 = file name, a2 = DOSBase, a5 = config frame
;   Out: d0 = bytes read, or -1 if the file cannot be opened or read
_mwLoadFile:
	movem.l	d1-d4/a0-a1/a6,-(sp)
	move.l	a2,a6
	move.l	a0,d1
	move.l	#MODE_OLDFILE,d2
	jsr	DosOpen(a6)
	move.l	d0,d4			;d4 = file handle
	bne.s	_mlf_read
	moveq.l	#-1,d0
	bra.s	_mlf_out
_mlf_read:
	move.l	d4,d1
	lea	CFG_Buf(a5),a0
	move.l	a0,d2
	move.l	#CFG_BUFSZ-1,d3
	jsr	DosRead(a6)
	move.l	d0,d3			;d3 = bytes read, -1 = read error
	move.l	d4,d1
	jsr	DosClose(a6)
	move.l	d3,d0
_mlf_out:
	movem.l	(sp)+,d1-d4/a0-a1/a6
	rts

;-- _cfgStripComments: blank out ; and # comments up to the end of their line.
;   The keyword search runs over the whole buffer, so without this a commented
;   out key is still matched.
;   In : a0 = NUL-terminated buffer
_cfgStripComments:
	movem.l	d0/a0,-(sp)
_csc_scan:
	move.b	(a0),d0
	beq.s	_csc_out
	cmp.b	#';',d0
	beq.s	_csc_blank
	cmp.b	#'#',d0
	beq.s	_csc_blank
	addq.l	#1,a0
	bra.s	_csc_scan
_csc_blank:
	move.b	#' ',(a0)+
	move.b	(a0),d0
	beq.s	_csc_out
	cmp.b	#13,d0
	beq.s	_csc_scan
	cmp.b	#10,d0
	beq.s	_csc_scan
	bra.s	_csc_blank
_csc_out:
	movem.l	(sp)+,d0/a0
	rts

;-- _cfgUpper: fold one ASCII letter in d0.b to upper case.
_cfgUpper:
	cmp.b	#'a',d0
	bcs.s	_cup_out
	cmp.b	#'z',d0
	bhi.s	_cup_out
	sub.b	#'a'-'A',d0
_cup_out:
	rts

_mwReadConfig:
	movem.l	d0-d7/a0-a4/a6,-(sp)
	move.b	#1,CFG_AutoMount(a5)	;automount on by default everywhere; opt
					;out via AUTOMOUNT 0 in ENV:cfd.prefs
	move.l	#-1,CFG_DbgRead(a5)
	clr.b	CFG_CtlNext(a5)
	clr.b	CFG_OvNext(a5)
	clr.b	CFG_Source(a5)
	clr.b	CFG_AmBad(a5)
	clr.b	CFG_Trunc(a5)
	clr.l	CFG_MountCfg+mc_Flags(a5)
	clr.l	CFG_MountCfg+mc_Control(a5)
	clr.l	CFG_MountCfg+mc_Overrides(a5)
;-- default UNMOUNT list: every um_table prefix (unmount all supported
;   filesystems on removal). An explicit UNMOUNT key rebuilds the list; a key
;   with no recognized names leaves it empty (keep handlers). 6 prefixes +
;   terminator fit the 8-long CFG_Prefixes field.
	lea	CFG_Prefixes(a5),a0
	lea	um_table(pc),a1
_cfg_umdef:
	move.l	(a1)+,d0		;name ptr (0 = end of table)
	beq.s	_cfg_umdef_done
	move.l	(a1)+,(a0)+		;append the row's dostype prefix
	bra.s	_cfg_umdef
_cfg_umdef_done:
	clr.l	(a0)			;terminate prefix list
	lea	CFG_Overrides(a5),a0
	clr.l	ovr_Prefix(a0)		;empty override table (terminator)
	move.l	(_AbsExecBase).w,a6
	moveq.l	#36,d0
	lea	MAgentDosName(pc),a1	;"dos.library"
	jsr	OpenLibrary(a6)
	tst.l	d0
	beq.w	_cfg_done		;no dos.library -> defaults
	move.l	d0,a2			;a2 = DOSBase
	bsr	_mwLoadPrefs		;d3 = bytes read, or -1
	move.l	d3,CFG_DbgRead(a5)
	move.l	a2,a1
	move.l	(_AbsExecBase).w,a6
	jsr	CloseLibrary(a6)
	tst.l	d3
	ble.w	_cfg_done		;no prefs -> defaults
	cmp.l	#CFG_BUFSZ-1,d3
	bcs.s	_cfg_term
	move.l	#CFG_BUFSZ-1,d3
	move.b	#1,CFG_Trunc(a5)	;prefs filled the buffer: rest not parsed
_cfg_term:
	lea	CFG_Buf(a5),a0
	clr.b	0(a0,d3.l)		;NUL-terminate
	lea	CFG_Buf(a5),a0
	bsr	_cfgStripComments
;-- AUTOMOUNT
	lea	CFG_Buf(a5),a0
	lea	kw_automount(pc),a1
	bsr	_cfgStr
	tst.l	d0
	beq.s	_cfg_flags
;-- accepted values: 0 1 ON OFF YES NO, either case. Anything else keeps the
;   default and is reported in the worker trace.
	move.l	d0,a0
	bsr	_cfgSkipSp
	move.b	(a0),d0
	cmp.b	#'0',d0
	beq.s	_cfg_am_off
	cmp.b	#'1',d0
	beq.s	_cfg_am_on
	bsr	_cfgUpper
	cmp.b	#'N',d0			;NO
	beq.s	_cfg_am_off
	cmp.b	#'Y',d0			;YES
	beq.s	_cfg_am_on
	cmp.b	#'O',d0			;ON / OFF
	bne.s	_cfg_am_bad
	move.b	1(a0),d0
	bsr	_cfgUpper
	cmp.b	#'F',d0
	beq.s	_cfg_am_off
	cmp.b	#'N',d0
	beq.s	_cfg_am_on
_cfg_am_bad:
	move.b	#1,CFG_AmBad(a5)	;unrecognized value -> keep the default
	bra.s	_cfg_flags
_cfg_am_off:
	clr.b	CFG_AutoMount(a5)
	bra.s	_cfg_flags
_cfg_am_on:
	move.b	#1,CFG_AutoMount(a5)
_cfg_flags:
;-- global FLAGS
	lea	CFG_Buf(a5),a0
	lea	kw_flags(pc),a1
	bsr	_cfgStr
	tst.l	d0
	beq.s	_cfg_control
	move.l	d0,a0
	bsr	_cfgSkipSp
	bsr	_cfgDec
	move.l	d0,CFG_MountCfg+mc_Flags(a5)
_cfg_control:
;-- global CONTROL
	lea	CFG_Buf(a5),a0
	lea	kw_control(pc),a1
	bsr	_cfgStr
	tst.l	d0
	beq.s	_cfg_ovkw
	move.l	d0,a0
	bsr	_cfgSkipSp
	bsr	_cfgCtl
	move.l	d0,CFG_MountCfg+mc_Control(a5)
_cfg_ovkw:
;-- per-FS overrides: {keyword, dostype-prefix, isControl} rows
	lea	ovkw_table(pc),a4
_cfg_ovloop:
	move.l	(a4),d0			;keyword (0 = end)
	beq.s	_cfg_unmount
	move.l	d0,a1
	lea	CFG_Buf(a5),a0
	bsr	_cfgStr
	tst.l	d0
	beq.s	_cfg_ovnext
	move.l	d0,a0			;a0 = value start
	bsr	_cfgSkipSp
	move.l	4(a4),d0		;prefix
	bsr	_cfgFindOrAddOv		;d1 = row (0 = table full)
	tst.l	d1
	beq.s	_cfg_ovnext
	move.l	d1,a1			;a1 = override row
	tst.l	8(a4)			;isControl?
	bne.s	_cfg_ovctl
	bsr	_cfgDec			;FLAGS_<fs>
	move.l	d0,ovr_Flags(a1)
	move.b	#1,ovr_HasFlags(a1)
	bra.s	_cfg_ovnext
_cfg_ovctl:
	bsr	_cfgCtl			;CONTROL_<fs>
	move.l	d0,ovr_Control(a1)
_cfg_ovnext:
	lea	12(a4),a4		;next ovkw row (12 bytes)
	bra.s	_cfg_ovloop
_cfg_unmount:
	lea	CFG_Buf(a5),a0
	lea	kw_unmount(pc),a1
	bsr	_cfgStr
	tst.l	d0
	beq.s	_cfg_done		;no UNMOUNT key -> keep default (unmount all)
	lea	CFG_Prefixes(a5),a2	;output cursor
	lea	um_table(pc),a3		;{name, dostype prefix} rows
_cfg_um_loop:
	move.l	(a3),d0			;name pointer (0 = end of table)
	beq.s	_cfg_um_term
	lea	CFG_Buf(a5),a0
	move.l	d0,a1			;needle = FS name
	bsr	_cfgStr
	tst.l	d0
	beq.s	_cfg_um_next
	move.l	4(a3),(a2)+		;name present -> append its dostype prefix
_cfg_um_next:
	addq.l	#8,a3			;next row
	bra.s	_cfg_um_loop
_cfg_um_term:
	clr.l	(a2)			;terminate prefix list
_cfg_done:
	movem.l	(sp)+,d0-d7/a0-a4/a6
	rts

;-- _cfgStr: find NUL-term needle (a1) as a WHOLE WORD in NUL-term haystack (a0).
;   Word char = [A-Za-z0-9_]; the match must be bounded by non-word chars (or the
;   buffer ends) on both sides, so FLAGS does not match inside FLAGS_DOS and a
;   name DOS does not match inside FLAGS_DOS.
;   Out: d0 = ptr just past the match, or 0. Preserves d2-d3/a2-a4.
_cfgStr:
	movem.l	d2-d3/a2-a4,-(sp)
	move.l	a1,a3			;needle start
	move.l	a0,a4			;haystack start
_cs_outer:
	tst.b	(a0)
	beq.s	_cs_no			;haystack end -> no match
	cmp.l	a0,a4
	beq.s	_cs_try			;at start -> prev boundary ok
	move.l	a0,a2
	subq.l	#1,a2
	move.b	(a2),d2
	bsr	_cfgWordCh
	tst.b	d0
	bne.s	_cs_adv			;prev is word char -> not a word start
_cs_try:
	move.l	a0,a2			;haystack cursor
	move.l	a3,a1			;needle cursor
_cs_inner:
	move.b	(a1)+,d3
	beq.s	_cs_chksfx		;needle end -> check suffix boundary
	move.b	(a2)+,d2
	beq.s	_cs_no			;haystack ended mid-needle
	cmp.b	d3,d2
	beq.s	_cs_inner
	bra.s	_cs_adv			;mismatch
_cs_chksfx:
	move.b	(a2),d2			;char just past match
	bsr	_cfgWordCh
	tst.b	d0
	bne.s	_cs_adv			;suffix is word char -> not whole word
	move.l	a2,d0			;whole-word match
	bra.s	_cs_ret
_cs_adv:
	addq.l	#1,a0
	bra.s	_cs_outer
_cs_no:
	moveq.l	#0,d0
_cs_ret:
	movem.l	(sp)+,d2-d3/a2-a4
	rts

;-- _cfgWordCh: d2.b char -> d0.b = 1 if [A-Za-z0-9_] else 0.
_cfgWordCh:
	moveq.l	#1,d0
	cmp.b	#'0',d2
	bcs.s	_cwc_a
	cmp.b	#'9',d2
	bls.s	_cwc_ret
_cwc_a:
	cmp.b	#'A',d2
	bcs.s	_cwc_b
	cmp.b	#'Z',d2
	bls.s	_cwc_ret
_cwc_b:
	cmp.b	#'a',d2
	bcs.s	_cwc_c
	cmp.b	#'z',d2
	bls.s	_cwc_ret
_cwc_c:
	cmp.b	#'_',d2
	beq.s	_cwc_ret
	moveq.l	#0,d0
_cwc_ret:
	rts

;-- _cfgSkipSp: advance a0 past spaces, tabs and '='. Clobbers d0.
_cfgSkipSp:
	move.b	(a0),d0
	cmp.b	#' ',d0
	beq.s	_csk_adv
	cmp.b	#9,d0
	beq.s	_csk_adv
	cmp.b	#'=',d0
	beq.s	_csk_adv
	rts
_csk_adv:
	addq.l	#1,a0
	bra.s	_cfgSkipSp

;-- _cfgDec: parse unsigned decimal at a0 -> d0. Advances a0; preserves a1-a4.
_cfgDec:
	movem.l	d1-d2,-(sp)
	moveq.l	#0,d1
_cfgdec_l:
	moveq.l	#0,d0
	move.b	(a0)+,d0
	sub.b	#'0',d0
	bcs.s	_cfgdec_e
	cmp.b	#9,d0
	bhi.s	_cfgdec_e
	move.l	d1,d2
	lsl.l	#3,d1
	add.l	d2,d1
	add.l	d2,d1			;d1 = d1*10
	add.l	d0,d1
	bra.s	_cfgdec_l
_cfgdec_e:
	move.l	d1,d0
	movem.l	(sp)+,d1-d2
	rts

;-- _cfgCtl: copy the CONTROL value at a0 (optionally "quoted") into the next
;   control-pool slot. Out: d0 = slot addr, or 0 (empty / pool full).
;   Preserves a1-a4/d1-d4.
_cfgCtl:
	movem.l	d1-d4/a1-a2,-(sp)
	moveq.l	#0,d1
	move.b	CFG_CtlNext(a5),d1
	cmp.b	#CFG_NCTL,d1
	bhs.s	_cfgctl_none
	move.l	d1,d4
	lsl.l	#5,d4			;*CFG_CTLSZ (32)
	lea	CFG_Controls(a5),a1
	add.l	d4,a1			;a1 = slot base
	move.l	a1,a2			;a2 = dest cursor
	moveq.l	#CFG_CTLSZ-1,d3
	moveq.l	#0,d2			;quote flag
	cmp.b	#'"',(a0)
	bne.s	_cfgctl_cp
	addq.l	#1,a0
	moveq.l	#1,d2
_cfgctl_cp:
	move.b	(a0)+,d1
	beq.s	_cfgctl_end
	tst.b	d2
	bne.s	_cfgctl_q
	cmp.b	#' ',d1			;ws-delimited: stop at space/ctrl
	bls.s	_cfgctl_end
	cmp.b	#',',d1
	beq.s	_cfgctl_end
	bra.s	_cfgctl_put
_cfgctl_q:
	cmp.b	#'"',d1			;closing quote
	beq.s	_cfgctl_end
_cfgctl_put:
	tst.l	d3
	beq.s	_cfgctl_end
	move.b	d1,(a2)+
	subq.l	#1,d3
	bra.s	_cfgctl_cp
_cfgctl_end:
	clr.b	(a2)			;NUL-terminate slot
	tst.b	(a1)
	beq.s	_cfgctl_none		;empty -> no slot consumed
	addq.b	#1,CFG_CtlNext(a5)
	move.l	a1,d0
	movem.l	(sp)+,d1-d4/a1-a2
	rts
_cfgctl_none:
	moveq.l	#0,d0
	movem.l	(sp)+,d1-d4/a1-a2
	rts

;-- _cfgFindOrAddOv: find the override row for prefix d0, else append one.
;   Out: d1 = row addr, or 0 if table full. Preserves a0/d0/a2-a4.
_cfgFindOrAddOv:
	movem.l	d2/a1-a2,-(sp)
	lea	CFG_Overrides(a5),a1
_cfoa_scan:
	move.l	ovr_Prefix(a1),d2
	beq.s	_cfoa_add
	cmp.l	d2,d0
	beq.s	_cfoa_hit
	lea	ovr_Sizeof(a1),a1
	bra.s	_cfoa_scan
_cfoa_add:
	moveq.l	#0,d2
	move.b	CFG_OvNext(a5),d2
	cmp.b	#CFG_OVMAX,d2
	bhs.s	_cfoa_full
	addq.b	#1,CFG_OvNext(a5)
	move.l	d0,ovr_Prefix(a1)
	clr.l	ovr_Flags(a1)
	clr.b	ovr_HasFlags(a1)
	clr.l	ovr_Control(a1)
	lea	ovr_Sizeof(a1),a2
	clr.l	ovr_Prefix(a2)		;new terminator
	lea	CFG_Overrides(a5),a2
	move.l	a2,CFG_MountCfg+mc_Overrides(a5)
_cfoa_hit:
	move.l	a1,d1
	movem.l	(sp)+,d2/a1-a2
	rts
_cfoa_full:
	moveq.l	#0,d1
	movem.l	(sp)+,d2/a1-a2
	rts

s_cfgname:	dc.b	"cfd.prefs",0
s_envarc_prefs:	dc.b	"ENVARC:cfd.prefs",0
s_env_archive:	dc.b	"SYS:Prefs/Env-Archive/cfd.prefs",0
kw_automount:	dc.b	"AUTOMOUNT",0
kw_flags:	dc.b	"FLAGS",0
kw_control:	dc.b	"CONTROL",0
kw_unmount:	dc.b	"UNMOUNT",0
kw_flags_dos:	dc.b	"FLAGS_DOS",0
kw_flags_ffs:	dc.b	"FLAGS_FFS",0
kw_flags_sfs:	dc.b	"FLAGS_SFS",0
kw_flags_pfs:	dc.b	"FLAGS_PFS",0
kw_flags_fat:	dc.b	"FLAGS_FAT",0
kw_ctl_dos:	dc.b	"CONTROL_DOS",0
kw_ctl_ffs:	dc.b	"CONTROL_FFS",0
kw_ctl_sfs:	dc.b	"CONTROL_SFS",0
kw_ctl_pfs:	dc.b	"CONTROL_PFS",0
kw_ctl_fat:	dc.b	"CONTROL_FAT",0
nm_pfs:		dc.b	"PFS",0
nm_dos:		dc.b	"DOS",0
nm_ffs:		dc.b	"FFS",0
nm_sfs:		dc.b	"SFS",0
nm_fat:		dc.b	"FAT",0
	even

;-- UNMOUNT name -> dostype-prefix table. Each row: name C-string, prefix
;   (pe_DosType high 3 bytes). A name may have several rows; add a filesystem
;   by adding a row. 0 terminates.
um_table:
	dc.l	nm_pfs,$50465300	;PFS -> 'PFS'
	dc.l	nm_pfs,$50445300	;PFS -> 'PDS' (pfs3 alternate)
	dc.l	nm_dos,$444F5300	;DOS -> 'DOS'
	dc.l	nm_ffs,$444F5300	;FFS -> 'DOS'
	dc.l	nm_sfs,$53465300	;SFS -> 'SFS'
	dc.l	nm_fat,$46415400	;FAT -> 'FAT'
	dc.l	0

;-- per-FS override keyword table. Each row: keyword, dostype prefix,
;   isControl (0 = FLAGS_<fs>, 1 = CONTROL_<fs>). PFS has two rows (PFS + PDS).
;   0 terminates.
ovkw_table:
	dc.l	kw_flags_dos,$444F5300,0
	dc.l	kw_flags_ffs,$444F5300,0
	dc.l	kw_flags_sfs,$53465300,0
	dc.l	kw_flags_pfs,$50465300,0
	dc.l	kw_flags_pfs,$50445300,0
	dc.l	kw_flags_fat,$46415400,0
	dc.l	kw_ctl_dos,$444F5300,1
	dc.l	kw_ctl_ffs,$444F5300,1
	dc.l	kw_ctl_sfs,$53465300,1
	dc.l	kw_ctl_pfs,$50465300,1
	dc.l	kw_ctl_pfs,$50445300,1
	dc.l	kw_ctl_fat,$46415400,1
	dc.l	0

MAgentName:
	dc.b	"CF.MountAgent",0
MWorkName:
	dc.b	"CF.MountWork",0
MAgentDosName:
	dc.b	"dos.library",0
RdbLibName:
	dc.b	"ptable.library",0
	even

	ifd	DEBUG
dbg_ma_spawn:
	dc.b	"[MA] automount agent ready (unit 0)",13,10,0
dbg_ma_wake_in:
	dc.b	"[MA] unit 0: card present, automounting",13,10,0
dbg_ma_wake_out:
	dc.b	"[MA] unit 0: card removed",13,10,0
dbg_ma_dos:
	dc.b	"[MA] unit 0: DOS ready, starting worker",13,10,0
dbg_ma_run_fail:
	dc.b	"[MA] unit 0: ERROR could not start mount worker",13,10,0
dbg_mw_pt:
	dc.b	"[MW] using ptable.library",13,10,0
dbg_mw_pt_fail:
	dc.b	"[MW] ERROR ptable.library unavailable",13,10,0
dbg_mw_scan_b:
	dc.b	"[MW] scanning compactflash.device:0 for partitions",13,10,0
dbg_mw_scan_a:
	dc.b	"[MW] scan done, partitions known: ",0
dbg_mw_mnt_b:
	dc.b	"[MW] mounting new partitions",13,10,0
dbg_mw_mnt_a:
	dc.b	"[MW] mounted volumes: ",0
dbg_mw_umnt_b:
	dc.b	"[MW] card removed",13,10,0
dbg_mw_umnt_a:
	dc.b	"[MW] entries detached: ",0
dbg_mw_umnt_wait:
	dc.b	"[MW] card still in slot, not identified yet: keeping mounts",0
dbg_mw_cfg_b:
	dc.b	"[MW] config: src=",0
dbg_mw_cfg_rd:
	dc.b	" read=",0
dbg_mw_cfg_am:
	dc.b	" auto=",0
dbg_mw_cfg_fl:
	dc.b	" flags=",0
dbg_mw_cfg_ambad:
	dc.b	" (AUTOMOUNT value ignored)",0
dbg_mw_cfg_trunc:
	dc.b	" (prefs truncated)",0
	even
	endc

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
	bsr	_IS1
	bra.s	_wc_end
_wc_next:
	subq.w	#1,d0
	move.w	d0,CFU_WatchTimer(a1)
_wc_end:
	moveq.l	#0,d0
	rts

;--- notify user -------------------------------------------

; Walks CFU_Clients (a list of IORequests left behind by TD_ADDCHANGEINT).
; Each node's IO_Data points to a client-supplied Interrupt struct whose
; IS_Code is called with a6=SysBase, a1=IS_Data.
;
; Trust contract: callers are responsible for calling TD_REMCHANGEINT
; before their IS_Code memory is freed. We only reject NULL IO_Data /
; NULL IS_Code defensively (cheap, catches accidental zero init) and
; otherwise dispatch directly to the registered server.
NotifyClients:
	movem.l	d2/a2/a5,-(sp)
	CALLEXEC Forbid			;a6 = SysBase on return
	move.l	CFU_Clients(a3),d2
ncl_loop:
	move.l	d2,a5			;&IORequest
	move.l	(a5),d2			;d2 = next (ln_Succ)
	beq.w	ncl_end			;end of List

	move.l	a5,a2			;save &IORequest for possible Remove
	move.l	IO_Data(a5),a5		;&InterruptServer (may be bogus)
	move.l	a5,d0
	beq.s	ncl_drop		;no Interrupt struct -> drop

	move.l	IS_Code(a5),a1		;client-supplied IS_Code
	move.l	a1,d0
	beq.s	ncl_drop		;NULL IS_Code -> drop

	DBGMSG	dbg_notify_call
	move.l	a1,d0
	DBGNUM
	DBGNL

	move.l	IS_Data(a5),a1		;Interrupt convention: a1 = IS_Data
	move.l	IS_Code(a5),a5		;a5 = IS_Code
	jsr	(a5)			;a6 = SysBase preserved by server
	bra.w	ncl_loop

ncl_drop:
	DBGMSG	dbg_notify_drop
	move.l	a2,d0
	DBGNUM
	DBGNL
	move.l	a2,a1			;node to unlink
	jsr	Remove(a6)
	bra.w	ncl_loop

ncl_end:
	CALLEXEC Permit
	movem.l	(sp)+,d2/a2/a5
	rts

;--- test PCMCIA communication -----------------------------
; Test which PIO transfer modes work reliably with the card
;
; Input:
;   a3 = CFU pointer
;
; Output:
;   d0 = bitfield of working modes (bits 0-3)
;        bit 0: mode 0 (WORD - 16-bit word access)
;        bit 1: mode 1 (BYTE data - 8-bit at adjacent addresses)
;        bit 2: mode 2 (BYTE alt - 8-bit at separate I/O addresses)
;        bit 3: mode 3 (BYTE alt2 - 8-bit via alternate register)
;   CFU_RWFlags = bitfield of working modes
;   CFU_WriteMode = selected write mode (0-3, lowest working mode)
;   CFU_ReadMode = cleared to 0
;
; Notes:
;   - Tests I/O modes 0-3 using pattern-based read/write tests
;   - Runs TestRun twice for reliability (AND results)
;   - Selects the lowest working I/O mode (0 preferred)
;   - If no modes work, defaults to mode 1
;   - Updates transfer mode configuration in CFU
;
RWTest:
	movem.l	d2-d3,-(sp)
	move.l	CFU_IDEAddr(a3),a0
	addq.l	#4,a0
	move.l	a0,a1
	add.l	#$10000,a1
	move.w	#$1234,d2		;the bit pattern used for testing
	bsr	TestRun
	move.w	d0,d3
	bsr	TestRun
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
	bsr	_BindIOHandlers		;prime read/write handler pointers
	move.l	d3,d0
	movem.l	(sp)+,d2-d3
	rts

;--- test I/O mode patterns --------------------------------
; Test I/O modes 0-3 by writing/reading test patterns
;
; Input:
;   a0 = IDE register base address (CFU_IDEAddr + 4)
;   a1 = alternate address (a0 + 0x10000)
;   d2 = test pattern (e.g., $1234)
;   a3 = CFU pointer
;
; Output:
;   d0 = bitfield of working I/O modes (bits 0-3)
;
; Notes:
;   - Tests all 16 combinations of write/read modes (4x4)
;   - Mode 0: 16-bit word access
;   - Mode 1: 8-bit byte access (adjacent addresses)
;   - Mode 2: 8-bit byte access (separate I/O)
;   - Mode 3: 8-bit byte access (alternate register)
;   - Uses jump table (tr_tab) for mode-specific handlers
;   - Increments pattern for each test to detect stale data
;
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
	add.w	d0,d0			;*2 via add.w (faster than lsl.w #1)
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

;*** IDE Protocol ******************************************
;--- wait by polling ---------------------------------------
; Poll IDE status register until drive becomes ready
;
; Input:
;   a3 = CFU pointer
;
; Output:
;   d0 = IDE status byte (bit 7 = BSY, bit 6 = DRDY)
;        Returns -1 if card removed or timeout
;
; Notes:
;   - Polls IDE status register waiting for BSY to clear
;   - Selects master drive (DEVHEAD = $E0) before polling
;   - 30-second timeout (100 iterations x 300ms delay)
;   - Acknowledges status changes via PCMCIA config register
;   - Frees interrupts when ready (bit 1 of register 14)
;   - Used during card initialization to wait for drive ready
;
BusyWait:
	move.l	d2,-(sp)
	bsr	_IDEStart
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
	bsr	_IDEStop
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
; Read IDE error register and ATAPI sense data
;
; Input:
;   a3 = CFU pointer
;
; Output:
;   d0 = sense key (0-127) if ATAPI, -1 if ATA or error
;   CFU_IDEError = IDE error register value
;   CFU_IDESense = ATAPI sense key (if ATAPI device)
;   CFU_IOErr = converted IO error code (if ATAPI)
;
; Notes:
;   - Reads IDE error register (offset 13) into CFU_IDEError
;   - For ATAPI devices, issues REQUEST SENSE command ($03)
;   - Reads sense key from error register after REQUEST SENSE
;   - Converts sense key to IO error code (bit 6 set = error)
;   - Handles both word (mode 0) and byte (modes 1-3) transfers
;   - Returns -1 if BSY/ERR set or command failed
;
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
	bsr	_IDECmd
	bsr	WaitReady
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

;--- send command ------------------------------------------
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

	bsr	ClearWaitSignal
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

;--- _PatternCheck: detect stuck FIFO pattern ---------------
; Checks if IDENTIFY data contains a repeated word pattern
; (stuck data register returning same value for every read).
;
; Input:
;   a0 = pointer to 512-byte IDENTIFY block
;
; Output:
;   d0 = 1 (valid, words differ) or 0 (stuck pattern)
;
_PatternCheck:
	move.w	(a0),d0
	cmp.w	20(a0),d0		;compare Word 0 with Word 10
	bne.s	_pc_ok
	cmp.w	120(a0),d0		;compare Word 0 with Word 60
	bne.s	_pc_ok
	moveq.l	#0,d0			;all three identical = stuck
	rts
_pc_ok:
	moveq.l	#1,d0
	rts

;--- _XORChecksum: XOR checksum of 256-word block -----------
; Computes XOR of all 256 words in a 512-byte block.
;
; Input:
;   a0 = pointer to 512-byte block
;
; Output:
;   d0 = XOR of all 256 words
;
_XORChecksum:
	movem.l	d1-d2/a0,-(sp)
	moveq.l	#0,d0
	move.w	#256-1,d1
_xc_loop:
	move.w	(a0)+,d2
	eor.w	d2,d0
	dbf	d1,_xc_loop
	movem.l	(sp)+,d1-d2/a0
	rts

;--- _ReadIdentify: issue IDENTIFY and read 512 bytes -------
; Sends ATA IDENTIFY DEVICE (or IDENTIFY PACKET DEVICE)
; command and reads 512 bytes into CFU_ConfigBlock.
;
; Input:
;   d5 = command word (e.g. $e0ec for IDENTIFY DEVICE)
;   a3 = CFU pointer
;
; Output:
;   d0 = 1 (success) or 0 (failure)
;
_ReadIdentify:
	clr.l	CFU_IDESet+2(a3)
	move.w	d5,CFU_IDESet+6(a3)
	bsr	_IDECmd
	tst.w	d0
	beq.s	_ri_fail
	bsr	WaitReady
	moveq.l	#$29,d0			;DF, DRQ, ERR
	and.b	CFU_IDEStatus(a3),d0
	subq.b	#8,d0			;DRQ
	bne.s	_ri_fail
	lea	CFU_ConfigBlock(a3),a2
	moveq.l	#512>>8,d0
	lsl.l	#8,d0
	bsr	_pio_in
	moveq.l	#1,d0
	rts
_ri_fail:
	moveq.l	#0,d0
	rts

;--- read drive configuration ------------------------------
; Identify the connected ATA/ATAPI device.
;
; Input:
;   a3 = CFU pointer
;
; Output:
;   d0 = device type:
;        0 = no device / error / IDENTIFY timeout
;        1 = ATA device (CompactFlash or fixed disk)
;        2 = ATAPI device (CD-ROM, DVD, etc.)
;
; Caller contract:
;   In the default -atapi build the pre-IDENTIFY task-file
;   signature check in _t_itest rejects ATAPI cards before this
;   routine runs, so d0=2 here is the residual safety-net case.
;   _t_itest redirects d0=2 to _t_identify_failed (ReleaseCard)
;   in -atapi builds; only +atapi builds route to _t_iatapi.
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
;   1. Send IDENTIFY DEVICE ($EC)
;   2. Wait for DRQ, retry up to 32 times for slow adapters
;   3. If DRQ never sets, fall back to IDENTIFY PACKET DEVICE
;      ($A1) as a final attempt to elicit any response from the
;      card. See _gid_check_retry for the rationale.
;   4. Read 512-byte identify data
;   5. Parse device type and set unit parameters
;
_GetIDEID:
	movem.l	d2-d6/a2,-(sp)
	DBGMSG	dbg_id_get		;"[CFD] Getting IDE ID"

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
	bsr	_IDEStart
	move.w	#$e0ec,d5		;LBA, drive #0, IDENTIFY DEVICE
	moveq.l	#0,d3			;the read mode
_gid_command:
	move.w	d3,CFU_ReceiveMode(a3)
	clr.l	CFU_IDESet+2(a3)
	move.w	d5,CFU_IDESet+6(a3)
	bsr	_IDECmd
	tst.w	d0
	beq.w	_gid_error
	
	bsr	WaitReady
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
	bsr	_pio_in			;read data
	move.l	CFU_IDEAddr(a3),a0
	move.l	#A_Pb,a1
	moveq.l	#120,d1
_gid_wait:
	bsr	Wait1
	move.b	14(a0),d0
	bpl.s	_gid_done

	subq.w	#1,d1
	bgt.s	_gid_wait
_gid_done:
	btst	#3,d0
	beq.s	_gid_found		;that is all, OK

	move.w	#$e000,CFU_IDESet+6(a3)	;NOP
	bsr	_IDECmd			;abort
	bsr	WaitReady
	cmp.b	#3,d3
	bgt.s	_gid_break
	beq.s	_gid_switch

	add.w	#$0101,d3		;try different read mode
	bra.w	_gid_command
_gid_switch:
	bsr	_IDEStop
	move.w	#$0404,d3
	move.w	d3,CFU_ReceiveMode(a3)
	move.l	CFU_ConfigAddr(a3),a0
	move.b	#$40,(a0)
	bsr	Wait40
	move.l	CFU_MemPtr(a3),CFU_IDEAddr(a3)
	bsr	_IDEStart
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
	beq.w	_gid_timeout

	; Step 1: Check for stuck FIFO
	lea	CFU_ConfigBlock(a3),a0
	bsr	_PatternCheck
	tst.w	d0
	beq.s	_gid_stuck

	; Step 2: XOR checksum of first read
	lea	CFU_ConfigBlock(a3),a0
	bsr	_XORChecksum
	move.w	d0,d4			;save checksum

	; Step 3: Second read for verification
	bsr	_ReadIdentify
	tst.w	d0
	beq.s	_gid_verify_fail

	; Step 4: XOR checksum of second read and compare
	lea	CFU_ConfigBlock(a3),a0
	bsr	_XORChecksum
	cmp.w	d4,d0
	beq.s	_gid_verified

_gid_verify_fail:
	DBGMSG	dbg_id_mismatch
	moveq.l	#0,d2
	bra.w	_gid_end

_gid_stuck:
	ifd	DEBUG
	lea	CFU_ConfigBlock(a3),a0
	move.w	(a0),d0
	move.w	d0,-(sp)
	DBGMSG	dbg_id_garbage
	move.w	(sp)+,d0
	bsr	_DebugHexWord
	DBGMSG	dbg_id_garbage_end
	endc
	moveq.l	#0,d2
	bra.w	_gid_end

_gid_verified:
	lea	CFU_ConfigBlock(a3),a0
	move.w	#512/2,d2
_gid_swap:
	move.w	(a0),d0
	rol.w	#8,d0
	move.w	d0,(a0)+		;..byte order
	subq.w	#1,d2
	bgt.s	_gid_swap

_gid_valid:
	cmp.w	#$a0a1,d5
	beq.s	_gid_atapi

	move.l	CFU_ConfigBlock+120(a3),d0
	swap	d0
	move.l	d0,CFU_DriveSize(a3)
	moveq.l	#1,d2			;ATA OK
	DBGMSG	dbg_id_done_pre
	DBGMSG	dbg_id_ata
	DBGMSG	dbg_id_done_post
	bra.w	_gid_end
_gid_atapi:
	moveq.l	#12,d1
	moveq.l	#3,d0
	and.w	CFU_ConfigBlock(a3),d0
	beq.s	_gid_a1

	moveq.l	#16,d1
_gid_a1:
	move.w	d1,CFU_PLength(a3)	;set ATAPI command length
	moveq.l	#2,d2			;ATAPI OK
	DBGMSG	dbg_id_done_pre
	DBGMSG	dbg_id_atapi
	DBGMSG	dbg_id_done_post
	bra.w	_gid_end

;--- Retry for slow adapters ---
; When DRQ does not set after IDENTIFY DEVICE, retry up to 32
; times with a Wait40 delay between attempts. This catches
; SD-to-CF adapters that need extra settle time after card
; insertion.
_gid_check_retry:
	subq.l	#1,d6
	beq.w	_gid_break		;retries exhausted, final $A1 attempt
	bsr	Wait40			;delay before retry
	bra.w	_gid_retry

_gid_timeout:
	DBGMSG	dbg_id_done_pre
	DBGMSG	dbg_id_timeout
	DBGMSG	dbg_id_done_post
_gid_end:
	bsr	_IDEStop
	bsr	_BindIOHandlers		;probe settled, rebind handlers
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
;   d7 = MOVEM loop counter
;   a2 = buffer pointer
;
; Notes:
;   - Uses READ SECTORS ($21) for single-sector transfers
;   - Uses READ MULTIPLE ($C4) for multi-sector transfers
;   - Handles ATAPI via SCSI path (_rb_scsi)
;   - Retries up to 5 times on error
;
_ReadBlocks:
	movem.l	d2-d7/a2/a5,-(sp)
	move.l	a1,a2			;&buffer
	move.l	d0,d2			;Block #
	move.l	d1,d3			;total bytes
	move.l	d1,d5
	beq.w	_rb_ready		;nothing to do

	ifd	ATAPI
	tst.w	CFU_PLength(a3)
	bgt.w	_rb_scsi
	endc

	bsr	_IDEStart
_rb_swath:
	move.w	#5,CFU_Try(a3)
	move.l	d2,CFU_Block(a3)
	move.l	d3,CFU_Count(a3)
	move.l	a2,CFU_Buffer(a3)
_rb_try:
	move.l	CFU_ReadBlockFn(a3),a5	;cache bound handler across chunk loop
	move.l	a5,d0			;handler bound? (_BindIOHandlers ran?)
	beq.w	_rb_nodisk		;NULL -> fail IO as "disk changed"
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
	move.b	d4,(a0)+		;Sectors
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
	bsr	_IDECmd
	tst.w	d0
	beq.w	_rb_nodisk
_rb_block:
	cmp.l	d6,d4
	bcc.s	_rb_2

	move.l	d4,d6
_rb_2:
	bsr	WaitReady
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.w	_rb_nodisk		;card removed

	moveq.l	#$ffffffa9,d0		;BSY, DWF, DRQ, ERR
	and.b	CFU_IDEStatus(a3),d0
	subq.b	#8,d0			;DRQ
	bne.w	_rb_break

	move.l	d6,d0
	lsl.l	#8,d0			;bytes = blocks * 512
	add.l	d0,d0			;final *2 via add.l (faster than lsl.l #1)
	jsr	(a5)			;dispatch via a5-cached handler (pi_modeN)
_rb_lnext:
	add.l	d6,d2
	sub.l	d6,d3
	sub.l	d6,d4
	bgt.w	_rb_block

	tst.l	d3
	bgt.w	_rb_swath
_rb_stop:
	move.l	CFU_IDEAddr(a3),a0
	move.l	a0,d0
	beq.s	_rb_skip_status		;skip if IDEAddr is NULL
	move.b	14(a0),CFU_IDEStatus(a3)
_rb_skip_status:
	bsr	_IDEStop
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
	movem.l	(sp)+,d2-d7/a2/a5
	rts

_rb_break:
	move.b	#TDERR_NOSECHDR,CFU_IOErr(a3)
	bsr	_IDEError
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

	ifd	ATAPI
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
	add.l	d0,d0			;*2 via add.l (faster than lsl.l #1)
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
	bsr	_Packet
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
	endc

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
	cmp.b	#4,d1			;mode in 0..4?
	bls.s	pi_ok
	moveq.l	#0,d1			;out-of-range -> safe default (WORD mode)
pi_ok:
	add.l	d1,d1			;*2 via add.l (faster than lsl.l #1)
	lea	pi_tab(pc),a1
	add.w	(a1,d1.w),a1		;d1 high bits cleared above, .w is 68000-safe
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
	move.l	CFU_DataPort(a3),a0
	cnop	0,4
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
	move.l	CFU_DataPort(a3),a0
	cnop	0,4
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
	move.l	CFU_DataPort(a3),a0
	move.l	a0,a1
	add.l	#$10001,a1
	cnop	0,4
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
	move.l	CFU_DataPort(a3),a0
	cnop	0,4
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
	cnop	0,4
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
; Conditionally compiled out of the default build: this helper has no
; callers because _BindIOHandlers wires the appropriate po_modeN
; routine directly into CFU_WriteBlockFn (cached on the CFU), bypassing
; the po_tab indirection on the write side. Build with -DDEADCODE to
; revive.
	ifd	DEADCODE
_pio_out:
	moveq.l	#0,d1
	move.b	CFU_SendMode(a3),d1
	cmp.b	#4,d1			;mode in 0..4?
	bls.s	po_ok
	moveq.l	#0,d1			;out-of-range -> safe default (WORD mode)
po_ok:
	lsl.l	#1,d1
	lea	po_tab(pc),a1
	add.w	(a1,d1.w),a1		;d1 high bits cleared above, .w is 68000-safe
	jmp	(a1)
po_tab:
	dc.w	po_mode0-po_tab
	dc.w	po_mode1-po_tab
	dc.w	po_mode2-po_tab
	dc.w	po_mode1-po_tab
	dc.w	po_mode4-po_tab
	endc

; I/O Register 8, word-wise
po_mode0:
	lsr.l	#4,d0
	subq.l	#1,d0
	move.l	CFU_DataPort(a3),a0
	cnop	0,4
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
	move.l	CFU_DataPort(a3),a0
	cnop	0,4
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
	move.l	CFU_DataPort(a3),a0
	move.l	a0,a1
	add.l	#$10001,a1
	cnop	0,4
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
	cnop	0,4
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

;--- _BindIOHandlers --------------------------------------
; Specialize the hot read/write block dispatch for the current
; CFU_ReceiveMode / CFU_SendMode so that _rb_block and _wb_block
; can jsr the selected worker directly without per-block mode
; checks or pi_tab/po_tab dispatch.
;
; Must be called once after mode probing settles and re-called
; from every later site that changes CFU_ReceiveMode or
; CFU_SendMode:
;   - end of RWTest
;   - _gid_end (covers _gid_switch's mode-4 fallback)
;   - _wb_switch (mid-write fallback to memory-mapped mode)
;   - _wb_bump fallback step (try next send mode)
;
; Dispatch flow:
;
;   COLD (on every mode change, rare):
;     _BindIOHandlers
;       -> CFU_ReadBlockFn  := pi_modeN
;       -> CFU_WriteBlockFn := po_modeN
;
;   HOT (per IO request, per block):
;     _rb_try / _wb_try:
;       a5 := CFU_*BlockFn(a3)        ; cached once, outside chunk loop
;     _rb_block / _wb_block:
;       jsr (a5)                      ; direct call, no mode read
;       -> pi_modeN / po_modeN worker
;
;   (pi_tab / po_tab are used only by the cold _pio_in / _pio_out
;   helpers for IDENTIFY / config reads, not by the block hot path.)
;
; Clobbers: d0, a0, a1 (callers must save anything live).
;
_BindIOHandlers:
	moveq.l	#0,d0
	move.b	CFU_ReceiveMode(a3),d0
	add.w	d0,d0
	lea	rb_handler_tab(pc),a0
	move.l	a0,a1
	add.w	(a0,d0.w),a1
	move.l	a1,CFU_ReadBlockFn(a3)

	moveq.l	#0,d0
	move.b	CFU_SendMode(a3),d0
	add.w	d0,d0
	lea	wb_handler_tab(pc),a0
	move.l	a0,a1
	add.w	(a0,d0.w),a1
	move.l	a1,CFU_WriteBlockFn(a3)
	rts

; Word-offset tables (PC-relative, matches pi_tab/po_tab style).
; Indexed by CFU_ReceiveMode / CFU_SendMode (0..4).
rb_handler_tab:
	dc.w	pi_mode0-rb_handler_tab
	dc.w	pi_mode1-rb_handler_tab
	dc.w	pi_mode2-rb_handler_tab
	dc.w	pi_mode3-rb_handler_tab
	dc.w	pi_mode4-rb_handler_tab

wb_handler_tab:
	dc.w	po_mode0-wb_handler_tab
	dc.w	po_mode1-wb_handler_tab
	dc.w	po_mode2-wb_handler_tab
	dc.w	po_mode1-wb_handler_tab		;mode 3 folds to mode 1
	dc.w	po_mode4-wb_handler_tab

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
;   d7 = MOVEM loop counter
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
	movem.l	d2-d7/a2/a5,-(sp)
	move.l	a0,a2			;&buffer
	move.l	d0,d2			;Block #
	move.l	d1,d3			;total bytes
	move.l	d1,d5
	beq.w	_wb_ready		;nothing to do

	ifd	ATAPI
	tst.w	CFU_PLength(a3)
	bgt.w	_wb_scsi
	endc

	bsr	_IDEStart
	tst.l	CFU_DriveSize(a3)
	beq.w	_wb_nodisk
_wb_swath:
	move.w	#5,CFU_Try(a3)
	move.l	d2,CFU_Block(a3)
	move.l	d3,CFU_Count(a3)
	move.l	a2,CFU_Buffer(a3)
_wb_try:
	move.l	CFU_WriteBlockFn(a3),a5	;cache bound handler across chunk loop
	move.l	a5,d0			;handler bound? (_BindIOHandlers ran?)
	beq.w	_wb_nodisk		;NULL -> fail IO as "disk changed"
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
	move.b	d4,(a0)+		;Sectors
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
	bsr	_IDECmd
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

_wb_w3:
	cmp.l	d6,d4
	bcc.s	_wb_w4

	move.l	d4,d6
_wb_w4:
	move.l	d6,d0
	lsl.l	#8,d0			;bytes = blocks * 512
	add.l	d0,d0			;final *2 via add.l (faster than lsl.l #1)
	jsr	(a5)			;dispatch via a5-cached handler (po_modeN)
_wb_lnext:
	bsr	WaitReady
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
	bsr	_IDEStop
_wb_ready:
	move.l	a2,a0
	move.l	d5,d0
	sub.l	d3,d0
	movem.l	(sp)+,d2-d7/a2/a5
	rts

_wb_erase:
	move.b	#$c0,d0			;"CFA ERASE SECTORS"
	move.w	d0,(a0)
	bsr	_IDECmd
	tst.w	d0
	beq.s	_wb_nodisk

	bsr	WaitReady
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.s	_wb_nodisk		;card removed

	moveq.l	#$ffffffa9,d0		;BSY, DWF, DRQ, ERR
	and.b	CFU_IDEStatus(a3),d0
	beq.s	_wb_eok
_wb_eerror:
	move.b	#IOERR_NOCMD,CFU_IOErr(a3)
	bsr	_IDEError
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
	bsr	_IDECmd			;abort
	bsr	WaitReady
	move.b	CFU_SendMode(a3),d0
	cmp.b	#3,d0
	bgt.s	_wb_break
	beq.s	_wb_switch

	addq.b	#1,CFU_SendMode(a3)	;try different transfer mode
	bsr	_BindIOHandlers		;rebind for new send mode
	bra.s	_wb_break
_wb_switch:
	bsr	_IDEStop
	move.w	#$0404,CFU_ReceiveMode(a3)
	bsr	_BindIOHandlers		;rebind for memory-mapped mode
	move.l	CFU_ConfigAddr(a3),a0
	move.b	#$40,(a0)
	bsr	Wait40
	move.l	CFU_MemPtr(a3),CFU_IDEAddr(a3)
	bsr	_IDEStart
_wb_break:
	move.b	#TDERR_NOSECHDR,CFU_IOErr(a3)
	bsr	_IDEError
	addq.l	#1,CFU_WriteErrors(a3)
	subq.w	#1,CFU_Try(a3)
	beq.w	_wb_stop

	clr.b	CFU_IOErr(a3)
	move.l	CFU_Block(a3),d2
	move.l	CFU_Count(a3),d3
	move.l	CFU_Buffer(a3),a2
	bra.w	_wb_try

	ifd	ATAPI
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
	add.l	d0,d0			;*2 via add.l (faster than lsl.l #1)
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
	bsr	_Packet
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
	endc

;--- set fast transfer mode --------------------------------
;d0 -> Blocks/Interrupt

_InitMultipleMode:
	bsr	_IDEStart
	moveq.l	#0,d1
	move.b	CFU_ConfigBlock+95(a3),d1	;word 47 bits 15:8 = MaxMulti count
	ifd	DEBUG
	move.l	d1,-(sp)
	DBGMSG	dbg_multimax
	move.l	(sp),d0
	bsr	_DebugDecimal
	bsr	_DebugNewline
	move.l	(sp)+,d1
	endc
	tst.b	d1
	beq.w	_imm_nosup		;0 = not supported

	ifd	DEBUG
	move.l	d1,-(sp)
	DBGMSG	dbg_multiset
	move.l	(sp),d0
	bsr	_DebugDecimal
	move.l	(sp)+,d1
	endc
	lea	CFU_IDESet+2(a3),a0
	lsl.w	#8,d1
	move.w	d1,(a0)+
	moveq.l	#0,d1
	move.w	d1,(a0)+
	move.w	#$e0c6,(a0)		;"SET MULTIPLE MODE"
	bsr	_IDECmd
	tst.w	d0
	beq.w	_imm_error

	bsr	WaitReady
	moveq.l	#3,d1
	and.b	CFU_EventFlags(a3),d1
	bne.w	_imm_error		;card removed

	moveq.l	#$21,d1
	and.b	CFU_IDEStatus(a3),d1
	bne.w	_imm_error		;error or unsupported

	DBGMSG	dbg_multiok		;", OK"

	bsr	_IDEStop
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
	bsr	_TestMultiSectorIssue
	tst.b	d0
	bne.s	_imm_rw_drq_issue		;DRQ issue detected, use firmware value
	DBGMSG	dbg_multi_ovr_ok
	move.w	#256,CFU_MultiSizeRW(a3)	;auto-detected: card works, use 256
	bra.s	_imm_rw_debug

_imm_rw_skip_auto:
	DBGMSG	dbg_multi_ovr_skip
	ifd	DEBUG
	bra.s	_imm_rw_firmware
	endc

_imm_rw_drq_issue:
	DBGMSG	dbg_multi_ovr_fail
	;fall through to _imm_rw_firmware

_imm_rw_firmware:
	moveq.l	#0,d0
	move.w	CFU_MultiSize(a3),d0
	move.w	d0,CFU_MultiSizeRW(a3)		;use firmware value
_imm_rw_debug:
	ifd	DEBUG
	move.l	d0,-(sp)
	DBGMSG	dbg_multirw
	moveq.l	#0,d0
	move.w	CFU_MultiSizeRW(a3),d0
	bsr	_DebugDecimal
	bsr	_DebugNewline
	move.l	(sp)+,d0
	endc
	rts

_imm_nosup:
	DBGMSG	dbg_multinosup
	moveq.l	#1,d0			;default to single blocks
	bra.w	_imm_end

_imm_error:
	DBGMSG	dbg_multifail		;", FAILED" (appends to set multi line)
	ifd	DEBUG
	moveq.l	#0,d0
	move.b	CFU_IDEStatus(a3),d0
	bsr	_DebugIDEStatus		;show what went wrong
	endc
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

	;--- Start IDE access ---
	bsr	_IDEStart

	;--- Issue READ SECTORS command for LBA 0, 1 sector ---
	lea	CFU_IDESet+2(a3),a0
	move.w	#$0100,(a0)+		;1 sector, LBA bits 7:0 = 0
	clr.w	(a0)+			;LBA bits 23:8 = 0
	move.w	#$e020,(a0)		;LBA mode, drive 0, READ SECTORS ($20)
	bsr	_IDECmd
	tst.w	d0
	beq.s	_tms_ok			;command failed, assume card works

	;--- Wait for DRQ ---
	bsr	WaitReady
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.s	_tms_ok			;card removed, assume ok

	moveq.l	#$29,d0			;DF, DRQ, ERR
	and.b	CFU_IDEStatus(a3),d0
	subq.b	#8,d0			;DRQ?
	bne.s	_tms_ok			;no DRQ, assume card works

	;--- Read 512 bytes (discard data) ---
	;Uses word reads, 256 iterations of 1 word = 512 bytes
	move.l	CFU_DataPort(a3),a0	;IDE data register
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
	bsr	_IDEStop
	moveq.l	#1,d0			;return 1 = issue, use firmware value
	bra.s	_tms_end

_tms_ok:
	bsr	_IDEStop
	moveq.l	#0,d0			;return 0 = card works, use 256
_tms_end:
	movem.l	(sp)+,d1-d2/a0-a1
	rts

;--- PIO Mode to Memory Timing Mapping ---------------------
; Compile-time option: GTIMING
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
	ifd	GTIMING
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
	bsr	_DebugDecimal
	DBGMSG	dbg_gayle_speed
	move.l	(sp),d0			;Gayle speed (d0)
	bsr	_DebugDecimal
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
	bsr	_ops_bits_to_ns		;convert to nanoseconds
	bsr	_DebugDecimal
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
	bsr	_ops_bits_to_ns		;convert to nanoseconds
	bsr	_DebugDecimal
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
	bsr	_ops_bits_to_ns		;convert to nanoseconds

_ops_show_actual:
	ifd	DEBUG
	;d0 = actual speed selected by hardware
	move.l	d0,-(sp)
	DBGMSG	dbg_gayle_actual
	move.l	(sp)+,d0
	bsr	_DebugDecimal
	DBGMSG	dbg_ns
	endc
_ops_end:
	rts
	else
	;GTIMING not compiled - read and show current Gayle speed
	ifd	DEBUG
	DBGMSG	dbg_gayle_timing
	DBGMSG	dbg_gayle_current
	move.l	#$00DAB000,a0
	moveq.l	#0,d0
	move.b	(a0),d0
	and.b	#$0C,d0			;mask speed bits 2-3
	bsr	_ops_bits_to_ns		;convert to nanoseconds
	bsr	_DebugDecimal
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
	bsr	_IDEStart
	move.l	CFU_IDEAddr(a3),a0
	move.l	#A_Pb,a1
	tst.b	(a1)
	nop
_su_wait:
	tst.b	(a1)
	nop
	move.b	7(a0),d0
	bmi.s	_su_wait		;BSY

	move.b	#7,13(a0)		;Subcommand "Spin Up"
	move.b	#$ef,7(a0)		;SET FEATURES
	bsr	WaitReady
	move.b	CFU_IDEStatus(a3),d0
	bra.w	_IDEStop

	ifd	ATAPI
;--- query Disk Status -------------------------------------
; d0 -> -1 (error), 0 (no disk), 1 (inserted), 2 (new Disk)

_MediaStatus:
	move.l	d2,-(sp)
	moveq.l	#-1,d2
	bsr	_IDEStart
	move.l	CFU_IDEAddr(a3),a0
	move.b	7(a0),d0
	and.b	#$c0,d0			;BSY, DRDY
	cmp.b	#$40,d0			;DRDY
	bne.s	_ms_end

	move.b	#$da,7(a0)		;"GET MEDIA STATUS"
	bsr	WaitReady
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
	bsr	_IDEStop
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

	bsr	_IDEStart
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

	bsr	ClearWaitSignal
	and.b	#$df,CFU_EventFlags(a3)	;Interrupt response ON
	lea	CFU_Packet(a3),a0
	move.w	CFU_PLength(a3),d1
_p_packet:
	move.w	(a0)+,(a2)		;send command line
	subq.w	#2,d1
	bgt.s	_p_packet
_p_data:
	tst.l	d6
	bmi.w	_p_abort

	bsr	WaitReady
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
	bsr	_IDEStop
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
	bsr	_MediaStatus
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
	bsr	_Packet
	moveq.l	#0,d1
	tst.b	d0
	bne.s	as_end

	move.l	CFU_ConfigBlock+508(a3),d1
	move.l	d1,CFU_BlockSize(a3)
	move.l	d1,d0
	LOG2
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
	bsr	ATAPISize
	move.l	CFU_DriveSize(a3),d1
	cmp.l	d0,d1
	beq.s	ap_time			;still all the same

	move.l	d0,CFU_DriveSize(a3)
	bsr	NotifyClients
ap_time:
	lea	CFU_TimeReq(a3),a1
	move.w	#TR_ADDREQUEST,IO_Command(a1)
	moveq.l	#1,d0
	move.l	d0,TR_Seconds(a1)
	clr.l	TR_Micros(a1)
	CALLEXEC SendIO
ap_end:
	rts
	endc
	cnop	0,4

s_codeend:

;*** that's it!!!! *****************************************
	end
