#!/bin/bash
#
# build_putty_apps.sh - Build PuTTY apps and create macOS app bundles
#
# This script:
# 1. Compiles PuTTY, pterm, and command-line tools using jhbuild GTK3
# 2. Creates relocatable app bundles with all dependencies
# 3. Generates a DMG with all applications
#

set -e  # Exit on error

# Configuration
JHBUILD_PREFIX="${JHBUILD_PREFIX:-$HOME/source/jhbuild/install}"
PUTTY_SOURCE="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE_GENERATOR="${APP_BUNDLE_GENERATOR:-$HOME/source/AppBundleGenerator/AppBundleGenerator}"
DEST_DIR="${DEST_DIR:-$HOME/Desktop}"
VERSION="0.82"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  PuTTY macOS App Bundle Builder${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  jhbuild prefix: $JHBUILD_PREFIX"
echo "  Source directory: $PUTTY_SOURCE"
echo "  AppBundleGenerator: $APP_BUNDLE_GENERATOR"
echo "  Destination: $DEST_DIR"
echo "  Version: $VERSION"
echo ""

# Verify prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if [ ! -f "$APP_BUNDLE_GENERATOR" ]; then
    echo -e "${RED}Error: AppBundleGenerator not found at: $APP_BUNDLE_GENERATOR${NC}"
    echo "Please build AppBundleGenerator first:"
    echo "  cd ~/source/AppBundleGenerator && make"
    exit 1
fi

if [ ! -d "$JHBUILD_PREFIX" ]; then
    echo -e "${RED}Error: jhbuild prefix not found at: $JHBUILD_PREFIX${NC}"
    echo "Please build GTK3 stack with jhbuild first"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites found${NC}"
echo ""

# Set up jhbuild environment
export PATH="$JHBUILD_PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$JHBUILD_PREFIX/lib/pkgconfig:$JHBUILD_PREFIX/share/pkgconfig"
export LD_LIBRARY_PATH="$JHBUILD_PREFIX/lib:$LD_LIBRARY_PATH"
export CC=/usr/bin/clang
export CFLAGS="-I$JHBUILD_PREFIX/include"
export LDFLAGS="-L$JHBUILD_PREFIX/lib"

# Step 1: Build PuTTY binaries
echo -e "${YELLOW}Step 1: Building PuTTY binaries...${NC}"

cd "$PUTTY_SOURCE/unix"

# Get GTK flags
GTK_CFLAGS=$(pkg-config --cflags gtk+-3.0 gtk-mac-integration-gtk3)
GTK_LIBS=$(pkg-config --libs gtk+-3.0 gtk-mac-integration-gtk3)

echo "  GTK_CFLAGS: $GTK_CFLAGS"
echo "  GTK_LIBS: $GTK_LIBS"
echo ""

# Compile putty (SSH GUI client)
echo "  Building putty..."
$CC $CFLAGS $GTK_CFLAGS -o ../putty \
    gtkapp.c gtkwin.c gtkdlg.c gtkcfg.c gtkask.c gtkfont.c gtkmisc.c \
    gtkcomm.c gtkcols.c gtkdisplay.c gtkseat.c gtkslotman.c \
    ../terminal.c ../window.c ../config.c ../dialog.c \
    ../settings.c ../tree234.c ../callback.c ../timing.c \
    ../be_all_s.c ../be_misc.c \
    ../ssh.c ../sshaes.c ../ssharcf.c ../sshblowf.c ../sshbn.c \
    ../sshccp.c ../sshcrc.c ../sshcrcda.c ../sshdes.c ../sshdh.c \
    ../sshdss.c ../sshecc.c ../sshgssc.c ../sshhmac.c ../sshmd5.c \
    ../sshpubk.c ../sshrand.c ../sshrsa.c ../sshsh256.c ../sshsh512.c \
    ../sshsha.c ../sshsha3.c ../sshzlib.c \
    ../portfwd.c ../x11fwd.c ../ldisc.c ../logging.c ../proxy.c \
    ../raw.c ../rlogin.c ../telnet.c ../serial.c \
    ../uxnet.c ../uxnoise.c ../uxproxy.c ../uxsel.c ../uxser.c \
    ../uxstore.c ../uxpty.c ../uxpoll.c ../uxutils.c ../uxmisc.c \
    ../uxgss.c ../uxagentc.c \
    ../misc.c ../minibidi.c ../stripctrl.c ../cmdline.c \
    ../time.c ../wildcard.c ../pinger.c ../printerc.c ../version.c \
    ../sshutils.c ../sshbcrypt.c ../sshpubk.c \
    $LDFLAGS $GTK_LIBS \
    2>&1 | tee ../putty_build.log || {
        echo -e "${RED}Failed to build putty${NC}"
        cat ../putty_build.log
        exit 1
    }

# Compile pterm (standalone terminal emulator)
echo "  Building pterm..."
$CC $CFLAGS $GTK_CFLAGS -o ../pterm \
    gtkapp.c gtkwin.c gtkdlg.c gtkcfg.c gtkask.c gtkfont.c gtkmisc.c \
    gtkcomm.c gtkcols.c gtkdisplay.c gtkseat.c gtkslotman.c \
    ../terminal.c ../window.c ../config.c ../dialog.c \
    ../settings.c ../tree234.c ../callback.c ../timing.c \
    ../be_none.c ../be_misc.c \
    ../ldisc.c ../logging.c \
    ../uxnet.c ../uxnoise.c ../uxproxy.c ../uxsel.c ../uxser.c \
    ../uxstore.c ../uxpty.c ../uxpoll.c ../uxutils.c ../uxmisc.c \
    ../misc.c ../minibidi.c ../stripctrl.c ../cmdline.c \
    ../time.c ../wildcard.c ../version.c \
    $LDFLAGS $GTK_LIBS \
    2>&1 | tee ../pterm_build.log || {
        echo -e "${YELLOW}Warning: Failed to build pterm, continuing...${NC}"
    }

cd "$PUTTY_SOURCE"

echo -e "${GREEN}✓ PuTTY binaries built${NC}"
echo ""

# Step 2: Create app bundles for putty and pterm
echo -e "${YELLOW}Step 2: Creating app bundles...${NC}"

# Create bundles for each GUI app
for app in putty pterm; do
    if [ ! -f "$PUTTY_SOURCE/$app" ]; then
        echo -e "${YELLOW}  Skipping $app (not built)${NC}"
        continue
    fi

    APP_NAME=$(echo $app | sed 's/.*/\u&/')  # Capitalize first letter
    BUNDLE_ID="org.tartarus.$app"

    echo "  Creating $APP_NAME.app..."

    BUNDLE_ARGS=()
    BUNDLE_ARGS+=("--identifier" "$BUNDLE_ID")
    BUNDLE_ARGS+=("--version" "$VERSION")
    BUNDLE_ARGS+=("--category" "public.app-category.utilities")
    BUNDLE_ARGS+=("--min-os" "12.0")
    BUNDLE_ARGS+=("--sign" "-")
    BUNDLE_ARGS+=("--hardened-runtime")
    BUNDLE_ARGS+=("--allow-dyld-vars")
    BUNDLE_ARGS+=("--stage-dependencies" "$JHBUILD_PREFIX")

    "$APP_BUNDLE_GENERATOR" \
        "${BUNDLE_ARGS[@]}" \
        "$APP_NAME" \
        "$DEST_DIR" \
        "$PUTTY_SOURCE/$app" || {
        echo -e "${RED}Failed to create $APP_NAME.app${NC}"
        exit 1
    }

    echo -e "${GREEN}  ✓ $APP_NAME.app created${NC}"
done

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}     Build Complete!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${BLUE}App bundles created:${NC}"
ls -d "$DEST_DIR"/*.app 2>/dev/null | grep -E "(Putty|Pterm)" || echo "  None"
echo ""
echo -e "${BLUE}To test:${NC}"
echo "  open \"$DEST_DIR/Putty.app\""
echo ""
