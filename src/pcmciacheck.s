; pcmciacheck hardware test tool V1.17
; Copyright (C) 2002  Torsten Jager <t.jager@gmx.de>
; This file is part of cfd, a free storage device driver for Amiga.
;
; This tool is free software; you can redistribute it and/or
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

;pcmciacheck 1.17
;TJ. 29.08.2002

FILE_VERSION	= 1
FILE_REVISION	= 17

;--- from exec.library -------------------------------------

CALLEXEC macro
	move.l	S_ExecBase(a4),a6
	jsr	\1(a6)
	endm

CALLSAME macro
	jsr	\1(a6)			;same library as last CALLxxx
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
AllocMem	= -198
FreeMem		= -210
AddHead		= -240
Remove		= -252
AddTask		= -282
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

;Speicher-Typ
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

;Device-Vektoren
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

;--- from dos.library --------------------------------------

CALLDOS	macro
	move.l	S_DosBase(a4),a6
	jsr	\1(a6)
	endm

Open			= -30
Close			= -36
Read			= -42
Write			= -48
Output			= -60
UnloadSeg		= -156
DateStamp		= -192
Delay			= -198
CreateNewProcess	= -498
MatchPatternNoCase	= -972

MODE_OLDFILE		= 1005
MODE_NEWFILE		= 1006
MODE_READWRITE		= 1004

;DOS errors
;0	OK
;103	mo memory
;115	invalid number
;202	object in use
;303	object already exists
;205	unknown channel
;209	unknown DosPacket command
;212	wrong object type
;213	disk not validated
;214	disk read only
;216	directory not empty
;218	disk not mounted
;219	invalid file position
;221	disk full
;222	file protected from deletion
;323	file read only
;225	wrong disk type
;226	no disk
;232	end of directory

;struct DateStamp
DS_Days		=  0
DS_Mins		=  4
DS_Ticks	=  8
DS_Sizeof	= 12

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

;CardMiscControl()
CARD_ENABLEF_DIGAUDIO	= 2
CARD_DISABLEF_WP	= 8
CARD_INTF_SETCLR	= 128		;ab v39
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
CMM_CommonMemSize	= 12		;ab v39
CMM_AttributeMemSize	= 16
CMM_IOMemSize		= 20
CMM_Sizeof		= 24

;--- the hardware brake ------------------------------------

A_Pb		= $bfe101		;Centronics data register

;--- global variables --------------------------------------

S_ExecBase	= 0
S_DosBase	= 4
S_MsgPort	= 8
S_TimeReq	= 44
S_CardMode	= 84
S_ReadMode	= 86
S_ChunkStart	= 88
S_LogFile	= 92
S_WritePattern	= 15*1024

;*** Lets get it on!! **************************************

Start:
	link.w	a5,#-256
	movem.l	d2-d5/a2-a6,-(sp)
	lea	-256(a5),a1
	bsr.w	GetDosParams
	moveq.l	#16*4,d0
	lsl.l	#8,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	move.l	(_AbsExecBase).w,a6
	jsr	AllocMem(a6)
	move.l	d0,a4
	tst.l	d0
	beq.w	s_end

	move.l	(_AbsExecBase).w,S_ExecBase(a4)
	moveq.l	#36,d0
	lea	DosName(pc),a1
	CALLEXEC OpenLibrary
	move.l	d0,S_DosBase(a4)
	beq.w	s_freemem

	tst.l	-256(a5)
	beq.w	s_help

	move.b	#PA_SIGNAL,S_MsgPort+MP_Flags(a4)
	moveq.l	#-1,d0
	CALLEXEC AllocSignal
	move.b	d0,S_MsgPort+MP_SigBit(a4)
	sub.l	a1,a1
	CALLEXEC FindTask
	move.l	d0,S_MsgPort+MP_SigTask(a4)
	lea	S_MsgPort+MP_MsgList(a4),a0
	INITLIST a0
	move.w	#TR_Sizeof,S_TimeReq+MN_Length(a4)
	lea	S_MsgPort(a4),a0
	move.l	a0,S_TimeReq+MN_ReplyPort(a4)
	moveq.l	#UNIT_VBLANK,d0
	moveq.l	#0,d1
	lea	TimerName(pc),a0
	lea	S_TimeReq(a4),a1
	CALLEXEC OpenDevice
	tst.b	d0
	bne.s	s_freetimesig
	bra.w	s_go
s_closetimer:
	lea	S_TimeReq(a4),a1
	CALLEXEC CloseDevice
s_freetimesig:
	moveq.l	#0,d0
	move.b	S_MsgPort+MP_SigBit(a4),d0
	CALLEXEC FreeSignal
s_closedos:
	move.l	S_DosBase(a4),a1
	CALLEXEC CloseLibrary
s_freemem:
	moveq.l	#16*4,d0
	lsl.l	#8,d0
	move.l	a4,a1
	CALLEXEC FreeMem
s_end:
	moveq.l	#0,d0
	movem.l	(sp)+,d2-d5/a2-a6
	unlk	a5
	rts

		dc.b	`$VER: pcmciacheck 1.17 (29.08.2002)`,LF,0
		dc.b	`© Torsten Jager`,0

DosName:	dc.b	`dos.library`,0
TimerName:	dc.b	`timer.device`,0
HelpStr:	dc.b	`Bitte Zieldatei angeben.`,LF,0
NoCardStr:	dc.b	`Keine Karte eingelegt.`,LF,0
NoFileStr:	dc.b	`Kann Protokolldatei nicht öffnen.`,LF,0
TestStr:	dc.b	`Das ist ein Test.`,0
	even

s_go:
	move.b	$00da8000,d0
	btst	#6,d0
	beq.w	s_nocard

;- - prepare logfile  - - - - - - - - - - - - - - - - - - -

	lea	S_LogFile(a4),a2
	move.l	#`FORM`,(a2)+
	addq.l	#4,a2			;to be filled in
	move.l	#`pcc2`,(a2)+

;- - prepare card - - - - - - - - - - - - - - - - - - - - -

	move.l	#$00a00200,a0
	move.b	(a0),S_CardMode(a4)
	move.b	#$01,(a0)

;- - read test  - - - - - - - - - - - - - - - - - - - - - -

	move.b	#-1,S_ReadMode(a4)
	moveq.l	#0,d5
s_readcheck:
	move.l	#`rdc0`,d0
	add.b	d5,d0
	move.l	d0,(a2)+
	addq.l	#4,a2
	move.l	a2,S_ChunkStart(a4)
	move.l	#$00a20000,a3
	move.l	a3,a1
	add.l	#$10000,a1
	move.b	#$e0,6(a3)		;LBA, drive 0
	move.b	#$ec,7(a1)		;"IDENTIFY DEVICE"
	bsr.w	WaitReady
	tst.b	d0
	bmi.s	s_rcnext
s_rcq:
	lea	s_readcode(pc),a0
	move.l	d5,d0
	lsl.l	#1,d0
	add.w	(a0,d0.l),a0
	jsr	(a0)
	move.b	7(a3),d0
	bmi.s	s_rcnext

	btst	#3,d0
	bne.s	s_rcq
s_rcnext:
	move.l	S_ChunkStart(a4),a0
	move.l	a2,d0
	sub.l	a0,d0
	move.l	d0,-(a0)
	cmp.l	#512,d0			;remember the first..
	bne.s	s_rc1

	tst.b	S_ReadMode(a4)
	bpl.s	s_rc1

	move.b	d5,S_ReadMode(a4)	;..working read mode
s_rc1:
	addq.w	#1,d5
	cmp.w	#4,d5
	bcs.s	s_readcheck

	tst.b	S_ReadMode(a4)
	bpl.s	s_rc2

	clr.b	S_ReadMode(a4)
s_rc2:

;- - write test - - - - - - - - - - - - - - - - - - - - - -

	lea	S_WritePattern(a4),a0
	lea	S_WritePattern+3*256(a4),a1
	move.l	#$00010203,d0
	moveq.l	#256/4,d1
s_wcf1:
	move.l	d0,(a0)+
	move.l	d0,-(a1)
	add.l	#$04040404,d0
	subq.w	#1,d1
	bgt.s	s_wcf1

	lea	TestStr(pc),a0
	lea	S_WritePattern+20*16(a4),a1
	bsr.w	StrCopy
	lea	TestStr(pc),a0
	lea	S_WritePattern+3*256+30*16(a4),a1
	bsr.w	StrCopy
	move.l	#`wcln`,(a2)+
	moveq.l	#16,d0
	move.l	d0,(a2)+
	moveq.l	#0,d5
s_writecheck:
	lea	S_WritePattern(a4),a6
	move.l	a3,a1
	add.l	#$10000,a1
	move.b	#1,2(a3)		;1 Block
	move.l	d5,d0
	addq.b	#1,d0
	move.b	d0,3(a1)		;LBA 7:0
	moveq.l	#0,d0
	move.b	d0,4(a3)		;LBA 15:8
	move.b	d0,5(a1)		;LBA 23:16
	move.b	#$e0,6(a3)		;LBA 27:24, drive 0
s_wcready:
	move.b	$00da8000,d0
	btst	#6,d0
	beq.s	s_wcnext		;card removed

	move.b	14(a3),d0
	bmi.s	s_wcready		;BSY

	btst	#6,d0
	beq.s	s_wcready		;DRDY

	move.b	#$31,7(a1)		;"WRITE SECTORS"
s_wcr2:
	move.b	$00da8000,d0
	btst	#6,d0
	beq.s	s_wcnext

	move.b	14(a3),d0
	bmi.s	s_wcr2

	btst	#3,d0
	beq.s	s_wcr2			;DRQ
s_wcq:
	lea	s_writecode(pc),a1
	move.l	d5,d0
	lsl.l	#1,d0
	add.w	(a1,d0.l),a1
	jsr	(a1)
	move.b	14(a3),d0
	bmi.s	s_wcnext

	btst	#3,d0
	bne.s	s_wcq
s_wcnext:
	lea	S_WritePattern(a4),a1
	move.l	a6,d0
	sub.l	a1,d0
	move.l	d0,(a2)+
	bsr.w	WaitReady
	addq.w	#1,d5
	cmp.w	#4,d5
	bcs.w	s_writecheck

	move.l	#`wcda`,(a2)+
	addq.l	#4,a2
	move.l	a2,S_ChunkStart(a4)
	move.l	a3,a1
	add.l	#$10000,a1
	move.b	#4,2(a3)		;4 Blocks
	move.b	#1,3(a1)		;LBA 7:0
	moveq.l	#0,d0
	move.b	d0,4(a3)		;LBA 15:8
	move.b	d0,5(a1)		;LBA 23:16
	move.b	#$e0,6(a3)		;LBA 27:24, drive 0
	move.b	#$21,7(a1)		;"READ SECTORS"
	moveq.l	#4,d5
s_wcblock:
	bsr.w	WaitReady
	tst.b	d0
	bmi.s	s_wcbreak

	move.l	S_LogFile+16(a4),d4
	lsr.w	#8,d4
s_wcbq:
	lea	s_readcode(pc),a1
	moveq.l	#0,d0
	move.b	S_ReadMode(a4),d0
	lsl.l	#1,d0
	add.w	(a1,d0.l),a1
	jsr	(a1)
	subq.w	#1,d4
	bgt.s	s_wcbq

	subq.w	#1,d5
	bgt.s	s_wcblock
s_wcbreak:
	move.l	S_ChunkStart(a4),a0
	move.l	a2,d0
	sub.l	a0,d0
	move.l	d0,-(a0)

;- - reset card - - - - - - - - - - - - - - - - - - - - - -

	move.b	S_CardMode(a4),$00a00200

;- - write log  - - - - - - - - - - - - - - - - - - - - - -

	move.l	-256(a5),d1
	move.l	#MODE_NEWFILE,d2
	CALLDOS	Open
	move.l	d0,d4
	beq.s	s_nofile

	lea	S_LogFile(a4),a0
	move.l	a0,d2
	addq.l	#8,a0
	move.l	a2,d3
	sub.l	a0,d3
	move.l	d3,-(a0)
	addq.l	#8,d3
	move.l	d4,d1
	CALLDOS	Write
	move.l	d4,d1
	CALLDOS	Close
	bra.w	s_closetimer

s_help:
	lea	HelpStr(pc),a0
	bsr.w	ReportError
	bra.w	s_closedos

s_nocard:
	lea	NoCardStr(pc),a0
	bsr.w	ReportError
	bra.w	s_closetimer

s_nofile:
	lea	NoFileStr(pc),a0
	bsr.w	ReportError
	bra.w	s_closetimer

;- - read funktions - - - - - - - - - - - - - - - - - - - -
; a2 <- &buffer
; a3 <- &IORegister

s_readcode:
	dc.w	s_read0-s_readcode
	dc.w	s_read1-s_readcode
	dc.w	s_read2-s_readcode
	dc.w	s_read3-s_readcode

s_read0:
	moveq.l	#(256/16)-1,d0
s_r0:
	move.w	(a3),(a2)+
	move.w	(a3),(a2)+
	move.w	(a3),(a2)+
	move.w	(a3),(a2)+
	move.w	(a3),(a2)+
	move.w	(a3),(a2)+
	move.w	(a3),(a2)+
	move.w	(a3),(a2)+
	dbf	d0,s_r0
	rts

s_read1:
	moveq.l	#(256/16)-1,d0
s_r1:
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	move.b	(a3),(a2)+
	dbf	d0,s_r1
	rts

s_read2:
	lea	8(a3),a0
	move.l	a0,a1
	add.l	#$10001,a1
	moveq.l	#(256/16)-1,d0
s_r2:
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
	dbf	d0,s_r2
	rts

s_read3:
	lea	8(a3),a0
	moveq.l	#(256/16)-1,d0
s_r3:
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	move.b	(a0),(a2)+
	dbf	d0,s_r3
	rts

;- - write funktions  - - - - - - - - - - - - - - - - - - -
; a0 <-> &buffer
; a3 <-  &IORegister

s_writecode:
	dc.w	s_write0-s_writecode
	dc.w	s_write1-s_writecode
	dc.w	s_write2-s_writecode
	dc.w	s_write3-s_writecode

s_write0:
	moveq.l	#(256/16)-1,d0
s_w0:
	move.w	(a6)+,(a3)
	move.w	(a6)+,(a3)
	move.w	(a6)+,(a3)
	move.w	(a6)+,(a3)
	move.w	(a6)+,(a3)
	move.w	(a6)+,(a3)
	move.w	(a6)+,(a3)
	move.w	(a6)+,(a3)
	dbf	d0,s_w0
	rts

s_write1:
	moveq.l	#(256/16)-1,d0
s_w1:
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	move.b	(a6)+,(a3)
	dbf	d0,s_w1
	rts

s_write2:
	lea	8(a3),a0
	move.l	a0,a1
	add.l	#$10001,a1
	moveq.l	#(256/16)-1,d0
s_w2:
	move.b	(a6)+,(a0)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a0)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a0)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a0)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a0)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a0)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a0)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a0)
	move.b	(a6)+,(a1)
	dbf	d0,s_w2
	rts

s_write3:
	lea	8(a3),a1
	moveq.l	#(256/16)-1,d0
s_w3:
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	move.b	(a6)+,(a1)
	dbf	d0,s_w3
	rts

;--- help text ---------------------------------------------
;a0 <- &Text

ReportError:
	movem.l	d2-d3,-(sp)
	move.l	a0,d2
re_count:
	tst.b	(a0)+
	bne.s	re_count

	subq.l	#1,a0
	move.l	a0,d3
	sub.l	d2,d3
	CALLDOS	Output
	move.l	d0,d1
	beq.s	re_end

	CALLDOS	Write
re_end:
	movem.l	(sp)+,d2-d3
	rts

;*** IDE Protokol ******************************************
;--- wait by polling ---------------------------------------
; a3 <- &IORegister
; d0 -> IDE Status or -1

WaitReady:
	move.l	d2,-(sp)
	moveq.l	#100,d2			;30 s
wr_loop:
	moveq.l	#-1,d0
	move.b	$00da8000,d1
	btst	#6,d1
	beq.s	wr_end			;card removed

	subq.w	#1,d2
	ble.s	wr_end			;timeout

	move.b	#$0f,$00a00200+4	;acknowledge new status
	moveq.l	#0,d0
	move.b	14(a3),d0
	bpl.s	wr_end			;OK

	lea	S_TimeReq(a4),a1
	move.w	#TR_ADDREQUEST,IO_Command(a1)
	clr.l	TR_Seconds(a1)
	move.l	#100000,TR_Micros(a1)
	CALLEXEC DoIO
	bra.s	wr_loop
wr_end:
	move.l	(sp)+,d2
	rts

;--- extract command line parameters -----------------------
; a0 <- &command line
; a1 <- &target
; d0 -> # parameters found

GetDosParams:
	movem.l	a1-a2,-(sp)
	lea	40(a1),a2		;&target
gdp_par:
	move.l	a2,(a1)+		;Vektor field..
	moveq.l	#0,d2
gdp_char:
	move.b	(a0)+,d0
	cmp.b	#` `,d0
	beq.s	gdp_spc
	bcs.s	gdp_pend

	cmp.b	#`"`,d0
	beq.s	gdp_cite
gdp_write:
	or.w	#1,d2
	move.b	d0,(a2)+		;..and strings
	bra.s	gdp_char

gdp_spc:
	btst	#0,d2
	beq.s	gdp_char

	btst	#1,d2
	beq.s	gdp_pend
	bra.s	gdp_write

gdp_cite:
	btst	#0,d2
	bne.s	gdp_c1

	or.w	#3,d2
	bra.s	gdp_char
gdp_c1:
	cmp.b	#` `+1,(a0)
	bcc.s	gdp_write

	move.b	(a0)+,d0
gdp_pend:
	clr.b	(a2)+
	cmp.b	#` `,d0
	beq.s	gdp_par

	btst	#0,d2
	bne.s	gdp_p1

	subq.l	#4,a1
gdp_p1:
	clr.l	(a1)
	move.l	a1,d0
	sub.l	(sp),d0
	lsr.l	#2,d0
	movem.l	(sp)+,a1-a2
	rts

;*** some math and strings *********************************
;--- copy string -------------------------------------------
; a0 <-  &from
; a1 <-> &to

StrCopy:
	move.b	(a0)+,(a1)+
	bne.s	StrCopy

	subq.l	#1,a1
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

;*** thats it!! ********************************************
	end
