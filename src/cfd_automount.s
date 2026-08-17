; compactflash.automount - boot / automount bringup for compactflash.device.
;
; Optional companion to compactflash.device. Load it only when you want
; autoboot (ROM) or automount. It carries two romtags:
;
;   * compactflash.automount (RTF_AFTERDOS, FIRST): after DOS is functional,
;     open compactflash.device unit 0 and hold it open, which starts the unit
;     task, the card-detect interrupt and the automount agent. Listed first
;     because LoadModule activates only a file's first romtag, so this one
;     brings it up for a disk install.
;
;   * compactflash.autoboot (RTF_COLDSTART, SECOND): at cold boot, scan the
;     card's RDB and register its partitions (autoboot). Found by the linear
;     ROM scan, so it runs from a flashed Kickstart; LoadModule ignores it
;     (autoboot is pre-DOS, ROM only).
;
; The device itself contains no boot code; omit this module and you get a plain
; mount-only device. It reaches the device by name (FindName, OpenDevice)
; and with ptable.library by LVO; the only private coupling is the handful of
; CFD/CFU offsets in cfd_pub.i.

	include	"cfd_pub.i"		;CFD_BootDone/DosReady/Unit, CFU_Mount*
	include	"ptable_pub.i"		;_LVOBootScanPartitions, PRI_CFD_BOOT
	include	"cfd_automount_version.i"	;FILE_VERSION, VERSION_STRING (Makefile-generated)

_AbsExecBase	= 4

; Exec LVOs
FindResident	= -96
InitResident	= -102
Forbid		= -132
Permit		= -138
AllocMem	= -198
FreeMem		= -210
FindName	= -276
Signal		= -324
CloseLibrary	= -414
OpenDevice	= -444
OpenLibrary	= -552
RawPutChar	= -516			;used by lib/raw_debug.i (DEBUG boot serial)

; Exec base / structure offsets
SB_DeviceList	= 350
LIB_OpenCnt	= 32
LN_Type		= 8
MP_Flags	= 14
MP_MsgList	= 20
MP_Sizeof	= 34
MN_ReplyPort	= 14
MN_Length	= 18
IO_Sizeof	= 56

NT_MSGPORT	= 4
NT_MESSAGE	= 5
NT_UNKNOWN	= 0
PA_IGNORE	= 2
MEMF_PUBLIC	= 1
MEMF_CLEAR	= $10000

; Resident (romtag)
RTC_MATCHWORD	= $4afc
RTF_COLDSTART	= $01
RTF_AFTERDOS	= $04
LF		= 10

INITLIST	macro
	move.l	\1,(\1)
	addq.l	#4,(\1)
	clr.l	4(\1)
	move.l	\1,8(\1)
	endm

;-- Boot-stub-local DEBUG/non-DEBUG branch helpers (fold the tst.l d0 inside, so
;   the OpenLibrary / FindResident call sites stay one line each).
	ifd	DEBUG
DBG_BNE_MSG	macro
	tst.l	d0
	beq.s	.bsdbg_skip\@
	lea	\1(pc),a0
	bsr	_bootDebug
	bra.w	\2
.bsdbg_skip\@:
	endm
DBG_BEQ_MSG	macro
	tst.l	d0
	bne.s	.bsdbg_skip\@
	lea	\1(pc),a0
	bsr	_bootDebug
	bra.w	\2
.bsdbg_skip\@:
	endm
	else
DBG_BNE_MSG	macro
	tst.l	d0
	bne.w	\2
	endm
DBG_BEQ_MSG	macro
	tst.l	d0
	beq.w	\2
	endm
	endc

	moveq.l	#0,d0			;defuse an accidental Shell invocation
	rts

	cnop	0,2
; AFTERDOS romtag (first), so LoadModule activates it.
s_automount_rt:
	dc.w	RTC_MATCHWORD
	dc.l	s_automount_rt
	dc.l	s_autoboot_rt		;EndSkip: continue ROM scan into the COLDSTART romtag
	dc.b	RTF_AFTERDOS
	dc.b	FILE_VERSION
	dc.b	NT_UNKNOWN
	dc.b	-100			;AFTERDOS modules start at -100 (exec.doc)
	dc.l	automount_name
	dc.l	idstring
	dc.l	s_automount

; COLDSTART romtag (second), reached by the ROM scan via EndSkip.
s_autoboot_rt:
	dc.w	RTC_MATCHWORD
	dc.l	s_autoboot_rt
	dc.l	endtag
	dc.b	RTF_COLDSTART
	dc.b	FILE_VERSION
	dc.b	NT_UNKNOWN
	dc.b	PRI_CFD_BOOT		;see ptable_pub.i for priority rationale
	dc.l	autoboot_name
	dc.l	idstring
	dc.l	s_autobootstub

automount_name:
	dc.b	"compactflash.automount",0
autoboot_name:
	dc.b	"compactflash.autoboot",0
devname:
	dc.b	"compactflash.device",0
RdbLibName:
	dc.b	"ptable.library",0
	dc.b	"$VER: "		;tag for Version; rt_IdString points after it
idstring:
	VERSION_STRING
	dc.b	LF,0
	even

	ifd	DEBUG
dbg_bs_no_card:
	dc.b	"[CFD] boot: no PCMCIA card -> skip autoboot",13,10,0
dbg_bs_open:
	dc.b	"[CFD] boot: open ptable.library ...",13,10,0
dbg_bs_preload:
	dc.b	"[CFD] boot: ptable.library already resident",13,10,0
dbg_bs_initres:
	dc.b	"[CFD] boot: ptable.library not preloaded, InitResident()...",13,10,0
dbg_bs_noires:
	dc.b	"[CFD] boot: ptable.library not in ROM list - skip autoboot",13,10,0
dbg_bs_initfail:
	dc.b	"[CFD] boot: ptable.library InitResident failed",13,10,0
dbg_bs_scan:
	dc.b	"[CFD] boot: BootScanPartitions(compactflash.device,0)",13,10,0
	even
	endc

;===========================================================
; _amFindInitDev: find compactflash.device in DeviceList, running its
; romtag init (found by resident name) first when a builder did not
; auto-init it. Shared by both romtag stubs.
; In : a6 = SysBase
; Out: d0 = &CFD (0 = device unavailable);
;      d1 = 1 if this call InitResident'ed the device (first init)
; Clobbers d0/d1/a0/a1.
;===========================================================
_amFindInitDev:
	move.l	d2,-(sp)
	moveq.l	#0,d2			;d2 = did-init flag
	bsr.s	_afd_find
	tst.l	d0
	bne.s	_afd_out
	lea	devname(pc),a1
	jsr	FindResident(a6)
	tst.l	d0
	beq.s	_afd_out		;no resident either -> d0 = 0
	move.l	d0,a1
	sub.l	a0,a0
	jsr	InitResident(a6)
	moveq.l	#1,d2
	bsr.s	_afd_find		;re-find after init -> live &CFD
_afd_out:
	move.l	d2,d1
	move.l	(sp)+,d2
	rts
_afd_find:
	jsr	Forbid(a6)
	lea	SB_DeviceList(a6),a0
	lea	devname(pc),a1
	jsr	FindName(a6)
	move.l	d0,-(sp)		;FindName result across Permit
	jsr	Permit(a6)
	move.l	(sp)+,d0
	rts

;===========================================================
; RTF_AFTERDOS hook ("compactflash.automount")
;
; System-Startup initialises RTF_AFTERDOS modules after the boot volume and all
; remaining filesystems are started, before Startup-Sequence (NDK
; system-startup.doc), the OS-defined "DOS is fully functional" moment. Here:
;   1. ensure the device + unit task + card-detect interrupts + MountAgent exist
;      (OpenDevice unit 0, held open for good), so a card inserted after a
;      cardless boot mounts;
;   2. set CFD_DosReady; the MountAgent defers every event until then (it must
;      not touch dos.library while System-Startup is still building it);
;   3. signal the agent so a deferred cold-boot insert is processed.
; a6 = SysBase.
;===========================================================
s_automount:
	movem.l	d2/a2-a3/a6,-(sp)

;-- find the device; InitResident it (by name) when it is not in DeviceList yet
	bsr	_amFindInitDev
	tst.l	d0
	beq.w	_dr_out
	move.l	d0,a3			;a3 = &CFD
;-- Own one-shot guard. CFD_DosReady is also written by the mount agent, so
;   testing that here can suppress the Signal below, which is the only wake
;   the agent gets on a ROM boot.
	tst.b	CFD_DosHook(a3)
	bne.w	_dr_out
	move.b	#1,CFD_DosHook(a3)

;-- open unit 0 permanently. MsgPort + IOStdReq live in a one-shot public
;   allocation (never freed): the device stays open, the port receives no
;   messages and the request is never reused.
	moveq.l	#MP_Sizeof+IO_Sizeof,d0
	move.l	#MEMF_PUBLIC+MEMF_CLEAR,d1
	jsr	AllocMem(a6)
	tst.l	d0
	beq.w	_dr_out
	move.l	d0,a2			;a2 = MsgPort; +MP_Sizeof = IOStdReq
	move.b	#NT_MSGPORT,LN_Type(a2)
	move.b	#PA_IGNORE,MP_Flags(a2)
	lea	MP_MsgList(a2),a0
	INITLIST a0
	lea	MP_Sizeof(a2),a1	;a1 = IOStdReq
	move.b	#NT_MESSAGE,LN_Type(a1)
	move.w	#IO_Sizeof,MN_Length(a1)
	move.l	a2,MN_ReplyPort(a1)
	lea	devname(pc),a0
	moveq.l	#0,d0			;unit 0
	moveq.l	#0,d1			;flags 0 (serial debug is opt-in via config FLAGS)
	jsr	OpenDevice(a6)
	tst.l	d0
	bne.s	_dr_openfail

;-- DOS is ready: unblock the agent and reprocess deferred events
	move.b	#1,CFD_DosReady(a3)
	move.l	CFD_Unit(a3),d0
	beq.s	_dr_out
	move.l	d0,a0
	move.l	CFU_MountSig(a0),d0
	beq.s	_dr_out
	move.l	CFU_MountAgent(a0),d1
	beq.s	_dr_out
	move.l	d1,a1
	jsr	Signal(a6)
	bra.s	_dr_out

_dr_openfail:
	move.l	a2,a1
	moveq.l	#MP_Sizeof+IO_Sizeof,d0
	jsr	FreeMem(a6)
_dr_out:
	movem.l	(sp)+,d2/a2-a3/a6
	moveq.l	#0,d0
	rts

;===========================================================
; RTF_COLDSTART stub ("compactflash.autoboot")
;
; Runs at cold boot. Ensures the device and ptable.library are initialised
; (find by name; InitResident if a builder did not auto-init them), then scans
; the card's RDB and registers its partitions for autoboot.
;
; Sequence:
;   1. Find/init compactflash.device if not yet in DeviceList.
;   2. Exit early if CFD_BootDone already set (2nd cold-start pass), else set
;      it now: the scan below opens the device, which spawns the mount agent
;      while this runs, and the agent reads the flag.
;   3. Find/init ptable.library; if absent (disk-only install) exit silently
;      (the device still works, only autoboot is unavailable).
;   4. BootScanPartitions("compactflash.device", 0).
;   5. CloseLibrary, return.
; a6 = SysBase.
;===========================================================
s_autobootstub:
	movem.l	d2-d7/a2-a6,-(sp)
	move.l	a6,a5			;a5 = ExecBase

;-- Probe DeviceList; InitResident (by name) if missing.
	move.l	a5,a6
	bsr	_amFindInitDev
	move.l	d0,d7
	beq.w	_bs_done
	tst.l	d1
	beq.s	_bs_devPresent		;was already present -> no OpenCnt bump
;-- Hold the device open (OpenCnt=1) so a whole-machine takeover like
;   WHDLoad, which flushes anything unused, leaves it alone. First init only.
	move.l	d7,a0
	addq.w	#1,LIB_OpenCnt(a0)

_bs_devPresent:
;-- 2nd-pass guard
	move.l	d7,a0
	tst.b	CFD_BootDone(a0)
	bne.w	_bs_done
;-- Mark the cold path as taken BEFORE OpenDevice. The device open below
;   starts the unit task, which spawns the mount agent while this scan is
;   still running; the agent reads this flag to tell a ROM install (wait for
;   the after-DOS hook) from a disk-loaded one (mark DOS ready itself).
	move.b	#1,CFD_BootDone(a0)

;-- No-card pre-gate. Read live Gayle CCDET ($DA8000 bit 6, set =
;   card present); when the slot is empty skip OpenDevice to avoid
;   the unit-task hardware footprint (OwnCard, AddIntServer #5,
;   timer.device) at cold-start.
	btst.b	#6,$00DA8000
	bne.s	_bs_have_card
	ifd	DEBUG
	lea	dbg_bs_no_card(pc),a0
	bsr	_bootDebug
	endc
	bra.w	_bs_done
_bs_have_card:

;-- OpenLibrary "ptable.library", v2 (unified pipeline: BootScanPartitions).
	ifd	DEBUG
	lea	dbg_bs_open(pc),a0
	bsr	_bootDebug
	endc
	moveq.l	#2,d0
	lea	RdbLibName(pc),a1
	jsr	OpenLibrary(a6)
	DBG_BNE_MSG dbg_bs_preload,_bs_libOk

;-- ptable.library not yet initialised; find and init it manually.
;   If absent (disk-only install) FindResident returns NULL, so exit.
	ifd	DEBUG
	lea	dbg_bs_initres(pc),a0
	bsr	_bootDebug
	endc
	lea	RdbLibName(pc),a1
	jsr	FindResident(a6)
	DBG_BEQ_MSG dbg_bs_noires,_bs_done
	move.l	d0,a1			;a1 = &Resident
	sub.l	a0,a0			;a0 = NULL (no SegList)
	jsr	InitResident(a6)
	moveq.l	#2,d0
	lea	RdbLibName(pc),a1
	jsr	OpenLibrary(a6)
	DBG_BEQ_MSG dbg_bs_initfail,_bs_done

_bs_libOk:
	move.l	d0,a3			;a3 = ptable.library base

;-- Keep ptable.library in use so a memory-flush takeover (WHDLoad) won't
;   expunge it once we close it below.
	addq.w	#1,LIB_OpenCnt(a3)

	ifd	DEBUG
	lea	dbg_bs_scan(pc),a0
	bsr	_bootDebug
	endc
	moveq.l	#0,d0			;unit 0
	lea	devname(pc),a1		;deviceName = "compactflash.device"
	move.l	a3,a6
	jsr	_LVOBootScanPartitions(a6)
	move.l	a3,a1
	move.l	a5,a6
	jsr	CloseLibrary(a6)

_bs_done:
	moveq.l	#0,d0
	movem.l	(sp)+,d2-d7/a2-a6
	rts

	include	"lib/raw_debug.i"

	cnop	0,4
endtag:
	end
