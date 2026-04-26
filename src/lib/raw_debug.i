;===========================================================
; raw_debug.i -- compile-time-gated raw serial debug helper
;
; Provides _bootDebug: print NUL-terminated string at (a0) via
; Exec/RawPutChar, using (_AbsExecBase).w so a6 may hold any
; value on entry.  All caller registers preserved.
;
; Independent of any per-mount (like Flags=8)
; Body is omitted in non-DEBUG builds.
;
; Required external symbols (must be visible at include site):
;   _AbsExecBase   absolute address (= 4)
;   RawPutChar     LVO offset
;===========================================================

	ifd	DEBUG
_bootDebug:
	movem.l	d0-d1/a0-a1/a6,-(sp)
	move.l	(_AbsExecBase).w,a6
_bdbg_lp:
	moveq.l	#0,d0
	move.b	(a0)+,d0
	beq.s	_bdbg_end
	jsr	RawPutChar(a6)
	bra.s	_bdbg_lp
_bdbg_end:
	movem.l	(sp)+,d0-d1/a0-a1/a6
	rts
	endc
