// Icon generator for GhostBoard
// Generates high-res PNG icons that can be converted to .icns
module icon_generator;

import raylib5;
import std::io;

fn void main() {
    // Generate multiple sizes for iconset
    int[] sizes = {16, 32, 64, 128, 256, 512, 1024};
    
    foreach (size : sizes) {
        generate_icon(size);
    }
    
    io::printn("Icon generation complete!");
    io::printn("Run: ./scripts/create_icns.sh to create .icns file");
}

fn void generate_icon(int size) {
    rl::initWindow(size, size, "Icon Generator");
    rl::setConfigFlags(ConfigFlag.WINDOW_HIDDEN);
    
    // Create the icon image
    rl::Image icon = rl::genImageColor(size, size, {0, 0, 0, 0});
    
    // Scale factors
    float scale = (float)size / 1024.0f;
    int padding = (int)(80.0f * scale);
    int corner_radius = (int)(120.0f * scale);
    int inner_padding = (int)(100.0f * scale);
    
    // Main clipboard body (rounded rectangle)
    rl::Color body_color = {189, 147, 249, 255}; // COLOR_PURPLE
    rl::Color accent_color = {143, 141, 52, 255}; // COLOR_GOLD
    rl::Color ghost_color = {189, 255, 192, 180}; // COLOR_GREEN with transparency
    
    // Draw main rounded rectangle (clipboard body)
    int body_width = size - (padding * 2);
    int body_height = size - (padding * 2);
    
    // Fill the rounded rectangle manually
    for (int y = padding; y < size - padding; y++) {
        for (int x = padding; x < size - padding; x++) {
            // Calculate distance from corners
            int dx = 0;
            int dy = 0;
            
            if (x < padding + corner_radius) {
                dx = (padding + corner_radius) - x;
            } else if (x > size - padding - corner_radius) {
                dx = x - (size - padding - corner_radius);
            }
            
            if (y < padding + corner_radius) {
                dy = (padding + corner_radius) - y;
            } else if (y > size - padding - corner_radius) {
                dy = y - (size - padding - corner_radius);
            }
            
            int dist_sq = dx * dx + dy * dy;
            int radius_sq = corner_radius * corner_radius;
            
            if (dist_sq <= radius_sq || dx == 0 || dy == 0) {
                rl::imageDrawPixel(&icon, x, y, body_color);
            }
        }
    }
    
    // Draw clip at top (accent)
    int clip_width = (int)(200.0f * scale);
    int clip_height = (int)(80.0f * scale);
    int clip_x = (size - clip_width) / 2;
    int clip_y = padding - clip_height / 2;
    int clip_corner = (int)(15.0f * scale);
    
    rl::imageDrawRectangle(&icon, clip_x + clip_corner, clip_y, clip_width - (2 * clip_corner), clip_height, accent_color);
    rl::imageDrawRectangle(&icon, clip_x, clip_y + clip_corner, clip_width, clip_height - (2 * clip_corner), accent_color);
    rl::imageDrawCircle(&icon, clip_x + clip_corner, clip_y + clip_corner, clip_corner, accent_color);
    rl::imageDrawCircle(&icon, clip_x + clip_width - clip_corner, clip_y + clip_corner, clip_corner, accent_color);
    rl::imageDrawCircle(&icon, clip_x + clip_corner, clip_y + clip_height - clip_corner, clip_corner, accent_color);
    rl::imageDrawCircle(&icon, clip_x + clip_width - clip_corner, clip_y + clip_height - clip_corner, clip_corner, accent_color);
    
    // Draw ghost effect - two "floating" circles
    int ghost_size = (int)(60.0f * scale);
    int ghost1_x = (int)((float)size * 0.35f);
    int ghost1_y = (int)((float)size * 0.45f);
    int ghost2_x = (int)((float)size * 0.55f);
    int ghost2_y = (int)((float)size * 0.60f);
    
    rl::imageDrawCircle(&icon, ghost1_x, ghost1_y, ghost_size, ghost_color);
    rl::imageDrawCircle(&icon, ghost2_x, ghost2_y, (int)(ghost_size * 0.7f), ghost_color);
    
    // Draw small highlight circle (makes it look more "ghost-like")
    rl::Color highlight = {255, 255, 255, 100};
    rl::imageDrawCircle(&icon, ghost1_x - ghost_size/3, ghost1_y - ghost_size/3, ghost_size/4, highlight);
    
    // Export the icon
    ZString filename = string::tformat("resources/icon_%dx%d.png", size, size).zstr_tcopy();
    rl::exportImage(icon, filename);
    rl::unloadImage(icon);
    rl::closeWindow();
    
    io::printfn("Generated: %s", filename);
}
