#!/bin/bash
set -e

echo "Building icon generator..."

# Compile the icon generator
c3c compile \
    --libdir lib \
    --lib raylib55 \
    --output-dir build \
    -o icon_generator \
    -O2 \
    --macos-min-version 15 \
    --macos-sdk-version 15 \
    scripts/generate_icon.c3

echo "Running icon generator..."
./build/icon_generator

echo ""
echo "Creating .icns file..."
./scripts/create_icns.sh

echo ""
echo "✓ Icon generation complete!"
echo "You can now view the icon at: resources/AppIcon.icns"
