module alt.arraymap;

/**
Array indexing implementation with hash map.

The KeyIndex template can be used to hash index an existing array.

Its use is extended in KeyValueIndex to provide a hash map index lookup.

Instead of using pointers to nodes, it has a separate arrays for
hash values, and array of double linked integer indexes,
and a map of the hash to link index.

The hash values and links should be treated by the D
memory management as not needing to be scanned pointers.

Arrays for Keys and Values will depend on the type provided by the templates.

It can support duplicate key entries, or unique keys
Unless deletions are followed by insertions, it will iterate in the order of insertion.

If no calls to free a key then the arrays are compact, without holes.

Empty slots are marked by setting the Hibit in the hash array entry,
and adding the associated index link record to the freelinks.

Links chains are made from duplicates or hash collisions.

After index removal, keys and values remain at same index until replaced by a further insertion.

The KeyIndex template, and the indexArray method can be used to index an existing array in place.

Performance gets slower than the builtin druntime hash map implementation.

Performance of KeyIndex will degrade if lots of duplicate keys.
Use findPut to maintain duplicate keys.



The code and algorithms have been adapted from the "Ultimate++" sources Index.h, Index.hpp Index.cpp,
and reworked as a single D module.  The arrangement and number of functions differ somewhat from the
original.

The Ultimate++ has an overall BSD license.

*/

/**
Authors: Michael Rynn, michaelrynn@optusnet.com.au
Date: October 14, 2010

 */

//import hash.util;
import std.variant;
import std.array;
import std.stdio;
import std.exception;
import std.stdint;
import std.conv;
import std.traits;

//version=FOLDHASH;
/**
	Insertion into a full array always results in incrementing the length
    of the hash_,  links_,  keys_,  values_ array.
	The insertion index is always shared between hash_, links_, keys_, values_.
	If a free link exists, then the index of that is used.

	The length_ indicates the number of occupied slots.
	If the length_ == hash_.length, then the arrays are full.
	Use capacity to help insertion times
*/
alias void delegate(uintptr_t newcap) SetCapDg;
alias void delegate(uintptr_t unsetIndex) IndexRemoveDg;

class ArrayMapError : Error {
	this(string s)
	{
		super(s);
	}
}

/**
    The principle of this is to store the linked list as an array index, not as pointers.
    For the 64 bit compiler, everything gets blown up to 64 bits.
    Since the links are not pointers, for hash table sizes < 2^31, maybe its worth keeping the link indexes as 32 bit int,
    with version LINK_MAP_32.  The table of primes is not setup for 64 bits as largest size is 2^31 - 1.
    Table capacity shrinkage is manual.
*/

version=LINK_MAP_32;

version(LINK_MAP_32)
{
    alias int intlink_t;

}
else {
    alias intptr_t intlink_t;
}

struct HashLinkMap {
	struct HLink {
		intlink_t   next;
		intlink_t	prev;
	}
	uintptr_t		capacity_; // reserved capacity for values
	uintptr_t		mapcap_;  // map loading capacity
	hash_t[]	    hash_;		// remember the hash values
	intlink_t[]		hmap_;		// map to links
	HLink[]		    hlinks_;
	intlink_t		freelinks_ = -1;
	double      loadRatio_ = 0.8;
	size_t		length_;   // active links
	SetCapDg	capdg_;
	IndexRemoveDg	removeDg_;

	enum { UNSIGNED_HIBIT = 0x80000000 }

version(FOLDHASH)
	static size_t hashBound(size_t i) { return getNextPower2(i); }
else
	static size_t hashBound(size_t i) { return getNextPrime(i); }

	/** For pre-emptive strike on memory */


	@property
	const size_t length() { return length_; }

	// return index and final form of hash to put in hash_

	intptr_t findLink(size_t h)
	{
		immutable hlen = hmap_.length;
		h = h & ~UNSIGNED_HIBIT;
		if(hlen == 0)
			return -1;
		version(FOLDHASH)
			return hmap_[(hlen - 1) & (((h >> 23) - (h >> 15) - (h >> 7) - h))];
		else
			return hmap_[h % hlen];
	}

	void assign(ref HashLinkMap hlm)
	{
		hlinks_ = hlm.hlinks_.dup;
		hmap_ = hlm.hmap_.dup;
		hash_ = hlm.hash_.dup;
		freelinks_ = hlm.freelinks_;
		loadRatio_ = hlm.loadRatio_;
		length_ = hlm.length_;
	}

	intptr_t findNext(intptr_t i)
	{
		auto q = hlinks_[i].next;
		immutable hlen = hmap_.length;
		size_t h = hash_[i];
		version(FOLDHASH)
			size_t ix = hmap_[(hlen - 1) & (((h >> 23) - (h >> 15) - (h >> 7) - h))];
		else
			size_t ix = hmap_[h % hlen];
		return (q == ix) ? -1 : q;
	}

	void unlink(intptr_t i)
	{

		assert(i < hash_.length);

		size_t h = hash_[i];
		assert((h & UNSIGNED_HIBIT) == 0);
		hash_[i] = h | UNSIGNED_HIBIT;
		length_--;
		if(i < hlinks_.length)
		{ // TODO: what about earlier check?
			HLink* h0 = &hlinks_[i];
			immutable hlen = hmap_.length;
			version(FOLDHASH)
				auto mptr = &hmap_[(hlen - 1) & (((h >> 23) - (h >> 15) - (h >> 7) - h))];
			else
				auto mptr = &hmap_[h % hlen];

			if(i == *mptr) {
				if(h0.next == i) {
					*mptr = -1;
					return;
				}
			}
			// unlink
			*mptr = h0.next;
			hlinks_[h0.next].prev = h0.prev;
			hlinks_[h0.prev].next = h0.next;

			// link to freelinks_;
			if(freelinks_ >= 0) {  // already linked to another value
				HLink* h2 = &hlinks_[freelinks_];
				h0.next = freelinks_;
				h0.prev = h2.prev;
				h2.prev = cast(intlink_t) i;
				hlinks_[h0.prev].next = cast(intlink_t) i;
			}
			else {
				freelinks_ = h0.prev = h0.next = cast(intlink_t)i;
			}
			if (removeDg_)
				removeDg_(i);
		}
	}

	/** the link and hash index is given, so just link it */
	void setLinkIndex(intptr_t f0, size_t hash)
	{
		immutable h = hash & ~UNSIGNED_HIBIT;
		immutable hlen = hmap_.length;
		hash_[f0] = h;
		length_++;
		version(FOLDHASH)
			auto mptr = &hmap_[(hlen - 1) & (((h >> 23) - (h >> 15) - (h >> 7) - h))];
		else
			auto mptr = &hmap_[h % hlen];
		immutable mval = *mptr;
		HLink* ink = &hlinks_[f0];
		if(mval >= 0) {  // already linked to another value
			HLink* h2 = &hlinks_[mval];
			ink.next = cast(intlink_t)mval;
			ink.prev = h2.prev;
			h2.prev = cast(intlink_t)f0;
			hlinks_[ink.prev].next = cast(intlink_t)f0;
		}
		else {
			*mptr = ink.prev = ink.next = cast(intlink_t)f0;
		}
	}



	/** make or get unused link for new hash */
	intptr_t makeLink(uintptr_t hash)
	{
		size_t hlen = hmap_.length;
		size_t hsize = hash_.length;

		auto f0 = freelinks_;
		if (f0 >= 0)
		{
			HLink* ink = &hlinks_[f0];
			freelinks_ = ink.next;
			if (f0 == freelinks_)
				freelinks_ = -1;
			else {
				hlinks_[ink.next].prev = ink.prev;
				hlinks_[ink.prev].next = ink.next;
			}
		}
		else
		{
			// are we full yet
			if (hsize+1 >= capacity_)
			{
				if (hsize == 0)
					hsize = 4;
				if (capdg_ !is null)
					capdg_(hsize*3);
				else
					setCapacity(hsize*3);
				//reindex(hsize+1);
			}
			else if (length_ +1 >= mapcap_)
			{
				reindex((length_ +1)*2);
			}

			f0 = cast(intlink_t)hlinks_.length;
			hash_ ~= f0;
			hlinks_ ~= HLink(f0,f0);

		}
		setLinkIndex(f0, hash);
		return f0;
	}

	/** clear everything, maybe setup again */
	void clear()
	{
		hlinks_ = null;
		hmap_ = null;
		freelinks_ = -1;
		length_ = 0;
		hash_ = null;
		capacity_ = 0;
		mapcap_ = 0;
	}

	void setCapacity(uintptr_t cap)
	{
		if (cap > 0)
		{
		    auto oldCapacity = capacity_;

			capacity_ = hlinks_.reserve(cap);
			size_t ncap = hash_.reserve(cap);
			if (ncap < capacity_)
				capacity_ = ncap;
			//if (hash_.length > 0)
			if (capacity_ != oldCapacity)
                reindex(cap);
		}
	}
	/** remap the hash values to links */
	private void reindex(uintptr_t n)
	{
		hlinks_.length = 0;
		freelinks_ = -1;
		//length_ = 0;   length_ does not change during this process == number of valid hash_[]

		size_t nlen = cast(size_t)(n / loadRatio_);
		hmap_.length = hashBound(nlen);
		mapcap_ = cast(size_t) (loadRatio_ * hmap_.length);
		hmap_[] = -1;
		finishIndex();
	}

	/** remap links  from hash_ to hlinks_ */
	private void finishIndex()
	{
		size_t llen = hlinks_.length;
		auto hsize = hash_.length;
		if (llen < hsize)
		{
			hlinks_.length = hsize;
			immutable hlen = hmap_.length;
			intlink_t * mptr = void;
			for(uintptr_t i = llen; i < hsize; i++)
			{
				auto h = hash_[i]; // convert hash into map index
				if ((h & UNSIGNED_HIBIT)==0)
				{
					version(FOLDHASH)
						mptr = &hmap_[(hlen - 1) & (((h >> 23) - (h >> 15) - (h >> 7) - h))];
					else
						mptr = &hmap_[h % hlen];
				}
				else
					mptr = &freelinks_;
				immutable mval = *mptr;
				HLink* f1 = &hlinks_[i]; // mapped to link with index i
				if(mval >= 0) {
					HLink* f2 = &hlinks_[mval];
					f1.next = mval;
					f1.prev = f2.prev;
					f2.prev = cast(intlink_t) i;
					hlinks_[f1.prev].next = cast(intlink_t)i;
				}
				else {
					*mptr = f1.prev = f1.next = cast(intlink_t)i;
				}
			}
		}
	}
}

/**
	Usage:
----
	string[] test = getStringSet(40,10_000);
	scope indx = new KeyIndex!(string[]);
	indx.indexArray(test);

	string lookForAll = "random hello";
	int i = indx.findKeyIndex(lookForAll);
	if (i >= 0)
	{
		// anymore?
		i = indx.nextKeyIndex(lookForAll,i);
	}
----
*/
class KeyIndex(K)
{
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


	protected {
		K[]	keys_;
		HashLinkMap	hlm_;
		TypeInfo    keyti_;



		/** Remove all entries for the key */
		final intptr_t unlinkKey(ref LK k, uintptr_t h)
		{
			intptr_t n = 0;
			auto q = hlm_.findLink(h);
			while(q >= 0)
			{
				auto w = q;
				q = hlm_.findNext(q);
				if(k == keys_[w])
				{
					hlm_.unlink(w);
					n++;
				}
			}
			return n;
		}
		/**  always adds a new entry */
		final intptr_t putHash(ref K k, uintptr_t _hash)
		{
			auto q = hlm_.makeLink(_hash);
			if (q >= keys_.length)
				keys_.length = q+1;
			keys_[q] = k;
			return q;
		}
		final intptr_t findKeyHash(ref LK k, uintptr_t _hash)
		{

			auto i = hlm_.findLink(_hash);
			while(i >= 0 && !(k == keys_[i]))
				i = hlm_.findNext(i);
			return i;
		}
	}

	this(KeyIndex ki)
	{
		keys_ = ki.keys_.dup;
		keyti_ = ki.keyti_;
		hlm_.assign(ki.hlm_);
		hlm_.capdg_ = &setCapacity;
	}

	this(K[] k)
	{
		keyti_= typeid(K);
		hlm_.capdg_ = &setCapacity;
		indexArray(k);
	}
	this()
	{
		keyti_= typeid(K);
		hlm_.capdg_ = &setCapacity;
	}

	final uintptr_t capacity() const
	{
		return hlm_.capacity_;
	}
	void setCapacity(uintptr_t cap) 
	{
		hlm_.setCapacity(cap);
		auto ncap = keys_.reserve(cap);
		if (ncap < hlm_.capacity_)
			hlm_.capacity_ = ncap;
	}

	// no entries are unlinked, no holes in key, values, hash_
	bool isCompact()
	{
		return (hlm_.freelinks_ == -1);
	}

	@property const uintptr_t length()
	{
		return hlm_.length_;
	}

	/** index a different array */
	void setKeys(K[] ak)
	{
		indexArray(ak);
	}
	/** get a copy? of all the current keys */
	@property K[] keys()
	{
	    if (hlm_.length_ == keys_.length)
            return keys_.dup;
		else
		{
			K[] nkey;
			nkey.length = hlm_.length_;
			auto hvalues = hashData();
			uint ct = 0;
			for(uint i = 0; i < hvalues.length; i++)
			{
				if ((hvalues[i] & HashLinkMap.UNSIGNED_HIBIT)==0)
					nkey[ct++] = keys_[i];
			}
			return nkey;
		}
	}
    @property double loadRatio()
    {
        return hlm_.loadRatio_;
    }

	// May be useful with key removal to treat keys and values
	void OnIndexRemoval(IndexRemoveDg dg)
	{
		hlm_.removeDg_ = dg;
	}

    @property void loadRatio(double ratio)
    {
		hlm_.loadRatio_ = ratio;
    }
	final const(uintptr_t)[] hashData() const
	{
		return 	hlm_.hash_;
	}
	// alias to and hash index the array
	final void indexArray(K[] ka)
	{
		keys_ = ka;
		hlm_.clear();
		uintptr_t ilen = keys_.length;
		setCapacity(ilen);
		hlm_.hash_.length = ilen;
		hlm_.hlinks_.length = ilen;
		for(uintptr_t i = 0; i < keys_.length; i++)
		{
			// assume duplicates are possible?
			// in this process, the link record is fixed by key position
			auto h = keyti_.getHash(&keys_[i]);
			hlm_.setLinkIndex(i, h);
		}
	}
		/*
		uint h = keyti_.getHash(&k);
		int ix = findKeyHash(k, h);
		if (ix >= 0)
		{
			keys_[ix] = k;
			fix = ix;
			return true;
		}
		else {
			fix = putHash(k, h);
			return false;
		}
		*/
	// looks for first of any existing entries, and replaces key
	// return true if existing key, with position at fix
	final bool findPut(ref K k, ref intptr_t fix)
	{
		auto h = keyti_.getHash(&k);
		auto startLink = hlm_.findLink(h);
		if (startLink >= 0)
		{
			// collision or key match chain found.
			auto ix = startLink;
			do
			{
				if (keys_[ix] == k)
				{
					// key is already inserted at ix
					fix = ix;
					return true;
				}
				ix = hlm_.hlinks_[ix].next;
			}
			while (ix != startLink);
		}
		auto q = hlm_.makeLink(h);
		if (q >= keys_.length)
			keys_ ~= k;
		else
			keys_[q] = k;
		fix = q;
		return false;
		/*
		uint h = keyti_.getHash(&k);
		int ix = findKeyHash(k, h);
		if (ix >= 0)
		{
			keys_[ix] = k;
			fix = ix;
			return true;
		}
		else {
			fix = putHash(k, h);
			return false;
		}
		*/
	}

	final bool put(K k)
	{
		intptr_t ix = -1;
		return findPut(k, ix);
	}

	final intptr_t putdup(ref K k)
	{
		return putHash(k, keyti_.getHash(&k));
	}

	final intptr_t putdup(K k)
	{
		return putHash(k, keyti_.getHash(&k));
	}

	final intptr_t findKeyIndex(ref LK k)
	{
		return findKeyHash(k, keyti_.getHash(&k));
	}

	final intptr_t nextKeyIndex(ref LK k, intptr_t i)
	{
		while(i >= 0 && !(k == keys_[i]))
			i = hlm_.findNext(i);
		return i;
	}

	final bool contains(LK k)
	{
		return  findKeyHash(k, keyti_.getHash(&k)) >= 0 ? true : false;
	}

	final intptr_t removeKey(LK k)
	{
		return unlinkKey(k, keyti_.getHash(&k));
	}

	final intptr_t removeKey(ref LK k)
	{
		return unlinkKey(k, keyti_.getHash(&k));
	}

	final void clearKeys()
	{
		hlm_.clear();
		keys_ = null;
	}

	final void removeIndex(intptr_t i)
	{
		hlm_.unlink(i);
	}
	final void rehash()
	{
		hlm_.reindex(hlm_.length_);
	}
}

/// Imitates in some respects a bool[key], but only stores 'true' keys
struct HashSet(K)
{
    alias KeyIndex!(K)  SetImpl;

    SetImpl  imp_;

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

    bool opIndex(LK k)
    {
        if (imp_ !is null)
        {
			return imp_.contains(k);
        }
        return false;
    }



	void setKeys(K[] akey)
	{
        imp_ = new SetImpl(akey);
	}
	void opIndexAssign(bool bval, K k)
	{
		if (bval)
		{
			if (imp_ is null)
				imp_ = new SetImpl();
			intptr_t ix = -1;
			imp_.findPut(k, ix);
		}
		else {
			if (imp_ !is null)
				imp_.removeKey(k);
		}
	}

    void detach()
    {
        imp_ = null;
    }
    void clear()
    {
        if (imp_ !is null)
            imp_.clearKeys();
    }
    @property void rehash()
    {
	    if (imp_ !is null)
            imp_.rehash();
    }
    @property HashSet init()
    {
        HashSet result;
        return result;
    }
    @property HashSet allocate()
    {
        HashSet result;
        result.imp_ = new SetImpl();
        return result;
    }
    @property
		K[] keys()
	{
	    if (imp_ is null)
            return null;
        return imp_.keys();
	}

    bool get(LK k)
    {
		if (imp_ !is null)
		{
			return imp_.contains(k);
		}
		return false;
    }


    @property uintptr_t capacity()
    {
        if (imp_ is null)
            return 0;
        return imp_.capacity();
    }

	@property bool contains(LK k)
	{
        return imp_ is null ? false
			: imp_.contains(k);
	}

    @property void capacity(uintptr_t cap)
    {
	    if (imp_ is null)
            imp_ = new SetImpl();
        imp_.setCapacity(cap);
    }
    @property double loadRatio()
    {
        if (imp_ is null)
            return 0;
        //'return imp_.used;
        return imp_.loadRatio;
    }

    @property void loadRatio(double ratio)
    {
	    if (imp_ is null)
            imp_ = new SetImpl();
        imp_.loadRatio(ratio);
    }


	@property  const size_t length()
	{
	    if (imp_ is null)
            return 0;
        //'return imp_.used;
        return imp_.length;
	}


    @property HashSet dup()
    {
        HashSet copy;

        if (imp_ !is null)
        {
            copy.imp_ = new SetImpl(imp_);
        }
        return copy;
    }
    bool wasRemoved(K key)
    {
        if (imp_ !is null)
            return (imp_.removeKey(key) >= 0) ? true : false;
		else
			return false;
    }
    void remove(LK key)
    {
        if (imp_ !is null)
            imp_.removeKey(key);
    }
	// return true if new key inserted
    bool put(K k)
    {
		if (imp_ is null)
            imp_ = new SetImpl();
		intptr_t ix = -1;
		bool result = imp_.findPut(k, ix);
		return imp_.put(k);
    }

	intptr_t	findKeyIndex(ref LK key)
	{
		return (imp_ !is null) ? imp_.findKeyIndex(key) : -1;
	}
}


version (UTEST)
{
void test_index()
{
	auto a = [1,2,3,4,5,6];
	replace(a,4,5,null);

	string[] test = getStringSet(40,10_000);
	scope indx = new KeyIndex!(string[]);
	indx.indexArray(test);
	for(int i = 0; i < test.length; i++)
	{
		if (! (indx.findKeyIndex(test[i]) == i) )
			throw new AAError("unittest for KeyIndex(string[]) failed");
	}
}
}


/**

	Usage:
---

	auto hm = new KeyValueIndex!(int[string]);

	// code like an AA, its also a KeyIndex

	hm["test1"] = 1;

	// add duplicates

	hm.putdup("test1") = 2;

	// access raw data
	auto keys = hm.keyData();
	auto values = hm.valueData();  // danger, aliased!

	// remove all copies of a key

---
*/
class KeyValueIndex(K,V) : KeyIndex!(K)
{
	V[]  values_;

	alias KeyValueIndex!(K,V) KVIndex;

	this(K[] keyset, V[] valueset)
	{
		super(keyset);
		values_ = valueset;
	}
	this(KeyValueIndex kvi)
	{
		// duplicate everything
		super(kvi);
		values_ = kvi.values.dup;
		hlm_.capdg_ = &setCapacity;
	}

	this()
	{
		super();
		hlm_.capdg_ = &setCapacity;

	}

	@property KVIndex dup()
	{
		return new KVIndex(this);
	}

	final intptr_t putdup(ref K k, ref V v)
	{
		auto ix = super.putHash(k, keyti_.getHash(&k));
		if (ix >= values_.length)
		{
			values_.length = ix+1;
		}
		values_[ix] = v;
		return ix;
	}

	final V get(ref LK k)
	{
		auto ix = super.findKeyIndex(k);
		if (ix >= 0)
			return values_[ix];
		else
			throw new ArrayMapError("V get(key) failed");
	}
	

	override void setCapacity(uintptr_t cap)
	{
		super.setCapacity(cap);
		auto ncap = values_.reserve(cap);
		if (ncap < hlm_.capacity_)
			hlm_.capacity_ = ncap;
		//writeln("Reserved ", cap, " got ", hlm_.capacity_);
	}

	final V get(LK k)
	{
		return get(k);
	}

	final void clear()
	{
		super.clearKeys();
		values_ = null;
	}



	final bool put(K k, V v)
	{
		int ix = -1;
		bool result = super.put(k);
		values_[ix] = v;
		return result;
	}

	final intptr_t putdup(K k, V v)
	{
		intptr_t ix = super.putHash(k, keyti_.getHash(&k));
		if (ix >= values_.length)
		{
			values_.length = ix+1;
		}
		values_[ix] = v;
		return ix;
	}

	final V* opIn_r(LK k)
	{
		//wrap
		auto ix = super.findKeyIndex(k);
		if (ix >= 0)
			return &values_[ix];
		else
			return null;
	}

    final V opIndex(LK k)
    {
		auto ix = super.findKeyIndex(k);
		if (ix >= 0)
			return values_[ix];
		else
			throw new ArrayMapError("V get(key) failed");
    }
	V get(LK k, lazy V defaultValue)
	{
		auto ix = super.findKeyIndex(k);
		if (ix >= 0)
			return values_[ix];
		else
			return defaultValue;
	}
	/*
	final bool get(K k, ref V val )
	{
		int ix = super.findKeyIndex(k);
		if (ix >= 0)
		{
			val = values_[ix];
			return true;
		}
		static if(!is(V==Variant))
			val = V.init;
		return false;

	}
	*/

    final bool remove(LK key)
    {
		auto ix = super.findKeyIndex(key);
		if (ix >= 0)
		{
			removeIndex(ix);
			return true;
		}
		return false;
    }

    final bool remove(LK key, ref V value)
    {
		auto ix = super.findKeyIndex(key);
		if (ix >= 0)
		{
			value = values_[ix];
			removeIndex(ix);
			return true;
		}
		return false;
    }

	final void opIndexAssign(V value, K k)
	{
		intptr_t ix = -1;
		if (!super.findPut(k, ix))
		{
			if (ix >= values_.length)
			{
				values_ ~= value;
				return;
			}
		}
		values_[ix] = value;
	}

	@property K[] keyData()
	{
		return keys_;
	}

	@property V[] valueData()
	{
		return values_;
	}



	int forEachValue(int delegate(V value) dg)
	{
		if (hlm_.length_ == values_.length)
		{
			for(uint i = 0; i < hlm_.length_; i++)
			{
				int result = dg(values_[i]);
				if (result)
					return result;
			}
		}
		else {
			auto hvalues = super.hashData();
			for(uint i = 0; i < hlm_.length_; i++)
			{
				if ((hvalues[i] & HashLinkMap.UNSIGNED_HIBIT)==0)
				{
					int result = dg(values_[i]);
					if (result)
						return result;
				}
			}
		}
		return 0;
	}

	void setKeysValues(K[] ak, V[] av)
	{
		assert(ak.length == av.length);
		values_ = av;
		setKeys(ak);	
	}

    @property
	V[] values()
	{
	    if (hlm_.length_ == values_.length)
            return values_.dup;
		else
		{
			V[] nval;
			nval.length = hlm_.length_;
			auto hdata = super.hashData();
			uint ct = 0;
			for(uint i = 0; i < hdata.length; i++)
			{
				if ((hdata[i] &  HashLinkMap.UNSIGNED_HIBIT)==0)
					nval[ct++] = values_[i];
			}
			return nval;
		}
	}
	int opApply(int delegate(V value) dg) const
	{
		auto hvalues = super.hashData();
		uint ct = 0;
		for(uint i = 0; i < hvalues.length; i++)
		{
			if ((hvalues[i] &  HashLinkMap.UNSIGNED_HIBIT)==0)
			{
				int result = dg(cast(V) values_[i]);
				if (result)
					return result;
			}
		}
		return 0;
	}

	int opApply(int delegate(const K key, V value) dg) const
	{
		auto hvalues = super.hashData();
		uint ct = 0;
		for(uint i = 0; i < hvalues.length; i++)
		{
			if ((hvalues[i] &  HashLinkMap.UNSIGNED_HIBIT)==0)
			{
				int result = dg(keys_[i], cast(V) values_[i]);
				if (result)
					return result;
			}
		}
		return 0;
	}
       /// 0: table length, 1 : unoccupied nodes,
        /// 2* : followed by [n-2] :  number of nodes of length n
	/// ignoring duplicate keys, only interested in length of chains on a hash
	/// In going through hash array, will hit common chains.
	/// in order to handle this, identify each chain by its lowest link number, store count
	/// this will repeat some counting
    @property uint[] list_stats()
    {
		intptr_t lowlink[];
		uint[] result;

		result.length = 16;

		lowlink.length = hlm_.hlinks_.length;
		lowlink[] = -1;

		auto hdata = hlm_.hmap_;
		result[0] = cast(uint) hdata.length;

		intptr_t emptybuckets = 0;
		HashLinkMap.HLink[] links = hlm_.hlinks_;

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

}


struct HashTable(K,V)
{
    alias KeyValueIndex!(K,V)  AAClassImpl;
	
    static if (isSomeString!K)
    {
		// type for lookups only
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

    AAClassImpl  imp_;

	V* opIn_r(LK k)
	{
		//wrap
		if (imp_ is null)
            return null;
		return imp_.opIn_r(k);
	}

    V opIndex(LK k)
    {
        if (imp_ !is null)
        {
			return imp_.opIndex(k);
        }
        throw new ArrayMapError("no key for opIndex");
    }

	void setKeysValues(K[] akey, V[] aval)
	{
        imp_ = new AAClassImpl(akey,aval);
	}
	void opIndexAssign(V value, K k)
	{
	    if (imp_ is null)
            imp_ = new AAClassImpl();
        imp_.opIndexAssign(value, k);
	}

    void detach()
    {
        imp_ = null;
    }
    void clear()
    {
        if (imp_ !is null)
            imp_.clear();
    }
    @property void rehash()
    {
	    if (imp_ !is null)
            imp_.rehash();
    }
    @property HashTable init()
    {
        HashTable result;
        return result;
    }
    @property HashTable allocate()
    {
        HashTable result;
        result.imp_ = new AAClassImpl();
        return result;
    }
    @property
	K[] keys()
	{
	    if (imp_ is null)
            return null;
        return imp_.keys();
	}

    @property
	V[] values()
	{
	    if (imp_ is null)
            return null;
        return imp_.values();
	}

    V get(LK k)
    {
		if (imp_ !is null)
		{
			return imp_.get(k);
		}
        throw new ArrayMapError("get on absent AA key");
    }

    V get(LK key, lazy V defaultValue)
    {
	    if (imp_ !is null)
	    {
           return imp_.get(key, defaultValue);
	    }
		else
			return defaultValue;
    }
	/*
	bool get(K k, ref V val )
	{
	    if (imp_ !is null)
	    {
           return imp_.get(k, val);
	    }
		static if(!is(V==Variant))
			val = V.init;
		return false;
	}
	*/
    @property uintptr_t capacity() const
    {
        if (imp_ is null)
            return 0;
        //'return imp_.used;
        return imp_.capacity();
    }

	@property bool contains(K k)
	{
        return imp_ is null ? false
			  : imp_.contains(k);
	}

    @property void capacity(uintptr_t cap)
    {
	    if (imp_ is null)
            imp_ = new AAClassImpl();
        imp_.setCapacity(cap);
    }
    @property double loadRatio()
    {
        if (imp_ is null)
            return 0;
        //'return imp_.used;
        return imp_.loadRatio;
    }

    @property void loadRatio(double ratio)
    {
	    if (imp_ is null)
            imp_ = new AAClassImpl();
        imp_.loadRatio(ratio);
    }
    version(miss_stats)
    {
        @property size_t rehash_ct()
        {
            if (imp_ is null)
                return 0;
            //'return imp_.used;
            return imp_.rehash_ct;
        }

        @property size_t misses()
        {
            if (imp_ is null)
                return 0;
            //'return imp_.used;
            return imp_.misses;
        }

    }
    @property uint[] list_stats()
    {
        if (imp_ is null)
            return null;
        //'return imp_.used;
        return imp_.list_stats;
    }
	@property  const size_t length()
	{
	    if (imp_ is null)
            return 0;
        //'return imp_.used;
        return imp_.length;
	}


    @property HashTable dup()
    {
        HashTable copy;

        if (imp_ !is null)
        {
            copy.imp_ = new AAClassImpl(imp_);
        }
        return copy;
    }
    bool remove(LK key, ref V value)
    {
        if (imp_ !is null)
            return imp_.remove(key, value);
		else
			return false;
    }
    void remove(LK key)
    {
        if (imp_ !is null)
            imp_.remove(key);
    }
	 // return true if new key inserted
    bool put(K k, ref V value)
    {
		if (imp_ is null)
            imp_ = new AAClassImpl();
		intptr_t ix = -1;
		bool result = imp_.findPut(k, ix);
		return imp_.put(k, value);
    }
	int forEachValue(int delegate(V value) dg)
	{
		return (imp_ !is null) ? imp_.forEachValue(dg) : 0;
	}

	int opApply(int delegate(V value) dg) const
	{
		return (imp_ !is null) ? imp_.opApply(dg) : 0;
	}

	int opApply(int delegate(const K key, V value) dg) const
	{
        return (imp_ !is null) ? imp_.opApply(dg) : 0;
	}

	V valueAtIndex(intptr_t ix)
	{
		return imp_.values[ix];	
	}
	void setAtIndex(ref V value, intptr_t ix)
	{
		imp_.values[ix] = value;	
	}
	intptr_t	findKeyIndex(ref LK key)
	{
		return (imp_ !is null) ? imp_.findKeyIndex(key) : -1;
	}
}

version(LINK_MAP_32)
{
    private immutable
    uintptr_t[] prime_list = [
        13UL, 53UL, 193UL, 389UL,
        769UL, 1_543UL, 3_079UL, 6_151UL,
        12_289UL, 24_593UL, 49_157UL, 98_317UL,
        196_613UL, 393_241UL, 786_433UL, 1_572_869UL,
        3_145_739UL, 6_291_469UL, 12_582_917UL, 25_165_843UL,
        50_331_653UL, 100_663_319UL, 201_326_611UL, 402_653_189UL,
        805_306_457UL, 1_610_612_741UL,  2_147_483_647
    ];
}
else {
    private immutable
    uintptr_t[] prime_list = [
        13UL, 53UL, 193UL, 389UL,
        769UL, 1_543UL, 3_079UL, 6_151UL,
        12_289UL, 24_593UL, 49_157UL, 98_317UL,
        196_613UL, 393_241UL, 786_433UL, 1_572_869UL,
        3_145_739UL, 6_291_469UL, 12_582_917UL, 25_165_843UL,
        50_331_653UL, 100_663_319UL, 201_326_611UL, 402_653_189UL,
        805_306_457UL, 1_610_612_741UL,
        3_221_225_473UL, 4_294_967_291UL
    ];

}

template binary_search( T )
{
	/** return index of match or next greater value */
	intptr_t upperBound(const(T)[] data, T value)
	{
		intptr_t a = 0;
		auto b = data.length;
		while (a < b)
		{
			immutable mid = a + (b-a)/2;
			immutable test = data[mid];
			if (test < value)
			{
				a = mid+1;
			}
			else if (value < test)
			{
				b = mid;
			}
			else {
				// exact match equals upperBounde
				return mid;
			}
		}
		// not found
		return a;
	}
}

uintptr_t getNextPrime(uintptr_t atLeast)
{
	auto ix = binary_search!uintptr_t.upperBound(prime_list, atLeast);
	if (ix < prime_list.length)
		return prime_list[ix];
	else
		throw new ArrayMapError(text("getNextPrime value too big: ", atLeast));
}

