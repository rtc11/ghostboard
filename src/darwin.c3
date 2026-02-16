/**
* Objective C bindings
*/
module objc @if(env::DARWIN);

import std::os::macos::objc;

extern fn void register_class_pair(ObjcClass cls) @cname("objc_registerClassPair");

alias GetInt        = fn int   (ObjcId, ObjcSelector);
alias GetId         = fn ObjcId(ObjcId, ObjcSelector);
alias GetId_Id      = fn ObjcId(ObjcId, ObjcSelector, ObjcId);
alias SendId        = fn void  (ObjcId, ObjcSelector, ObjcId);
alias GetId_str     = fn ObjcId(ObjcId, ObjcSelector, ZString);
alias GetBool_Id    = fn bool  (ObjcId, ObjcSelector, ObjcId);
alias GetId_double  = fn ObjcId(ObjcId, ObjcSelector, double);
alias SendBool      = fn void  (ObjcId, ObjcSelector, bool);
alias GetBool_IdId  = fn bool  (ObjcId, ObjcSelector, ObjcId, ObjcId);
alias SendUsz       = fn void  (ObjcId, ObjcSelector, usz);
alias GetId_IdSelId = fn ObjcId(ObjcId, ObjcSelector, ObjcId, ObjcSelector, ObjcId);

/**
* Core Foundation
*/
module cf @if(env::DARWIN);
extern fn void release(void* obj) @cname("CFRelease");
extern fn void* runLoopGetCurrent() @cname("CFRunLoopGetCurrent");
extern fn void runLoopAddSource(void* rl, void* source, void* mode) @cname("CFRunLoopAddSource");
extern fn void* machPortCreateRunLoopSource(void* allocator, void* tap, int order) @cname("CFMachPortCreateRunLoopSource");
extern const void* RUN_LOOP_COMMON_MODES @cname("kCFRunLoopCommonModes");

/**
* Core Graphics
*/
module cg @if(env::DARWIN);
import std::io;
import raylib5;
import std::os::macos::objc;

const uint COLOR_SPACE_MODEL_RGB = 1; 
const uint TXT_ALIGNMENT_LEFT = 0;
const ushort KEY_V = 0x09;
const ulong FLAG_CMD_KEY = (1 << 20);
const double[6] AFFINE_TRANSFORM_IDENTITY = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0};

alias EventTrapCallback = fn void*(void* proxy, int type, void* event, void* refcon);

struct Rect {
    double x;
    double y;
    double width;
    double height;
}

extern fn void* eventSourceCreate(int state) @cname("CGEventSourceCreate");
extern fn void* eventCreateKeyboardEvent(void* source, ushort virtualKey, bool keyDown) @cname("CGEventCreateKeyboardEvent");
extern fn void eventSetFlags(void* event, ulong flags) @cname("CGEventSetFlags");
extern fn void eventPost(int tap, void* event) @cname("CGEventPost");
extern fn void* eventTapCreate(int tap, int place, int options, ulong mask, EventTrapCallback callback, void* user_info) @cname("CGEventTapCreate");
extern fn void* eventTapCreateForPSN(void* psn, int place, int options, ulong mask, void* callback, void* userInfo) @cname("CGEventTapCreateForPSN");
extern fn bool eventSourceKeyState(int state, ushort key) @cname("CGEventSourceKeyState");
extern fn void eventTapEnable(void* tap, bool enable) @cname("CGEventTapEnable");
extern fn ulong eventGetFlags(void* event) @cname("CGEventGetFlags");
extern fn long eventGetIntegerValueField(void* event, int field) @cname("CGEventGetIntegerValueField");
extern fn void* colorSpaceCreateDeviceRGB() @cname("CGColorSpaceCreateDeviceRGB");
extern fn void colorSpaceRelease(void* space) @cname("CGColorSpaceRelease");
extern fn void* bitmapContextCreate(void* data, usz width, usz height, usz bitsPerComponent, usz bytesPerRow, void* space, uint bitmapInfo) @cname("CGBitmapContextCreate");
extern fn void contextRelease(void* c) @cname("CGContextRelease");
extern fn void contextScaleCTM(void* c, double sx, double sy) @cname("CGContextScaleCTM");
extern fn void contextSetTextPosition(void* c, double x, double y) @cname("CGContextSetTextPosition");
extern fn void contextSetRGBFillColor(void* c, double red, double green, double blue, double alpha) @cname("CGContextSetRGBFillColor");
extern fn void contextSetTextMatrix(void* c, double[6] matrix) @cname("CGContextSetTextMatrix");
extern fn void contextFillRect(void* c, Rect rect) @cname("CGContextFillRect");

/**
* Core Text
*/
module ct @if(env::DARWIN);

extern fn void* fontCreateWithName(void* name, double size, void* matrix) @cname("CTFontCreateWithName");
extern fn void* lineCreateWithAttributedString(void* attrString) @cname("CTLineCreateWithAttributedString");
extern fn void lineDraw(void* line, void* context) @cname("CTLineDraw");

