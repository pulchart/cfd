;===========================================================
; cfd_pub.i - device offsets shared between compactflash.device and the
; compactflash.automount bringup module. Single source of truth for the few CFD /
; CFU fields the boot/after-DOS code touches by name; the two binaries are built
; and versioned together. (cfd.s documents the full CFD/CFU layout; these live
; here so the automount module need not duplicate them.)
;===========================================================

; CompactFlashDevice (CFD)
CFD_Unit	= 52			;pointer to the (single) CFU
CFD_BootDone	= 56			;byte: RTF_COLDSTART one-shot guard, set once the
					;stub passes its find/guard checks
CFD_DosReady	= 57			;byte: set when DOS is functional (after-DOS)
CFD_PrefsReady	= 58			;byte: cfd.prefs resolved once (no boot retry)
CFD_DosHook	= 59			;byte: RTF_AFTERDOS one-shot guard

; CompactFlashUnit (CFU)
CFU_MountAgent	= 980			;MountAgent Task ptr (0 = none)
CFU_MountSig	= 984			;MountAgent wake signal mask (0 = not ready)
