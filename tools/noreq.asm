; pr_WindowPtr -1 for the shell process: a missing volume is an error, not a requester
	move.l	4.w,a6
	sub.l	a1,a1
	jsr	-294(a6)
	move.l	d0,a0
	moveq	#-1,d0
	move.l	d0,184(a0)
	moveq	#0,d0
	rts
