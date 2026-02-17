module ui;
import raylib5;
import std::os::macos::objc, objc;

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

struct UIState {
    int selected_idx;
    Mode mode;
    Vector2 scroll_pos;
    int key_repeat_counter;
    DString search_query;
}

enum Mode {
    HIDE,
    LIST,
    INSPECT,
    SEARCH,
    QUIT,
}

fn void move_app_to_background() {
    ObjcId shared_app = objc::msg_send(objc::getClass("NSApplication"), SendVoid, "sharedApplication");
    objc::msg_send(shared_app, GetId_Id, "hide:", shared_app);
}

fn void app_to_foreground() {
    ObjcId shared_app = objc::msg_send(objc::getClass("NSApplication"), SendVoid, "sharedApplication");
    objc::msg_send(shared_app, SendBool, "activateIgnoringOtherApps:", true);
}

fn void center_window() {
    int monitor = rl::getCurrentMonitor();
    rl::Vector2 size = { (float)rl::getMonitorWidth(monitor), (float)rl::getMonitorHeight(monitor) };
    rl::Vector2 scale = rl::getWindowScaleDPI();
    int x = (int)((size.x / scale.x - ui::SCREEN_WIDTH) / 2f);
    int y = (int)((size.y / scale.y - ui::SCREEN_HEIGHT) / 2f);
    rl::setWindowPosition(x, y);
}

fn void UIState.show_window(&self) {
    ui::app_to_foreground();
    center_window();
    self.selected_idx = 0;
    self.mode = LIST;
    self.scroll_pos = {0, 0};
    rl::clearWindowState(WINDOW_HIDDEN);
    rl::setWindowState(WINDOW_TOPMOST);
    rl::restoreWindow();
}

