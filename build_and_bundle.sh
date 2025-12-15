#!/bin/bash
#
# build_and_bundle.sh - Complete PuTTY build and bundle script
#
# This script builds PuTTY using CMake and creates app bundles
#

set -e

# Configuration
JHBUILD_PREFIX="${JHBUILD_PREFIX:-$HOME/source/jhbuild/install}"
PUTTY_SOURCE="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE_GENERATOR="${APP_BUNDLE_GENERATOR:-$HOME/source/AppBundleGenerator/AppBundleGenerator}"
DEST_DIR="${DEST_DIR:-$HOME/Desktop}"
VERSION="0.82"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  PuTTY macOS Build & Bundle${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Set up environment
export PATH="$JHBUILD_PREFIX/bin:/usr/bin:/bin:/opt/homebrew/bin"
export PKG_CONFIG_PATH="$JHBUILD_PREFIX/lib/pkgconfig:$JHBUILD_PREFIX/share/pkgconfig"
export CC=/usr/bin/clang
export CFLAGS="-I$JHBUILD_PREFIX/include"
export LDFLAGS="-L$JHBUILD_PREFIX/lib"

# Check if cmake is available
if ! command -v cmake &> /dev/null; then
    echo -e "${RED}Error: cmake not found${NC}"
    exit 1
fi

# Build with CMake
echo -e "${YELLOW}Building PuTTY with CMake...${NC}"
cd "$PUTTY_SOURCE"

# Create build directory
rm -rf build_macos
mkdir -p build_macos
cd build_macos

# Configure with CMake
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$JHBUILD_PREFIX" \
    -DCMAKE_PREFIX_PATH="$JHBUILD_PREFIX" \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_C_FLAGS="-I$JHBUILD_PREFIX/include" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$JHBUILD_PREFIX/lib" \
    || {
    echo -e "${RED}CMake configuration failed${NC}"
    cd ..
    echo -e "${YELLOW}Trying alternative build method...${NC}"

    # Fallback: Try using existing Makefiles if they exist
    if [ -f "unix/Makefile.gtk" ]; then
        echo "Using unix/Makefile.gtk..."
        cd unix
        make -f Makefile.gtk
        cd ..
    else
        echo -e "${RED}No working build system found${NC}"
        echo "Please check the PuTTY build documentation"
        exit 1
    fi
}

# Build
echo -e "${YELLOW}Compiling...${NC}"
make -j4 || {
    echo -e "${RED}Build failed${NC}"
    exit 1
}

cd "$PUTTY_SOURCE"

echo -e "${GREEN}✓ Build complete${NC}"
echo ""

# Find built binaries
echo -e "${YELLOW}Locating binaries...${NC}"
PUTTY_BIN=$(find build_macos -name "putty" -type f -perm +111 2>/dev/null | head -1)
PTERM_BIN=$(find build_macos -name "pterm" -type f -perm +111 2>/dev/null | head -1)

if [ -z "$PUTTY_BIN" ]; then
    echo -e "${RED}Error: putty binary not found${NC}"
    exit 1
fi

echo "  putty: $PUTTY_BIN"
echo "  pterm: $PTERM_BIN"
echo ""

# Create app bundles
echo -e "${YELLOW}Creating app bundles...${NC}"

for app in putty pterm; do
    APP_VAR="${app^^}_BIN"
    APP_BIN="${!APP_VAR}"

    if [ -z "$APP_BIN" ] || [ ! -f "$APP_BIN" ]; then
        echo -e "${YELLOW}  Skipping $app (not built)${NC}"
        continue
    fi

    APP_NAME=$(echo $app | sed 's/.*/\u&/')
    BUNDLE_ID="org.tartarus.$app"

    echo "  Creating $APP_NAME.app..."

    "$APP_BUNDLE_GENERATOR" \
        --identifier "$BUNDLE_ID" \
        --version "$VERSION" \
        --category "public.app-category.utilities" \
        --min-os "12.0" \
        --sign "-" \
        --hardened-runtime \
        --allow-dyld-vars \
        --stage-dependencies "$JHBUILD_PREFIX" \
        "$APP_NAME" \
        "$DEST_DIR" \
        "$APP_BIN" || {
        echo -e "${RED}Failed to create $APP_NAME.app${NC}"
        continue
    }

    echo -e "${GREEN}  ✓ $APP_NAME.app created${NC}"
done

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}     Complete!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${BLUE}App bundles:${NC}"
ls -d "$DEST_DIR"/*.app 2>/dev/null | grep -E "(Putty|Pterm)" || echo "  None created"
echo ""
