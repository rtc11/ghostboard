#!/bin/bash

# This script creates a self-signed code signing certificate for local development

CERT_NAME="GhostBoard Developer"

echo "Creating self-signed code signing certificate..."
echo ""
echo "Follow these steps in Keychain Access:"
echo ""
echo "1. Open 'Keychain Access' app"
echo "2. Menu: Keychain Access → Certificate Assistant → Create a Certificate..."
echo "3. Set these values:"
echo "   - Name: $CERT_NAME"
echo "   - Identity Type: Self-Signed Root"
echo "   - Certificate Type: Code Signing"
echo "   - Check: ✓ Let me override defaults"
echo "4. Click Continue"
echo "5. Keep clicking Continue through the dialogs (accept defaults)"
echo "6. On 'Specify a Location For The Certificate':"
echo "   - Keychain: login"
echo "7. Click Continue, then Done"
echo ""
echo "8. Find the new '$CERT_NAME' certificate in login keychain"
echo "9. Double-click it"
echo "10. Expand 'Trust' section"
echo "11. Set 'Code Signing' to 'Always Trust'"
echo "12. Close (you'll be prompted for password)"
echo ""
echo "After setup, verify with:"
echo "  security find-identity -v -p codesigning"
echo ""
echo "You should see: '$CERT_NAME'"

