#ifndef RUNTIME_H
#define RUNTIME_H

#include <stdio.h>
#include <stdlib.h>

#include "ggggc/gc.h"
#include "ggggc/collections.h"

typedef unsigned long long uint64_t;

typedef struct {
    int val, tag;
} value_t;

/* object shape */
typedef struct LangShapeMap__struct* LangShapeMap_;
typedef struct LangIndexMap__struct* LangIndexMap_;

enum {
    /* Should we pass this object by reference?
     * In this case, the object should be permanently marked 'free',
     * and on attempt to unfree it, this flag is checked. */
    LANG_FLAG_BYREF = 1 << 0,
    /* Is it legal to mutate this object? (It is assumed first that we fully own it).
     * Alternatively, we may designate objects such as modules constant 
     * to avoid copying, until a mutate.
     * All operations thus occur on a parent pointer, which houses the 
     * location of the object.
     *
     * This mimics how boxes are used in the language. */
    LANG_FLAG_MUTABLE = 1 << 1,
    /* Has this object been conceptually 'freed'? 
     * This provides an optimization for cases where the last reference to this value
     * will be out of scope by the time it is used. 
     * The next reference to store this object will claim it very cheaply. */
    LANG_FLAG_FREE = 1 << 2,
    /* Has this object been stored in a canonical form? 
     * This is necessary knowledge for fast inequality checks for example
     * with strings, and for properly removing the strings from the 
     * intern pool. */
    LANG_INTERNED = 1 << 3,
    /* For fast string checks: */
    LANG_IS_STRING = 1 << 4,
    /* For fast box checks: */
    LANG_IS_BOX = 1 << 5,
    /* For fast object checks: */
    LANG_IS_OBJECT = 1 << 6
};

typedef struct {
    // 0 if not hashed. The object specific hash function is called here, and cached.
    unsigned int cachedHash;
    // Object flags which configure runtime copying behaviour, etc.
    unsigned int flags;
} LangHeader;

#define LANG_TYPE(T) GGC_TYPE(T) GGC_MDATA(LangHeader, _header);

/* boxed strings */
LANG_TYPE(LangNull)
GGC_END_TYPE(LangNull, GGC_NO_PTRS);

/* boxed strings */
LANG_TYPE(LangString)
    GGC_MPTR(GGC_char_Array, value);
GGC_END_TYPE(LangString,
    GGC_PTR(LangString, value)
    );

GGC_TYPE(LangShape)
    GGC_MDATA(size_t, size);
    GGC_MPTR(LangShapeMap_, children);
    GGC_MPTR(LangIndexMap_, members);
GGC_END_TYPE(LangShape,
    GGC_PTR(LangShape, children)
    GGC_PTR(LangShape, members)
    );

LANG_TYPE(LangObject)
    GGC_MPTR(LangShape, shape);
    GGC_MPTR(LangNullArray, members);
GGC_END_TYPE(LangObject,
    GGC_PTR(LangObject, shape)
    GGC_PTR(LangObject, members)
    );

/* map of strings to object shapes */
GGC_MAP_DECL(LangShapeMap, LangString, LangShape);

/* map of strings to indexes (size_ts) */
GGC_UNIT(size_t)
GGC_MAP_DECL(LangIndexMap, LangString, GGC_size_t_Unit);

LANG_TYPE(LangBoxedRef)
    GGC_MPTR(void*, langPtr);
GGC_END_TYPE(LangBoxedRef,
    GGC_PTR(LangBoxedRef, langPtr)
);

GGC_TYPE(LangInlineCache)
    GGC_MPTR(LangShape, cachedShape);
    GGC_MPTR(LangString, cachedMember);
    GGC_MDATA(int, cachedIndex); /* Index in the cached shape */
GGC_END_TYPE(LangInlineCache,
    GGC_PTR(LangInlineCache, cachedShape)
    GGC_PTR(LangInlineCache, cachedMember)
);

/****************************************************************************
 * Language closures and 'native' functions:
 ****************************************************************************/

LANG_TYPE(LangFunction)
    /* Not allocated by GGGGC: */
    GGC_MPTR(void*, cFuncPtr);
    /* TODO: This should have a hook which frees everything about a function*/
    GGC_MPTR(LangNullArray, functionMetaData);
    /**/
    GGC_MPTR(LangNullArray, capturedVars);
GGC_END_TYPE(LangFunction,
    GGC_PTR(LangFunction, capturedVars)
);

/****************************************************************************
 * Initialized VM data:
 ****************************************************************************/

struct LangTypeDescriptors {
    struct GGGGC_Descriptor** boxType;
    struct GGGGC_Descriptor** stringType;
    struct GGGGC_Descriptor** funcType;
    struct GGGGC_Descriptor** objType;
};
struct LangGlobals {
    void** pstack;
    void*** pstackTop;
    void* emptyShape;
    void* defaultValue;
    struct LangTypeDescriptors types;
};

/****************************************************************************
 * Utilities:
 ****************************************************************************/

#define _likely(x)      __builtin_expect(!!(x), 1)
#define _unlikely(x)    __builtin_expect(!!(x), 0)

#define TYPE_TAG_BOOL 1
#define TYPE_TAG_INT 3

#endif /*RUNTIME_H*/
