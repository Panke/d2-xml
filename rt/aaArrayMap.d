module rt.aaArrayMap;
import rt.aaI, rt.unarray;
import std.stdint;
import alt.zstring;

debug(DEVTEST) {
	import std.stdio;
}

private {
 import core.memory, std.c.string, core.stdc.stdarg;
}



/**
	Insert (write) performance slows down a lot, for large size maps, order of 10e6.
	This may be partly because for each write entry, 5 arrays require updates.
	The hash_t array, the links array, the map array, the keys array and values array.
	For large sizes these are more likely to be in far apart memory addresses,
	and more likely to cause separate CPU memory cache flushes. In comparison, the Link
	implementation, the writes all go to the same small node, and 4 pieces of information.
*/
class KeyValueArrayMap : IAA {
private:
	alias int intlink_t;
	alias alt.zstring.Array!HLink	LinksArray;
	alias alt.zstring.Array!intlink_t	MapArray;

	static struct HLink {
		intlink_t		next;
		intlink_t		prev;
	}
	/// Masks the highest bit of a hash value, to mark empty. This will mar the randomness a bit.
	enum { EMPTY_BIT =  1 << (hash_t.sizeof-1) }

	uintptr_t		capacity_; // reserved capacity for values
	uintptr_t		mapcap_;  // map loading capacity
	alt.zstring.Array!hash_t	hash_;
	//hash_t[]	    hash_;		// remember the hash values
	//intlink_t[]		hmap_;		// map to links
	//HLink[]		    hlinks_;
	LinksArray		hlinks_;
	MapArray		hmap_;

	int				freelinks_ = -1;
	double			loadRatio_ = 0.8;
	size_t			nodes_;   // active stored pairs
	UntypedArray	keys_;
	UntypedArray	values_;
	intptr_t		refcount_;

	// clear the hole
	void evict(intptr_t ix)
	{
		keys_.destroy(ix);
		if (values_.ptr)
			values_.destroy(ix);
	}
	
	// Set capacity, to at least the indicated value
	void setCapacity(uintptr_t atLeast)
	{
		if (atLeast > 0)
		{
		    auto oldCapacity = capacity_;

			hlinks_.reserve(atLeast);
			capacity_ = hlinks_.capacity;

			hash_.reserve(capacity_);
			//if (keys_.dti)
			keys_.reserve(capacity_,true);
			//if (values_.dti)
			values_.reserve(capacity_,true);			
			//if (hash_.length > 0)
			if (capacity_ != oldCapacity)
                reindex(capacity_);

		}		
	}

	// maps a hash value, to a link index
	final int hashToLinkIndex(hash_t h)
	{
		immutable hlen = hmap_.length;
		h = h & ~EMPTY_BIT;
		if(hlen == 0)
			return -1;
		return hmap_[h % hlen];
	}
	// one step along a link chain, return -1 if get first link (pointed to by hash)
	int findNext(int i)
	{
		auto q = hlinks_[i].next;
		size_t h = hash_[i];
		size_t ix = hmap_[h % hmap_.length]; 
		return (q == ix) ? -1 : q;
	}
	// Effect a removal by unlinking and making a hole
	final void unlink(intptr_t i)
	{
		assert(i < hash_.length);

		auto h = hash_[i];
		assert((h & EMPTY_BIT) == 0);
		hash_[i] = h | EMPTY_BIT;
		nodes_--;

		if(i < hlinks_.length)
		{ // TODO: what about earlier check?
			auto pbase = hlinks_.ptr;

			HLink* h0 = &pbase[i];
			auto mptr = &hmap_.ptr[h % hmap_.length];

			if(i == *mptr) 
			{
				// beginning of chain
				if(h0.next == i)
				{
					// only one in chain
					*mptr = -1;
					return;
				}
			}
			// unlink
			*mptr = h0.next;

			pbase[h0.next].prev = h0.prev;
			pbase[h0.prev].next = h0.next;

			// link to freelinks_;
			if(freelinks_ >= 0) 
			{  // already linked to another value
				HLink* h2 = &pbase[freelinks_];
				h0.next = freelinks_;
				h0.prev = h2.prev;
				h2.prev = cast(intlink_t) i;
				pbase[h0.prev].next = cast(intlink_t) i;
			}
			else {
				freelinks_ = h0.prev = h0.next = cast(intlink_t)i;
			}
			evict(i);
		}
	}
	/** the link and hash index is given, so just link it */
	final void setLinkIndex(intptr_t f0, size_t hash)
	{
		immutable h = hash & ~EMPTY_BIT; // clear empty
		immutable hlen = hmap_.length;
		hash_[f0] = h;
		nodes_++;

		auto mptr = &hmap_.ptr[h % hmap_.length];
		immutable mval = *mptr;
		auto pbase = hlinks_.ptr;
		HLink* ink = &pbase[f0];
		if(mval >= 0) {  // already linked to another value
			HLink* h2 = &pbase[mval];
			ink.next = cast(intlink_t)mval;
			ink.prev = h2.prev;
			h2.prev = cast(intlink_t)f0;
			pbase[ink.prev].next = cast(intlink_t)f0;
		}
		else {
			*mptr = ink.prev = ink.next = cast(intlink_t)f0;
		}
	}

	/** new link for added node */
	final intptr_t makeLink(uintptr_t hash)
	{
		size_t hlen = hmap_.length;
		size_t hsize = hash_.length;

		auto f0 = freelinks_;
		if (f0 >= 0)
		{
			auto pbase = hlinks_.ptr;
			HLink* ink = &pbase[f0];
			freelinks_ = ink.next;
			if (f0 == freelinks_)
				freelinks_ = -1;
			else {
				pbase[ink.next].prev = ink.prev;
				pbase[ink.prev].next = ink.next;
			}
		}
		else
		{
			// are we full yet
			auto wanted = hsize+1;
			if (wanted > capacity_)
			{
				wanted = (wanted > 8)? hsize*2 : 16;
				setCapacity(cast(uintptr_t) (wanted));
			}

			f0 = cast(intlink_t)hlinks_.length;
			hash_.put(f0);
			hlinks_.put(HLink(f0,f0));

		}
		setLinkIndex(f0, hash);
		return f0;
	}
	/** remap the hash values to links */
	final void reindex(uintptr_t n)
	{
		hlinks_.length = 0;
		freelinks_ = -1;
		//length_ = 0;   length_ does not change during this process == number of valid hash_[]

		size_t nlen = cast(size_t)(n / loadRatio_);
		hmap_.length = getAAPrimeNumber(nlen);
		hmap_.setAll(-1);
		mapcap_ = cast(size_t) (loadRatio_ * hmap_.length);
		finishIndex();
	}

	final void finishIndex()
	{
		size_t llen = hlinks_.length;
		auto hsize = hash_.length;
		if (llen < hsize)
		{
			hlinks_.length = hsize;
			immutable hlen = hmap_.length;
			intlink_t * mptr = void;
			auto plink = hlinks_.ptr;
			for(uintptr_t i = llen; i < hsize; i++)
			{
				auto h = hash_[i]; // convert hash into map index
				if ((h & EMPTY_BIT)==0)
				{
					mptr = &hmap_.ptr[h % hlen];
				}
				else
					mptr = &freelinks_;
				immutable mval = *mptr;
				HLink* f1 = &plink[i]; // mapped to link with index i
				if(mval >= 0) {
					HLink* f2 = &plink[mval];
					f1.next = mval;
					f1.prev = f2.prev;
					f2.prev = cast(intlink_t) i;
					plink[f1.prev].next = cast(intlink_t)i;
				}
				else {
					*mptr = f1.prev = f1.next = cast(intlink_t)i;
				}
			}
		}
	}


	/** Remove all entries for the key. Return number removed */
	intptr_t unlinkAll(void *pkey)
	{
		auto h = keys_.dti.getHash(pkey);
		intptr_t n = 0;
		auto q = hashToLinkIndex(h);
		while(q >= 0)
		{
			auto w = q;
			q = findNext(q);
			if(keys_.compare(w,pkey)==0)
			{
				unlink(w);
				n++;
			}
		}
		return n;
	}
	final intptr_t putHash(void *pkey, uintptr_t _hash)
	{
		auto q = makeLink(_hash);
		if (q >= keys_.length)
			keys_.length = q+1;
		keys_.assign(q, pkey);
		return q;
	}
	final intptr_t findKeyHash(const void *pkey, uintptr_t _hash)
	{
		auto i = hashToLinkIndex(_hash);
		while(i >= 0 && (keys_.compare(i,cast(void*) pkey)!=0))
			i = findNext(i);
		return i;
	}
	// return true if existing key, with position at fix
	final bool findPut(void* pkey, ref intptr_t fix)
	{
		auto h = keys_.dti.getHash(pkey);
		auto startLink = hashToLinkIndex(h);
		if (startLink >= 0)
		{
			// collision or key match chain found.
			auto ix = startLink;
			do
			{
				if (keys_.compare(ix, pkey)==0)
				{
					// key is already inserted at ix
					fix = ix;
					return true;
				}
				ix = hlinks_[ix].next;
			}
			while (ix != startLink);
		}
		auto q = makeLink(h);
		// TODO: may need post-blit fix?
		if (q >= keys_.length)
		{
			keys_.append(pkey); 
			values_.extend();
		}
		else {
			keys_.assign(q, pkey);
		}
		fix = q;
		return false;
	}
public:

	size_t	length() 
	{
		return nodes_;
	}
	/// get the length by counting all nodes, for debug verification.
	size_t	count()
	{
		return nodes_;
	}
	final void setArrays(void[] ka, void[] va)
	{
		clear();
		keys_.assign(ka);
		values_.assign(va);

		uintptr_t ilen = keys_.length;
		setCapacity(ilen);
		hash_.length = ilen;
		hlinks_.length = ilen;
		for(uintptr_t i = 0; i < keys_.length; i++)
		{
			// assume duplicates are possible?
			// in this process, the link record is fixed by key position
			auto h = keys_.hash(i);
			setLinkIndex(i, h);
		}
	}
    uint[] statistics()
    {
		intptr_t lowlink[];
		uint[] result;

		result.length = 16;

		lowlink.length = hlinks_.length;
		lowlink[] = -1;

		auto hdata = hmap_;
		result[0] = cast(uint) hdata.length;

		intptr_t emptybuckets = 0;
		auto links = hlinks_.toConstArray();

		for(uintptr_t i = 0; i < hdata.length; i++)
		{
			auto ix = hdata[i];
			if (ix != -1)
			{
				auto firstLink = ix;
				intptr_t chainct = 1;
				auto minlink = firstLink;
				ix = links[ix].next;
				while (ix != firstLink)
				{
					chainct++;
					if (ix < minlink)
						minlink = ix;
					ix = links[ix].next;
				}
				if (lowlink[minlink] == -1)
				{
					lowlink[minlink] = chainct;
					if (chainct >= result.length-1)
				    {
						result.length = chainct + 2;
					}
					result[chainct+1] += 1;
				}
			}
			else
				emptybuckets++;
		}
        result[1] = cast(uint) emptybuckets;
        return result;
    }

	void append(void[] keys, void[] values)
	{
		auto valuesize = values_.dti.tsize();           // value size
		auto keysize = keys_.dti.tsize();               // key size
		auto klen = keys.length;	
		assert(klen == values.length);

		for (size_t j = 0; j < klen; j++)
		{   
			appendPair( keys.ptr + j * keysize,  values.ptr + j * valuesize);
		}
	}
	
	void release()
	{
		refcount_--;
		if (refcount_ == 0)
		{
			debug (DEVTEST) {
				writeln("ArrayMap released!");
			}
			clear();
			delete this;
		}
	}
	dg2_t getAppendDg()
	{
		return &appendPair;
	}

	void addref()
	{
		refcount_++;
	}

	final int appendPair(void* pkey, void* pvalue)
	{
		intptr_t ix;
		findPut(pkey, ix);
		values_.assign(ix, pvalue);
		return 0;
	}

	void init(KeyValueArrayMap caa)
	{
		keys_.dti = caa.keys_.dti;
		//keys_.copyFn = caa.keys_.copyFn;
		values_.dti = caa.values_.dti;
		//values_.copyFn = caa.values_.copyFn;
		refcount_ = 1;
	}

	/// Get empty configured implementation

	IAA emptyClone()
	{
		auto aa = new KeyValueArrayMap();
		aa.init(this);
		return aa;
	}
	/// get pokeable value slot. Ignore value size and keyti, 
	/// because keyti_ and valueti_ need to have aleady been setup.
	/// as they are required for array memory allocation.
	void* getX(void* pkey, out bool existed)
	{
		intptr_t ix;
		existed = findPut(pkey, ix);
		return values_.vptr(ix);
	}

	/// Return existing or null
	void* inX(const void* pkey)
	{
		if (nodes_ == 0)
			return null;
		auto ix = findKeyHash(pkey, keys_.dti.getHash(pkey));
		return (ix >= 0) ? values_.vptr(ix) : null;
	}

	/// implement initialisation from a literal
	/+ Not going to work
	void init(TypeInfo_AssociativeArray ti, void[] keys, void[] values)
	{
		values_.dti = ti.next;           // value size
		keys_.dti = ti.key;
		auto klen = keys.length;
		assert(klen == values.length);
		setArrays(keys,values);
	
	}
	+/
	/// TODO: test if works.
	bool equals(IAA other, TypeInfo_AssociativeArray rawTi)
	{
		Interface* p1 = cast(Interface*)other;
		Object o1 = cast(Object)(*cast(void**)p1 - p1.offset);

		auto  saa = cast(KeyValueArrayMap) o1;

		if (saa is null) 
			return false;
		if (nodes_ != other.length)
			return false;
		auto ktype = keys_.dti;
		auto vtype = values_.dti;
		/// will string==char[] work ? if not cook your own.
		if (ktype !is other.keyType() || vtype !is other.valueType())
			return false;

		for(auto ix = 0; ix < keys_.length; ix++)
		{
			if ((hash_[ix] & EMPTY_BIT) == 0)
			{
				void* vptr = other.inX(keys_.vptr(ix));
				if (vptr is null)
					return false;
				if (vtype.compare( values_.vptr(ix), vptr)!=0)
						return false;
			}
		}	
		return true;
	}
	/// return unique copy of array of keys
	ArrayRet_t keys()
	{
		if (!nodes_)
			return null;
		UntypedArray ka;

		ka.dti = keys_.dti;
		ka.reserve(nodes_);

		for(auto ix = 0; ix < keys_.length; ix++)
		{
			if ((hash_[ix] & EMPTY_BIT) == 0)
			{
				ka.append(keys_.vptr(ix));
			}
		}	

		ArrayD a;
		ka.transfer(a);
		return *cast(ArrayRet_t*)(&a);
	}
	/// return unique copy of array of keys
	ArrayRet_t values()
	{
		if (!nodes_)
			return null;
		UntypedArray ka;

		ka.dti = values_.dti;
		ka.reserve(nodes_);

		for(auto ix = 0; ix < keys_.length; ix++)
		{
			if ((hash_[ix] & EMPTY_BIT) == 0)
			{
				ka.append(values_.vptr(ix));
			}
		}	

		ArrayD a;
		ka.transfer(a);
		return *cast(ArrayRet_t*)(&a);
	}
	/+ Not going to work
	void init(TypeInfo_AssociativeArray ti, size_t aalen, ...)
	{
		values_.clear();
		keys_.clear();
		values_.dti = ti.next;           // value size
		keys_.dti = ti.key;

		auto valuesize = values_.dti.tsize;         // value size
		auto keysize = keys_.dti.tsize();  


		if (aalen == 0 || valuesize == 0 || keysize == 0)
		{
		}
		else
		{
			va_list q;
			version(X86_64) va_start(q, __va_argsave); else va_start(q, aalen);
			
			keys_.reserve(aalen);
			values_.reserve(aalen);

			size_t keystacksize   = (keysize   + int.sizeof - 1) & ~(int.sizeof - 1);
			size_t valuestacksize = (valuesize + int.sizeof - 1) & ~(int.sizeof - 1);

			for (size_t j = 0; j < aalen; j++)
			{   
				keys_.append(q);
				q += keystacksize;
				values_.append(q);
				q += valuestacksize;
		    }
			rehash();
			va_end(q);
		}
	}
	+/
	
	/// Typeinfo for key.
	TypeInfo keyType()
	{
		return keys_.dti;
	}

	/// Typeinfo for value.
	TypeInfo valueType()
	{
		return values_.dti;
	}

	/// rehash.  Return IAA
	IAA rehash()
	{
		reindex(nodes_);
		return this;
	}
	
	class KeyRange : IKeyRange
	{
		intptr_t ix_ = -1;
		
		this()
		{
			popFront();
		}

		void popFront()
		{
			ix_++;
			while(ix_ < this.outer.hash_.length)
			{
				if ((this.outer.hash_[ix_] & EMPTY_BIT)==0)
					return;
				ix_++;
			}
		}

		AAKeyRef front()
		{
			return this.outer.keys_.vptr(ix_);
		}
		bool empty()
		{
			return (ix_ < this.outer.hash_.length);
		}
	}

	class ValueRange : IValueRange
	{
		intptr_t ix_ = -1;

		this()
		{
			popFront();
		}

		void popFront()
		{
			ix_++;
			while(ix_ < this.outer.hash_.length)
			{
				if ((this.outer.hash_[ix_] & EMPTY_BIT)==0)
					return;
				ix_++;
			}
		}

		AAValueRef front()
		{
			return this.outer.values_.vptr(ix_);
		}
		bool empty()
		{
			return (ix_ < this.outer.hash_.length);
		}
	}

	/// Range interface for keys
	IKeyRange		byKey()
	{
		return new KeyRange();
	}

	/// Range interface for values
	IValueRange		byValue()
	{
		return new ValueRange();
	}
	/// Return existing or null. valuesize not used in builtin. Same as inX
	void* getRvalueX(const void* pkey)
	{
		if (nodes_ == 0)
			return null;
		auto ix = findKeyHash(pkey, keys_.dti.getHash(pkey));
		return (ix >= 0) ? values_.vptr(ix) : null;		
	}
	/// delete all matching keys
	bool delX(void* pkey)
	{
		return (unlinkAll(pkey) > 0);	
	}

	int apply(dg_t dg)
	{
		for(auto ix = 0; ix < hash_.length; ix++)
		{
			if ( (hash_[ix] & EMPTY_BIT) == 0)
			{
				auto result = dg(keys_.vptr(ix));
				if (result)
					return result;

			}
		}
		return 0;
	}

	int apply2(dg2_t dg)
	{
		for(auto ix = 0; ix < hash_.length; ix++)
		{
			if ( (hash_[ix] & EMPTY_BIT) == 0)
			{
				auto result = dg(keys_.vptr(ix), values_.vptr(ix));
				if (result)
					return result;

			}
		}
		return 0;
	}


	/// setup types
	/+ Not going to work
	void init(TypeInfo_AssociativeArray aati)
	{
		extractAATypeInfo(aati, keys_.dti, values_.dti);
	}
	+/

	/// setup types
	void init(TypeInfo kti, TypeInfo  vti)
	{
		keys_.dti = kti;
		values_.dti = vti;
		refcount_ = 1;
	}
	/** clear everything, maybe setup again */
	final void clear()
	{
		version(NoGarbageCollection)
		{
			bool delNow = true;
		}
		else {
			bool delNow = false;
		}
		hlinks_.free(delNow);
		hmap_.free(delNow);
		freelinks_ = -1;
		nodes_ = 0;
		hash_.free(delNow);
		capacity_ = 0;
		mapcap_ = 0;
		/// unarray always deletes
		keys_.clear();
		values_.clear();
	}
}

IAA makeAA( TypeInfo kti,  TypeInfo vti)
{
	auto aa = new KeyValueArrayMap();
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
