/**

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

Shared data definitions for communicating with the parser.

*/

module std.xmlp.parseitem;

import std.xmlp.xmlchar;
import std.string;
import std.stdint;
import core.memory;

import alt.buffer;

static if (__VERSION__ <= 2053)
{
    import std.ctype;
    alias std.ctype.isdigit isDigit;
}
else
{
    import std.ascii;
}

private import std.c.string :
memcpy;

/// Rationalize the error messages here.  More messages and functionality to add.

/// Standard DOM node type identification


version (CustomAA)
{
	import alt.arraymap;
	alias HashTable!(string,string) StringMap;
	alias HashTable!(dchar, string) ReverseEntityMap;
}
else {
alias string[string] StringMap;
alias string[dchar] ReverseEntityMap;
}


unittest
{
    AttributeMap amap;

    amap["tname"]="tval";
    assert(amap.length==1);
}
/**
	Returns parsed fragment of XML. The type indicates what to expect.
*/

enum XmlResult
{
    TAG_START, /// Element name in scratch.  Attributes in names and values. Element content expected next.
    TAG_SINGLE, /// Element name in scratch.  Attributes in names and values. Element has no content.
	TAG_EMPTY = TAG_SINGLE,
    TAG_END,   /// Element end tag.  No more element content.
    STR_TEXT,  /// Text block content.
    STR_CDATA, /// CDATA block content.
    STR_COMMENT,  /// Comment block content.
    STR_PI,		///  Processing Instruction.  Name in names[0].  Instruction content in values[0].
    DOC_END,      /// Parse finished
	XML_DEC,   /// XML declaration.  Declaration attributes in names and values.
	DOC_TYPE,	/// DTD parse results contained in doctype as DtdValidate.
	XI_NOTATION,
	XI_ENTITY,
	XI_OTHER,		/// internal DOCTYPE declarations
	RET_NULL,  /// nothing returned
	ENUM_LENGTH, /// size of array to hold all the other values
};


alias KeyValueBlock!(string,string,true) AttributeMap;
alias AttributeMap.BlockRec Attribute;

class AttrList {
	AttributeMap	map_;
	
	uintptr_t length() const @property 
	{
		return map_.length;
	}

	void takeOver(ref AttributeMap map)
	{
		map_.takeOver(map);
	}
	void explode()
	{
		map_.explode();
	}

	void opIndexAssign(string value, string name)
	{
		map_[name] = value;
	}
	void remove(string key)
	{
		map_.remove(key);
	}
}


	alias AttributeMap AttributePairs;

	/// As collection key
	struct XmlKey
	{
		const(char)[]       path_;
		XmlResult           type_;

		const hash_t toHash() nothrow @safe
		{
			hash_t result = type_;
			foreach(char c ; path_)
				result = result * 13 + c;
			return result;
		}

		const int opCmp(ref const XmlKey S)
		{
			int diff = S.type_ - this.type_;
			if (diff == 0)
				diff = cmp(S.path_, this.path_);
			return diff;
		}
	}
	/**

	Using an Associative Array to store attributes as name - value pairs,
	although it would seem a natural thing to do, was a performance drag,
	on most of large and small xml files tried so far. Even with a file with a dozen
	attributes on each element (unicode database file).
	Maybe the break even point for the number of attributes for
	AA vs linear array seems too high.

	*/
	class XmlReturn
	{
		XmlResult		type = XmlResult.RET_NULL;
		string			scratch;
		alias scratch			name;
		alias scratch			data;

		AttributeMap	attr;
		alias attr	attribute;

		Object			node; // maybe used to pass back some xml node or object

		/// should use attr[val].
		deprecated string opIndex(string val)
		{
			return attr.opIndex(val);
		}
		void reset()
		{
			scratch = null;
			node = null;
			attr.reset();
			type = XmlResult.RET_NULL;
		}
	}
	alias XmlReturn TagData;

	alias void delegate(XmlReturn ret) ParseDg;


/// number class returned by parseNumber
enum NumberClass
{
    NUM_ERROR = -1,
    NUM_EMPTY,
    NUM_INTEGER,
    NUM_REAL
};

/**
Parse regular decimal number strings.
Returns -1 if error, 0 if empty, 1 if integer, 2 if floating point.
 and the collected string.
No NAN or INF, only error, empty, integer, or real.
process a string, likely to be an integer or a real, or error / empty.
*/

NumberClass
parseNumber(R,W)(R rd, auto ref W wr,  int recurse = 0 )
{
    int   digitct = 0;
    bool  done = rd.empty;
    bool  decPoint = false;
    for(;;)
    {
        if (done)
            break;
        auto test = rd.front;
        switch(test)
        {
        case '-':
        case '+':
            if (digitct > 0)
            {
                done = true;
            }
            break;
        case '.':
            if (!decPoint)
                decPoint = true;
            else
                done = true;
            break;
        default:
            if (!std.ascii.isDigit(test))
            {
                done = true;
                if (test == 'e' || test == 'E')
                {
                    // Ambiguous end of number, or exponent?
                    if (recurse == 0)
                    {
                        wr.put(cast(char)test);
                        rd.popFront();
                        if (parseNumber(rd,wr, recurse+1)==NumberClass.NUM_INTEGER)
                            return NumberClass.NUM_REAL;
                        else
                            return NumberClass.NUM_ERROR;
                    }
                    // assume end of number
                }
            }
            else
                digitct++;
            break;
        }
        if (done)
            break;
        wr.put(cast(char)test);
        rd.popFront();
        done = rd.empty;
    }
    if (decPoint)
        return NumberClass.NUM_REAL;
    if (digitct == 0)
        return NumberClass.NUM_EMPTY;
    return NumberClass.NUM_INTEGER;
};

/// read in a string till encounter a character in sepChar set
/// This won't work for struct based R,W ?
bool readToken(R,W) (R rd, dstring sepSet, auto ref W wr)
{
    bool hit = false;
SCAN_LOOP:
    for(;;)
    {
        if (rd.empty)
            break;
        auto test = rd.front;
        foreach(dchar sep ; sepSet)
        {
             if (test == sep)
                break SCAN_LOOP;
        }

        wr.put(test);
        rd.popFront();
        hit = true;
    }
    return hit;
}
/// read in a string till encounter the dchar
bool readToken (R,W) (R rd, dchar match, auto ref W wr)
{
    bool hit = false;
SCAN_LOOP:
    for(;;)
    {
        if (rd.empty)
            break;
        auto test = rd.front;
        if (test == match)
            break SCAN_LOOP;
        wr.put(test);
        rd.popFront();
        hit = true;
    }
    return hit;
}

/** eat up exact match and return true. */
bool match(R)(R rd, dstring ds)
{
    auto slen = ds.length;
    if (slen == 0)
        return false; // THROW EXCEPTION ?
    size_t ix = 0;
    while ((ix < slen) && !rd.empty && (rd.front == ds[ix]))
    {
        ix++;
        rd.popFront();
    }
    if (ix==slen)
        return true;
    if (ix > 0)
        rd.pushFront(ds[0..ix]);
    return false;
}

bool matchChar(R)(R rd, dchar c)
{
    if (rd.empty)
        return false;
    if (c == rd.front)
    {
        rd.popFront();
        return true;
    }
    return false;
}


uint countSpace(R)(R rd)
{
    uint   count = 0;
    while(!rd.empty)
    {
        switch(rd.front)
        {
        case 0x020:
            break;
        case 0x09:
            break;
        case 0x0A:
            break;
        case 0x0D:
            break;
        default:
            return count;
        }
        rd.popFront();
        count++;
    }
    return count;
}
/** Using xml 1.1 (or 1.0 fifth edition ), plus look for ::, which terminates a name.
	name, or name::, return name, and -1 (need to check src further to disambiguate ::)
	return name:qname, and position of first ':'


*/

bool getQName(R)(R src, ref Buffer!char scratch, ref intptr_t prefix)
{
    scratch.length = 0;
    if (src.empty || !isNameStartChar11(src.front))
        return false;

    scratch.put(src.front);
    src.popFront();
    intptr_t ppos = -1;
    while(!src.empty)
    {
        dchar test = src.front;
        if (test == ':')
        {
            if (ppos >= 0)
            {
                // already got prefix
                break;
            }
            src.popFront();
            test = src.front;
            if (test == ':')
            {
                // end of name was reached, push back, leaving ::
                src.pushFront(':');
                break;
            }
            // its a prefix:name ?
            ppos = scratch.length;
            scratch.put(':');

        }
        if (isNameChar11(test))
            scratch.put(test);
        else
            break;
        src.popFront();
    }
    prefix = ppos;
    return true;
}

// presume front contains first quote character
bool unquote(R)(R src, ref Buffer!char scratch )
{
    dchar terminal = src.front;
    src.popFront();
    scratch.length = 0;

    for(;;)
    {
        if (src.empty)
            return false;
        if (src.front != terminal)
            scratch.put(src.front);
        else
        {
            src.popFront();
            break;
        }
        src.popFront();
    }
    return true;
}

bool getAttribute(R)(R src, ref string atname, ref string atvalue)
{
    Buffer!char temp;
    intptr_t pos;
    countSpace(src);
    if (getQName(src, temp, pos))
    {
        countSpace(src);
        if (match(src,"="))
        {
            countSpace(src);
            dchar test = src.front;
            atname = temp.unique;
            if (test=='\"' || test == '\'')
            {
                if (unquote(src, temp))
                {
                    atvalue = temp.unique;
                    return true;
                }
            }
        }
    }
    return false;
}


bool normalizeSpace(ref string value)
{
	Buffer!char	app;
	app.reserve(value.length);
	int spaceCt = 0;
	// only care about space characters
	for (size_t ix = 0; ix < value.length; ix++)
	{
		char test = value[ix];
		if (isSpace(test))
		{
			spaceCt++;
		}
		else
		{
			if (spaceCt)
			{
				app.put(' ');
				spaceCt = 0;
			}
			app.put(test);
		}
	}

	char[] result = app.toArray;
	if (result != value)
	{
		value = app.idup;
		return true;
	}
	return false;
}

/** Split string on the first ':'.
*  Return number of ':' found.
*  If no first splitting ':' found return nmSpace = "", local = name.
*  If returns 1, and nmSpace.length is 0, then first character was :
*  if returns 1, and local.length is 0, then last character was :
**/
intptr_t splitNameSpace(string name, out string nmSpace, out string local)
{
    intptr_t sepct = 0;

    auto npos = indexOf(name, ':');

    if (npos >= 0)
    {
        sepct++;
        nmSpace = name[0 .. npos];
        local = name[npos+1 .. $];
        if (local.length > 0)
        {
            string temp = local;
            npos = indexOf(temp,':');
            if (npos >= 0)
            {
                sepct++;  // 2 is already too many
                //temp = temp[npos+1 .. $];
                //npos = indexOf(temp,':');
            }
        }
    }
    else
    {
        local = name;
    }
    return sepct;
}