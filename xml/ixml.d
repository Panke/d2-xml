module xml.ixml;

import std.string, std.stdint, std.utf, xml.xmlerror;
import std.algorithm;

enum CharFilter
{
    filterOff, filterOn, filterAlwaysOff
}

/// Parameter names for parser.
enum string xmlAttributeNormalize = "attribute-normalize";
enum string xmlCharFilter = "char-filter";
enum string xmlNamespaces = "namespaces";
enum string xmlFragment = "fragment";

//alias void delegate() SourceEmptyDg;
//alias void delegate(Exception)	PreThrowDg;
/// Return a string for the error code


import alt.buffer;


enum XmlResult {
	TAG_START,
	TAG_SINGLE, TAG_EMPTY = TAG_SINGLE,
	TAG_END,
	TEXT,
	CDATA,
	COMMENT,
	XML_PI,
	XML_DEC,
	DOC_END,
	DOC_TYPE,	/// DTD parse results contained in doctype as DtdValidate.
	XI_NOTATION,
	XI_ENTITY,
	XI_OTHER,		/// internal DOCTYPE declarations
	RET_NULL,  /// nothing returned
	ENUM_LENGTH, /// size of array to hold all the other values

}

enum NodeType
{
    None = 0,
	Element_node = 1,
	Attribute_node = 2,
	Text_node = 3,
	CDATA_Section_node = 4,
	Entity_Reference_node = 5,
	Entity_node = 6,
	Processing_Instruction_node = 7,
	Comment_node = 8,
	Document_node = 9,
	Document_type_node = 10,
	Document_fragment_node = 11,
	Notation_node = 12
};

enum EntityType { Parameter, General, Notation }

enum RefTagType { UNKNOWN_REF, ENTITY_REF, SYSTEM_REF, NOTATION_REF}

/// Kind of default value for attributes
enum AttributeDefault
{
    df_none,
    df_implied,
    df_required,
    df_fixed
}

/** Distinguish various kinds of attribute data.
The value att_enumeration means a choice of pre-defined values.
**/
enum AttributeType
{
    att_cdata,
    att_id,
    att_idref,
    att_idrefs,
    att_entity,
    att_entities,
    att_nmtoken,
    att_nmtokens,
    att_notation,
    att_enumeration
}

/// Call-backs for a parser wrap to re-assemble and transform parsed data. Natural resemblance to SAX, and James Clarks Expat.
class XmlEvent(T) {
	
	alias immutable(T)[] XmlString;
	alias KeyValueBlock!(XmlString, XmlString,true) AttributeMap;
	alias KeyValueBlock!(XmlString, XmlString,true).BlockRec Attribute;

	XmlResult	type;
	alias type  eventId;

	XmlString  name;
	alias name data;
	alias name scratch;

	AttributeMap	attr;
	alias attr attributes;
}

interface IXmlErrorHandler(T)
{
	XmlErrorLevel pushError(string s, XmlErrorLevel level);
	void checkErrorStatus();
	void setEncoding(const(T)[] codeName);

	Exception makeException(XmlErrorCode code);
	Exception makeException(string s, XmlErrorLevel level = XmlErrorLevel.FATAL);
	Exception caughtException(Exception x);
}

/// Parser interface callbacks are efficient, compared to delegates.
interface IXmlDocHandler(T)
{
	void init(ref XmlEvent!T s); // Allows user to set own XmlEvent class derivative
	void startTag( XmlEvent!T s); // tag, followed by attribute pairs
	void soloTag(XmlEvent!T s);
	void endTag(XmlEvent!T s); // tag
	void text(XmlEvent!T s); // text
	void cdata(XmlEvent!T s);
	void comment(XmlEvent!T s);
	void instruction(XmlEvent!T s); // Processing instruction name, content
	void declaration(XmlEvent!T s); // declaration attribute name, value
	
	void startDoctype(Object parser);		// notify of Dtd processing start
	void endDoctype(Object parser);		// notify of Dtd completed

	void notation(Object n);				// Notation entity data reference
	/// currently up to StdEventSize , ie XmlDeclaration last eventId
	/// just return the entity name, not decoded
	void entityName(const(T)[] s,bool inAttribute);
}

/// Implementation template that does nothing  but Exception handling


class XmlErrorImpl(T) : IXmlErrorHandler!T
{
	private {
		Buffer!string			errors_;
		XmlErrorLevel			maxError_;
	}

	XmlErrorLevel pushError(string s, XmlErrorLevel level)
	{
		errors_.put(s);
		if (maxError_ < level)
			maxError_ = level;
		return maxError_;
	}

	void checkErrorStatus(){}
	void setEncoding(const(T)[] codeName){}

	Exception preThrow(XmlError e)
	{
		return e;
	}

	Exception makeException(XmlErrorCode code)
	{
		return new XmlError(getXmlErrorMsg(code));

	}
	Exception makeException(string s, XmlErrorLevel level = XmlErrorLevel.FATAL)
	{
		return new XmlError(s,level);
	}

	Exception caughtException(Exception x)
	{
		auto s = x.toString();
		pushError(s, XmlErrorLevel.FATAL);
		return preThrow(new XmlError(s, XmlErrorLevel.FATAL));
	}
}

/// class with combined interfaces that does nothing
class NullDocHandler(T) : XmlErrorImpl!T, IXmlDocHandler!T {
	void init(ref XmlEvent!T s){} // Allows user to set own XmlEvent class derivative
	void startTag( XmlEvent!T s){} // tag, followed by attribute pairs
	void soloTag(XmlEvent!T s){}
	void endTag(XmlEvent!T s){} // tag
	void text(XmlEvent!T s){} // text
	void cdata(XmlEvent!T s){}
	void comment(XmlEvent!T s){}
	void instruction(XmlEvent!T s){} // Processing instruction name, content
	void declaration(XmlEvent!T s){} // declaration attribute name, value

	void startDoctype(Object parser){}		// notify of Dtd processing start
	void endDoctype(Object parser){}		// notify of Dtd completed

	void notation(Object n){}				// Notation entity data reference
	/// currently up to StdEventSize , ie XmlDeclaration last eventId
	/// just return the entity name, not decoded
	void entityName(const(T)[] s,bool inAttribute){}

}

static string badCharMsg(dchar c)
{
	if (cast(uint)c < 0x110000)
		return format("bad character 0x%x [%s]\n", cast(uint)c, c);
	else
		return format("Character exceeds Unicode range 0x%x\n", cast(uint)c);
}

/**
	Read only character array range, output dchar.
*/
struct  ReadRange(T)
{
	bool empty;
	dchar front;
	const(T)[]	data_;

	this(const(T)[] s)
	{
		data_ = s;
		empty = s.length == 0;
		popFront();
	}

	void popFront()
	{
		if (data_.length > 0)
		{
			static if (is(T == dchar))
			{
				front = data_[0];
				data_ = data_[1..$];
			}
			else {
				uintptr_t ix = 0;
				front = decode(data_, ix);
				data_ = data_[ix..$];
			}
		}
		else
			empty = true;
	}
}


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
