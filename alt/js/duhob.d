module alt.duhob;

import alt.blockheap, alt.hashutil;
import std.stdint, std.conv, std.traits;
/* test object dispatch */

private import core.memory;

class DuhString {
	string	str_;

	this(string s)
	{
		str_ = s;
	}

	hash_t toHash() const @safe
	{
		immutable end = str_.length;
		uintptr_t ix = 0;
		hash_t result = end;
		while (ix < end)
		{
			result += str_[ix] * 13;
		}
		return result;
	}
}
class DuhInteger {
	long	num_;

	this(long n)
	{
		num_ = n;
	}

	hash_t toHash() const @safe
	{
		return typeid(long).getHash(&num_);
	}
}
struct ObjPair {
	ObjPair*	next_;
	hash_t		hash_;
	Object		key_;
	Object		value_;
}

private alias ObjPair* ubucket;

private enum DuhTableOp {
		GET,
		GET_LOCAL,
		PUT,
		DEL
}

class DuhObjAA  {
	ubucket[]			buckets_;
	uintptr_t			nodes_;
	uintptr_t			capacity_; // resize trigger
	ObjPair				nullBucket_;
	bool				hasNull_;
	ubucket[7]			binit;
	enum double loadRatio_ = 1.0;
	DuhObjAA			chain_;

	private static	BlockHeap*	gBucketHeap;


	struct NodeRef {
		private ubucket ref_;
		private this(ubucket b)
		{
			ref_ = b;
		}
		bool valid() @property const
		{
			return (ref_ !is null);
		}
		Object value() @property
		{
			return ref_.value_;
		}
		void value(Object val) @property
		{
			ref_.value_ = val;
		}
	}

	struct Range {
		ubucket[]	slots_;
		ubucket		current_;

		this(DuhObjAA aa)
		{
			slots_ = aa.buckets_;
			nextSlot();
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
		ref inout(ObjPair) front() inout @property
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
	static this()
	{
		gBucketHeap = new BlockHeap(null);
		gBucketHeap.setup(ObjPair.sizeof);
	}
	this()
	{
		buckets_ = binit;
		capacity_ = cast(size_t)(buckets_.length * loadRatio_);
	}
	private ubucket getNode(Object key, DuhTableOp op)
	{
		if (key is null)
		{
			final switch(op)
			{
				case DuhTableOp.GET_LOCAL:
					return (hasNull_ ? &nullBucket_ : null);
				case DuhTableOp.GET:
					if (hasNull_)
						return &nullBucket_;
					if (chain_ !is null)
						return chain_.getNode(null,DuhTableOp.GET);
					return null;
				case DuhTableOp.PUT:
					return &nullBucket_;
				case DuhTableOp.DEL:
					if (!hasNull_)
						return null;
					hasNull_ = false;
					return &nullBucket_;
			}
		}
		ubucket e = void;
		ubucket* pe = void;	// pointer to pointer
		hash_t key_hash = key.toHash();
		pe = &buckets_[key_hash % $];
		for(;;)
		{
			e = *pe;
			if (e is null)
				break;
			// object defined comparison may get weird results, if not object type equivalent.
			if ((key_hash == e.hash_)&&(key.opEquals(e.key_)))
			{
				if (op == DuhTableOp.DEL)
				{
					*pe = e.next_;
					nodes_--;
				}
				return e;
			}
			pe = &e.next_; // hash collision?
		}
		// Not found
		// for readonly lookup, can use the chain_
		if (op == DuhTableOp.GET)
		{
			if (chain_ !is null)
				return chain_.getNode(key,DuhTableOp.GET);
			return null;
		}
		if (op == DuhTableOp.PUT)
		{
			e = cast(ubucket) gBucketHeap.allocate();
			e.key_ = key;
			e.hash_ = key_hash;
			*pe = e;
			nodes_++;
			if (nodes_ > capacity_)
				grow_rehash();
			return e;
		}
		return null; // not found and not create
	}

	NodeRef reference(Object key)
	{
		return NodeRef(getNode(key, DuhTableOp.GET));
	}
	NodeRef unchained(Object key)
	{
		return NodeRef(getNode(key, DuhTableOp.GET_LOCAL));
	}

    private void grow_rehash()
    {
        auto nlen = cast(uintptr_t)(nodes_ / loadRatio_);
        nlen = getNextPrime(nlen);
        if (nlen > buckets_.length)
            resizeTable(nlen);
        capacity_ = cast(uintptr_t)(buckets_.length * loadRatio_);
        return;
    }

    private  void resizeTable(size_t nlen)
    {
		// GC will need to peek into these objects,
		// unless take over memory management completely,
		// 
		auto vptr = GC.calloc(ubucket.sizeof * nlen);
        auto newtable = (cast(ubucket*)vptr)[0..nlen];

        if (nodes_)
            foreach (e; buckets_)
			{
				while(e !is null)
				{
					auto aaNext = e.next_;
					e.next_ = null;
					// TODO: possibility of null key?
					// or Null object ? hash_t == 0
					auto pe = &newtable[e.hash_ % $];
					while (*pe !is null)
					{
						pe = &(*pe).next_;
					}
					*pe = e;
					e = aaNext;
				}
			}
        if (buckets_.ptr == binit.ptr)
        {
            binit = null;
        }
        else
            delete buckets_;
        buckets_ = newtable;
        capacity_ = cast(size_t)(buckets_.length * loadRatio_);
    }

	/// set another table for lookups.
	void chain(DuhObjAA table)
	{
		if (table !is this)
			chain_ = table;
	}
	Object opIndex(Object key)
	{
		ubucket b = getNode(key,DuhTableOp.GET);
		return (b is null) ? null : b.value_;
	}
	Object opIndex(string s)
	{
		ubyte[__traits(classInstanceSize, DuhString)]  temp;
		DuhString key = emplace!(DuhString,string)(cast(void[])temp,s);
		ubucket b = getNode(key,DuhTableOp.GET); // get won't store the key
		return (b is null) ? null : b.value_;
	}
	Object opIndex(long n)
	{
		ubyte[__traits(classInstanceSize, DuhInteger)]  temp;
		auto key = emplace!(DuhInteger,long)(cast(void[])temp,n);
		ubucket b = getNode(key,DuhTableOp.GET);
		return (b is null) ? null : b.value_;
	}

	void remove(Object key)
	{
		ubucket b = getNode(key,DuhTableOp.DEL);
		if (b !is null)
		{
			*b = ObjPair.init;
			gBucketHeap.collect(b);
		}
	}

	void opIndexAssign(Object value,  Object key)
	{
		ubucket b = getNode(key,DuhTableOp.PUT);
		b.value_ = value;
	}
	void opIndexAssign(string s, string key)
	{
		auto skey = new DuhString(key);
		auto sval = new DuhString(s);
		opIndexAssign(sval,skey);
	}
	void opIndexAssign(Object s, string key)
	{
		DuhString	skey = new DuhString(key);
		opIndexAssign(s,skey);
	}

	void opIndexAssign(string s, long key)
	{
		DuhString	sval = new DuhString(s);
		DuhInteger	lkey = new DuhInteger(key);
		opIndexAssign(sval,lkey);
	}

    auto byKey()  @property 
    {
        static struct Result
        {
            Range state;

            this(DuhObjAA p)
            {
                state = Range(p);
            }

            ref Object front() @property 
            {
                return state.front.key_;
            }

            alias state this;
        }
        return Result(this);
	}

    public intptr_t opApply(int delegate(Object key, ref Object value) dg)
    {
		intptr_t result = 0;
		ubucket nx = void;
		foreach (e; buckets_)
		{
			while (e !is null)
			{
				nx = e.next_;
				result = dg(e.key_, e.value_);
				if (result || nodes_ == 0)
					break;
				e = nx;
			}
		}
		return result;
    }

	uintptr_t length() const @property
	{
		return nodes_;
	}

}


unittest {


}