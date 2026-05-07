; ptable.library - partition table scan and mount helper for AmigaOS
; Copyright (C) 2026  Jaroslav Pulchart
;
; This library is free software; you can redistribute it and/or
; modify it under the terms of the GNU Lesser General Public
; License as published by the Free Software Foundation; either
; version 2.1 of the License, or (at your option) any later version.
;
; This library is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
; Lesser General Public License for more details.
;
; You should have received a copy of the GNU Lesser General Public
; License along with this library; if not, write to the Free Software
; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

;===========================================================================
; ROLE
;
; ptable.library carries the cold-start RDB autoboot path:
;
;   * Find RDSK on a block device, walk the partition list.
;   * Load filesystem handlers carried in the RDB FSHD/LSEG
;     blocks into FileSystem.resource (mini in-house LoadSeg).
;   * Publish each partition via AddBootNode (bootable, with a
;     synthetic ConfigDev + DiagArea/BootPoint that starts
;     dos.library) or AddDosNode (non-bootable).
;
; INERT WHEN DISK-LOADED
;
; Like every Amiga library, ptable.library can be loaded from
; LIBS: at runtime via OpenLibrary. However, the only useful
; consumer (a device's RTF_COLDSTART stub) runs from
; Kickstart's ROM scan BEFORE ramlib starts, so a disk-loaded
; ptable.library will simply never have a caller. Functional
; autoboot therefore requires this library to be ROM-resident.
;
; BUILD VARIANTS
;
;   Full build (DEBUG=1): includes serial debug output.
;   Small build (no DEBUG): minimal binary size.
;===========================================================================

;--- Includes ---
	include	"ptable_version.i"
	include	"ptable_pub.i"

;--- from exec.library -------------------------------------

_AbsExecBase	= 4

;SysBase offsets (subset)
SB_DeviceList	= 350

FindResident	= -96
InitResident	= -102
Forbid		= -132
Permit		= -138
FindName	= -276
AllocMem	= -198
FreeMem		= -210
AddHead		= -240
Remove		= -252
FindTask	= -294
AllocSignal	= -330
FreeSignal	= -336
CloseLibrary	= -414
OpenDevice	= -444
CloseDevice	= -450
DoIO		= -456
OpenResource	= -498
OpenLibrary	= -552
RawPutChar	= -516
AddResource	= -486
CacheClearU	= -636

;struct Node
LN_Type		=  8
LN_Name		= 10
LN_Sizeof	= 14

;LN_Type
NT_UNKNOWN	= 0
NT_TASK		= 1
NT_DEVICE	= 3
NT_MSGPORT	= 4
NT_MESSAGE	= 5
NT_RESOURCE	= 8
NT_LIBRARY	= 9

;struct MsgPort
MP_Flags	= 14
MP_SigBit	= 15
MP_SigTask	= 16
MP_MsgList	= 20
MP_Sizeof	= 34

;struct Message
MN_ReplyPort	= 14
MN_Length	= 18

;memory types
MEMF_PUBLIC	= 1
MEMF_CLEAR	= $10000
MEMF_REVERSE	= $40000

;struct Library
LIB_Node	= 0
LIB_Flags	= 14
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

;struct Resident
RTC_MATCHWORD	= $4afc
RT_INIT		= $16
RTF_AUTOINIT	= $80

;trackdisk / IO command set (subset used by the boot path)
IO_Device	= 20
IO_Unit		= 24
IO_Command	= 28
IO_Flags	= 30
IO_Error	= 31
IO_Actual	= 32
IO_Length	= 36
IO_Data		= 40
IO_Offset	= 44
IO_Sizeof	= 56

TD_CHANGESTATE	= 14
NSCMD_TD_READ64	= $c000

;CR/LF for debug strings
CR		= 13
LF		= 10

;--- LibBase layout ----------------------------------------
; The standard 34-byte exec library struct plus a couple of
; private slots used by the implementation.

RDBL_ExecBase	= LIB_Sizeof		;ExecBase pointer
RDBL_SegList	= LIB_Sizeof+4		;SegList for Expunge / FreeMem
RDBL_Sizeof	= LIB_Sizeof+8

;===========================================================
; Romtag + InitTable
;
; RTF_AUTOINIT here means Exec's MakeLibrary scaffolding does
; the entire setup for us: allocate RDBL_Sizeof bytes, copy
; the function offset table, call s_initfunc with d0 = new
; lib base / a0 = SegList / a6 = ExecBase, then AddLibrary.
;===========================================================

Start:
	moveq.l	#0,d0
	rts				;guard against shell invocation

	cnop	0,2
s_resident:
	dc.w	RTC_MATCHWORD
	dc.l	s_resident
	dc.l	s_endcode
	dc.b	RTF_AUTOINIT
	dc.b	LIB_VERSION
	dc.b	NT_LIBRARY
	dc.b	PRI_PTABLE_LIB		;see ptable_pub.i for priority rationale
	dc.l	s_libname
	dc.l	s_libidstring
	dc.l	s_inittable

s_libname:
	dc.b	"ptable.library",0
	dc.b	"$VER: "
s_libidstring:
	LIB_VERSION_STRING
	dc.b	LF,0
	even

s_inittable:
	dc.l	RDBL_Sizeof
	dc.l	s_functable
	dc.l	0			;no InitStruct() table
	dc.l	s_initfunc

s_functable:
	dc.w	-1
	dc.w	Open-s_functable
	dc.w	Close-s_functable
	dc.w	Expunge-s_functable
	dc.w	Null-s_functable	;reserved
	dc.w	BootScanRDB-s_functable
	dc.w	-1

;--- s_initfunc: called by Exec.MakeLibrary scaffolding ----
; d0 <- new LibBase
; a0 <- SegList (0 when ROM-resident)
; a6 <- ExecBase
; d0 -> LibBase or 0
s_initfunc:
	move.l	d0,a1			;a1 = LibBase
	move.l	a6,RDBL_ExecBase(a1)
	move.l	a0,RDBL_SegList(a1)
	;; LIB_Version is set up by MakeLibrary from the Resident's
	;; rt_Version, but rt_Version is only a byte; populate the
	;; full longword (major:minor) so consumers calling
	;; OpenLibrary("ptable.library", N) see a real revision.
	move.l	#LIB_VERSION<<16+LIB_REVISION,LIB_Version(a1)
	move.l	a1,d0
	rts

;--- Open: a6 = LibBase --------------------------------------
Open:
	addq.w	#1,LIB_OpenCnt(a6)
	and.b	#~LIBF_DELEXP,LIB_Flags(a6)
	move.l	a6,d0
	rts

;--- Close: a6 = LibBase, returns SegList or 0 ---------------
Close:
	moveq.l	#0,d0
	subq.w	#1,LIB_OpenCnt(a6)
	bne.s	cl_end
	btst	#3,LIB_Flags(a6)	;LIBF_DELEXP (bit 3 of LIB_Flags)
	beq.s	cl_end
	bra.s	Expunge
cl_end:
	rts

;--- Expunge: a6 = LibBase ---------------------------------
; Standard expunge: if the library is open, mark for delayed
; expunge and return 0; otherwise unlink, free our chunk, and
; return the SegList so ramlib can UnLoadSeg.
Expunge:
	movem.l	d2/a5-a6,-(sp)
	move.l	a6,a5			;a5 = LibBase
	move.l	(_AbsExecBase).w,a6
	tst.w	LIB_OpenCnt(a5)
	beq.s	ex_now
	or.b	#LIBF_DELEXP,LIB_Flags(a5)
	moveq.l	#0,d0
	bra.s	ex_end
ex_now:
	move.l	RDBL_SegList(a5),d2	;preserve SegList for return
	move.l	a5,a1
	jsr	Remove(a6)		;unlink from library list
	moveq.l	#0,d0
	move.w	LIB_NegSize(a5),d0
	move.l	a5,a1
	sub.l	d0,a1
	add.w	LIB_PosSize(a5),d0
	jsr	FreeMem(a6)
	move.l	d2,d0
ex_end:
	movem.l	(sp)+,d2/a5-a6
	rts

;--- Null: reserved LVO and various fall-through "do nothing"
Null:
	moveq.l	#0,d0
	rts

;===========================================================
; Boot-time bodies (BootScanRDB and helpers)
;
; All in a single source so the static branches below stay
; in range.
;===========================================================

	include	"ptable_boot.s"
	include	"ptable_fs.s"
	include	"ptable_hunk.s"
	include	"ptable_dosdiag.i"

	cnop	0,4
s_endcode:
	end
