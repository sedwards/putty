#!/bin/bash
# create_dmg.sh - Create a distributable DMG for PuTTY applications
# Includes GUI apps, CLI tools, and installation scripts

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${DEST_DIR:-$HOME/Desktop}"
BUILD_DIR="$SCRIPT_DIR/build"
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

# Check for CLI tools
CLI_TOOLS=(plink pscp psftp puttygen pageant)
FOUND_CLI_TOOLS=()
for tool in "${CLI_TOOLS[@]}"; do
    if [ -f "$BUILD_DIR/$tool" ]; then
        FOUND_CLI_TOOLS+=("$tool")
    fi
done

if [ ${#FOUND_CLI_TOOLS[@]} -eq 0 ]; then
    warn "No CLI tools found in $BUILD_DIR"
fi

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

# Create CLI Tools directory
if [ ${#FOUND_CLI_TOOLS[@]} -gt 0 ]; then
    info "Adding CLI tools..."
    mkdir -p "$TEMP_DIR/CLI Tools"
    for tool in "${FOUND_CLI_TOOLS[@]}"; do
        info "  Adding $tool"
        cp "$BUILD_DIR/$tool" "$TEMP_DIR/CLI Tools/"
        chmod 755 "$TEMP_DIR/CLI Tools/$tool"
    done
fi

# Create installation script for CLI tools
info "Creating installation script..."
cat > "$TEMP_DIR/Install CLI Tools" << 'INSTALL_SCRIPT'
#!/bin/bash
# Install PuTTY CLI Tools to /usr/local/bin

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}PuTTY CLI Tools Installer${NC}"
echo ""
echo "This will install the following command-line tools to /usr/local/bin:"
echo "  • plink    - SSH command-line client"
echo "  • pscp     - SCP file transfer utility"
echo "  • psftp    - SFTP file transfer utility"
echo "  • puttygen - SSH key generation tool"
echo "  • pageant  - SSH authentication agent"
echo ""
echo -e "${YELLOW}Administrator password required${NC}"
echo ""

# Get the directory containing this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_TOOLS_DIR="$SCRIPT_DIR/CLI Tools"

if [ ! -d "$CLI_TOOLS_DIR" ]; then
    echo -e "${RED}Error: CLI Tools directory not found${NC}"
    exit 1
fi

# Ensure /usr/local/bin exists
if [ ! -d /usr/local/bin ]; then
    echo "Creating /usr/local/bin directory..."
    sudo mkdir -p /usr/local/bin || {
        echo -e "${RED}Failed to create /usr/local/bin${NC}"
        exit 1
    }
fi

# Install each tool
INSTALLED=0
FAILED=0

for tool in plink pscp psftp puttygen pageant; do
    if [ -f "$CLI_TOOLS_DIR/$tool" ]; then
        echo -e "${GREEN}Installing $tool...${NC}"
        if sudo cp "$CLI_TOOLS_DIR/$tool" /usr/local/bin/ && sudo chmod 755 "/usr/local/bin/$tool"; then
            INSTALLED=$((INSTALLED + 1))
        else
            echo -e "${RED}Failed to install $tool${NC}"
            FAILED=$((FAILED + 1))
        fi
    fi
done

echo ""
if [ $INSTALLED -gt 0 ]; then
    echo -e "${GREEN}Successfully installed $INSTALLED CLI tool(s)${NC}"
    echo ""
    echo "The tools are now available in your terminal:"
    for tool in plink pscp psftp puttygen pageant; do
        if [ -f "/usr/local/bin/$tool" ]; then
            echo "  $tool"
        fi
    done
    echo ""
    echo "Configuration will be stored in: ~/Library/Putty/"
fi

if [ $FAILED -gt 0 ]; then
    echo -e "${YELLOW}Warning: $FAILED tool(s) failed to install${NC}"
fi

echo ""
echo "To uninstall, run: Uninstall PuTTY"
echo ""
read -p "Press Enter to close..."
INSTALL_SCRIPT

chmod 755 "$TEMP_DIR/Install CLI Tools"

# Create uninstaller script
info "Creating uninstaller script..."
cat > "$TEMP_DIR/Uninstall PuTTY" << 'UNINSTALL_SCRIPT'
#!/bin/bash
# Uninstall PuTTY from macOS

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}PuTTY Uninstaller${NC}"
echo ""
echo "This will remove:"
echo "  • /Applications/Putty.app"
echo "  • /Applications/Pterm.app"
echo "  • /usr/local/bin/plink"
echo "  • /usr/local/bin/pscp"
echo "  • /usr/local/bin/psftp"
echo "  • /usr/local/bin/puttygen"
echo "  • /usr/local/bin/pageant"
echo ""
echo -e "${YELLOW}User settings in ~/Library/Putty will NOT be removed${NC}"
echo ""
read -p "Continue with uninstallation? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled"
    exit 0
fi

echo ""
echo -e "${GREEN}Removing PuTTY...${NC}"
echo -e "${YELLOW}Administrator password required${NC}"
echo ""

# Remove applications
REMOVED=0
if [ -d "/Applications/Putty.app" ]; then
    echo "  Removing Putty.app"
    sudo rm -rf "/Applications/Putty.app" && REMOVED=$((REMOVED + 1))
fi

if [ -d "/Applications/Pterm.app" ]; then
    echo "  Removing Pterm.app"
    sudo rm -rf "/Applications/Pterm.app" && REMOVED=$((REMOVED + 1))
fi

# Remove CLI tools
for tool in plink pscp psftp puttygen pageant; do
    if [ -f "/usr/local/bin/$tool" ]; then
        echo "  Removing $tool"
        sudo rm -f "/usr/local/bin/$tool" && REMOVED=$((REMOVED + 1))
    fi
done

echo ""
if [ $REMOVED -gt 0 ]; then
    echo -e "${GREEN}PuTTY has been uninstalled successfully${NC}"
    echo ""
    echo "To remove user settings, run:"
    echo "  rm -rf ~/Library/Putty"
else
    echo -e "${YELLOW}No PuTTY components found to remove${NC}"
fi

echo ""
read -p "Press Enter to close..."
UNINSTALL_SCRIPT

chmod 755 "$TEMP_DIR/Uninstall PuTTY"

# Create README for DMG
cat > "$TEMP_DIR/README.txt" << EOF
PuTTY for macOS
Version: $VERSION
Git Revision: $GIT_REV

PuTTY is a free SSH, Telnet, and serial terminal emulator.

===================
INCLUDED COMPONENTS
===================

GUI Applications:
  • Putty.app  - Full SSH/Telnet/Serial client with GUI
  • Pterm.app  - Standalone terminal emulator

Command-line Tools:
  • plink      - SSH command-line client
  • pscp       - SCP file transfer utility
  • psftp      - SFTP file transfer utility
  • puttygen   - SSH key generation tool
  • pageant    - SSH authentication agent

Installation Scripts:
  • Install CLI Tools  - Install command-line tools to /usr/local/bin
  • Uninstall PuTTY   - Remove all PuTTY components from your system

============
INSTALLATION
============

GUI Applications:
  Drag Putty.app and/or Pterm.app to your Applications folder

Command-line Tools:
  1. Double-click "Install CLI Tools" to install to /usr/local/bin
  2. Enter your password when prompted
  3. Tools will be available in Terminal

=============
CONFIGURATION
=============

Settings are stored in: ~/Library/Putty/

On first launch, PuTTY will create this directory automatically.
All session configurations, saved keys, and preferences are stored here.

=============
DOCUMENTATION
=============

Visit: https://www.chiark.greenend.org.uk/~sgtatham/putty/

For help with SSH connections:
  man ssh
  plink --help

============
UNINSTALLING
============

To uninstall PuTTY:
  1. Double-click "Uninstall PuTTY"
  2. Enter your password when prompted
  3. User settings in ~/Library/Putty will be preserved
     (Delete manually if desired)

Or manually:
  rm -rf /Applications/Putty.app
  rm -rf /Applications/Pterm.app
  sudo rm -f /usr/local/bin/{plink,pscp,psftp,puttygen,pageant}
  rm -rf ~/Library/Putty  # Optional: removes your settings

============
REQUIREMENTS
============

macOS 12.0 or later

=======
LICENSE
=======

MIT License

PuTTY is copyright 1997-$(date +%Y) Simon Tatham.

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

=================
BUILD INFORMATION
=================

Built with: GTK3 via jhbuild
Build date: $(date)
Git revision: $GIT_REV
Build host: $(hostname)
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
echo "  GUI apps: ${#APP_BUNDLES[@]}"
echo "  CLI tools: ${#FOUND_CLI_TOOLS[@]}"
echo ""
echo "DMG contents:"
echo "  • Putty.app and Pterm.app (drag to Applications)"
echo "  • CLI Tools/ directory with command-line utilities"
echo "  • Install CLI Tools - Installation script"
echo "  • Uninstall PuTTY - Uninstaller script"
echo "  • README.txt - Documentation"
echo "  • Applications symlink"
echo ""
echo "To test the DMG:"
echo "  open ${DMG_NAME}.dmg"
echo ""
