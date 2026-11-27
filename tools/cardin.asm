; the Gayle PCMCIA disable bit cleared: FS-UAE raises card detect again
	move.b	$da8000,d0
	and.b	#$fe,d0
	move.b	d0,$da8000
	moveq	#0,d0
	rts
