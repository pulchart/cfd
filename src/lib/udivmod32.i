;===========================================================
; udivmod32.i -- 32-bit unsigned divide + modulo
;
; Macro UDIVMOD32: d0 = d0/d1, d1 = d0 mod d1 (u32).
; Inlines divul.l on 68020+; calls UDivMod32 on 68000.
;===========================================================

UDIVMOD32 macro				;d0 = d0/d1, d1 = d0 mod d1 (u32)
	ifd	__68020__
	divul.l	d1,d1:d0
	else
	bsr	UDivMod32
	endif
	endm

	ifnd	__68020__

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

	endif	;__68020__
