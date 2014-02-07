module rt.aaSLink;

import rt.aaI;
import alt.zstring;

import std.stdint;
/**
As close as possible, implement druntime AA, transplanting the rt.aaA code.
*/
debug(DEVTEST) {
	import std.stdio;
}

private
{
    import core.stdc.stdarg;
    import core.stdc.string;
    import core.stdc.stdio;

    enum BlkAttr : uint
    {
        FINALIZE    = 0b0000_0001,
        NO_SCAN     = 0b0000_0010,
        NO_MOVE     = 0b0000_0100,
        APPENDABLE  = 0b0000_1000,
        NO_INTERIOR = 0b0001_0000,
        ALL_BITS    = 0b1111_1111
    }

    extern (C) void* gc_malloc( size_t sz, uint ba = 0 );
    extern (C) void  gc_free( void* p );


}

class SingleLinkAA : IAA {

	static struct aaA
	{
		aaA *next;
		hash_t hash;
		/* key   */
		/* value */
	}
	
	alias aaA*	hbucket;

	static struct NodeReturn {
		hbucket			node_;
		hbucket*		pnode_;
		hash_t			hash_ = 0;
	}


	Array!hbucket	b_;
    //hbucket[] b_;
    size_t nodes_;       // total number of aaA nodes
	size_t valueOffset_;	 // cache size of key, always being used.
    TypeInfo keyti_;     // TODO: replace this with TypeInfo_AssociativeArray when available in _aaGet()
	TypeInfo   valueti_;
	intptr_t   refcount_;

	/// Typeinfo for key.
	TypeInfo keyType()
	{
		return keyti_;
	}

	/// Typeinfo for value. //TODO: store and supply value TypeInfo
	TypeInfo valueType()
	{
		return valueti_;
	}

	this()
	{
		b_.length = 7;
	}

	// find node only for lookup.
	final hbucket lookupKey(const void* pkey)
	{
		immutable blen = b_.length;
		if (blen == 0)
			return null;
		auto key_hash =  keyti_.getHash(pkey);
		auto e =  b_[key_hash % blen];
		for(;;)
        {
			if (e is null)
				break;
			if (key_hash == e.hash)
			{
				if (keyti_.compare(pkey, e + 1)==0)
				{
					return e;
				}
			}
            e = e.next;
        }
		return null;
	}
	// find for put or delete
	final bool findKey(const void* pkey, ref NodeReturn fix) 
	{
		immutable blen = b_.length;
		if (blen == 0)
			return false;
		auto key_hash =  keyti_.getHash(pkey);
		auto pe =  b_.ptr + key_hash % blen;
		for(;;)
        {
			auto e = *pe;
			if (e is null)
				break;
			if (key_hash == e.hash)
			{
				if (keyti_.compare(pkey, e + 1)==0)
				{
					fix.hash_ = 0;
					fix.node_ = e;
					fix.pnode_ = pe;
					return true;
				}
			}
            pe = &e.next;
        }
		fix.node_ = null;
		fix.pnode_ = pe;
		fix.hash_ = key_hash;
		return false;
	}

	private final void makeNode(void* pkey, ref NodeReturn ret)
	{
		hbucket e = void;
		// Not found, create blank valued node
		//printf("create new one\n");
		immutable valuesize = valueti_.tsize;
		e = cast(hbucket) gc_malloc(aaA.sizeof + valueOffset_ + valuesize);
		e.next = null;
		e.hash = ret.hash_;
		ubyte* ptail = cast(ubyte*)(e + 1);
		memset(ptail, 0, valueOffset_); // zero it all.
		memcpy(ptail, pkey, valueOffset_); // blit
		keyti_.postblit(ptail);
		//copyKeyFn_(ptail, pkey);
		ptail += valueOffset_;
		memset(ptail, 0, valuesize); // zero value.  Copy to be done externally
		*ret.pnode_ = e;

		auto nodes = ++nodes_;
		//printf("length = %d, nodes = %d\n", aa.a.b.length, nodes);
		if (nodes_ > b_.length * 4)
		{
			//printf("rehash\n");
			rehash();
		}
		ret.node_ = e;
	}

	void* getX(void* pkey, out bool existed)
	{
		NodeReturn ret;

		if (findKey(pkey, ret))
		{
			existed = true;
		}
		else {
			makeNode(pkey, ret);
			existed = false; // not necessary?
		}
		return cast(void *)(ret.node_ + 1) + valueOffset_;
	}

	///return a pointer to a value
	/+
	void* getX(void* pkey)
	{
		size_t i;
		aaA *e;
		//printf("keyti = %p\n", keyti);
		//printf("aa = %p\n", aa);
		immutable keytitsize = keyti_.tsize();

		auto key_hash = keyti_.getHash(pkey);
		//printf("hash = %d\n", key_hash);
		i = key_hash % b_.length;
		auto pe = &b_[i];
		while ((e = *pe) !is null)
		{
			if (key_hash == e.hash)
			{
				auto c = keyti_.compare(pkey, e + 1);
				if (c == 0)
					goto Lret;
			}
			pe = &e.next;
		}

		// Not found, create blank valued node
		//printf("create new one\n");
		immutable valuesize = valueti_.tsize;
		immutable valueOffset = aligntsize(keytitsize);
		size_t size = aaA.sizeof + valueOffset + valuesize;
		e = cast(aaA *) gc_malloc(size);
		e.next = null;
		e.hash = key_hash;
		ubyte* ptail = cast(ubyte*)(e + 1);
		memset(ptail, 0, valueOffset); // zero it all.
		copyKeyFn_(ptail, pkey);

		ptail += valueOffset;
		memset(ptail, 0, valuesize); // zero value.  Copy to be done externally
		*pe = e;

		auto nodes = ++nodes_;
		//printf("length = %d, nodes = %d\n", aa.a.b.length, nodes);
		if (nodes_ > b_.length * 4)
		{
			//printf("rehash\n");
			rehash();
		}
		return ptail;
	Lret:
		return cast(void *)(e + 1) + aligntsize(keytitsize);
	}
	+/

	IAA rehash()
	{
		auto len = getAAPrimeNumber(nodes_);

		if (len != b_.length)
		{
			Array!hbucket	newb;
			
			version(NoGarbageCollection)
			{
				newb.length = len;
			}
			else {
					newb.initNoInterior(len);
			}
			immutable newlen = newb.length;
			// move nodes into new array
			auto btable = newb.ptr();
			debug {
				auto checkNodes = 0;
			}

			foreach (e; b_.toArray)
			{
				while (e)
				{   auto enext = e.next;
					const j = e.hash % newlen; // different hashes will go to different j
					auto pe = &btable[j];
					e.next = *pe; // point to whats there before
					*pe = e;  // become the first. Single link list append at front
					e = enext;
					debug {
						checkNodes++;
					}
				}
			}
			debug {
				assert(checkNodes == nodes_);
			}
			b_ = newb;
		}
		return cast(IAA) this;
	}
	size_t length() @property const
	{
		return nodes_; 
	}
	/// Return a verified count
	size_t	count() @property
	{
		size_t len;
		foreach (e; b_.toArray)
		{
			while (e)
			{   
				len++;
				e = e.next;
			}
		}	
		return len;
	}
	
	bool equals(IAA other,TypeInfo_AssociativeArray ti)
	{
		Interface* p1 = cast(Interface*)other;
        Object o1 = cast(Object)(*cast(void**)p1 - p1.offset);
		
		auto  saa = cast(SingleLinkAA) o1;

		if (saa is null) 
			return false;

		auto keyti = ti.key;
		auto valueti = ti.next;
		const keysize = aligntsize(keyti.tsize());
		const len2 = saa.b_.length;

		int _aaKeys_x(aaA* e)
		{
			do
			{
				auto pkey = cast(void*)(e + 1);
				auto pvalue = pkey + keysize;
				//printf("key = %d, value = %g\n", *cast(int*)pkey, *cast(double*)pvalue);

				// We have key/value for e1. See if they exist in e2

				auto key_hash = keyti.getHash(pkey);
				//printf("hash = %d\n", key_hash);
				const i = key_hash % len2;
				auto f = saa.b_[i];
				while (1)
				{
					//printf("f is %p\n", f);
					if (f is null)
						return 0;                   // key not found, so AA's are not equal
					if (key_hash == f.hash)
					{
						//printf("hash equals\n");
						auto c = keyti.compare(pkey, f + 1);
						if (c == 0)
						{   // Found key in e2. Compare values
							//printf("key equals\n");
							auto pvalue2 = cast(void *)(f + 1) + keysize;
							if (valueti.equals(pvalue, pvalue2))
							{
								//printf("value equals\n");
								break;
							}
							else
								return 0;           // values don't match, so AA's are not equal
						}
					}
					f = f.next;
				}

				// Look at next entry in e1
				e = e.next;
			} while (e !is null);
			return 1;                       // this subtree matches
		}

		foreach (e; b_.toArray)
		{
			if (e)
			{   if (_aaKeys_x(e) == 0)
                return 0;
			}
		}

		return 1;           // equal
	}


	/// setup types
	/// Won't work
	/+ void init(TypeInfo_AssociativeArray aati)
	{
		extractAATypeInfo(aati,keyti_, valueti_);
	}
	+/

	/// setup types
	void init(TypeInfo kti, TypeInfo vti)
	{
		keyti_ = kti;
		valueOffset_ = aligntsize(keyti_.tsize());
		valueti_ = vti;

		refcount_ = 1;
	}
	void release()
	{
		refcount_--;
		if (refcount_ == 0)
		{
			clear();
			debug(DEVTEST) {
				writeln("SingleLinkAA clear");
			}
			version(NoGarbageCollection)
			{
				delete this;
			}
		}
	}

	void addref()
	{
		refcount_++;
	}

	private void init(SingleLinkAA caa)
	{
		keyti_ = caa.keyti_;
		valueOffset_ = caa.valueOffset_;
		//copyKeyFn_ = caa.copyKeyFn_;
		valueti_ = caa.valueti_;
		//copyValueFn_ = caa.copyValueFn_;	
		refcount_ =	1;
	}

	/// Get empty configured implementation
	IAA emptyClone()
	{
		auto aa = new SingleLinkAA();
		aa.init(this);
		return aa;
	}

	/// Not going to work until TypeInfo gets copyFn
	/+
	void init(TypeInfo_AssociativeArray ti, size_t aalen, ...)
	{
		auto valuesize = ti.next.tsize();           // value size
		
		auto keyti = ti.key;
		auto keysize = keyti.tsize();               // key size
		valueOffset_ = aligntsize(keysize);

		if (length == 0 || valuesize == 0 || keysize == 0)
		{
		}
		else
		{
			va_list q;
			version(X86_64) va_start(q, __va_argsave); else va_start(q, aalen);

			if (aalen > 10) /// arbitrary loadRatio > 2.5, binit.length == 4
				b_ = newaaA(getAAPrimeNumber(aalen));

			size_t keystacksize   = (keysize   + int.sizeof - 1) & ~(int.sizeof - 1);
			size_t valuestacksize = (valuesize + int.sizeof - 1) & ~(int.sizeof - 1);

			auto len = b_.length;

			for (size_t j = 0; j < aalen; j++)
			{   
				void* pkey = q;
				q += keystacksize;
				void* pvalue = q;
				q += valuestacksize;
				aaA* e;

				auto key_hash = keyti.getHash(pkey);
				//printf("hash = %d\n", key_hash);
				auto pe = &b_[key_hash % len];
				while (1)
				{
					e = *pe;
					if (!e)
					{
						// Not found, create new elem
						//printf("create new one\n");
						e = cast(aaA *) cast(void*) new void[aaA.sizeof + valueOffset_ + valuesize];
						memcpy(e + 1, pkey, keysize);
						e.hash = key_hash;
						*pe = e;
						nodes_++;
						break;
					}
					if (key_hash == e.hash)
					{
						auto c = keyti.compare(pkey, e + 1);
						if (c == 0)
							break;
					}
					pe = &e.next;
				}
				memcpy(cast(void *)(e + 1) + valueOffset_, pvalue, valuesize);
			}

			va_end(q);
		}
	}
	+/

	int appendPair(void* pkey, void *pvalue)
	{
		NodeReturn ret;
		if (!findKey(pkey,ret))
		{
			makeNode(pkey,ret);
		}
		auto vp = cast(void*) (ret.node_ + 1) + valueOffset_;
		memcpy(vp, pvalue, valueti_.tsize());
		valueti_.postblit(vp);
		return 0;
	}
	dg2_t getAppendDg()
	{
		return &appendPair;
	}

	void append(void[] keys, void[] values)
	{
		auto valuesize = valueti_.tsize();           // value size
		auto keysize = keyti_.tsize();               // key size
		auto klen = keys.length;	
		assert(klen == values.length);

		for (size_t j = 0; j < klen; j++)
		{   
			appendPair( keys.ptr + j * keysize,  values.ptr + j * valuesize);
		}
	}

	
	/// get existing value , or null.  value size not used 
	/+void* getRvalueX(void* pkey)
	{
		auto keysize = aligntsize(keyti_.tsize());
		auto len = b_.length;

		if (len)
		{
			auto key_hash = keyti_.getHash(pkey);
			//printf("hash = %d\n", key_hash);
			size_t i = key_hash % len;
			auto e = b_[i];
			while (e !is null)
			{
				if (key_hash == e.hash)
				{
					auto c = keyti_.compare(pkey, e + 1);
					if (c == 0)
						return cast(void *)(e + 1) + keysize;
				}
				e = e.next;
			}
		}
		return null;    // not found, caller will throw exception
	}
	+/
	// implements "in" operator.  valuesize is not required.
	/// effectively same as getRvalueX

	void* inX(const void* pkey)
	{
		auto len = b_.length;

		if (len)
		{
			auto key_hash = keyti_.getHash(pkey);
			//printf("hash = %d\n", key_hash);
			const i = key_hash % len;
			auto e = b_[i];
			while (e !is null)
			{
				if (key_hash == e.hash)
				{
					auto c = keyti_.compare(pkey, e + 1);
					if (c == 0)
						return cast(void *)(e + 1) + aligntsize(keyti_.tsize());
				}
				e = e.next;
			}
		}
		// Not found
		return null;
	}


	private final void freeNode(aaA* e)
	{
		keyti_.destroy(e+1);
		valueti_.destroy(cast(void *) (e+1)+aligntsize(keyti_.tsize()));
		gc_free(e);
	}

	/// delete value. Problem, struct.~this() not called for key or value
	bool delX(void* pkey)
	{
		NodeReturn ret;
		if (findKey(pkey, ret))
		{
			auto e = ret.node_;
			*ret.pnode_ = e.next;
			freeNode(e);
			return true;
		}
		return false;
	}


	ArrayRet_t values()
	{
		size_t keysize = keyti_.tsize;
		size_t valuesize = valueti_.tsize;
		size_t resi;
		ArrayD a;

		auto alignsize = aligntsize(keysize);

		a.length = nodes_;
		a.ptr = cast(byte*) gc_malloc(a.length * valuesize,
										valuesize < (void*).sizeof ? BlkAttr.NO_SCAN : 0);
		resi = 0;
		foreach (e; b_.toArray)
		{
			while (e)
			{
				memcpy(a.ptr + resi * valuesize,
						cast(byte*)e + aaA.sizeof + alignsize,
						valuesize);
				resi++;
				e = e.next;
			}
		}
		assert(resi == a.length);

		return *cast(ArrayRet_t*)(&a);
	}


	ArrayRet_t keys()
	{
		auto len = nodes_;
		if (!len)
			return null;
		size_t keysize = keyti_.tsize;

		auto res = (cast(byte*) gc_malloc(len * keysize,
										  !(keyti_.flags() & 1) ? BlkAttr.NO_SCAN : 0))[0 .. len * keysize];
		size_t resi = 0;
		foreach (e; b_.toArray)
		{
			while (e)
			{
				memcpy(&res[resi * keysize], cast(byte*)(e + 1), keysize);
				resi++;
				e = e.next;
			}
		}
		assert(resi == len);

		ArrayD a;
		a.length = len;
		a.ptr = res.ptr;
		return *cast(ArrayRet_t*)(&a);
	}
	
	int apply(dg_t dg)
	{
		immutable alignsize = aligntsize(keyti_.tsize);
		//printf("_aaApply(aa = x%llx, keysize = %d, dg = x%llx)\n", aa.a, keysize, dg);

		foreach (e; b_.toArray)
		{
			while (e)
			{
				auto result = dg(cast(void *)(e + 1) + alignsize);
				if (result)
					return result;
				e = e.next;
			}
		}
		return 0;
	}
	/** At least length 2, 0 = length of hash map. 1 = count of nodes which are empty.
	  2 = count of nodes with chain length 1,  and so on, to length of array.
	*/
    uint[] statistics()
    {
        uint result[];

        if (b_.length==0)
        {
            result.length = 2;
            result[0] = 0;
            result[1] = 0;
            return result;
        }

        uint emptyCt = 0;

        result.length = 16;
        result[0] = cast(uint) b_.length;
        foreach(e ; b_.toArray)
        {
            if(e !is null)
            {
                uint listct = 0;
                while (e !is null)
                {
                    listct++;
                    e = e.next;
                }

                if (listct >= result.length-1)
                {
                    result.length = listct + 2;
                }
                result[listct+1] += 1;
            }
            else
            {
                emptyCt++;
            }

        }
        result[1] = cast(uint)emptyCt;
        return result;
    }
	int apply2(dg2_t dg)
	{

		//printf("_aaApply(aa = x%llx, keysize = %d, dg = x%llx)\n", aa.a, keysize, dg);

		immutable alignsize =  aligntsize(keyti_.tsize);

		foreach (e; b_.toArray)
		{
			while (e)
			{
				auto result = dg(e + 1, cast(void *)(e + 1) + alignsize);
				if (result)
					return result;
				e = e.next;
			}
		}

		return 0;
	}

	static struct SlotRange {
		alias aaA Slot;

		Slot*[] slots;
		Slot*   current;

		this(Slot*[] b)
		{
			if (b.length == 0) return;
			slots = b;
			nextSlot();
		}
		private final void nextSlot()
		{
			foreach (i, slot; slots)
			{
				if (!slot) continue;
				current = slot;
				slots = slots.ptr[i .. slots.length];
				break;
			}
		}

	public:
		@property bool empty() const
		{
			return current is null;
		}

		@property ref inout(Slot) front() inout
		{
			assert(current);
			return *current;
		}

		void popFront()
		{
			assert(current);
			current = current.next;
			if (!current)
			{
				slots = slots[1 .. $];
				nextSlot();
			}
		}
	}

	static class KeyRange : IKeyRange {
		SlotRange state;

		this(aaA*[] slots)
		{
			state = SlotRange(slots);
		}
		
		void popFront()
		{
			state.popFront();
		}
		bool empty()
		{
			return state.current is null;
		}
		AAKeyRef front()
		{
			return cast( const(void)* ) (state.current + 1);
		}
	}
	
	IKeyRange	byKey()
	{
		return new KeyRange(b_.toArray);
	}

	private static class ValueRange : IValueRange {
		SlotRange   state;
		uintptr_t	valueOffset;

		this(aaA*[] slots, uintptr_t offset)
		{
			state = SlotRange(slots);
			valueOffset = offset;
		}

		void popFront()
		{
			state.popFront();
		}
		bool empty()
		{
			return state.current is null;
		}
		AAValueRef front()
		{
			return cast(void*) ( (cast( const(byte)* ) (state.current + 1)) + valueOffset);
		}
	}

	IValueRange	byValue()
	{
		return new ValueRange(b_.toArray, aligntsize(keyti_.tsize));
	}
	/// remove all nodes
    void clear()
    {
		// each individual node needs cleaning
		if (nodes_)
		{
			foreach(e ; b_.toArray)
			{
				while(e !is null)
				{
					auto nxptr = e.next;
					freeNode(e);
					e = nxptr;
				}
			}
		}
		nodes_ = 0;
		b_.free(true);
		b_.length = 7; // initialize for new collection
    }
}


IAA makeAA(TypeInfo kti,TypeInfo vti)
{
	auto aa = new SingleLinkAA();
	aa.init(kti,vti);
	return aa;
}


unittest {

	alias alt.zstring.Array!char	arrayChar;

	alias rt.aaI.AssociativeArray!(int,arrayChar)	IntBlat;

	IntBlat baa;
	baa.init(&makeAA);
	baa[0] = arrayChar("Hello string");
	/// baa[1] = "raw string"; // no implicit conversion

	void testRefCount(IntBlat aaplace)
	{
		aaplace[1] = arrayChar("Another String");
	}

	auto copy2 = baa;

	testRefCount(baa);

	auto fs = baa[1];
	baa.remove(0);
	baa.remove(1);


	alias rt.aaI.AssociativeArray!(int,arrayChar)	IntStringAA;

    IntStringAA aa;
	aa.init(&makeAA);

    aa["hello"] = 3;
    assert(aa["hello"] == 3);
    aa["hello"]++;
    assert(aa["hello"] == 4);

    assert(aa.length == 1);

    string[] keys = aa.keys;
    assert(keys.length == 1);
    assert(memcmp(keys[0].ptr, cast(char*)"hello", 5) == 0);

    int[] values = aa.values;
    assert(values.length == 1);
    assert(values[0] == 4);

    aa.rehash;
    assert(aa.length == 1);
    assert(aa["hello"] == 4);

    aa["foo"] = 1;
    aa["bar"] = 2;
    aa["batz"] = 3;

    assert(aa.keys.length == 4);
    assert(aa.values.length == 4);

    foreach(a; aa.keys)
    {
        assert(a.length != 0);
        assert(a.ptr != null);
        //printf("key: %.*s -> value: %d\n", a.length, a.ptr, aa[a]);
    }

    foreach(v; aa.values)
    {
        assert(v != 0);
        //printf("value: %d\n", v);
    }	

}