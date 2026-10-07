; compactflash.device, automount, tools, mountlist, prefs, startup
(set copy-src (cat ptable-flavor "/" ptable-cpu "/devs/compactflash.device"))
(set copy-dest "DEVS:")
(P_COPY)
(set copy-src (cat ptable-flavor "/" ptable-cpu "/libs/compactflash.automount"))
(set copy-dest "LIBS:")
(P_COPY)
(set cfd-tools
  (askoptions
    (prompt "Tools to copy to C:")
    (help (cat "CFInfo: shows the card and driver information.\n\n"
               "lsptres: lists the partitions in partition.resource.\n\n"
               "pcmciacheck: tests whether a card works with the driver.\n\n"
               "pcmciaspeed: measures PCMCIA access timing.\n\n"
               "CFInfo and lsptres are ticked by default."))
    (choices "CFInfo: card and driver information"
             "lsptres: partitions in partition.resource"
             "pcmciacheck: card compatibility test"
             "pcmciaspeed: PCMCIA timing benchmark")
    (default 3)))
(if (in cfd-tools 0) (copyfiles (source "c/CFInfo") (dest "C:")))
(if (in cfd-tools 1) (copyfiles (source "c/lsptres") (dest "C:")))
(if (in cfd-tools 2) (copyfiles (source "c/pcmciacheck") (dest "C:")))
(if (in cfd-tools 3) (copyfiles (source "c/pcmciaspeed") (dest "C:")))
(set fa-file "S:User-Startup")
(set fa-pattern "LoadModule#?compactflash.device")
(P_FIRST_ACTIVE)
(set cfd-us-active fa-active)
(set cfd-opts
  (askoptions
    (prompt "Optional parts")
    (help (cat "Mountlist: CF0 to DEVS:DOSDrivers, needed only without automount.\n\n"
               "Disk icon: def_CF0.info to ENVARC:Sys and ENV:Sys, OS 3.5 or newer.\n\n"
               "Example cfd.prefs: replaces ENVARC:cfd.prefs and ENV:cfd.prefs. Unchecked "
               "keeps the existing prefs or the built-in defaults.\n\n"
               "All off by default."))
    (choices "Mountlist CF0 to DEVS:DOSDrivers"
             "CF0 disk icon to ENVARC:Sys"
             "Example cfd.prefs to ENVARC: and ENV:")
    (default 0)))
(if (in cfd-opts 0)
  (copyfiles (source "Storage/DOSDrivers/CF0") (dest "DEVS:DOSDrivers") (infos)))
(if (in cfd-opts 1)
  (
    (if (not (exists "ENVARC:Sys")) (makedir "ENVARC:Sys"))
    (if (not (exists "ENV:Sys")) (makedir "ENV:Sys"))
    (copyfiles (source "def_CF0.info") (dest "ENVARC:Sys"))
    (copyfiles (source "def_CF0.info") (dest "ENV:Sys"))))
(if (in cfd-opts 2)
  (
    (copyfiles (source "ENVARC/cfd.prefs") (dest "ENVARC:"))
    (copyfiles (source "ENVARC/cfd.prefs") (dest "ENV:"))))
(if (= @user-level 2)
  (
    (set cfd-expert
      (askoptions
        (prompt "Expert options")
        (help (cat "LoadModule: the driver, compactflash.automount and ptable.library are "
                   "loaded at boot from one LoadModule line at the top of S:User-Startup, "
                   "for automount without ROM. Leave it off when the driver is in ROM.\n\n"
                   "cfd and fat95 share that line, because a second LoadModule replaces "
                   "the modules of the first. The modules of the other package are kept. "
                   "Unticked: the cfd modules are removed from it. Not added when "
                   "S:User-Startup already has another LoadModule line.\n\n"
                   "Ticked by default when S:User-Startup already has an active line."))
        (choices "LoadModule line in S:User-Startup")
        (default (if cfd-us-active 1 0))))
    (set lm-self "cfd")
    (set lm-on (in cfd-expert 0))
    (P_LOADMODULE)))
