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
