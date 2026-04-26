; ptable.library - DiagArea / BootPoint blob
;
; Standalone DiagArea hung off a synthetic ConfigDev's er_Reserved0c
; (ExpansionRom.DiagArea pointer) so the Kickstart strap (early-boot ROM
; code) boot menu renders the device as bootable and, when the user picks
; it, invokes the BootPoint to start dos.library.
;
; DAC_CONFIGTIME (bit 4) in da_Config is REQUIRED: strap's
; sChkBootPoint checks it and skips the BootPoint when it is
; clear.

DAC_CONFIGTIME	= $10

	cnop	0,2
s_rdb_diag_rom:
	dc.b	DAC_CONFIGTIME		;da_Config (bit 4 required)
	dc.b	0			;da_Flags
	dc.w	(s_rdb_diag_end-s_rdb_diag_rom) ;da_Size: bytes copied to RAM
	dc.w	0			;da_DiagPoint: none
	dc.w	(s_rdb_bootpoint-s_rdb_diag_rom) ;da_BootPoint offset
s_rdb_bootpoint:
	;-- a6 = ExecBase (passed by Kickstart strap); a2 = BootNode (passed but unused here)
	lea	s_rdb_dosname(pc),a1
	jsr	FindResident(a6)
	tst.l	d0
	beq.s	_srbp_end
	movea.l	d0,a0
	movea.l	RT_INIT(a0),a0		;dos.library Init vector
	jsr	(a0)			;DOS starts as tasks
_srbp_end:
	rts
s_rdb_dosname:
	dc.b	"dos.library",0
	even
s_rdb_diag_end:
