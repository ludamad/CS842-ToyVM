#include <stdio.h>
#include <stdlib.h>

#include "runtime.h"
#include <sys/mman.h>

uint64_t RUNTIME_print(value_t* args, int n) {
    int i;
    for (i = 0; i < n; i++) {
        printf("Value %d : %d\n", i+1, args[i].val);
    }
    return 0;
}

/* map functions */
static size_t stringHash(LangString str) {
    GGC_char_Array arr = NULL;
    size_t i, ret = 0;

    GGC_PUSH_2(str, arr);
    arr = GGC_RP(str, value);

    for (i = 0; i < arr->length; i++)
        ret = ((unsigned char) GGC_RAD(arr, i)) + (ret << 16) - ret;

    return ret;
}

static int stringCmp(LangString strl, LangString strr) {
    GGC_char_Array arrl = NULL, arrr = NULL;
    size_t lenl, lenr, minlen;
    int ret;

    GGC_PUSH_4(strl, strr, arrl, arrr);
    arrl = GGC_RP(strl, value);
    arrr = GGC_RP(strr, value);
    lenl = arrl->length;
    lenr = arrr->length;
    if (lenl < lenr) minlen = lenl;
    else minlen = lenr;

    /* do the direct comparison */
    ret = memcmp(arrl->a__data, arrr->a__data, minlen);

    /* then adjust for length */
    if (ret == 0) {
        if (lenl < lenr) ret = -1;
        else if (lenl > lenr) ret = 1;
    }

    return ret;
}

/* map definitions */
GGC_MAP_DEFN(LangShapeMap, LangString, LangShape, stringHash, stringCmp);
GGC_MAP_DEFN(LangIndexMap, LangString, GGC_size_t_Unit, stringHash, stringCmp);

struct LangGlobals {
    void** pstack;
    void* emptyShape;
    void* defaultValue;
} langGlobals;

void* langDefaultValue;

ggc_thread_local void **ggc_jitPointerStack, **ggc_jitPointerStackTop;
void* langNewString(const char* value, size_t len);

void langGlobalsInit(int pstackSize) {
    LangShapeMap esm = NULL;
    LangShape emptyShape = NULL;
    LangIndexMap eim = NULL;
    LangString defaultValue = NULL;

    GGC_PUSH_4(esm, emptyShape, eim, defaultValue);

    langGlobals.pstack = (void**)mmap(NULL, pstackSize*sizeof(void*), PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
    ggc_jitPointerStack = langGlobals.pstack;
    ggc_jitPointerStackTop = langGlobals.pstack;

    /* the empty shape */
    emptyShape = GGC_NEW(LangShape);
    esm = GGC_NEW(LangShapeMap);
    eim = GGC_NEW(LangIndexMap);
    GGC_WP(emptyShape, children, esm);
    GGC_WP(emptyShape, members, eim);
    langGlobals.emptyShape = emptyShape;
    langGlobals.defaultValue = langNewString("", 0);
    langDefaultValue = langGlobals.defaultValue;

    GGC_POP();
    {
    	GGC_PUSH_3(langGlobals.emptyShape, langGlobals.defaultValue, langDefaultValue);
    }
}

/* simple boxer for strings */
void* langNewString(const char* value, size_t len) {
    LangString ret = NULL;
    GGC_char_Array arr = NULL;

    PSTACK();
    GGC_PUSH_2(ret, arr);

    arr = GGC_NEW_DA(char, len+1);
    strncpy(arr->a__data, value, len+1);

    ret = GGC_NEW(LangString);
    GGC_WP(ret, value, arr);

    return (void*)ret;
}

/* map functions */
static void stringPrint(LangString str) {
    GGC_char_Array arr = NULL;
    size_t i, ret = 0;

    GGC_PUSH_2(str, arr);
    arr = GGC_RP(str, value);

    for (i = 0; i < arr->length; i++)
        putchar(GGC_RAD(arr, i));
}

/* get the index to which a member belongs in this object, creating one if requested */
size_t langGetObjectMemberIndex(void **pstack, LangObject object,
		LangString member, LangInlineCache *cache, int create) {
	LangShape shape = NULL, cshape = NULL;
	LangShapeMap shapeChildren = NULL;
	LangIndexMap shapeMembers = NULL;
	LangValueArray oldObjectMembers = NULL, newObjectMembers = NULL;
	GGC_size_t_Unit indexBox = NULL;
	size_t ret;

	PSTACK();
	GGC_PUSH_9(object, member, shape, cshape, shapeChildren, shapeMembers,
			oldObjectMembers, newObjectMembers, indexBox);

	shape = GGC_RP(object, shape);

	printf("Looking up ");
	stringPrint(member);
	printf("\n");
	/* first, check if it is a known cached shape and member for which we remember the index */
	if (cache
			!= NULL&& shape == GGC_RP(*cache, cachedShape) && member == GGC_RP(*cache, cachedMember)) {
		printf("Got cache for ");
		stringPrint(member);
		printf(" at %d \n", GGC_RP(*cache, cachedMember));
		return GGC_RD(*cache, cachedIndex);
	}

	/* next, check if it already exists */
	shapeMembers = GGC_RP(shape, members);
	if (LangIndexMapGet(shapeMembers, member, &indexBox)) {
		/* got it! */
		ret = GGC_RD(indexBox, v);
		goto cacheAndReturn;
	}

	/* nope! Do we stop here? */
	if (!create)
		return(size_t) -1;

		/* expand the object */
	oldObjectMembers = GGC_RP(object, members);
	ret = oldObjectMembers->length;
	newObjectMembers = GGC_NEW_PA(LangValue, ret + 1);
	memcpy(newObjectMembers->a__ptrs, oldObjectMembers->a__ptrs,
			ret * sizeof(LangValue));
	GGC_WAP(newObjectMembers, ret, langDefaultValue);
	GGC_WP(object, members, newObjectMembers);

	/* check if there's already a defined child with it */
	shapeChildren = GGC_RP(shape, children);
	if (LangShapeMapGet(shapeChildren, member, &shape)) {
		/* got it! */
		GGC_WP(object, shape, shape);
		goto cacheAndReturn;
	}

	/* nope. Make the new shape */
	cshape = GGC_NEW(LangShape);
	LangShapeMapPut(shapeChildren, member, cshape);
	ret++;
	GGC_WD(cshape, size, ret);
	ret--;
	shapeChildren = GGC_NEW(LangShapeMap);
	GGC_WP(cshape, children, shapeChildren);
	shapeMembers = LangIndexMapClone(shapeMembers);
	GGC_WP(cshape, members, shapeMembers);
	indexBox = GGC_NEW(GGC_size_t_Unit);
	GGC_WD(indexBox, v, ret);
	LangIndexMapPut(shapeMembers, member, indexBox);
	GGC_WP(object, shape, cshape);
	shape = cshape; /* for cacheAndReturn */

	/* Overwrite the cache and return 'ret' */
	cacheAndReturn:
	/* first, check if it is a known cached shape and member for which we remember the index */
	if (cache != NULL) {
		GGC_WP(*cache, cachedShape, shape);
		GGC_WP(*cache, cachedMember, member);
		GGC_WD(*cache, cachedIndex, ret);
		printf("Set cache for ");
		stringPrint(member);
		printf(" at %X \n", GGC_RP(*cache, cachedMember));
	}
	return ret;
}
