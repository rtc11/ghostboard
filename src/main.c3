import std::collections::list;
import std::core::log, logger;
import std::io;
import std::math;
import std::os::env;
import std::os::macos::objc, objc;
import std::sort;
import std::thread;
import std::time;
import cg, cf, ct;
import config;
import raylib5;

const int SCREEN_WIDTH = 800;
const int SCREEN_HEIGHT = 600;

const rl::Color COLOR_RED    = { 177, 66, 66, 255 };      // #B14242
const rl::Color COLOR_ORANGE = { 196, 105, 61, 255};      // #C4693D
const rl::Color COLOR_BLUE   = { 74, 139, 139, 255};      // #4A8B8B
const rl::Color COLOR_PURPLE = { 189, 147, 249, 255 };    // #BD93F9
const rl::Color COLOR_GOLD   = { 143, 141, 52, 255 };     // #8f8d34
const rl::Color COLOR_BLACK  = { 22, 24, 26, 245};        // #16181af5
const rl::Color COLOR_GRAY  = { 13, 18, 20, 245};         // #0d1214f5
const rl::Color COLOR_GREEN  = {189, 255, 192, 255};      // #c6ffc0

const rl::Color COLOR_BG         = COLOR_BLACK;
const rl::Color COLOR_BODY       = COLOR_GRAY;
const rl::Color COLOR_TEXT       = COLOR_GREEN;
const rl::Color COLOR_TITLE      = COLOR_GOLD;
const rl::Color COLOR_FOOTER     = COLOR_GOLD;
const rl::Color COLOR_BADGE_LINE = COLOR_GOLD;
const rl::Color COLOR_BADGE_TEXT = COLOR_GREEN;

faultdef EMPTY, REDACTED, MISSING;

bool should_quit;

struct Manager {
    Clipboard cp;
    List{Entry} history;
    usz history_limit;
    Config config;
    int selected_idx;
    bool menu;
    bool show_all_text;
    rl::Vector2 scroll_pos;
    Font font;
}

struct Clipboard {
    ObjcId instance;
    ObjcSelector items_sel;
    ObjcSelector first_obj_sel;
    ObjcSelector types_sel;
}

struct Entry {
    String text;
    TzDateTime timestamp;
    usz hits;
}

fn bool Entry.less(&self, Entry other) => self.hits < other.hits;

fn void main(String[] args)
{
    Config config = {
        .config_dir = ".config/ghostboard",
        .storage_file = "clips",
        .log_file = "logs",
    };

    logger::setup_logging(&config);
    hide_from_dock();
    setup_tray();
    
    rl::setConfigFlags(ConfigFlag.WINDOW_UNDECORATED | ConfigFlag.WINDOW_TRANSPARENT | ConfigFlag.WINDOW_HIGHDPI);
    rl::initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "GhostBoard");

    Manager manager = init(limit: 30, config: config);

    setup_event_tap(&manager);
    manager.loop();
}


fn void hide_from_dock() {
    ObjcId shared_app = objc::msg_send(objc::getClass("NSApplication"), SendVoid, "sharedApplication");
    objc::msg_send(shared_app, SendUsz, "setActivationPolicy:", 1);
    rl::setConfigFlags(ConfigFlag.WINDOW_HIDDEN | ConfigFlag.WINDOW_ALWAYS_RUN);
}

fn void quit_action(ObjcId self, ObjcSelector _cmd, ObjcId sender) {
    should_quit = true;
}

fn void setup_tray() {
    ObjcId system_sbar = objc::msg_send(objc::getClass("NSStatusBar"), SendVoid, "systemStatusBar");
    ObjcId status_item = objc::msg_send(system_sbar, GetId_double, "statusItemWithLength:", -1.0);
    ObjcId button = objc::msg_send(status_item, SendVoid, "button");
    ObjcId icon = generate_tray_icon();
    objc::msg_send(button, SendId, "setImage:", icon);

    // Create menu
    ObjcId menu = objc::msg_send(objc::getClass("NSMenu"), GetId, "alloc");
    menu = objc::msg_send(menu, SendVoid, "init");
    
    // Create custom target class for quit action
    ObjcClass target_class = objc::allocateClassPair(objc::getClass("NSObject"), "GhostBoardQuitTarget", 0);
    objc::class_addMethod(target_class, objc::sel_registerName("quitAction:"), (void*)&quit_action, "v@:@");
    objc::register_class_pair(target_class);
    
    // Create exit menu item
    ObjcId exit_item = objc::msg_send(objc::getClass("NSMenuItem"), GetId, "alloc");
    ObjcId exit_title = to_nsstr("Quit GhostBoard");
    ObjcSelector quit_sel = objc::sel_registerName("quitAction:");
    ObjcId key_equivalent = to_nsstr("q");
    exit_item = objc::msg_send(exit_item, GetId_IdSelId, "initWithTitle:action:keyEquivalent:", exit_title, quit_sel, key_equivalent);
    ObjcId target = objc::msg_send(target_class, SendVoid, "alloc");
    target = objc::msg_send(target, SendVoid, "init");
    objc::msg_send(exit_item, SendId, "setTarget:", target);
    
    // Add item to menu
    objc::msg_send(menu, SendId, "addItem:", exit_item);
    
    // Set menu on status item
    objc::msg_send(status_item, SendId, "setMenu:", menu);
}

fn void setup_event_tap(Manager* manager) {
    log::info("Setting up event tap for global hotkey (Ctrl+Shift+V)...");
    void* tap = cg::eventTapCreate(tap: 0, place: 0, options: 0, mask: (1<<10), callback: &on_key_event, user_info: manager);
    if (tap == null) {
        log::error("Failed to create event tap - Accessibility Permissions required!");
        log::error("Go to System Settings > Privacy & Security > Accessibility");
        log::error("Remove GhostBoard.app, add it back, enable it, then restart.");
        log::error("If already added, try removing and re-adding after code changes.");
        return;
    }
    void* run_loop_source = cf::machPortCreateRunLoopSource(null, tap, 0);
    cf::runLoopAddSource(cf::runLoopGetCurrent(), run_loop_source, cf::RUN_LOOP_COMMON_MODES);
    cg::eventTapEnable(tap, true);
    log::info("Global event tap active! Press Ctrl+Shift+V to open menu.");
}

fn void* on_key_event(void* proxy, int type, void* event, void* refcon) {
    if (type != 10) return event;
    ulong flags = cg::eventGetFlags(event);
    ushort keycode = (ushort)cg::eventGetIntegerValueField(event, 9);
    log::debug("key event - keycode: 0x%x, flags: 0x%x", keycode, flags);
    bool control = (flags & 0x40000) != 0;
    bool shift = (flags & 0x20000) != 0;
    if (control && shift && keycode == 0x09) {
        Manager* manager = (Manager*)refcon;
        if (!manager.menu) {
            log::info("global hotkey detected! enabling menu");
            manager.menu = true;
            manager.show_window();
        }
        return null;
    }
    return event;
}

fn void move_app_to_background() {
    ObjcId shared_app = objc::msg_send(objc::getClass("NSApplication"), SendVoid, "sharedApplication");
    objc::msg_send(shared_app, GetId_Id, "hide:", shared_app);
}

fn Manager init(usz limit = 10, Config config) {
    ObjcClass cls = objc::class_by_name("NSPasteboard")!!;
    Clipboard cp = {
        .instance = objc::msg_send(cls, SendVoid, "generalPasteboard"),
        .items_sel = objc::sel_registerName("pasteboardItems"),
        .first_obj_sel = objc::sel_registerName("firstObject"),
        .types_sel = objc::sel_registerName("types"),
    };
    
    // Try to get bundle resource path
    ObjcId bundle = objc::msg_send(objc::getClass("NSBundle"), SendVoid, "mainBundle");
    ObjcId resource_path = objc::msg_send(bundle, SendVoid, "resourcePath");
    ZString bundle_resources = null;
    if (resource_path != null) {
        bundle_resources = (ZString)objc::msg_send(resource_path, SendVoid, "UTF8String");
    }
    
    Font font;
    if (bundle_resources != null) {
        String font_path = string::tformat("%s/SF-Pro.ttf", bundle_resources);
        log::debug("trying to load font from bundle: %s", font_path);
        font = rl::loadFontEx(font_path.zstr_tcopy(), 64, null, 0);
    } else {
        font.texture.id = 0;
    }
    
    if (font.texture.id == 0) {
        log::debug("failed to load font from bundle, trying resources/SF-Pro.ttf");
        font = rl::loadFontEx("resources/SF-Pro.ttf", 64, null, 0);
        if (font.texture.id == 0) {
            log::warn("failed to load font from resources/SF-Pro.ttf");
        } else {
            log::info("loaded font from resources/SF-Pro.ttf");
        }
    } else {
        log::info("loaded font from bundle");
    }
    
    Manager manager = {
        .cp = cp,
        .history_limit = limit,
        .config = config,
        .font = font,
    };
    manager.load_from_file();
    manager.update();
    rl::setExitKey(rl::KEY_NULL); // disable default ESCAPE to exit
    return manager;
}

fn void Manager.center_window(&self) {
    int monitor = rl::getCurrentMonitor();
    rl::Vector2 size = { (float)rl::getMonitorWidth(monitor), (float)rl::getMonitorHeight(monitor) };
    rl::Vector2 scale = rl::getWindowScaleDPI();
    int x = (int)((size.x / scale.x - SCREEN_WIDTH) / 2f);
    int y = (int)((size.y / scale.y - SCREEN_HEIGHT) / 2f);
    rl::setWindowPosition(x, y);
}

fn void Manager.show_window(&self) {
    // app to foreground
    ObjcId shared_app = objc::msg_send(objc::getClass("NSApplication"), SendVoid, "sharedApplication");
    objc::msg_send(shared_app, SendBool, "activateIgnoringOtherApps:", true);

    self.center_window();
    self.selected_idx = 0;
    self.show_all_text = false;
    self.scroll_pos = {0, 0};  // Reset scroll position
    // Sort by hits (descending - highest first)
    quicksort(&self.history);
    self.history.reverse();
    rl::clearWindowState(WINDOW_HIDDEN);
    rl::setWindowState(WINDOW_TOPMOST);
    rl::restoreWindow();
}

fn void Manager.loop(&self) {
    int last_count = (int)objc::msg_send(self.cp.instance, GetInt, "changeCount");

    while (!rl::windowShouldClose() && !should_quit) {
        if (self.menu && !rl::isWindowFocused()) {
            self.menu = false;
            rl::setWindowState(WINDOW_HIDDEN);
            move_app_to_background();
        }

        int current_count = (int)objc::msg_send(self.cp.instance, GetInt, "changeCount");
        if (current_count != last_count) {
            log::info("new clip detected");
            last_count = current_count;
            thread::sleep(time::ms(50)); // race condition, wait for macos to save its clip first
            self.update();
        }
 
        if (self.menu) {
            if (self.show_all_text) {
                self.show_all_text_view();
            } else {
                self.show_clips();
            }
            self.menu_mode();
        } else {
            rl::pollInputEvents();
            rl::beginDrawing();
            rl::clearBackground(COLOR_BG);
            rl::endDrawing();
        }

        thread::sleep(time::ms(8)); // ~120
    }
    rl::closeWindow();
}

fn void Manager.menu_mode(&self) {
    const int MAX_VISIBLE_ITEMS = 17;
    const int ITEM_SPACING = 30;
    
    if (!self.show_all_text) {
        if (rl::isKeyPressed(rl::KEY_DOWN) || rl::isKeyPressed(rl::KEY_J)) {
            // Clamp at bottom instead of wrapping
            if (self.selected_idx < (int)self.history.len() - 1) {
                self.selected_idx++;
                
                // Auto-scroll when selection moves below visible area
                int scroll_offset = (int)(self.scroll_pos.y / ITEM_SPACING);
                if (self.selected_idx >= scroll_offset + MAX_VISIBLE_ITEMS) {
                    self.scroll_pos.y += ITEM_SPACING;
                }
            }
        }

        if (rl::isKeyPressed(rl::KEY_UP) || rl::isKeyPressed(rl::KEY_K)) {
            // Clamp at top instead of wrapping
            if (self.selected_idx > 0) {
                self.selected_idx--;
                
                // Auto-scroll when selection moves above visible area
                int scroll_offset = (int)(self.scroll_pos.y / ITEM_SPACING);
                if (self.selected_idx < scroll_offset) {
                    self.scroll_pos.y -= ITEM_SPACING;
                }
            }
        }
        
        // Mouse wheel scrolling
        float wheel = rl::getMouseWheelMove();
        if (wheel != 0) {
            self.scroll_pos.y -= wheel * 30.0f;
            // Clamp scroll position
            if (self.scroll_pos.y < 0) self.scroll_pos.y = 0;
            int max_scroll = math::max(0, ((int)self.history.len() - MAX_VISIBLE_ITEMS) * ITEM_SPACING);
            if (self.scroll_pos.y > max_scroll) self.scroll_pos.y = (float)max_scroll;
        }
    }

    if (rl::isKeyPressed(rl::KEY_ESCAPE) || rl::isKeyPressed(rl::KEY_Q)) {
        if (self.show_all_text) {
            self.show_all_text = false;
        } else {
            self.menu = false;
            rl::setWindowState(WINDOW_HIDDEN);
            move_app_to_background();
        }
    }

    if (rl::isKeyPressed(rl::KEY_ENTER)) {
        if (self.history.len() == 0) {
            self.menu = false;
            rl::setWindowState(WINDOW_HIDDEN);
            move_app_to_background();
        }
        // Get the selected entry (now using direct index since history is sorted)
        Entry? selected = self.history.get(self.selected_idx);
        if (try selected) {
            self.cp.set(selected.text);
        } else if (@catch(selected) == REDACTED) {
            self.cp.set("***");
        } 
        self.menu = false;
        rl::setWindowState(WINDOW_HIDDEN);
        move_app_to_background();

        // wait for the os to complete the transition
        thread::sleep(time::ms(50));
        self.simulate_paste();
    }

    if (rl::isKeyPressed(rl::KEY_O)) {
        if (self.history.len() > 0) {
            self.show_all_text = !self.show_all_text;
            self.scroll_pos = {0, 0};
        }
    }

    if (rl::isKeyPressed(rl::KEY_D) || rl::isKeyPressed(rl::KEY_DELETE)) {
        if (!self.show_all_text && self.history.len() > 0) {
            self.remove_selected();
        }
    }

    if (self.show_all_text) {
        float scroll_speed = 20f;
        float hjkl_speed = 15;
        if (rl::isKeyDown(rl::KEY_LEFT)  || rl::isKeyDown(rl::KEY_H)) self.scroll_pos.x -= hjkl_speed;
        if (rl::isKeyDown(rl::KEY_DOWN)  || rl::isKeyDown(rl::KEY_J)) self.scroll_pos.y += hjkl_speed;
        if (rl::isKeyDown(rl::KEY_UP)    || rl::isKeyDown(rl::KEY_K)) self.scroll_pos.y -= hjkl_speed;
        if (rl::isKeyDown(rl::KEY_RIGHT) || rl::isKeyDown(rl::KEY_L)) self.scroll_pos.x += hjkl_speed;
        float wheel = rl::getMouseWheelMove();
        if (wheel != 0) self.scroll_pos.y -= wheel * scroll_speed;
        if (self.scroll_pos.y < 0) self.scroll_pos.y = 0;
        if (self.scroll_pos.x < 0) self.scroll_pos.x = 0;
    }
}

fn void Manager.add(&self, String text) {
    Entry entry = {
        .text = text.copy(mem),
        .timestamp = datetime::now().to_local(),
        .hits = 1,
    };

    self.history.push(entry);
    self.save_to_file();
}

fn void Manager.remove_selected(&self) {
    if (self.history.len() == 0) return;
    
    Entry? entry = self.history.get(self.selected_idx);
    if (catch entry) return;
    self.history.remove_at(self.selected_idx);
    
    entry.text.free(mem);
    
    if (self.history.len() == 0) {
        self.selected_idx = 0;
    } else if (self.selected_idx >= self.history.len()) {
        self.selected_idx = (int)self.history.len() - 1;
    }
    
    self.save_to_file();
    log::info("removed clip at index %d", self.selected_idx);
}

fn bool Manager.update(&self) {
    bool? safe = self.cp.is_safe();
    if (catch safe) {
        log::warn("the clip was missing from last clip on macOS");
        return false;
    }
    if (!safe) {
        log::warn("the clip was concealed.");
        return false;
    }
    Entry? cur = self.cp.get_current_clip();
    if (catch cur) {
        log::error("failed to get the clip as text from macOS");
        return false;
    }
    if (cur.text.len == 0) {
        log::info("did not save empty string");
        return false;
    }

    usz? existing_idx = self.history.findTextIndex(cur.text);
    if (try existing_idx) {
        self.history[existing_idx].hits++;
        log::info("clip already exists, incremented hits to %d", self.history[existing_idx].hits);
        self.save_to_file();
        return false;
    } 

    log::info("new clip saved");
    self.add(cur.text);

    if (self.history.len() > self.history_limit) {
        if (try old = self.history.pop_first()) {
            log::info("removed clipboard history from: %s ago", datetime::now().diff_us(old.timestamp).to_nano());
            old.text.free(mem);
            self.save_to_file();
        }
    }
    return true;
}

fn usz? List{Entry}.findTextIndex(&self, String text) {
    foreach(i, entry: self) {
        if (entry.text == text) return i;
    }
    return MISSING?;
}

fn String Manager.get_storage_path(&self) {
    String? home = env::tget_var("HOME");
    if (catch home) return self.config.storage_file;
    String dir_path = string::tformat("%s/%s", home, self.config.config_dir);
    io::path::mkdir(dir_path, true)!!;
    return string::tformat("%s/%s", dir_path, self.config.storage_file);
}

fn void Manager.save_to_file(&self) {
    String path = self.get_storage_path();
    File? file = file::open(path, "wb");
    if (catch file) {
        log::error("failed to open file for writing: %s", path);
        return;
    }
    defer (void)file.close();
    
    foreach (entry: self.history) {
        Time timestamp = entry.timestamp.time;
        io::write_any(&file, &timestamp)!!;
        int gmt_offset = entry.timestamp.gmt_offset;
        io::write_any(&file, &gmt_offset)!!;
        usz hits = entry.hits;
        io::write_any(&file, &hits)!!;
        usz text_len = entry.text.len;
        io::write_any(&file, &text_len)!!;
        io::write_all(&file, entry.text)!!;
    }
}

fn void Manager.load_from_file(&self) {
    String path = self.get_storage_path();
    File? file = file::open(path, "rb");
    if (catch file) {
        log::info("no existing clipboard history found");
        return;
    }
    defer (void)file.close();
    
    while (!file.eof()) {
        long timestamp;
        if (catch io::read_any(&file, &timestamp)) break;
        
        int gmt_offset;
        if (catch io::read_any(&file, &gmt_offset)) break;
        
        usz hits;
        if (catch io::read_any(&file, &hits)) break;
        
        usz text_len;
        if (catch io::read_any(&file, &text_len)) break;
        
        char[] buffer = mem::alloc_array(char, text_len);
        if (catch io::read_all(&file, buffer)) {
            mem::free(buffer);
            break;
        }
        
        Entry entry = {
            .text = ((String)buffer).copy(mem),
            .timestamp = datetime::from_time_tz((Time)timestamp, gmt_offset),
            .hits = hits,
        };
        self.history.push(entry);
        mem::free(buffer);
    }
    
    log::info("loaded %d clips from storage", self.history.len());
}

fn void draw_rounded_corners(rl::Rectangle rec, rl::Color color) {
    float roundness = 0.5;
    int segments = 12; //  higher is smoother
    rl::drawRectangleRounded(rec, roundness, segments, color);
} 

fn void Manager.show_clips(&self) {
    rl::beginDrawing();
    rl::clearBackground(COLOR_BG);
    rl::setTextureFilter(self.font.texture, BILINEAR);

    // header
    ZString header_txt = "GhostBoard".zstr_tcopy();
    float header_font_size = 24f;
    rl::Vector2 header_size = rl::measureTextEx(self.font, header_txt, header_font_size, 0f);
    float header_x = (SCREEN_WIDTH - header_size.x) / 2f;
    int header_padding = 10;
    int extra_body_space = 80;
    rl::Rectangle header_rec = { 
        header_x - header_padding - extra_body_space / 2f, 
        10 - header_padding / 2f, 
        header_size.x + header_padding * 2f + extra_body_space, 
        header_size.y + header_padding 
    };
    rl::drawRectangleRounded(header_rec, 0.5, 12, COLOR_BODY);
    rl::drawTextEx(self.font, header_txt, {header_x, 10f}, header_font_size, 0f, COLOR_TITLE);
    
    // version number
    ZString version_txt = "v0.1.0".zstr_tcopy();
    float version_font_size = 14f;
    rl::Vector2 version_size = rl::measureTextEx(self.font, version_txt, version_font_size, 0f);
    float version_x = header_x + header_size.x + 8f;
    float version_y = 10f + (header_size.y - version_size.y) / 2f;
    rl::drawTextEx(self.font, version_txt, {version_x, version_y}, version_font_size, 0f, COLOR_FOOTER);

    int spacing = 30;
    int rec_padding = 20;
    int rec_height = 25;
    int rec_width = SCREEN_WIDTH - (rec_padding * 2);

    int max_text_len = 84;
    int font_size = 20;
    int font_padding = 25;
    float font_y_offset = (rec_height - (float)font_size) / 2f;

    float badge_w = 50;
    float badge_h = rec_height;
    float badge_y_offset = (rec_height - (float)badge_h) / 2f;
    int badge_padding = rec_padding - 5;

    // Display clips directly (history is already sorted)
    int visual_idx; 
    foreach (entry : self.history) {
        float y_pos = 50 + ((float)visual_idx * spacing) - self.scroll_pos.y;
        
        // Skip rendering items outside visible area (footer starts at ~570)
        if (y_pos < 45 || y_pos + rec_height > SCREEN_HEIGHT - 40) {
            visual_idx++;
            continue;
        }
        
        bool is_selected = visual_idx == self.selected_idx;

        // rectangle
        rl::Color rec_color = is_selected ? COLOR_BODY : COLOR_BG;
        rl::Rectangle rec = { rec_padding, y_pos, rec_width, rec_height };
        rl::drawRectangleRounded(rec: rec, roundness: 0.5, segments: 12, color: rec_color); 

        // text
        String text = entry.text;
        if(try newline_pos = text.index_of_char('\n')) {
            text = text[..newline_pos];
        }
        if (text.len > max_text_len) {
            text = text[..max_text_len];
        }
        rl::Color text_color = is_selected ? COLOR_TITLE : COLOR_TEXT;
        rl::drawTextEx(self.font, text.zstr_tcopy(), {font_padding, y_pos + font_y_offset}, font_size, 0f, text_color);

        // badge
        float badge_x = (float)rec_padding + rec_width - badge_w;
        float badge_y = (float)y_pos + badge_y_offset;
        ZString count_str = string::tformat_zstr("%d", entry.text.len);
        rl::Color badge_bg = COLOR_BODY;
        rl::Color badge_corner_color = is_selected ? COLOR_BADGE_LINE : COLOR_BODY;
        rl::Rectangle badge_rec = { badge_x, badge_y, badge_w, badge_h };
        rl::drawRectangleRounded(rec: badge_rec, roundness: 0.5, segments: 12, color: badge_bg); 
        rl::drawRectangleRoundedLinesEx(badge_rec, 0.5, 24, 1.0, badge_corner_color);
        rl::Vector2 count_size = rl::measureTextEx(self.font, count_str, 12, 0);
        rl::Vector2 count_pos = {
            badge_x + (badge_w - count_size.x) / 2f,
            badge_y + (badge_h - count_size.y) / 2f,
        };
        rl::drawTextEx(self.font, count_str, count_pos, 14, 0, COLOR_BADGE_TEXT);

        // timestamp footer
        if (is_selected) {
            ZString timestamp = string::tformat_zstr("%s", entry.timestamp);
            rl::Vector2 timestamp_size = rl::measureTextEx(self.font, timestamp, 16, 0);
            float timestamp_x = (SCREEN_WIDTH - timestamp_size.x) - 25;
            rl::drawTextEx(self.font, timestamp, {timestamp_x, SCREEN_HEIGHT - 30f}, 16, 0f, COLOR_FOOTER);
        }

        visual_idx++;
    }

    // footer
    ZString footer = string::tformat_zstr("o: inspect clip       d: delete clip       enter: select clip       q: quit       hjkl: navigate");
    rl::drawTextEx(self.font, footer, {25, SCREEN_HEIGHT - 30f}, 19, 0f, COLOR_FOOTER);
    rl::endDrawing();
}

fn void Manager.show_all_text_view(&self) {
    rl::beginDrawing();
    rl::clearBackground(COLOR_BG);

    Entry? selected = self.history.get(self.selected_idx);

    if (try selected) {
        // header
        String preview = selected.text;
        if (try newline_pos = preview.index_of_char('\n')) {
            preview = preview[..newline_pos];
        }
        int max_text_len = 90;
        if (preview.len > max_text_len) {
            preview = preview[..max_text_len];
        }
        int rec_padding = 20;
        int rec_height = 25;
        int rec_width = SCREEN_WIDTH - (rec_padding * 2);
        int y_pos = 10;
        rl::Rectangle header_rec = { (float)rec_padding, (float)y_pos, (float)rec_width, (float)rec_height};
        rl::drawRectangleRounded(header_rec, 0.5, 12, COLOR_BODY);
        float font_size = 20;
        float font_y_offset = (rec_height - font_size) / 2f;
        rl::drawTextEx(self.font, preview.zstr_tcopy(), {header_rec.x + 10, (float)y_pos + font_y_offset}, font_size, 0f, COLOR_TITLE);
        float badge_w = 50;
        float badge_h = (float)rec_height;
        float badge_x = header_rec.x + header_rec.width - badge_w;
        ZString count_str = string::tformat_zstr("%d", selected.text.len);
        rl::Rectangle badge_rec = { badge_x, (float)y_pos, badge_w, badge_h};
        rl::drawRectangleRounded(badge_rec, 0.5, 12, COLOR_BODY);
        rl::drawRectangleRoundedLinesEx(badge_rec, 0.5, 24, 1f, COLOR_BADGE_LINE);
        rl::Vector2 count_size = rl::measureTextEx(self.font, count_str, 12, 0);
        rl::Vector2 count_pos = {
            badge_x + (badge_w - count_size.x) / 2f,
            (float)y_pos + (badge_h - count_size.y) / 2f,
        };
        rl::drawTextEx(self.font, count_str, count_pos, 14, 0, COLOR_BADGE_TEXT);

        // text area
        rl::Rectangle text_area_rec = { 20, 50, SCREEN_WIDTH - 40, SCREEN_HEIGHT - 80 };
        rl::drawRectangleRounded(text_area_rec, 0.2, 8, COLOR_BODY);
        
        int text_padding = 20;
        rl::Vector2 scale = rl::getWindowScaleDPI();
        rl::beginScissorMode(
            x: (20 + text_padding) * (int)scale.x, 
            y: (50 + text_padding) * (int)scale.y,
            width: (SCREEN_WIDTH - 40 - text_padding * 2) * (int)scale.x,
            height: (SCREEN_HEIGHT - 80 - text_padding * 2) * (int)scale.y,
        );
        rl::Vector2 pos = {
            20 + (float) text_padding - self.scroll_pos.x,
            50 + (float) text_padding - self.scroll_pos.y
        }; 
        rl::drawTextEx(self.font, selected.text.zstr_tcopy(), pos, 18f, 1f, COLOR_TEXT);
        rl::endScissorMode();

        // timestamp
        ZString timestamp = string::tformat_zstr("%s", selected.timestamp);
        rl::Vector2 timestamp_size = rl::measureTextEx(self.font, timestamp, 16, 0);
        float timestamp_x = (SCREEN_WIDTH - timestamp_size.x) - 25;
        rl::drawTextEx(self.font, timestamp, {timestamp_x, SCREEN_HEIGHT - 30f}, 16, 0f, COLOR_FOOTER);

        // footer
        ZString footer = string::tformat_zstr("o: inspect clip       d: delete clip       enter: select clip       q: quit       hjkl: navigate");
        rl::drawTextEx(self.font, footer, {25, SCREEN_HEIGHT - 30f}, 19, 0f, COLOR_FOOTER);

    }
    rl::endDrawing();
}

// Grant your compiled binary Accessibility Permissions in 
// System Settings > Privacy & Security > Accessibility. 
// If you don't do this, the events will be silently ignored.
fn void Manager.simulate_paste(&self) {
    void* source = cg::eventSourceCreate(0);

    void* v_down = cg::eventCreateKeyboardEvent(source, cg::KEY_V, true);
    void* v_up = cg::eventCreateKeyboardEvent(source, cg::KEY_V, false);

    cg::eventSetFlags(v_down, cg::FLAG_CMD_KEY);
    cg::eventSetFlags(v_up, cg::FLAG_CMD_KEY);

    cg::eventPost(0, v_down);
    cg::eventPost(0, v_up);

    cf::release(v_down);
    cf::release(v_up);
    cf::release(source);
}

fn bool? Clipboard.is_safe(&self) {
    @pool() {
        ObjcId items_array = objc::msg_send(self.instance, SendVoid, "pasteboardItems");
        log::debug("pasteboardItems returned: %p", items_array);
        
        if (items_array == null) {
            log::debug("pasteboardItems is null");
            return EMPTY?;
        }
        
        int count = (int)objc::msg_send(items_array, GetInt, "count");
        log::debug("pasteboardItems count: %d", count);
        
        ObjcId item = objc::msg_send(items_array, SendVoid, "firstObject");
        log::debug("firstObject returned: %p", item);
        
        if (item == null) {
            log::debug("firstObject is null, clipboard appears empty");
            return EMPTY?;
        }

        ObjcId types_array = objc::msg_send(item, SendVoid, "types");

        ObjcId concealed_key = to_nsstr("org.nspasteboard.ConcealedType");
        bool concealed = (bool)objc::msg_send(types_array, GetBool_Id, "containsObject:", concealed_key);
        return !concealed;
    };
}

fn Entry? Clipboard.get_current_clip(&self) {
    @pool() {
        ObjcId type_str = to_nsstr("public.utf8-plain-text");
        ObjcId ns_str = objc::msg_send(self.instance, GetId_Id, "stringForType:", type_str);
        if (ns_str == null) return EMPTY?;
        ZString zstr = (ZString)objc::msg_send(ns_str, SendVoid, "UTF8String");
        return {
            .text = zstr.copy(mem),
            .timestamp = datetime::now().to_local(),
        };
    };
}

fn void Clipboard.set(&self, String text) {
    @pool() {
        objc::msg_send(self.instance, SendVoid, "clearContents");
        ObjcId ns_str = to_nsstr(text.zstr_tcopy());
        ObjcId type_str = to_nsstr("public.utf8-plain-text");
        objc::msg_send(self.instance, GetBool_IdId, "setString:forType:", ns_str, type_str);
    };
}


fn ObjcId to_nsstr(ZString str) {
    ObjcClass str_cls = objc::getClass("NSString");
    return objc::msg_send(str_cls, GetId_str, "stringWithUTF8String:", str);
}

fn ObjcId generate_tray_icon() {
    rl::Image icon = rl::genImageColor(22, 22, {0, 0, 0, 0});
    
    rl::Color draw_color = rl::WHITE; 
    int r = 4; 

    rl::imageDrawRectangle(&icon, 4 + r, 6, 14 - (2 * r), 12, draw_color);
    rl::imageDrawRectangle(&icon, 4, 6 + r, 14, 12 - (2 * r), draw_color);
    rl::imageDrawCircle(&icon, 4 + r, 6 + r, r, draw_color);
    rl::imageDrawCircle(&icon, 4 + 14 - r, 6 + r, r, draw_color);
    rl::imageDrawCircle(&icon, 4 + r, 6 + 12 - r, r, draw_color);
    rl::imageDrawCircle(&icon, 4 + 14 - r, 6 + 12 - r, r, draw_color);
    rl::imageDrawCircle(&icon, 8, 10, 2, {0, 0, 0, 0});
    rl::imageDrawCircle(&icon, 14, 10, 2, {0, 0, 0, 0});
    
    ZString icon_path = "/tmp/ghostboard_tray.png";
    rl::exportImage(icon, icon_path);
    
    ObjcId ns_image = objc::msg_send(objc::getClass("NSImage"), GetId, "alloc");
    ns_image = objc::msg_send(ns_image, GetId_Id, "initByReferencingFile:", to_nsstr(icon_path));
    
    objc::msg_send(ns_image, SendBool, "setTemplate:", true);
    
    rl::unloadImage(icon);
    return ns_image;
}

fn usz? DateTime.to_format(&self, Formatter* formatter) @dynamic 
{
    String fmt = "%02d:%02d:%02d";
    return formatter.printf(fmt, self.hour, self.min, self.sec);
}
