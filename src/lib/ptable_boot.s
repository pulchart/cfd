;===========================================================
; ptable_boot.s -- BootScanRDB body and helpers
;
; Device-agnostic: takes a device name and unit from the
; caller, opens that device, walks the RDB, and registers
; partitions via expansion.library.
;
; Register conventions inside this block:
;   a4 = &BootCtx (allocated on entry, freed on exit)
;   a5 = ExecBase (cached from RDBL_ExecBase(LibBase))
; a6 is repeatedly loaded with ExecBase / ExpansionBase /
; DosBase / FileSystem.resource base before each jsr.
;===========================================================

;--- from expansion.library --------------------------------
AddBootNode	= -36
AddConfigDev	= -30
AddDosNode	= -150

;--- ConfigDev layout (libraries/configvars.i) -------------
;   Only the fields actually written by the synthetic ConfigDev
;   below are defined here; full layout lives in NDK.
CD_NODE_TYPE	= 8
CD_NODE_NAME	= 10
CD_ER_TYPE	= 16
CD_ER_PRODUCT	= 17
CD_ER_MANUF	= 20
CD_ER_SERIAL	= 22
CD_ER_RESERVED0C = 28
CD_BOARDADDR	= 32
CD_BOARDSIZE	= 36
CD_SIZEOF	= 68

NT_CONFIGDEV	= 20
ERTF_DIAGVALID	= $10

;--- from dos.library --------------------------------------
DOS_Delay	= -198

;--- Rigid Disk Block / Partition / FSHD / LSEG ------------
;   Only the fields actually read by the walkers below are
;   defined; *_ID / *_ChkSum / *_SummedLongs are referred to by
;   the RDSK/PART/FSHD/LSEG signature longs (RDSK_ID, ...).
RDB_LOCATION_LIMIT = 16
RDB_BLOCK_BYTES	= 512

rdb_SummedLongs	= 4
rdb_PartitionList = 28
rdb_FileSysHeaderList = 32

RDSK_ID		= $5244534B		;'RDSK'

pb_Next		= 16
pb_Flags	= 20
pb_DriveName	= 36
pb_Environment	= 128

PART_ID		= $50415254		;'PART'

;-- pb_Flags bit numbers (used with btst)
PBFFB_BOOTABLE	= 0
PBFFB_NOMOUNT	= 1

fhb_Next	= 16
fhb_DosType	= 32
fhb_Version	= 36
fhb_PatchFlags	= 40
fhb_Type	= 44
fhb_Task	= 48
fhb_Lock	= 52
fhb_Handler	= 56
fhb_StackSize	= 60
fhb_Priority	= 64
fhb_Startup	= 68
fhb_SegListBlocks = 72
fhb_GlobalVec	= 76

FSHD_ID		= $46534844		;'FSHD'

lsb_Next	= 16
lsb_LoadData	= 20

LSEG_ID		= $4C534547		;'LSEG'

DE_BOOTPRI	= 15
DE_DOSTYPE	= 16
DE_BOOTBLOCKS	= 19

fsr_Creator	= 14
fsr_FileSysEntries = 18
fsr_Sizeof	= 32

fse_DosType	= 14
fse_Version	= 18
fse_PatchFlags	= 22
fse_Type	= 26
fse_Task	= 30
fse_Lock	= 34
fse_Handler	= 38
fse_StackSize	= 42
fse_Priority	= 46
fse_Startup	= 50
fse_SegList	= 54
fse_GlobalVec	= 58
fse_Sizeof	= 62

;--- AmigaDOS hunk format (used by rdb_hunk.s) -------------
HUNK_UNIT	= $000003E7
HUNK_NAME	= $000003E8
HUNK_CODE	= $000003E9
HUNK_DATA	= $000003EA
HUNK_BSS	= $000003EB
HUNK_RELOC32	= $000003EC
HUNK_SYMBOL	= $000003F0
HUNK_DEBUG	= $000003F1
HUNK_END	= $000003F2
HUNK_HEADER	= $000003F3
HUNK_OVERLAY	= $000003F5
HUNK_BREAK	= $000003F6
HUNK_RELOC32SHORT = $000003FC

;--- DeviceNode field offsets (for _bootPatchDNfromFSE) ---
dn_Type		= 4
dn_Task		= 8
dn_Lock		= 12
dn_Handler	= 16
dn_StackSize	= 20
dn_Priority	= 24
dn_Startup	= 28
dn_SegList	= 32
dn_GlobVec	= 36
dn_Name		= 40

;===========================================================
; BootCtx layout (one AllocMem on BootScanRDB entry):
;
;   offset  size  field
;   ------  ----  --------------------------------------------
;       0     4   BC_ExecBase     cached ExecBase
;       4     4   BC_ExpBase      expansion.library base
;       8     4   BC_DosBase      dos.library base (may be 0)
;      12     4   BC_Unit         unit number passed by caller
;      16     4   BC_BlockBuf     -> trailing 512B buffer
;      20     4   BC_FSResource   FileSystem.resource (lazy)
;      24     1   BC_DevOpen      1 if OpenDevice succeeded
;      25     1   BC_SigOK        1 if reply-port signal alloc'd
;      26     1   BC_HaveNodes    1 if any AddBootNode/AddDosNode ran
;      27     1   BC_PartCount    count of partitions registered
;      28    34   BC_DevMsgPort
;      62    56   BC_DevIOReq
;     118     2   (pad to long)
;     120     4   BC_ConfigDev    synthetic ConfigDev (0 = none)
;     124     4   BC_DevName      caller's device name string
;     128     4   BC_DevNameBSTR  cached BSTR(BPTR) of BC_DevName
;                                 for fssm_Device (0 = alloc failed,
;                                 _bootAddOnePartition then skips)
;     132   512   block buffer (BC_BlockBuf points here)

BC_ExecBase	= 0
BC_ExpBase	= 4
BC_DosBase	= 8
BC_Unit		= 12
BC_BlockBuf	= 16
BC_FSResource	= 20
BC_DevOpen	= 24
BC_SigOK	= 25
BC_HaveNodes	= 26
BC_PartCount	= 27
BC_DevMsgPort	= 28
BC_DevIOReq	= 62
BC_Pad2		= 118
BC_ConfigDev	= 120
BC_DevName	= 124
BC_DevNameBSTR	= 128
BC_Sizeof	= 132

BC_BUF_BYTES	= 512

;--- DeviceNode blob layout (built by _bootAddOnePartition) ---
DN_FSSM_OFF	= 44
DN_ENVEC_OFF	= 60
DN_BSTR_OFF	= 144
DN_BLOB_SIZE	= 176

;===========================================================
; Constants: ROM strings used during scan
;===========================================================
ExpansionName:
	dc.b	"expansion.library",0
DosName:
	dc.b	"dos.library",0
FileSysResName:
	dc.b	"FileSystem.resource",0
	even
;-- "ptable.library" is shared with the LN_Name string in
;   ptable_lib.s; reuse s_libname(pc) for fsr_Creator and the
;   FileSysEntry LN_Name (see ptable_fs.s).

;--- Debug strings (only emitted in DEBUG builds) ----------
	ifd	DEBUG
dbg_boot_start:
	dc.b	"[RDB] scan",CR,LF,0
dbg_boot_no_card:
	dc.b	"[RDB] no card",CR,LF,0
dbg_boot_no_rdb:
	dc.b	"[RDB] no RDB",CR,LF,0
dbg_boot_fs_add:
	dc.b	"[RDB] +fs ",0
dbg_boot_part_boot:
	dc.b	"[RDB] +boot ",0
dbg_boot_part_dos:
	dc.b	"[RDB] +dos  ",0
dbg_boot_part_skip:
	dc.b	"[RDB] skip ",0
dbg_boot_done:
	dc.b	"[RDB] done",CR,LF,0
dbg_boot_exp_fail:
	dc.b	"[RDB] err: no exp.lib",CR,LF,0
dbg_boot_no_mem:
	dc.b	"[RDB] err: no mem",CR,LF,0
dbg_boot_opendev_err:
	dc.b	"[RDB] err: OpenDevice $",0
dbg_boot_rdsk_found:
	dc.b	"[RDB] found RDSK",CR,LF,0
dbg_boot_nl:
	dc.b	CR,LF,0
dbg_hunk_badid:
	dc.b	"[RDB] hunk: bad id $",0
	endc
	even

;===========================================================
; BootScanRDB
;
; Inputs:
;   a1 = device name (NUL-terminated C-string)
;   d0 = unit number
;   a6 = LibBase
;
; Output:
;   d0 = number of partitions registered (0 = no card / no RDB
;        / allocation failure / etc.)
;
; Preserves d2-d7/a2-a5/a6
;===========================================================
BootScanRDB:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	a1,d6			;d6 = device name
	move.l	d0,d5			;d5 = unit
	move.l	RDBL_ExecBase(a6),a5	;a5 = ExecBase

;-- allocate BootCtx + 512B buffer in one shot
	move.l	#BC_Sizeof+BC_BUF_BYTES,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	move.l	a5,a6
	jsr	AllocMem(a6)
	tst.l	d0
	bne.s	bs_haveCtx
	ifd	DEBUG
	lea	dbg_boot_no_mem(pc),a0
	bsr	_bootDebug
	endc
	moveq.l	#0,d6			;result count = 0
	bra.w	bs_no_alloc
bs_haveCtx:
	move.l	d0,a4			;a4 = &BootCtx
	move.l	a5,BC_ExecBase(a4)
	move.l	d6,BC_DevName(a4)	;d6 still holds devname
	move.l	d5,BC_Unit(a4)
	lea	BC_Sizeof(a4),a0
	move.l	a0,BC_BlockBuf(a4)
	move.b	#-1,BC_SigOK(a4)	;sentinel: no signal allocated yet

;-- Cache the device-name BSTR once per scan; reused for every
;   partition's fssm_Device.  On failure the slot stays 0
;   (BootCtx is MEMF_CLEAR) and _bootAddOnePartition skips.
	move.l	BC_DevName(a4),a0
	move.l	a5,a6
	bsr	_bootMakeExecBSTR
	move.l	d0,BC_DevNameBSTR(a4)

;-- open expansion.library
	moveq.l	#0,d0
	lea	ExpansionName(pc),a1
	move.l	a5,a6
	jsr	OpenLibrary(a6)
	move.l	d0,BC_ExpBase(a4)
	bne.s	bs_haveExp
	ifd	DEBUG
	lea	dbg_boot_exp_fail(pc),a0
	bsr	_bootDebug
	endc
	bra.w	bs_cleanup
bs_haveExp:

;-- Synthesize a ConfigDev for the device.
;   (The ConfigDev's CD_NODE_NAME points at the caller's device
;   name string so strap renders the early-startup menu against
;   the correct device.  ER_TYPE = ERTF_DIAGVALID together with
;   er_Reserved0c -> s_rdb_diag_rom drives the BootPoint flow:
;   strap copies the DiagArea to RAM and calls da_BootPoint,
;   which then runs FindResident("dos.library") + RT_INIT.)
	move.l	a5,a6			;ExecBase
	move.l	#CD_SIZEOF,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	jsr	AllocMem(a6)
	tst.l	d0
	beq.w	bs_no_cd
	move.l	d0,BC_ConfigDev(a4)
	move.l	d0,a2
	move.b	#NT_CONFIGDEV,CD_NODE_TYPE(a2)
	move.l	BC_DevName(a4),CD_NODE_NAME(a2)
	move.b	#$C0|ERTF_DIAGVALID|4,CD_ER_TYPE(a2)	;Z-II, diag, 512KB
	lea	s_rdb_diag_rom(pc),a0
	move.l	a0,CD_ER_RESERVED0C(a2)
	move.b	#1,CD_ER_PRODUCT(a2)
	move.w	#$FFFF,CD_ER_MANUF(a2)		;no vendor
	move.l	#$52444230,CD_ER_SERIAL(a2)	;'RDB0'
	move.l	#$00A00000,CD_BOARDADDR(a2)	;PCMCIA attributes base
	move.l	#$00080000,CD_BOARDSIZE(a2)	;512 KB
bs_no_cd:

;-- open dos.library; used for Delay() only.  OK to be NULL.
	move.l	a5,a6
	moveq.l	#0,d0
	lea	DosName(pc),a1
	jsr	OpenLibrary(a6)
	move.l	d0,BC_DosBase(a4)

	ifd	DEBUG
	lea	dbg_boot_start(pc),a0
	bsr	_bootDebug
	endc

;-- open the requested unit, run the scan, close the unit.
	bsr	_bootOpenUnit
	tst.l	d0
	beq.s	bs_close_unit
	bsr	_bootScanRdb
bs_close_unit:
	bsr	_bootCloseUnit		;idempotent: handles partial open

;-- Register synthetic ConfigDev with strap (eb_CDevList) so the
;   early-startup boot menu shows the device and the BootPoint
;   fires when the user picks a bootable partition.  Guarded:
;   only call when at least one partition was registered.
	tst.b	BC_HaveNodes(a4)
	beq.s	bs_close
	move.l	BC_ConfigDev(a4),d0
	beq.s	bs_close
	move.l	BC_ExpBase(a4),d0
	beq.s	bs_close
	move.l	d0,a6
	move.l	BC_ConfigDev(a4),a0
	jsr	AddConfigDev(a6)

bs_close:
	move.l	BC_ExecBase(a4),a6
	move.l	BC_DosBase(a4),d0
	beq.s	bs_close1
	move.l	d0,a1
	jsr	CloseLibrary(a6)
bs_close1:
	move.l	BC_ExpBase(a4),d0
	beq.s	bs_cleanup
	move.l	d0,a1
	jsr	CloseLibrary(a6)

bs_cleanup:
	ifd	DEBUG
	lea	dbg_boot_done(pc),a0
	bsr	_bootDebug
	endc
	moveq.l	#0,d6
	move.b	BC_PartCount(a4),d6	;return value = partitions registered
	move.l	a4,a1
	move.l	#BC_Sizeof+BC_BUF_BYTES,d0
	move.l	BC_ExecBase(a4),a6
	jsr	FreeMem(a6)

bs_no_alloc:
	move.l	d6,d0
	movem.l	(sp)+,d2-d7/a2-a6
	rts

;===========================================================
; _bootOpenUnit: OpenDevice + spin on TD_CHANGESTATE.
;
; Input:  a4 = &BootCtx, a5 = ExecBase, BC_Unit / BC_DevName set
; Output: d0 = 1 on success (media present), 0 on failure
;===========================================================
_bootOpenUnit:
	move.l	a5,a6

;-- MsgPort
	sub.l	a1,a1
	jsr	FindTask(a6)
	lea	BC_DevMsgPort(a4),a2
	move.l	d0,MP_SigTask(a2)

	moveq.l	#-1,d0
	jsr	AllocSignal(a6)
	cmp.b	#-1,d0
	bne.s	_bou_sig_ok
	bra.w	_bou_fail
_bou_sig_ok:
	move.b	d0,MP_SigBit(a2)
	move.b	d0,BC_SigOK(a4)
	move.b	#NT_MSGPORT,LN_Type(a2)
	clr.b	MP_Flags(a2)		;PA_SIGNAL = 0
	lea	MP_MsgList(a2),a0
	move.l	a0,(a0)			;INITLIST inline
	addq.l	#4,(a0)
	clr.l	4(a0)
	move.l	a0,8(a0)

;-- IOStdReq
	lea	BC_DevIOReq(a4),a1
	move.b	#NT_MESSAGE,LN_Type(a1)
	move.w	#IO_Sizeof,MN_Length(a1)
	move.l	a2,MN_ReplyPort(a1)

;-- OpenDevice (caller-supplied name + unit)
	move.l	BC_DevName(a4),a0
	move.l	BC_Unit(a4),d0
	;moveq.l	#9,d1			;Flags=1|8: SocketOn + serial debug
	moveq.l	#0,d1
	jsr	OpenDevice(a6)
	tst.l	d0
	beq.s	_bou_od_ok
	ifd	DEBUG
	move.l	d0,-(sp)
	lea	dbg_boot_opendev_err(pc),a0
	bsr	_bootDebug
	move.l	(sp)+,d0
	bsr	_bootDebugHex8
	lea	dbg_boot_nl(pc),a0
	bsr	_bootDebug
	endc
	bra.w	_bou_fail
_bou_od_ok:
	move.b	#1,BC_DevOpen(a4)

;-- poll TD_CHANGESTATE up to 5s for slow card spin-up
	moveq.l	#50,d7
_bou_poll:
	lea	BC_DevIOReq(a4),a1
	move.w	#TD_CHANGESTATE,IO_Command(a1)
	clr.l	IO_Actual(a1)
	clr.b	IO_Error(a1)
	jsr	DoIO(a6)
	tst.b	BC_DevIOReq+IO_Error(a4)
	bne.s	_bou_delay
	move.l	BC_DevIOReq+IO_Actual(a4),d0
	beq.s	_bou_ok			;IO_Actual=0 -> media present
_bou_delay:
	bsr	_bootDelay100ms
	subq.w	#1,d7
	bne.s	_bou_poll
	ifd	DEBUG
	lea	dbg_boot_no_card(pc),a0
	bsr	_bootDebug
	endc
	moveq.l	#0,d0
	rts
_bou_ok:
	moveq.l	#1,d0
	rts
_bou_fail:
	moveq.l	#0,d0
	rts

;===========================================================
; _bootCloseUnit: CloseDevice + FreeSignal (idempotent)
;===========================================================
_bootCloseUnit:
	move.l	BC_ExecBase(a4),a6
	tst.b	BC_DevOpen(a4)
	beq.s	_bcu_sig
	lea	BC_DevIOReq(a4),a1
	jsr	CloseDevice(a6)
	clr.b	BC_DevOpen(a4)
_bcu_sig:
	move.b	BC_SigOK(a4),d0
	cmp.b	#-1,d0
	beq.s	_bcu_end
	ext.w	d0
	ext.l	d0
	jsr	FreeSignal(a6)
	move.b	#-1,BC_SigOK(a4)
_bcu_end:
	rts

;===========================================================
; _bootDelay100ms: sleep ~100 ms.  Uses dos.library/Delay(5)
; if DosBase is open, otherwise a rough busy-wait (~350k
; simple insns is ~100ms on a 7 MHz 68000).
;===========================================================
_bootDelay100ms:
	move.l	a6,-(sp)
	move.l	BC_DosBase(a4),d0
	beq.s	_bd_busy
	move.l	d0,a6
	moveq.l	#5,d1			;50 Hz * 0.1s = 5 ticks
	jsr	DOS_Delay(a6)
	move.l	(sp)+,a6
	rts
_bd_busy:
	move.l	#150000,d0
_bd_bl:	subq.l	#1,d0
	bne.s	_bd_bl
	move.l	(sp)+,a6
	rts

;===========================================================
; _bootReadBlock: read one 512B block by 32-bit block#.
;
; Input:  d0 = block# (0..16M), a4 = &BootCtx
; Output: d0 = 0 on success, nonzero (IO_Error) otherwise
;
; Wraps _bootReadBytes64 so reads survive partition starts
; that wrap past 4 GiB in 32-bit IO_Offset.
;===========================================================
_bootReadBlock:
	movem.l	d1-d2/a1,-(sp)
	moveq.l	#0,d1			;high32 = 0 (block# always small)
	add.l	d0,d0			;*2 via add.l (faster than lsl.l #1)
	lsl.l	#8,d0			;d0 = block * 512 (low32)
	exg	d0,d1			;d0=high32=0, d1=low32
	move.l	#RDB_BLOCK_BYTES,d2
	move.l	BC_BlockBuf(a4),a1
	bsr	_bootReadBytes64
	movem.l	(sp)+,d1-d2/a1
	rts

;===========================================================
; _bootReadBytes64: NSCMD_TD_READ64 wrapper.
; (NSCMD reads bypass any CMD_READ partition-base intercept on the
; device, since we hand both halves of the 64-bit offset
; explicitly here.)
;
; Input : d0.l = high32, d1.l = low32, d2.l = bytes,
;         a1   = destination, a4 = &BootCtx
; Output: d0 = 0 on success, nonzero IO_Error otherwise
;===========================================================
_bootReadBytes64:
	movem.l	d1-d2/a0/a1/a6,-(sp)
	move.l	BC_ExecBase(a4),a6
	lea	BC_DevIOReq(a4),a0
	move.w	#NSCMD_TD_READ64,IO_Command(a0)
	clr.b	IO_Error(a0)
	move.l	d0,IO_Actual(a0)	;high 32 bits
	move.l	d1,IO_Offset(a0)	;low  32 bits
	move.l	d2,IO_Length(a0)
	move.l	a1,IO_Data(a0)
	move.l	a0,a1
	jsr	DoIO(a6)
	moveq.l	#0,d0
	move.b	BC_DevIOReq+IO_Error(a4),d0
	movem.l	(sp)+,d1-d2/a0/a1/a6
	rts

;===========================================================
; _bootChecksum: sum of first d1 longs of buffer (a0).
; Returns d0 = 0 if checksum valid, nonzero otherwise.
;===========================================================
_bootChecksum:
	movem.l	d2/a2,-(sp)
	move.l	a0,a2
	moveq.l	#0,d0
	move.l	d1,d2
	subq.l	#1,d2
	bmi.s	_bcs_end
_bcs_loop:
	add.l	(a2)+,d0
	dbra	d2,_bcs_loop
_bcs_end:
	movem.l	(sp)+,d2/a2
	tst.l	d0
	rts

;===========================================================
; _bootScanRdb: find RDSK, run FS-load + partition-add phases.
;===========================================================
_bootScanRdb:
;-- find the RDB in the first 16 blocks
	moveq.l	#0,d6			;d6 = current block index
_brdb_scan:
	move.l	d6,d0
	bsr	_bootReadBlock
	tst.l	d0
	bne.s	_brdb_next
	move.l	BC_BlockBuf(a4),a0
	cmpi.l	#RDSK_ID,(a0)
	bne.s	_brdb_next
	move.l	rdb_SummedLongs(a0),d1
	cmp.l	#128,d1
	bhi.s	_brdb_next
	bsr	_bootChecksum
	beq.s	_brdb_found
_brdb_next:
	addq.l	#1,d6
	cmp.l	#RDB_LOCATION_LIMIT,d6
	blo.w	_brdb_scan
	ifd	DEBUG
	lea	dbg_boot_no_rdb(pc),a0
	bsr	_bootDebug
	endc
	rts

_brdb_found:
	ifd	DEBUG
	lea	dbg_boot_rdsk_found(pc),a0
	bsr	_bootDebug
	endc
	move.l	BC_BlockBuf(a4),a0
	move.l	rdb_PartitionList(a0),d5	;d5 = partition list head
	move.l	rdb_FileSysHeaderList(a0),d4	;d4 = fshd list head

;-- Phase 1: add filesystems carried in RDB.  Hard cap at 16 hops
;   so a corrupted multi-step fhb_Next cycle (A->B->A) cannot trap
;   the cold-start path; the trivial 1-step self-loop is also
;   caught by the cmp.l d3,d6 guard at the bottom of the loop.
	move.l	d4,d3
	moveq.l	#16,d2			;d2 = hop counter
_brdb_fs_loop:
	move.l	d3,d0
	addq.l	#1,d0			;-1 -> 0 (end sentinel)
	beq.w	_brdb_fs_done
	subq.l	#1,d2			;walker hop counter
	bmi.w	_brdb_fs_done
	move.l	d3,d6
	move.l	d3,d0
	bsr	_bootReadBlock
	tst.l	d0
	bne.w	_brdb_fs_done
	move.l	BC_BlockBuf(a4),a0
	cmpi.l	#FSHD_ID,(a0)
	bne.w	_brdb_fs_done
	move.l	fhb_Next(a0),d3
	bsr	_bootAddOneFileSys
	cmp.l	d3,d6			;self-loop guard
	beq.s	_brdb_fs_done
	bra.w	_brdb_fs_loop
_brdb_fs_done:

;-- Phase 2: add partitions.  Hard cap at 128 hops (RDB allows up to
;   ~127 partitions in practice); same rationale as the FSHD walker.
	move.l	d5,d3
	moveq.l	#127,d2			;d2 = hop counter (signed-fit moveq)
_brdb_part_loop:
	move.l	d3,d0
	addq.l	#1,d0
	beq.s	_brdb_pt_done
	subq.l	#1,d2			;walker hop counter
	bmi.s	_brdb_pt_done
	move.l	d3,d6
	move.l	d3,d0
	bsr	_bootReadBlock
	tst.l	d0
	bne.s	_brdb_pt_done
	move.l	BC_BlockBuf(a4),a0
	cmpi.l	#PART_ID,(a0)
	bne.s	_brdb_pt_done
	move.l	pb_Next(a0),d3
	bsr	_bootAddOnePartition
	cmp.l	d3,d6
	beq.s	_brdb_pt_done
	bra.s	_brdb_part_loop
_brdb_pt_done:
	rts

;===========================================================
; _bootAddOnePartition
;
; Input:  BC_BlockBuf -> current PartitionBlock; a4 = &BootCtx
; Output: nothing (registers a DeviceNode via expansion.library
;         when partition is mountable).
;===========================================================
_bootAddOnePartition:
	movem.l	d2-d7/a2/a5,-(sp)

	move.l	BC_BlockBuf(a4),a2	;a2 = PartitionBlock
	move.l	BC_ExecBase(a4),a6

;-- NOMOUNT gate (pb_Flags bit PBFFB_NOMOUNT)
	move.l	pb_Flags(a2),d0
	btst	#PBFFB_NOMOUNT,d0
	beq.s	_bap_mountable
	ifd	DEBUG
	lea	dbg_boot_part_skip(pc),a0
	bsr	_bootDebug
	move.l	BC_BlockBuf(a4),a0
	lea	pb_DriveName(a0),a0	;raw RDB name (no DN blob yet)
	bsr	_bootDebugBStr
	endc
	bra.w	_bap_end
_bap_mountable:

;-- The cached device-name BSTR is required for every FSSM; if the
;   one-shot alloc in BootScanRDB failed there is no way to mount.
	tst.l	BC_DevNameBSTR(a4)
	beq.w	_bap_end

;-- Validate DosEnvec TableSize before allocating the DN blob
	move.l	pb_Environment(a2),d2	;d2 = envSize (TableSize)
	cmp.l	#DE_DOSTYPE,d2		;need index 16 (DOSTYPE) in range
	blo.w	_bap_end
	cmp.l	#20,d2
	bhi.w	_bap_end

;-- Allocate DeviceNode blob (MEMF_REVERSE: high in RAM, away
;   from low-heap fragmentation).  Layout:
;     [  0..43 ] DeviceNode
;     [ 44..59 ] FileSysStartupMsg
;     [ 60..143] DosEnvec (TableSize <= 20 -> <= 84 bytes)
;     [144..175] dn_Name BSTR
	move.l	#DN_BLOB_SIZE,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR+MEMF_REVERSE,d1
	jsr	AllocMem(a6)
	tst.l	d0
	beq.w	_bap_end
	move.l	d0,d7			;d7 = DN byte addr
	move.l	d7,a5			;a5 = DN

;-- DeviceNode fields
	move.l	#-1,36(a5)		;dn_GlobVec
	move.l	#4000,20(a5)		;dn_StackSize
	moveq.l	#5,d0
	move.l	d0,24(a5)		;dn_Priority

;-- pb_DriveName BSTR -> DN_BSTR_OFF (early-startup menu only
;   renders the partition name from a BSTR inside the DN's own
;   allocation; separate-pool BSTRs render blank).
	lea	pb_DriveName(a2),a0
	lea	DN_BSTR_OFF(a5),a1
	moveq.l	#0,d3
	move.b	(a0),d3
	addq.l	#1,d3
_bap_dn_cp:
	move.b	(a0)+,(a1)+
	subq.l	#1,d3
	bne.s	_bap_dn_cp
	lea	DN_BSTR_OFF(a5),a1
	move.l	a1,d0
	lsr.l	#2,d0			;BPTR
	move.l	d0,40(a5)		;dn_Name

;-- Uniquify the drive name against eb_MountList:
;   append .1/.2/... when the name already exists, so two cards
;   reusing RDB names don't clash in the early-startup menu).
;   a4=&BootCtx, a5=DN blob.
	bsr	_bootDedupName

;-- FileSysStartupMsg at DN_FSSM_OFF (fields written directly
;   from BootCtx + DN; no scratch packet involved).
	lea	DN_FSSM_OFF(a5),a1
	move.l	a1,d0
	lsr.l	#2,d0
	move.l	d0,28(a5)		;dn_Startup = BPTR(FSSM)
	move.l	BC_Unit(a4),(a1)	;fssm_Unit
	move.l	BC_DevNameBSTR(a4),4(a1) ;fssm_Device (cached BSTR)
	lea	DN_ENVEC_OFF(a5),a0
	move.l	a0,d0
	lsr.l	#2,d0
	move.l	d0,8(a1)		;fssm_Environ = BPTR(envec)

;-- Copy DosEnvec straight from pb_Environment(a2) into the DN
;   blob's envec slot (one pass, no packet round-trip).
	lea	pb_Environment(a2),a1	;a1 = source (TableSize + entries)
	move.l	d2,d3			;d2 = envSize (already validated)
	addq.l	#1,d3			;count = TableSize + 1
_bap_envec_cp:
	move.l	(a1)+,(a0)+
	subq.l	#1,d3
	bne.s	_bap_envec_cp

;-- Apply FileSysEntry patches BEFORE AddBootNode (FFS auto-attach
;   in expansion.library otherwise replaces a custom handler such
;   as PFS3 silently).
	move.l	BC_ExecBase(a4),a6
	move.l	pb_Environment+DE_DOSTYPE*4(a2),d0
	bsr	_bootFindFSEntry
	tst.l	d0
	beq.s	_bap_fse_miss
	move.l	d0,a1
	move.l	d7,a0
	bsr	_bootPatchDNfromFSE
_bap_fse_miss:

;-- Switch a6 back to expansion.library for the AddBootNode /
;   AddDosNode call.
	move.l	BC_ExpBase(a4),a6

	move.l	pb_Flags(a2),d0
	btst	#PBFFB_BOOTABLE,d0
	beq.w	_bap_dosnode

;---- AddBootNode
	ifd	DEBUG
	lea	dbg_boot_part_boot(pc),a0
	bsr	_bootDebug
	lea	DN_BSTR_OFF(a5),a0	;name as registered (post-dedup)
	bsr	_bootDebugBStr
	endc
	move.l	pb_Environment+DE_BOOTPRI*4(a2),d0
	moveq.l	#0,d1			;flags=0: no ADNF_STARTPROC
	move.l	d7,a0
	move.l	BC_ConfigDev(a4),a1	;synthetic ConfigDev
	jsr	AddBootNode(a6)
	move.b	#1,BC_HaveNodes(a4)
	addq.b	#1,BC_PartCount(a4)

	bra.s	_bap_end

_bap_dosnode:
	ifd	DEBUG
	lea	dbg_boot_part_dos(pc),a0
	bsr	_bootDebug
	lea	DN_BSTR_OFF(a5),a0	;name as registered (post-dedup)
	bsr	_bootDebugBStr
	endc
	move.l	pb_Environment+DE_BOOTPRI*4(a2),d0
	moveq.l	#0,d1
	move.l	d7,a0
	jsr	AddDosNode(a6)
	move.b	#1,BC_HaveNodes(a4)
	addq.b	#1,BC_PartCount(a4)

_bap_end:
	movem.l	(sp)+,d2-d7/a2/a5
	rts

;===========================================================
; _bootMakeExecBSTR: allocate and fill a BSTR copy of a
; NUL-terminated C string for FSSM use.  ptable.library is
; device-agnostic so the caller-supplied name has to be
; converted to a BSTR at runtime.
;
; Called once per BootScanRDB invocation; the result is cached
; in BC_DevNameBSTR and shared across every partition's FSSM.
;
; Input : a0 = NUL-terminated C string, a4 = &BootCtx,
;         a6 = ExecBase
; Output: d0 = BPTR (already >>2) to BSTR, or 0 on failure
;         (Allocation is small and intentionally leaked: it must
;          outlive BootCtx for FSSM consumers to keep using it.
;          Total leak per scan is name_length + 4 bytes.)
;===========================================================
_bootMakeExecBSTR:
	movem.l	d1-d3/a0-a2,-(sp)
	move.l	a0,a1			;a1 = src

;-- count length (clamped to 255 for BSTR)
	moveq.l	#0,d2
_bmb_cnt:
	tst.b	(a1)+
	beq.s	_bmb_cnt_done
	addq.l	#1,d2
	cmp.l	#255,d2
	blo.s	_bmb_cnt
_bmb_cnt_done:

;-- alloc round_up(d2 + 1, 4) bytes; pad to longword for BSTR
	move.l	d2,d0
	addq.l	#1,d0			;include length byte
	addq.l	#3,d0
	and.l	#~3,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	jsr	AllocMem(a6)
	tst.l	d0
	beq.s	_bmb_fail
	move.l	d0,a1			;a1 = BSTR base
	move.b	d2,(a1)+		;length byte
;-- restore saved src ptr from stack: movem.l layout (low->high) is
;-- d1,d2,d3,a0,a1,a2, so the saved a0 lives at 12(sp), not (sp).
	move.l	12(sp),a0		;src ptr (saved a0)
	move.l	d2,d3			;copy d2 chars
	tst.l	d3
	beq.s	_bmb_done
_bmb_cp:
	move.b	(a0)+,(a1)+
	subq.l	#1,d3
	bne.s	_bmb_cp
_bmb_done:
;-- d0 already holds the BSTR base from AllocMem; turn it into a
;-- BPTR in place. movem.l restore touches d1-d3/a0-a2 only, so
;-- d0 carries the result through to the caller.
	lsr.l	#2,d0			;BPTR
	movem.l	(sp)+,d1-d3/a0-a2
	rts
_bmb_fail:
	movem.l	(sp)+,d1-d3/a0-a2
	moveq.l	#0,d0
	rts

;===========================================================
; _bootDedupName: ensure the candidate drive name (BSTR at
; DN_BSTR_OFF in the DN blob) is unique on expansion.library's
; eb_MountList. Mirrors commonly used rule by .device(s):
; if the name already exists, append ".n" (.1, .2, ...) and, if
; a name ending ".n" is also present, bump to ".n+1" and rescan
; from the top.
;
; Input : a4 = &BootCtx, a5 = DN blob (name BSTR at DN_BSTR_OFF)
; Output: BSTR at DN_BSTR_OFF mutated in place if a clash was hit
; Preserves a4/a5/a6/d7 (the caller relies on a5/d7).
;===========================================================
_bootDedupName:
	movem.l	d0-d6/a0-a3,-(sp)
	move.l	BC_ExpBase(a4),a3	;a3 = ExpansionBase
	move.l	a3,d0
	beq.s	_bdn_ret		;no exp.lib -> nothing to check

	lea	DN_BSTR_OFF(a5),a0
	moveq.l	#0,d5
	move.b	(a0),d5			;d5 = original base char count
	moveq.l	#0,d4			;d4 = suffix counter (0 = bare name)

_bdn_retry:
;-- walk eb_MountList (LH at offset 74); entries are BootNodes.
	lea	74(a3),a0		;a0 = &eb_MountList
	move.l	(a0),a1			;a1 = first node (lh_Head)
_bdn_walk:
	move.l	(a1),d0			;ln_Succ
	beq.s	_bdn_unique		;tail sentinel -> name is unique
	move.l	16(a1),a2		;bn_DeviceNode
	move.l	a2,d0
	beq.s	_bdn_next		;NULL device node
	move.l	40(a2),d0		;dn_Name (BPTR)
	beq.s	_bdn_next		;NULL name
	lsl.l	#2,d0
	move.l	d0,a2			;a2 = existing name BSTR
	lea	DN_BSTR_OFF(a5),a0	;a0 = candidate BSTR
	bsr	_bootBStrEqualCI	;Z = equal
	beq.s	_bdn_dup
_bdn_next:
	move.l	(a1),a1			;a1 = ln_Succ
	bra.s	_bdn_walk

_bdn_dup:
	cmp.l	#9999,d4		;defensive cap on suffix value
	bhs.s	_bdn_unique
	addq.l	#1,d4
	bsr	_bootApplySuffix
	bra.s	_bdn_retry

_bdn_unique:
_bdn_ret:
	movem.l	(sp)+,d0-d6/a0-a3
	rts

;===========================================================
; _bootApplySuffix: rewrite the name BSTR in place as
; "<base>.<n>". The base chars stay at DN_BSTR_OFF+1; the dot
; and digits are written strictly to their right, so the base
; prefix we re-read on each bump is never corrupted. If the
; result would exceed the 31-char the base is truncated (the
; suffix is kept, since it guarantees uniqueness).
;
; Input : a5 = DN blob, d4 = suffix value (>=1), d5 = base len
; Preserves all registers.
;===========================================================
_bootApplySuffix:
	movem.l	d0-d3/a0-a2,-(sp)
	lea	-8(sp),sp		;8-byte digit scratch
	move.l	sp,a2			;a2 = scratch base
	move.l	a2,a0			;a0 = scratch write ptr
	moveq.l	#0,d1			;digit count
	move.l	d4,d0			;value to convert
_bas_div:
	divu.w	#10,d0			;d0 = [rem:quot]
	move.w	d0,d2			;d2.w = quotient
	clr.w	d0
	swap	d0			;d0.w = remainder
	add.b	#'0',d0
	move.b	d0,(a0)+		;store digit (least significant first)
	addq.l	#1,d1
	moveq.l	#0,d0
	move.w	d2,d0			;d0 = quotient (zero-extended)
	tst.w	d0
	bne.s	_bas_div

;-- suffixLen = d1 + 1 (the dot); clamp kept base so total <= 31
	move.l	d1,d3
	addq.l	#1,d3			;d3 = suffix length
	move.l	d5,d2			;d2 = kept base length
	move.l	d2,d0
	add.l	d3,d0
	cmp.l	#31,d0
	bls.s	_bas_fits
	moveq.l	#31,d2
	sub.l	d3,d2			;keptBase = 31 - suffixLen
_bas_fits:
;-- length byte
	lea	DN_BSTR_OFF(a5),a1
	move.l	d2,d0
	add.l	d3,d0			;total length
	move.b	d0,(a1)
;-- '.' after the kept base
	lea	1(a1),a1
	add.l	d2,a1
	move.b	#'.',(a1)+
;-- digits, most significant first (scratch holds them reversed)
	move.l	a2,a0
	add.l	d1,a0			;a0 -> one past last stored digit
_bas_wr:
	move.b	-(a0),(a1)+
	cmp.l	a2,a0
	bhi.s	_bas_wr

	lea	8(sp),sp		;free scratch
	movem.l	(sp)+,d0-d3/a0-a2
	rts

;===========================================================
; _bootBStrEqualCI: case-insensitive compare of two BSTRs
;
; Input : a0 = BSTR A, a2 = BSTR B
; Output: d0 = 0 and Z set if equal; d0 = 1 and Z clear if not
; Preserves a0/a1/a2 and d1-d3.
;===========================================================
_bootBStrEqualCI:
	movem.l	d1-d3/a0/a2,-(sp)
	moveq.l	#0,d1
	move.b	(a0)+,d1		;len A
	moveq.l	#0,d2
	move.b	(a2)+,d2		;len B
	cmp.b	d1,d2
	bne.s	_bse_ne
	tst.b	d1
	beq.s	_bse_eq			;both empty
_bse_loop:
	move.b	(a0)+,d2
	move.b	(a2)+,d3
	cmp.b	#'a',d2
	blo.s	_bse_d2ok
	cmp.b	#'z',d2
	bhi.s	_bse_d2ok
	sub.b	#$20,d2			;to upper
_bse_d2ok:
	cmp.b	#'a',d3
	blo.s	_bse_d3ok
	cmp.b	#'z',d3
	bhi.s	_bse_d3ok
	sub.b	#$20,d3
_bse_d3ok:
	cmp.b	d2,d3
	bne.s	_bse_ne
	subq.b	#1,d1
	bne.s	_bse_loop
_bse_eq:
	movem.l	(sp)+,d1-d3/a0/a2
	moveq.l	#0,d0			;0 = equal
	tst.l	d0			;set Z
	rts
_bse_ne:
	movem.l	(sp)+,d1-d3/a0/a2
	moveq.l	#1,d0			;nonzero = not equal
	tst.l	d0			;clear Z
	rts

;===========================================================
; Debug helpers (only assembled in DEBUG builds).
; All callable from BootScanRDB context (a4 = &BootCtx,
; a5 = ExecBase).  Use (_AbsExecBase).w so they remain
; callable even when a6 has been temporarily clobbered.
;===========================================================
	ifd	DEBUG
	include	"raw_debug.i"

_bootDebugHex8:
	movem.l	d0-d3/a6,-(sp)
	move.l	(_AbsExecBase).w,a6
	move.l	d0,d2
	moveq.l	#7,d3
_bdhx_lp:
	rol.l	#4,d2
	move.l	d2,d0
	and.l	#$f,d0
	cmp.b	#10,d0
	blt.s	_bdhx_dec
	add.b	#'A'-10,d0
	bra.s	_bdhx_em
_bdhx_dec:
	add.b	#'0',d0
_bdhx_em:
	jsr	RawPutChar(a6)
	dbra	d3,_bdhx_lp
	movem.l	(sp)+,d0-d3/a6
	rts

_bootDebugDosType:
	movem.l	d0-d3/a0/a6,-(sp)
	move.l	(_AbsExecBase).w,a6
	move.l	d0,d2
	moveq.l	#3,d3
_bddt_lp:
	rol.l	#8,d2
	move.l	d2,d0
	and.l	#$ff,d0
	tst.l	d0
	bne.s	_bddt_em
	moveq.l	#'.',d0
_bddt_em:
	jsr	RawPutChar(a6)
	dbra	d3,_bddt_lp
	movem.l	(sp)+,d0-d3/a0/a6
	rts

_bootDebugDecW:
	movem.l	d0-d5/a6,-(sp)
	move.l	(_AbsExecBase).w,a6
	and.l	#$ffff,d0
	sub.l	#8,sp
	move.l	sp,a0
	moveq.l	#4,d3
_bddw_fill:
	move.l	d0,d2
	divu	#10,d2
	move.l	d2,d1
	swap	d1
	and.l	#$ff,d1
	add.b	#'0',d1
	move.b	d1,0(a0,d3.l)
	move.w	d2,d0
	dbra	d3,_bddw_fill
	moveq.l	#0,d3
_bddw_skip:
	cmp.b	#4,d3
	bge.s	_bddw_print
	move.b	0(a0,d3.l),d0
	cmp.b	#'0',d0
	bne.s	_bddw_print
	addq.l	#1,d3
	bra.s	_bddw_skip
_bddw_print:
	move.b	0(a0,d3.l),d0
	and.l	#$ff,d0
	jsr	RawPutChar(a6)
	addq.l	#1,d3
	cmp.b	#5,d3
	blt.s	_bddw_print
	add.l	#8,sp
	movem.l	(sp)+,d0-d5/a6
	rts

_bootDebugVersionNL:
	movem.l	d0-d2/a0/a6,-(sp)
	move.l	(_AbsExecBase).w,a6
	move.l	d0,d2
	moveq.l	#' ',d0
	jsr	RawPutChar(a6)
	moveq.l	#'v',d0
	jsr	RawPutChar(a6)
	move.l	d2,d0
	swap	d0
	and.l	#$ffff,d0
	bsr	_bootDebugDecW
	moveq.l	#'.',d0
	move.l	(_AbsExecBase).w,a6
	jsr	RawPutChar(a6)
	move.l	d2,d0
	and.l	#$ffff,d0
	bsr	_bootDebugDecW
	move.l	(_AbsExecBase).w,a6
	moveq.l	#13,d0
	jsr	RawPutChar(a6)
	moveq.l	#10,d0
	jsr	RawPutChar(a6)
	movem.l	(sp)+,d0-d2/a0/a6
	rts

;-- Print a BSTR (length byte + chars) followed by CR/LF.
;   a0 = BSTR pointer. Length is clamped to 31 so a garbage
;   length byte in a raw RDB block can't run away.
;   Callers: pb_DriveName (skip path, pre-blob) and the deduped
;   name in the DN blob (DN_BSTR_OFF, +boot/+dos paths).
_bootDebugBStr:
	movem.l	d0/d3/a0/a6,-(sp)
	move.l	(_AbsExecBase).w,a6
	moveq.l	#0,d3
	move.b	(a0)+,d3
	cmp.w	#31,d3
	bls.s	_bdbs_ok
	moveq.l	#31,d3
_bdbs_ok:
	subq.l	#1,d3
	bmi.s	_bdbs_nl
_bdbs_lp:
	moveq.l	#0,d0
	move.b	(a0)+,d0
	jsr	RawPutChar(a6)
	dbra	d3,_bdbs_lp
_bdbs_nl:
	moveq.l	#13,d0
	jsr	RawPutChar(a6)
	moveq.l	#10,d0
	jsr	RawPutChar(a6)
	movem.l	(sp)+,d0/d3/a0/a6
	rts
	endc	;DEBUG
