#include <jit/jit.h>


#include "runtime.h"

/****************************************************************************
 * Instruction data
 ****************************************************************************/

/* 32 bit instructions
 * 1 byte opcode */
enum {
	LBC_NOP,
	/* Takes N pairs to initialize with */
	LBC_NEWTABLE, /* 8b_ 16b n_pairs*/
	LBC_NEWARRAY, /* 8b_ 16b n_values*/
	LBC_NEWBOX,   /* 8b_ 16b stack ref */

	LBC_NEWCLOSURE, /* 8b_ 16b n_args */
	LBC_RETAIN,     /* 8b_ 16b stack-ref */
	LBC_FREE,       /* 8b_ 16b stack-ref*/

	/* Extended opcodes */
    /* Operation signature: 8b_ 16b left-ref 16b right-ref 16b dest */
	LBC_ADD,
	LBC_SUB,
	LBC_MUL,
	LBC_DIV,

	/* Branch on greater than: */
	LBC_BGT,
	/* Branch on equal: */
	LBC_BEQ,
	/* Return properly backed booleans: */
	LBC_GT,
};

/****************************************************************************
 * Function context data
 ****************************************************************************/

/* Eval is one giant function, use macros for everything: */

/* Two different views of the stack: */
#define _V(i) (((value_t*)pStack)[i])
#define _P(i) (((LangNull)pStack)[i])

/* A different view of the instruction stream: */
#define _sPtr ((short*)iPtr)

#define _header(v) GGC_RD(_P(v), _header)
#define _flags(v) _header(v).flags
#define _desc(v) _P(v)->header.descriptor__ptr

#define _tag(v) _V(v).tag
#define _val(v) _V(v).val

#define _isInt(v) (_tag(v) == TYPE_TAG_INT)
#define _isBool(v) (_tag(v) == TYPE_TAG_BOOL)
#define _isStr(v) (!(_tag(v)&1) && (_flags(v) & LANG_IS_STRING))

#define _reqInt(v)  if (_unlikely(!_isInt (v))) goto intErr
#define _reqBool(v) if (_unlikely(!_isBool(v))) goto boolErr
#define _reqStr(v)  if (_unlikely(!_isStr (v))) goto strErr

/* For operators: */
#define _opLeft   _sPtr[1]
#define _opRight  _sPtr[2]
#define _opDest   _sPtr[3]


/* The LibJIT-created function will set up the stack for us.
 * All we must do then is continue from 'iPtr' to 'end' */
int eval(int* iPtr, int* end, void** pStack, struct LangGlobals* globals, LangNullArray metadata) {
	value_t result;
	while (iPtr != end) {
		switch (*iPtr) {
		case LBC_ADD:
			_reqInt(_opLeft);
			_reqInt(_opRight);
			result.tag = TYPE_TAG_INT;
			result.val = _val(_opLeft) + _val(_opRight);
			_V(_opDest) = result;
			break;
		}
	}
	strErr:
	intErr:
		jit_throw_exception("Oops");
}

