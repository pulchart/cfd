# Makefile for compactflash.device
# Builds in the amiga-toolchain image with vasm (assembler) and vbcc (C compiler)
#
# Usage: make [options] [target]
#   help - show detailed usage output

# Release version: YYYYMMDD package date + optional in-progress suffix
# (-dev). Empty suffix for a final release.
RELEASE_DATE = 20261115
VERSION_SUFFIX =

# compactflash.device version
CFD_MAJOR = 2
CFD_MINOR = 2
CFD_VERSION_SUFFIX =
CFD_DATE = 15.11.2026

# compactflash.automount version (optional boot/automount module)
AUTOMOUNT_MAJOR = 2
AUTOMOUNT_MINOR = 0
AUTOMOUNT_VERSION_SUFFIX =
AUTOMOUNT_DATE = 27.08.2026

# Tool-specific versions
CFINFO_MAJOR = 1
CFINFO_MINOR = 40
CFINFO_VERSION_SUFFIX =
CFINFO_DATE = 03.10.2026

PCMCIASPEED_MAJOR = 1
PCMCIASPEED_MINOR = 37
PCMCIASPEED_VERSION_SUFFIX =
PCMCIASPEED_DATE = 03.10.2026

PCMCIACHECK_MAJOR = 2
PCMCIACHECK_MINOR = 2
PCMCIACHECK_VERSION_SUFFIX =
PCMCIACHECK_DATE = 03.10.2026

# Derived versions
VERSION = $(RELEASE_DATE)$(VERSION_SUFFIX)

# Human-readable date derived from RELEASE_DATE (YYYYMMDD -> DD.MM.YYYY)
DATE = $(shell echo "$(RELEASE_DATE)" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\3.\2.\1/')
CFD_VERSION = $(CFD_MAJOR).$(CFD_MINOR)$(CFD_VERSION_SUFFIX)
VERSION_INC = src/cfd_version.i
AUTOMOUNT_VERSION = $(AUTOMOUNT_MAJOR).$(AUTOMOUNT_MINOR)$(AUTOMOUNT_VERSION_SUFFIX)
AUTOMOUNT_VERSION_INC = src/cfd_automount_version.i

# ptable.library version/date read from the submodule build stamp
PLIB_VERSION = $(firstword $(shell cat $(PTABLE_VERSION_FILE) 2>/dev/null))
PLIB_DATE    = $(word 2,$(shell cat $(PTABLE_VERSION_FILE) 2>/dev/null))

# lsptres version/date read from the ptable build stamp.
LSPTRES_VERSION = $(firstword $(shell cat $(PTABLE_LSPTRES_VERSION_FILE) 2>/dev/null))
LSPTRES_DATE    = $(word 2,$(shell cat $(PTABLE_LSPTRES_VERSION_FILE) 2>/dev/null))

# Tool versions (derived)
CFINFO_VERSION      = $(CFINFO_MAJOR).$(CFINFO_MINOR)$(CFINFO_VERSION_SUFFIX)
PCMCIASPEED_VERSION = $(PCMCIASPEED_MAJOR).$(PCMCIASPEED_MINOR)$(PCMCIASPEED_VERSION_SUFFIX)
PCMCIACHECK_VERSION = $(PCMCIACHECK_MAJOR).$(PCMCIACHECK_MINOR)$(PCMCIACHECK_VERSION_SUFFIX)

# Component table driving TOOLS_ALL and the README/dist auto-gen blocks.
COMPONENTS = CFD AUTOMOUNT PLIB CFINFO PCMCIASPEED PCMCIACHECK LSPTRES

CFD_NAME          = compactflash.device
CFD_KIND          = device
AUTOMOUNT_NAME      = compactflash.automount
AUTOMOUNT_KIND      = module
PLIB_NAME         = ptable.library
PLIB_KIND         = library
CFINFO_NAME       = CFInfo
CFINFO_KIND       = tool
PCMCIASPEED_NAME  = pcmciaspeed
PCMCIASPEED_KIND  = tool
PCMCIACHECK_NAME  = pcmciacheck
PCMCIACHECK_KIND  = tool
LSPTRES_NAME      = lsptres
LSPTRES_KIND      = tool

# "PREFIX|name|version|date" per component, fed to tools/components.sh
# (the README.md block and the cfd.readme list both render from this).
COMPONENT_ARGS = $(foreach c,$(COMPONENTS),'$(c)|$($(c)_NAME)|$($(c)_VERSION)|$($(c)_DATE)')

# Flavor x CPU fan-out for assembled artifacts (device, library).
FLAVORS = full/68020 small/68020 full/68000 small/68000
# compactflash.automount (KIND=module) ships in libs/ like the library.
_subdir_device  = devs
_subdir_library = libs
_subdir_module  = libs

# Per-component "name:target:version:date" entries; device/library fan out over $(FLAVORS).
define _artifact_entries
$(if $(filter tool,$($(1)_KIND)),\
$($(1)_NAME):$(OUTDIR_C)/$($(1)_NAME):$($(1)_VERSION):$($(1)_DATE),\
$(foreach f,$(FLAVORS),$(f)/$(_subdir_$($(1)_KIND))/$($(1)_NAME):$(OUTDIR)/$(f)/$(_subdir_$($(1)_KIND))/$($(1)_NAME):$($(1)_VERSION):$($(1)_DATE)))
endef

# Verbose mode (V=1 for verbose output)
ifeq ($(V),1)
  Q =
  DEFINITIONS =
else
  Q = @
  DEFINITIONS = -quiet
endif

# GTIMING: Gayle timing optimization
# Maps CF card PIO modes to optimal Gayle PCMCIA timing
# Default" disabled (experimental, set GTIMING=1 to enable)
TEXT=""
GTIMING ?= 0
ifeq ($(GTIMING),1)
  TEXT=", +gayletiming"
  DEFINITIONS += -DGTIMING=$(GTIMING)
else
  TEXT=", -gayletiming"
endif

# CIS gate: enforce CISTPL_FUNCEXT declares IDE
# FUNCEXT_VOTING=0 relaxes the gate (FUNCEXT values are still parsed and logged),
# but the card is always accepted at this stage. Useful on hardware whose
# attribute-memory reads are unstable (e.g. A1200 + ACA1234) where a corrupted
# FUNCEXT would otherwise reject an otherwise-good CF card.
FUNCEXT_VOTING ?= 1
ifeq ($(FUNCEXT_VOTING),1)
  TEXT := $(TEXT), +funcextvoting
  DEFINITIONS += -DFUNCEXT_VOTING=$(FUNCEXT_VOTING)
else
  TEXT := $(TEXT), -funcextvoting
endif

# ATAPI: compile in the ATAPI handler
# Default (0): handler compiled out
ATAPI ?= 0
ifeq ($(ATAPI),1)
  TEXT := $(TEXT), +atapi
  DEFINITIONS += -DATAPI=$(ATAPI)
else
  TEXT := $(TEXT), -atapi
endif

LHA = lha

# Flags
# VASMFLAGS is the base set shared by all tiers; per-tier CPU flag
# (-m68020 / -m68000) is appended in the individual build rules.
# ptable.library submodule (override PTABLE= to point elsewhere, e.g. a local
# checkout).
PTABLE ?= extern/ptable
PTABLE_SRC = $(PTABLE)/src
PTABLE_VERSION_FILE = $(PTABLE)/dist/ptable.version
PTABLE_LSPTRES_VERSION_FILE = $(PTABLE)/dist/lsptres.version

# Every target runs in the amiga-toolchain image: the tools are on its PATH,
# VBCC and NDK in its environment
TOOLCHAIN_IMAGE ?= ghcr.io/pulchart/amiga-toolchain:latest
#TOOLCHAIN_IMAGE ?= docker.io/pulchart/amiga-toolchain:latest

# Outside the image make runs the goals in TOOLCHAIN_IMAGE, pulled when the registry
# has a newer one; the checkout, PTABLE and their git dirs are mounted at their paths
ifeq ($(wildcard /usr/share/amiga-toolchain/toolchain.json),)
GOALS  := $(or $(MAKECMDGOALS),all)
gitdir  = $(shell d=$$(git -C $(1) rev-parse --git-common-dir 2>/dev/null) && cd $(1) && cd "$$d" && pwd)
MOUNTS := $(sort $(filter-out $(CURDIR) $(CURDIR)/%,$(call gitdir,.) $(abspath $(PTABLE)) $(call gitdir,$(PTABLE))))
.PHONY: $(GOALS)
$(firstword $(GOALS)):
	@podman run --rm --pull=newer --security-opt label=disable -v $(CURDIR):$(CURDIR) -w $(CURDIR) \
		$(foreach d,$(MOUNTS),-v $(d):$(d)) $(TOOLCHAIN_IMAGE) make $(MAKEOVERRIDES) $(GOALS)
$(wordlist 2,$(words $(GOALS)),$(GOALS)):
	@:
else

# -I $(PTABLE_SRC) lets the driver resolve the submodule's ptable_pub.i.
VASMFLAGS = -Fhunkexe -nosym $(DEFINITIONS) -I $(PTABLE_SRC)
VBCCFLAGS = +aos68k -O2 -c99 -I$(NDK)/Include_H

# CPU tier flags
# -D__68020__=1 enables the 020+ inline math paths (mulu.l / divul.l / bfffo)
# inside src/cfd.s. Must not be set for the 68000 tier.
VASMCPU_020 = -m68020 -D__68020__=1
VASMCPU_000 = -m68000
# Aliases used by the static-pattern recipes via $(VASMCPU_$(cpu))
# where cpu is the directory name "68020" / "68000".
VASMCPU_68020 = $(VASMCPU_020)
VASMCPU_68000 = $(VASMCPU_000)

# Directories
SRCDIR = src
LIBSRC = src/lib
OUTDIR = dist
OUTDIR_C = $(OUTDIR)/c

# Files: Driver
SOURCE = $(SRCDIR)/cfd.s
# Extra sources pulled in via "include" from cfd.s.  Listed here so
# a change to them triggers a rebuild of the driver targets below.
SOURCE_DEPS = $(PTABLE_SRC)/ptable_pub.i \
              $(LIBSRC)/umul32.i \
              $(LIBSRC)/log2.i \
              $(LIBSRC)/udivmod32.i \
              $(LIBSRC)/raw_debug.i

# ptable.library is built by the $(PTABLE) submodule, not assembled here.

# Per-flavor / per-cpu output drawers.
#
# dist/<flavor>/<cpu>/{devs,libs}/<file> mirrors the AmigaOS install
# tree: dragging the contents of dist/<flavor>/<cpu>/ into SYS:
# installs both the device (devs/) and the library (libs/) at once,
# with their final filenames - no .small suffix to drop.
DEVICE_TARGETS = \
  $(OUTDIR)/full/68020/devs/compactflash.device  \
  $(OUTDIR)/full/68000/devs/compactflash.device  \
  $(OUTDIR)/small/68020/devs/compactflash.device \
  $(OUTDIR)/small/68000/devs/compactflash.device

LIBRARY_TARGETS = \
  $(OUTDIR)/full/68020/libs/ptable.library  \
  $(OUTDIR)/full/68000/libs/ptable.library  \
  $(OUTDIR)/small/68020/libs/ptable.library \
  $(OUTDIR)/small/68000/libs/ptable.library

DRIVER_TARGETS = $(DEVICE_TARGETS)

# Convenience aliases (used by the readme template substitutions and
# the per-tier convenience phonies further down).
TARGET_FULL      = $(OUTDIR)/full/68020/devs/compactflash.device
TARGET_SMALL     = $(OUTDIR)/small/68020/devs/compactflash.device
TARGET_FULL_000  = $(OUTDIR)/full/68000/devs/compactflash.device
TARGET_SMALL_000 = $(OUTDIR)/small/68000/devs/compactflash.device
LIB_FULL         = $(OUTDIR)/full/68020/libs/ptable.library
LIB_SMALL        = $(OUTDIR)/small/68020/libs/ptable.library
LIB_FULL_000     = $(OUTDIR)/full/68000/libs/ptable.library
LIB_SMALL_000    = $(OUTDIR)/small/68000/libs/ptable.library

TOOLS_ALL = $(foreach c,$(COMPONENTS),$(call _artifact_entries,$(c)))

# Lookup tables consumed by the static-pattern recipes below.
# DEBUG_<flavor> resolves to the per-flavor extra vasm flags;
# VASMCPU_<cpu> already exists above (-m68020 -D__68020__=1 vs -m68000).
DEBUG_full  = -DDEBUG=1
DEBUG_small =

# Files: Tools
SOURCE_PAGE = $(PTABLE_SRC)/page.c
SOURCE_CFINFO = $(SRCDIR)/cfinfo.c
TARGET_CFINFO = $(OUTDIR_C)/CFInfo
SOURCE_PCMCIASPEED = $(SRCDIR)/pcmciaspeed.c
TARGET_PCMCIASPEED = $(OUTDIR_C)/pcmciaspeed
SOURCE_PCMCIACHECK = $(SRCDIR)/pcmciacheck.c
TARGET_PCMCIACHECK = $(OUTDIR_C)/pcmciacheck
# lsptres binary + guide are built by the $(PTABLE) submodule and copied
# from its dist/, so every release ships the ptable-built bytes.
TARGET_LSPTRES = $(OUTDIR_C)/lsptres
# Guest tools of the integration suite, not shipped.
IT_TOOLS = devinfo holdfile
IT_TARGETS = $(addprefix build/tools/,$(IT_TOOLS))

# compactflash.automount: optional boot/automount bringup module (cold-boot
# autoboot + after-DOS device open), split out of compactflash.device.  Shipped
# in libs/ per tier (full = boot serial, small = none); 68000-safe so the same
# binary runs on every CPU.  Load only when autoboot/automount is wanted.
SOURCE_AUTOMOUNT = $(SRCDIR)/cfd_automount.s
AUTOMOUNT_TARGETS = \
  $(OUTDIR)/full/68020/libs/compactflash.automount  \
  $(OUTDIR)/full/68000/libs/compactflash.automount  \
  $(OUTDIR)/small/68020/libs/compactflash.automount \
  $(OUTDIR)/small/68000/libs/compactflash.automount

# Files: Release
RELEASE_NAME = cfd.v$(VERSION)
ARCHIVE_NAME = $(RELEASE_NAME).lha
README_NAME = $(RELEASE_NAME).readme
README_TEMPLATE = dist.readme.in

# ============================================================
# Build targets
# ============================================================

# Default target - build all driver tiers, library, and tools
all: version-readme $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(AUTOMOUNT_TARGETS) $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK) $(TARGET_LSPTRES)

# Generate version include file (always check, only update if changed)
# Uses a stamp file to track the current version string
VERSION_STAMP = .version-stamp
.PHONY: FORCE check-lha
FORCE:

$(VERSION_STAMP): FORCE
	$(Q)echo "$(CFD_VERSION) $(CFD_DATE)" > $(VERSION_STAMP).tmp
	$(Q)if ! cmp -s $(VERSION_STAMP).tmp $(VERSION_STAMP) 2>/dev/null; then \
		mv $(VERSION_STAMP).tmp $(VERSION_STAMP); \
	else \
		rm -f $(VERSION_STAMP).tmp; \
	fi

$(VERSION_INC): $(VERSION_STAMP)
	$(Q)echo "  VERSION compactflash.device $(CFD_VERSION)"
	$(Q)echo "; Auto-generated by Makefile" > $@
	$(Q)echo "FILE_VERSION	= $(CFD_MAJOR)" >> $@
	$(Q)echo "FILE_REVISION	= $(CFD_MINOR)" >> $@
	$(Q)echo "VERSION_STRING	macro" >> $@
	$(Q)echo "	ifd	__68020__" >> $@
	$(Q)echo "	dc.b	\"compactflash.device $(CFD_VERSION) ($(CFD_DATE)) [68020]\"" >> $@
	$(Q)echo "	else" >> $@
	$(Q)echo "	dc.b	\"compactflash.device $(CFD_VERSION) ($(CFD_DATE)) [68000]\"" >> $@
	$(Q)echo "	endc" >> $@
	$(Q)echo "	endm" >> $@

# compactflash.automount version include (own component version, stamp-tracked)
# Regenerated only when the Makefile (which holds the version/date) changes.
$(AUTOMOUNT_VERSION_INC): Makefile
	$(Q)echo "  VERSION compactflash.automount $(AUTOMOUNT_VERSION)"
	$(Q)echo "; Auto-generated by Makefile" > $@
	$(Q)echo "FILE_VERSION	= $(AUTOMOUNT_MAJOR)" >> $@
	$(Q)echo "FILE_REVISION	= $(AUTOMOUNT_MINOR)" >> $@
	$(Q)echo "VERSION_STRING	macro" >> $@
	$(Q)echo "	dc.b	\"compactflash.automount $(AUTOMOUNT_VERSION) ($(AUTOMOUNT_DATE))\"" >> $@
	$(Q)echo "	endm" >> $@

# Build ptable.library in the submodule (all four tiers, lsptres, the guides
# and the dist/*.version stamps that PLIB_*/LSPTRES_* read); its own make
# decides what to rebuild. Everything ptable-owned is copied from that build.
PTABLE_OUTPUTS = $(foreach f,$(FLAVORS),$(PTABLE)/dist/$(f)/ptable.library) \
                 $(PTABLE)/dist/c/lsptres $(PTABLE)/dist/docs/lsptres.guide \
                 $(PTABLE_VERSION_FILE) $(PTABLE_LSPTRES_VERSION_FILE)
.PHONY: ptable-build
ptable-build:
	$(Q)test -f $(PTABLE_SRC)/ptable_lib.s || { \
		echo "ERROR: ptable submodule missing at $(PTABLE)."; \
		echo "  git submodule update --init, or build with PTABLE=<path>"; \
		exit 1; }
	$(Q)$(MAKE) -C $(PTABLE) all guides
$(PTABLE_OUTPUTS): | ptable-build
	@:

# Move the ptable submodule to its upstream tip and rebuild everything that
# bundles it (guides included: "all" does not cover dist/docs/lsptres.guide).
# Uses the branch tip rather than "git submodule update": if the recorded
# commit was orphaned by an upstream history rewrite, restoring the pin would
# fail. Leaves the result uncommitted for review. Phony; a $(PTABLE) that is
# not a git checkout is a soft skip.
.PHONY: ptable-sync
ptable-sync:
	$(Q)if [ -e "$(PTABLE)/.git" ]; then \
		git -C "$(PTABLE)" fetch origin; \
		git -C "$(PTABLE)" checkout --detach origin/master; \
		$(MAKE) all guides; \
		echo "  ptable synced to $$(git -C "$(PTABLE)" rev-parse --short HEAD) ($$(cat $(PTABLE_VERSION_FILE)))"; \
		echo "  review, then commit $(PTABLE) with the rebuilt dist/ artifacts"; \
	else \
		echo "  NOTE: $(PTABLE) is not a git checkout - nothing to sync"; \
	fi

# Rewrite the topmost release-notes header and the COMPONENTS block in
# docs/changes.md from current Makefile vars. Add new release headers by hand.
# Depends on the submodule version stamp: PLIB_*/LSPTRES_* expand lazily
# from $(PTABLE)/dist/*.version, so stamping before that build exists
# writes empty "component  ()" rows into changes.md.
version-readme: $(PTABLE_VERSION_FILE) $(PTABLE_LSPTRES_VERSION_FILE)
	$(Q)sed -i '0,/^## [0-9]\{8\}[^[:space:]]*/s/^## [0-9]\{8\}[^[:space:]]*/## $(VERSION)/' docs/changes.md
	$(Q)block="_Components in this release_:\n\n$$(sh tools/components.sh md $(COMPONENT_ARGS))"; \
	awk -v block="$$block" ' \
	    /<!-- COMPONENTS:BEGIN -->/{print; print block; in_block=1; next} \
	    /<!-- COMPONENTS:END -->/{in_block=0} \
	    !in_block' docs/changes.md > docs/changes.md.tmp && mv docs/changes.md.tmp docs/changes.md
	$(Q)echo "  CHANGES topmost header + components updated to $(VERSION) ($(DATE))"

# Driver: dist/<flavor>/<cpu>/devs/compactflash.device
#
# Static-pattern rule -- $* matches "<flavor>/<cpu>" (e.g. "full/68020"),
# from which we derive vasm flags via the DEBUG_<flavor> / VASMCPU_<cpu>
# lookup tables defined above.
$(DEVICE_TARGETS): $(OUTDIR)/%/devs/compactflash.device: $(SOURCE) $(SOURCE_DEPS) $(VERSION_INC)
	$(eval flav := $(word 1,$(subst /, ,$*)))
	$(eval cpu  := $(word 2,$(subst /, ,$*)))
	$(Q)mkdir -p $(@D)
	$(Q)echo "  VASM    $@ [$(flav), $(cpu)$(TEXT)]"
	$(Q)vasmm68k_mot $(VASMFLAGS) $(VASMCPU_$(cpu)) $(DEBUG_$(flav)) -o $@ $<
	$(Q)echo "          $$(stat -c%s $@) bytes, md5:$$(md5sum $@ | cut -c1-8)"

# ptable.library: copied from the submodule build (dist/<flavor>/<cpu>/ptable.library)
# into our install tree at dist/<flavor>/<cpu>/libs/ptable.library.
$(LIBRARY_TARGETS): $(OUTDIR)/%/libs/ptable.library: $(PTABLE)/dist/%/ptable.library
	$(Q)mkdir -p $(@D)
	$(Q)cp $(PTABLE)/dist/$*/ptable.library $@
	$(Q)echo "  PTABLE  $@ [$*] (md5:$$(md5sum $@ | cut -c1-8))"

# Per-tier convenience phonies (subsets of DEVICE_TARGETS / LIBRARY_TARGETS)
full:      $(TARGET_FULL)
small:     $(TARGET_SMALL)
full-000:  $(TARGET_FULL_000)
small-000: $(TARGET_SMALL_000)

library:           $(LIBRARY_TARGETS)
library-full:      $(LIB_FULL)
library-small:     $(LIB_SMALL)
library-full-000:  $(LIB_FULL_000)
library-small-000: $(LIB_SMALL_000)

# Tools only target
tools: $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK) $(TARGET_LSPTRES)

# Generate AmigaGuide documentation from Markdown
GUIDE_OUTPUT_DIR = dist/docs
GUIDE_CFD        = $(GUIDE_OUTPUT_DIR)/cfd.guide
GUIDE_AUTOMOUNT  = $(GUIDE_OUTPUT_DIR)/automount.guide
GUIDE_AMREVIEW   = $(GUIDE_OUTPUT_DIR)/automount-review.guide
GUIDE_CHANGES    = $(GUIDE_OUTPUT_DIR)/changes.guide
GUIDE_CFINFO     = $(GUIDE_OUTPUT_DIR)/CFInfo.guide
GUIDE_SPEED      = $(GUIDE_OUTPUT_DIR)/pcmciaspeed.guide
GUIDE_CHECK      = $(GUIDE_OUTPUT_DIR)/pcmciacheck.guide
GUIDE_LSPTRES    = $(GUIDE_OUTPUT_DIR)/lsptres.guide

guide guides: $(GUIDE_CFD) $(GUIDE_AUTOMOUNT) $(GUIDE_AMREVIEW) $(GUIDE_CHANGES) $(GUIDE_CFINFO) $(GUIDE_SPEED) $(GUIDE_CHECK) $(GUIDE_LSPTRES)

$(GUIDE_CFD): README.md
	$(Q)mkdir -p $(GUIDE_OUTPUT_DIR)
	$(Q)echo "  GUIDE   $@"
	$(Q)md2guide README.md $@ --version $(CFD_VERSION) --date $(CFD_DATE) --title "compactflash.device" --ver-title "compactflash.device guide"

$(GUIDE_AUTOMOUNT): docs/automount.md
	$(Q)mkdir -p $(GUIDE_OUTPUT_DIR)
	$(Q)echo "  GUIDE   $@"
	$(Q)md2guide docs/automount.md $@ --version $(CFD_VERSION) --date $(CFD_DATE) --title "compactflash.device" --ver-title "automount guide"

$(GUIDE_AMREVIEW): docs/automount-review.md
	$(Q)mkdir -p $(GUIDE_OUTPUT_DIR)
	$(Q)echo "  GUIDE   $@"
	$(Q)md2guide docs/automount-review.md $@ --version $(CFD_VERSION) --date $(CFD_DATE) --title "compactflash.device" --ver-title "automount feature review guide"

$(GUIDE_CHANGES): docs/changes.md Makefile
	$(Q)mkdir -p $(GUIDE_OUTPUT_DIR)
	$(Q)echo "  GUIDE   $@"
	$(Q)md2guide docs/changes.md $@ --version $(VERSION) --date $(DATE) --title "compactflash.device release notes" --ver-title "compactflash.device release notes guide"

$(GUIDE_CFINFO): docs/CFInfo.md
	$(Q)mkdir -p $(GUIDE_OUTPUT_DIR)
	$(Q)echo "  GUIDE   $@"
	$(Q)md2guide docs/CFInfo.md $@ --version $(CFINFO_VERSION) --date $(CFINFO_DATE) --ver-title "CFInfo guide"

$(GUIDE_SPEED): docs/pcmciaspeed.md
	$(Q)mkdir -p $(GUIDE_OUTPUT_DIR)
	$(Q)echo "  GUIDE   $@"
	$(Q)md2guide docs/pcmciaspeed.md $@ --version $(PCMCIASPEED_VERSION) --date $(PCMCIASPEED_DATE) --ver-title "pcmciaspeed guide"

$(GUIDE_CHECK): docs/pcmciacheck.md
	$(Q)mkdir -p $(GUIDE_OUTPUT_DIR)
	$(Q)echo "  GUIDE   $@"
	$(Q)md2guide docs/pcmciacheck.md $@ --version $(PCMCIACHECK_VERSION) --date $(PCMCIACHECK_DATE) --ver-title "pcmciacheck guide"

# lsptres.guide: copied from the submodule build, not generated here.
$(GUIDE_LSPTRES): $(PTABLE)/dist/docs/lsptres.guide
	$(Q)mkdir -p $(GUIDE_OUTPUT_DIR)
	$(Q)cp $(PTABLE)/dist/docs/lsptres.guide $@
	$(Q)echo "  PTABLE  $@"

$(TARGET_CFINFO): $(SOURCE_CFINFO) $(SOURCE_PAGE) $(PTABLE_SRC)/page.h Makefile
	$(Q)mkdir -p $(OUTDIR_C)
	$(Q)echo "  VBCC    $(TARGET_CFINFO)"
	$(Q)vc +aos68k -O2 -c99 -I$(NDK)/Include_H -I$(PTABLE_SRC) -DVERSION='"$(CFINFO_VERSION)"' -DDATE='"$(CFINFO_DATE)"' -o $(TARGET_CFINFO) $(SOURCE_CFINFO) $(SOURCE_PAGE)
	$(Q)echo "          $$(stat -c%s $(TARGET_CFINFO)) bytes, md5:$$(md5sum $(TARGET_CFINFO) | cut -c1-8)"

$(TARGET_PCMCIASPEED): $(SOURCE_PCMCIASPEED) Makefile
	$(Q)mkdir -p $(OUTDIR_C)
	$(Q)echo "  VBCC    $(TARGET_PCMCIASPEED)"
	$(Q)vc +aos68k -O2 -c99 -I$(NDK)/Include_H -DVERSION='"$(PCMCIASPEED_VERSION)"' -DDATE='"$(PCMCIASPEED_DATE)"' -o $(TARGET_PCMCIASPEED) $<
	$(Q)echo "          $$(stat -c%s $(TARGET_PCMCIASPEED)) bytes, md5:$$(md5sum $(TARGET_PCMCIASPEED) | cut -c1-8)"

$(TARGET_PCMCIACHECK): $(SOURCE_PCMCIACHECK) $(SOURCE_PAGE) $(PTABLE_SRC)/page.h Makefile
	$(Q)mkdir -p $(OUTDIR_C)
	$(Q)echo "  VBCC    $(TARGET_PCMCIACHECK)"
	$(Q)vc +aos68k -O2 -c99 -I$(NDK)/Include_H -I$(PTABLE_SRC) -DVERSION='"$(PCMCIACHECK_VERSION)"' -DDATE='"$(PCMCIACHECK_DATE)"' -o $(TARGET_PCMCIACHECK) $(SOURCE_PCMCIACHECK) $(SOURCE_PAGE)
	$(Q)echo "          $$(stat -c%s $(TARGET_PCMCIACHECK)) bytes, md5:$$(md5sum $(TARGET_PCMCIACHECK) | cut -c1-8)"

# lsptres: copied from the submodule build (dist/c/lsptres), not compiled here.

build/tools/%: tools/%.c Makefile
	$(Q)mkdir -p $(dir $@)
	$(Q)echo "  VBCC    $@"
	$(Q)vc $(VBCCFLAGS) -o $@ $< -lamiga

$(IT_TOOLS): %: build/tools/%

$(TARGET_LSPTRES): $(PTABLE)/dist/c/lsptres
	$(Q)mkdir -p $(OUTDIR_C)
	$(Q)cp $(PTABLE)/dist/c/lsptres $@
	$(Q)echo "  PTABLE  $@ (md5:$$(md5sum $@ | cut -c1-8))"

$(AUTOMOUNT_TARGETS): $(OUTDIR)/%/libs/compactflash.automount: $(SOURCE_AUTOMOUNT) $(SRCDIR)/cfd_pub.i $(AUTOMOUNT_VERSION_INC) $(PTABLE_SRC)/ptable_pub.i
	$(eval flav := $(word 1,$(subst /, ,$*)))
	$(Q)mkdir -p $(@D)
	$(Q)echo "  VASM    $@ [$(flav), automount]"
	$(Q)vasmm68k_mot $(VASMFLAGS) $(VASMCPU_68000) $(DEBUG_$(flav)) -o $@ $<
	$(Q)echo "          $$(stat -c%s $@) bytes, md5:$$(md5sum $@ | cut -c1-8)"

# ============================================================
# Release targets
# ============================================================

# Component summary with literal `\n` for GNU sed substitution; plain
# text (no markdown), changed-since-previous-tag components flagged "(new)".
COMPONENT_VERSIONS_NL = $(shell sh tools/components.sh plain $(COMPONENT_ARGS))

# Generate readme from template
$(README_NAME): $(README_TEMPLATE) $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(AUTOMOUNT_TARGETS) $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK) $(TARGET_LSPTRES)
	@echo "Generating $(README_NAME) from template..."
	@tool_checksums=""; \
	for tool_info in $(TOOLS_ALL); do \
		tool_name=$$(echo "$$tool_info" | cut -d: -f1); \
		tool_target=$$(echo "$$tool_info" | cut -d: -f2); \
		tool_version=$$(echo "$$tool_info" | cut -d: -f3); \
		tool_date=$$(echo "$$tool_info" | cut -d: -f4); \
		if [ -f "$$tool_target" ]; then \
			tool_size=$$(stat -c%s "$$tool_target" 2>/dev/null || echo 0); \
			tool_md5=$$(md5sum "$$tool_target" 2>/dev/null | cut -d' ' -f1 || echo "N/A"); \
			tool_sha256=$$(sha256sum "$$tool_target" 2>/dev/null | cut -d' ' -f1 || echo "N/A"); \
			tool_checksums="$$tool_checksums$$tool_name $$tool_version ($$tool_date) ($$tool_size bytes):\n  MD5:    $$tool_md5\n  SHA256: $$tool_sha256\n\n"; \
		fi; \
	done; \
	sed -e "s|@VERSION@|$(VERSION)|g" \
	    -e "s|@DATE@|$(DATE)|g" \
	    -e "s|@COMPONENT_VERSIONS@|$(COMPONENT_VERSIONS_NL)|" \
	    -e "s|@TOOL_CHECKSUMS@|$$tool_checksums|" \
	    $(README_TEMPLATE) > $@
	@echo "Generated: $@"

# Generate readme only
readme: $(README_NAME)

# Create Aminet-compatible LHA release
# Archive tree: binaries, Installer script and the laid-out icons/ tree.
STAGE   = build/stage
INSTALL = install

stage: version-readme $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(AUTOMOUNT_TARGETS) $(README_NAME) guides
	$(Q)rm -rf $(STAGE)
	$(Q)mkdir -p $(STAGE)/cfd/src/lib
	$(Q)cp -r dist/full dist/small dist/c dist/Storage dist/ENVARC dist/docs dist/images $(STAGE)/cfd/
	$(Q)cp src/*.* $(STAGE)/cfd/src/
	$(Q)cp src/lib/*.* $(STAGE)/cfd/src/lib/
	$(Q)cp $(README_NAME) $(STAGE)/cfd/cfd.readme
	$(Q)cp LICENSE $(STAGE)/cfd/
	$(Q)cp -r icons/. $(STAGE)/
	$(Q)[ -f $(PTABLE)/install/common.inc ] || { echo "ERROR: $(PTABLE) has no install/; build with PTABLE=<amigaos-ptable checkout>"; exit 1; }
	$(Q)sed -e "s|@VERSION@|$(VERSION)|" -e "s|@DATE@|$(DATE)|" $(INSTALL)/cfd.head $(PTABLE)/install/common.inc $(PTABLE)/install/ptable.inc \
	    $(INSTALL)/cfd.inc $(INSTALL)/cfd.tail > $(STAGE)/cfd/Install
	$(Q)sed -e "s|@VERSION@|$(VERSION)|" -e "s|@DATE@|$(DATE)|" $(INSTALL)/setup.head $(INSTALL)/setup.inc $(INSTALL)/setup.tail > $(STAGE)/cfd/Setup

release: check-lha stage
	@echo "Creating Aminet release: $(ARCHIVE_NAME)"
	@rm -f "$(ARCHIVE_NAME)"
	@cd "$(STAGE)" && $(LHA) c "../../$(ARCHIVE_NAME)" cfd cfd.info >/dev/null
	@echo "=================================="
	@echo "Created: $(ARCHIVE_NAME)"
	@ls -lh "$(ARCHIVE_NAME)"
	@echo ""
	@echo "Contents:"
	@$(LHA) l "$(ARCHIVE_NAME)"
	@echo ""
	@echo "For Aminet upload:"
	@echo "  1. $(ARCHIVE_NAME)"
	@echo "  2. $(README_NAME)"
	@echo ""
	@echo "Upload to: ftp://main.aminet.net/new"

# Check if lha is installed
check-lha:
	@command -v $(LHA) >/dev/null 2>&1 || { \
		echo "ERROR: lha command not found!"; \
		echo "Install with: sudo dnf install lha"; \
		exit 1; \
	}

# ============================================================
# Utility targets
# ============================================================

# Show checksums for all built artifacts
checksums: $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK) $(TARGET_LSPTRES)
	@for target in $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK) $(TARGET_LSPTRES); do \
		if [ -f "$$target" ]; then \
			echo "=== $${target} ==="; \
			ls -l "$$target"; \
			echo "MD5:    $$(md5sum "$$target" | cut -d' ' -f1)"; \
			echo "SHA256: $$(sha256sum "$$target" | cut -d' ' -f1)"; \
			echo ""; \
		fi \
	done


TEST_SUITES = ata_contracts config_loader mountcfg rom_hunks
.PHONY: test check-test-deps test-list-update lint test-integration $(IT_TOOLS)
check-test-deps:
	$(Q)CFD_PTABLE="$(PTABLE)" python3 tests/deps.py
test: check-test-deps
	$(Q)set -e; for suite in $(TEST_SUITES); do \
		echo "TEST $$suite"; CFD_PTABLE="$(PTABLE)" python3 tests/$$suite.py; \
	done
test-list-update:
	$(Q)python3 tests/list_tests.py
	$(Q)echo "Updated: tests/INVENTORY.md"

# ruff over the tracked Python files (rules in ruff.toml), yamllint over the YAML files.
lint:
	$(Q)ruff check $$(git ls-files '*.py')
	$(Q)ruff format --check $$(git ls-files '*.py')
	$(Q)yamllint -s $$(git ls-files '*.yaml' '*.yml')

# FS-UAE integration suite: the built driver set under the OS profiles of
# tests/integration/config.yaml. IT passes options to run.py.
test-integration: $(IT_TARGETS)
	$(Q)python3 tests/integration/run.py $(IT)

# Clean build artifacts
clean:
	rm -rf build
	rm -f $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(AUTOMOUNT_TARGETS) $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK) $(TARGET_LSPTRES) $(VERSION_INC) $(VERSION_STAMP) $(AUTOMOUNT_VERSION_INC)
	$(Q)[ ! -f $(PTABLE_SRC)/ptable_lib.s ] || $(MAKE) -C $(PTABLE) clean
	$(Q)for d in $(OUTDIR)/full $(OUTDIR)/small ; do \
		[ ! -d $$d ] || find $$d -depth -type d -empty -delete ; \
	done

# Clean everything including release archives
distclean: clean
	rm -f cfd*.lha cfd*.readme

# Show help
help:
	@echo "Usage: make [V=1] [target]"
	@echo ""
	@echo "Build targets:"
	@echo "  all              - Build driver + ptable.library + tools (default)"
	@echo "  full             - Build 68020+ full driver only (with serial debug capability)"
	@echo "  small            - Build 68020+ small driver only (no serial debug code)"
	@echo "  full-000         - Build 68000 full driver only (stock A600)"
	@echo "  small-000        - Build 68000 small driver only (stock A600)"
	@echo "  library          - Build all ptable.library variants"
	@echo "  library-full     - Build 68020+ full ptable.library only"
	@echo "  library-small    - Build 68020+ small ptable.library only"
	@echo "  library-full-000 - Build 68000 full ptable.library only"
	@echo "  library-small-000- Build 68000 small ptable.library only"
	@echo "  tools            - Build all tools"
	@echo "  $(IT_TOOLS) - Build build/tools/<name> for the integration suite"
	@echo "  guide / guides   - Generate AmigaGuide documentation from Markdown"
	@echo "  ptable-sync      - Move $(PTABLE) to its upstream tip and rebuild (uncommitted)"
	@echo ""
	@echo "Options:"
	@echo "  V=1                 - Verbose output (show full compiler messages)"
	@echo "  GTIMING=1           - Enable Gayle timing optimization (experimental)"
	@echo "  FUNCEXT_VOTING=0    - Relaxed CIS gate: report FUNCEXT but always accept (default: enforce IDE)"
	@echo "  ATAPI=1             - Compile in the ATAPI handler (default: out; untested, no pass CIS gating till refactored)"
	@echo "  TOOLCHAIN_IMAGE=... - amiga-toolchain image the targets run in"
	@echo ""
	@echo "Note: every device build carries a tiny RTF_COLDSTART stub"
	@echo "      that OpenLibrarys ptable.library at Kickstart cold start."
	@echo "      Make sure ptable.library ends up in ROM (Remus / Capitoline)"
	@echo "      for autoboot to fire."
	@echo ""
	@echo "Release targets:"
	@echo "  version-readme - Update current release notes in docs/changes.md"
	@echo "  readme         - Generate $(README_NAME) from template"
	@echo "  release        - Create Aminet LHA archive + readme"
	@echo ""
	@echo "Utility targets:"
	@echo "  checksums - Show file sizes and checksums"
	@echo "  clean     - Remove built device files"
	@echo "  distclean - Remove all generated files including archives"
	@echo "  help      - Show this help"
	@echo ""
	@echo "Output files:"
	@echo "  $(TARGET_FULL) - 68020+ full (A1200 stock; 68020+)"
	@echo "  $(TARGET_SMALL) - 68020+ small"
	@echo "  $(TARGET_FULL_000) - 68000 full (stock A600; 68000+)"
	@echo "  $(TARGET_SMALL_000) - 68000 small"
	@echo "  $(LIB_FULL) - 68020+ full ptable.library"
	@echo "  $(LIB_SMALL) - 68020+ small ptable.library"
	@echo "  $(LIB_FULL_000) - 68000 full ptable.library"
	@echo "  $(LIB_SMALL_000) - 68000 small ptable.library"
	@echo "  $(TARGET_CFINFO) - card info utility"
	@echo "  $(TARGET_PCMCIASPEED) - pcmcia speed/timing benchmark utility"
	@echo "  $(TARGET_PCMCIACHECK) - pcmcia check utility"
	@echo "  $(TARGET_LSPTRES) - partition.resource lister"
	@echo "  $(README_NAME) - Aminet readme"
	@echo "  $(ARCHIVE_NAME) - Aminet release archive"
	@echo ""
	@echo "Release: $(VERSION) ($(DATE)); compactflash.device: $(CFD_VERSION) ($(CFD_DATE)); ptable.library: $(PLIB_VERSION) ($(PLIB_DATE))"

.PHONY: all full small full-000 small-000 library library-full library-small library-full-000 library-small-000 tools guide guides version-readme readme release stage check-lha checksums clean distclean help

endif
