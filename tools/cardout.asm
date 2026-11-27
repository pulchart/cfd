; the card leaves the slot until cardin, through uaelib function 120 of the
; FS-UAE in the amiga-fsuae images; 20 (failed) on any other FS-UAE
UAELIB	= $f0ff60
	move.w	UAELIB,d0
	and.w	#$f000,d0
	cmp.w	#$a000,d0		;a UAE trap: uaelib is there
	bne.s	.fail
	pea	1.w			;remove
	pea	120.w
	jsr	UAELIB
	addq.l	#8,sp
	clr.b	d0
	cmp.l	#$50434d00,d0		;the answer of function 120
	bne.s	.fail
	moveq	#0,d0
	rts
.fail:	moveq	#20,d0
	rts
