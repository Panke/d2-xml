/**
 * Implementation of associative arrays.
 *
 * Copyright: Copyright Digital Mars 2000 - 2010.
 * License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
 * Authors:   Walter Bright, Sean Kelly

Don't use this.

Modified by Michael Rynn as experiment.  Its a failure,
because compiler will not supply a TypeInfo copy function,
and value TypeInfo for timely initialization of aaI.

Once initialization is taken care of, the interface implementation should work.

Resort to AssociativeArray template in aaI to supply everything.

 */

/*          Copyright Digital Mars 2000 - 2010.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE_1_0.txt or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module rt.aaA;

import rt.aaI;



/* This is the type actually seen by the programmer, although
 * it is completely opaque.
 */


/**********************************
* Align to next pointer boundary, so that
* GC won't be faced with misaligned pointers
* in value.
*/


extern (C):


size_t _aaLen(AA aa)
{
	with (aa)
		return (a) ? a.length : 0;
}


/*************************************************
 * Get pointer to value in associative array indexed by key.
 * Add entry for key if it is not already there.
 */

// retained for backwards compatibility
void* _aaGet(AA* aa, TypeInfo keyti, size_t valuesize, ...)
{
    return _aaGetX(aa, keyti, valuesize, cast(void*)(&valuesize + 1));
}

/** Initialization for gAAFactory isn't enough for the information required 
    by the aaI implementations.
	Need ExtraTypeInfo with a copyFn.
*/

void* _aaGetX(AA* aa, TypeInfo keyti, size_t valuesize, void* pkey)
/*
in
{
    //assert(aa);
}
out (result)
{
    //assert(result);
    //assert(aa.a);
    //assert(aa.a.length);
    //assert(_aaInAh(*aa.a, key));
}
body*/
{
	auto a = aa.a;
	if (a is null)
	{
		auto aati = cast(TypeInfo_AssociativeArray) keyti;
		if (aati !is null)
			a = gAAFactory(aati.key,aati.value);
		else
			a = gAAFactory(keyti,null);
		aa.a = a;
	}
	return a.getX(pkey);

}


/*************************************************
 * Get pointer to value in associative array indexed by key.
 * Returns null if it is not already there.
 */

void* _aaGetRvalue(AA aa, TypeInfo keyti, size_t valuesize, ...)
{
	return (aa.a) ? aa.a.getRvalueX(cast(void*)(&valuesize + 1)) : null;
}

void* _aaGetRvalueX(AA aa, TypeInfo keyti, size_t valuesize, void* pkey)
{
	return (aa.a) ? aa.a.getRvalueX(pkey) : null;
}


/*************************************************
 * Determine if key is in aa.
 * Returns:
 *      null    not in aa
 *      !=null  in aa, return pointer to value
 */

void* _aaIn(AA aa, TypeInfo keyti, ...)
{
    return _aaInX(aa, keyti, cast(void*)(&keyti + 1));
}

void* _aaInX(AA aa, TypeInfo keyti, void* pkey)
in
{
}
out (result)
{
    //assert(result == 0 || result == 1);
}
body
{
    return (aa.a) ? aa.a.inX(pkey) : null;
}

/*************************************************
 * Delete key entry in aa[].
 * If key is not in aa[], do nothing.
 */

bool _aaDel(AA aa, TypeInfo keyti, ...)
{
	return (aa.a) ? aa.a.delX(keyti,cast(void*)(&keyti + 1)) : false;

}

bool _aaDelX(AA aa, TypeInfo keyti, void* pkey)
{
	return (aa.a) ? aa.a.delX(keyti,pkey) : false;
}


/********************************************
 * Produce array of values from aa.
 */

ArrayRet_t _aaValues(AA aa, size_t keysize, size_t valuesize)
{
    size_t resi;
    Array a;

    auto alignsize = aligntsize(keysize);

    if (aa.a)
    {
		return aa.a.values(keysize,valuesize);
    }
    return *cast(ArrayRet_t*)(&a);
}


/********************************************
 * Rehash an array.
 */

void* _aaRehash(AA* paa, TypeInfo keyti)
in
{
    //_aaInvAh(paa);
}
out (result)
{
    //_aaInvAh(result);
}
body
{
    //printf("Rehash\n");
    return (paa.a) ? cast(void*)paa.a.rehash() : null;
}

/********************************************
 * Produce array of N byte keys from aa.
 */

ArrayRet_t _aaKeys(AA aa, size_t keysize)
{
	return (aa.a) ? aa.a.keys(keysize) : null;
}

unittest
{
    int[string] aa;

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


/**********************************************
 * 'apply' for associative arrays - to support foreach
 */

// dg is D, but _aaApply() is C
extern (D) alias int delegate(void *) dg_t;

int _aaApply(AA aa, size_t keysize, dg_t dg)
{
	return (aa.a) ? aa.a.apply(keysize, dg) : 0;
}

// dg is D, but _aaApply2() is C
extern (D) alias int delegate(void *, void *) dg2_t;

int _aaApply2(AA aa, size_t keysize, dg2_t dg)
{
	return (aa.a) ? aa.a.apply2(keysize, dg) : 0;
}




extern (C)
void* _d_assocarrayliteralT(TypeInfo_AssociativeArray ti, size_t length, ...)
{
	TypeInfo keyti, valueti;
	extractAATypeInfo(ti, keyti, valueti);
	IAA a = gAAFactory(keyti, valueti);
	a.init(ti, length, _argptr);
	return cast(void *) a;

}

/// Cannot have "opaque" interface and declared type returned at same time. 
/// C name space function names doesn't include return type?

extern (C)
IAA _d_assocarrayliteralTX(TypeInfo_AssociativeArray ti, void[] keys, void[] values)
{
	TypeInfo keyti,valueti;
	extractAATypeInfo(ti, keyti, valueti);
	IAA a = gAAFactory(keyti, valueti);
	a.init(ti,keys,values);
	return a;
}


/***********************************
 * Compare AA contents for equality.
 * Returns:
 *      1       equal
 *      0       not equal
 */
int _aaEqual(TypeInfo tiRaw, AA e1, AA e2)
{
    //printf("_aaEqual()\n");
    //printf("keyti = %.*s\n", ti.key.classinfo.name);
    //printf("valueti = %.*s\n", ti.next.classinfo.name);

    if (e1.a is e2.a)
        return 1;
	auto a1 = e1.a;
	auto a2 = e2.a;
	if (a1 is null || a2 is null)
		return false;

    size_t len = a1.length;
	if (len != a2.length)
		return 0;
	if (len == 0)
		return 1; // equally empty?


    // Check for Bug 5925. ti_raw could be a TypeInfo_Const, we need to unwrap
    //   it until reaching a real TypeInfo_AssociativeArray.
    TypeInfo_AssociativeArray ti;
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

    /* Algorithm: Visit each key/value pair in e1. If that key doesn't exist
     * in e2, or if the value in e1 doesn't match the one in e2, the arrays
     * are not equal, and exit early.
     * After all pairs are checked, the arrays must be equal.
     */
	// why need tiRaw?
	return a1.equals(a2, ti);
}
