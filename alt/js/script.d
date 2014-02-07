module alt.js.script;
import std.stdint;
import std.variant;
import alt.blockheap;
import alt.hashutil;
import alt.aahash;
import alt.zstring;
import std.traits;
import std.conv, std.string, std.variant;

debug import std.stdio;

private import core.memory;
/**
	Its an effort to write lua code, as its not D, which I am too used to.
	There is too much effort on the stack interface to C functions.
	And then also need a lua DLL installed. And then fixing up the lua code.

	So this is the Js scripting  non-language. (Dee Unsigned Hash).
	It has to be made up of JsObjects.  
	Currently unsigned integer, double , string, array, AA, and table.

	The main prescription is that they are derived from JsHash.

	Compiled by D compiler of course.
	
	Most of lua is all about the table/array structure.
	Its global variables and local variables are tables.
	When a lookup fails in a local variable table, checks to see if local table has a "metatable".
	
	So why not write one in D?
	
	Lua tables can be arrays, or associative arrays.
	AA are accessed with pair iterator.
	Array are accessed with ipair iterator.

	D version has true integers, not just doubles without a fraction part.
	Lua arrays are 1-index based, not 0.
	uint (uintptr_t)  index 
		- if index is less than length
		- if index is equal to length, expand length by 1 and set array value.
		- if index is greater than length, use it as aaKey.
	
	any other type, use as Variant key, Variant value.

	Each table may have a metatable - string key, and a delegate (function in Lua)

	This allows tables to implement metamethods.
	
	__add, __concat, __div, __eq, __gc, __index, __le, __lt, __metatable, __mod, __mode,
	__mul, __newindex, __pow, __sub, __tostring, __unm

	But of course Lua has reliable garbage collection. The type of every object in every one of its tables is known.
	There is then no question of not deciding what is, or is not a pointer.

	All names, are string keys to anonymous values in tables.
	When a value has no keys pointing to, its collectible.
	
	D has a conservative garbage collector.
	I have not much confidence it can pick apart messy linked data structures.
	Some internal 'GC' cleanup, leaving alone aliased immutable arrays, may be required.

	Lets say that all values are stored as Nodes in a heap.
	
	Some nodes contail Table objects
	
	D classes do not have override for '.' of course.
	But '.' in lua means table[keyAA] so be happy.


*/
/**
	A D untptr_t,  hash table

*/

/// All objects are a hash value A hash_t is also an unsigned integer object? and so has a precomputed hash.
/// No boolean value, JsHash = 0 = false.   JsHash = 1 = true;
enum ObjType : ushort {
	Undefined,
	Null,
	Integer,
	Double,
	String,
	Class,
	List,
	Map,
	Function,
	NativeFn,
}

enum ObjFlags : ushort {
	ReadOnly = 1,
	Hidden = 2,
	ObjectId = 4
}

struct ObjId {
	ObjType  type_;
	ObjFlags flags_;
}

union JsData {
	string	 str_; // uintptr_t * 2  (8 or 16)
	Object	 obj_; // 4 or 8
	long	 long_;//8
	double	 float_; //8
}
struct JsValue {
	JsData	data; // (8 or 16)
	ObjId	id;	// 4 

	static TypeInfo[] gTypeInfo = 
	[
		null,null,
		typeid(long),typeid(double), typeid(string),null,null, null, null
	];

	
	this(string s)
	{
		assign(s);
	}

	this(long val)
	{
		assign(val);
	}

	this(double val)
	{
		assign(val);
	}

	this(Object o)
	{
		assign(o);
	}
	
	this(ObjType ot=ObjType.Undefined)
	{
		id.type_ = ot;
	}

	void zero()
	{
		id = ObjId.init;
		data = JsData.init;
	}

	void assign(long val)
	{
		id.type_ = ObjType.Integer;
		data.long_ = val;
	}
	void assign(double val)
	{
		id.type_ = ObjType.Double;
		data.float_ = val;
	}
	void assign(Object o)
	{
		id.type_ = ObjType.Class;
		data.obj_ = o;
	}
	void assign(string s)
	{
		id.type_ = ObjType.String;
		data.str_ = s;
	}

	bool opEquals(ref const JsValue S) const
	{
		if (this.id.type_ != S.id.type_)
		{
			return false;
		}
		switch(this.id.type_)
		{
			case ObjType.Integer:
				return this.data.long_ == S.data.long_;
			case ObjType.Double:
				return this.data.float_ == S.data.float_;		
			case ObjType.String:
				return this.data.str_ == S.data.str_;
			case ObjType.Class:
				auto ci = this.data.obj_.classinfo;
				if (ci == S.data.obj_.classinfo)
					return ci.equals(cast (void*) (this.data.obj_), cast(void*)(S.data.obj_));
				else
					return false;
			default:
				return false;
		}
	}
	int opCmp(ref const JsValue S)
	{
		if (this.id.type_ != S.id.type_)
		{
			return -1;
		}
		switch(this.id.type_)
		{
		case ObjType.Integer:
			auto longDiff = this.data.long_ - S.data.long_;
			return (longDiff > 0) ? 1 : (longDiff < 0) ? -1 : 0;
		case ObjType.Double:
			auto doubleDiff = this.data.float_ - S.data.float_;
			return (doubleDiff > 0.0) ? 1 : (doubleDiff < 0.0) ? -1 : 0; 		
		case ObjType.String:
			return this.data.str_.cmp(S.data.str_);
		case ObjType.Class:
			return typeid(Object).compare(cast(void*)this.data.obj_, cast(void*)S.data.obj_);
		default:
			return -1;
		}
	}

	string toString()
	{
		switch(this.id.type_)
		{
			case ObjType.Integer:
				return to!string(data.long_);
			case ObjType.Double:
				return to!string(data.float_);	
			case ObjType.String:
				return  data.str_;	
			case ObjType.Class:
				return	data.obj_.toString();
			default:
				return format("Type %s",this.id.type_);
		}	
	}

	hash_t toHash() const
	{
		TypeInfo ti = gTypeInfo[id.type_];
		if (ti !is null)
		{
			return ti.getHash(&this);
		}
		return 0;
	}
	
}

alias HashTable!(JsValue,JsValue) JsValueMap;
alias Array!JsValue	JsValueArray;
/*
// rather than use D AA built in, Make one JsAA

struct JsBucket {
	JsBucket*		next_;
	hash_t			hash_;
	JsValue			key_;	
	JsValue			value_;
}

private enum JsTableOp {
	GET,
	GET_LOCAL,
	PUT,
	DEL
}
alias JsBucket* ubucket;

class JsAA  {
	ubucket[]			buckets_;
	uintptr_t			nodes_;
	uintptr_t			capacity_; // resize trigger
	ubucket[7]			binit;
	enum double loadRatio_ = 1.0;
	JsAA				chain_;

	static	BlockHeap	gBucketHeaven_;
	static  JsAA	gFront_;
	static  JsAA	gBack_;

	
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
		ref JsValue value() @property
		{
			return ref_.value_;
		}
		void value(ref JsValue val) @property
		{
			ref_.value_ = val;
		}
	}

	struct Range {
		ubucket[]	slots_;
		ubucket		current_;

		this(JsAA aa)
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
		ref inout(JsBucket) front() inout @property
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
		gBucketHeaven_ = new BlockHeap(JsBucket.sizeof,0);
	}
	this()
	{
		buckets_ = binit;
		capacity_ = cast(size_t)(buckets_.length * loadRatio_);
	}
	private ubucket getNode(JsValue* key, JsTableOp op)
	{
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
				if (op == JsTableOp.DEL)
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
		if (op == JsTableOp.GET)
		{
			if (chain_ !is null)
				return chain_.getNode(key,JsTableOp.GET);
			return null;
		}
		if (op == JsTableOp.PUT)
		{
			e = cast(ubucket) gBucketHeaven_.allocate();
			e.key_ = *key;
			e.hash_ = key_hash;
			*pe = e;
			nodes_++;
			if (nodes_ > capacity_)
				grow_rehash();
			return e;
		}
		return null; // not found and not create
	}

	NodeRef reference(ref JsValue key)
	{
		return NodeRef(getNode(&key, JsTableOp.GET));
	}
	NodeRef unchained(ref JsValue key)
	{
		return NodeRef(getNode(&key, JsTableOp.GET_LOCAL));
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
	void chain(JsAA table)
	{
		if (table !is this)
			chain_ = table;
	}
	JsValue opIndex(ref JsValue key)
	{
		ubucket b = getNode(&key,JsTableOp.GET);
		return (b is null) ? JsValue.init : b.value_;
	}
	JsValue opIndex(string s)
	{
		JsValue nkey;
		nkey.assign(s);
		return opIndex(nkey);
	}
	JsValue opIndex(uintptr_t key)
	{
		JsValue nkey;
		nkey.assign(key); 
		return opIndex(nkey);
	}

	void remove(ref JsValue key)
	{
		ubucket b = getNode(&key,JsTableOp.DEL);
		if (b !is null)
		{
			*b = JsBucket.init;
			gBucketHeaven_.collect(b);
		}
	}

	void opIndexAssign(ref JsValue value,  ref JsValue key)
	{
		ubucket b = getNode(&key,JsTableOp.PUT);
		b.value_ = value;
	}
	void opIndexAssign(string s, string key)
	{
		JsValue	sval;
		JsValue	ukey;
		sval.assign(s);
		ukey.assign(key);
		opIndexAssign(sval,ukey);
	}
	void opIndexAssign(Object s, string key)
	{
		JsValue	sval;
		JsValue	ukey;
		sval.assign(s);
		ukey.assign(key);
		opIndexAssign(sval,ukey);
	}

	void opIndexAssign(string s, uintptr_t key)
	{
		JsValue	sval;
		JsValue	ukey;
		sval.assign(s);
		ukey.assign(key);
		opIndexAssign(sval,ukey);
	}

    auto byKey()  @property 
    {
        static struct Result
        {
            Range state;

            this(JsAA p)
            {
                state = Range(p);
            }

            ref JsValue front() @property 
            {
                return state.front.key_;
            }

            alias state this;
        }
        return Result(this);
	}

    public intptr_t opApply(int delegate(ref const JsValue key, ref JsValue value) dg)
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


*/

class JsArray : JsObject { 
private	JsValueArray	array_;
public:

	this(string[] sa)
	{
		foreach(s ; sa)
			this ~= s;
	}
	
	this()
	{
	}
	
	void opCatAssign(string s)
	{
		auto slen = array_.length;
		array_.length = slen+1;
		array_.ptr[slen].assign(s);
	}

	void opCatAssign(ref JsValue val)
	{
		array_.put(val);
	}

	JsValue*  opIndex(uintptr_t key)
	{
		if (key >= array_.length)
		{
			return null;
		}
		return &array_.ptr[key];
	}

	void opAssign(string[] sa)
	{
		array_.length = sa.length;
		auto p = array_.ptr;
		foreach(ix, s ; sa)
		{
			p[ix].assign(s);
		}
			
	}

	void opIndexAssign(ref JsValue value,uintptr_t key)
	{
		if (key >= array_.length)
		{
			array_.length = key+1;
		}
		array_.ptr[key] = value;
	}	
	void opIndexAssign(string s,uintptr_t key)
	{
		if (key >= array_.length)
		{
			array_.length = key+1;
		}
		array_.ptr[key].assign(s);
	}		
    public intptr_t opApply(int delegate(uintptr_t key, ref JsValue value) dg)
    {
		intptr_t result = 0;
		for(auto ix = 0; ix < array_.length; ix++)
		{
			result = dg(ix,array_.ptr[ix]);
			if (result)
				return result;
		}
		return result;
    }
}


struct JsValueRange {
private
	JsValue[]	data_;
	JsValue*	current_;
public:
	this(JsValue[] dx)
	{
		data_ = dx;
		popFront();
	}
	bool empty() const @property
	{
		return (current_ is null);
	}
	JsValue* front() @property
	{
		return current_;
	}
	void popFront()
	{
		if (data_.length == 0)
			current_ = null;
		else {
			current_ = &data_[0];
			data_ = data_[1..$];
		}
	}

}


/// Can store a value, and properties.
/// It may have multiple references to it.
class JsObject  {
	JsValue			value_;
	JsValueMap		map_;

	ref JsValue value() @property
	{
		return value_;
	}

	void value(ref JsValue v) @property
	{
		value_ = v;
	}
	bool opEquals(Object o) 
	{
		auto dh = cast(JsObject) o;
		if (dh is null)
			return false;
		return (value_ == dh.value_);
	}
	int opCmp(Object o) 
	{
		auto dh = cast(JsObject) o;
		if (dh is null)
			return -1;	
		return (value_.opCmp(dh.value_));
	}
}

class JsFunction : JsObject {
	Array!string	argNames_;
	uintptr_t		fnAddress_;
}

class JsTable  {
	private JsValueMap		map_;
	private JsValueArray	array_;
public:	
	this()
	{
	}
	
	JsValueArray* array() @property
	{
		return &array_;
	}
	JsValueRange byIndex()
	{
		return JsValueRange(array_.toArray());
	}
	JsValueMap.NodeRef getlocal(ref JsValue key)
	{
		return map_.getlocal(key);
	}
	JsValueMap.NodeRef getchain(ref JsValue key)
	{
		return map_.getchain(key);
	}
	uintptr_t end() const @property
	{
		return array_.length;
	}
	
	void chain(JsTable nextTable)
	{
		map_.chain(nextTable.map_);
	}
	void opIndexAssign(ref JsValue value, ref JsValue key)
	{
		map_[key] = value;
	}
	/// integer index, string value may be appended or set in array.
	/// or mapped if > array length
	void opIndexAssign(string value, uintptr_t arrayIX)
	{
		auto slen = array_.length;
		if (arrayIX <= slen)
		{
			if (arrayIX == slen)
			{
				array_.put(JsValue(value));
				return;
			}
			array_[arrayIX] = JsValue(value);
			return;
		}
		map_[JsValue(arrayIX)] = JsValue(value);
	}
	/// automatic storage as JsValue
	void opIndexAssign(string value, string key)
	{
		map_[JsValue(key)] = JsValue(value);
	}
	/// Can store table, or array
	void opIndexAssign(JsTable value, string key)
	{
		map_[JsValue(key)] = JsValue(value);
	}
	/// Can store table, or array
	void opIndexAssign(JsArray value, string key)
	{
		map_[JsValue(key)] = JsValue(value);
	}
}

unittest {
	auto dt = new JsTable();
	dt[1] = "test";
	auto da = new JsArray();

	da = ["test1", "test2", "test3"];
	dt["key"] = "value1";
	auto dt2 = new JsTable();
	dt2["key2"] = dt;
	dt2["array ref"] = da;


}
