;===========================================================
; ptable_fs.s -- FileSystem.resource open/create/insert + FSE
; build helpers.
;===========================================================

;===========================================================
; _bootAddOneFileSys
; Input:  BC_BlockBuf -> current FileSysHeaderBlock; a4 = &BootCtx
;
; Reads the LSEG chain, concatenates the payload, then either
; relocates HUNK images via _bootRelocateHunks or wraps a
; pre-linked blob as a single-hunk SegList.  Builds a
; FileSysEntry and inserts it into FileSys.resource.
;===========================================================
_bootAddOneFileSys:
	movem.l	d2-d7/a2-a3,-(sp)

;-- snapshot FSHD fields
	move.l	BC_BlockBuf(a4),a0
	move.l	fhb_DosType(a0),d2
	move.l	fhb_SegListBlocks(a0),d3

;-- validate LSEG head BEFORE any allocation
	move.l	d3,d0
	addq.l	#1,d0
	beq.w	_bao_end

;-- duplicate FSHD (256 bytes) so we keep template fields after
;   reading LSEG blocks (which clobber BC_BlockBuf)
	moveq.l	#0,d0
	move.w	#256,d0
	move.l	#MEMF_PUBLIC,d1
	move.l	BC_ExecBase(a4),a6
	jsr	AllocMem(a6)
	tst.l	d0
	beq.w	_bao_end
	move.l	d0,a3
	move.l	BC_BlockBuf(a4),a0
	move.l	a3,a1
	move.l	#256>>2,d0
_bao_fshd_copy:
	move.l	(a0)+,(a1)+
	subq.l	#1,d0
	bne.s	_bao_fshd_copy

;-- skip if a handler with this DosType already exists
	move.l	d2,d0
	bsr	_bootFindFSEntry
	tst.l	d0
	beq.s	_bao_no_dup
	bra.w	_bao_free_fshd
_bao_no_dup:

;-- pass 1: count LSEG payload bytes
	moveq.l	#0,d4
	move.l	d3,d5
_bao_cnt_loop:
	move.l	d5,d0
	bsr	_bootReadBlock
	tst.l	d0
	bne.w	_bao_free_fshd
	move.l	BC_BlockBuf(a4),a0
	cmpi.l	#LSEG_ID,(a0)
	bne.w	_bao_free_fshd
	add.l	#RDB_BLOCK_BYTES-lsb_LoadData,d4
	move.l	lsb_Next(a0),d0
	move.l	d0,d5
	addq.l	#1,d0
	bne.s	_bao_cnt_loop

	tst.l	d4
	beq.w	_bao_free_fshd
	cmp.l	#$100000,d4		;cap at 1 MiB
	bhi.w	_bao_free_fshd

;-- allocate SegList buffer (size + nextBPTR + payload + 0)
	move.l	d4,d0
	add.l	#12,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	move.l	BC_ExecBase(a4),a6
	jsr	AllocMem(a6)
	tst.l	d0
	beq.w	_bao_free_fshd
	move.l	d0,a2

	move.l	d4,d0
	addq.l	#8,d0
	move.l	d0,(a2)

;-- pass 2: copy LSEG payloads
	lea	8(a2),a0
	move.l	d3,d5
_bao_cp_loop:
	move.l	d5,d0
	bsr	_bootReadBlock
	tst.l	d0
	bne.w	_bao_free_seg
	move.l	BC_BlockBuf(a4),a1
	cmpi.l	#LSEG_ID,(a1)
	bne.w	_bao_free_seg
	move.l	lsb_Next(a1),d5
	lea	lsb_LoadData(a1),a1
	move.l	#(RDB_BLOCK_BYTES-lsb_LoadData)>>2,d0
_bao_cp_words:
	move.l	(a1)+,(a0)+
	subq.l	#1,d0
	bne.s	_bao_cp_words
	move.l	d5,d0
	addq.l	#1,d0
	bne.s	_bao_cp_loop

;-- HUNK image vs pre-linked
	cmpi.l	#HUNK_HEADER,8(a2)
	bne.w	_bao_not_hunk

;-- HUNK: relocate via _bootRelocateHunks
	move.l	a2,-(sp)
	lea	8(a2),a2
	bsr	_bootRelocateHunks
	move.l	(sp)+,a2
	tst.l	d0
	beq.w	_bao_free_seg
	move.l	d0,d7
	move.l	BC_ExecBase(a4),a6
	move.l	a2,a1
	move.l	d4,d0
	add.l	#12,d0
	jsr	FreeMem(a6)
	sub.l	a2,a2
	bra.w	_bao_fse_build
_bao_not_hunk:

;-- pre-linked: wrap concat buffer as single-hunk SegList
	move.l	a2,d0
	addq.l	#4,d0
	lsr.l	#2,d0
	move.l	d0,d7

_bao_fse_build:
;-- I-cache flush before publishing the SegList
	move.l	BC_ExecBase(a4),a6
	jsr	CacheClearU(a6)

;-- Build a FileSysEntry; MEMF_REVERSE to keep it high.
	moveq.l	#fse_Sizeof,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR+MEMF_REVERSE,d1
	move.l	BC_ExecBase(a4),a6
	jsr	AllocMem(a6)
	tst.l	d0
	beq.w	_bao_free_seg
	move.l	d0,a0

	move.b	#NT_UNKNOWN,LN_Type(a0)
	move.l	d7,d0			;d7 = relocated SegList BPTR
	bsr	_bootFSName
	move.l	d0,LN_Name(a0)		;handler identity, or 0 -> unnamed
	move.l	d2,fse_DosType(a0)

	move.l	fhb_Version(a3),fse_Version(a0)
	move.l	fhb_PatchFlags(a3),d5
	move.l	d5,fse_PatchFlags(a0)
	move.l	fhb_Type(a3),fse_Type(a0)
	move.l	fhb_Task(a3),fse_Task(a0)
	move.l	fhb_Lock(a3),fse_Lock(a0)
	move.l	fhb_Handler(a3),fse_Handler(a0)
	move.l	fhb_StackSize(a3),fse_StackSize(a0)
	move.l	fhb_Priority(a3),fse_Priority(a0)
	move.l	fhb_Startup(a3),fse_Startup(a0)
	move.l	d7,fse_SegList(a0)
	move.l	fhb_GlobalVec(a3),fse_GlobalVec(a0)

;-- ensure PatchFlags indicates SegList valid (bit 7 = $80)
	or.l	#$80,fse_PatchFlags(a0)

;-- insert into FileSysResource
	move.l	a0,a2
	bsr	_bootInsertFSEntry

	ifd	DEBUG
	movem.l	d0-d1/a0-a1/a6,-(sp)
	lea	dbg_boot_fs_add(pc),a0
	bsr	_bootDebug
	move.l	d2,d0
	bsr	_bootDebugDosType
	move.l	fse_Version(a2),d0
	bsr	_bootDebugVersionNL
	movem.l	(sp)+,d0-d1/a0-a1/a6
	endc

	bra.s	_bao_free_fshd

_bao_free_seg:
	move.l	a2,d0
	beq.s	_bao_free_fshd
	move.l	BC_ExecBase(a4),a6
	move.l	a2,a1
	move.l	d4,d0
	add.l	#12,d0
	jsr	FreeMem(a6)
_bao_free_fshd:
	move.l	BC_ExecBase(a4),a6
	move.l	a3,a1
	moveq.l	#0,d0
	move.w	#256,d0
	jsr	FreeMem(a6)
_bao_end:
	movem.l	(sp)+,d2-d7/a2-a3
	rts

;===========================================================
; _bootFSName: derive a display name for a loaded FS handler by
; scanning its SegList.  Pass A: first self-validating ROMTAG
; ($4AFC with RT_MATCHTAG == its own address) -> RT_IDSTRING, else
; RT_NAME.  Pass B (if no ROMTAG): first "$VER:" cookie.  Else 0.
; Input:  d0 = SegList (BPTR)
; Output: d0 = APTR to a NUL-terminated name, or 0 (unnamed).
; Returned pointers alias into the SegList, which outlives the FSE.
; Preserves all other registers.
;===========================================================
_bootFSName:
	movem.l	d1-d4/a0-a1,-(sp)
	move.l	d0,d4			;d4 = SegList BPTR (kept for pass B)
;-- Pass A: ROMTAG RT_IDSTRING / RT_NAME
	move.l	d4,d1
_bfn_rt_seg:
	tst.l	d1
	beq.w	_bfn_ver
	move.l	d1,d0
	lsl.l	#2,d0
	move.l	d0,a0			;a0 = seg (next-BPTR field)
	move.l	-4(a0),d2
	subq.l	#8,d2			;d2 = data length
	move.l	(a0),d1			;d1 = next seg BPTR
	addq.l	#4,a0			;a0 = data start (absolute addr)
	move.l	d2,d3
	sub.l	#$16,d3			;need a full romtag (0x16 bytes)
	bmi.s	_bfn_rt_seg
_bfn_rt_scan:
	cmpi.w	#$4AFC,(a0)
	bne.s	_bfn_rt_adv
	move.l	2(a0),d0		;RT_MATCHTAG
	cmp.l	a0,d0			;self-pointer? -> genuine romtag
	bne.s	_bfn_rt_adv
	move.l	$12(a0),d0		;RT_IDSTRING
	bne.s	_bfn_ret
	move.l	$0E(a0),d0		;RT_NAME
	bne.s	_bfn_ret
_bfn_rt_adv:
	addq.l	#2,a0
	subq.l	#2,d3
	bpl.s	_bfn_rt_scan
	bra.s	_bfn_rt_seg
;-- Pass B: "$VER:" cookie
_bfn_ver:
	move.l	d4,d1
_bfn_v_seg:
	tst.l	d1
	beq.s	_bfn_none
	move.l	d1,d0
	lsl.l	#2,d0
	move.l	d0,a0
	move.l	-4(a0),d2
	subq.l	#8,d2
	move.l	(a0),d1
	addq.l	#4,a0
	move.l	d2,d3
	subq.l	#5,d3
	bmi.s	_bfn_v_seg
_bfn_v_scan:
	cmpi.b	#'$',(a0)
	bne.s	_bfn_v_adv
	cmpi.b	#'V',1(a0)
	bne.s	_bfn_v_adv
	cmpi.b	#'E',2(a0)
	bne.s	_bfn_v_adv
	cmpi.b	#'R',3(a0)
	bne.s	_bfn_v_adv
	cmpi.b	#':',4(a0)
	bne.s	_bfn_v_adv
	lea	5(a0),a0		;skip "$VER:"
_bfn_v_sp:
	cmpi.b	#' ',(a0)		;skip following space(s)
	bne.s	_bfn_vhit
	addq.l	#1,a0
	bra.s	_bfn_v_sp
_bfn_vhit:
	move.l	a0,d0
	bra.s	_bfn_ret
_bfn_v_adv:
	addq.l	#1,a0
	subq.l	#1,d3
	bpl.s	_bfn_v_scan
	bra.s	_bfn_v_seg
_bfn_none:
	moveq.l	#0,d0
_bfn_ret:
	movem.l	(sp)+,d1-d4/a0-a1
	rts

;===========================================================
; _bootFindFSEntry: look up FileSysEntry by DosType.
; Input:  d0 = DosType
; Output: d0 = entry pointer or 0.
;===========================================================
_bootFindFSEntry:
	movem.l	d2/a2,-(sp)
	move.l	d0,d2
	bsr	_bootGetFSResource
	tst.l	d0
	beq.s	_bff_none
	move.l	d0,a0
	lea	fsr_FileSysEntries(a0),a0
	move.l	(a0),a2
_bff_loop:
	move.l	(a2),d0
	beq.s	_bff_none
	cmp.l	fse_DosType(a2),d2
	beq.s	_bff_hit
	move.l	d0,a2
	bra.s	_bff_loop
_bff_hit:
	move.l	a2,d0
	bra.s	_bff_end
_bff_none:
	moveq.l	#0,d0
_bff_end:
	movem.l	(sp)+,d2/a2
	rts

;===========================================================
; _bootPatchDNfromFSE: apply FSE patches to a DeviceNode
; eagerly, BEFORE AddBootNode (otherwise AddBootNode's empty-DN
; auto-attach silently replaces a custom handler).
;
; Input : a0 = DeviceNode, a1 = FileSysEntry
; Trashes: d0, d1.
;===========================================================
_bootPatchDNfromFSE:
	move.l	fse_PatchFlags(a1),d1
	btst	#0,d1
	beq.s	_pdf_no_type
	move.l	fse_Type(a1),dn_Type(a0)
_pdf_no_type:
	btst	#1,d1
	beq.s	_pdf_no_task
	move.l	fse_Task(a1),dn_Task(a0)
_pdf_no_task:
	btst	#2,d1
	beq.s	_pdf_no_lock
	move.l	fse_Lock(a1),dn_Lock(a0)
_pdf_no_lock:
	btst	#3,d1
	beq.s	_pdf_no_handler
	move.l	fse_Handler(a1),dn_Handler(a0)
_pdf_no_handler:
	btst	#4,d1
	beq.s	_pdf_no_stack
	move.l	fse_StackSize(a1),dn_StackSize(a0)
_pdf_no_stack:
	btst	#5,d1
	beq.s	_pdf_no_pri
	move.l	fse_Priority(a1),dn_Priority(a0)
_pdf_no_pri:
;-- bit 6 (Startup) deliberately skipped (FSSM blob is ours)
	btst	#7,d1
	beq.s	_pdf_no_seg
	move.l	fse_SegList(a1),dn_SegList(a0)
_pdf_no_seg:
	btst	#8,d1
	beq.s	_pdf_no_gv
	move.l	fse_GlobalVec(a1),dn_GlobVec(a0)
_pdf_no_gv:
	rts

;===========================================================
; _bootInsertFSEntry: Forbid + AddHead + Permit
; Input: a2 = FileSysEntry
;===========================================================
_bootInsertFSEntry:
	move.l	a6,-(sp)
	bsr	_bootGetFSResource
	tst.l	d0
	beq.w	_bie_end
	move.l	d0,a0
	lea	fsr_FileSysEntries(a0),a0

	move.l	BC_ExecBase(a4),a6
	jsr	Forbid(a6)
	move.l	a2,a1
	jsr	AddHead(a6)
	jsr	Permit(a6)
_bie_end:
	move.l	(sp)+,a6
	rts

;===========================================================
; _bootGetFSResource: OpenResource(FileSystem.resource); if it
; does not exist yet, allocate + AddResource.  Cache in
; BC_FSResource.
; Output: d0 = resource pointer (or 0 on alloc failure)
;===========================================================
_bootGetFSResource:
	move.l	BC_FSResource(a4),d0
	bne.s	_bfr_end

	move.l	BC_ExecBase(a4),a6
	lea	FileSysResName(pc),a1
	jsr	OpenResource(a6)
	tst.l	d0
	bne.s	_bfr_cache

;-- create a new FileSysResource
	moveq.l	#fsr_Sizeof,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	jsr	AllocMem(a6)
	tst.l	d0
	beq.s	_bfr_end
	move.l	d0,a0
	move.b	#NT_RESOURCE,LN_Type(a0)
	lea	FileSysResName(pc),a1
	move.l	a1,LN_Name(a0)
	lea	s_libname(pc),a1
	move.l	a1,fsr_Creator(a0)
	lea	fsr_FileSysEntries(a0),a1
	move.l	a1,(a1)
	addq.l	#4,(a1)
	clr.l	4(a1)
	move.l	a1,8(a1)

	move.l	a0,-(sp)
	move.l	a0,a1
	jsr	AddResource(a6)
	move.l	(sp)+,d0
_bfr_cache:
	move.l	d0,BC_FSResource(a4)
_bfr_end:
	rts
