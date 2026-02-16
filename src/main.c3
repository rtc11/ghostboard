import std::io;
import std::time;
import std::thread;
import std::collections::list;
import std::os::macos::objc;
import std::os::env;
import cg, cf, ct;
import raylib5;

alias IdFnFloat            = fn ObjcId(ObjcId, ObjcSelector, float);
alias IdFnDouble           = fn ObjcId(ObjcId, ObjcSelector, double);
alias IdFnIdId             = fn ObjcId(ObjcId, ObjcSelector, ObjcId, ObjcId);
alias GetInt               = fn int   (ObjcId, ObjcSelector);
alias GetId                = fn ObjcId(ObjcId, ObjcSelector);
alias SendIdForId          = fn ObjcId(ObjcId, ObjcSelector, ObjcId);
alias SendId               = fn void  (ObjcId, ObjcSelector, ObjcId);
alias SendIntForId         = fn ObjcId(ObjcId, ObjcSelector, int);
alias SendStringForId      = fn ObjcId(ObjcId, ObjcSelector, ZString);
alias SendIdForBool        = fn bool  (ObjcId, ObjcSelector, ObjcId);
alias StatusItemWithLength = fn ObjcId(ObjcId, ObjcSelector, double);
alias SendBool             = fn void  (ObjcId, ObjcSelector, bool);
alias SendTwoStrings       = fn void  (ObjcId, ObjcSelector, ZString, ZString);
alias SendIdIdForBool      = fn bool  (ObjcId, ObjcSelector, ObjcId, ObjcId);
alias SetPolicy            = fn void  (ObjcId, ObjcSelector, usz);
alias SendAction           = fn bool  (ObjcId, ObjcSelector, ObjcSelector, ObjcId, ObjcId);

const int SCREEN_WIDTH = 800;
const int SCREEN_HEIGHT = 600;

const rl::Color COLOR_RED    = { 177, 66, 66, 255 };      // #B14242
const rl::Color COLOR_ORANGE = { 196, 105, 61, 255};      //#C4693D
const rl::Color COLOR_BLUE   = { 74, 139, 139, 255};      //#4A8B8B
const rl::Color COLOR_PURPLE = { 189, 147, 249, 255 };    //#BD93F9
const rl::Color COLOR_GOLD   = { 143, 141, 52, 255 };     //#8f8d34
const rl::Color COLOR_BLACK  = { 22, 24, 26, 245};        // #16181af5
const rl::Color COLOR_GRAY  = { 13, 18, 20, 245};         // #0d1214f5
const rl::Color COLOR_GREEN  = {189, 255, 192, 255};      //#c6ffc0

const rl::Color COLOR_BG         = COLOR_BLACK;
const rl::Color COLOR_BODY       = COLOR_GRAY;
const rl::Color COLOR_TEXT       = COLOR_GREEN;
const rl::Color COLOR_TITLE      = COLOR_GOLD;
const rl::Color COLOR_FOOTER     = COLOR_GOLD;
const rl::Color COLOR_BADGE_LINE = COLOR_GOLD;
const rl::Color COLOR_BADGE_TEXT = COLOR_GREEN;

const String STORAGE_DIR = ".config/ghostboard";
const String STORAGE_FILE = "clips";

faultdef EMPTY, REDACTED;

struct Manager {
    Clipboard cp;
    List{Entry} history;
    usz history_limit;
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
}

// Grant your terminal and/or binary Accessibility Permissions in 
// System Settings > Privacy & Security > Accessibility. 
fn void main(String[] args)
{
    hide_from_dock();
    setup_tray();
    
    rl::setConfigFlags(ConfigFlag.WINDOW_UNDECORATED | ConfigFlag.WINDOW_TRANSPARENT | ConfigFlag.WINDOW_HIGHDPI);
    rl::initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "GhostBoard");

    Manager manager = init(limit: 20);

    setup_event_tap(&manager);
    manager.loop();
}

fn void hide_from_dock() {
    ObjcId shared_app = objc::msg_send(objc::getClass("NSApplication"), SendVoid, "sharedApplication");
    objc::msg_send(shared_app, SetPolicy, "setActivationPolicy:", 1);
    rl::setConfigFlags(ConfigFlag.WINDOW_HIDDEN | ConfigFlag.WINDOW_ALWAYS_RUN);
}

fn void setup_tray() {
    ObjcId system_sbar = objc::msg_send(objc::getClass("NSStatusBar"), SendVoid, "systemStatusBar");
    ObjcId status_item = objc::msg_send(system_sbar, StatusItemWithLength, "statusItemWithLength:", -1.0);
    ObjcId button = objc::msg_send(status_item, SendVoid, "button");
    ObjcId icon = generate_tray_icon();
    objc::msg_send(button, SendId, "setImage:", icon);
}

fn void setup_event_tap(Manager* manager) {
    ulong mask = (1 << 10);
    void* tap = cg::eventTapCreate(0, 0, 0, mask, &on_key_event, manager);
    if (tap == null) {
        io::printfn("failed to create event tap. check Accessibility Permissions!");
        return;
    }
    void* run_loop_source = cf::machPortCreateRunLoopSource(null, tap, 0);
    cf::runLoopAddSource(cf::runLoopGetCurrent(), run_loop_source, cf::RUN_LOOP_COMMON_MODES);
    cg::eventTapEnable(tap, true);
    io::printfn("global event tap active.");
}

fn void* on_key_event(void* proxy, int type, void* event, void* refcon) {
    if (type != 10) return event;
    ulong flags = cg::eventGetFlags(event);
    ushort keycode = (ushort)cg::eventGetIntegerValueField(event, 9);
    // io::printfn("key pressed event detected: %s", keycode);
    bool control = (flags & 0x40000) != 0;
    bool shift = (flags & 0x20000) != 0;
    if (control && shift && keycode == 0x09) {
        Manager* manager = (Manager*)refcon;
        if (!manager.menu) {
            io::printfn("global hotkey detected! enabling menu");
            manager.menu = true;
            manager.show_window();
        }
        return null;
    }
    return event;
}

fn void move_app_to_background() {
    ObjcId shared_app = objc::msg_send(objc::getClass("NSApplication"), SendVoid, "sharedApplication");
    objc::msg_send(shared_app, SendIdForId, "hide:", shared_app);
}

fn Manager init(usz limit = 10) {
    ObjcClass cls = objc::class_by_name("NSPasteboard")!!;
    Clipboard cp = {
        .instance = objc::msg_send(cls, SendVoid, "generalPasteboard"),
        .items_sel = objc::sel_registerName("pasteboardItems"),
        .first_obj_sel = objc::sel_registerName("firstObject"),
        .types_sel = objc::sel_registerName("types"),
    };
    Manager manager = {
        .cp = cp,
        .history_limit = limit,
        .font = rl::loadFontEx("resources/SF-Pro.ttf", 64, null, 0),
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
    rl::clearWindowState(WINDOW_HIDDEN);
    rl::setWindowState(WINDOW_TOPMOST);
    rl::restoreWindow();
}

fn void Manager.loop(&self) {
    int last_count = (int)objc::msg_send(self.cp.instance, GetInt, "changeCount");

    while (!rl::windowShouldClose()) {
        if (self.menu && !rl::isWindowFocused()) {
            self.menu = false;
            rl::setWindowState(WINDOW_HIDDEN);
            move_app_to_background();
        }

        int current_count = (int)objc::msg_send(self.cp.instance, GetInt, "changeCount");
        if (current_count != last_count) {
            io::printfn("new clip detected, storing..");
            last_count = current_count;
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
    if (!self.show_all_text) {
        if (rl::isKeyPressed(rl::KEY_DOWN) || rl::isKeyPressed(rl::KEY_J)) {
            self.selected_idx = (self.selected_idx + 1) % (int)self.history.len();
        }

        if (rl::isKeyPressed(rl::KEY_UP) || rl::isKeyPressed(rl::KEY_K)) {
            self.selected_idx = (self.selected_idx - 1 + (int)self.history.len()) % (int)self.history.len();
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
        usz reversed_idx = self.history.len() - 1 - self.selected_idx;
        Entry? selected = self.history.get(reversed_idx);
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
    };

    self.history.push(entry);
    self.save_to_file();
}

fn void Manager.remove_selected(&self) {
    if (self.history.len() == 0) return;
    
    usz reversed_idx = self.history.len() - 1 - self.selected_idx;
    Entry? entry = self.history.get(reversed_idx);
    if (catch entry) return;
    self.history.remove_at(reversed_idx);
    
    entry.text.free(mem);
    
    if (self.history.len() == 0) {
        self.selected_idx = 0;
    } else if (self.selected_idx >= self.history.len()) {
        self.selected_idx = (int)self.history.len() - 1;
    }
    
    self.save_to_file();
    io::printfn("removed clip at index %d", reversed_idx);
}

fn bool Manager.update(&self) {
    bool? safe = self.cp.is_safe();
    if (catch safe) return false;
    if (!safe) return false;
    Entry? cur = self.cp.get_current_clip();
    if (catch cur) return false;
    if (cur.text.len == 0) return false;
    if (try last = self.history.last()) {
        if (cur.text == last.text) return false;
    }

    self.add(cur.text);

    if (self.history.len() > self.history_limit) {
        if (try old = self.history.pop_first()) {
            io::printfn("removed clipboard history from: %s ago", datetime::now().diff_us(old.timestamp).to_nano());
            old.text.free(mem);
            self.save_to_file();
        }
    }
    return true;
}

fn String Manager.get_storage_path(&self) {
    String? home = env::tget_var("HOME");
    if (catch home) return STORAGE_FILE;
    String dir_path = string::tformat("%s/%s", home, STORAGE_DIR);
    io::path::mkdir(dir_path, true)!!;
    return string::tformat("%s/%s", dir_path, STORAGE_FILE);
}

fn void Manager.save_to_file(&self) {
    String path = self.get_storage_path();
    File? file = file::open(path, "wb");
    if (catch file) {
        io::printfn("failed to open file for writing: %s", path);
        return;
    }
    defer (void)file.close();
    
    foreach (entry: self.history) {
        Time timestamp = entry.timestamp.time;
        io::write_any(&file, &timestamp)!!;
        int gmt_offset = entry.timestamp.gmt_offset;
        io::write_any(&file, &gmt_offset)!!;
        usz text_len = entry.text.len;
        io::write_any(&file, &text_len)!!;
        io::write_all(&file, entry.text)!!;
    }
}

fn void Manager.load_from_file(&self) {
    String path = self.get_storage_path();
    File? file = file::open(path, "rb");
    if (catch file) {
        io::printfn("no existing clipboard history found");
        return;
    }
    defer (void)file.close();
    
    while (!file.eof()) {
        long timestamp;
        if (catch io::read_any(&file, &timestamp)) break;
        
        int gmt_offset;
        if (catch io::read_any(&file, &gmt_offset)) break;
        
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
        };
        self.history.push(entry);
        mem::free(buffer);
    }
    
    io::printfn("loaded %d clips from storage", self.history.len());
}

fn void draw_rounded_corners(rl::Rectangle rec, rl::Color color) {
    float roundness = 0.5;
    int segments = 12; //  higher is smoother
    rl::drawRectangleRounded(rec, roundness, segments, color); } 

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
    rl::Rectangle header_rec = { 
        header_x - header_padding, 
        10 - header_padding / 2f, 
        header_size.x + header_padding * 2f, 
        header_size.y + header_padding 
    };
    rl::drawRectangleRounded(header_rec, 0.5, 12, COLOR_BODY);
    rl::drawTextEx(self.font, header_txt, {header_x, 10f}, header_font_size, 0f, COLOR_TITLE);

    int spacing = 30;
    int rec_padding = 20;
    int rec_height = 25;
    int rec_width = SCREEN_WIDTH - (rec_padding * 2);

    int max_text_len = 90;
    int font_size = 20;
    int font_padding = 25;
    float font_y_offset = (rec_height - (float)font_size) / 2f;

    float badge_w = 50;
    float badge_h = rec_height;
    float badge_y_offset = (rec_height - (float)badge_h) / 2f;
    int badge_padding = rec_padding - 5;

    // the index is still the same even if we reverse the iter.
    int visual_idx; 
    foreach_r (entry: self.history) {
        int y_pos = 50 + (visual_idx * spacing);
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

    usz reversed_idx = self.history.len() - 1 - self.selected_idx;
    Entry? selected = self.history.get(reversed_idx);

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
        ObjcId item = objc::msg_send(items_array, SendVoid, "firstObject");
        if (item == null) return EMPTY?;

        ObjcId types_array = objc::msg_send(item, SendVoid, "types");

        ObjcId concealed_key = to_nsstr("org.nspasteboard.ConcealedType");
        bool concealed = (bool)objc::msg_send(types_array, SendIdForBool, "containsObject:", concealed_key);
        return !concealed;
    };
}

fn Entry? Clipboard.get_current_clip(&self) {
    @pool() {
        ObjcId type_str = to_nsstr("public.utf8-plain-text");
        ObjcId ns_str = objc::msg_send(self.instance, SendIdForId, "stringForType:", type_str);
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
        objc::msg_send(self.instance, SendIdIdForBool, "setString:forType:", ns_str, type_str);
    };
}

fn ObjcId to_nsstr(ZString str) {
    ObjcClass str_cls = objc::getClass("NSString");
    return objc::msg_send(str_cls, SendStringForId, "stringWithUTF8String:", str);
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
    ns_image = objc::msg_send(ns_image, SendIdForId, "initByReferencingFile:", to_nsstr(icon_path));
    
    objc::msg_send(ns_image, SendBool, "setTemplate:", true);
    
    rl::unloadImage(icon);
    return ns_image;
}

fn usz? DateTime.to_format(&self, Formatter* formatter) @dynamic 
{
    String fmt = "%02d:%02d:%02d";
    return formatter.printf(fmt, self.hour, self.min, self.sec);
}
