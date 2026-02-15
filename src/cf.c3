// CORE FOUNDATION
module cf;
extern fn void release(void* obj) @cname("CFRelease");
extern fn void* runLoopGetCurrent() @cname("CFRunLoopGetCurrent");
extern fn void runLoopAddSource(void* rl, void* source, void* mode) @cname("CFRunLoopAddSource");
extern fn void* machPortCreateRunLoopSource(void* allocator, void* tap, int order) @cname("CFMachPortCreateRunLoopSource");
extern const void* RUN_LOOP_COMMON_MODES @cname("kCFRunLoopCommonModes");

