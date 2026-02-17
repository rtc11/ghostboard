module manager;

import std::sort;
import std::collections::list;
import config, clipboard, ui;
import raylib5;
import std::math;
import std::time;
import std::os::env;
import std::thread;
import std::io;
import std::os::macos::objc, objc;
import cg, cf, ct;

faultdef REDACTED;

struct Manager {
    Clipboard cp;
    List{Entry} history;
    usz history_limit;
    Config config;
    Font font;
    UIState ui;
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
    manager.ui.search_query.tinit(128);
    manager.load_from_file();
    manager.update();
    rl::setExitKey(rl::KEY_NULL); // disable default ESCAPE to exit
    return manager;
}

fn void Manager.center_window(&self) {
    int monitor = rl::getCurrentMonitor();
    rl::Vector2 size = { (float)rl::getMonitorWidth(monitor), (float)rl::getMonitorHeight(monitor) };
    rl::Vector2 scale = rl::getWindowScaleDPI();
    int x = (int)((size.x / scale.x - ui::SCREEN_WIDTH) / 2f);
    int y = (int)((size.y / scale.y - ui::SCREEN_HEIGHT) / 2f);
    rl::setWindowPosition(x, y);
}

fn void Manager.show_window(&self) {
    ui::app_to_foreground();
    self.center_window();
    self.ui.selected_idx = 0;
    self.ui.mode = LIST;
    self.ui.scroll_pos = {0, 0};
    quicksort(&self.history);
    rl::clearWindowState(WINDOW_HIDDEN);
    rl::setWindowState(WINDOW_TOPMOST);
    rl::restoreWindow();
}

// bool should_quit;

fn void Manager.loop(&self) {
    int last_count = (int)objc::msg_send(self.cp.instance, GetInt, "changeCount");

    while (!rl::windowShouldClose() && self.ui.mode != QUIT) {
        if (self.ui.mode == LIST && !rl::isWindowFocused()) {
            self.ui.mode = HIDE;
            rl::setWindowState(WINDOW_HIDDEN);
            ui::move_app_to_background();
        }

        int current_count = (int)objc::msg_send(self.cp.instance, GetInt, "changeCount");
        if (current_count != last_count) {
            log::info("new clip detected");
            last_count = current_count;
            thread::sleep(time::ms(50)); // race condition, wait for macos to save its clip first
            self.update();
        }
 
        switch (self.ui.mode) {
            case INSPECT:
                self.show_all_text_view();
                self.menu_mode();
            case LIST:
            case SEARCH:
                self.show_clips();
                self.menu_mode();
            case HIDE:
                rl::pollInputEvents();
                rl::beginDrawing();
                rl::clearBackground(ui::COLOR_BG);
                rl::endDrawing();
            case QUIT:
        }

        thread::sleep(time::ms(8));
    }
    rl::closeWindow();
}

fn void Manager.menu_mode(&self) {
    const int MAX_VISIBLE_ITEMS = 17;
    const int ITEM_SPACING = 30;
    const int KEY_REPEAT_INITIAL_DELAY = 20;  // Wait 20 frames (~167ms) before starting repeat
    const int KEY_REPEAT_DELAY = 3;           // Then move every 3 frames (~25ms)
    
    if (self.ui.mode == LIST) {
        bool key_down = rl::isKeyDown(rl::KEY_DOWN) || rl::isKeyDown(rl::KEY_J);
        bool key_up = rl::isKeyDown(rl::KEY_UP) || rl::isKeyDown(rl::KEY_K);
        
        // Reset counter if no key is pressed
        if (!key_down && !key_up) {
            self.ui.key_repeat_counter = 0;
        }
        
        if (key_down) {
            // Allow movement on first press or after initial delay
            bool first_press = rl::isKeyPressed(rl::KEY_DOWN) || rl::isKeyPressed(rl::KEY_J);
            bool should_repeat = self.ui.key_repeat_counter >= KEY_REPEAT_INITIAL_DELAY && 
                                 (self.ui.key_repeat_counter - KEY_REPEAT_INITIAL_DELAY) % KEY_REPEAT_DELAY == 0;
            
            if (first_press || should_repeat) {
                if (self.ui.selected_idx < (int)self.history.len() - 1) {
                    self.ui.selected_idx++;
                    
                    // Auto-scroll when selection moves below visible area
                    int scroll_offset = (int)(self.ui.scroll_pos.y / ITEM_SPACING);
                    if (self.ui.selected_idx >= scroll_offset + MAX_VISIBLE_ITEMS) {
                        self.ui.scroll_pos.y += ITEM_SPACING;
                    }
                }
            }
            self.ui.key_repeat_counter++;
        }

        if (key_up) {
            // Allow movement on first press or after initial delay
            bool first_press = rl::isKeyPressed(rl::KEY_UP) || rl::isKeyPressed(rl::KEY_K);
            bool should_repeat = self.ui.key_repeat_counter >= KEY_REPEAT_INITIAL_DELAY && 
                                 (self.ui.key_repeat_counter - KEY_REPEAT_INITIAL_DELAY) % KEY_REPEAT_DELAY == 0;
            
            if (first_press || should_repeat) {
                if (self.ui.selected_idx > 0) {
                    self.ui.selected_idx--;
                    
                    // Auto-scroll when selection moves above visible area
                    int scroll_offset = (int)(self.ui.scroll_pos.y / ITEM_SPACING);
                    if (self.ui.selected_idx < scroll_offset) {
                        self.ui.scroll_pos.y -= ITEM_SPACING;
                    }
                }
            }
            self.ui.key_repeat_counter++;
        }
        
        // Mouse wheel scrolling
        float wheel = rl::getMouseWheelMove();
        if (wheel != 0) {
            self.ui.scroll_pos.y -= wheel * 30.0f;
            // Clamp scroll position
            if (self.ui.scroll_pos.y < 0) self.ui.scroll_pos.y = 0;
            int max_scroll = math::max(0, ((int)self.history.len() - MAX_VISIBLE_ITEMS) * ITEM_SPACING);
            if (self.ui.scroll_pos.y > max_scroll) self.ui.scroll_pos.y = (float)max_scroll;
        }
    }

    if (rl::isKeyPressed(rl::KEY_ESCAPE) || rl::isKeyPressed(rl::KEY_Q)) {
        switch (self.ui.mode) {
            case SEARCH:
                self.ui.mode = LIST;
                self.ui.search_query.clear();
                self.ui.selected_idx = 0;
            case INSPECT:
                self.ui.mode = LIST;
            default:
                self.ui.mode = HIDE;
                rl::setWindowState(WINDOW_HIDDEN);
                ui::move_app_to_background();
        }
    }
    
    // Handle text input and mode switching - process all characters
    int key = rl::getCharPressed();
    while (key > 0) {
        if (key == '/' && self.ui.mode == LIST) {
            log::info("search mode activated");
            self.ui.mode = SEARCH;
            self.ui.search_query.clear();
            self.ui.selected_idx = 0;
        } else if (self.ui.mode == SEARCH && key >= 32 && key < 127 && key != '/') {
            self.ui.search_query.append_char((char)key);
            self.ui.selected_idx = 0;
        }
        key = rl::getCharPressed();
    }
    
    // Handle backspace in search mode
    if (self.ui.mode == SEARCH) {
        if (rl::isKeyPressed(rl::KEY_BACKSPACE) && self.ui.search_query.len() > 0) {
            self.ui.search_query.delete(self.ui.search_query.len() - 1, 1);
            self.ui.selected_idx = 0;
        }
    }

    if (rl::isKeyPressed(rl::KEY_ENTER)) {
        Entry? selected = self.history.get(self.ui.selected_idx);
        if (try selected) {
            self.cp.set(selected.text);
        } else if (@catch(selected) == REDACTED) {
            self.cp.set("***");
        } 
        self.ui.mode = HIDE;
        rl::setWindowState(WINDOW_HIDDEN);
        ui::move_app_to_background();
        thread::sleep(time::ms(50)); // wait for the os to complete the transition
        self.simulate_paste();
    }

    if (rl::isKeyPressed(rl::KEY_O) && self.history.len() > 0) {
        switch (self.ui.mode) {
            case LIST: self.ui.mode = INSPECT;
            case INSPECT: self.ui.mode = LIST;
            default: break;
        }
        self.ui.scroll_pos = {0, 0};
    }

    if (rl::isKeyPressed(rl::KEY_D) || rl::isKeyPressed(rl::KEY_DELETE) && self.ui.mode == LIST && self.history.len() > 0) {
        self.remove_selected();
    }

    if (self.ui.mode == INSPECT) {
        float scroll_speed = 20f;
        float hjkl_speed = 15;
        if (rl::isKeyDown(rl::KEY_LEFT)  || rl::isKeyDown(rl::KEY_H)) self.ui.scroll_pos.x -= hjkl_speed;
        if (rl::isKeyDown(rl::KEY_DOWN)  || rl::isKeyDown(rl::KEY_J)) self.ui.scroll_pos.y += hjkl_speed;
        if (rl::isKeyDown(rl::KEY_UP)    || rl::isKeyDown(rl::KEY_K)) self.ui.scroll_pos.y -= hjkl_speed;
        if (rl::isKeyDown(rl::KEY_RIGHT) || rl::isKeyDown(rl::KEY_L)) self.ui.scroll_pos.x += hjkl_speed;
        float wheel = rl::getMouseWheelMove();
        if (wheel != 0) self.ui.scroll_pos.y -= wheel * scroll_speed;
        if (self.ui.scroll_pos.y < 0) self.ui.scroll_pos.y = 0;
        if (self.ui.scroll_pos.x < 0) self.ui.scroll_pos.x = 0;
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
    
    Entry? entry = self.history.get(self.ui.selected_idx);
    if (catch entry) return;
    self.history.remove_at(self.ui.selected_idx);
    
    entry.text.free(mem);
    
    if (self.history.len() == 0) {
        self.ui.selected_idx = 0;
    } else if (self.ui.selected_idx >= self.history.len()) {
        self.ui.selected_idx = (int)self.history.len() - 1;
    }
    
    self.save_to_file();
    log::info("removed clip at index %d", self.ui.selected_idx);
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

fn void Manager.show_clips(&self) {
    rl::beginDrawing();
    rl::clearBackground(ui::COLOR_BG);
    rl::setTextureFilter(self.font.texture, BILINEAR);

    // header
    ZString header_txt = "GhostBoard".zstr_tcopy();
    float header_font_size = 24f;
    rl::Vector2 header_size = rl::measureTextEx(self.font, header_txt, header_font_size, 0f);
    float header_x = (ui::SCREEN_WIDTH - header_size.x) / 2f;
    int header_padding = 10;
    int extra_body_space = 80;
    rl::Rectangle header_rec = { 
        header_x - header_padding - extra_body_space / 2f, 
        10 - header_padding / 2f, 
        header_size.x + header_padding * 2f + extra_body_space, 
        header_size.y + header_padding 
    };
    rl::drawRectangleRounded(header_rec, 0.5, 12, ui::COLOR_BODY);
    rl::drawTextEx(self.font, header_txt, {header_x, 10f}, header_font_size, 0f, ui::COLOR_TITLE);
    
    // version number
    ZString version_txt = "v0.1.0".zstr_tcopy();
    float version_font_size = 14f;
    rl::Vector2 version_size = rl::measureTextEx(self.font, version_txt, version_font_size, 0f);
    float version_x = header_x + header_size.x + 8f;
    float version_y = 10f + (header_size.y - version_size.y) / 2f;
    rl::drawTextEx(self.font, version_txt, {version_x, version_y}, version_font_size, 0f, ui::COLOR_FOOTER);
    
    // Search bar (if in search mode)
    int search_bar_height = 0;
    if (self.ui.mode == SEARCH) {
        search_bar_height = 30;
        String search_text = self.ui.search_query.len() > 0 ? self.ui.search_query.str_view() : "Type to search...";
        ZString search_display = string::tformat_zstr("/ %s", search_text);
        rl::Vector2 search_pos = {25, 43};
        rl::Color search_color = self.ui.search_query.len() > 0 ? ui::COLOR_TITLE : ui::COLOR_FOOTER;
        rl::drawTextEx(self.font, search_display, search_pos, 18, 0f, search_color);
    }

    int spacing = 30;
    int rec_padding = 20;
    int rec_height = 25;
    int rec_width = ui::SCREEN_WIDTH - (rec_padding * 2);

    int max_text_len = 84;
    int font_size = 20;
    int font_padding = 25;
    float font_y_offset = (rec_height - (float)font_size) / 2f;

    float badge_w = 50;
    float badge_h = rec_height;
    float badge_y_offset = (rec_height - (float)badge_h) / 2f;
    int badge_padding = rec_padding - 5;

    // Filter by search query if active
    int visual_idx; 
    foreach (entry : self.history) {
        // Filter by search query
        if (self.ui.mode == SEARCH && self.ui.search_query.len() > 0) {
            String query_lower = self.ui.search_query.str_view().to_lower_tcopy();
            String text_lower = entry.text.to_lower_tcopy();
            if (!text_lower.contains(query_lower)) {
                continue;  // Skip entries that don't match
            }
        }
        
        float y_pos = 50 + (float)search_bar_height + ((float)visual_idx * spacing) - self.ui.scroll_pos.y;
        
        // Skip rendering items outside visible area (footer starts at ~570)
        if (y_pos < 45 || y_pos + rec_height > ui::SCREEN_HEIGHT - 40) {
            visual_idx++;
            continue;
        }
        
        bool is_selected = visual_idx == self.ui.selected_idx;

        // rectangle
        rl::Color rec_color = is_selected ? ui::COLOR_BODY : ui::COLOR_BG;
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
        rl::Color text_color = is_selected ? ui::COLOR_TITLE : ui::COLOR_TEXT;
        rl::drawTextEx(self.font, text.zstr_tcopy(), {font_padding, y_pos + font_y_offset}, font_size, 0f, text_color);

        // badge
        float badge_x = (float)rec_padding + rec_width - badge_w;
        float badge_y = (float)y_pos + badge_y_offset;
        ZString count_str = string::tformat_zstr("%d", entry.text.len);
        rl::Color badge_bg = ui::COLOR_BODY;
        rl::Color badge_corner_color = is_selected ? ui::COLOR_BADGE_LINE : ui::COLOR_BODY;
        rl::Rectangle badge_rec = { badge_x, badge_y, badge_w, badge_h };
        rl::drawRectangleRounded(rec: badge_rec, roundness: 0.5, segments: 12, color: badge_bg); 
        rl::drawRectangleRoundedLinesEx(badge_rec, 0.5, 24, 1.0, badge_corner_color);
        rl::Vector2 count_size = rl::measureTextEx(self.font, count_str, 12, 0);
        rl::Vector2 count_pos = {
            badge_x + (badge_w - count_size.x) / 2f,
            badge_y + (badge_h - count_size.y) / 2f,
        };
        rl::drawTextEx(self.font, count_str, count_pos, 14, 0, ui::COLOR_BADGE_TEXT);

        // timestamp footer
        if (is_selected) {
            ZString timestamp = string::tformat_zstr("%s", entry.timestamp);
            rl::Vector2 timestamp_size = rl::measureTextEx(self.font, timestamp, 16, 0);
            float timestamp_x = (ui::SCREEN_WIDTH - timestamp_size.x) - 25;
            rl::drawTextEx(self.font, timestamp, {timestamp_x, ui::SCREEN_HEIGHT - 30f}, 16, 0f, ui::COLOR_FOOTER);
        }

        visual_idx++;
    }

    // footer
    ZString footer = string::tformat_zstr("o: inspect clip       d: delete clip       enter: select clip       q: quit       hjkl: navigate");
    rl::drawTextEx(self.font, footer, {25, ui::SCREEN_HEIGHT - 30f}, 19, 0f, ui::COLOR_FOOTER);
    rl::endDrawing();
}

fn void Manager.show_all_text_view(&self) {
    rl::beginDrawing();
    rl::clearBackground(ui::COLOR_BG);

    Entry? selected = self.history.get(self.ui.selected_idx);

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
        int rec_width = ui::SCREEN_WIDTH - (rec_padding * 2);
        int y_pos = 10;
        rl::Rectangle header_rec = { (float)rec_padding, (float)y_pos, (float)rec_width, (float)rec_height};
        rl::drawRectangleRounded(header_rec, 0.5, 12, ui::COLOR_BODY);
        float font_size = 20;
        float font_y_offset = (rec_height - font_size) / 2f;
        rl::drawTextEx(self.font, preview.zstr_tcopy(), {header_rec.x + 10, (float)y_pos + font_y_offset}, font_size, 0f, ui::COLOR_TITLE);
        float badge_w = 50;
        float badge_h = (float)rec_height;
        float badge_x = header_rec.x + header_rec.width - badge_w;
        ZString count_str = string::tformat_zstr("%d", selected.text.len);
        rl::Rectangle badge_rec = { badge_x, (float)y_pos, badge_w, badge_h};
        rl::drawRectangleRounded(badge_rec, 0.5, 12, ui::COLOR_BODY);
        rl::drawRectangleRoundedLinesEx(badge_rec, 0.5, 24, 1f, ui::COLOR_BADGE_LINE);
        rl::Vector2 count_size = rl::measureTextEx(self.font, count_str, 12, 0);
        rl::Vector2 count_pos = {
            badge_x + (badge_w - count_size.x) / 2f,
            (float)y_pos + (badge_h - count_size.y) / 2f,
        };
        rl::drawTextEx(self.font, count_str, count_pos, 14, 0, ui::COLOR_BADGE_TEXT);

        // text area
        rl::Rectangle text_area_rec = { 20, 50, ui::SCREEN_WIDTH - 40, ui::SCREEN_HEIGHT - 80 };
        rl::drawRectangleRounded(text_area_rec, 0.2, 8, ui::COLOR_BODY);
        
        int text_padding = 20;
        rl::Vector2 scale = rl::getWindowScaleDPI();
        rl::beginScissorMode(
            x: (20 + text_padding) * (int)scale.x, 
            y: (50 + text_padding) * (int)scale.y,
            width: (ui::SCREEN_WIDTH - 40 - text_padding * 2) * (int)scale.x,
            height: (ui::SCREEN_HEIGHT - 80 - text_padding * 2) * (int)scale.y,
        );
        rl::Vector2 pos = {
            20 + (float) text_padding - self.ui.scroll_pos.x,
            50 + (float) text_padding - self.ui.scroll_pos.y
        }; 
        rl::drawTextEx(self.font, selected.text.zstr_tcopy(), pos, 18f, 1f, ui::COLOR_TEXT);
        rl::endScissorMode();

        // timestamp
        ZString timestamp = string::tformat_zstr("%s", selected.timestamp);
        rl::Vector2 timestamp_size = rl::measureTextEx(self.font, timestamp, 16, 0);
        float timestamp_x = (ui::SCREEN_WIDTH - timestamp_size.x) - 25;
        rl::drawTextEx(self.font, timestamp, {timestamp_x, ui::SCREEN_HEIGHT - 30f}, 16, 0f, ui::COLOR_FOOTER);

        // footer
        ZString footer = string::tformat_zstr("o: inspect clip       d: delete clip       enter: select clip       q: quit       hjkl: navigate");
        rl::drawTextEx(self.font, footer, {25, ui::SCREEN_HEIGHT - 30f}, 19, 0f, ui::COLOR_FOOTER);

    }
    rl::endDrawing();
}

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

