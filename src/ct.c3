// CORE TEXT
module ct;

extern fn void* fontCreateWithName(void* name, double size, void* matrix) @cname("CTFontCreateWithName");
extern fn void* lineCreateWithAttributedString(void* attrString) @cname("CTLineCreateWithAttributedString");
extern fn void lineDraw(void* line, void* context) @cname("CTLineDraw");

