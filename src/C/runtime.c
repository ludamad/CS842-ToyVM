/* Allow for MAP_ANONYMOUS */
#define _GNU_SOURCE

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

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

/* create an object */
LangObject langNewObject(struct LangGlobals* globals, void **pstack) {
    LangObject ret = NULL;
    LangNullArray members = NULL;
    LangShape shape = globals->emptyShape;

    PSTACK();
    GGC_PUSH_2(ret, members);

    ret = GGC_NEW(LangObject);
    members = GGC_NEW_PA(LangNull, 0);
    GGC_WP(ret, members, members);
    GGC_WP(ret, shape, shape);

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
void** langCreatePointer() {
    void **ret = malloc(sizeof(void *));
    if (ret == NULL) {
        perror("malloc");
        abort();
    }
    *ret = NULL;
    GGC_PUSH_1(*ret);
    GGC_GLOBALIZE();
    return ret;
}


/* map definitions */
GGC_MAP_DEFN(LangShapeMap, LangString, LangShape, stringHash, stringCmp);
GGC_MAP_DEFN(LangIndexMap, LangString, GGC_size_t_Unit, stringHash, stringCmp);

void* langDefaultValue;

LangString langStringCopy(const char* value, size_t len);
LangString langStringConcat(LangString str1, LangString str2);

void langGlobalsInit(struct LangGlobals* globals, int pstackSize) {
    LangShapeMap esm = NULL;
    LangShape emptyShape = NULL;
    LangIndexMap eim = NULL;
    LangString defaultValue = NULL;

    GGC_PUSH_4(esm, emptyShape, eim, defaultValue);

    globals->pstack = (void**)mmap(NULL, pstackSize*sizeof(void*), PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    ggc_jitPointerStack = globals->pstack;
    ggc_jitPointerStackTop = globals->pstack;
    globals->pstackTop = &ggc_jitPointerStackTop;

    /* the empty shape */
    emptyShape = GGC_NEW(LangShape);
    esm = GGC_NEW(LangShapeMap);
    eim = GGC_NEW(LangIndexMap);
    GGC_WP(emptyShape, children, esm);
    GGC_WP(emptyShape, members, eim);
    globals->emptyShape = emptyShape;
    globals->defaultValue = langStringCopy("", 0);
    langDefaultValue = globals->defaultValue;
    globals->types.boxType = (struct GGGGC_Descriptor**) langCreatePointer();
    *globals->types.boxType = LangBoxedRef__descriptorSlot.descriptor;
    globals->types.stringType = (struct GGGGC_Descriptor**) langCreatePointer();
    *globals->types.stringType = LangString__descriptorSlot.descriptor;

    GGC_POP();
    {
    	GGC_PUSH_3(globals->emptyShape, globals->defaultValue, langDefaultValue);
        GGC_GLOBALIZE();
    }
}

/* simple boxer for strings */
LangString langStringNew(size_t len) {
    LangString ret = NULL;
    GGC_char_Array arr = NULL;
    LangHeader header = {0, LANG_IS_STRING};

    GGC_PUSH_2(ret, arr);

    arr = GGC_NEW_DA(char, len+1);

    ret = GGC_NEW(LangString);
    GGC_WD(ret, _header, header);
    GGC_WP(ret, value, arr);

    GGC_POP();
    return ret;
}

LangString langStringCopy(const char* value, size_t len) {
    LangString ret = langStringNew(len);
    GGC_char_Array arr = GGC_RP(ret, value);
    strncpy(arr->a__data, value, len+1);
    return ret;
}

LangString langStringConcat(LangString str1, LangString str2) {
    GGC_char_Array arr1 = NULL, arr2 = NULL, arr3 = NULL;
    int newLen;
    LangString result;
    GGC_PUSH_6(str1, str2, result, arr1, arr2, arr3);

    arr1 = GGC_RP(str1, value);
    arr2 = GGC_RP(str2, value);
    newLen = arr1->length + arr2 ->length - 2;
    result = langStringNew(newLen);
    arr3 = GGC_RP(result, value);
    strncpy(arr3->a__data, arr1->a__data, arr1->length - 1);
    strncpy(arr3->a__data + arr1->length - 1, arr2->a__data, arr2->length - 1);
    GGC_POP();
    return result;
}

/* map functions */
void langStringPrint(LangString str) {
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
	LangNullArray oldObjectMembers = NULL, newObjectMembers = NULL;
	GGC_size_t_Unit indexBox = NULL;
	size_t ret;

	PSTACK();
	GGC_PUSH_9(object, member, shape, cshape, shapeChildren, shapeMembers,
			oldObjectMembers, newObjectMembers, indexBox);

	shape = GGC_RP(object, shape);

	
        printf("Looking up ");
	langStringPrint(member);
	printf("\n");
	/* first, check if it is a known cached shape and member for which we remember the index */
	if (cache
			!= NULL&& shape == GGC_RP(*cache, cachedShape) && member == GGC_RP(*cache, cachedMember)) {
		langStringPrint(member);
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
	newObjectMembers = GGC_NEW_PA(LangNull, ret + 1);
	memcpy(newObjectMembers->a__ptrs, oldObjectMembers->a__ptrs,
			ret * sizeof(LangNull));
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
		langStringPrint(member);
	}
	return ret;
}

