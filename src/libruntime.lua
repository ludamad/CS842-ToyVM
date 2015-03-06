local ffi = require "ffi"
local gc = require "ggggc"

-- Too much work to correctly expose GC'd types
-- and we only use them from C and from JIT, so its OK.
ffi.cdef [[
    uint64_t RUNTIME_print(uint64_t* args, unsigned int n);  
    void** createPointerStack(int maxSize);
    size_t langGetObjectMemberIndex(void **pstack, void* object, void* member, void* cache, int create);

    struct LangGlobals {
        void** pstack;
        void*** pstackTop;
        void* emptyShape;
        void* defaultValue;
    };
    typedef struct {
        struct GGGGC_Header header;
        unsigned int __cachedHash;
        GGC_char_Array array;
    } LangString;

    void** langCreatePointer();
    void langStringPrint(LangString* str);
    void langGlobalsInit(struct LangGlobals* globals, int pstackSize);
    LangString* langStringNew(size_t len);
    LangString* langStringCopy(const char *value, size_t len);
    void langStringPrint(LangString* str);
    LangString* langStringConcat(LangString* str1, LangString* str2);
]]

return gc
