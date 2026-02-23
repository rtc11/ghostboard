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
        
        // Read file paths (new field with presence flag)
        List{String} file_paths;
        file_paths.tinit();
        bool is_file = false;
        if (try io::read_any(&file, &is_file) && is_file) {
            usz file_count;
            if (try io::read_any(&file, &file_count)) {
                for (usz i = 0; i < file_count && i < 1000; i++) {  // Sanity check
                    usz path_len;
                    if (try io::read_any(&file, &path_len)) {
                        if (path_len > 0 && path_len < 10000) {
                            char[] path_buffer = mem::alloc_array(char, path_len);
                            if (try io::read_all(&file, path_buffer)) {
                                file_paths.push(((String)path_buffer).copy(mem));
                            }
                            mem::free(path_buffer);
                        }
                    }
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
            // .file_paths = file_paths.array_view().copy(mem),
            .file_paths = file_paths,
            .is_file = is_file,
        };
        log::info("Loaded entry: is_file=%s, file_paths.len=%d, text=%s", is_file, file_paths.len(), entry.text[:entry.text.len < 50 ? entry.text.len : 50]);
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
        log::debug("Saving entry: is_file=%s, file_paths.len=%d", entry.is_file, entry.file_paths.len());
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
        
        // Write file paths with presence flag
        bool is_file = entry.is_file;
        io::write_any(&file, &is_file)!!;
        if (is_file) {
            usz file_count = entry.file_paths.len();
            io::write_any(&file, &file_count)!!;
            foreach (file_path : entry.file_paths) {
                usz path_len = file_path.len;
                io::write_any(&file, &path_len)!!;
                io::write_all(&file, file_path)!!;
            }
        }
    }
    log::debug("saved %d clips to storage", history.len());
}

fn void cleanup_expired_clips(Config* config, List{StoredEntry}* history) {
    DateTime now = datetime::now();
    int removed_count = 0;
    
    for (int i = (int)((usz)history.len() - 1); i >= 0; i--) {
        StoredEntry* entry = history.get_ref(i);
        if (entry.is_favorite) continue;
        double age_seconds = now.diff_sec(entry.timestamp);
        int age_days = (int)(age_seconds / 86400);
        int expire_days = entry.hits <= 1 ? config.expire_unused_days : config.expire_used_days;
        
        if (age_days > expire_days) {
            log::info("Removing expired clip (age: %d days, hits: %d): %.50s...", age_days, entry.hits, entry.text);
            history.remove_at(i);
            removed_count++;
        }
    }
    
    if (removed_count > 0) {
        log::info("Cleanup complete: removed %d expired clips", removed_count);
    }
}

