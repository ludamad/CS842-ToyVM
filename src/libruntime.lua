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

    void** langCreatePointer();
    void langStringPrint(void* str);
    void langGlobalsInit(struct LangGlobals* globals, int pstackSize);
    void* langNewString(const char *value, size_t len);
]]

return gc
