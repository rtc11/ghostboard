module clipboard;

import std::collections::list;
import std::core::log, logger;
import std::os::macos::objc, objc;
import std::time;

faultdef EMPTY, MISSING;

struct Clipboard {
    ObjcId instance;
    ObjcSelector items_sel;
    ObjcSelector first_obj_sel;
    ObjcSelector types_sel;
}

struct StoredEntry {
    String text;
    TzDateTime timestamp;
    usz hits;
    bool is_favorite;
    int quicklist_number;
    String source_app;
    String note;
    List{String} file_paths;
    bool is_file;
}

// Sort by hits
fn bool StoredEntry.less(&self, StoredEntry other) => self.hits > other.hits;

fn bool? Clipboard.is_safe(&self) {
    @pool() {
        ObjcId items_array = objc::msg_send(self.instance, SendVoid, "pasteboardItems");
        log::debug("pasteboardItems returned: %p", items_array);
        
        if (items_array == null) {
            log::debug("pasteboardItems is null");
            return EMPTY?;
        }
        
        int count = (int)objc::msg_send(items_array, GetInt, "count");
        log::debug("pasteboardItems count: %d", count);
        
        ObjcId item = objc::msg_send(items_array, SendVoid, "firstObject");
        log::debug("firstObject returned: %p", item);
        
        if (item == null) {
            log::debug("firstObject is null, clipboard appears empty");
            return EMPTY?;
        }

        ObjcId types_array = objc::msg_send(item, SendVoid, "types");

        ObjcId concealed_key = objc::nsstr("org.nspasteboard.ConcealedType");
        bool concealed = (bool)objc::msg_send(types_array, GetBool_Id, "containsObject:", concealed_key);
        return !concealed;
    };
}

fn void Clipboard.set(&self, String text) {
    @pool() {
        objc::msg_send(self.instance, SendVoid, "clearContents");
        ObjcId ns_str = objc::nsstr(text.zstr_tcopy());
        ObjcId type_str = objc::nsstr("public.utf8-plain-text");
        objc::msg_send(self.instance, GetBool_IdId, "setString:forType:", ns_str, type_str);
    };
}

fn void Clipboard.set_files(&self, List{String} file_paths) {
    @pool() {
        objc::msg_send(self.instance, SendVoid, "clearContents");
        
        // Create array of file URLs
        ObjcClass ns_array_class = objc::getClass("NSMutableArray");
        ObjcId file_urls = objc::msg_send(ns_array_class, SendVoid, "array");
        
        ObjcClass nsurl_class = objc::getClass("NSURL");
        foreach (path : file_paths) {
            ObjcId path_str = objc::nsstr(path.zstr_tcopy());
            ObjcId file_url = objc::msg_send(nsurl_class, GetId_Id, "fileURLWithPath:", path_str);
            if (file_url != null) {
                objc::msg_send(file_urls, SendId, "addObject:", file_url);
            }
        }
        
        // Write file URLs to pasteboard
        ObjcId type_str = objc::nsstr("public.file-url");
        objc::msg_send(self.instance, SendId, "writeObjects:", file_urls);
        
        // Also write as plain text for terminal support
        DString joined = dstring::temp_with_capacity(1024);
        foreach (i, path : file_paths) {
            if (i > 0) joined.append_char('\n');
            joined.append(path);
        }
        ObjcId text_str = objc::nsstr(joined.zstr_view());
        ObjcId text_type = objc::nsstr("public.utf8-plain-text");
        objc::msg_send(self.instance, GetBool_IdId, "setString:forType:", text_str, text_type);
    };
}

fn StoredEntry? Clipboard.get_current_clip(&self) {
    @pool() {
        // Try to get file URLs
        ObjcId items_array = objc::msg_send(self.instance, SendVoid, "pasteboardItems");
        if (items_array != null) {
            ulong items_count = (ulong)objc::msg_send(items_array, GetULong, "count");
            if (items_count == 0) return EMPTY?;
            
            ObjcId item = objc::msg_send(items_array, SendVoid, "firstObject");
            if (item != null) {
                ObjcId types_array = objc::msg_send(item, SendVoid, "types");
                ObjcId file_url_type_check = objc::nsstr("public.file-url");
                bool has_files = (bool)objc::msg_send(types_array, GetBool_Id, "containsObject:", file_url_type_check);
                
                if (has_files) {
                    // Get file URLs
                    List{String} file_paths;
                    file_paths.init(mem);
                    
                    ulong count = (ulong)objc::msg_send(items_array, GetULong, "count");
                    for (ulong i = 0; i < count; i++) {
                        ObjcId paste_item = objc::msg_send(items_array, GetId_Usz, "objectAtIndex:", (usz)i);
                        ObjcId url_data = objc::msg_send(paste_item, GetId_Id, "dataForType:", file_url_type_check);
                        if (url_data != null) {
                            ObjcClass nsstring_class = objc::getClass("NSString");
                            ObjcId url_str_alloc = objc::msg_send(nsstring_class, GetId, "alloc");
                            ObjcId url_str = objc::msg_send(url_str_alloc, GetId_IdUsz, "initWithData:encoding:", url_data, 4);
                            
                            ObjcId file_url = null;
                            if (url_str != null) {
                                ObjcClass nsurl_class = objc::getClass("NSURL");
                                file_url = objc::msg_send(nsurl_class, GetId_Id, "URLWithString:", url_str);
                            }
                            if (file_url != null) {
                                ObjcId path_ns = objc::msg_send(file_url, SendVoid, "path");
                                if (path_ns != null) {
                                    ZString path_zstr = (ZString)objc::msg_send(path_ns, SendVoid, "UTF8String");
                                    if (path_zstr != null) {
                                        file_paths.push(path_zstr.copy(mem));
                                    }
                                }
                            }
                        }
                    }
                    
                    if (file_paths.len() > 0) {
                        log::info("Detected %d file(s) in clipboard", file_paths.len());
                        foreach (i, path : file_paths) {
                            log::info("  File %d: %s", i, path);
                        }
                        
                        // Get frontmost application
                        ObjcId workspace = objc::msg_send(objc::getClass("NSWorkspace"), SendVoid, "sharedWorkspace");
                        ObjcId frontmost_app = objc::msg_send(workspace, SendVoid, "frontmostApplication");
                        ObjcId app_name_ns = objc::msg_send(frontmost_app, SendVoid, "localizedName");
                        ZString app_name_zstr = (ZString)objc::msg_send(app_name_ns, SendVoid, "UTF8String");
                        String source_app = app_name_zstr != null ? app_name_zstr.str_view().copy(mem) : "Unknown".copy(mem);
                        
                        // Create display text
                        DString display_text = dstring::temp_with_capacity(1024);
                        foreach (i, path : file_paths) {
                            if (i > 0) display_text.append_char('\n');
                            display_text.append(path);
                        }
                        
                        log::info("Created file entry with is_file=true, file_paths.len=%d", file_paths.len());
                        return {
                            .text = display_text.str_view().copy(mem),
                            .timestamp = datetime::now().to_local(),
                            .source_app = source_app,
                            .file_paths = file_paths,
                            .is_file = true,
                        };
                    }
                }
            }
        }
        
        // Fall back to text
        ObjcId type_str = objc::nsstr("public.utf8-plain-text");
        ObjcId ns_str = objc::msg_send(self.instance, GetId_Id, "stringForType:", type_str);
        if (ns_str == null) return EMPTY?;
        ZString zstr = (ZString)objc::msg_send(ns_str, SendVoid, "UTF8String");
        
        // Get frontmost application
        ObjcId workspace = objc::msg_send(objc::getClass("NSWorkspace"), SendVoid, "sharedWorkspace");
        ObjcId frontmost_app = objc::msg_send(workspace, SendVoid, "frontmostApplication");
        ObjcId app_name_ns = objc::msg_send(frontmost_app, SendVoid, "localizedName");
        ZString app_name_zstr = (ZString)objc::msg_send(app_name_ns, SendVoid, "UTF8String");
        String source_app = app_name_zstr != null ? app_name_zstr.str_view().copy(mem) : "Unknown".copy(mem);
        
        return {
            .text = zstr.copy(mem),
            .timestamp = datetime::now().to_local(),
            .source_app = source_app,
        };
    };
}

fn usz? List{StoredEntry}.findTextIndex(&self, String text) {
    foreach(i, entry: self) {
        if (entry.text == text) return i;
    }
    return MISSING?;
}

