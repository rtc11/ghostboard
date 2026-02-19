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
        
        usz text_len;
        if (catch io::read_any(&file, &text_len)) break;
        
        char[] buffer = mem::alloc_array(char, text_len);
        if (catch io::read_all(&file, buffer)) {
            mem::free(buffer);
            break;
        }
        
        StoredEntry entry = {
            .text = ((String)buffer).copy(mem),
            .timestamp = datetime::from_time_tz((Time)timestamp, gmt_offset),
            .hits = hits,
            .is_favorite = is_favorite,
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
        usz text_len = entry.text.len;
        io::write_any(&file, &text_len)!!;
        io::write_all(&file, entry.text)!!;
    }
}

