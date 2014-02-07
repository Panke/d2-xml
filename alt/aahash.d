module alt.aahash;

/**
A very literal adaption of the D runtime implementation, but as an independent module. Single linked bucket list.
Method getNode operation takes a pointer to memory as its only a read.
Method putNode must be a reference to the key type.

Lookups are a bit slower than druntime.  Why?
*/

import alt.blockheap;
import alt.hashutil;
import alt.zstring;
import std.stdint;
import std.traits;

private import core.memory;

version(NoGarbageCollection)
{
	private enum DoDeletes = true;
}
else {
	private enum DoDeletes = false;
}


package enum  NodeOp {op_get, op_getlocal, op_del };

// Round up size of HashVoidImpl to nearest power of 2,  using binit.length
private struct HashAAImpl(K,V)
{
	static struct AANode(K,V)
	{
		AANode!(K,V) *next_;
		hash_t hash_;
		K	   key_;
		V	   value_;
	}

    static if (isSomeString!K)
    {

        static if (is(K==string))
        {
            alias const(char)[] LK;
        }
        else static if (is(K==wstring))
        {
            alias const(wchar)[] LK;
        }
        else static if (is(K==dstring))
        {
            alias const(dchar)[] LK;
        }
    }
    else {
		alias K LK;
    }

	alias HashAAImpl!(K,V)	SameTypeImpl;
	alias AANode!(K,V)		bucket;
	alias bucket*			hbucket;
	static Array!BlockHeap	gHeaps_; // using these heaps in thread.

	static ~this()
	{
		foreach(ref h ; gHeaps_.toArray())
		{
			auto dh = h;
			h = null;
			delete dh;
		}
	}
	/// get an existing heap of reusable nodes in this thread. Will never actually delete any blocks?
	/// TODO: Thread cleanup?
	static BlockHeap getHeap(uintptr_t nodeSize)
	{
		auto heaps = gHeaps_.toArray();
		if (heaps.length > 0)
		{
			for(auto ix = 0; ix < heaps.length; ix++)
			{
				auto heap = heaps[ix];
				if (heap.nodeSize == nodeSize)
					return heap;
			}
		}
		auto result = new BlockHeap(nodeSize);
		gHeaps_.put(result);
		return result;
	}

	hbucket[]			b_;
	TypeInfo			keyti_;    
    BlockHeap			heap_;		
	bool				sharedHeap_;

	
	uintptr_t		refcount_;	 
    uintptr_t		nodes_;		 // total number of entries in the hash table.
    uintptr_t		capacity_;   // maximum number before a resize of hbucket, and redistribution.	
	//ratio of buckets to bucket array size. After about 2.0, performance is getting clogged, with longish chains.
	//better hashing allows more even distribution.
    double minRatio_ = 0.6;  // lower limit, set after rehash.
	enum double maxRatio_ = 3.3; // upper limit, sets capacity trigger for rehash

	this(uintptr_t preAlloc)
	{
		keyti_ = typeid(K);

		if (preAlloc > 0)
		{
			heap_ = new BlockHeap(bucket.sizeof,0);
			heap_.preAllocate(preAlloc);	
			sharedHeap_ = false;
		}
		refcount_ = 1;
	}

	this(BlockHeap heap)
	{
		keyti_ = typeid(K);
		heap_ = heap;
		if (heap_)
			sharedHeap_ = true;
		refcount_ = 1;
	}

	~this()
	{
		clear();
	}

	void addref()
	{
		refcount_++;
	}

	void release(bool del)
	{
		if ( refcount_ > 0)
		{
			refcount_--;
			if (!refcount_)
			{
				if (del)
				{
					this.clear();
					version(NoGarbageCollection)
					{
						GC.free(this);
					}
				}
			}
		}
	}

    private void freeNode(hbucket e)
    {
		.clear(*e);
		if (heap_)
			heap_.collect(e);
    }

    // get pointer to stored key, if it exists, else
    package final const(K)* getKeyPtr(ref LK pkey)
    {
        auto e = getNode(&pkey);
        return (e is null) ? null
                : &e.key_;
    }

	static struct NodeReturn {
		hbucket			node_;
		hbucket*		pnode_;
		hash_t			hash_ = 0;
	}

	static struct NodeRef {
		private {
			hbucket			node_ = null;
		}

		bool valid() @property const
		{
			return (node_ !is null);
		}
		ref V value() @property
		{
			return node_.value_;
		}
	}

	// find only for lookup.
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
			if (key_hash == e.hash_)
			{
				if (keyti_.compare(&e.key_, pkey)==0)
				{
					return e;
				}
			}
            e = e.next_;
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
			if (key_hash == e.hash_)
			{
				if (keyti_.compare(&e.key_, pkey)==0)
				{
					fix.hash_ = 0;
					fix.node_ = e;
					fix.pnode_ = pe;
					return true;
				}
			}
            pe = &e.next_;
        }
		fix.node_ = null;
		fix.pnode_ = pe;
		fix.hash_ = key_hash;
		return false;
	}

	final void delNode(ref NodeReturn ret)
	{
		(*ret.pnode_) = ret.node_.next_;
		nodes_--;
		.clear(*ret.node_);
		if (heap_)
			heap_.collect(ret.node_);
		else
			GC.free(ret.node_);
	}

	final hbucket getNode(const void* pkey)
	{
		NodeReturn ret = void;
		return findKey(pkey,ret) ? ret.node_ : null;
	}

	/// insert, replace
    final hbucket putNode(ref K pkey) 
    {       
		if (b_.length == 0)
			capacity(7);
		NodeReturn ret;
		if (findKey(&pkey, ret))
		{
			return ret.node_;
		}
		hbucket e = void;
		if (heap_ is null)
		{
			e = cast(hbucket) GC.calloc(bucket.sizeof);
			//memset(e, 0, bucket.sizeof);
		}
		else
			e = cast(hbucket) heap_.allocate();
		e.key_ = pkey;
        e.hash_ = ret.hash_;
		(*ret.pnode_) = e;
        nodes_++;
        if (nodes_ > capacity_)
            grow_rehash();
        return e;
    }


    private  void resizeTable(size_t nlen)
    {
		auto oldData = b_;
		
		// NO_INTERIOR helps stop pointer aliasing
		auto ptr = cast(hbucket*) GC.malloc( nlen * hbucket.sizeof, GC.BlkAttr.NO_INTERIOR);
		b_ = ptr[0..nlen];
		b_[] = null;

		capacity_ = cast(size_t)(nlen * maxRatio_);
		auto pnew = b_.ptr;
		foreach(e ; oldData)
        {
            while(e !is null)
            {
                hbucket aaNext = e.next_;
                e.next_ = null;
                auto key_hash = e.hash_;
                hbucket* pe = &pnew[key_hash % nlen];
                while (*pe !is null)
                {
                    pe = &(*pe).next_;
                }
                *pe = e;
                e = aaNext;
            }
        }
    }

    // capacity sets the size of the table of node pointers.
    void capacity(size_t cap)
    {
        if (cap < nodes_)
            cap = nodes_;
        size_t nlen = cast(size_t)(cap / maxRatio_);

        nlen = getNextPrime(nlen);

        resizeTable(nlen);
    }

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
        foreach(e ; b_)
        {
            if(e !is null)
            {
                uint listct = 0;
                while (e !is null)
                {
                    listct++;
                    e = e.next_;
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


    /// capacity exceeded, grow much bigger, avoid frequent rehash
    private void grow_rehash()
    {
		rehash();
		return;
    }

    void rehash()
    {
        auto nlen = getNextPrime(cast(uintptr_t)(nodes_/minRatio_));
        if (nlen != b_.length)
            resizeTable(nlen);
        return;
    }


    void clear()
    {
		// each individual node needs cleaning
		if (nodes_)
		{
			foreach(e ; b_)
			{
				while(e !is null)
				{
					hbucket nxptr = e.next_;
					freeNode(e);
					e = nxptr;
				}
			}
		}
		b_ = null;
        if (heap_ && !sharedHeap_)
		{
			delete heap_;
		}
		nodes_ = 0;
		capacity_ = 0;
    }

	alias KeyValueBlock!(K,V,true)	SortableBlock;

	/// return a sortable block of key value pairs
	auto sortableBlock()
	{
		SortableBlock result;
		
		result.capacity = nodes_;

		if (nodes_ > 0)
		{
			foreach(e ; b_)
			{
				while (e !is null)
				{
					result.put(SortableBlock.BlockRec(e.key_, e.value_));
					e = e.next_;
				}
			}
		}
		return result;
	}

    auto  values()
    {
        Array!V	result;

        if(nodes_ > 0)
        {
			result.reserve(nodes_,true);
			foreach(e ; b_)
			{
				while (e !is null)
				{
					result.put(e.value_);
					e = e.next_;
				}
			}
		}
		return result;
    }

    auto keys()
    {
        Array!K result;

        if(nodes_ > 0)
        {
			result.reserve(nodes_,true);
            foreach(e ; b_)
            {
                while (e !is null)
                {
					result.put(e.key_);
                    e = e.next_;
                }
            }
        }
        return result;
    }
    intptr_t applyValues(dg_t dg)
    {
        intptr_t result;
        foreach (e; b_)
        {
            while (e !is null)
            {
                hbucket nx = e.next_;
                result = dg(&e.value_);
                if (result || nodes_ == 0)
                    break;
                e = nx;
            }
        }
        return result;
    }

    equals_t dataMatch(ref HashAAImpl other)
    {
        if (other.nodes_ != nodes_)
            return false;

        auto valueti = typeid(V);
        foreach (e; b_)
        {
            while (e !is null)
            {
                auto test = other.getNode(&e.key_);
                if (test is null)
                    return false;
                if (!valueti.equals(&e.value_, &test.value_))
                    return false;
                e = e.next_;
            }
        }
        return true;
    }

    intptr_t applyKeyValues(dg2_t dg)
    {
        intptr_t result;
        foreach (e; b_)
        {
            while (e !is null)
            {
                hbucket nx = e.next_;
				auto tempKey = e.key_;
                result = dg(&tempKey, &e.value_);
                if (result || nodes_ == 0)
                    break;
                e = nx;
            }
        }
		return result;
    }

    intptr_t applyKeys(dg_t dg)
    {
        intptr_t result;
        foreach (e; b_)
        {
            while (e !is null)
            {
                hbucket nx = e.next_;
				auto tempKey = e.key_;
                result = dg(&tempKey); /// not getting the original
                if (result || nodes_ == 0)
                    break;
                e = nx;
            }
        }
		return result;
    }
	struct Range {
		hbucket[]	slots_;
		hbucket	    current_;
		SameTypeImpl*		paa_;

		this(SameTypeImpl* aa)
		{
			paa_ = aa;
			paa_.addref();
			slots_ = paa_.b_;
			nextSlot();
		}
		~this()
		{
			paa_.release(true);
		}

		void nextSlot()
		{
			foreach(i , slot ; slots_)
			{
				if (!slot) 
					continue;
				current_ = slot; 
				slots_ = slots_.ptr[i..slots_.length]; // is slots_[i..$] different?
				break;
			}
		}
	public:
		bool empty() const @property
		{
			return (current_ is null);
		}
		ref inout(bucket) front() inout @property
		{
			assert(current_);
			return *current_;
		}
		void popFront()
		{
			assert(current_);
			current_ = current_.next_;
			if (!current_)
			{
				slots_ = slots_[1..$];
				nextSlot();
			}
		}

	}

    auto byValue()  @property 
    {
        static struct Result
        {
            Range state;

            this(SameTypeImpl* paa)
            {
                state = Range(paa);
            }

            ref V front() @property 
            {
                return state.front.value_;
            }

            alias state this;
        }
        return Result(&this);
	}

    auto byKey()  @property 
    {
        static struct Result
        {
            Range state;

            this(SameTypeImpl* paa)
            {
                state = Range(paa);
            }

            ref K front() @property 
            {
                return state.front.key_;
            }

            alias state this;
        }
        return Result(&this);
	}
}


struct HashTable(K, V)
{
	alias  HashAAImpl!(K,V) AAImpl;
	
	alias HashTable!(K,V)	MyType;

    static if (isSomeString!K)
    {

        static if (is(K==string))
        {
            alias const(char)[] LK;
        }
        else static if (is(K==wstring))
        {
            alias const(wchar)[] LK;
        }
        else static if (is(K==dstring))
        {
            alias const(dchar)[] LK;
        }
    }
    else {
		alias K LK;
    }


    private AAImpl* aa_;



	/// Post-Blit - Now I really am in trouble. 
	this(this)
	{
		if (aa_)
		{
			if (aa_.refcount_ > 0)
				aa_.refcount_++;
		}
	}
	~this()
	{
		deallocate(DoDeletes);
	}

	private void deallocate(bool del=false)
	{
		if (aa_)
		{
			aa_.release(del);
			aa_ = null;
		}
	}
    /** A call to setup always creates a new implementation object, overwriting the
        instance created by a previous setup.
        Overwriting does not delete pre-existing implementation object, which
        may be aliased.

        ---
        DRHashMap!(uint[uint]) aa;

        aa.setup; // optional setup, default, do not hash integer/float/char keys
        ---

        OR
         ---
        DRHashMap!(uint[uint]) aa;

        aa.setup(true); //optional setup, use normal hashing.
        ---

       If hashSmall is false (default), then key integer bitty values are stored
       directly in the hash field, as themselves without doing a hash.
       This can be a bit faster for these keys.

       The call to setup will be automatic if it is not called first deliberatedly.

    */

    void setup(uint preAllocate = 0)
    {
        aa_ = new AAImpl(preAllocate);
    }

    /// Return if the implementation is already initialised.
    bool isSetup()
    {
        return ( aa_ !is null);
    }
    /// support "in" operator
    V* opIn_r(ref LK key)
    {

        if (aa_ is null)
            return null;
		auto e = aa_.lookupKey(&key);
		return e is null ? null : &e.value_;
    }

    /// Return the value or throw exception
    V opIndex(ref LK key)
    {
        if (aa_ !is null)
        {
            auto e = aa_.lookupKey(&key);
            if (e !is null)
            {
                return e.value_;
            }
        }
        throw new AAKeyError("no key for opIndex");
    }
    /// support "in" operator
    V* opIn_r(LK key)
    {

        if (aa_ is null)
            return null;
		auto e = aa_.lookupKey(&key);
		return e is null ? null : &e.value_;
    }

    /// Return the value or throw exception
    V opIndex(LK key)
    {
        if (aa_ !is null)
        {
            auto e = aa_.lookupKey(&key);
            if (e !is null)
            {
                return e.value_;
            }
        }
        throw new AAKeyError("no key for opIndex");
    }

    /// Insert or replace. Will call setup for uninitialised AA.
    void opIndexAssign(V value, K key)
    {
        if (aa_ is null)
            setup();
        auto e = aa_.putNode(key);
        e.value_ = value;
    }


    /// Insert or replace. Return true if insert occurred.
    bool putInsert(K key, ref V value)
    {
        if (aa_ is null)
            setup();
        auto before_nodes = aa_.nodes_;
        auto e = aa_.putNode(key);
        e.value_ = value;
        return (aa_.nodes_ > before_nodes);
    }

    /// Insert or replace.
    void put(K key, ref V value)
    {
        if (aa_ is null)
            setup();
        auto e = aa_.putNode(key);
		e.value_ = value;
    }

    /// Get the value or throw exception
    V get(LK key, lazy V value)
    {
		if (aa_ is null)
			return value;
		auto e = aa_.lookupKey(&key);
		return (e is null) ? value : e.value_;
    }
    /// Return if the key exists.
    bool contains(LK key)
    {
        if (aa_ is null)
            return false;
        return  aa_.lookupKey(&key) !is null;
    }
    /// Get the value if it exists, false if it does not.
    bool get(LK key, ref V val)
    {
        if (aa_ !is null)
        {
            auto e = aa_.lookupKey(&key);
            if (e !is null)
            {
                val = e.value_;
                return true;
            }
        }
        return false;
    }

    /**
        Set the capacity, which cannot be made less than current number of entries.
        The actual capacity value achieved will usually larger.
        Table length is set to be (next prime number) > (capacity / load_ratio).
        Capacity is then set to be (Table length) * load_ratio;
    */
    @property void capacity(size_t cap)
    {
        //version(TEST_DRAA) writefln("capacity %s ",cap);
        if (aa_ is null)
            setup();

        aa_.capacity(cap);
    }
    /** Return threshold number of entries for automatic rehash after insertion.
    */
    @property size_t capacity()
    {
        if (aa_ is null)
            return 0;
        return aa_.capacity_;
    }

    /**
		
    */
    @property void minRatio(double ratio)
    {
        if (aa_ is null)
            setup();
        aa_.minRatio_ = ratio;
    }

    /**
        Return the current loadRatio
    */
    @property double minRatio()
    {
        if (aa_ is null)
            return 0.0;
        else
            return aa_.minRatio_;
    }
    /**
        Return the number of entries
    */
    @property final size_t length()
    {
        return (aa_ is null) ? 0 : aa_.nodes_;
    }


    /**
        Call remove for each entry. Start afresh.
    */

    @property void clear()
    {
        if (aa_ !is null)
        {
            aa_.clear();
        }
    }

    /**
        Optimise table size according to current number of nodes and loadRatio.
    */
    @property void rehash()
    {
        if (aa_ !is null)
        {
            aa_.rehash();
        }
    }
    /// Test if both arrays are empty, the same object, or both have same data
    bool equals(ref HashTable other)
    {
        auto c1 = aa_;
        auto c2 = other.aa_;

        if (c1 is null)
            return (c2 is null);
        else if (c2 is null)
            return false;

        return c1.dataMatch(*c2);
    }

    /// Non-optimised function to append all the keys from other onto this.
    void append(ref HashTable other)
    {
        if (!other.isSetup())
            return;
        if (aa_ is null)
            setup();

        foreach(key, value ; other)
        {
            this[key] = value;
        }

    }
    /// Delete the key and return true if it existed.
    bool remove(LK key)
    {
        if (aa_ is null)
            return false;
		AAImpl.NodeReturn ret;
		if (aa_.findKey(&key, ret))
			aa_.delNode(ret);
        return false;
    }

    /** Return the value and remove the key at the same time.
        Return false if no key found.
    */

    bool remove(LK key, ref V value)
    {
        if (aa_ !is null)
        {
			AAImpl.NodeReturn ret;
			if (aa_.findKey(&key,ret))
			{
				value = ret.node_.value_;
				aa_.delNode(ret);
				return true;
			}
        }
        return false;
    }

    public int eachKey(int delegate(ref K key) dg)
    {
        return (aa_ is null) ? 0 : aa_.applyKeys(cast(dg_t) dg);
    }
    /**
        foreach(value)
    */
    public int opApply(int delegate(ref V value) dg)
    {
        return (aa_ is null) ? 0 :  aa_.applyValues(cast(dg_t) dg);
    }
    /**
        foreach(key, value)
    */
    public int opApply(int delegate(ref K key, ref V value) dg)
    {
        return (aa_ is null) ? 0 : aa_.applyKeyValues(cast(dg2_t) dg);
    }

    /**
        Return all keys.
    */
    @property
    auto keys()
    {
		Array!K	result;
		if (aa_ !is null)
			result = aa_.keys();
		return result;
    }
    /**
        Return all values.
    */
    @property
    auto values()
    {
		Array!V result;
		if (aa_ !is null)
			result = aa_.values();
		return result;

    }

    /**
        Return all keys and values.
    */
    auto sortableBlock()
    {
		AAImpl.SortableBlock result;
		if (aa_ !is null)
			result = aa_.sortableBlock();
		return result;
    }

    /**
        Return <hash table length>, <empty buckets>,  <buckets of length 1>, [<buckets of length #>]
        Result will be of length 2 or more.
    */
    @property uint[] list_stats()
    {
        if (aa_ is null)
        {
            return new uint[2];
        }
        else
        {
            return aa_.statistics();
        }
    }

	alias AAImpl.NodeRef NodeRef;

	NodeRef getNode(ref LK key)
	{
		return (aa_ is null) ? NodeRef(null) : NodeRef(aa_.lookupKey(&key));
	}
}



unittest {
	alias Array!char arrayChar;

	alias HashTable!(arrayChar, arrayChar)	StringMap;
	
	// cannot set directly from string, like testAA["key2"] = "value2";
	// can assign indirect
	arrayChar k1 = "key1";
	arrayChar v1 = "value1";

	StringMap m1;
	
	m1[k1] = v1;
	
	auto m2 = m1;

	assert(m2[k1] == v1);
	
}