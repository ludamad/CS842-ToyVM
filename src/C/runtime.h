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

/* boxed strings */
GGC_TYPE(LangString)
    GGC_MDATA(unsigned int, __cachedHash);
    GGC_MPTR(GGC_char_Array, value);
GGC_END_TYPE(LangString,
    GGC_PTR(LangString, value)
    );

/* the type tag for boxed data types */
GGC_TYPE(LangValue)
    GGC_MDATA(int, val);
    GGC_MDATA(int, tag);
GGC_END_TYPE(LangValue, GGC_NO_PTRS);

/* object shape */
typedef struct LangShapeMap__struct* LangShapeMap_;
typedef struct LangIndexMap__struct* LangIndexMap_;

GGC_TYPE(LangShape)
    GGC_MDATA(size_t, size);
    GGC_MPTR(LangShapeMap_, children);
    GGC_MPTR(LangIndexMap_, members);
GGC_END_TYPE(LangShape,
    GGC_PTR(LangShape, children)
    GGC_PTR(LangShape, members)
    );

GGC_TYPE(LangObject)
    GGC_MPTR(LangShape, shape);
    GGC_MPTR(LangValueArray, members);
GGC_END_TYPE(LangObject,
    GGC_PTR(LangObject, shape)
    GGC_PTR(LangObject, members)
    );

/* map of strings to object shapes */
GGC_MAP_DECL(LangShapeMap, LangString, LangShape);

/* map of strings to indexes (size_ts) */
GGC_UNIT(size_t)
GGC_MAP_DECL(LangIndexMap, LangString, GGC_size_t_Unit);

GGC_TYPE(LangInlineCache)
    GGC_MPTR(LangShape, cachedShape);
    GGC_MPTR(LangString, cachedMember);
    GGC_MDATA(int, cachedIndex); /* Index in the cached shape */
        GGC_END_TYPE(LangInlineCache,
    GGC_PTR(LangInlineCache, cachedShape)
    GGC_PTR(LangInlineCache, cachedMember)
);

#endif /*RUNTIME_H*/
