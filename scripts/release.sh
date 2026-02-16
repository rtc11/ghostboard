#!/bin/bash

# Build the project
c3c build

# Set app name
APP_NAME="GhostBoard"
BUNDLE_DIR="build/${APP_NAME}.app"
SIGNING_IDENTITY="GhostBoard Developer"

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

# Code sign the app
echo "Signing the app..."
codesign --force --deep --sign "$SIGNING_IDENTITY" "${BUNDLE_DIR}"

if [ $? -eq 0 ]; then
    echo "✓ App successfully signed with: $SIGNING_IDENTITY"
    codesign -dvvv "${BUNDLE_DIR}" 2>&1 | grep "Authority"
else
    echo "⚠ Warning: Could not sign app. Signature: '$SIGNING_IDENTITY' not found."
    echo "  Run ./scripts/create-cert.sh to create signing certificate."
    echo "  App will still work but Accessibility permissions won't persist across rebuilds."
fi

echo "✓ App bundle created at: ${BUNDLE_DIR}"
echo "✓ You can now run it by double-clicking or: open ${BUNDLE_DIR}"
