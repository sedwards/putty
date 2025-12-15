#!/bin/bash
#
# build_putty_mac.sh - Build PuTTY applications and create macOS app bundles
#
# This script:
# 1. Builds PuTTY with CMake using jhbuild GTK3
# 2. Creates relocatable app bundles with all dependencies
# 3. Uses AppBundleGenerator like the gFTP build process
#
# Based on ../gftp/build_gftp_app.sh
#

set -e  # Exit on error

# Configuration
JHBUILD_PREFIX="${JHBUILD_PREFIX:-$HOME/source/jhbuild/install}"
PUTTY_SOURCE="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE_GENERATOR="${APP_BUNDLE_GENERATOR:-$HOME/source/AppBundleGenerator/AppBundleGenerator}"
DEST_DIR="${DEST_DIR:-$HOME/Desktop}"
VERSION="0.83"

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

if ! command -v cmake &> /dev/null; then
    echo -e "${RED}Error: cmake not found in PATH${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites found${NC}"
echo ""

# Set up jhbuild environment
export PATH="$JHBUILD_PREFIX/bin:/opt/homebrew/bin:/usr/bin:/bin"
export PKG_CONFIG_PATH="$JHBUILD_PREFIX/lib/pkgconfig:$JHBUILD_PREFIX/share/pkgconfig"
export LD_LIBRARY_PATH="$JHBUILD_PREFIX/lib:$LD_LIBRARY_PATH"
export CC=/usr/bin/clang
export CFLAGS="-I$JHBUILD_PREFIX/include"
export LDFLAGS="-L$JHBUILD_PREFIX/lib"

# Step 1: Build PuTTY with CMake
echo -e "${YELLOW}Step 1: Building PuTTY with CMake...${NC}"

cd "$PUTTY_SOURCE"

# Create build directory
BUILD_DIR="build_macos"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "  Configuring with CMake..."
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$JHBUILD_PREFIX" \
    -DCMAKE_PREFIX_PATH="$JHBUILD_PREFIX" \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_C_FLAGS="-I$JHBUILD_PREFIX/include" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$JHBUILD_PREFIX/lib" \
    || {
    echo -e "${RED}CMake configuration failed${NC}"
    exit 1
}

echo "  Compiling..."
make -j4 || {
    echo -e "${RED}Build failed${NC}"
    exit 1
}

cd "$PUTTY_SOURCE"

echo -e "${GREEN}✓ PuTTY built successfully${NC}"
echo ""

# Step 2: Find built binaries
echo -e "${YELLOW}Step 2: Locating binaries...${NC}"

# GUI applications that need app bundles
GUI_APPS=("putty" "pterm")

for app in "${GUI_APPS[@]}"; do
    APP_PATH=$(find "$BUILD_DIR" -name "$app" -type f -perm +111 2>/dev/null | grep -v "\.dSYM" | head -1)
    if [ -n "$APP_PATH" ] && [ -f "$APP_PATH" ]; then
        echo "  Found $app: $APP_PATH"
        APP_VAR=$(echo "$app" | tr '[:lower:]' '[:upper:]')_BIN
        eval "$APP_VAR=\"$APP_PATH\""
    else
        echo -e "${YELLOW}  Warning: $app not found${NC}"
    fi
done

echo ""

# Step 3: Create app bundles
echo -e "${YELLOW}Step 3: Creating macOS app bundles...${NC}"

for app in "${GUI_APPS[@]}"; do
    APP_VAR="$(echo "$app" | tr '[:lower:]' '[:upper:]')_BIN"
    APP_BIN=$(eval "echo \$$APP_VAR")

    if [ -z "$APP_BIN" ] || [ ! -f "$APP_BIN" ]; then
        echo -e "${YELLOW}  Skipping $app (not built)${NC}"
        continue
    fi

    APP_NAME="$(echo ${app:0:1} | tr '[:lower:]' '[:upper:]')${app:1}"  # Capitalize first letter
    BUNDLE_ID="org.tartarus.putty.$app"

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
        "$APP_BIN" || {
        echo -e "${RED}Failed to create $APP_NAME.app${NC}"
        continue
    }

    echo -e "${GREEN}  ✓ $APP_NAME.app created${NC}"
done

echo ""

# Step 4: Verify bundles
echo -e "${YELLOW}Step 4: Verifying app bundles...${NC}"

for app in "${GUI_APPS[@]}"; do
    APP_NAME="$(echo ${app:0:1} | tr '[:lower:]' '[:upper:]')${app:1}"
    BUNDLE_PATH="$DEST_DIR/$APP_NAME.app"

    if [ ! -d "$BUNDLE_PATH" ]; then
        continue
    fi

    echo "  Checking $APP_NAME.app..."
    if [ ! -f "$BUNDLE_PATH/Contents/Info.plist" ]; then
        echo -e "${RED}    ✗ Missing Info.plist${NC}"
        continue
    fi

    if [ ! -d "$BUNDLE_PATH/Contents/Resources/lib" ]; then
        echo -e "${YELLOW}    Warning: Resources/lib not found${NC}"
    fi

    echo -e "${GREEN}    ✓ Bundle structure looks good${NC}"
done

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}     Build Complete!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${BLUE}App bundles created:${NC}"
for app in "${GUI_APPS[@]}"; do
    APP_NAME="$(echo ${app:0:1} | tr '[:lower:]' '[:upper:]')${app:1}"
    if [ -d "$DEST_DIR/$APP_NAME.app" ]; then
        echo "  $DEST_DIR/$APP_NAME.app"
    fi
done
echo ""
echo -e "${BLUE}To test:${NC}"
echo "  open \"$DEST_DIR/Putty.app\""
echo ""
echo -e "${BLUE}To create a DMG:${NC}"
echo "  ./create_dmg.sh"
echo ""
