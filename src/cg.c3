// CORE GRAPHICS
module cg;
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

