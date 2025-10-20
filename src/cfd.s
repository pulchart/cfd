; compactflash.device driver V1.32
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

;compactflash.device v1.32
;TJ. 14.11.2009

FILE_VERSION	= 1
FILE_REVISION	= 32

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

;struct CompactFlashDevice
CFD_ExecBase	= 36			;LIB_Sizeof + 2
CFD_DosBase	= 40
CFD_CardBase	= 44
CFD_SegList	= 48
CFD_Unit	= 52
CFD_Sizeof	= 56

;struct CompactFlashUnit
CFU_Flags	= 38			;UN_Sizeof
CFU_Device	= 40

CFU_UnitSize	= 44			;help cfddebug
CFU_ResVersion	= 48
CFU_ResRev	= 50
CFU_Debug	= 52
CFU_ActiveHacks	= 54
CFU_ReadErrors	= 56
CFU_WriteErrors	= 60

CFU_TimeReq	= 64

CFU_Process	= 104
CFU_CardSig	= 108
CFU_Signals2	= 112			;timer, card
CFU_Signals3	= 116			;timer, card, ioreq
CFU_CardHandle	= 120
CFU_InsertInt	= 148
CFU_RemoveInt	= 172
CFU_StatusInt	= 196
CFU_EventFlags	= 220
CFU_IOErr	= 221
CFU_IDEStatus	= 222
CFU_IDEError	= 223
CFU_MemPtr	= 224
CFU_AttrPtr	= 228
CFU_IOPtr	= 232
CFU_MultiSize	= 236
CFU_OpenFlags	= 238
CFU_DTSize	= 240			;struct DeviceTData
CFU_DTSpeed	= 244
CFU_DTType	= 248
CFU_DTFlags	= 249
CFU_CardReady	= 250			;0 during recognition/initialization
CFU_Clients	= 252			;struct List
CFU_Request	= 264
CFU_DriveSize	= 268
CFU_BlockSize	= 272
CFU_Block	= 276
CFU_Count	= 280
CFU_Buffer	= 284
CFU_Try		= 288
CFU_SCSIState	= 290
CFU_ConfigAddr	= 292
CFU_RWFlags	= 296
CFU_BlockShift	= 298
CFU_ReadMode	= 300
CFU_WriteMode	= 301
CFU_ReceiveMode	= 302
CFU_SendMode	= 303
CFU_WatchInt	= 304
CFU_WatchTimer	= 328
CFU_IDESense	= 330
CFU_unused2	= 331
CFU_OKInts	= 332
CFU_FastInts	= 336
CFU_LostInts	= 340
CFU_IDEAddr	= 344
CFU_IDESet	= 348
CFU_SCSIStruct	= 356
CFU_PLength	= 386
CFU_Packet	= 388

CFU_ConfigBlock	= 404

CFU_TimePort	= 916

CFU_KillSig	= 952
CFU_KillTask	= 956
CFU_CacheFlags	= 960

CFU_Sizeof	= 964


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
	dc.b	`compactflash.device`,0
	dc.b	`$VER: `
s_idstring:
	dc.b	`compactflash.device 1.32 (14.11.2009)`,LF,0
	dc.b	`� Torsten Jager`,0
CardName:
	dc.b	`card.resource`,0
TimerName:
	dc.b	`timer.device`,0
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
	dc.w	`TJ`
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

	cmp.b	#` `,d0
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
	move.b	(a0)+,(a1)+		;Spezific Information
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

;*** Test **************************************************

_DEBUG	macro
	moveq.l	#\1,d0
	bsr.w	_Debug
	endm

_Debug:
;	movem.l	d0-d1/a0-a1,-(sp)
;	move.l	#$02000000,a1
;	move.l	d0,(a1)+
;	move.l	a3,a0
;	move.w	#CFU_Sizeof/4,d0
;_d_loop:
;	move.l	(a0)+,(a1)+
;	subq.w	#1,d0
;	bgt.s	_d_loop

;	movem.l	(sp)+,d0-d1/a0-a1
;	rts

Wait40:
	lea	CFU_TimeReq(a3),a1
	move.w	#TR_ADDREQUEST,IO_Command(a1)
	moveq.l	#0,d0
	move.l	d0,TR_Seconds(a1)
	move.l	#40000,TR_Micros(a1)	;wait 40 ms
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
	clr.w	CFU_CardReady(a3)
	lea	CFU_CardHandle(a3),a2
	move.l	a2,a1
	CALLCARD ReadCardStatus
	and.b	#CARD_STATUSF_CCDET,d0
	beq.w	_t_ibreak		;false alert

	clr.w	CFU_Debug(a3)
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
	addq.w	#1,CFU_Debug(a3)
	moveq.l	#30,d2
_t_i1:
	subq.w	#1,d2
	bmi.s	_t_i2			;Timeout

	bsr.w	Wait40			;..or go on waiting
	moveq.l	#3,d0
	and.b	CFU_EventFlags(a3),d0
	bne.w	_t_ibreak

	move.l	a2,a1
	CALLCARD ReadCardStatus
	and.b	#CARD_STATUSF_BSY,d0
	bne.s	_t_i1			;card ready after resetting..
_t_i2:
	addq.w	#1,CFU_Debug(a3)
	bsr.w	ConfigureHBA
	addq.w	#1,CFU_Debug(a3)
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

	add.w	#16,CFU_Debug(a3)
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
	addq.w	#1,CFU_Debug(a3)
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

	addq.w	#1,CFU_Debug(a3)
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
	addq.w	#1,CFU_Debug(a3)
	moveq.l	#CARD_VOLTAGE_5V,d0
	move.l	a2,a1
	CALLCARD CardProgramVoltage

	addq.w	#1,CFU_Debug(a3)
	lea	CFU_ConfigBlock(a3),a0
	move.l	a2,a1
	moveq.l	#$1a,d1			;CISTPL_CONFIG
	moveq.l	#127,d0
	CALLSAME CopyTuple
	tst.w	d0
	beq.w	_t_ibreak

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
	beq.w	_t_ibreak		;Hack #2 deaktivated..

	moveq.l	#$200>>3,d2		;..or try again without CIS
	lsl.l	#3,d2
	or.w	#1<<8,CFU_ActiveHacks(a3)
_t_faddr:
	cmp.l	#$00020000,d2
	bcc.w	_t_ibreak		;address out of range

	addq.w	#1,CFU_Debug(a3)
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
	and.b	#$a0,d0			;BSY, DWF
	beq.s	_t_itest

	btst	#0,CFU_ActiveHacks(a3)
	bne.s	_t_ibreak
	bra.s	_t_inodisk		;ATA removable media???
_t_itest:
	bsr.w	RWTest			;find a working transfer mode
	addq.w	#1,CFU_Debug(a3)
	bsr.w	_GetIDEID		;read ATA Konfiguration block
	move.l	d0,d2
	beq.s	_t_inodisk

	btst	#6,CFU_ConfigBlock+167(a3)
	beq.s	_t_i6

	addq.w	#1,CFU_Debug(a3)
	bsr.w	_SpinUp			;try waking up the drive..
	moveq.l	#0,d2
_t_i6:
	btst	#2,CFU_ConfigBlock+1(a3)
	beq.s	_t_i7

	addq.w	#2,CFU_Debug(a3)
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

	addq.w	#1,CFU_Debug(a3)
	bsr.w	_InitMultipleMode
	bra.s	_t_iok
_t_iatapi:
	bsr.w	ATAPIPoll		;start monitoring media removals
	bra.s	_t_iok
_t_inodisk:
	clr.l	CFU_DriveSize(a3)
_t_iok:
	addq.w	#1,CFU_Debug(a3)
	bsr.w	NotifyClients
	addq.w	#1,CFU_Debug(a3)
	bra.w	_t_check

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
	clr.l	CFU_DriveSize(a3)
	clr.w	CFU_PLength(a3)
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
	dc.b	`FREECOM`,0
_t_fcstr2:
	dc.b	`PCCARD-IDE`,0
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
	beq.s	_cfdf_end		;deaktivated

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
	beq.s	_so_end			;aktive already

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
; d0 -> 1 (OK)

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

_GetIDEID:
	movem.l	d2-d5/a2,-(sp)
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
	bne.s	_gid_break

	lea	CFU_ConfigBlock(a3),a2
	moveq.l	#512>>8,d0
	lsl.l	#8,d0
	bsr.w	_pio_in			;read data
	move.l	CFU_IDEAddr(a3),a0
	move.l	#A_Pb,a1
	moveq.l	#120,d1
	tst.b	(a1)
	nop
_gid_wait:
	tst.b	(a1)
	nop
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
	bra.s	_gid_command
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
_gid_end:
	bsr.w	_IDEStop
	move.l	d2,d0
	movem.l	(sp)+,d2-d5/a2
	rts

;--- read Blocks -------------------------------------------
; d0 <- Block #
; d1 <- byte count
; a1 <-> &buffer
; d0 -> bytes read

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

	moveq.l	#1,d4
	lsl.l	#8,d4
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
	bne.s	_rb_break

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
	move.b	14(a0),CFU_IDEStatus(a3)
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
; d0 <-  # Bytes
; a2 <-> &buffer

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
; d0 <-  # Bytes
; a2 <-> &buffer

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
; d0 <- Block #
; d1 <- bytes to write
; a0 <-> &buffer or -1 ("erase only)"
; d0 -> bytes written

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
	moveq.l	#1,d4
	lsl.l	#8,d4
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
	move.b	CFU_ConfigBlock+95(a3),d1
	ble.s	_imm_error		;not supported

	lea	CFU_IDESet+2(a3),a0
	lsl.w	#8,d1
	move.w	d1,(a0)+
	moveq.l	#0,d1
	move.w	d1,(a0)+
	move.w	#$e0c6,(a0)		;"SET MULTIPLE MODE"
	bsr.w	_IDECmd
	tst.w	d0
	beq.s	_imm_error

	bsr.w	WaitReady
	moveq.l	#3,d1
	and.b	CFU_EventFlags(a3),d1
	bne.s	_imm_error		;card removed

	moveq.l	#$21,d1
	and.b	CFU_IDEStatus(a3),d1
	bne.s	_imm_error		;error or unsupported

	moveq.l	#0,d0
	move.b	CFU_ConfigBlock+95(a3),d0
_imm_end:
	move.w	d0,CFU_MultiSize(a3)
	bsr.w	_IDEStop
	move.w	CFU_MultiSize(a3),d0
	rts

_imm_error:
	moveq.l	#1,d0			;default to single blocks
	bra.s	_imm_end

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
; d0 -> -1 (erro), 0 (no disk), 1 (inserted), 2 (new Disk)

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

	add.l	d2,d4			;advane &buffer
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

;*** das war`s!!!! *****************************************
	end
