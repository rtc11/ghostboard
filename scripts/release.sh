#!/bin/bash

# Build the project
c3c build

# Set app name
APP_NAME="GhostBoard"
BUNDLE_DIR="build/${APP_NAME}.app"

# Remove old bundle if it exists
rm -rf "${BUNDLE_DIR}"

# Create .app bundle structure
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

# Copy executable
cp build/ghostboard "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"

# Copy resources
cp -r resources/* "${BUNDLE_DIR}/Contents/Resources/"

# Create Info.plist
cat > "${BUNDLE_DIR}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.rtc11.ghostboard</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "✓ App bundle created at: ${BUNDLE_DIR}"
echo "✓ You can now run it by double-clicking or: open ${BUNDLE_DIR}"
