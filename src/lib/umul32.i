;===========================================================
; umul32.i -- 32-bit unsigned multiply
;
; Macro UMUL32: d0 = d0 * d1 (u32).
; Inlines mulu.l on 68020+; calls UMul32 on 68000.
;===========================================================

UMUL32	macro				;d0 = d0 * d1 (u32)
	ifd	__68020__
	mulu.l	d1,d0
	else
	bsr	UMul32
	endif
	endm

	ifnd	__68020__

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

	endif	;__68020__
