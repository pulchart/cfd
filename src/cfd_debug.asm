;*** Serial Debug *******************************************
;
; Serial debug output via RawPutChar (directly to serial port)
; Enable with mount Flags = 8
;
; Usage:
;   DBGMSG <string_label>    - output string if debug enabled
;   DBGCHR <char>            - output single char if debug enabled
;   DBGNUM                   - output d0.l as hex if debug enabled
;

	ifd	DEBUG

DBGMSG	macro
	lea	\1(pc),a0
	bsr.w	_DebugStr
	endm

DBGCHR	macro
	moveq.l	#\1,d0
	bsr.w	_DebugChar
	endm

DBGNUM	macro
	bsr.w	_DebugHex
	endm

	else

DBGMSG	macro
	endm

DBGCHR	macro
	endm

DBGNUM	macro
	endm

	endc

	ifd	DEBUG
;--- _DebugChar: output single char in d0 if debug enabled ---
; d0 = character to output
; a3 = unit, a4 = device
; preserves all registers
_DebugChar:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dc_end
	movem.l	d0-d1/a0-a1/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	jsr	RawPutChar(a6)
	movem.l	(sp)+,d0-d1/a0-a1/a6
_dc_end:
	rts

;--- _DebugStr: output null-terminated string ---
; a0 = pointer to string
; a3 = unit, a4 = device
; preserves all registers
_DebugStr:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_ds_end
	movem.l	d0-d1/a0-a1/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
_ds_loop:
	moveq.l	#0,d0
	move.b	(a0)+,d0
	beq.s	_ds_done
	jsr	RawPutChar(a6)
	bra.s	_ds_loop
_ds_done:
	movem.l	(sp)+,d0-d1/a0-a1/a6
_ds_end:
	rts

;--- _DebugHex: output d0.l as 8-digit hex ---
; d0 = value to output
; a3 = unit, a4 = device
; preserves all registers
_DebugHex:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dh_end
	movem.l	d0-d3/a0-a1/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	move.l	d0,d2
	moveq.l	#7,d3			;8 digits
_dh_loop:
	rol.l	#4,d2
	moveq.l	#$0f,d0
	and.l	d2,d0
	cmp.b	#10,d0
	bcs.s	_dh_digit
	addq.b	#'A'-'0'-10,d0
_dh_digit:
	add.b	#'0',d0
	jsr	RawPutChar(a6)
	dbra	d3,_dh_loop
	movem.l	(sp)+,d0-d3/a0-a1/a6
_dh_end:
	rts

;--- _DebugNewline: output CR+LF ---
_DebugNewline:
	moveq.l	#13,d0
	bsr.s	_DebugChar
	moveq.l	#10,d0
	bra.s	_DebugChar

;--- _DebugATAStr: output ATA string ---
; a0 = pointer to ATA string
; d1 = length in bytes
; Note: uses d2 for loop counter since RawPutChar clobbers d0-d1
; Spaces are shown as dots for visibility
_DebugATAStr:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_das_end
	movem.l	d0-d2/a0-a1/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	subq.w	#1,d1
	move.w	d1,d2			;use d2 as loop counter (RawPutChar clobbers d1)
_das_loop:
	moveq.l	#0,d0
	move.b	(a0)+,d0		;read byte in normal order
	beq.s	_das_skip
	cmp.b	#' ',d0
	bcs.s	_das_skip		;skip if < space
	bne.s	_das_print		;print if > space
	moveq.l	#'.',d0			;replace space with dot
_das_print:
	jsr	RawPutChar(a6)
_das_skip:
	dbra	d2,_das_loop		;d2 is safe from RawPutChar
	movem.l	(sp)+,d0-d2/a0-a1/a6
_das_end:
	rts

;--- _DebugCardInfo: output card identification ---
; Call after successful _GetIDEID
_DebugCardInfo:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dci_end
	movem.l	d0-d1/a0,-(sp)

	;Model name (words 27-46, offset 54, 40 bytes)
	DBGMSG	dbg_model
	lea	CFU_ConfigBlock+54(a3),a0
	moveq.l	#40,d1
	bsr.w	_DebugATAStr
	bsr.w	_DebugNewline

	;Serial number (words 10-19, offset 20, 20 bytes)
	DBGMSG	dbg_serial
	lea	CFU_ConfigBlock+20(a3),a0
	moveq.l	#20,d1
	bsr.w	_DebugATAStr
	bsr.w	_DebugNewline

	;Firmware (words 23-26, offset 46, 8 bytes)
	DBGMSG	dbg_firmware
	lea	CFU_ConfigBlock+46(a3),a0
	moveq.l	#8,d1
	bsr.w	_DebugATAStr
	bsr.w	_DebugNewline

	movem.l	(sp)+,d0-d1/a0
_dci_end:
	rts

;--- _DebugHexDump: dump IDENTIFY structure (512 bytes) ---
; Outputs 32 lines of 16 bytes each with offset
_DebugHexDump:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.w	_dhd_end
	movem.l	d0-d4/a0-a1/a6,-(sp)

	DBGMSG	dbg_identify_raw

	move.l	CFD_ExecBase(a4),a6
	lea	CFU_ConfigBlock(a3),a0
	moveq.l	#0,d3			;word counter (0,8,16,...248)
	moveq.l	#31,d4			;32 lines (0-31)

_dhd_line:
	;print word offset (W0, W8, W16... W248)
	moveq.l	#'W',d0
	jsr	RawPutChar(a6)
	move.w	d3,d0
	bsr.w	_DebugDecimal		;output decimal number
	moveq.l	#':',d0
	jsr	RawPutChar(a6)
	moveq.l	#' ',d0
	jsr	RawPutChar(a6)

	;print 8 words per line
	moveq.l	#7,d2
_dhd_word:
	move.w	(a0)+,d0
	bsr.w	_DebugHexWord
	moveq.l	#' ',d0
	jsr	RawPutChar(a6)
	dbra	d2,_dhd_word
	addq.w	#8,d3			;next line starts at word+8

	;newline
	moveq.l	#13,d0
	jsr	RawPutChar(a6)
	moveq.l	#10,d0
	jsr	RawPutChar(a6)

	dbra	d4,_dhd_line

	movem.l	(sp)+,d0-d4/a0-a1/a6
_dhd_end:
	rts

;--- _DebugHexByte: output d0.b as 2-digit hex ---
_DebugHexByte:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dhb_end
	movem.l	d0-d2/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	move.b	d0,d2
	lsr.b	#4,d0
	bsr.s	_dhb_digit
	move.b	d2,d0
	and.b	#$0f,d0
	bsr.s	_dhb_digit
	movem.l	(sp)+,d0-d2/a6
_dhb_end:
	rts
_dhb_digit:
	cmp.b	#10,d0
	bcs.s	_dhb_09
	add.b	#'A'-10,d0
	jmp	RawPutChar(a6)
_dhb_09:
	add.b	#'0',d0
	jmp	RawPutChar(a6)

;--- _DebugIdentifyFields: show labeled IDENTIFY fields ---
; Note: uses a2 for config block pointer (DBGMSG clobbers a0)
_DebugIdentifyFields:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.w	_dif_end
	movem.l	d0/a0/a2/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	lea	CFU_ConfigBlock(a3),a2

	DBGMSG	dbg_identify_dump

	;Word 47: Max multi-sector
	DBGMSG	dbg_id_maxmulti
	move.w	94(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline

	;Word 49: Capabilities
	DBGMSG	dbg_id_caps
	move.w	98(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline

	;Word 59: Multi-sector setting
	DBGMSG	dbg_id_multisect
	move.w	118(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline

	;Words 60-61: LBA capacity (swap words for display)
	DBGMSG	dbg_id_lba
	move.w	122(a2),d0		;Word 61 (high)
	bsr.w	_DebugHexWord
	move.w	120(a2),d0		;Word 60 (low)
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline

	;Word 63: Multiword DMA
	DBGMSG	dbg_id_dma
	move.w	126(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline

	;Word 64: PIO modes
	DBGMSG	dbg_id_pio
	move.w	128(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline

	;Word 88: Ultra DMA
	DBGMSG	dbg_id_udma
	move.w	176(a2),d0
	bsr.w	_DebugHexWord
	bsr.w	_DebugNewline

	movem.l	(sp)+,d0/a0/a2/a6
_dif_end:
	rts

;--- _DebugHexWord: output d0.w as 4-digit hex ---
_DebugHexWord:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dhw_end
	movem.l	d0-d1/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	move.w	d0,d1
	lsr.w	#8,d0
	bsr.w	_DebugHexByte
	move.w	d1,d0
	bsr.w	_DebugHexByte
	movem.l	(sp)+,d0-d1/a6
_dhw_end:
	rts

;--- _DebugTransferMode: show transfer mode (WORD/BYTE) ---
_DebugTransferMode:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dtm_end
	DBGMSG	dbg_transfer
	tst.b	CFU_WriteMode(a3)
	bne.s	_dtm_byte
	DBGMSG	dbg_word
	bra.s	_dtm_end
_dtm_byte:
	DBGMSG	dbg_byte
_dtm_end:
	rts

;--- _DebugDecimal: output d0.w as decimal (0-255) ---
; Uses stack to preserve values across RawPutChar calls
_DebugDecimal:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dd_end
	movem.l	d0-d3/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6
	moveq.l	#0,d2
	move.w	d0,d2			;d2 = value (preserved)
	moveq.l	#0,d3			;d3 = leading zero flag

	;hundreds digit
	moveq.l	#0,d0
_dd_h_loop:
	cmp.w	#100,d2
	bcs.s	_dd_h_done
	sub.w	#100,d2
	addq.w	#1,d0
	bra.s	_dd_h_loop
_dd_h_done:
	tst.w	d0
	beq.s	_dd_tens
	add.b	#'0',d0
	move.w	d2,-(sp)		;save d2
	jsr	RawPutChar(a6)
	move.w	(sp)+,d2		;restore d2
	moveq.l	#1,d3			;set leading flag

_dd_tens:
	;tens digit
	moveq.l	#0,d0
_dd_t_loop:
	cmp.w	#10,d2
	bcs.s	_dd_t_done
	sub.w	#10,d2
	addq.w	#1,d0
	bra.s	_dd_t_loop
_dd_t_done:
	tst.w	d0
	bne.s	_dd_t_print
	tst.w	d3
	beq.s	_dd_ones		;skip leading zero
_dd_t_print:
	add.b	#'0',d0
	move.w	d2,-(sp)		;save d2
	jsr	RawPutChar(a6)
	move.w	(sp)+,d2		;restore d2

_dd_ones:
	;ones digit (always print)
	move.w	d2,d0
	add.b	#'0',d0
	jsr	RawPutChar(a6)

	movem.l	(sp)+,d0-d3/a6
_dd_end:
	rts

;--- _DebugDecimal32: output d0.l as unsigned decimal ---
; Prints 0..4294967295 using repeated /10.
; (Uses two DIVU steps to get a full 32-bit quotient.)
_DebugDecimal32:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dd32_end
	movem.l	d1-d5/a0/a6,-(sp)
	move.l	CFD_ExecBase(a4),a6

	move.l	sp,a0			;marker for digit stack (after saved regs)
	tst.l	d0
	bne.s	_dd32_loop
	; special case: 0
	moveq.l	#'0',d1
	move.l	d1,d0
	jsr	RawPutChar(a6)
	bra.s	_dd32_restore

_dd32_loop:
	; compute q = d0 / 10, r = d0 % 10
	; step 1: divide high word by 10 -> quotient_hi (16), rem_hi (0..9)
	move.l	d0,d1
	swap	d1			;d1.w = high word
	and.l	#$0000ffff,d1
	divu	#10,d1			;d1 = (rem_hi<<16) | quot_hi
	move.w	d1,d2			;quot_hi
	swap	d1
	move.w	d1,d3			;rem_hi

	; step 2: divide (rem_hi<<16 | low word) by 10 -> quotient_lo, remainder
	moveq.l	#0,d1
	move.w	d3,d1
	swap	d1			;rem_hi<<16
	move.w	d0,d1			;add low word
	divu	#10,d1			;d1 = (rem<<16) | quot_lo
	move.w	d1,d4			;quot_lo
	swap	d1
	move.w	d1,d5			;remainder (0..9)

	; new d0 = (quot_hi<<16) | quot_lo
	move.w	d2,d0
	swap	d0
	move.w	d4,d0

	; push digit character
	add.b	#'0',d5
	move.b	d5,-(sp)

	tst.l	d0
	bne.s	_dd32_loop

_dd32_out:
	cmp.l	sp,a0
	beq.s	_dd32_restore
	moveq.l	#0,d0
	move.b	(sp)+,d0
	jsr	RawPutChar(a6)
	bra.s	_dd32_out

_dd32_restore:
	movem.l	(sp)+,d1-d5/a0/a6
_dd32_end:
	rts

;--- _DebugIDEStatus: show IDE status and error registers ---
; d0 = status register value
_DebugIDEStatus:
	btst	#3,CFU_OpenFlags+1(a3)
	beq.s	_dis_end
	movem.l	d0-d1/a0,-(sp)
	move.l	d0,d1			;save status
	DBGMSG	dbg_idestatus
	move.l	d1,d0
	bsr.w	_DebugHex
	bsr.w	_DebugNewline
	DBGMSG	dbg_ideerr
	;Read error register
	move.l	CFU_IDEAddr(a3),a0
	moveq.l	#0,d0
	move.b	2(a0),d0		;error register at offset 2
	bsr.w	_DebugHex
	bsr.w	_DebugNewline
	movem.l	(sp)+,d0-d1/a0
_dis_end:
	rts
	endc
