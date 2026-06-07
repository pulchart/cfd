;===========================================================
; ptable_hunk.s -- mini LoadSeg for cold-start use.
;
; Converts a concatenated HUNK executable (as found in the
; LSEG chain of an RDB FileSysHeader) into a relocated, chained
; SegList suitable for fse_SegList.  Runs before dos.library
; is initialised so InternalLoadSeg is not callable.
;
; Supported hunk ids:
;   HUNK_HEADER  ($3F3): library-name list, table_size, first,
;                        last, per-hunk sizes.
;   HUNK_CODE    ($3E9): copy n longwords into current hunk.
;   HUNK_DATA    ($3EA): copy n longwords into current hunk.
;   HUNK_BSS     ($3EB): skip (memory MEMF_CLEAR already).
;   HUNK_RELOC32 ($3EC): apply 32-bit absolute relocations.
;   HUNK_RELOC32SHORT ($3FC): as RELOC32 but word-encoded.
;   HUNK_SYMBOL  ($3F0): skip symbol records until 0.
;   HUNK_DEBUG   ($3F1): skip n longwords.
;   HUNK_NAME    ($3E8): skip n longwords.
;   HUNK_UNIT    ($3E7): skip n longwords.
;   HUNK_END     ($3F2): advance to next hunk.
;
; Any other id logs "[RDB] hunk: bad id $xxxxxxxx" (DEBUG builds)
; then triggers full teardown (free per-hunk allocs, free scratch
; table, return 0). Caller leaves FileSystem.resource untouched in
; that case.
;
; Input : a2 = pointer to concatenated HUNK image (caller's
;              concat buffer, payload starts at a2[0]).
;         d4 = buffer size in bytes (used for bounds checks).
;         a4 = &BootCtx (for ExecBase).
; Output: d0 = SegList BPTR on success, 0 on failure.
;         Caller retains ownership of the input buffer.
;
; Clobbers: none visible to caller (movem saves d2-d7/a2-a6).
;===========================================================
_bootRelocateHunks:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	a2,a3
	add.l	d4,a3			;a3 = end-of-buffer (exclusive)

;-- 1. verify HUNK_HEADER id
	cmpa.l	a3,a2
	bhs.w	_brh_fail
	cmpi.l	#HUNK_HEADER,(a2)
	bne.w	_brh_fail
	addq.l	#4,a2

;-- 2. skip resident-library-name list: while (n=*a2++) skip n longs
_brh_lib_loop:
	cmpa.l	a3,a2
	bhs.w	_brh_fail
	move.l	(a2)+,d0
	tst.l	d0
	beq.s	_brh_lib_done
	lsl.l	#2,d0
	add.l	d0,a2
	cmpa.l	a3,a2
	bhi.w	_brh_fail
	bra.s	_brh_lib_loop
_brh_lib_done:

;-- 3. table_size (ignored), first_hunk, last_hunk
	lea	12(a2),a0
	cmpa.l	a3,a0
	bhi.w	_brh_fail
	addq.l	#4,a2
	move.l	(a2)+,d2		;first_hunk
	move.l	(a2)+,d3		;last_hunk

;-- 4. count = last - first + 1, clamp to [1..64]
	move.l	d3,d4
	sub.l	d2,d4
	addq.l	#1,d4
	tst.l	d4
	ble.w	_brh_fail
	cmp.l	#64,d4
	bhi.w	_brh_fail

;-- 5. allocate scratch pointer table
	move.l	d4,d0
	lsl.l	#2,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	move.l	BC_ExecBase(a4),a6
	jsr	AllocMem(a6)
	tst.l	d0
	beq.w	_brh_fail
	move.l	d0,a5

;-- 6. allocation pass: alloc each hunk
	moveq.l	#0,d5
_brh_alloc_loop:
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	move.l	(a2)+,d6
	and.l	#$3FFFFFFF,d6
	move.l	d6,d0
	lsl.l	#2,d0
	addq.l	#8,d0
	cmp.l	#$100000,d0		;sanity: cap 1 MiB / hunk
	bhi.w	_brh_teardown
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	move.l	BC_ExecBase(a4),a6
	jsr	AllocMem(a6)
	tst.l	d0
	beq.w	_brh_teardown
	move.l	d0,a0
	move.l	d6,d1
	lsl.l	#2,d1
	addq.l	#8,d1
	move.l	d1,(a0)			;alloc[0] = total bytes (for FreeMem)
	clr.l	4(a0)
	move.l	d5,d0
	lsl.l	#2,d0
	move.l	a0,(a5,d0.l)
	addq.l	#1,d5
	cmp.l	d4,d5
	blo.w	_brh_alloc_loop

;-- 7. chain segments via next-BPTRs
	move.l	d4,d7
	subq.l	#1,d7
	ble.s	_brh_chain_done
	moveq.l	#0,d5
_brh_chain_loop:
	move.l	d5,d0
	lsl.l	#2,d0
	move.l	(a5,d0.l),a0
	move.l	d5,d0
	addq.l	#1,d0
	lsl.l	#2,d0
	move.l	(a5,d0.l),a1
	move.l	a1,d0
	addq.l	#4,d0
	lsr.l	#2,d0
	move.l	d0,4(a0)
	addq.l	#1,d5
	cmp.l	d7,d5
	blo.s	_brh_chain_loop
_brh_chain_done:

;-- 8. walk hunk bodies
	moveq.l	#0,d5
_brh_body_loop:
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	move.l	(a2)+,d0
	cmpi.l	#HUNK_CODE,d0
	beq.w	_brh_copy
	cmpi.l	#HUNK_DATA,d0
	beq.w	_brh_copy
	cmpi.l	#HUNK_BSS,d0
	beq.w	_brh_bss
	cmpi.l	#HUNK_RELOC32,d0
	beq.w	_brh_reloc
	cmpi.l	#HUNK_RELOC32SHORT,d0
	beq.w	_brh_reloc_short
	cmpi.l	#HUNK_SYMBOL,d0
	beq.w	_brh_symbol
	cmpi.l	#HUNK_DEBUG,d0
	beq.w	_brh_skip_n
	cmpi.l	#HUNK_NAME,d0
	beq.w	_brh_skip_n
	cmpi.l	#HUNK_UNIT,d0
	beq.w	_brh_skip_n
	cmpi.l	#HUNK_END,d0
	beq.w	_brh_hunk_end
	bra.w	_brh_unknown

_brh_copy:
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	move.l	(a2)+,d6
	and.l	#$3FFFFFFF,d6
	move.l	a2,d0
	move.l	d6,d1
	lsl.l	#2,d1
	add.l	d1,d0
	cmp.l	a3,d0
	bhi.w	_brh_teardown
	move.l	d5,d0
	lsl.l	#2,d0
	move.l	(a5,d0.l),a1
	;-- verify body size fits the allocation: alloc stores
	;   (header_d6*4 + 8) at offset 0; data area is alloc-8 bytes
	move.l	(a1),d0
	sub.l	#8,d0
	cmp.l	d1,d0
	blo.w	_brh_teardown
	addq.l	#8,a1
	tst.l	d6
	beq.s	_brh_copy_done
_brh_copy_w:
	move.l	(a2)+,(a1)+
	subq.l	#1,d6
	bne.s	_brh_copy_w
_brh_copy_done:
	bra.w	_brh_body_loop

_brh_bss:
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	move.l	(a2)+,d6
	and.l	#$3FFFFFFF,d6
	;-- verify body BSS size fits the allocation
	move.l	d5,d0
	lsl.l	#2,d0
	move.l	(a5,d0.l),a1
	move.l	(a1),d0
	sub.l	#8,d0
	move.l	d6,d1
	lsl.l	#2,d1
	cmp.l	d1,d0
	blo.w	_brh_teardown
	bra.w	_brh_body_loop

_brh_reloc:
	move.l	d5,d0
	lsl.l	#2,d0
	move.l	(a5,d0.l),a0
	addq.l	#8,a0			;a0 = dst-hunk data base
_brh_reloc_outer:
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	move.l	(a2)+,d6
	tst.l	d6
	beq.w	_brh_body_loop
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	move.l	(a2)+,d7
	sub.l	d2,d7
	bmi.w	_brh_teardown
	cmp.l	d4,d7
	bhs.w	_brh_teardown
	move.l	d7,d0
	lsl.l	#2,d0
	move.l	(a5,d0.l),a1
	addq.l	#8,a1
_brh_reloc_inner:
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	move.l	(a2)+,d0
	;-- bounds-check relocation offset against dst hunk's data area;
	;   alloc size header is at -8(a0), data ends at alloc_size-8
	;   bytes, max valid 4-byte write offset = alloc_size-12.
	move.l	-8(a0),d3
	sub.l	#12,d3
	cmp.l	d3,d0
	bhi.w	_brh_teardown
	move.l	a1,d1
	add.l	d1,(a0,d0.l)
	subq.l	#1,d6
	bne.s	_brh_reloc_inner
	bra.w	_brh_reloc_outer

;-- HUNK_RELOC32SHORT: identical fix-up to _brh_reloc but count,
;   target-hunk and offset are UWORDs; the block is longword-padded
;   after the terminating zero count.
_brh_reloc_short:
	move.l	d5,d0
	lsl.l	#2,d0
	move.l	(a5,d0.l),a0
	addq.l	#8,a0			;a0 = dst-hunk data base
_brh_rs_outer:
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	moveq.l	#0,d6
	move.w	(a2)+,d6		;count (UWORD); 0 -> end
	tst.l	d6
	beq.s	_brh_rs_end
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	moveq.l	#0,d7
	move.w	(a2)+,d7		;target hunk number (UWORD)
	sub.l	d2,d7			;d2 = first_hunk
	bmi.w	_brh_teardown
	cmp.l	d4,d7			;d4 = hunk count
	bhs.w	_brh_teardown
	move.l	d7,d0
	lsl.l	#2,d0
	move.l	(a5,d0.l),a1
	addq.l	#8,a1			;a1 = target hunk data base
_brh_rs_inner:
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	moveq.l	#0,d0
	move.w	(a2)+,d0		;offset (UWORD)
	move.l	-8(a0),d3
	sub.l	#12,d3
	cmp.l	d3,d0
	bhi.w	_brh_teardown
	move.l	a1,d1
	add.l	d1,(a0,d0.l)
	subq.l	#1,d6
	bne.s	_brh_rs_inner
	bra.s	_brh_rs_outer
_brh_rs_end:
	move.l	a2,d0			;align cursor up to longword
	addq.l	#3,d0
	and.l	#$FFFFFFFC,d0
	move.l	d0,a2
	bra.w	_brh_body_loop

;-- unrecognized hunk id: log it (DEBUG) and tear down so the
;   load failure is visible rather than silent.
_brh_unknown:
	ifd	DEBUG
	move.l	d0,-(sp)		;preserve id across helpers
	lea	dbg_hunk_badid(pc),a0
	bsr	_bootDebug
	move.l	(sp),d0
	bsr	_bootDebugHex8
	lea	dbg_boot_nl(pc),a0
	bsr	_bootDebug
	move.l	(sp)+,d0
	endc
	bra.w	_brh_teardown

_brh_symbol:
_brh_sym_loop:
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	move.l	(a2)+,d6
	tst.l	d6
	beq.w	_brh_body_loop
	and.l	#$00FFFFFF,d6
	addq.l	#1,d6
	move.l	d6,d0
	lsl.l	#2,d0
	add.l	d0,a2
	cmpa.l	a3,a2
	bhi.w	_brh_teardown
	bra.s	_brh_sym_loop

_brh_skip_n:
	cmpa.l	a3,a2
	bhs.w	_brh_teardown
	move.l	(a2)+,d6
	move.l	d6,d0
	lsl.l	#2,d0
	add.l	d0,a2
	cmpa.l	a3,a2
	bhi.w	_brh_teardown
	bra.w	_brh_body_loop

_brh_hunk_end:
	addq.l	#1,d5
	cmp.l	d4,d5
	blo.w	_brh_body_loop

;-- success: result BPTR = (table[0] + 4) >> 2
	move.l	(a5),a0
	move.l	a0,d7
	addq.l	#4,d7
	lsr.l	#2,d7

	move.l	d4,d0
	lsl.l	#2,d0
	move.l	a5,a1
	move.l	BC_ExecBase(a4),a6
	jsr	FreeMem(a6)

;-- I-cache flush after RELOC32 fixups (required on 68040/060).
	move.l	BC_ExecBase(a4),a6
	jsr	CacheClearU(a6)

	move.l	d7,d0
	movem.l	(sp)+,d2-d7/a2-a6
	rts

_brh_teardown:
	moveq.l	#0,d5
_brh_td_loop:
	cmp.l	d4,d5
	bhs.s	_brh_td_tbl
	move.l	d5,d0
	lsl.l	#2,d0
	move.l	(a5,d0.l),a1
	move.l	a1,d0
	beq.s	_brh_td_next
	move.l	(a1),d0
	move.l	BC_ExecBase(a4),a6
	jsr	FreeMem(a6)
_brh_td_next:
	addq.l	#1,d5
	bra.s	_brh_td_loop
_brh_td_tbl:
	move.l	d4,d0
	lsl.l	#2,d0
	move.l	a5,a1
	move.l	BC_ExecBase(a4),a6
	jsr	FreeMem(a6)
	moveq.l	#0,d0
	movem.l	(sp)+,d2-d7/a2-a6
	rts

_brh_fail:
	moveq.l	#0,d0
	movem.l	(sp)+,d2-d7/a2-a6
	rts
