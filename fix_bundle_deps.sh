#!/bin/bash
# fix_bundle_deps.sh - Fix up missing dependencies in app bundles
# This script copies missing transitive dependencies that AppBundleGenerator missed

set -e

BUNDLE_PATH="$1"
JHBUILD_PREFIX="${JHBUILD_PREFIX:-$HOME/source/jhbuild/install}"

if [ -z "$BUNDLE_PATH" ] || [ ! -d "$BUNDLE_PATH" ]; then
    echo "Usage: $0 <path-to-app-bundle>"
    echo "Example: $0 ~/Desktop/Putty.app"
    exit 1
fi

LIB_DIR="$BUNDLE_PATH/Contents/Resources/lib"

if [ ! -d "$LIB_DIR" ]; then
    echo "Error: $LIB_DIR not found"
    exit 1
fi

echo "Fixing dependencies for: $BUNDLE_PATH"
echo "Using jhbuild prefix: $JHBUILD_PREFIX"

# Function to copy a library and its dependencies recursively
copy_lib_recursive() {
    local lib_name="$1"
    local source_path="$JHBUILD_PREFIX/lib/$lib_name"
    local dest_path="$LIB_DIR/$lib_name"

    # Skip if already copied
    if [ -f "$dest_path" ]; then
        return
    fi

    # Check if source exists
    if [ ! -f "$source_path" ]; then
        echo "Warning: $source_path not found, skipping"
        return
    fi

    echo "  Copying $lib_name"
    cp "$source_path" "$dest_path"
    chmod 755 "$dest_path"
}

# Scan all libraries in the bundle and find missing dependencies
echo "Scanning for missing dependencies..."
MISSING_LIBS=()

for lib in "$LIB_DIR"/*.dylib; do
    if [ ! -f "$lib" ]; then
        continue
    fi

    # Get dependencies of this library
    DEPS=$(otool -L "$lib" 2>/dev/null | grep -E "@rpath|$JHBUILD_PREFIX" | awk '{print $1}' | sed 's/@rpath\///')

    for dep in $DEPS; do
        # Extract just the library name
        dep_name=$(basename "$dep")

        # Check if it exists in the bundle
        if [ ! -f "$LIB_DIR/$dep_name" ] && [[ "$dep_name" == lib*.dylib ]]; then
            # Add to missing list if not already there
            if [[ ! " ${MISSING_LIBS[@]} " =~ " ${dep_name} " ]]; then
                MISSING_LIBS+=("$dep_name")
            fi
        fi
    done
done

if [ ${#MISSING_LIBS[@]} -eq 0 ]; then
    echo "No missing dependencies found!"
    exit 0
fi

echo "Found ${#MISSING_LIBS[@]} missing libraries"

# Copy missing libraries
for lib in "${MISSING_LIBS[@]}"; do
    copy_lib_recursive "$lib"
done

echo "Done! Fixed dependencies in $BUNDLE_PATH"
