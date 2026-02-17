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

struct Entry {
    String text;
    TzDateTime timestamp;
    usz hits;
}

// Sort by hits
fn bool Entry.less(&self, Entry other) => self.hits > other.hits;

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


fn Entry? Clipboard.get_current_clip(&self) {
    @pool() {
        ObjcId type_str = objc::nsstr("public.utf8-plain-text");
        ObjcId ns_str = objc::msg_send(self.instance, GetId_Id, "stringForType:", type_str);
        if (ns_str == null) return EMPTY?;
        ZString zstr = (ZString)objc::msg_send(ns_str, SendVoid, "UTF8String");
        return {
            .text = zstr.copy(mem),
            .timestamp = datetime::now().to_local(),
        };
    };
}

fn usz? List{Entry}.findTextIndex(&self, String text) {
    foreach(i, entry: self) {
        if (entry.text == text) return i;
    }
    return MISSING?;
}

