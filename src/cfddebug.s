; cfddebug log file generator tool V1.08
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

;Test for compactflash.device v1.08+
;TJ. 17.04.2002

FILE_VERSION	= 1
FILE_REVISION	= 8

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

Forbid		= -132
Permit		= -138
AllocMem	= -198
FreeMem		= -210
AddHead		= -240
Remove		= -252
FindName	= -276
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
OpenResource	= -498
TypeOfMem	= -534
OpenLibrary	= -552
CopyMem		= -624
CacheClearE	= -642
CacheControl	= -648

;struct ExecBase
EXB_MemList	= 322
EXB_ResourceList = 336
EXB_DeviceList	= 350
EXB_LibList	= 378
EXB_PortList	= 392

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

LF              = 10

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

MODE_OLDFILE	= 1005
MODE_NEWFILE	= 1006
MODE_READWRITE	= 1004

;DOS errors
;0	OK
;103	no memory
;115	invalid number
;202	object in use
;303	object already exists
;205	unknown channel
;209	unknown DosPacket command
;212	object of wrong type
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

;--- private struktures ------------------------------------

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

CFU_UnitSize	= 44			;for cfddebug
CFU_ResVersion	= 48
CFU_ResRev	= 50
CFU_Debug	= 52
CFU_ReadErrors	= 56
CFU_WriteErrors	= 60

CFU_TimeReq	= 64

CFU_Process	= 104
CFU_TaskSig	= 108
CFU_CardSig	= 112
CFU_CardHandle	= 116
CFU_InsertInt	= 144
CFU_RemoveInt	= 168
CFU_StatusInt	= 192
CFU_EventFlags	= 216
CFU_IOErr	= 217
CFU_IDEStatus	= 218
CFU_IDEError	= 219
CFU_MultiSize	= 220
CFU_unused2	= 222
CFU_MemPtr	= 224
CFU_AttrPtr	= 228
CFU_IOPtr	= 232
CFU_DTSize	= 236			;struct DeviceTData
CFU_DTSpeed	= 240
CFU_DTType	= 244
CFU_DTFlags	= 245
CFU_unused1	= 246
CFU_Clients	= 248			;struct List
CFU_Request	= 260
CFU_DriveSize	= 264
CFU_Block	= 268
CFU_Count	= 272
CFU_Buffer	= 276
CFU_Try		= 280
CFU_SCSIState	= 282
CFU_ConfigAddr	= 284
CFU_ConfigBlock	= 288

CFU_Sizeof	= 800

CFU_106Sizeof	= 776

;CFU_Flags
CFUF_FLUSH	= 1
CFUF_STOPPED	= 2
CFUF_TERM	= 4

;--- global variables --------------------------------------

S_ArgC		= -4
S_ArgV		= -8
S_ExecBase	= -12
S_DosBase	= -16
S_File		= -20
S_FSize		= -24
S_CFDevice	= -28
S_CFDVersion	= -32
S_Buffer	= -36
S_StringBuf	= -256
S_Sizeof	= -256

;*** Lets get it on!! **************************************

;	lea	t_params(pc),a0
;	bra.s	Start

;t_params: dc.b	`ram:0`, LF

Start:
	link.w	a4,#S_Sizeof
	movem.l	d2-d3/a2/a4/a6,-(sp)
	move.l	(_AbsExecBase).w,S_ExecBase(a4)
	move.l	a0,S_ArgV(a4)
	move.l	d0,S_ArgC(a4)
	lea	S_StringBuf(a4),a1
	bsr.w	GetDosParams
	moveq.l	#36,d0
	lea	DosName(pc),a1
	CALLEXEC OpenLibrary
	move.l	d0,S_DosBase(a4)
	beq.w	s_end

	move.l	S_ExecBase(a4),a0
	add.w	#EXB_DeviceList,a0
	lea	CfdName(pc),a1
	CALLEXEC FindName
	move.l	d0,S_CFDevice(a4)
	beq.w	s_nodev

	moveq.l	#5120>>8,d0
	lsl.l	#8,d0
	moveq.l	#MEMF_PUBLIC,d1
	CALLEXEC AllocMem
	move.l	d0,S_Buffer(a4)
	beq.w	s_nomem

	move.l	d0,a2			;&target
	move.l	#`FORM`,(a2)+
	clr.l	(a2)+
	move.l	#`cfdd`,(a2)+
	move.l	#`devi`,(a2)+
	move.l	S_CFDevice(a4),a0	;&CompactFlashDevice
	move.l	LIB_Version(a0),S_CFDVersion(a4)
	moveq.l	#0,d0
	move.w	LIB_PosSize(a0),d0
	move.l	d0,(a2)+
s_devcopy:
	move.l	(a0)+,(a2)+
	subq.l	#4,d0
	bgt.s	s_devcopy

	move.l	S_CFDevice(a4),a0
	move.l	CFD_Unit(a0),d0
	beq.s	s_mem1

	move.l	d0,a0			;&CompactFlashUnit
	move.l	#`unit`,(a2)+
	move.l	#CFU_106Sizeof,d0
	cmp.l	#1<<16+8,S_CFDVersion(a4)
	bcs.s	s_uc1

	move.l	CFU_UnitSize(a0),d0
s_uc1:
	move.l	d0,(a2)+
s_unitcopy:
	move.l	(a0)+,(a2)+
	subq.l	#4,d0
	bgt.s	s_unitcopy
s_mem1:
	move.l	#`hba `,(a2)+
	moveq.l	#4,d0
	move.l	d0,(a2)+
	move.l	#$00da8000,a0
s_hbacopy:
	move.b	(a0),(a2)+
	add.w	#$1000,a0
	subq.w	#1,d0
	bgt.s	s_hbacopy

	move.l	S_CFDevice(a4),a0
	move.l	CFD_Unit(a0),a0
	move.l	CFU_MemPtr(a0),a1
	moveq.l	#528>>3,d0
	lsl.l	#3,d0
	move.l	#`cmem`,(a2)+
	move.l	d0,(a2)+
s_memcopy:
	move.b	(a1)+,(a2)+
	subq.l	#1,d0
	bgt.s	s_memcopy

	move.l	CFU_AttrPtr(a0),a1
	moveq.l	#$500>>4,d0
	lsl.l	#4,d0
	move.l	#`catt`,(a2)+
	move.l	d0,(a2)+
s_attcopy:
	move.b	(a1)+,(a2)+
	subq.l	#1,d0
	bgt.s	s_attcopy

	move.l	CFU_IOPtr(a0),a1
	moveq.l	#$400>>4,d0
	lsl.l	#4,d0
	move.l	#`cio `,(a2)+
	move.l	d0,(a2)+
s_iocopy:
	move.b	(a1)+,(a2)+
	subq.l	#1,d0
	bgt.s	s_iocopy

	move.l	S_Buffer(a4),a0
	move.l	a2,d0
	sub.l	a0,d0
	move.l	d0,S_FSize(a4)
	subq.l	#8,d0
	move.l	d0,4(a0)
	move.l	S_StringBuf(a4),d1
	beq.s	s_help

	move.l	#MODE_NEWFILE,d2
	CALLDOS	Open
	move.l	d0,S_File(a4)
	beq.s	s_nofile

	move.l	d0,d1
	move.l	S_Buffer(a4),d2
	move.l	S_FSize(a4),d3
	CALLDOS	Write
	move.l	S_File(a4),d1
	CALLDOS	Close
s_freemem:
	moveq.l	#5120>>8,d0
	lsl.l	#8,d0
	move.l	S_Buffer(a4),a1
	CALLEXEC FreeMem
s_closedos:
	move.l	S_DosBase(a4),a1
	CALLEXEC CloseLibrary
	moveq.l	#0,d0
s_end:
	movem.l	(sp)+,d2-d3/a2/a4/a6
	unlk	a4
	rts

s_nodev:
	lea	NoDevStr(pc),a0
	bsr.s	ReportError
	bra.s	s_closedos

s_nomem:
	lea	NoMemStr(pc),a0
	bsr.s	ReportError
	bra.s	s_closedos

s_help:
	lea	HelpStr(pc),a0
	bsr.s	ReportError
	bra.s	s_freemem

s_nofile:
	lea	NoFileStr(pc),a0
	bsr.s	ReportError
	bra.s	s_freemem

;--- error reports -----------------------------------------
; a0 <- &Text

ReportError:
	movem.l	d2-d3,-(sp)
	move.l	a0,d2
	CALLDOS	Output
	move.l	d0,d1
	beq.s	re_end

	move.l	d2,a0
re_count:
	tst.b	(a0)+
	bne.s	re_count

	move.l	a0,d3
	sub.l	d2,d3
	subq.l	#1,d3
	CALLDOS	Write
re_end:
	movem.l	(sp)+,d2-d3
	rts

	   dc.b	`$VER: cfddebug 1.08 (17.04.2002)`,LF,0
	   dc.b	`© Torsten Jager`,0
DosName:   dc.b	`dos.library`,0
CfdName:   dc.b	`compactflash.device`,0
NoDevStr:  dc.b	`"compactflash.device" is not active.`,LF,0
NoMemStr:  dc.b	`Not enough memory.`,LF,0
HelpStr:   dc.b	`usage: cfddebug <logfile>`,LF,0
NoFileStr: dc.b	`Could not open log file.`,LF,0
	even

;--- extract command line parameters -----------------------
; a0 <- &command line
; a1 <- &target
; d0 -> # parameters found

GetDosParams:
	movem.l	a1-a2,-(sp)
	lea	40(a1),a2		;&target
gdp_par:
	move.l	a2,(a1)+		;vektor field..
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
	move.b	d0,(a2)+		;..and the strings
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

;*** thats all folks!!!! ***********************************
	end
