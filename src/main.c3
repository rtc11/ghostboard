import std::core::log, logger;
import std::os::macos::objc, objc;
import std::thread;
import std::time;
import cg, cf, ct;
import config, clipboard, manager, ui;
import raylib5;

// macOS hardware keycodes (different from ASCII/raylib character codes)
const ushort KEYCODE_D     = 0x02;
const ushort KEYCODE_U     = 0x20;
const ushort KEYCODE_V     = 0x09;
const ushort KEYCODE_EQUAL = 0x1B;
const ushort KEYCODE_SLASH = 0x2C;
const ushort KEYCODE_1     = 0x12;
const ushort KEYCODE_2     = 0x13;
const ushort KEYCODE_3     = 0x14;
const ushort KEYCODE_4     = 0x15;
const ushort KEYCODE_5     = 0x17;
const ushort KEYCODE_6     = 0x16;
const ushort KEYCODE_7     = 0x1A;
const ushort KEYCODE_8     = 0x1C;
const ushort KEYCODE_9     = 0x19;

fn void main(String[] args)
{
    Config config = {
        .config_dir = ".config/ghostboard",
        .storage_file = "storage.bin",
        .log_file = "logs.txt",
        .history_limit = 500,
        .font_path = "/System/Library/Fonts/SFNS.ttf",
        .expire_unused_days = 7,
        .expire_used_days = 30,
    };

    logger::setup_logging(&config);
    hide_from_dock();
    
    rl::setConfigFlags(ConfigFlag.WINDOW_UNDECORATED | ConfigFlag.WINDOW_TRANSPARENT | ConfigFlag.WINDOW_HIGHDPI);
    rl::initWindow(ui::SCREEN_WIDTH, ui::SCREEN_HEIGHT, "GhostBoard");

    Manager manager = manager::init(config: config);

    setup_tray(&manager);

    setup_event_tap(&manager);
    manager.run();
}

fn void hide_from_dock() {
    ObjcId shared_app = objc::msg_send(objc::getClass("NSApplication"), SendVoid, "sharedApplication");
    objc::msg_send(shared_app, SendUsz, "setActivationPolicy:", 1);
    rl::setConfigFlags(ConfigFlag.WINDOW_HIDDEN | ConfigFlag.WINDOW_ALWAYS_RUN);
}

fn void quit_action(ObjcId self, ObjcSelector _cmd, ObjcId sender) {
    log::info("Quit action called");
    Manager* manager = (Manager*)objc::get_associated_object(self, "manager");
    if (manager) manager.ui.mode = QUIT;
}

fn void setup_tray(Manager* manager) {
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
    ObjcId exit_title = objc::nsstr("Quit GhostBoard");
    ObjcSelector quit_sel = objc::sel_registerName("quitAction:");
    ObjcId key_equivalent = objc::nsstr("q");
    exit_item = objc::msg_send(exit_item, GetId_IdSelId, "initWithTitle:action:keyEquivalent:", exit_title, quit_sel, key_equivalent);
    ObjcId target = objc::msg_send(target_class, SendVoid, "alloc");
    target = objc::msg_send(target, SendVoid, "init");
    objc::set_associated_object(target, "manager", manager, objc::ASSOCIATION_ASSIGN);
    objc::msg_send(exit_item, SendId, "setTarget:", target);
    objc::msg_send(menu, SendId, "addItem:", exit_item);
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
    bool command = (flags & 0x100000) != 0;
    
    Manager* manager = (Manager*)refcon;
    
    // Ctrl+Shift+V to open menu
    if (control && shift && keycode == KEYCODE_V) {
        log::info("Ctrl+Shift+V detected, current mode: %s", manager.ui.mode);
        if (manager.ui.mode == HIDE) {
            log::info("global hotkey detected! enabling menu");
            manager.ui.show_window();
        }
        return null;
    }
    
    // Ctrl+D and Ctrl+U for page scrolling when window is visible
    if (control && !shift && !command) {
        if (keycode == KEYCODE_D) {
            log::info("Ctrl+D detected in event tap, mode: %s", manager.ui.mode);
            if (manager.ui.mode != HIDE) {
                manager.ui.ctrl_d_pressed = true;
            }
            return event;
        }
        if (keycode == KEYCODE_U) {
            log::info("Ctrl+U detected in event tap, mode: %s", manager.ui.mode);
            if (manager.ui.mode != HIDE) {
                manager.ui.ctrl_u_pressed = true;
            }
            return event;
        }
    }
    
    // Command++ and Command+- for font scaling when window is visible
    if (command && !control && !shift) {
        if (keycode == KEYCODE_EQUAL) { // Plus/Equal key (Command++)
            log::info("Command++ detected - mode: %s", manager.ui.mode);
            if (manager.ui.mode != HIDE) {
                manager.font_scale += 0.1;
                if (manager.font_scale > 2.0) manager.font_scale = 2.0; // Max 2x
                log::info("Font scale: %.2f", manager.font_scale);
            }
            return null;
        }
        if (keycode == KEYCODE_SLASH) { // Slash key (Command+-)
            log::info("Command+- detected - mode: %s", manager.ui.mode);
            if (manager.ui.mode != HIDE) {
                manager.font_scale -= 0.1;
                if (manager.font_scale < 0.5) manager.font_scale = 0.5; // Min 0.5x
                log::info("Font scale: %.2f", manager.font_scale);
            }
            return null;
        }
    }
    
    // Ctrl+Shift+1-9 for quicklist (only when app is hidden)
    if ((control || command) && shift && keycode >= KEYCODE_1 && keycode <= KEYCODE_9 && manager.ui.mode == HIDE) {
        int num = 0;
        switch (keycode) {
            case KEYCODE_1: num = 1;
            case KEYCODE_2: num = 2;
            case KEYCODE_3: num = 3;
            case KEYCODE_4: num = 4;
            case KEYCODE_5: num = 5;
            case KEYCODE_6: num = 6;
            case KEYCODE_7: num = 7;
            case KEYCODE_8: num = 8;
            case KEYCODE_9: num = 9;
        }
        if (num > 0) {
            log::info("checking for quicklist clip with number %d", num);
            foreach (entry : manager.history) {
                log::debug("clip has quicklist_number: %d", entry.quicklist_number);
                if (entry.quicklist_number == num) {
                    manager.cp.set(entry.text);
                    if (manager.ui.mode == HIDE) {
                        manager.simulate_paste();
                    }
                    log::info("pasted quicklist clip %d", num);
                    return null;
                }
            }
            log::info("no clip assigned to quicklist slot %d", num);
        }
    }
    
    return event;
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
    ns_image = objc::msg_send(ns_image, GetId_Id, "initByReferencingFile:", objc::nsstr(icon_path));
    objc::msg_send(ns_image, SendBool, "setTemplate:", true);
    rl::unloadImage(icon);
    return ns_image;
}

