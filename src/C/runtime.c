#include <stdio.h>
#include <stdlib.h>

#include "ghash.h"

typedef unsigned long long uint64_t;

typedef struct {
    int val, tag;
} LangValue;

#define DEF(name) \
    uint64_t RUNTIME_##name(uint64_t* _args, int n) { \
        LangValue* args = (LangValue*) _args; 

#define ENDDEF(val) \
        return val; \
    }

DEF(print)
    int i;
    for (i = 0; i < n; i++) {
        printf("Value %d : %d\n", i+1, args[i].val);
    }
ENDDEF(0)
