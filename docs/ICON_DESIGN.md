# GhostBoard Icon Design

## Concept

The GhostBoard icon represents a clipboard with a "ghost" (transparent/ephemeral) theme, symbolizing:
- 📋 Clipboard functionality
- 👻 Ghost-like (runs in background, appears when needed)
- 🎨 Modern, minimal aesthetic

## Design Elements

### Main Shape
- Rounded rectangle (clipboard body)
- Color: Purple (#BD93F9) - matches app theme
- Rounded corners for modern look

### Accent (Clip)
- Gold (#8F8D34) clip at top
- Represents physical clipboard clip
- Provides visual hierarchy

### Ghost Effect
- Semi-transparent green circles (#BDFFC0)
- Floating/overlapping to suggest transparency
- Subtle white highlight for depth

## Sizes Generated

The icon is generated at multiple sizes for macOS:
- 16x16 (menu bar, list views)
- 32x32 (small icons)
- 64x64 (medium icons)
- 128x128 (large icons)
- 256x256 (very large icons)
- 512x512 (retina displays)
- 1024x1024 (App Store, high-res)

## Color Palette

```
Body:      #BD93F9 (Purple) - COLOR_PURPLE
Accent:    #8F8D34 (Gold)   - COLOR_GOLD  
Ghost:     #BDFFC0 (Green)  - COLOR_GREEN with alpha 180
Highlight: #FFFFFF (White)  - alpha 100
```

## Building the Icon

```bash
# Generate all icon sizes and create .icns file
./scripts/build_icon.sh
```

This will:
1. Compile the icon generator (C3 + raylib)
2. Generate PNG files at all required sizes
3. Create AppIcon.iconset with proper naming
4. Convert to AppIcon.icns using iconutil
5. Place final icon in resources/

## Customizing

To customize the icon, edit `scripts/generate_icon.c3`:

- **Colors**: Change `body_color`, `accent_color`, `ghost_color`
- **Size ratios**: Adjust scale factors for padding, corners
- **Ghost effect**: Modify circle positions and sizes
- **Shape**: Change the drawing logic for different designs

## Using the Icon

After generating, update `project.json`:

```json
"targets": {
  "ghostboard": {
    "target": "macos-aarch64",
    "type": "executable",
    "macos-bundle": {
      "icon": "resources/AppIcon.icns",
      "identifier": "com.ghostboard.app",
      "name": "GhostBoard",
      "version": "0.1.0"
    },
    ...
  }
}
```

Then rebuild:
```bash
c3c build
```

The icon will appear:
- In Finder when viewing the .app
- In the Dock when the app is running
- In Spotlight search results
- In the Applications folder

## ASCII Preview

```
     ╔═══════╗
     ║ CLIP  ║
     ╚═══════╝
   ╭─────────────╮
   │             │
   │    ◉  ◉     │  ← Ghost circles
   │      ◉      │
   │             │
   ╰─────────────╯
```

## Alternative Designs

If you want a different look, consider:

1. **Minimalist**: Just the clipboard outline
2. **Stack**: Multiple clipboard layers (history)
3. **Number badge**: Show quicklist slots (1-9)
4. **Keyboard**: Show Ctrl+Shift+V keys
5. **Ghost mascot**: Actual ghost character

Edit `generate_icon.c3` to implement these ideas!
