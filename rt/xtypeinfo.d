module rt.xtypeinfo;

/** 
Until TypeInfo gets a copy function, supply own.
Abandoned at present.
*/

alias void function(void* dest, void* src) TypeCopyFn;
alias int delegate(void* dest, void* src) TypeCmpFn;
alias bool delegate(void* dest, void* src) TypeEqualFn;
alias hash_t delegate(void* dest) TypeHashFn;

struct AATypeInfo {
	TypeInfo	ti;
	TypeCopyFn  copyFn;
}

