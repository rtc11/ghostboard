module manager;

import config, clipboard, ui, storage;
import raylib5;
import std::collections::list;
import std::io;
import std::math;
import std::os::env;
import std::os::macos::objc, objc, cg, cf, ct;
import std::sort;
import std::thread;
import std::time;

faultdef REDACTED;

struct Manager {
    Clipboard cp;
    List{StoredEntry} history;
    usz history_limit;
    Config config;
    Font font;
    UIState ui;
}

fn Manager init(Config config) {
    Clipboard cp = {
        .instance = objc::msg_send(objc::class_by_name("NSPasteboard")!!, SendVoid, "generalPasteboard"),
        .items_sel = objc::sel_registerName("pasteboardItems"),
        .first_obj_sel = objc::sel_registerName("firstObject"),
        .types_sel = objc::sel_registerName("types"),
    };
    Manager manager = {
        .cp = cp,
        .history_limit = config.history_limit,
        .config = config,
        .font = ui::load_font(),
    };
    storage::load_from_file(&manager.config, &manager.history);
    manager.update();
    rl::setExitKey(rl::KEY_NULL); // disable default ESCAPE to exit
    return manager;
}

// Helper: Check if entry should be visible based on current filters
fn bool Manager.is_entry_visible(&self, StoredEntry entry) {
    if (self.ui.active_tab == FAVORITES && !entry.is_favorite) {
        return false;
    }
    if (self.ui.active_tab == QUICKLIST && entry.quicklist_number == 0) {
        return false;
    }
    if (self.ui.mode == SEARCH && self.ui.search_query.len() > 0) {
        String query_lower = self.ui.search_query.str_view().to_lower_tcopy();
        String text_lower = entry.text.to_lower_tcopy();
        if (!text_lower.contains(query_lower)) {
            return false;
        }
    }
    return true;
}

// Helper: Count visible entries
fn int Manager.count_visible_entries(&self) {
    int count = 0;
    foreach (entry : self.history) {
        if (self.is_entry_visible(entry)) {
            count++;
        }
    }
    return count;
}

// Helper: Get entry at visual index (accounting for filters)
fn StoredEntry? Manager.get_entry_at_visual_index(&self, int visual_idx) {
    int current_idx = 0;
    foreach (entry : self.history) {
        if (!self.is_entry_visible(entry)) {
            continue;
        }
        if (current_idx == visual_idx) {
            return entry;
        }
        current_idx++;
    }
    return REDACTED?;
}

// Helper: Get actual index from visual index
fn int Manager.get_actual_index_from_visual(&self, int visual_idx) {
    int current_visual = 0;
    foreach (i, entry : self.history) {
        if (!self.is_entry_visible(entry)) {
            continue;
        }
        if (current_visual == visual_idx) {
            return (int)i;
        }
        current_visual++;
    }
    return -1;
}

fn void Manager.run(&self) {
    int last_clipboard_count = self.get_clipboard_count();
    
    while (!rl::windowShouldClose() && self.ui.mode != QUIT) {
        self.process_events(&last_clipboard_count);
        self.update_state();
        self.render();
        thread::sleep(time::ms(8)); // ~120fps
    }
    self.shutdown();
}

fn void Manager.shutdown(&self) {
    rl::closeWindow();
    ObjcId pb = objc::msg_send(objc::getClass("NSPasteboard"), GetId, "generalPasteboard");
    objc::msg_send(pb, SendVoid, "clearContents");
}

fn void Manager.process_events(&self, int* last_clipboard_count) {
    self.handle_window_focus();
    self.check_clipboard_changes(last_clipboard_count);
    self.handle_input();
}

fn void Manager.update_state(&self) {
    // - Animation updates
    // - Timed state changes
    // - Background tasks
}

fn void Manager.render(&self) {
    switch (self.ui.mode) {
        case INSPECT: self.render_inspect();
        case LIST   : self.render_clips();
        case SEARCH : self.render_clips();
        case HELP   : self.render_help();
        case HIDE   : self.render_hidden();
        case QUIT   :
    }
}

fn void Manager.handle_window_focus(&self) {
    if (self.ui.mode == LIST && !rl::isWindowFocused()) {
        self.ui.mode = HIDE;
        rl::setWindowState(WINDOW_HIDDEN);
        ui::move_app_to_background();
    }
}

fn void Manager.check_clipboard_changes(&self, int* last_count) {
    int current = self.get_clipboard_count();
    if (current != *last_count) {
        log::info("new clip detected");
        *last_count = current;
        thread::sleep(time::ms(50)); // race condition workaround
        self.update();
    }
}

fn int Manager.get_clipboard_count(&self) {
    return (int)objc::msg_send(self.cp.instance, GetInt, "changeCount");
}

fn void Manager.render_hidden(&self) {
    rl::pollInputEvents();
    rl::beginDrawing();
    rl::clearBackground(ui::COLOR_BG);
    rl::endDrawing();
}

fn void Manager.handle_input(&self) {
    switch (self.ui.mode) {
        case LIST: self.handle_list_input();
        case SEARCH: self.handle_search_input();
        case INSPECT: self.handle_inspect_input();
        case HELP: self.handle_help_input();
        case HIDE:
        case QUIT:
    }
    self.handle_mode_switching();
}

fn void Manager.handle_page_scroll(&self, int visible_count, bool is_down) {
    const int MAX_VISIBLE_ITEMS = 16;
    const int ITEM_SPACING = 30;
    const int PAGE_JUMP = MAX_VISIBLE_ITEMS / 2;
    
    if (visible_count == 0) return;
    
    if (is_down) {
        self.ui.selected_idx = math::min(self.ui.selected_idx + PAGE_JUMP, visible_count - 1);
    } else {
        self.ui.selected_idx = math::max(self.ui.selected_idx - PAGE_JUMP, 0);
    }
    
    int scroll_offset = (int)(self.ui.scroll_pos.y / ITEM_SPACING);
    if (is_down && self.ui.selected_idx >= scroll_offset + MAX_VISIBLE_ITEMS - 1) {
        self.ui.scroll_pos.y = (float)((self.ui.selected_idx - MAX_VISIBLE_ITEMS + 2) * ITEM_SPACING);
    } else if (!is_down && self.ui.selected_idx < scroll_offset) {
        self.ui.scroll_pos.y = (float)(self.ui.selected_idx * ITEM_SPACING);
    }
}

fn void Manager.handle_navigation(&self) {
    const int MAX_VISIBLE_ITEMS = 16;
    const int ITEM_SPACING = 30;
    const int KEY_REPEAT_INITIAL_DELAY = 20;
    const int KEY_REPEAT_DELAY = 3;
    
    int visible_count = self.count_visible_entries();
    
    // Page scrolling with Ctrl+D and Ctrl+U (detected by event tap)
    if (self.ui.ctrl_d_pressed) {
        self.ui.ctrl_d_pressed = false;
        self.handle_page_scroll(visible_count, true);
        return;
    }
    if (self.ui.ctrl_u_pressed) {
        self.ui.ctrl_u_pressed = false;
        self.handle_page_scroll(visible_count, false);
        return;
    }
    
    bool key_down = rl::isKeyDown(rl::KEY_DOWN) || rl::isKeyDown(rl::KEY_J);
    bool key_up = rl::isKeyDown(rl::KEY_UP) || rl::isKeyDown(rl::KEY_K);
    
    if (!key_down && !key_up) {
        self.ui.key_repeat_counter = 0;
        return;
    }
    
    if (key_down) {
        bool first_press = rl::isKeyPressed(rl::KEY_DOWN) || rl::isKeyPressed(rl::KEY_J);
        bool should_repeat = self.ui.key_repeat_counter >= KEY_REPEAT_INITIAL_DELAY && 
                             (self.ui.key_repeat_counter - KEY_REPEAT_INITIAL_DELAY) % KEY_REPEAT_DELAY == 0;
        if (first_press || should_repeat) {
            if (self.ui.selected_idx < visible_count - 1) {
                self.ui.selected_idx++;
                
                int scroll_offset = (int)(self.ui.scroll_pos.y / ITEM_SPACING);
                if (self.ui.selected_idx >= scroll_offset + MAX_VISIBLE_ITEMS) {
                    self.ui.scroll_pos.y += ITEM_SPACING;
                }
            }
        }
        self.ui.key_repeat_counter++;
    }

    if (key_up) {
        bool first_press = rl::isKeyPressed(rl::KEY_UP) || rl::isKeyPressed(rl::KEY_K);
        bool should_repeat = self.ui.key_repeat_counter >= KEY_REPEAT_INITIAL_DELAY && 
                             (self.ui.key_repeat_counter - KEY_REPEAT_INITIAL_DELAY) % KEY_REPEAT_DELAY == 0;
        if (first_press || should_repeat) {
            if (self.ui.selected_idx > 0) {
                self.ui.selected_idx--;
                
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
        if (self.ui.scroll_pos.y < 0) self.ui.scroll_pos.y = 0;
        int max_scroll = math::max(0, (visible_count - MAX_VISIBLE_ITEMS) * ITEM_SPACING);
        if (self.ui.scroll_pos.y > max_scroll) self.ui.scroll_pos.y = (float)max_scroll;
    }
}

fn void Manager.handle_selection(&self) {
    if (rl::isKeyPressed(rl::KEY_ENTER)) {
        StoredEntry? selected = self.get_selected_entry();
        if (try selected) {
            self.cp.set(selected.text);
            self.ui.mode = HIDE;
            rl::setWindowState(WINDOW_HIDDEN);
            ui::move_app_to_background();
            self.simulate_paste();
        }
    }
    
    // Double-tap 'd' to delete (vim-style dd) - but not with Ctrl
    bool ctrl = rl::isKeyDown(rl::KEY_LEFT_CONTROL) || rl::isKeyDown(rl::KEY_RIGHT_CONTROL);
    if (rl::isKeyPressed(rl::KEY_D) && !ctrl) {
        double current_time = rl::getTime();
        if (self.ui.delete_pending && (current_time - self.ui.last_delete_press_time) < 0.5) {
            // Second press within 0.5 seconds - delete
            if (self.history.len() > 0) {
                self.remove_selected();
            }
            self.ui.delete_pending = false;
        } else {
            // First press - mark as pending
            self.ui.delete_pending = true;
            self.ui.last_delete_press_time = current_time;
        }
    } else if (self.ui.delete_pending) {
        // Reset if other key pressed or timeout
        double current_time = rl::getTime();
        if (current_time - self.ui.last_delete_press_time > 0.5) {
            self.ui.delete_pending = false;
        }
    }
    
    // Keep Delete key for immediate deletion
    if (rl::isKeyPressed(rl::KEY_DELETE)) {
        if (self.history.len() > 0) {
            self.remove_selected();
        }
    }
}

fn StoredEntry? Manager.get_selected_entry(&self) {
    return self.get_entry_at_visual_index(self.ui.selected_idx);
}

fn void Manager.handle_text_input(&self) {
    int key = rl::getCharPressed();
    while (key > 0) {
        if (key >= 32 && key < 127 && key != '/') {
            self.ui.search_query.append_char((char)key);
            self.ui.selected_idx = 0;
        }
        key = rl::getCharPressed();
    }
    
    if (rl::isKeyPressed(rl::KEY_BACKSPACE) && self.ui.search_query.len() > 0) {
        self.ui.search_query.delete(self.ui.search_query.len() - 1, 1);
        self.ui.selected_idx = 0;
    }
}

fn void Manager.handle_mode_switching(&self) {
    if (rl::isKeyPressed(rl::KEY_ESCAPE) || rl::isKeyPressed(rl::KEY_Q)) {
        switch (self.ui.mode) {
            case SEARCH:
                self.ui.mode = LIST;
                self.ui.search_query.clear();
                self.ui.selected_idx = 0;
            case INSPECT:
                self.ui.mode = LIST;
            case HELP:
                self.ui.mode = LIST;
                self.ui.scroll_pos = {0, 0};
            default:
                self.ui.mode = HIDE;
                rl::setWindowState(WINDOW_HIDDEN);
                ui::move_app_to_background();
        }
        return;
    }
    
    // H to toggle help mode
    if (rl::isKeyPressed(rl::KEY_H)) {
        switch (self.ui.mode) {
            case LIST: self.ui.mode = HELP;
            case HELP: self.ui.mode = LIST;
            default:
        }
    }
    
    // / to enter search mode
    int key = rl::getCharPressed();
    while (key > 0) {
        if (key == '/' && self.ui.mode == LIST) {
            log::info("search mode activated");
            self.ui.mode = SEARCH;
            self.ui.search_query.clear();
            self.ui.selected_idx = 0;
        }
        key = rl::getCharPressed();
    }
    
    // O to toggle inspect mode
    if (rl::isKeyPressed(rl::KEY_O) && self.history.len() > 0) {
        switch (self.ui.mode) {
            case LIST: self.ui.mode = INSPECT;
            case INSPECT: self.ui.mode = LIST;
            default:
        }
    }
}

fn void Manager.handle_tab_switching(&self) {
    if (rl::isKeyPressed(rl::KEY_TAB)) {
        switch (self.ui.active_tab) {
            case ALL_CLIPS: self.ui.active_tab = FAVORITES;
            case FAVORITES: self.ui.active_tab = QUICKLIST;
            case QUICKLIST: self.ui.active_tab = ALL_CLIPS;
        }
        self.ui.selected_idx = 0;
        self.ui.scroll_pos = {0, 0};
    }
}

fn void Manager.handle_favorite_toggle(&self) {
    if (rl::isKeyPressed(rl::KEY_F) && self.history.len() > 0) {
        int actual_idx = self.get_actual_index_from_visual(self.ui.selected_idx);
        if (actual_idx >= 0) {
            self.history[actual_idx].is_favorite = !self.history[actual_idx].is_favorite;
            storage::save_to_file(&self.config, &self.history);
            log::info("clip %s (index %d)", self.history[actual_idx].is_favorite ? "favorited" : "unfavorited", actual_idx);
        }
    }
}

fn void Manager.handle_quicklist_toggle(&self) {
    if (self.history.len() == 0) return;
    
    // Check for number keys 1-9
    for (int num = 1; num <= 9; num++) {
        KeyboardKey key = (KeyboardKey)((int)rl::KEY_ONE + (num - 1));
        if (rl::isKeyPressed(key)) {
            int actual_idx = self.get_actual_index_from_visual(self.ui.selected_idx);
            
            if (actual_idx >= 0) {
                if (self.history[actual_idx].quicklist_number == num) {
                    self.history[actual_idx].quicklist_number = 0;
                    log::info("removed clip from quicklist slot %d", num);
                } else {
                    // Remove the number from any other clip first
                    for (int j = 0; j < self.history.len(); j++) {
                        if (self.history[j].quicklist_number == num) {
                            self.history[j].quicklist_number = 0;
                            log::info("cleared quicklist slot %d from previous clip", num);
                        }
                    }
                    self.history[actual_idx].quicklist_number = num;
                    log::info("assigned clip to quicklist slot %d", num);
                }
                storage::save_to_file(&self.config, &self.history);
            }
            break;
        }
    }
}

fn void Manager.handle_list_input(&self) {
    self.handle_tab_switching();
    self.handle_navigation();
    self.handle_selection();
    self.handle_favorite_toggle();
    self.handle_quicklist_toggle();
}

fn void Manager.handle_search_input(&self) {
    self.handle_text_input();
    self.handle_navigation();
    self.handle_selection();
}

fn void Manager.handle_inspect_input(&self) {
    // Page scrolling with Ctrl+D and Ctrl+U
    bool ctrl = rl::isKeyDown(rl::KEY_LEFT_CONTROL) || rl::isKeyDown(rl::KEY_RIGHT_CONTROL);
    if (ctrl && rl::isKeyPressed(rl::KEY_D)) {
        self.ui.scroll_pos.y += 200.0f;
        return;
    }
    if (ctrl && rl::isKeyPressed(rl::KEY_U)) {
        self.ui.scroll_pos.y -= 200.0f;
        if (self.ui.scroll_pos.y < 0) self.ui.scroll_pos.y = 0;
        return;
    }
    
    // Vertical scrolling
    if (rl::isKeyDown(rl::KEY_DOWN) || rl::isKeyDown(rl::KEY_J)) {
        self.ui.scroll_pos.y += 10.0f;
    }
    if (rl::isKeyDown(rl::KEY_UP) || rl::isKeyDown(rl::KEY_K)) {
        self.ui.scroll_pos.y -= 10.0f;
        if (self.ui.scroll_pos.y < 0) self.ui.scroll_pos.y = 0;
    }
    
    // Horizontal scrolling
    if (rl::isKeyDown(rl::KEY_RIGHT) || rl::isKeyDown(rl::KEY_L)) {
        self.ui.scroll_pos.x += 10.0f;
    }
    if (rl::isKeyDown(rl::KEY_LEFT) || rl::isKeyDown(rl::KEY_H)) {
        self.ui.scroll_pos.x -= 10.0f;
        if (self.ui.scroll_pos.x < 0) self.ui.scroll_pos.x = 0;
    }
    
    // Mouse wheel scrolling
    float wheel = rl::getMouseWheelMove();
    if (wheel != 0) {
        self.ui.scroll_pos.y -= wheel * 30.0f;
        if (self.ui.scroll_pos.y < 0) self.ui.scroll_pos.y = 0;
    }
}

fn void Manager.handle_help_input(&self) {
    // Page scrolling with Ctrl+D and Ctrl+U
    bool ctrl = rl::isKeyDown(rl::KEY_LEFT_CONTROL) || rl::isKeyDown(rl::KEY_RIGHT_CONTROL);
    if (ctrl && rl::isKeyPressed(rl::KEY_D)) {
        self.ui.scroll_pos.y += 200.0f;
        return;
    }
    if (ctrl && rl::isKeyPressed(rl::KEY_U)) {
        self.ui.scroll_pos.y -= 200.0f;
        if (self.ui.scroll_pos.y < 0) self.ui.scroll_pos.y = 0;
        return;
    }
    
    // Vertical scrolling
    if (rl::isKeyDown(rl::KEY_DOWN) || rl::isKeyDown(rl::KEY_J)) {
        self.ui.scroll_pos.y += 10.0f;
    }
    if (rl::isKeyDown(rl::KEY_UP) || rl::isKeyDown(rl::KEY_K)) {
        self.ui.scroll_pos.y -= 10.0f;
        if (self.ui.scroll_pos.y < 0) self.ui.scroll_pos.y = 0;
    }
    
    // Mouse wheel scrolling
    float wheel = rl::getMouseWheelMove();
    if (wheel != 0) {
        self.ui.scroll_pos.y -= wheel * 30.0f;
        if (self.ui.scroll_pos.y < 0) self.ui.scroll_pos.y = 0;
    }
}

fn void Manager.add(&self, String text, String source_app) {
    StoredEntry entry = {
        .text = text.copy(mem),
        .timestamp = datetime::now().to_local(),
        .hits = 1,
        .source_app = source_app.copy(mem),
    };

    self.history.push(entry);
    storage::save_to_file(&self.config, &self.history);
}

fn void Manager.remove_selected(&self) {
    if (self.history.len() == 0) return;
    
    int actual_idx = self.get_actual_index_from_visual(self.ui.selected_idx);
    if (actual_idx < 0) return;
    
    StoredEntry? entry = self.history.get(actual_idx);
    if (catch entry) return;
    self.history.remove_at(actual_idx);
    entry.text.free(mem);
    
    // Adjust selected index if needed
    int visible_count = self.count_visible_entries();
    if (visible_count == 0) {
        self.ui.selected_idx = 0;
    } else if (self.ui.selected_idx >= visible_count) {
        self.ui.selected_idx = visible_count - 1;
    }
    storage::save_to_file(&self.config, &self.history);
    log::info("removed clip at index %d", actual_idx);
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
    StoredEntry? cur = self.cp.get_current_clip();
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
        storage::save_to_file(&self.config, &self.history);
        return false;
    } 

    log::info("new clip saved from %s", cur.source_app);
    self.add(cur.text, cur.source_app);

    if (self.history.len() > self.history_limit) {
        if (try old = self.history.pop_first()) {
            log::info("removed clipboard history from: %s ago", datetime::now().diff_us(old.timestamp).to_nano());
            old.text.free(mem);
            storage::save_to_file(&self.config, &self.history);
        }
    }
    return true;
}

fn void Manager.render_clips(&self) {
    rl::beginDrawing();
    rl::clearBackground(ui::COLOR_BG);
    rl::setTextureFilter(self.font.texture, BILINEAR);
    self.draw_header();
    self.draw_tabs();
    self.draw_search_bar();
    self.draw_clip_list();
    self.draw_footer();
    rl::endDrawing();
}

fn void Manager.draw_header(&self) {
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
}

fn void Manager.draw_search_bar(&self) {
    if (self.ui.mode == SEARCH) {
        String search_text = self.ui.search_query.len() > 0 ? self.ui.search_query.str_view() : "Type to search...";
        ZString search_display = string::tformat_zstr("/ %s", search_text);
        rl::Vector2 search_pos = {25, 73};
        rl::Color search_color = self.ui.search_query.len() > 0 ? ui::COLOR_TITLE : ui::COLOR_FOOTER;
        rl::drawTextEx(self.font, search_display, search_pos, 18, 0f, search_color);
    }
}

fn void Manager.draw_tabs(&self) {
    float tab_y = 43;
    float tab_height = 25;
    float tab_width = 100;
    float tab_spacing = 10;
    float total_width = tab_width * 3 + tab_spacing * 2;
    float tab_x_start = (ui::SCREEN_WIDTH - total_width) / 2f;
    
    // All Clips tab
    rl::Rectangle all_tab = { tab_x_start, tab_y, tab_width, tab_height };
    rl::Color all_bg = self.ui.active_tab == ALL_CLIPS ? ui::COLOR_BODY : ui::COLOR_BG;
    rl::Color all_text = self.ui.active_tab == ALL_CLIPS ? ui::COLOR_TITLE : ui::COLOR_TEXT;
    rl::drawRectangleRounded(all_tab, 0.5, 12, all_bg);
    if (self.ui.active_tab == ALL_CLIPS) {
        rl::drawRectangleRoundedLinesEx(all_tab, 0.5, 24, 1.5, ui::COLOR_BADGE_LINE);
    }
    ZString all_txt = "All Clips".zstr_tcopy();
    rl::Vector2 all_size = rl::measureTextEx(self.font, all_txt, 16, 0);
    rl::Vector2 all_pos = {
        tab_x_start + (tab_width - all_size.x) / 2f,
        tab_y + (tab_height - all_size.y) / 2f
    };
    rl::drawTextEx(self.font, all_txt, all_pos, 16, 0f, all_text);
    
    // Favorites tab
    float fav_x = tab_x_start + tab_width + tab_spacing;
    rl::Rectangle fav_tab = { fav_x, tab_y, tab_width, tab_height };
    rl::Color fav_bg = self.ui.active_tab == FAVORITES ? ui::COLOR_BODY : ui::COLOR_BG;
    rl::Color fav_text = self.ui.active_tab == FAVORITES ? ui::COLOR_TITLE : ui::COLOR_TEXT;
    rl::drawRectangleRounded(fav_tab, 0.5, 12, fav_bg);
    if (self.ui.active_tab == FAVORITES) {
        rl::drawRectangleRoundedLinesEx(fav_tab, 0.5, 24, 1.5, ui::COLOR_BADGE_LINE);
    }
    ZString fav_txt = "Favorites".zstr_tcopy();
    rl::Vector2 fav_size = rl::measureTextEx(self.font, fav_txt, 16, 0);
    rl::Vector2 fav_pos = {
        fav_x + (tab_width - fav_size.x) / 2f,
        tab_y + (tab_height - fav_size.y) / 2f
    };
    rl::drawTextEx(self.font, fav_txt, fav_pos, 16, 0f, fav_text);
    
    // Quicklist tab
    float quick_x = fav_x + tab_width + tab_spacing;
    rl::Rectangle quick_tab = { quick_x, tab_y, tab_width, tab_height };
    rl::Color quick_bg = self.ui.active_tab == QUICKLIST ? ui::COLOR_BODY : ui::COLOR_BG;
    rl::Color quick_text = self.ui.active_tab == QUICKLIST ? ui::COLOR_TITLE : ui::COLOR_TEXT;
    rl::drawRectangleRounded(quick_tab, 0.5, 12, quick_bg);
    if (self.ui.active_tab == QUICKLIST) {
        rl::drawRectangleRoundedLinesEx(quick_tab, 0.5, 24, 1.5, ui::COLOR_BADGE_LINE);
    }
    ZString quick_txt = "Quicklist".zstr_tcopy();
    rl::Vector2 quick_size = rl::measureTextEx(self.font, quick_txt, 16, 0);
    rl::Vector2 quick_pos = {
        quick_x + (tab_width - quick_size.x) / 2f,
        tab_y + (tab_height - quick_size.y) / 2f
    };
    rl::drawTextEx(self.font, quick_txt, quick_pos, 16, 0f, quick_text);
}

fn void Manager.draw_clip_list(&self) {
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
    float search_bar_height = self.ui.mode == SEARCH ? 30 : 0;
    float tabs_height = 30;

    int visual_idx; 
    quicksort(&self.history);
    foreach (entry : self.history) {
        if (!self.is_entry_visible(entry)) {
            continue;
        }
        
        float y_pos = 50 + tabs_height + search_bar_height + ((float)visual_idx * spacing) - self.ui.scroll_pos.y;
        
        // Skip rendering items outside visible area (footer starts at ~570)
        if (y_pos < 75 || y_pos + rec_height > ui::SCREEN_HEIGHT - 40) {
            visual_idx++;
            continue;
        }
        
        bool is_selected = visual_idx == self.ui.selected_idx;

        // rectangle
        rl::Color rec_color = is_selected ? ui::COLOR_BODY : ui::COLOR_BG;
        rl::Rectangle rec = { rec_padding, y_pos, rec_width, rec_height };
        rl::drawRectangleRounded(rec: rec, roundness: 0.5, segments: 12, color: rec_color); 

        // favorite indicator
        if (entry.is_favorite) {
            rl::drawTextEx(self.font, "★".zstr_tcopy(), {(float)font_padding - 15, y_pos + font_y_offset + 3}, (float)font_size - 5, 0f, ui::COLOR_GOLD);
        }

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
        
        // quicklist number indicator (left of badge)
        if (entry.quicklist_number > 0) {
            ZString num_str = string::tformat_zstr("%d", entry.quicklist_number);
            rl::Vector2 num_size = rl::measureTextEx(self.font, num_str, 16, 0);
            float num_x = badge_x - num_size.x - 10;
            rl::drawTextEx(self.font, num_str, {num_x, y_pos + font_y_offset}, 16, 0f, ui::COLOR_PURPLE);
        }

        // timestamp footer
        if (is_selected) {
            ZString timestamp = string::tformat_zstr("%s", entry.timestamp);
            rl::Vector2 timestamp_size = rl::measureTextEx(self.font, timestamp, 16, 0);
            float timestamp_x = (ui::SCREEN_WIDTH - timestamp_size.x) - 25;
            rl::drawTextEx(self.font, timestamp, {timestamp_x, ui::SCREEN_HEIGHT - 30f}, 16, 0f, ui::COLOR_FOOTER);
        }

        visual_idx++;
    }
}

fn void Manager.draw_footer(&self) {
    ZString footer = string::tformat_zstr("h: help       q: quit");
    rl::drawTextEx(self.font, footer, {25, ui::SCREEN_HEIGHT - 30f}, 19, 0f, ui::COLOR_FOOTER);
}

fn void Manager.render_inspect(&self) {
    rl::beginDrawing();
    rl::clearBackground(ui::COLOR_BG);

    StoredEntry? selected = self.get_selected_entry();

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

        // footer with hit count, source app, and full date
        ZString footer_left = string::tformat_zstr("Copied %d times   From: %s", selected.hits, selected.source_app);
        rl::drawTextEx(self.font, footer_left, {25, ui::SCREEN_HEIGHT - 30f}, 16, 0f, ui::COLOR_FOOTER);
        ZString date_str = string::tformat_zstr("%04d-%02d-%02d %02d:%02d:%02d", 
            selected.timestamp.year, selected.timestamp.month.ordinal, selected.timestamp.day,
            selected.timestamp.hour, selected.timestamp.min, selected.timestamp.sec);
        rl::Vector2 date_size = rl::measureTextEx(self.font, date_str, 16, 0);
        float date_x = (ui::SCREEN_WIDTH - date_size.x) - 25;
        rl::drawTextEx(self.font, date_str, {date_x, ui::SCREEN_HEIGHT - 30f}, 16, 0f, ui::COLOR_FOOTER);

    }
    rl::endDrawing();
}

fn void Manager.simulate_paste(&self) {
    thread::sleep(time::ms(50)); // race condition workaround -  wait for window transition
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

fn void Manager.render_help(&self) {
    rl::beginDrawing();
    rl::clearBackground(ui::COLOR_BG);
    rl::setTextureFilter(self.font.texture, BILINEAR);
    
    // Header
    ZString header_txt = "Keyboard Shortcuts".zstr_tcopy();
    float header_font_size = 24f;
    rl::Vector2 header_size = rl::measureTextEx(self.font, header_txt, header_font_size, 0f);
    float header_x = (ui::SCREEN_WIDTH - header_size.x) / 2f;
    int header_padding = 10;
    rl::Rectangle header_rec = { 
        header_x - header_padding, 
        10 - header_padding / 2f, 
        header_size.x + header_padding * 2f, 
        header_size.y + header_padding 
    };
    rl::drawRectangleRounded(header_rec, 0.5, 12, ui::COLOR_BODY);
    rl::drawTextEx(self.font, header_txt, {header_x, 10f}, header_font_size, 0f, ui::COLOR_TITLE);
    
    // Scrollable help content area
    rl::Rectangle help_area = { 20, 50, ui::SCREEN_WIDTH - 40, ui::SCREEN_HEIGHT - 90 };
    rl::drawRectangleRounded(help_area, 0.2, 8, ui::COLOR_BODY);
    
    int padding = 20;
    rl::Vector2 scale = rl::getWindowScaleDPI();
    rl::beginScissorMode(
        x: (20 + padding) * (int)scale.x, 
        y: (50 + padding) * (int)scale.y,
        width: (ui::SCREEN_WIDTH - 40 - padding * 2) * (int)scale.x,
        height: (ui::SCREEN_HEIGHT - 90 - padding * 2) * (int)scale.y,
    );
    
    float y_pos = 50f + padding - self.ui.scroll_pos.y;
    float line_height = 28;
    float section_spacing = 15;
    float indent = 30;
    
    // Navigation section
    rl::drawTextEx(self.font, "Navigation:".zstr_tcopy(), {50, y_pos}, 20, 0f, ui::COLOR_GOLD);
    y_pos += line_height;
    rl::drawTextEx(self.font, "↑/↓ or j/k".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Navigate clips".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "Ctrl+d".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Page down".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "Ctrl+u".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Page up".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "Tab".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Switch between tabs".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height + section_spacing;
    
    // Actions section
    rl::drawTextEx(self.font, "Actions:".zstr_tcopy(), {50, y_pos}, 20, 0f, ui::COLOR_GOLD);
    y_pos += line_height;
    rl::drawTextEx(self.font, "Enter".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Select and paste clip".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "o".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Inspect full clip".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "f".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Toggle favorite".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "1-9".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Assign to quicklist slot".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "dd".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Delete clip (double-tap)".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "Delete".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Delete clip immediately".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "/".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Search clips".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height + section_spacing;
    
    // Global Shortcuts section
    rl::drawTextEx(self.font, "Global Shortcuts:".zstr_tcopy(), {50, y_pos}, 20, 0f, ui::COLOR_GOLD);
    y_pos += line_height;
    rl::drawTextEx(self.font, "Ctrl+Shift+V".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Open GhostBoard".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "Ctrl+Shift+1-9".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Paste quicklist clip".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height + section_spacing;
    
    // Tabs section
    rl::drawTextEx(self.font, "Tabs:".zstr_tcopy(), {50, y_pos}, 20, 0f, ui::COLOR_GOLD);
    y_pos += line_height;
    rl::drawTextEx(self.font, "All Clips".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "All clipboard history".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "Favorites".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Favorited clips only".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    y_pos += line_height;
    rl::drawTextEx(self.font, "Quicklist".zstr_tcopy(), {50 + indent, y_pos}, 18, 0f, ui::COLOR_PURPLE);
    rl::drawTextEx(self.font, "Numbered clips (1-9)".zstr_tcopy(), {250, y_pos}, 18, 0f, ui::COLOR_TEXT);
    
    rl::endScissorMode();
    
    // Footer
    ZString footer = string::tformat_zstr("h: help       q: quit");
    rl::drawTextEx(self.font, footer, {25, ui::SCREEN_HEIGHT - 30f}, 19, 0f, ui::COLOR_FOOTER);
    
    rl::endDrawing();
}

