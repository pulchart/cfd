#!/bin/bash
# Script to create Aminet-compatible LHA release for cfd
# Run this from the cfd directory

set -e

VERSION="134"
RELEASE_NAME="cfd${VERSION}"
ARCHIVE_NAME="cfd${VERSION}.lha"

echo "Creating Aminet release: ${ARCHIVE_NAME}"
echo "=================================="

# Check if lha is installed
if ! command -v lha &> /dev/null; then
    echo "ERROR: lha command not found!"
    echo "Install with: sudo dnf install lha  (Fedora)"
    echo "          or: sudo apt install lha  (Debian/Ubuntu)"
    exit 1
fi

# Create clean staging directory
STAGING_DIR=$(mktemp -d)
RELEASE_DIR="${STAGING_DIR}/cfd"

echo "Staging directory: ${STAGING_DIR}"

# Create directory structure
mkdir -p "${RELEASE_DIR}/c"
mkdir -p "${RELEASE_DIR}/devs"
mkdir -p "${RELEASE_DIR}/src"

# Copy files
echo "Copying files..."

# Binaries
cp c/cfddebug "${RELEASE_DIR}/c/"
cp c/pcmciacheck "${RELEASE_DIR}/c/"
cp c/pcmciaspeed "${RELEASE_DIR}/c/"

# Device and mountlist
cp devs/compactflash.device "${RELEASE_DIR}/devs/"
cp devs/CF0 "${RELEASE_DIR}/devs/"
cp devs/CF0.info "${RELEASE_DIR}/devs/" 2>/dev/null || true

# Source code
cp src/*.s "${RELEASE_DIR}/src/"

# Documentation and metadata
cp README.md "${RELEASE_DIR}/"
cp LICENSE "${RELEASE_DIR}/"

# Images (optional, but useful for documentation)
cp adapter.jpg "${RELEASE_DIR}/" 2>/dev/null || true
cp adapter2.jpg "${RELEASE_DIR}/" 2>/dev/null || true

# Amiga icon files (if they exist)
cp c.info "${RELEASE_DIR}/" 2>/dev/null || true
cp devs.info "${RELEASE_DIR}/" 2>/dev/null || true
cp adapter.jpg.info "${RELEASE_DIR}/" 2>/dev/null || true
cp adapter2.jpg.info "${RELEASE_DIR}/" 2>/dev/null || true
cp def_CF0.info "${RELEASE_DIR}/" 2>/dev/null || true

# Create LHA archive
echo "Creating LHA archive..."
cd "${STAGING_DIR}"
lha c "${ARCHIVE_NAME}" cfd

# Move archive to original directory
cd -
mv "${STAGING_DIR}/${ARCHIVE_NAME}" .

# Cleanup
rm -rf "${STAGING_DIR}"

# Show result
echo ""
echo "=================================="
echo "Created: ${ARCHIVE_NAME}"
echo ""
ls -lh "${ARCHIVE_NAME}"
echo ""
echo "Contents:"
lha l "${ARCHIVE_NAME}"
echo ""
echo "For Aminet upload:"
echo "  1. ${ARCHIVE_NAME}"
echo "  2. cfd${VERSION}.readme"
echo ""
echo "Upload to: ftp://main.aminet.net/new"

