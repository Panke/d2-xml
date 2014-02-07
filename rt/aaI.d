module rt.aaI;

import std.stdint;
import std.traits;

/// enumerate keys
extern (D) alias int delegate(void *) dg_t;
/// enumerate keys and values
extern (D) alias int delegate(void *, void *) dg2_t;
/// interface to work with D2 (dmd) implementation of opaque AA struct

/// Try and support object.AssociativeArray byKey and byValue.

alias const(void)* AAKeyRef;
alias void* AAValueRef;

interface IKeyRange {
	void popFront();
	AAKeyRef front();
	bool empty();
}

interface IValueRange {
	void popFront();
	AAValueRef front();
	bool empty();
}

/**
	Current Linked AA assumes that  TypeInfo of value type need not be
	stored.
	
	This is awfully clever.  Actual assignment of value types can be done outside of the 
	AA interface by the compiler.  The AA interface returns a pointer to the memory spot,
	every time a value is required.  This includes opIn_r , byKey, byValue.
	
	Its a bit of problem for struct with post-blit and/or destructor.
	The AA copies the memory of the nodes into an array, but it would seem that
	it is unable to perform post-blit, because underlying _aaValues only knows keysize and valuesize
	of the memory spots.
	
	This means that every call to set, has to pass in key TypeInfo, and valuesize.
	The key TypeInfo, just in case its the first call. Valuesize, because the AA doesn't actually know.
	
	Also creates a possibility its the wrong keyti, and valuesize.
	I do not see how AssociativeArray template in object.d can rectify this.

	

*/

interface IAA {
	/// equals checks same implementation.
	bool equals(IAA other, TypeInfo_AssociativeArray rawTi);

	/// setup types.  Won't work
	/// void init(TypeInfo_AssociativeArray aati);

	/// setup types
	void init(TypeInfo kti,TypeInfo vti);


	/// implement initialisation from a literal va_list. Won't work.
	///void init(TypeInfo_AssociativeArray ti, size_t length, ...);


	/// implement initialisation from a literal. Won't work.
	/// void init(TypeInfo_AssociativeArray ti, void[] keys, void[] values);
	///		return number of stored key-value pairs as a property
	size_t	length();

	/// append all the values from array index pairs, matching key and value types.
	/// return increase in size
	void append(void[] keys, void[] values);
	/// append or replace single key value pair. return 0 if successful (for apply2 delegate)
	//int append(void* key, void* value);

	dg2_t getAppendDg(); // return a int append(void* key, void* value);

	/// reference counting , or not
	void release();
	void addref();

	/// rehash.  Return IAA
	IAA rehash(); 
	/// Range interface for keys
	IKeyRange		byKey();
	/// Range interface for values
	IValueRange		byValue();
	/// remove key value pair
	bool delX(void* pkey);
	/// get existing or new location for a poking a value
	///void* getX(void* pkey);
	/// get, and return if location was created or was existing
	void* getX(void* pkey, out bool isNew);

	/// Return existing or null
	void* inX(const void* pkey);
	/// return unique copy of array of values
	ArrayRet_t values();

	/// return unique copy of array of keys
	ArrayRet_t keys();
	
	/** At least length 2, 0 = length of hash map. 1 = count of nodes which are empty.
	2 = count of nodes with chain length 1,  and so on, to length of array.
	*/
	uint[] statistics();
	/// return new instance with copy of each key-value pair
	//IAA dup();

	/// Delegate for each key
	int apply(dg_t dg);

	/// Delegate for each key and value
	int apply2(dg2_t dg);

	/// Typeinfo for key.
	TypeInfo keyType();

	/// Typeinfo for value.
	TypeInfo valueType();

	/// remove all pairs
	void clear();

	/// Get new interface with same configuration, but empty
	IAA emptyClone();

}

// how D will not see it
struct AA
{
    IAA a;
}

// These numbers are special
static immutable size_t[] prime_list = [
	31UL,
	97UL,            389UL,
	1_543UL,          6_151UL,
	24_593UL,         98_317UL,
	393_241UL,      1_572_869UL,
	6_291_469UL,     25_165_843UL,
	100_663_319UL,    402_653_189UL,
    1_610_612_741UL,  4_294_967_291UL,
	//  8_589_934_513UL, 17_179_869_143UL
];

size_t getAAPrimeNumber(size_t length)
{
	size_t i;
	for (i = 0; i < prime_list.length - 1; i++)
	{
		if (length <= prime_list[i])
			break;
	}
	return prime_list[i];
}

/// align struct key space so value starts on system aligned byte.

size_t aligntsize(size_t tsize)
{
    version (D_LP64)
        // Size of key needed to align value on 16 bytes
        return (tsize + 15) & ~(15);
    else
        return (tsize + size_t.sizeof - 1) & ~(size_t.sizeof - 1);
}


/* This is the type of the return value for dynamic arrays.
* It should be a type that is returned in registers.
* Although DMD will return types of Array in registers,
* gcc will not, so we instead use a 'long'.
*/
alias void[] ArrayRet_t;

struct ArrayD
{
    size_t length;
    void*  ptr;
}


struct AAError {
	enum {
		OPINDEX_FAIL = 0,

	}

	static class IAAException : Exception {
		this(string s)
		{	
			super(s);
		}
	}

	static string getMsg(intptr_t code)
	{
		switch(code)
		{
			case OPINDEX_FAIL:
				return "OpIndex value pointer null";
			default:
				return "IAA Exception";
		}
	}
	
	static Exception error(intptr_t code)
	{
		return new IAAException(getMsg(code));
	}


}



alias IAA function(TypeInfo keyti,TypeInfo valueti) createDefaultAA; 

shared createDefaultAA gAAFactory;


struct AssociativeArray(Key, Value)
{
private:
    IAA p;  
public:
	
	alias AssociativeArray!(Key,Value)	MyAAType;

	/// Support non-immutable lookups for immutable string types.
	/// TODO: make this more concise and broader?
	static if (isSomeString!Key)
    {
        static if (is(Key==string))
        {
            alias const(char)[] CKey;
        }
        else static if (is(Key==wstring))
        {
            alias const(wchar)[] CKey;
        }
        else static if (is(Key==dstring))
        {
            alias const(dchar)[] CKey;
        }
    }
    else {
		alias Key CKey;
    }


    @property size_t length() { return (p !is null) ? p.length : 0; }

	void init(createDefaultAA factory)
	{
		if (p)
		{
			p.release();
			p = null;
		}
		p = factory(typeid(Key), typeid(Value));
	}
	/// Post-Blits 
	this(this)
	{
		if (p)
		{
			p.addref();
		}
	}
	~this()
	{
		if (p)
		{
			p.release();
			p = null;
		}
	}
    MyAAType rehash() @property
    {
        p = p.rehash();
        return MyAAType(p);
    }

    Value[] values() @property
    {
		return (p !is null) ? *cast(Value[]*) p.values() : null;
    }

    Key[] keys() @property
    {
 		return (p !is null) ? *cast(Key[]*) p.keys() : null;
    }

    int opApply(scope int delegate(ref Key, ref Value) dg)
    {
		return p !is null ? p.apply2(cast(_dg2_t)dg) : 0;
    }

    int opApply(scope int delegate(ref Value) dg)
    {
        return p !is null ? p.apply(cast(_dg_t)dg) : 0;
    }

	void opAssign(Value[Key] op)
	{
		if (p is null)
			init(gAAFactory);
		auto dg = p.getAppendDg();
		foreach(k,v ; op)
		{
			dg(&k,&v);
		}
	}


	void opCatAssign(Value[Key] op)
	{
		if (p is null)
			init(gAAFactory);
		auto dg = p.getAppendDg();
		foreach(k,v ; op)
		{
			dg(&k,&v);
		}
	}
	void opCatAssign(MyAAType appendMe)
	{
		auto q = appendMe.p;
		if (q is null)
			// nothing to do
			return;
		if (p is null)
			p = q.emptyClone();
		q.apply2(p.getAppendDg());
	}

	Value opIndex(CKey key)
	{
		auto pvalue = (p !is null) ? p.inX(&key) : null;
		if (pvalue is null)
			throw AAError.error(AAError.OPINDEX_FAIL);
		return *(cast(Value*) pvalue);
	}
	Value opIndex(CKey key, lazy Value defaultValue)
	{
		auto pvalue = (p !is null) ? p.inX(&key) : null;
		return p ? *(cast(Value*) pvalue) : defaultValue;
	}

    Value get(CKey key, lazy Value defaultValue)
    {
        auto pval = (p !is null) ? p.inX(&key) : null;
        return pval ? *(cast(Value*) pval) : defaultValue;
    }

	Value* opIn_r(CKey key)
	{
		return ( p !is null) ? cast(Value*) p.inX(&key) : null;
	}
	
	// passed value is stored if it didn't exist, returned if it did.
	bool getOrPut(Key key, ref Value val)
	{	
		if (p is null)
			init(gAAFactory);
		bool existed = void;
		auto spot = cast(Value*) p.getX(&key, existed);
		if (!existed)
			*spot = val;
		else
			val = *spot;
		return existed;
	}

	void put(Key key, Value val)
	{
		if (p is null)
			init(gAAFactory);
		bool existed = void;
		auto spot = cast(Value*) p.getX(&key, existed);
		*spot = val;
	}

	uint[] chainLengths()
	{
		if (p is null)
			return [0,0];
		return p.statistics();
	}

	void opIndexAssign(Value val, Key key)
	{
		if (p is null)
			init(gAAFactory);
		bool existed = void;
		auto spot = cast(Value*) p.getX(&key, existed);
		*spot = val;
	}
	/// TODO: dup
   /* @property MyAAType dup()
    {
        MyAAType result;

		if (p !is null)
		{
			result.p = p.dup;
		}
		return result;
    } */
	
	
	MyAAType dup()
	{
		MyAAType result;
		if (p !is null)
		{
			auto q = p.emptyClone();
			p.apply2(q.getAppendDg());
			result.p = q;
		}
		return result;
	}

	void clear()
	{
		if (p !is null)
		{
			p.clear();
		}
	}

	bool remove(CKey key)
	{
		return (p !is null) ? p.delX(&key) : false;
	}

    @property auto byKey()
    {
        return (p !is null) ?  p.byKey() : null;
    }

    @property auto byValue()
    {
		return (p !is null) ?  p.byValue() : null;
    }
}

void extractAATypeInfo(TypeInfo tiRaw, ref TypeInfo keyti, ref TypeInfo valueti)
{
	TypeInfo_AssociativeArray  ti;
    while (true)
    {
        if ((ti = cast(TypeInfo_AssociativeArray)tiRaw) !is null)
            break;
        else if (auto tiConst = cast(TypeInfo_Const)tiRaw) {
            // The member in object_.d and object.di differ. This is to ensure
            //  the file can be compiled both independently in unittest and
            //  collectively in generating the library. Fixing object.di
            //  requires changes to std.format in Phobos, fixing object_.d
            //  makes Phobos's unittest fail, so this hack is employed here to
            //  avoid irrelevant changes.
            static if (is(typeof(&tiConst.base) == TypeInfo*))
                tiRaw = tiConst.base;
            else
                tiRaw = tiConst.next;
        } else
            assert(0);  // ???
    }
	keyti = ti.key;
	valueti = ti.next;
}

alias rt.aaI.AssociativeArray	AAIW;	