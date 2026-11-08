; cfd.prefs: one question per section, then write ENVARC: and optionally ENV:
(set setup-text "; compactflash.device config, written by Setup\n")
(set setup-text
  (cat setup-text "AUTOMOUNT "
    (if
      (askbool
        (prompt "Mount the partitions of an inserted card automatically?")
        (help (cat "Yes (default): when you insert a card, its partitions appear as volumes "
                   "on their own. Best with compactflash.device in ROM or loaded at boot "
                   "with LoadModule (Install offers that line in Expert mode).\n\n"
                   "No: nothing is mounted on insert. Only mountlists in DEVS:DOSDrivers or "
                   "a manual Mount do it.\n\n(AUTOMOUNT)"))
        (default 1))
      "1" "0")
    "\n"))
(set setup-um
  (askoptions
    (prompt "Filesystems to unmount fully when the card is removed")
    (help (cat "Which filesystems are fully unmounted when you pull a card.\n\nTicked (default " "all): the handler is stopped and freed.\n\nUnticked: its handler stays in " "memory after the card is pulled.\n\n(UNMOUNT)"))
    (choices "DOS/FFS" "SFS" "PFS" "FAT")
    (default 15)))
(if (= setup-um 0)
  (set setup-text (cat setup-text "UNMOUNT NONE\n"))
  (if (<> setup-um 15)
    (set setup-text
      (cat setup-text "UNMOUNT"
        (if (in setup-um 0) " DOS FFS" "")
        (if (in setup-um 1) " SFS" "")
        (if (in setup-um 2) " PFS" "")
        (if (in setup-um 3) " FAT" "")
        "\n"))))
(set setup-static-help
  (cat "These apply only to partitions you mount yourself with a mountlist in "
       "DEVS:DOSDrivers.\n\n"
       "Do not unmount static mounts (default ticked): pulling the card does not "
       "stop their handler, the volume shows as absent. (UNMOUNT_STATIC 0)"))
(if (= @user-level 2)
  (set setup-static
    (askoptions
      (prompt "Static mounts (mountlists in DEVS:DOSDrivers)")
      (help (cat setup-static-help "\n\n"
                 "Allow mounting an already mounted partition (default off): such a "
                 "mount may use a partition that is already mounted. Two handlers then "
                 "share one volume and any write damages it. (MOUNT_USED 1)"))
      (choices "Do not unmount static mounts on removal"
               "Allow mounting an already mounted partition (risky)")
      (default 1)))
  (set setup-static
    (askoptions
      (prompt "Static mounts (mountlists in DEVS:DOSDrivers)")
      (help setup-static-help)
      (choices "Do not unmount static mounts on removal")
      (default 1))))
(if (in setup-static 0) (set setup-text (cat setup-text "UNMOUNT_STATIC 0\n")))
(if (in setup-static 1) (set setup-text (cat setup-text "MOUNT_USED 1\n")))
; value of the first line with pv-key in pv-file into pv-value, "" when absent
; or commented; Search matches anywhere in a line, getenv returns the first line
(procedure P_PREFS_VALUE
  (set pv-value "")
  (if (<> pv-file "")
    (
      (run (cat "Search >ENV:cfdsetup " pv-file " \"" pv-key "#?\" PATTERN NONUM"))
      (set pv-out (getenv "cfdsetup"))
      (if (exists "ENV:cfdsetup") (delete "ENV:cfdsetup"))
      (if (or (= (substr pv-out 0 1) ";") (= (substr pv-out 0 1) "#"))
        (set pv-out ""))
      (set pv-k (strlen pv-key))
      (set pv-end (- (strlen pv-out) pv-k))
      (set pv-i 0)
      (set pv-pos -1)
      (while (<= pv-i pv-end)
        (if (= (substr pv-out pv-i pv-k) pv-key)
          (
            (set pv-pos (+ pv-i pv-k))
            (set pv-i (+ pv-end 1)))
          (set pv-i (+ pv-i 1))))
      (if (>= pv-pos 0)
        (
          (set pv-n (strlen pv-out))
          (set pv-go 1)
          (while pv-go
            (if (>= pv-pos pv-n)
              (set pv-go 0)
              (if (= (substr pv-out pv-pos 1) " ")
                (set pv-pos (+ pv-pos 1))
                (set pv-go 0))))
          (set pv-j pv-pos)
          (set pv-go 1)
          (while pv-go
            (if (>= pv-j pv-n)
              (set pv-go 0)
              (if (= (substr pv-out pv-j 1) "\n")
                (set pv-go 0)
                (set pv-j (+ pv-j 1)))))
          (set pv-value (substr pv-out pv-pos (- pv-j pv-pos))))))))
;- - per-filesystem handler keys: <kind>_<fs-key>, fs-alt read when missing - -
(procedure P_FS_KEY
  (set pv-key (cat fk-kind fs-key))
  (P_PREFS_VALUE)
  (if (and (= pv-value "") (<> fs-alt ""))
    (
      (set pv-key (cat fk-kind fs-alt))
      (P_PREFS_VALUE))))
; saved HANDLER/FORCE/STACK/PRI of fs-key into fs-old-h/-f/-s/-p,
; fs-any = 1 when any of them is set
(procedure P_FS_OLD
  (set fk-kind "HANDLER_")
  (P_FS_KEY)
  (set fs-old-h pv-value)
  (set fk-kind "FORCE_")
  (P_FS_KEY)
  (set fs-fv pv-value)
  (set fs-on (substr fs-fv 0 1))
  (set fs-on2 (substr fs-fv 0 2))
  (set fs-old-f
    (or (= fs-on "1") (= fs-on "Y") (= fs-on "y")
        (= fs-on2 "ON") (= fs-on2 "On") (= fs-on2 "on")))
  (set fk-kind "STACK_")
  (P_FS_KEY)
  (set fs-old-s pv-value)
  (set fk-kind "PRI_")
  (P_FS_KEY)
  (set fs-old-p pv-value)
  (set fs-any (<> (cat fs-old-h fs-fv fs-old-s fs-old-p) "")))
; handler page for fs-key after P_FS_OLD: resident only, a file
; when not resident, or a file over a resident one (FORCE)
(procedure P_FS_HANDLER
  (if (> (strlen fs-old-h) 23) (set fs-old-h ""))
  (set fs-sel
    (askchoice
      (prompt (cat "Handler for " fs-key " partitions"))
      (help (cat "Resident only (default): " fs-key " partitions mount only when "
                 "its handler is in ROM, in the card's RDB or already loaded.\n\n"
                 "Handler file if not resident: that file is loaded when nothing "
                 "resident serves the partition. (HANDLER_" fs-key ")\n\n"
                 "Handler file, also over a resident one: the file is used even "
                 "when a handler is resident, e.g. a newer version. (HANDLER_"
                 fs-key ", FORCE_" fs-key ")"))
      (choices (cat "Resident " fs-key " handler only")
               (cat "Handler file if no " fs-key " handler is resident")
               (cat "Handler file, also over a resident " fs-key))
      (default
        (if (= fs-old-h "") 0 (if fs-old-f 2 1)))))
  (if (> fs-sel 0)
    (
      (set fs-h "")
      (while (or (= fs-h "") (> (strlen fs-h) 23))
        (set fs-h
          (askstring
            (prompt (cat "Handler file for " fs-key ", at most 23 characters"))
            (help "A path such as L:SmartFilesystem or L:pfs3aio.")
            (default fs-old-h))))
      (set setup-text (cat setup-text "HANDLER_" fs-key " " fs-h "\n"))
      (if (= fs-sel 2)
        (set setup-text (cat setup-text "FORCE_" fs-key " 1\n"))))))
; Expert: stack and priority of the fs-key handler after P_FS_OLD, empty =
; its own; other levels keep the saved values
(procedure P_FS_TUNE
  (set fs-s fs-old-s)
  (set fs-p fs-old-p)
  (if (= @user-level 2)
    (
      (set fs-s "x")
      (while (not (or (= fs-s "") (patmatch "[0-9]#[0-9]" fs-s)))
        (set fs-s
          (askstring
            (prompt (cat fs-key " handler stack in bytes (empty: its own)"))
            (help (cat "Minimum stack for the " fs-key " handler task. A "
                       "larger value from the handler itself is kept. (STACK_"
                       fs-key ")"))
            (default fs-old-s))))
      (set fs-p "x")
      (while (not (or (= fs-p "") (patmatch "[0-9]#[0-9]" fs-p)
                      (patmatch "-[0-9]#[0-9]" fs-p)))
        (set fs-p
          (askstring
            (prompt (cat fs-key " handler task priority (empty: its own)"))
            (help (cat "Task priority of the " fs-key " handler, e.g. 5 or "
                       "-1. (PRI_" fs-key ")"))
            (default fs-old-p))))))
  (if (<> fs-s "") (set setup-text (cat setup-text "STACK_" fs-key " " fs-s "\n")))
  (if (<> fs-p "") (set setup-text (cat setup-text "PRI_" fs-key " " fs-p "\n"))))
(set pv-file
  (if (exists "ENVARC:cfd.prefs") "ENVARC:cfd.prefs"
    (if (exists "ENV:cfd.prefs") "ENV:cfd.prefs" "")))
;- - filesystem handlers: pick which, then one page each - -
; fs-key/fs-alt of handler page fs-n: 0 FFS, 1 SFS, 2 PFS
(procedure P_FS_SEL
  (set fs-key (if (= fs-n 0) "FFS" (if (= fs-n 1) "SFS" "PFS")))
  (set fs-alt (if (= fs-n 0) "DOS" "")))
(set fs-cfg-dflt 8)
(set fs-n 0)
(set fs-bit 1)
(while (< fs-n 3)
  (P_FS_SEL)
  (P_FS_OLD)
  (if fs-any (set fs-cfg-dflt (+ fs-cfg-dflt fs-bit)))
  (set fs-bit (+ fs-bit fs-bit))
  (set fs-n (+ fs-n 1)))
(set fs-cfg
  (askoptions
    (prompt "Set the handler for these filesystems")
    (help (cat "Ticked: the next pages ask how its handler is found. Unticked: "
               "it is mounted with a resident handler only.\n\nFAT (default "
               "ticked): fat95, CrossDOS or another FAT handler.\n\nDOS/FFS, "
               "SFS, PFS (default unticked): for an SFS or PFS3 partition on an "
               "RDB card whose handler is neither in ROM nor in the RDB, or to "
               "load a newer FastFileSystem than the ROM one."))
    (choices "DOS/FFS" "SFS" "PFS" "FAT")
    (default fs-cfg-dflt)))
(set fs-n 0)
(while (< fs-n 3)
  (if (in fs-cfg fs-n)
    (
      (P_FS_SEL)
      (P_FS_OLD)
      (P_FS_HANDLER)
      (P_FS_TUNE)))
  (set fs-n (+ fs-n 1)))
; FAT unticked: fat95 if resident, its options are still asked
(set setup-fat 0)
(if (in fs-cfg 3)
  (
    (set pv-key "DOSTYPE_FAT")
    (P_PREFS_VALUE)
    (set setup-old-dt pv-value)
    (set fs-key "FAT")
    (set fs-alt "")
    (P_FS_OLD)
    (set setup-fat-dflt
      (if (= setup-old-dt "")
        (if (= fs-old-h "") 0
          (if (= fs-old-h "L:fat95") (if fs-old-f 2 1) 4))
        (if (and (= setup-old-dt "0x4D534400")
                 (= fs-old-h "L:CrossDOSFileSystem")) 3 4)))
    (set setup-fat
      (askchoice
        (prompt "Filesystem for FAT partitions")
        (help (cat "Which filesystem mounts PC (FAT) partitions.\n\n"
                   "fat95 if resident (default): FAT partitions get the fat95 DosType. They "
                   "mount only when fat95 is resident (in ROM or loaded with LoadModule), "
                   "otherwise they stay unmounted.\n\n"
                   "fat95, loaded from L:fat95: as above, and L:fat95 is loaded when fat95 "
                   "is not resident. (HANDLER_FAT)\n\n"
                   "fat95, always from L:fat95: L:fat95 is used even when a fat95 is "
                   "resident, e.g. a newer one than in ROM. (HANDLER_FAT, FORCE_FAT)\n\n"
                   "CrossDOS: the AmigaOS FAT filesystem instead of fat95. It is loaded "
                   "only from L:CrossDOSFileSystem, so that file must exist. "
                   "(DOSTYPE_FAT, HANDLER_FAT)\n\n"
                   "Other DosType: you enter the DosType and, optionally, the handler to "
                   "load when nothing resident serves it. (DOSTYPE_FAT, HANDLER_FAT)"))
        (choices "fat95 if resident, else nothing"
                 "fat95, loaded from L:fat95 if not resident"
                 "fat95, always loaded from L:fat95"
                 "CrossDOS, loaded from L:CrossDOSFileSystem"
                 "Other DosType")
        (default setup-fat-dflt)))
    (if (= setup-fat 1) (set setup-text (cat setup-text "HANDLER_FAT L:fat95\n")))
    (if (= setup-fat 2) (set setup-text (cat setup-text "HANDLER_FAT L:fat95\nFORCE_FAT 1\n")))
    (if (= setup-fat 3) (set setup-text (cat setup-text "DOSTYPE_FAT 0x4D534400\nHANDLER_FAT L:CrossDOSFileSystem\n")))
    (if (= setup-fat 4)
      (
        (set setup-dt "")
        (set setup-dt-dflt setup-old-dt)
        (while (= setup-dt "")
          (set setup-dt
            (askstring
              (prompt "DosType for FAT partitions (required), for example 0x4D534400")
              (help (cat "The DosType FAT partitions are mounted with. It selects the "
                         "filesystem, written in hex as 0x4D534400. (DOSTYPE_FAT)"))
              (default setup-dt-dflt))))
        (set setup-text (cat setup-text "DOSTYPE_FAT " setup-dt "\n"))
        (set setup-h
          (askstring
            (prompt "Handler to load if that DosType is not resident (optional)")
            (help (cat "A path such as L:MyFileSystem, at most 23 characters. Not needed "
                       "when the filesystem handler is resident and registered in "
                       "FileSystem.resource for that DosType. Then leave it empty. "
                       "(HANDLER_FAT)"))
            (default fs-old-h)))
        (while (> (strlen setup-h) 23)
          (set setup-h
            (askstring
              (prompt "Handler path, at most 23 characters (optional)")
              (help (cat "Not needed when the filesystem handler is resident and registered "
                         "in FileSystem.resource for that DosType. Then leave it empty."))
              (default setup-h))))
        (if (<> setup-h "") (set setup-text (cat setup-text "HANDLER_FAT " setup-h "\n")))))
    (P_FS_TUNE)))
(if (< setup-fat 3)
  (
    (set setup-fat95-help
      (cat "Direct SCSI: read and write with direct SCSI commands, for disks over "
           "4 GB. (s)\n\n"
           "Extra datestamps: creation and last access dates as file comments. The "
           "last access date is updated on every read, so reading also writes to the "
           "card. (d, D)\n\n"
           "Lowercase 8.3 names: show short names as test.txt. (l)\n\n"
           "Uppercase initial: show short names as Test.txt. (L)\n\n"
           "No requesters (default ticked): if a card is pulled while files are open, "
           "no \"please reinsert\" or error windows appear, the program gets the "
           "error instead. (q)"))
    (if (= @user-level 2)
      (set setup-fat95
        (askoptions
          (prompt "fat95 options for FAT partitions on MBR/GPT cards (CONTROL_FAT)")
          (help (cat setup-fat95-help "\n\n"
                     "Mount already mounted: fat95 may mount a partition another handler "
                     "already serves (any write corrupts it). (m)\n\n"
                     "All others are off by default."))
          (choices "Direct SCSI reads and writes"
                   "Extra datestamps and last access date"
                   "Lowercase 8.3 names"
                   "Uppercase initial in 8.3 names"
                   "No requesters when a card is pulled"
                   "Mount already mounted partitions (risky)")
          (default 16)))
      (set setup-fat95
        (askoptions
          (prompt "fat95 options for FAT partitions on MBR/GPT cards (CONTROL_FAT)")
          (help (cat setup-fat95-help "\n\nAll others are off by default."))
          (choices "Direct SCSI reads and writes"
                   "Extra datestamps and last access date"
                   "Lowercase 8.3 names"
                   "Uppercase initial in 8.3 names"
                   "No requesters when a card is pulled")
          (default 16))))
    (set setup-text
      (cat setup-text "CONTROL_FAT "
        (if (in setup-fat95 1) "+d+D" "-d-D")
        (if (in setup-fat95 4) "+q" "-q")
        (if (in setup-fat95 0) "+s" "")
        (if (in setup-fat95 2) "+l" "")
        (if (in setup-fat95 3) "+L" "")
        (if (in setup-fat95 5) "+m" "")
        "\n"))))
(if (= @user-level 2)
  (set setup-flags
    (askoptions
      (prompt "Driver flags (for troubleshooting, default none)")
      (help (cat "cfd first: workaround for PCMCIA conflicts with other drivers. (1)\n\n"
                 "Compatibility: access the card through card.resource instead of the "
                 "chipset directly. (4)\n\n"
                 "Serial debug output: the driver writes trace messages to the serial "
                 "port at 9600 baud (full variant only). (8)\n\n"
                 "Enforce multi-sector mode: transfer 256 sectors per command even if "
                 "the card reports less. (16)\n\n"
                 "Skip multi-sector auto-detection: use the value the card reports. "
                 "(32)\n\n"
                 "The ticked values are added up into FLAGS."))
      (choices "cfd first: PCMCIA conflict workaround"
               "Compatibility: use card.resource"
               "Serial debug output (full variant)"
               "Enforce multi-sector mode (256 sectors)"
               "Skip multi-sector auto-detection")
      (default 0)))
  (set setup-flags 0))
(set setup-flagsum
  (+ (if (in setup-flags 0) 1 0)
     (if (in setup-flags 1) 4 0)
     (if (in setup-flags 2) 8 0)
     (if (in setup-flags 3) 16 0)
     (if (in setup-flags 4) 32 0)))
(if (<> setup-flagsum 0)
  (set setup-text (cat setup-text ("FLAGS %ld\n" setup-flagsum))))
(set setup-env
  (askbool
    (prompt "Also write ENV:cfd.prefs, so the settings apply now?")
    (help (cat "ENVARC:cfd.prefs, the saved settings, is always written and replaces the " "old file.\n\nYes (default): ENV:cfd.prefs is written too, so the next card " "you insert or pull uses the new settings.\n\nNo: they apply after the next " "reboot."))
    (default 1)))
(textfile (dest "ENVARC:cfd.prefs") (append setup-text))
(if setup-env (textfile (dest "ENV:cfd.prefs") (append setup-text)))
