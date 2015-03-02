local ffi = require "ffi"

ffi.cdef [[
        typedef size_t ggc_size_t;
        struct GGGGC_Pool {
                struct GGGGC_Pool *next;
                unsigned char gen;
                ggc_size_t *free, *end;
                ggc_size_t survivors;
                ggc_size_t breakTableSize;
                void *breakTable;
                unsigned char remember[((ggc_size_t) 1 << (24 - 12))];
                unsigned short firstObject[((ggc_size_t) 1 << (24 - 12))];
                ggc_size_t start[1];
        };
        struct GGGGC_Header {
                struct GGGGC_Descriptor *descriptor__ptr;
        };
        struct GGGGC_Descriptor {
                struct GGGGC_Header header;
                void *user__ptr;
                ggc_size_t size;
                ggc_size_t pointers[1];
        };
        struct GGGGC_PointerStack {
                struct GGGGC_PointerStack *next;
                ggc_size_t size;
                void *pointers[1];
        };
        typedef struct char__ggggc_array *GGC_char_Array;
        struct char__ggggc_array {
                struct GGGGC_Header header;
                ggc_size_t length;
                char a__data[1];
        };
        typedef struct short__ggggc_array *GGC_short_Array;
        struct short__ggggc_array {
                struct GGGGC_Header header;
                ggc_size_t length;
                short a__data[1];
        };
        typedef struct int__ggggc_array *GGC_int_Array;
        struct int__ggggc_array {
                struct GGGGC_Header header;
                ggc_size_t length;
                int a__data[1];
        };
        typedef struct unsigned__ggggc_array *GGC_unsigned_Array;
        struct unsigned__ggggc_array {
                struct GGGGC_Header header;
                ggc_size_t length;
                unsigned a__data[1];
        };
        typedef struct long__ggggc_array *GGC_long_Array;
        struct long__ggggc_array {
                struct GGGGC_Header header;
                ggc_size_t length;
                long a__data[1];
        };
        typedef struct float__ggggc_array *GGC_float_Array;
        struct float__ggggc_array {
                struct GGGGC_Header header;
                ggc_size_t length;
                float a__data[1];
        };
        typedef struct double__ggggc_array *GGC_double_Array;
        struct double__ggggc_array {
                struct GGGGC_Header header;
                ggc_size_t length;
                double a__data[1];
        };
        typedef struct size_t__ggggc_array *GGC_size_t_Array;
        struct size_t__ggggc_array {
                struct GGGGC_Header header;
                ggc_size_t length;
                size_t a__data[1];
        };
        void *ggggc_malloc(struct GGGGC_Descriptor *descriptor);
        void *ggggc_mallocSlot(struct GGGGC_DescriptorSlot *slot);
        void *ggggc_mallocPointerArray(ggc_size_t sz);
        void *ggggc_mallocDataArray(ggc_size_t nmemb, ggc_size_t size);
        struct GGGGC_Descriptor *ggggc_allocateDescriptor(ggc_size_t size,
                        ggc_size_t pointers);
        struct GGGGC_Descriptor *ggggc_allocateDescriptorL(ggc_size_t size,
                        const ggc_size_t *pointers);
        struct GGGGC_Descriptor *ggggc_allocateDescriptorPA(ggc_size_t size);
        struct GGGGC_Descriptor *ggggc_allocateDescriptorDA(ggc_size_t size);
        struct GGGGC_Descriptor *ggggc_allocateDescriptorSlot(
                        struct GGGGC_DescriptorSlot *slot);
        extern volatile int ggggc_stopTheWorld;
        int ggggc_yield(void);
        void ggggc_globalize(void);
        static const int ggggc_localPush = 0;
        struct GGGGC_PointerStack1 {
                struct GGGGC_PointerStack ps;
                void *pointers[1];
        };
        struct GGGGC_PointerStack2 {
                struct GGGGC_PointerStack ps;
                void *pointers[2];
        };
        struct GGGGC_PointerStack3 {
                struct GGGGC_PointerStack ps;
                void *pointers[3];
        };
        struct GGGGC_PointerStack4 {
                struct GGGGC_PointerStack ps;
                void *pointers[4];
        };
        struct GGGGC_PointerStack5 {
                struct GGGGC_PointerStack ps;
                void *pointers[5];
        };
        struct GGGGC_PointerStack6 {
                struct GGGGC_PointerStack ps;
                
                void *pointers[6];
        };
        struct GGGGC_PointerStack7 {
                struct GGGGC_PointerStack ps;
                void *pointers[7];
        };
        struct GGGGC_PointerStack8 {
                struct GGGGC_PointerStack ps;
                void *pointers[8];
        };
        struct GGGGC_PointerStack9 {
                struct GGGGC_PointerStack ps;
                void *pointers[9];
        };
        struct GGGGC_PointerStack10 {
                struct GGGGC_PointerStack ps;
                void *pointers[10];
        };
        struct GGGGC_PointerStack11 {
                struct GGGGC_PointerStack ps;
                void *pointers[11];
        };
        struct GGGGC_PointerStack12 {
                struct GGGGC_PointerStack ps;
                void *pointers[12];
        };
        struct GGGGC_PointerStack13 {
                struct GGGGC_PointerStack ps;
                void *pointers[13];
        };
        struct GGGGC_PointerStack14 {
                struct GGGGC_PointerStack ps;
                void *pointers[14];
        };
        struct GGGGC_PointerStack15 {
                struct GGGGC_PointerStack ps;
                void *pointers[15];
        };
        struct GGGGC_PointerStack16 {
                struct GGGGC_PointerStack ps;
                void *pointers[16];
        };
]]

local gc = ffi.load("./libggggc.so")

return gc