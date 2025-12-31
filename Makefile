# Makefile for compactflash.device
# Cross-compilation for Amiga using vasm

# Version (update these for new releases)
VERSION = 1.35
DATE = 31.12.2025
DATE_SHORT = 12/2025

# Derived version (remove dot for filenames)
VERSION_NODOT = $(subst .,,$(VERSION))

# Tools
VASM = vasmm68k_mot
LHA = lha

# Flags
VASMFLAGS = -Fhunkexe -m68020 -nosym

# Directories
SRCDIR = src
OUTDIR = devs

# Files
SOURCE = $(SRCDIR)/cfd.s
TARGET_DEBUG = $(OUTDIR)/compactflash.device
TARGET_SMALL = $(OUTDIR)/compactflash.device.small

# Release files
RELEASE_NAME = cfd$(VERSION_NODOT)
ARCHIVE_NAME = $(RELEASE_NAME).lha
README_NAME = $(RELEASE_NAME).readme
README_TEMPLATE = cfd.readme.in

# ============================================================
# Build targets
# ============================================================

# Default target - build both versions
all: $(TARGET_DEBUG) $(TARGET_SMALL)

# Full version (with serial debug capability)
$(TARGET_DEBUG): $(SOURCE)
	$(VASM) $(VASMFLAGS) -DDEBUG=1 -o $@ $<
	@echo "Built: $@ ($$(stat -c%s $@) bytes) [full]"

# Small version (no debug code/strings)
$(TARGET_SMALL): $(SOURCE)
	$(VASM) $(VASMFLAGS) -o $@ $<
	@echo "Built: $@ ($$(stat -c%s $@) bytes) [no debug]"

# Build only full version
full: $(TARGET_DEBUG)

# Build only small version
small: $(TARGET_SMALL)

# ============================================================
# Release targets
# ============================================================

# Generate readme from template
$(README_NAME): $(README_TEMPLATE) $(TARGET_DEBUG) $(TARGET_SMALL)
	@echo "Generating $(README_NAME) from template..."
	$(eval DEBUG_SIZE := $(shell stat -c%s $(TARGET_DEBUG)))
	$(eval DEBUG_MD5 := $(shell md5sum $(TARGET_DEBUG) | cut -d' ' -f1))
	$(eval DEBUG_SHA256 := $(shell sha256sum $(TARGET_DEBUG) | cut -d' ' -f1))
	$(eval NODEBUG_SIZE := $(shell stat -c%s $(TARGET_SMALL)))
	$(eval NODEBUG_MD5 := $(shell md5sum $(TARGET_SMALL) | cut -d' ' -f1))
	$(eval NODEBUG_SHA256 := $(shell sha256sum $(TARGET_SMALL) | cut -d' ' -f1))
	@sed -e 's|@VERSION@|$(VERSION_NODOT)|g' \
	     -e 's|@VERSION_DOT@|$(VERSION)|g' \
	     -e 's|@DATE@|$(DATE)|g' \
	     -e 's|@DATE_SHORT@|$(DATE_SHORT)|g' \
	     -e 's|@DEBUG_SIZE@|$(DEBUG_SIZE)|g' \
	     -e 's|@DEBUG_MD5@|$(DEBUG_MD5)|g' \
	     -e 's|@DEBUG_SHA256@|$(DEBUG_SHA256)|g' \
	     -e 's|@NODEBUG_SIZE@|$(NODEBUG_SIZE)|g' \
	     -e 's|@NODEBUG_MD5@|$(NODEBUG_MD5)|g' \
	     -e 's|@NODEBUG_SHA256@|$(NODEBUG_SHA256)|g' \
	     $(README_TEMPLATE) > $@
	@echo "Generated: $@"

# Generate readme only
readme: $(README_NAME)

# Create Aminet-compatible LHA release
release: $(TARGET_DEBUG) $(TARGET_SMALL) $(README_NAME) check-lha
	@echo "Creating Aminet release: $(ARCHIVE_NAME)"
	@echo "=================================="
	$(eval STAGING := $(shell mktemp -d))
	@mkdir -p "$(STAGING)/cfd/c"
	@mkdir -p "$(STAGING)/cfd/devs"
	@mkdir -p "$(STAGING)/cfd/src"
	@echo "Copying files..."
	@# Binaries
	@cp c/pcmciacheck "$(STAGING)/cfd/c/" 2>/dev/null || true
	@cp c/pcmciaspeed "$(STAGING)/cfd/c/" 2>/dev/null || true
	@# Device variants and mountlist
	@cp $(TARGET_DEBUG) "$(STAGING)/cfd/devs/"
	@cp $(TARGET_SMALL) "$(STAGING)/cfd/devs/"
	@cp devs/CF0 "$(STAGING)/cfd/devs/"
	@cp devs/CF0.info "$(STAGING)/cfd/devs/" 2>/dev/null || true
	@# Source code
	@cp src/*.s "$(STAGING)/cfd/src/"
	@# Documentation
	@cp README.md "$(STAGING)/cfd/"
	@cp LICENSE "$(STAGING)/cfd/"
	@# Images (optional)
	@mkdir -p "$(STAGING)/cfd/images"
	@cp images/cf-pcmcia-adapter.jpg "$(STAGING)/cfd/images/" 2>/dev/null || true
	@cp images/sd-cf-adapter.jpg "$(STAGING)/cfd/images/" 2>/dev/null || true
	@cp images/multimode-issue.jpg "$(STAGING)/cfd/images/" 2>/dev/null || true
	@# Amiga icon files
	@cp c.info "$(STAGING)/cfd/" 2>/dev/null || true
	@cp devs.info "$(STAGING)/cfd/" 2>/dev/null || true
	@cp images.info "$(STAGING)/cfd/images.info" 2>/dev/null || true
	@cp images/cf-pcmcia-adapter.jpg.info "$(STAGING)/cfd/images/" 2>/dev/null || true
	@cp images/sd-cf-adapter.jpg.info "$(STAGING)/cfd/images/" 2>/dev/null || true
	@cp images/multimode-issue.jpg.info "$(STAGING)/cfd/images/" 2>/dev/null || true
	@cp def_CF0.info "$(STAGING)/cfd/" 2>/dev/null || true
	@echo "Creating LHA archive..."
	@cd "$(STAGING)" && $(LHA) c "$(ARCHIVE_NAME)" cfd
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

# Show checksums for both versions
checksums: $(TARGET_DEBUG) $(TARGET_SMALL)
	@echo "=== Full version ==="
	@ls -l $(TARGET_DEBUG)
	@echo "MD5:    $$(md5sum $(TARGET_DEBUG) | cut -d' ' -f1)"
	@echo "SHA256: $$(sha256sum $(TARGET_DEBUG) | cut -d' ' -f1)"
	@echo ""
	@echo "=== Small version (no debug) ==="
	@ls -l $(TARGET_SMALL)
	@echo "MD5:    $$(md5sum $(TARGET_SMALL) | cut -d' ' -f1)"
	@echo "SHA256: $$(sha256sum $(TARGET_SMALL) | cut -d' ' -f1)"

# Clean build artifacts
clean:
	rm -f $(TARGET_DEBUG) $(TARGET_SMALL)

# Clean everything including release archives
distclean: clean
	rm -f cfd*.lha cfd*.readme

# Show help
help:
	@echo "Build targets:"
	@echo "  all       - Build both versions (default)"
	@echo "  full      - Build full version only (with serial debug capability)"
	@echo "  small     - Build small version only (no debug)"
	@echo ""
	@echo "Release targets:"
	@echo "  readme    - Generate $(README_NAME) from template"
	@echo "  release   - Create Aminet LHA archive + readme"
	@echo ""
	@echo "Utility targets:"
	@echo "  checksums - Show file sizes and checksums"
	@echo "  clean     - Remove built device files"
	@echo "  distclean - Remove all generated files including archives"
	@echo "  help      - Show this help"
	@echo ""
	@echo "Output files:"
	@echo "  $(TARGET_DEBUG)  - full version (with serial debug capability)"
	@echo "  $(TARGET_SMALL)  - small version (no debug code)"
	@echo "  $(README_NAME)   - Aminet readme (generated)"
	@echo "  $(ARCHIVE_NAME)  - Aminet release archive"
	@echo ""
	@echo "Version: $(VERSION) ($(DATE))"

.PHONY: all full small readme release check-lha checksums clean distclean help
