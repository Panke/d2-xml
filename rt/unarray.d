module rt.unarray;

/**

Generic stored array using ExtraTypeInfo

Authors: Michael Rynn

*/

import std.stdint;


private import core.memory, std.c.string;

import alt.zstring;
import rt.aaI;

/// manipulate array using TypeInfo.  Its called UntypedArray because the compiler 
/// does not know what type is being emulated.
/// This is very rough. Would like TypeInfo to have copyFn,
/// or would like custom TypeInfo made from template, customized for this.
/// so that the UntypedArray struct is a bit smaller.
/// Capacity is managed by the owner, specifically the KeyValueArrayMap in aaArrayMap.
/// General useability is not envisaged.
struct UntypedArray {
	byte*		ptr;
	size_t		length;
	size_t		capacity;
	TypeInfo	dti;
	//TypeCopyFn	copyFn;	  // fill deficiency in TypeInfo

	void assign(void[]  varray)
	{
		destroy();
		//TODO: free existing?
		ptr = cast(byte*) varray.ptr;
		length = varray.length;
		reserve(varray.length,true);
	}

	hash_t hash(size_t ix)
	{
		return dti.getHash(ptr+ix*dti.tsize);
	}
	void* vptr(size_t ix)
	{
		return ptr + ix*dti.tsize;
	}
	// this is not a full implementation, because it assumes arrayHashMap will manage capacity
	void append(void *pval)
	{
		immutable tsize = dti.tsize;
		auto dp = ptr + length*tsize;

		/// TypeInfo does not have a "copy" facility.
		memcpy(dp, pval, tsize);
		dti.postblit(dp);
		//copyFn(ptr+length*tsize, pval);
		length++;
	}
	
	/// Add zeroed blank to 
	void extend()
	{
		//auto pv = dti.init(); /// this gives null?
		///copyFn(ptr+length*dti.tsize, pv);
		//immutable tsize = dti.tsize;
		//memset(ptr+length*tsize, 0, tsize);
		length++;
	}
	
	private void destroy()
	{
		if (ptr is null)
			return;
		auto p = ptr;
		auto tsize = dti.tsize;
		auto pend = p + tsize * length;

		while ( p < pend)
		{

			dti.destroy(p);
			p += tsize;
		}
		GC.free(ptr);
		ptr = null;
	}
	/// Call TypeInfo destructor for everything and start again.
	void clear()
	{
		destroy();
		length = 0;
		capacity = 0;
	}

	/// Copy over as D would do it.
	void assign(size_t ix, void *pval)
	{
		immutable tsize = dti.tsize;
		auto dp = ptr + ix*tsize;

		memcpy(dp, pval, tsize);
		dti.postblit(dp);
		//copyFn(ptr+ix*tsize, pval);
	}

	/// return TypeInfo comparison
	intptr_t compare(size_t ix, void *pval)
	{
		return dti.compare(ptr+ix*dti.tsize, pval);
	}
	
	/// Call TypeInfo destructor for index
	void destroy(size_t ix)
	{
		immutable tsize = dti.tsize;
		dti.destroy(ptr + tsize*ix);
	}

	/// reserve assumes memory can moved around without consequence
	void reserve(size_t wanted, bool exactSize = false)
	{
		auto tisize = dti.tsize;
		if (!exactSize)
			wanted = getNextPower2(wanted);
		auto allocSize = tisize * wanted;
		

		auto info = GC.qalloc(allocSize, (dti.flags & 1) ? 0 : GC.BlkAttr.NO_SCAN);
		auto unitCap = info.size / tisize;
		auto unitZero = unitCap;

		if (length > 0)
		{
			if (length > unitCap) 
			{
				length = unitCap;
				unitZero = 0;
			}
			else {
				unitZero -= length;
			}
			memcpy(info.base, ptr, tisize*length);
		}
		if (unitZero)
			memset(cast(byte*)info.base + length*tisize, 0, unitZero*tisize); 
		if (exactSize)
			capacity = wanted;
		else
			capacity = unitCap;
		if (ptr)
		{
			GC.free(ptr);
		}
		ptr = cast(byte*)info.base;
	}
	/// move the memory to a conventional array proxy, and forget it.
	void transfer(ref ArrayD art)
	{
		art.ptr = ptr;
		art.length = length;
		ptr = null;
		length = 0;
		capacity = 0;
	}
	/// alias the memory of a conventional D slice
	void adopt(in ArrayD art)
	{
		ptr = cast(byte*)art.ptr;
		length = art.length;
		capacity = length;
	}

}