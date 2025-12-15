#!/bin/bash
# create_dmg.sh - Create a distributable DMG for PuTTY applications
# Based on ../gftp/create_dmg.sh

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${DEST_DIR:-$HOME/Desktop}"
VERSION="0.83"
GIT_REV=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
DMG_NAME="PuTTY-${VERSION}-${GIT_REV}-macOS"
VOLUME_NAME="PuTTY $VERSION"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}WARN: $1${NC}"
}

info "Creating DMG for PuTTY $VERSION (git: $GIT_REV)"

# Find all PuTTY app bundles
APP_BUNDLES=()
for app in Putty Pterm; do
    if [ -d "$DEST_DIR/$app.app" ]; then
        APP_BUNDLES+=("$DEST_DIR/$app.app")
    fi
done

if [ ${#APP_BUNDLES[@]} -eq 0 ]; then
    error "No app bundles found in $DEST_DIR. Run ./build_putty_mac.sh first."
fi

info "Found ${#APP_BUNDLES[@]} app bundle(s)"

# Remove old DMG if it exists
if [ -f "${DMG_NAME}.dmg" ]; then
    warn "Removing existing DMG: ${DMG_NAME}.dmg"
    rm -f "${DMG_NAME}.dmg"
fi

# Create temporary directory for DMG contents
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

info "Preparing DMG contents..."

# Copy app bundles
for bundle in "${APP_BUNDLES[@]}"; do
    info "  Adding $(basename "$bundle")"
    cp -R "$bundle" "$TEMP_DIR/"
done

# Create README for DMG
cat > "$TEMP_DIR/README.txt" << EOF
PuTTY for macOS
Version: $VERSION
Git Revision: $GIT_REV

PuTTY is a free SSH, Telnet, and serial terminal emulator.

Applications included:
  - Putty.app:  Full SSH/Telnet/Serial client with GUI
  - Pterm.app:  Standalone terminal emulator

Installation:
  Drag the applications to your Applications folder

Usage:
  Double-click any application to launch

Configuration:
  Settings are stored in ~/.putty/

Documentation:
  Visit: https://www.chiark.greenend.org.uk/~sgtatham/putty/

License:
  MIT License

Requirements:
  macOS 12.0 or later
EOF

# Create symbolic link to Applications folder for easy installation
info "Creating Applications symlink..."
ln -s /Applications "$TEMP_DIR/Applications"

# Create DMG
info "Creating DMG: ${DMG_NAME}.dmg"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$TEMP_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${DMG_NAME}.dmg"

# Verify DMG was created
if [ ! -f "${DMG_NAME}.dmg" ]; then
    error "Failed to create DMG"
fi

# Get DMG size
DMG_SIZE=$(du -h "${DMG_NAME}.dmg" | cut -f1)

info "DMG created successfully!"
echo ""
echo "DMG information:"
echo "  File: $SCRIPT_DIR/${DMG_NAME}.dmg"
echo "  Size: $DMG_SIZE"
echo "  Version: $VERSION"
echo "  Git revision: $GIT_REV"
echo "  Applications: ${#APP_BUNDLES[@]}"
echo ""
echo "To test the DMG:"
echo "  open ${DMG_NAME}.dmg"
echo ""
