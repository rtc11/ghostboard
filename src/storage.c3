module storage;
import clipboard, config;
import std::collections::list;
import std::core::log, logger;
import std::io;
import std::os::env;
import std::time;

fn String get_path(Config* config) {
    String? home = env::tget_var("HOME");
    if (catch home) return config.storage_file;
    String dir_path = string::tformat("%s/%s", home, config.config_dir);
    io::path::mkdir(dir_path, true)!!;
    return string::tformat("%s/%s", dir_path, config.storage_file);
}

fn void load_from_file(Config* config, List{StoredEntry}* history) {
    String path = get_path(config);
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
        
        bool is_favorite;
        if (catch io::read_any(&file, &is_favorite)) break;
        
        int quicklist_number;
        if (catch io::read_any(&file, &quicklist_number)) break;
        
        usz source_app_len;
        if (catch io::read_any(&file, &source_app_len)) break;
        
        char[] source_app_buffer = mem::alloc_array(char, source_app_len);
        if (catch io::read_all(&file, source_app_buffer)) {
            mem::free(source_app_buffer);
            break;
        }
        String source_app = ((String)source_app_buffer).copy(mem);
        mem::free(source_app_buffer);
        
        usz text_len;
        if (catch io::read_any(&file, &text_len)) break;
        
        char[] buffer = mem::alloc_array(char, text_len);
        if (catch io::read_all(&file, buffer)) {
            mem::free(buffer);
            break;
        }
        
        // Read note (new field with presence flag for backward compatibility)
        String note = "".copy(mem);
        bool has_note = false;
        if (try io::read_any(&file, &has_note) && has_note) {
            usz note_len;
            if (try io::read_any(&file, &note_len)) {
                if (note_len > 0 && note_len < 10000) {  // Sanity check
                    char[] note_buffer = mem::alloc_array(char, note_len);
                    if (try io::read_all(&file, note_buffer)) {
                        note = ((String)note_buffer).copy(mem);
                    }
                    mem::free(note_buffer);
                }
            }
        }
        
        StoredEntry entry = {
            .text = ((String)buffer).copy(mem),
            .timestamp = datetime::from_time_tz((Time)timestamp, gmt_offset),
            .hits = hits,
            .is_favorite = is_favorite,
            .quicklist_number = quicklist_number,
            .source_app = source_app,
            .note = note,
        };
        history.push(entry);
        mem::free(buffer);
    }
    
    log::info("loaded %d clips from storage", history.len());
}

fn void save_to_file(Config* config, List{StoredEntry}* history) {
    String path = get_path(config);
    File? file = file::open(path, "wb");
    if (catch file) {
        log::error("failed to open file for writing: %s", path);
        return;
    }
    defer (void)file.close();
    
    foreach (entry: history) {
        Time timestamp = entry.timestamp.time;
        io::write_any(&file, &timestamp)!!;
        int gmt_offset = entry.timestamp.gmt_offset;
        io::write_any(&file, &gmt_offset)!!;
        usz hits = entry.hits;
        io::write_any(&file, &hits)!!;
        bool is_favorite = entry.is_favorite;
        io::write_any(&file, &is_favorite)!!;
        int quicklist_number = entry.quicklist_number;
        io::write_any(&file, &quicklist_number)!!;
        usz source_app_len = entry.source_app.len;
        io::write_any(&file, &source_app_len)!!;
        io::write_all(&file, entry.source_app)!!;
        usz text_len = entry.text.len;
        io::write_any(&file, &text_len)!!;
        io::write_all(&file, entry.text)!!;
        
        // Write note with presence flag for backward compatibility
        bool has_note = entry.note.len > 0;
        io::write_any(&file, &has_note)!!;
        if (has_note) {
            usz note_len = entry.note.len;
            io::write_any(&file, &note_len)!!;
            io::write_all(&file, entry.note)!!;
        }
    }
    log::info("saved %d clips to storage", history.len());
}

