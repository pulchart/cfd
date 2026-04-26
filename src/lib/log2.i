;===========================================================
; log2.i -- floor(log2(d0)) for d0 != 0
;
; Macro LOG2: d0 = floor(log2(d0)), d0 != 0.
; Inlines bfffo on 68020+; calls Log2 on 68000.
;===========================================================

LOG2	macro				;d0 = floor(log2(d0)), d0 != 0
	ifd	__68020__
	bfffo	d0{0:32},d0
	eori.w	#31,d0
	else
	bsr	Log2
	endif
	endm

	ifnd	__68020__

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

	endif	;__68020__
