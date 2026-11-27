; the Gayle PCMCIA disable bit set: FS-UAE drops card detect
	move.b	$da8000,d0
	or.b	#1,d0
	move.b	d0,$da8000
	moveq	#0,d0
	rts
