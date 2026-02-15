module c3lipboard;

import std::io;
import std::time;
import std::thread;
import std::collections::list;
import std::os::macos::objc;
import cg, cf, ct;
import raylib5;

// TODO: newest clip first
// TODO: smaller clearer font

alias IdFnFloat = fn ObjcId(ObjcId, ObjcSelector, float);
alias IdFnDouble = fn ObjcId(ObjcId, ObjcSelector, double);
alias IdFnIdId = fn ObjcId(ObjcId, ObjcSelector, ObjcId, ObjcId);
alias GetInt = fn int(ObjcId, ObjcSelector);
alias SendIdForId = fn ObjcId(ObjcId, ObjcSelector, ObjcId);
alias SendIntForId = fn ObjcId(ObjcId, ObjcSelector, int);
alias SendStringForId = fn ObjcId(ObjcId, ObjcSelector, ZString);
alias SendIdForBool = fn bool(ObjcId, ObjcSelector, ObjcId);
alias StatusItemWithLength = fn ObjcId(ObjcId, ObjcSelector, double);
alias SendBool = fn void(ObjcId, ObjcSelector, bool);
alias SendTwoStrings = fn void(ObjcId, ObjcSelector, ZString, ZString);
alias SendIdIdForBool = fn bool(ObjcId, ObjcSelector, ObjcId, ObjcId);
alias SetPolicy = fn void(ObjcId, ObjcSelector, usz);
alias SendAction = fn bool(ObjcId, ObjcSelector, ObjcSelector, ObjcId, ObjcId);

const int SCREEN_WIDTH = 800;
const int SCREEN_HEIGHT = 600;
const rl::Color BG = { 20, 28, 33, 240};
const rl::Color TEXT = {190, 210, 66, 200};
const rl::Color BODY = { 13, 18, 20, 240};

struct Manager {
    Clipboard cp;
    List{Entry} history;
    usz history_limit;
    int selected_idx;
    bool menu;
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
    Time timestamp;
}

// Grant your terminal and/or binary Accessibility Permissions in 
// System Settings > Privacy & Security > Accessibility. 
fn void main(String[] args)
{
    hide_from_dock();
    setup_tray();
    
    rl::setConfigFlags(ConfigFlag.WINDOW_UNDECORATED | ConfigFlag.WINDOW_TRANSPARENT);
    rl::initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "c3lipboard");

    Manager manager = init(limit: 10);

    setup_event_tap(&manager);
    manager.loop();
}

fn void setup_tray() {
    ObjcId system_sbar = objc::msg_send(objc::getClass("NSStatusBar"), SendVoid, "systemStatusBar");
    ObjcId status_item = objc::msg_send(system_sbar, StatusItemWithLength, "statusItemWithLength:", -1.0);
    ObjcId button = objc::msg_send(status_item, SendVoid, "button");
    objc::msg_send(button, SendIdForId, "setTitle:", to_nsstr("📋"));
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

fn void Manager.print(&self) {
    io::printfn("hello from manager");
}

fn void Manager.show_window(&self) {

    // app to foreground
    ObjcId shared_app = objc::msg_send(objc::getClass("NSApplication"), SendVoid, "sharedApplication");
    objc::msg_send(shared_app, SendBool, "activateIgnoringOtherApps:", true);

    rl::clearWindowState(WINDOW_HIDDEN);
    rl::setWindowState(WINDOW_TOPMOST);
    rl::restoreWindow();
    rl::setWindowPosition(500, 300);
}

fn void Manager.loop(&self) {
    int last_count = (int)objc::msg_send(self.cp.instance, GetInt, "changeCount");

    while (!rl::windowShouldClose()) {
        if (self.menu && rl::isWindowFocused() == false) {
            self.menu = false;
            rl::setWindowState(WINDOW_HIDDEN);
        }

        int current_count = (int)objc::msg_send(self.cp.instance, GetInt, "changeCount");
        if (current_count != last_count) {
            last_count = current_count;
            if(self.update()) {
                io::printfn("[%d] history size: %d", current_count, self.history.len());
            }
        }
 
        if (self.menu) {
            self.show_clips();
            self.menu_mode();
        } else {
            rl::beginDrawing();
            rl::clearBackground(BG);
            rl::endDrawing();
        }

        thread::sleep(time::ms(16)); // ~60fps
    }
    rl::closeWindow();
}

fn void hide_from_dock() {
    ObjcId shared_app = objc::msg_send(objc::getClass("NSApplication"), SendVoid, "sharedApplication");
    objc::msg_send(shared_app, SetPolicy, "setActivationPolicy:", 1);
    rl::setConfigFlags(ConfigFlag.WINDOW_HIDDEN | ConfigFlag.WINDOW_ALWAYS_RUN);
}

fn void Manager.menu_mode(&self) {
    if (rl::isKeyPressed(rl::KEY_DOWN) || rl::isKeyPressed(rl::KEY_J)) {
        self.selected_idx = (self.selected_idx + 1) % (int)self.history.len();
    }
    if (rl::isKeyPressed(rl::KEY_UP) || rl::isKeyPressed(rl::KEY_K)) {
        self.selected_idx = (self.selected_idx - 1 + (int)self.history.len()) % (int)self.history.len();
    }
    if (rl::isKeyPressed(rl::KEY_ESCAPE) || rl::isKeyPressed(rl::KEY_Q)) {
        self.menu = false;
        rl::setWindowState(WINDOW_HIDDEN);
        hide_app_completely();
    }
    if (rl::isKeyPressed(rl::KEY_ENTER)) {
        if (self.history.len() == 0) {
            self.menu = false;
            rl::setWindowState(WINDOW_HIDDEN);
            hide_app_completely();
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
        hide_app_completely();

        // wait for the os to copmlete the transition
        thread::sleep(time::ms(50));
        self.simulate_paste();
    }
}

fn void hide_app_completely() {
    ObjcId shared_app = objc::msg_send(objc::getClass("NSApplication"), SendVoid, "sharedApplication");
    objc::msg_send(shared_app, SendIdForId, "hide:", shared_app);
}

faultdef EMPTY, REDACTED;

fn Entry? Clipboard.current(&self) {

    if (try safe = self.is_safe()) {
        if (!safe) {
            return {
                .text = "***",
                .timestamp = time::now(),
            };
        }

        if (try clip = self.get_current_clip()) {
            return clip;
        }
    }
    return EMPTY?;
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

fn ObjcId to_nsstr(ZString str) {
    ObjcClass str_cls = objc::getClass("NSString");
    return objc::msg_send(str_cls, SendStringForId, "stringWithUTF8String:", str);
}

fn Entry? Clipboard.get_current_clip(&self) {
    @pool() {
        ObjcId type_str = to_nsstr("public.utf8-plain-text");
        ObjcId ns_str = objc::msg_send(self.instance, SendIdForId, "stringForType:", type_str);
        if (ns_str == null) return EMPTY?;
        ZString zstr = (ZString)objc::msg_send(ns_str, SendVoid, "UTF8String");
        return {
            .text = zstr.copy(mem),
            .timestamp = time::now(),
        };
    };
}

fn void Manager.add(&self, String text) {
    Entry entry = {
        .text = text.copy(mem),
        .timestamp = time::now(),
    };

    self.history.push(entry);
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
            io::printfn("removed clipboard history from: %s ago", time::now().diff_us(old.timestamp).to_nano());
            old.text.free(mem);
        }
    }
    return true;
}

fn void Clipboard.set(&self, String text) {
    @pool() {
        objc::msg_send(self.instance, SendVoid, "clearContents");
        ObjcId ns_str = to_nsstr(text.zstr_tcopy());
        ObjcId type_str = to_nsstr("public.utf8-plain-text");
        objc::msg_send(self.instance, SendIdIdForBool, "setString:forType:", ns_str, type_str);
    };
}

fn void Manager.show_clips(&self) {
    rl::beginDrawing();
    rl::clearBackground(BG);
    rl::setTextureFilter(self.font.texture, BILINEAR);

    // header
    ZString header_txt = "GhostBoard".zstr_tcopy();
    float header_font_size = 24f;
    rl::Vector2 header_size = rl::measureTextEx(self.font, header_txt, header_font_size, 0f);
    float header_x = (SCREEN_WIDTH - header_size.x) / 2f; 
    rl::drawTextEx(self.font, header_txt, {header_x, 10f}, header_font_size, 0f, TEXT);

    int spacing = 30;
    int rec_padding = 20;
    int rec_height = 25;
    int rec_width = SCREEN_WIDTH - (rec_padding * 2);

    int max_text_len = 100;
    int font_size = 20;
    int font_padding = 25;
    float font_y_offset = (rec_height - (float)font_size) / 2f;

    float badge_w = 40;
    float badge_h = 16;
    float badge_y_offset = (rec_height - (float)badge_h) / 2f;
    int badge_padding = rec_padding - 5;

    // the index is still the same even if we reverse the iter.
    int visual_idx; 
    foreach_r (entry: self.history) {
        int y_pos = 50 + (visual_idx * spacing);
        bool is_selected = visual_idx == self.selected_idx;

        // rectangle
        rl::Color rec_color = is_selected ? BODY : BG;
        rl::drawRectangle(rec_padding, y_pos, rec_width, rec_height, rec_color);

        // text
        // TODO: hide everything after a potential newline
        String text = entry.text.len > max_text_len ? entry.text[..max_text_len] : entry.text;
        rl::drawTextEx(self.font, text.zstr_tcopy(), {font_padding, y_pos + font_y_offset}, font_size, 0f, TEXT);

        // badge
        float badge_x = (float)rec_padding + rec_width - badge_w;
        float badge_y = (float)y_pos + badge_y_offset;
        ZString count_str = string::tformat_zstr("%d", entry.text.len);
        rl::Color badge_bg = is_selected ? TEXT : BODY;
        rl::Color badge_txt_color = is_selected ? BODY : TEXT;
        rl::drawRectangleV({badge_x, badge_y}, {badge_w, badge_h}, badge_bg);
        rl::Vector2 count_size = rl::measureTextEx(self.font, count_str, 12, 0);
        rl::Vector2 count_pos = {
            badge_x + (badge_w - count_size.x) / 2f,
            badge_y + (badge_h - count_size.y) / 2f,
        };
        rl::drawTextEx(self.font, count_str, count_pos, 12, 0, badge_txt_color);

        visual_idx++;
    }
    rl::endDrawing();
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
        // .font = rl::loadFont("resources/SF-Pro.ttf"),
        .font = rl::loadFontEx("resources/SF-Pro.ttf", 64, null, 0),
    };
    manager.update();
    rl::setExitKey(rl::KEY_NULL); // disable default ESCAPE to exit
    return manager;
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

