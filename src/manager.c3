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

// Layout constants
const int MAX_VISIBLE_ITEMS = 16;
const int ITEM_SPACING = 30;
const int HEADER_HEIGHT = 50;
const int FOOTER_HEIGHT = 40;
const int TAB_HEIGHT = 30;

// Clip item rendering constants
const int CLIP_PADDING = 20;
const int CLIP_HEIGHT = 25;
const int CLIP_FONT_SIZE = 20;
const int CLIP_TEXT_PADDING = 25;
const int CLIP_MAX_TEXT_LENGTH = 84;
const float BADGE_WIDTH = 50;
const float FAVORITE_ICON_OFFSET = -15;
const float QUICKLIST_SPACING = 10;

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

// Helper: Check if visual index is in selection range
fn bool Manager.is_visual_selected(&self, int visual_idx) {
    if (!self.ui.visual_mode) return false;
    int min_idx = math::min(self.ui.visual_anchor, self.ui.selected_idx);
    int max_idx = math::max(self.ui.visual_anchor, self.ui.selected_idx);
    return visual_idx >= min_idx && visual_idx <= max_idx;
}

// Helper: Get count of items in visual selection
fn int Manager.get_visual_selection_count(&self) {
    if (!self.ui.visual_mode) return 0;
    int min_idx = math::min(self.ui.visual_anchor, self.ui.selected_idx);
    int max_idx = math::max(self.ui.visual_anchor, self.ui.selected_idx);
    return max_idx - min_idx + 1;
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
    const int KEY_REPEAT_INITIAL_DELAY = 20;
    const int KEY_REPEAT_DELAY = 3;
    
    int visible_count = self.count_visible_entries();
    
    // Handle G (jump to bottom)
    bool shift = rl::isKeyDown(rl::KEY_LEFT_SHIFT) || rl::isKeyDown(rl::KEY_RIGHT_SHIFT);
    if (shift && rl::isKeyPressed(rl::KEY_G)) {
        if (visible_count > 0) {
            self.ui.selected_idx = visible_count - 1;
            self.ui.scroll_pos.y = (float)math::max(0, (visible_count - MAX_VISIBLE_ITEMS) * ITEM_SPACING);
            log::info("jumped to bottom (G)");
        }
        return;
    }
    
    // Handle gg (jump to top)
    if (rl::isKeyPressed(rl::KEY_G)) {
        double current_time = rl::getTime();
        if (self.ui.g_pending && (current_time - self.ui.last_g_press_time) < 0.5) {
            // Second 'g' within 0.5 seconds - jump to top
            self.ui.selected_idx = 0;
            self.ui.scroll_pos.y = 0;
            self.ui.g_pending = false;
            log::info("jumped to top (gg)");
        } else {
            // First 'g' - mark as pending
            self.ui.g_pending = true;
            self.ui.last_g_press_time = current_time;
        }
        return;
    } else if (self.ui.g_pending) {
        // Reset if other key pressed or timeout
        double current_time = rl::getTime();
        if (current_time - self.ui.last_g_press_time > 0.5) {
            self.ui.g_pending = false;
        }
    }
    
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
    // Check for Shift+V to enter visual mode
    bool shift = rl::isKeyDown(rl::KEY_LEFT_SHIFT) || rl::isKeyDown(rl::KEY_RIGHT_SHIFT);
    if (shift && rl::isKeyPressed(rl::KEY_V)) {
        self.ui.visual_mode = !self.ui.visual_mode;
        if (self.ui.visual_mode) {
            self.ui.visual_anchor = self.ui.selected_idx;
            log::info("entered visual mode at index %d", self.ui.selected_idx);
        } else {
            log::info("exited visual mode");
        }
        return;
    }
    
    if (rl::isKeyPressed(rl::KEY_ENTER)) {
        if (self.ui.visual_mode) {
            self.paste_visual_selection();
            self.ui.visual_mode = false;
        } else {
            StoredEntry? selected = self.get_selected_entry();
            if (try selected) {
                self.cp.set(selected.text);
                self.ui.mode = HIDE;
                rl::setWindowState(WINDOW_HIDDEN);
                ui::move_app_to_background();
                self.simulate_paste();
            }
        }
    }
    
    // Double-tap 'd' to delete (vim-style dd) - but not with Ctrl
    bool ctrl = rl::isKeyDown(rl::KEY_LEFT_CONTROL) || rl::isKeyDown(rl::KEY_RIGHT_CONTROL);
    if (rl::isKeyPressed(rl::KEY_D) && !ctrl) {
        if (self.ui.visual_mode) {
            // In visual mode, delete selected items immediately
            self.delete_visual_selection();
            self.ui.visual_mode = false;
            return;
        }
        
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
            if (self.ui.visual_mode) {
                self.delete_visual_selection();
                self.ui.visual_mode = false;
            } else {
                self.remove_selected();
            }
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
        // Exit visual mode if active
        if (self.ui.visual_mode) {
            self.ui.visual_mode = false;
            log::info("exited visual mode");
            return;
        }
        
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
    if ((rl::isKeyPressed(rl::KEY_O) || rl::isKeyPressed(rl::KEY_I)) && self.history.len() > 0) {
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

fn void Manager.delete_visual_selection(&self) {
    if (!self.ui.visual_mode || self.history.len() == 0) return;
    
    int min_idx = math::min(self.ui.visual_anchor, self.ui.selected_idx);
    int max_idx = math::max(self.ui.visual_anchor, self.ui.selected_idx);
    
    // Collect actual indices to delete (in reverse order to avoid index shifting)
    List{int} to_delete;
    for (int visual_idx = max_idx; visual_idx >= min_idx; visual_idx--) {
        int actual_idx = self.get_actual_index_from_visual(visual_idx);
        if (actual_idx >= 0) {
            to_delete.push(actual_idx);
        }
    }
    
    // Delete in reverse order
    foreach (actual_idx : to_delete) {
        StoredEntry? entry = self.history.get(actual_idx);
        if (catch entry) continue;
        self.history.remove_at(actual_idx);
        entry.text.free(mem);
    }
    
    // Adjust selection
    int visible_count = self.count_visible_entries();
    if (visible_count == 0) {
        self.ui.selected_idx = 0;
    } else if (min_idx >= visible_count) {
        self.ui.selected_idx = visible_count - 1;
    } else {
        self.ui.selected_idx = min_idx;
    }
    
    storage::save_to_file(&self.config, &self.history);
    log::info("deleted %d clips from visual selection", to_delete.len());
}

fn void Manager.paste_visual_selection(&self) {
    if (!self.ui.visual_mode || self.history.len() == 0) return;
    
    int min_idx = math::min(self.ui.visual_anchor, self.ui.selected_idx);
    int max_idx = math::max(self.ui.visual_anchor, self.ui.selected_idx);
    
    // Collect all selected clip texts
    DString combined;
    for (int visual_idx = min_idx; visual_idx <= max_idx; visual_idx++) {
        StoredEntry? entry = self.get_entry_at_visual_index(visual_idx);
        if (try entry) {
            if (combined.len() > 0) {
                combined.append("\n");
            }
            combined.append(entry.text);
        }
    }
    
    if (combined.len() > 0) {
        self.cp.set(combined.str_view());
        self.ui.mode = HIDE;
        rl::setWindowState(WINDOW_HIDDEN);
        ui::move_app_to_background();
        self.simulate_paste();
        log::info("pasted %d clips from visual selection", max_idx - min_idx + 1);
    }
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

fn String Manager.truncate_clip_text(&self, String text) {
    String result = text;
    if (try newline_pos = result.index_of_char('\n')) {
        result = result[..newline_pos];
    }
    if (result.len > CLIP_MAX_TEXT_LENGTH) {
        result = result[..CLIP_MAX_TEXT_LENGTH];
    }
    return result;
}

fn void Manager.draw_clip_background(&self, float y_pos, bool is_selected, bool is_visual_selected) {
    int rec_width = ui::SCREEN_WIDTH - (CLIP_PADDING * 2);
    rl::Color rec_color;
    if (is_visual_selected) {
        rec_color = ui::COLOR_PURPLE;  // Visual selection color
    } else if (is_selected) {
        rec_color = ui::COLOR_BODY;
    } else {
        rec_color = ui::COLOR_BG;
    }
    rl::Rectangle rec = { CLIP_PADDING, y_pos, rec_width, CLIP_HEIGHT };
    rl::drawRectangleRounded(rec: rec, roundness: 0.5, segments: 12, color: rec_color);
}

fn void Manager.draw_favorite_indicator(&self, float y_pos, bool is_favorite) {
    if (!is_favorite) return;
    float font_y_offset = (CLIP_HEIGHT - (float)CLIP_FONT_SIZE) / 2f;
    rl::drawTextEx(
        self.font, 
        "★".zstr_tcopy(), 
        {(float)CLIP_TEXT_PADDING + FAVORITE_ICON_OFFSET, y_pos + font_y_offset + 3}, 
        (float)CLIP_FONT_SIZE - 5, 
        0f, 
        ui::COLOR_GOLD
    );
}

fn void Manager.draw_clip_text(&self, String text, float y_pos, bool is_selected) {
    String display_text = self.truncate_clip_text(text);
    float font_y_offset = (CLIP_HEIGHT - (float)CLIP_FONT_SIZE) / 2f;
    rl::Color text_color = is_selected ? ui::COLOR_TITLE : ui::COLOR_TEXT;
    rl::drawTextEx(
        self.font, 
        display_text.zstr_tcopy(), 
        {CLIP_TEXT_PADDING, y_pos + font_y_offset}, 
        CLIP_FONT_SIZE, 
        0f, 
        text_color
    );
}

fn void Manager.draw_clip_badge(&self, int text_length, float y_pos, bool is_selected) {
    int rec_width = ui::SCREEN_WIDTH - (CLIP_PADDING * 2);
    float badge_x = (float)CLIP_PADDING + rec_width - BADGE_WIDTH;
    float badge_y = y_pos;
    
    ZString count_str = string::tformat_zstr("%d", text_length);
    rl::Color badge_bg = ui::COLOR_BODY;
    rl::Color badge_border = is_selected ? ui::COLOR_BADGE_LINE : ui::COLOR_BODY;
    
    rl::Rectangle badge_rec = { badge_x, badge_y, BADGE_WIDTH, CLIP_HEIGHT };
    rl::drawRectangleRounded(rec: badge_rec, roundness: 0.5, segments: 12, color: badge_bg);
    rl::drawRectangleRoundedLinesEx(badge_rec, 0.5, 24, 1.0, badge_border);
    
    rl::Vector2 count_size = rl::measureTextEx(self.font, count_str, 12, 0);
    rl::Vector2 count_pos = {
        badge_x + (BADGE_WIDTH - count_size.x) / 2f,
        badge_y + (CLIP_HEIGHT - count_size.y) / 2f,
    };
    rl::drawTextEx(self.font, count_str, count_pos, 14, 0, ui::COLOR_BADGE_TEXT);
}

fn void Manager.draw_quicklist_number(&self, int quicklist_number, float y_pos) {
    if (quicklist_number == 0) return;
    
    int rec_width = ui::SCREEN_WIDTH - (CLIP_PADDING * 2);
    float badge_x = (float)CLIP_PADDING + rec_width - BADGE_WIDTH;
    float font_y_offset = (CLIP_HEIGHT - (float)CLIP_FONT_SIZE) / 2f;
    
    ZString num_str = string::tformat_zstr("%d", quicklist_number);
    rl::Vector2 num_size = rl::measureTextEx(self.font, num_str, 16, 0);
    float num_x = badge_x - num_size.x - QUICKLIST_SPACING;
    rl::drawTextEx(self.font, num_str, {num_x, y_pos + font_y_offset}, 16, 0f, ui::COLOR_PURPLE);
}

fn void Manager.draw_clip_list(&self) {
    float search_bar_height = self.ui.mode == SEARCH ? 30 : 0;
    float content_start = HEADER_HEIGHT + TAB_HEIGHT + search_bar_height;
    
    int visual_idx = 0;
    quicksort(&self.history);
    
    foreach (entry : self.history) {
        if (!self.is_entry_visible(entry)) {
            continue;
        }
        
        float y_pos = content_start + ((float)visual_idx * ITEM_SPACING) - self.ui.scroll_pos.y;
        bool is_selected = visual_idx == self.ui.selected_idx;
        bool is_visual_selected = self.is_visual_selected(visual_idx);
        
        // Skip rendering items outside visible area (but still increment visual_idx)
        float visible_area_start = content_start;
        float visible_area_end = ui::SCREEN_HEIGHT - FOOTER_HEIGHT;
        if (y_pos + CLIP_HEIGHT < visible_area_start || y_pos > visible_area_end) {
            visual_idx++;
            continue;
        }
        
        self.draw_clip_background(y_pos, is_selected, is_visual_selected);
        self.draw_favorite_indicator(y_pos, entry.is_favorite);
        self.draw_clip_text(entry.text, y_pos, is_selected);
        self.draw_clip_badge((int)entry.text.len, y_pos, is_selected);
        self.draw_quicklist_number(entry.quicklist_number, y_pos);
        
        // Timestamp in footer for selected item
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
    if (self.ui.visual_mode) {
        int count = self.get_visual_selection_count();
        ZString footer = string::tformat_zstr("-- VISUAL --  %d clip%s selected       q: exit visual", count, count == 1 ? "" : "s");
        rl::drawTextEx(self.font, footer, {25, ui::SCREEN_HEIGHT - 30f}, 19, 0f, ui::COLOR_PURPLE);
    } else {
        ZString footer = string::tformat_zstr("h: help       q: quit");
        rl::drawTextEx(self.font, footer, {25, ui::SCREEN_HEIGHT - 30f}, 19, 0f, ui::COLOR_FOOTER);
    }
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

struct HelpItem {
    ZString key;
    ZString description;
}

struct HelpSection {
    ZString title;
    List{HelpItem} items;
}

fn List{HelpSection} get_help_sections() {
    List{HelpSection} sections;

    List{HelpItem} nav_items;
    nav_items.push_all({
        {"↑/↓ or j/k", "Navigate clips"},
        {"Ctrl+d", "Page down"},
        {"Ctrl+u", "Page up"},
        {"gg", "Jump to top"},
        {"G", "Jump to bottom"},
        {"Tab", "Switch between tabs"},
    });
    sections.push({.title = "Navigation:", .items = nav_items});
    
    List{HelpItem} action_items;
    action_items.push_all({
        {"Enter", "Select and paste clip"},
        {"o or i", "Inspect full clip"},
        {"f", "Toggle favorite"},
        {"1-9", "Assign to quicklist slot"},
        {"dd", "Delete clip (double-tap)"},
        {"Delete", "Delete clip immediately"},
        {"/", "Search clips"},
    });
    sections.push({.title = "Actions:", .items = action_items});
    
    List{HelpItem} visual_items;
    visual_items.push_all({
        {"Shift+V", "Enter visual selection"},
        {"j/k", "Extend selection"},
        {"Enter", "Paste all selected"},
        {"d or Delete", "Delete all selected"},
        {"q or Esc", "Exit visual mode"},
    });
    sections.push({.title = "Visual Mode:", .items = visual_items});
    
    List{HelpItem} global_items;
    global_items.push_all({
        {"Ctrl+Shift+V", "Open GhostBoard"},
        {"Ctrl+Shift+1-9", "Paste quicklist clip"},
    });
    sections.push({.title = "Global Shortcuts:", .items = global_items});
    
    List{HelpItem} tab_items;
    tab_items.push_all({
        {"All Clips", "All clipboard history"},
        {"Favorites", "Favorited clips only"},
        {"Quicklist", "Numbered clips (1-9)"},
    });
    sections.push({.title = "Tabs:", .items = tab_items});
    
    return sections;
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
    float key_x = 50 + indent;
    float desc_x = 250;
    
    List{HelpSection} sections = get_help_sections();
    foreach (section : sections) {
        rl::drawTextEx(self.font, section.title, {50, y_pos}, 20, 0f, ui::COLOR_GOLD);
        y_pos += line_height;
        
        foreach (item : section.items) {
            rl::drawTextEx(self.font, item.key, {key_x, y_pos}, 18, 0f, ui::COLOR_PURPLE);
            rl::drawTextEx(self.font, item.description, {desc_x, y_pos}, 18, 0f, ui::COLOR_TEXT);
            y_pos += line_height;
        }
        
        y_pos += section_spacing;
    }
    
    rl::endScissorMode();
    
    // Footer
    ZString footer = string::tformat_zstr("h: help       q: quit");
    rl::drawTextEx(self.font, footer, {25, ui::SCREEN_HEIGHT - 30f}, 19, 0f, ui::COLOR_FOOTER);
    
    rl::endDrawing();
}

