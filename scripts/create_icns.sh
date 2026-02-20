#!/bin/bash
set -e

echo "Creating macOS icon set..."

# Create iconset directory
rm -rf AppIcon.iconset
mkdir -p AppIcon.iconset

# Copy generated icons to iconset with proper naming
cp resources/icon_16x16.png AppIcon.iconset/icon_16x16.png
cp resources/icon_32x32.png AppIcon.iconset/icon_16x16@2x.png
cp resources/icon_32x32.png AppIcon.iconset/icon_32x32.png
cp resources/icon_64x64.png AppIcon.iconset/icon_32x32@2x.png
cp resources/icon_128x128.png AppIcon.iconset/icon_128x128.png
cp resources/icon_256x256.png AppIcon.iconset/icon_128x128@2x.png
cp resources/icon_256x256.png AppIcon.iconset/icon_256x256.png
cp resources/icon_512x512.png AppIcon.iconset/icon_256x256@2x.png
cp resources/icon_512x512.png AppIcon.iconset/icon_512x512.png
cp resources/icon_1024x1024.png AppIcon.iconset/icon_512x512@2x.png

# Convert to .icns
echo "Converting to .icns..."
iconutil -c icns AppIcon.iconset -o resources/AppIcon.icns

# Clean up
rm -rf AppIcon.iconset

echo "✓ Created resources/AppIcon.icns"
echo ""
echo "Next steps:"
echo "1. Update project.json to include the icon"
echo "2. Rebuild your app"
echo ""
echo "Add this to your project.json targets.ghostboard:"
echo '  "macos-bundle": {'
echo '    "icon": "resources/AppIcon.icns",'
echo '    "identifier": "com.ghostboard.app",'
echo '    "name": "GhostBoard"'
echo '  }'
