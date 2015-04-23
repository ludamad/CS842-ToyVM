local ffi = require "ffi"
local gc = require "ggggc"

-- Too much work to correctly expose GC'd types
-- and we only use them from C and from JIT, so its OK.
ffi.cdef [[
    uint64_t RUNTIME_print(uint64_t* args, unsigned int n);  
    void** createPointerStack(int maxSize);
    size_t langGetObjectMemberIndex(void **pstack, void* object, void* member, void* cache, int create);

    struct LangTypeDescriptors {
        struct GGGGC_Descriptor** boxType;
        struct GGGGC_Descriptor** stringType;
        struct GGGGC_Descriptor** funcType;
    };

    struct LangGlobals {
        void** pstack;
        void*** pstackTop;
        void* emptyShape;
        void* defaultValue;
        struct LangTypeDescriptors types;
    };

    typedef struct {
        // 0 if not hashed. The object specific hash function is called here, and cached.
        unsigned int cachedHash;
        // Object flags which configure runtime copying behaviour, etc.
        unsigned int flags;
    } LangHeader;

    typedef struct {
        int tag, val;
    } LangValue;
    typedef unsigned int (*LangFunc)(unsigned int n);

    typedef struct {
        struct GGGGC_Header gcHeader;
        LangHeader header;
        GGC_char_Array array;
    } LangString;

    typedef struct {
        struct GGGGC_Header gcHeader;
        LangHeader header;
        LangValue value[1];
    } LangBoxedRef;

    typedef struct {
        struct GGGGC_Header gcHeader;
        LangHeader header;
        void* cFuncPtr;
        /* Array of LangValue's to use as initial arguments:*/
        void* capturedVars;
    } LangFunction;

    void** langCreatePointer();
    void langStringPrint(LangString* str);
    void langGlobalsInit(struct LangGlobals* globals, int pstackSize);
    LangString* langStringNew(size_t len);
    LangString* langStringCopy(const char *value, size_t len);
    void langStringPrint(LangString* str);
    LangString* langStringConcat(LangString* str1, LangString* str2);

    int eval(int* iPtr, int* end, void** pStack, struct LangGlobals* globals, void* metadata);

]]

return gc
