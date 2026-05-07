; ptable.library — public interface
;
; Include in both ptable.library and any consumer device's RTF_COLDSTART stub.
; The stub opens ptable.library, calls BootScanRDB, then closes it (a6 = lib base).

;--- LVOs (Exec convention: -6 per entry; Open/Close/Expunge/Reserved = -6..-24) ---

; BootScanRDB(deviceName: a1, unit: d0)  -> d0 = partitions registered, 0 on error
;   Scans RDB on the named Exec device/unit, calls AddBootNode/AddDosNode for each
;   partition, loads handler FSes into FileSysResource, and adds a synthetic ConfigDev
;   (ERTF_DIAGVALID) so the Kickstart strap (early-boot menu) sees the device.

_LVOBootScanRDB	= -30

;--- Resident priorities (RT_PRI) for InitCode ordering -------------------
;
; InitCode runs higher-priority residents first.  Reference points (Hyperion
; 47.x): scsi.device runs at prio 10, Kickstart strap runs at prio -60.
;
; Cold-boot order:
;   PRI_PTABLE_LIB    ptable.library RTF_AUTOINIT       must precede consumers
;   PRI_CFD_DEVICE    compactflash.device RTF_AUTOINIT  AddDevice for our unit
;   (scsi.device)                                       prio 10, not ours
;   PRI_CFD_BOOT      compactflash.boot RTF_COLDSTART   opens ptable.library,
;                                                       calls BootScanRDB
;
PRI_PTABLE_LIB	equ	22
PRI_CFD_DEVICE	equ	21
PRI_CFD_BOOT	equ	9
