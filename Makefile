# Makefile for compactflash.device
# Build using vasm/ASMPro (assembler) and vbcc (C compiler)
#
# Usage: make [options] [target]
#   help - show detailed usage output

# Release version (controls archive name and readme; update for each release)
VERSION_MAJOR = 1
VERSION_MINOR = 42
VERSION_SUFFIX = -dev
DATE = 03.05.2026
DATE_SHORT = 05/2026

# compactflash.device version
CFD_MAJOR = 1
CFD_MINOR = 42
CFD_VERSION_SUFFIX = -dev
CFD_DATE = 03.05.2026

# ptable.library version; bumped only on library-ABI changes:
# - additive LVOs bump REVISION
# - breaking changes bump MAJOR
PLIB_MAJOR = 1
PLIB_MINOR = 0
PLIB_VERSION_SUFFIX = -dev
PLIB_DATE = 03.05.2026

# Tool-specific versions
CFINFO_VERSION = 1.37
CFINFO_DATE = 11.01.2026

PCMCIASPEED_VERSION = 1.36
PCMCIASPEED_DATE = 02.01.2026

PCMCIACHECK_VERSION = 1.38
PCMCIACHECK_DATE = 22.01.2026

# Derived versions
VERSION = $(VERSION_MAJOR).$(VERSION_MINOR)$(VERSION_SUFFIX)
VERSION_NODOT = $(VERSION_MAJOR)$(VERSION_MINOR)
CFD_VERSION = $(CFD_MAJOR).$(CFD_MINOR)$(CFD_VERSION_SUFFIX)
VERSION_INC = src/cfd_version.i

# ptable.library version include (auto-generated like cfd_version.i)
PLIB_VERSION = $(PLIB_MAJOR).$(PLIB_MINOR)$(PLIB_VERSION_SUFFIX)
PLIB_VERSION_INC = src/lib/ptable_version.i

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

# Tools (override these for different installations)
VASM_HOME = /opt/vasm
VBCC_HOME = /opt/vbcc
VASM = $(VASM_HOME)/bin/vasmm68k_mot
VBCC = $(VBCC_HOME)/bin/vc
LHA = lha
EXPECTED_VASM_VERSION = 2.0e

# Flags
# VASMFLAGS is the base set shared by all tiers; per-tier CPU flag
# (-m68020 / -m68000) is appended in the individual build rules.
VASMFLAGS = -Fhunkexe -nosym $(DEFINITIONS)
VBCCFLAGS = +aos68k -O2 -c99 -INDK/Include_H

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
SOURCE_DEPS = $(LIBSRC)/ptable_pub.i \
              $(LIBSRC)/umul32.i \
              $(LIBSRC)/log2.i \
              $(LIBSRC)/udivmod32.i \
              $(LIBSRC)/raw_debug.i

# Files: ptable.library
LIB_SOURCE = $(LIBSRC)/ptable_lib.s
# Extra sources pulled in via "include" from ptable_lib.s.  Listed here
# so a change to any of them triggers a rebuild of the library targets.
LIB_SOURCE_DEPS = $(LIBSRC)/ptable_boot.s $(LIBSRC)/ptable_fs.s \
                  $(LIBSRC)/ptable_hunk.s $(LIBSRC)/ptable_dosdiag.i \
                  $(LIBSRC)/ptable_pub.i \
                  $(LIBSRC)/umul32.i $(LIBSRC)/log2.i \
                  $(LIBSRC)/raw_debug.i

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

# List of all artifacts for checksum generation (name:target:desc triples).
# name  - label printed in the readme; desc - optional parenthetical tag.
TOOLS_ALL = \
  full/68020/devs/compactflash.device:$(TARGET_FULL):$(CFD_VERSION):$(CFD_DATE) \
  small/68020/devs/compactflash.device:$(TARGET_SMALL):$(CFD_VERSION):$(CFD_DATE) \
  full/68000/devs/compactflash.device:$(TARGET_FULL_000):$(CFD_VERSION):$(CFD_DATE) \
  small/68000/devs/compactflash.device:$(TARGET_SMALL_000):$(CFD_VERSION):$(CFD_DATE) \
  full/68020/libs/ptable.library:$(LIB_FULL):$(PLIB_VERSION):$(PLIB_DATE) \
  small/68020/libs/ptable.library:$(LIB_SMALL):$(PLIB_VERSION):$(PLIB_DATE) \
  full/68000/libs/ptable.library:$(LIB_FULL_000):$(PLIB_VERSION):$(PLIB_DATE) \
  small/68000/libs/ptable.library:$(LIB_SMALL_000):$(PLIB_VERSION):$(PLIB_DATE) \
  CFInfo:$(TARGET_CFINFO):$(CFINFO_VERSION):$(CFINFO_DATE) \
  pcmciaspeed:$(TARGET_PCMCIASPEED):$(PCMCIASPEED_VERSION):$(PCMCIASPEED_DATE) \
  pcmciacheck:$(TARGET_PCMCIACHECK):$(PCMCIACHECK_VERSION):$(PCMCIACHECK_DATE)

# Lookup tables consumed by the static-pattern recipes below.
# DEBUG_<flavor> resolves to the per-flavor extra vasm flags;
# VASMCPU_<cpu> already exists above (-m68020 -D__68020__=1 vs -m68000).
DEBUG_full  = -DDEBUG=1
DEBUG_small =

# Files: Tools
SOURCE_CFINFO = $(SRCDIR)/cfinfo.c
TARGET_CFINFO = $(OUTDIR_C)/CFInfo
SOURCE_PCMCIASPEED = $(SRCDIR)/pcmciaspeed.c
TARGET_PCMCIASPEED = $(OUTDIR_C)/pcmciaspeed
SOURCE_PCMCIACHECK = $(SRCDIR)/pcmciacheck.c
TARGET_PCMCIACHECK = $(OUTDIR_C)/pcmciacheck

# Files: Release
DATE_YYYYMMDD = $(shell echo "$(DATE)" | sed 's/\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)/\3\2\1/')
ifneq ($(VERSION_SUFFIX),)
  RELEASE_NAME = cfd.v$(VERSION)$(DATE_YYYYMMDD)
else
  RELEASE_NAME = cfd.v$(VERSION)
endif
ARCHIVE_NAME = $(RELEASE_NAME).lha
README_NAME = $(RELEASE_NAME).readme
README_TEMPLATE = dist.readme.in
README_INFO = dist/cfd.readme.info

# ============================================================
# Build targets
# ============================================================

# Default target - build all driver tiers, library, and tools
all: check-vasm version-readme $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK)

# Generate version include file (always check, only update if changed)
# Uses a stamp file to track the current version string
VERSION_STAMP = .version-stamp
.PHONY: FORCE check-vasm check-lha
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

# ptable.library version include - regenerated whenever the library
# version macros above change (the stamp file already tracks the
# device VERSION; library version is bound to it because both are
# released as one archive).
$(PLIB_VERSION_INC): $(VERSION_STAMP)
	$(Q)echo "  VERSION ptable.library $(PLIB_VERSION)"
	$(Q)echo "; Auto-generated by Makefile" > $@
	$(Q)echo "LIB_VERSION	= $(PLIB_MAJOR)" >> $@
	$(Q)echo "LIB_REVISION	= $(PLIB_MINOR)" >> $@
	$(Q)echo "LIB_VERSION_STRING	macro" >> $@
	$(Q)echo "	ifd	__68020__" >> $@
	$(Q)echo "	dc.b	\"ptable.library $(PLIB_VERSION) ($(PLIB_DATE)) [68020]\"" >> $@
	$(Q)echo "	else" >> $@
	$(Q)echo "	dc.b	\"ptable.library $(PLIB_VERSION) ($(PLIB_DATE)) [68000]\"" >> $@
	$(Q)echo "	endc" >> $@
	$(Q)echo "	endm" >> $@

# Update version suffix in README.md (in-place)
# Updates the "What's New" section header: ### v1.36 or ### v1.36-dev
version-readme:
	$(Q)sed -i 's/^### v$(VERSION_MAJOR)\.$(VERSION_MINOR)[^ ]* ([0-9]\{2\}\.[0-9]\{2\}\.[0-9]\{4\})/### v$(VERSION) ($(DATE))/' README.md
	$(Q)echo "  README  version updated to v$(VERSION) ($(DATE))"

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
	$(Q)$(VASM) $(VASMFLAGS) $(VASMCPU_$(cpu)) $(DEBUG_$(flav)) -o $@ $<
	$(Q)echo "          $$(stat -c%s $@) bytes, md5:$$(md5sum $@ | cut -c1-8)"

# ptable.library: dist/<flavor>/<cpu>/libs/ptable.library
$(LIBRARY_TARGETS): $(OUTDIR)/%/libs/ptable.library: $(LIB_SOURCE) $(LIB_SOURCE_DEPS) $(PLIB_VERSION_INC)
	$(eval flav := $(word 1,$(subst /, ,$*)))
	$(eval cpu  := $(word 2,$(subst /, ,$*)))
	$(Q)mkdir -p $(@D)
	$(Q)echo "  VASM    $@ [$(flav), $(cpu)]"
	$(Q)$(VASM) $(VASMFLAGS) $(VASMCPU_$(cpu)) $(DEBUG_$(flav)) -o $@ $<
	$(Q)echo "          $$(stat -c%s $@) bytes, md5:$$(md5sum $@ | cut -c1-8)"

# Per-tier convenience phonies (subsets of DEVICE_TARGETS / LIBRARY_TARGETS)
full:      check-vasm $(TARGET_FULL)
small:     check-vasm $(TARGET_SMALL)
full-000:  check-vasm $(TARGET_FULL_000)
small-000: check-vasm $(TARGET_SMALL_000)

library:           check-vasm $(LIBRARY_TARGETS)
library-full:      check-vasm $(LIB_FULL)
library-small:     check-vasm $(LIB_SMALL)
library-full-000:  check-vasm $(LIB_FULL_000)
library-small-000: check-vasm $(LIB_SMALL_000)

# Tools only target
tools: $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK)

# Generate AmigaGuide documentation from Markdown
guides:
	$(Q)echo "  GUIDE   dist/docs/*.guide"
	$(Q)tools/md2guide.py docs/CFInfo.md dist/docs/CFInfo.guide --version $(CFINFO_VERSION) --date $(CFINFO_DATE) --ver-title "CFInfo guide"
	$(Q)tools/md2guide.py docs/pcmciaspeed.md dist/docs/pcmciaspeed.guide --version $(PCMCIASPEED_VERSION) --date $(PCMCIASPEED_DATE) --ver-title "pcmciaspeed guide"
	$(Q)tools/md2guide.py docs/pcmciacheck.md dist/docs/pcmciacheck.guide --version $(PCMCIACHECK_VERSION) --date $(PCMCIACHECK_DATE) --ver-title "pcmciacheck guide"
	$(Q)tools/md2guide.py README.md dist/docs/cfd.guide --version $(CFD_VERSION) --date $(CFD_DATE) --title "compactflash.device" --ver-title "compactflash.device guide"

# CFInfo utility (requires vbcc)
$(TARGET_CFINFO): $(SOURCE_CFINFO)
	$(Q)mkdir -p $(OUTDIR_C)
	$(Q)echo "  VBCC    $(TARGET_CFINFO)"
	$(Q)VBCC=$(VBCC_HOME) PATH=$(VBCC_HOME)/bin:$$PATH $(VBCC) +aos68k -O2 -c99 -INDK/Include_H -DVERSION='"$(CFINFO_VERSION)"' -DDATE='"$(CFINFO_DATE)"' -o $(TARGET_CFINFO) $<
	$(Q)echo "          $$(stat -c%s $(TARGET_CFINFO)) bytes, md5:$$(md5sum $(TARGET_CFINFO) | cut -c1-8)"

# pcmciaspeed utility (requires vbcc)
$(TARGET_PCMCIASPEED): $(SOURCE_PCMCIASPEED)
	$(Q)mkdir -p $(OUTDIR_C)
	$(Q)echo "  VBCC    $(TARGET_PCMCIASPEED)"
	$(Q)VBCC=$(VBCC_HOME) PATH=$(VBCC_HOME)/bin:$$PATH $(VBCC) +aos68k -O2 -c99 -INDK/Include_H -DVERSION='"$(PCMCIASPEED_VERSION)"' -DDATE='"$(PCMCIASPEED_DATE)"' -o $(TARGET_PCMCIASPEED) $<
	$(Q)echo "          $$(stat -c%s $(TARGET_PCMCIASPEED)) bytes, md5:$$(md5sum $(TARGET_PCMCIASPEED) | cut -c1-8)"

# pcmciacheck utility (requires vbcc)
$(TARGET_PCMCIACHECK): $(SOURCE_PCMCIACHECK)
	$(Q)mkdir -p $(OUTDIR_C)
	$(Q)echo "  VBCC    $(TARGET_PCMCIACHECK)"
	$(Q)VBCC=$(VBCC_HOME) PATH=$(VBCC_HOME)/bin:$$PATH $(VBCC) +aos68k -O2 -c99 -INDK/Include_H -DVERSION='"$(PCMCIACHECK_VERSION)"' -DDATE='"$(PCMCIACHECK_DATE)"' -o $(TARGET_PCMCIACHECK) $<
	$(Q)echo "          $$(stat -c%s $(TARGET_PCMCIACHECK)) bytes, md5:$$(md5sum $(TARGET_PCMCIACHECK) | cut -c1-8)"

# ============================================================
# Release targets
# ============================================================

# Generate readme from template
$(README_NAME): $(README_TEMPLATE) $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK)
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
	    -e "s|@CFD_VERSION@|$(CFD_VERSION)|g" \
	    -e "s|@PLIB_VERSION@|$(PLIB_VERSION)|g" \
	    -e "s|@TOOL_CHECKSUMS@|$$tool_checksums|" \
	    $(README_TEMPLATE) > $@
	@echo "Generated: $@"

# Generate readme only
readme: $(README_NAME)

# Create Aminet-compatible LHA release
release: check-vasm version-readme $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(README_NAME) guides check-lha
	@echo "Creating Aminet release: $(ARCHIVE_NAME)"
	@echo "=================================="
	$(eval STAGING := $(shell mktemp -d))
	@mkdir -p "$(STAGING)/cfd/src/lib"
	@echo "Copying files..."
	@# Per-flavor binary trees (cfd/full/<cpu>/{devs,libs}/<file>)
	@cp -r dist/full dist/small "$(STAGING)/cfd/"
	@# Flavor-shared assets (tools, mountlist, docs, images)
	@cp -r dist/c dist/Storage dist/docs dist/images "$(STAGING)/cfd/"
	@# Top-level icons paired with the top-level drawers/files above.
	@# (devs.info / libs.info are reused per-flavor below, not at
	@# the cfd/ root - there are no top-level devs/ or libs/ drawers.)
	@cp dist/full.info dist/small.info \
	    dist/c.info dist/docs.info dist/images.info dist/src.info \
	    dist/LICENSE.info dist/def_CF0.info "$(STAGING)/cfd/"
	@# Source code
	@cp src/*.* "$(STAGING)/cfd/src/"
	@cp src/lib/*.* "$(STAGING)/cfd/src/lib/"
	@# Documentation and license
	@cp $(README_NAME) "$(STAGING)/cfd/cfd.readme"
	@cp $(README_INFO) "$(STAGING)/cfd/cfd.readme.info"
	@cp LICENSE "$(STAGING)/cfd/"
	@# Drawer icon
	@cp dist.info "$(STAGING)/cfd.info"
	@echo "Creating LHA archive..."
	@cd "$(STAGING)" && $(LHA) c "$(ARCHIVE_NAME)" cfd cfd.info
	@mv "$(STAGING)/$(ARCHIVE_NAME)" .
	@rm -rf "$(STAGING)"
	@echo ""
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

# Check if vasm is installed and expected version
check-vasm:
	@[ -x "$(VASM)" ] || { \
		echo "ERROR: vasm command not found: $(VASM)"; \
		echo "Set VASM_HOME to your vasm installation (expected $(EXPECTED_VASM_VERSION))"; \
		exit 1; \
	}
	@version_output="$$( $(VASM) -v 2>&1 )"; \
	detected_version="$$( printf '%s\n' "$$version_output" | sed '/./!d' | sed -n '1p' )"; \
	case "$$version_output" in \
		*"$(EXPECTED_VASM_VERSION)"*) ;; \
		*) \
			echo "ERROR: unsupported vasm version!"; \
			echo "Expected: $(EXPECTED_VASM_VERSION)"; \
			echo "Detected: $${detected_version:-<no output>}"; \
			exit 1; \
			;; \
	esac

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
checksums: $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK)
	@for target in $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK); do \
		if [ -f "$$target" ]; then \
			echo "=== $${target} ==="; \
			ls -l "$$target"; \
			echo "MD5:    $$(md5sum "$$target" | cut -d' ' -f1)"; \
			echo "SHA256: $$(sha256sum "$$target" | cut -d' ' -f1)"; \
			echo ""; \
		fi \
	done


# Clean build artifacts
clean:
	rm -f $(DRIVER_TARGETS) $(LIBRARY_TARGETS) $(TARGET_CFINFO) $(TARGET_PCMCIASPEED) $(TARGET_PCMCIACHECK) $(VERSION_INC) $(PLIB_VERSION_INC) $(VERSION_STAMP)
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
	@echo "  guides           - Generate AmigaGuide documentation from Markdown"
	@echo ""
	@echo "Options:"
	@echo "  V=1                 - Verbose output (show full compiler messages)"
	@echo "  GTIMING=1           - Enable Gayle timing optimization (experimental)"
	@echo "  VASM_HOME=/opt/vbcc - vasm installation path"
	@echo "  VBCC_HOME=/opt/vbcc - vbcc installation path"
	@echo ""
	@echo "Note: every device build carries a tiny RTF_COLDSTART stub"
	@echo "      that OpenLibrarys ptable.library at Kickstart cold start."
	@echo "      Make sure ptable.library ends up in ROM (Remus / Capitoline)"
	@echo "      for autoboot to fire."
	@echo ""
	@echo "Release targets:"
	@echo "  version-readme - Update version suffix in README.md (in-place)"
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
	@echo "  $(README_NAME) - Aminet readme"
	@echo "  $(ARCHIVE_NAME) - Aminet release archive"
	@echo ""
	@echo "Release: $(VERSION) ($(DATE)); compactflash.device: $(CFD_VERSION) ($(CFD_DATE)); ptable.library: $(PLIB_VERSION) ($(PLIB_DATE))"

.PHONY: all full small full-000 small-000 library library-full library-small library-full-000 library-small-000 tools guides version-readme readme release check-lha checksums clean distclean help
