/**
Test arrays for non-garbage collector memory management, ie reference counting for arrays and manual for everything else.

Array!T	is reference counted and copy on write.  Aliasing requires a class wrapper.   
HashTable!(K,V) is reference counted and aliased promiscously everywhere.

With both of them having reference counted data, keeping pointers around to them, GC or no GC, might break-dangle, or do weird things.
Also thread issues will be weird and are completely untested.

So 
---
alias Array!T	arrayT;
alias arrayT*	parrayT; // can be risky

alias HashTable!(K,V) KVMap;
alias KVMap*	kvmap; // can be risky

---


*/

import alt.aahash;
import gc.gc;
import std.c.stdio;
import alt.zstring;
import std.stdint;

alias Array!char arrayChar;

void test1()
{
	alias KeyValueBlock!(arrayChar,arrayChar,true)	KVB;

	KVB sb;

	arrayChar output;


	void put(arrayChar s)
	{
		output.put(' ');
		output.put(s);
	}


	sb.appendMode = true;
	arrayChar k1 = "version";
	arrayChar k2 = "standalone";
	arrayChar k3 = "encoding";
	arrayChar v1 = "1.0";
	arrayChar v2 = "yes";
	arrayChar v3 = "utf-8";

	auto diff = k1.opCmp(k2);
	diff = k2.opCmp(k1);
	diff = k2.opCmp(k3);
	diff = k3.opCmp(k3);
	diff = k1.opCmp(k3);
	diff = k3.opCmp(k1);


	sb[k1] = v1;
	sb[k2] = v2;
	sb[k3] = v3;

	auto oldK1 = sb.atIndex(0);

	sb.sort();

	auto newK1 = sb.atIndex(0);

	auto cd = sb;

    put(cd[k1]);
    put(cd[k2]);
    put(cd[k3]);

	output.nullTerminate();
	printf("%s\n", output.constPtr);
}

void test2()
{

	alias HashTable!(arrayChar, arrayChar)	StringMap;

	StringMap m1;

	m1.setup(1);
	// cannot set directly from string, like testAA["key2"] = "value2";
	// can assign indirect


	arrayChar k1 = "key1";
	arrayChar v1 = "value1";
	m1[k1] = v1;
	m1[v1] = k1;
	auto m2 = m1; 

	arrayChar k2 = "key2";

	m2[k2] = v1;

	assert(m1[k2] == v1);
	assert(m2[k1] == v1);
	m1.remove(k1);
	assert(k1 !in m1);

}

void arrayStats()
{
	intptr_t alloc, blocks;

	alt.zstring.getStats(alloc, blocks);
	printf("arrays %d  %d\n", alloc, blocks);
}

void main(string[] args)
{
	GCStats.showstats();
	printf("No garbage collection\n");

	alias Array!char arrayChar;

	HashTable!(arrayChar,arrayChar)	StringMap;

	for(auto i = 0; i < 10; i++)
	{
		test1();
		test2();
		GCStats.showstats();
		arrayStats();
	}
	getchar();
	
}
