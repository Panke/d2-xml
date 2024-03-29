module xml.xmlerror;

import std.stdint, std.string;

enum XmlErrorLevel {
	OK = 0,
	INVALID = 1,
	ERROR = 2,
	FATAL = 3
}


class XmlError : Exception {
	XmlErrorLevel	level_;
	string[]		errorList_;

	this(string msg, XmlErrorLevel level = XmlErrorLevel.FATAL)
	{
		level_ = level;
		super(msg);
	}

	void errorList(string[] list) @property
	{
		errorList_ = list;
	}

	string[] errorList() @property 
	{
		return errorList_;
	}
	@property XmlErrorLevel level() const 
	{
		return level_;
	}
}
/// Common messages that have a string lookup.
enum XmlErrorCode
{
	NO_CODE,
    UNEXPECTED_END,
    TAG_FORMAT,
    MISSING_QUOTE,
    EXPECTED_ATTRIBUTE,
    BAD_CHARACTER,
    MISSING_SPACE,
    DUPLICATE_ATTRIBUTE,
    ELEMENT_NESTING,
    CDATA_COMMENT,
    BAD_ENTITY_REFERENCE,
    MISSING_END_BRACKET,
    EXPECTED_NAME,
    CONTEXT_STACK,
	EXPECT_INCLUDE,
	CIRCULAR_ENTITY_REFERENCE,
};


string getXmlErrorMsg(int code)
{
    switch(code)
    {
		case XmlErrorCode.UNEXPECTED_END:
			return "Unexpected end to parse source";
		case XmlErrorCode.TAG_FORMAT:
			return "Tag format error";
		case XmlErrorCode.MISSING_QUOTE:
			return "Missing quote";
		case XmlErrorCode.EXPECTED_ATTRIBUTE:
			return "Attribute value expected";
		case XmlErrorCode.BAD_CHARACTER:
			return "Bad character value";
		case XmlErrorCode.MISSING_SPACE:
			return "Missing space character";
		case XmlErrorCode.DUPLICATE_ATTRIBUTE:
			return "Duplicate attribute";
		case XmlErrorCode.ELEMENT_NESTING:
			return "Element nesting error";
		case XmlErrorCode.CDATA_COMMENT:
			return "Expected CDATA or Comment";
		case XmlErrorCode.BAD_ENTITY_REFERENCE:
			return "Expected entity reference";
		case XmlErrorCode.MISSING_END_BRACKET:
			return "Missing end >";
		case XmlErrorCode.EXPECTED_NAME:
			return "Expected name";
		case XmlErrorCode.CONTEXT_STACK:
			return "Pop on empty context stack";
		case XmlErrorCode.EXPECT_INCLUDE:
			return "INCLUDE or IGNORE expected";
		case XmlErrorCode.CIRCULAR_ENTITY_REFERENCE:
			return "Circular entity reference";
		default:
			break;
    }
    return format("Unknown error code: %s ",code);
}
/// Used to communicate error details
class DOMError  :  Object
{

protected:
    DOMLocator		location_;
    string			message_;
    uint			severity_;
    Exception		theError_;
public:

    enum
    {
        NO_ERROR = 0,
			SEVERITY_WARNING,
			SEVERITY_ERROR,
			SEVERITY_FATAL_ERROR
    }
    /// constructor
    this(string msg)
    {
        message_ = msg;
    }

    package void setSeverity(uint level)
    {
        severity_ = level;
    }

    package void setException(Exception x)
    {
        theError_ = x;
    }

    package void setLocator(DOMLocator loc)
    {
        location_ = loc;
    }
    /// DOM property
    DOMLocator getLocation()
    {
        return location_;
    }
    /// DOM property
    string getMessage()
    {
        return message_;
    }
    /// DOM property
    uint   getSeverity()
    {
        return severity_;
    }
    /// DOM property
    Object getRelatedData()
    {
        return null;
    }
    /// DOM property
    Object getRelatedException()
    {
        return theError_;
    }
    /// DOM property
    string getType()
    {
        return "null";
    }
}


/// Used to communicate the source position of an error
class DOMLocator
{
package:
    // TODO : get character units size
    intptr_t		charsOffset; // position in stream Characters
    intptr_t		lineNumber;
    intptr_t		colNumber;
public:
	this(intptr_t byteOffset, intptr_t colNo, intptr_t lineNo)
    {
        charsOffset = byteOffset;
        lineNumber = lineNo;
        colNumber = colNo;
    }

	this()
    {
        charsOffset = -1;
        lineNumber = -1;
        colNumber = -1;
    }

    /// Not sure if supposed to depend on stream character size.
    intptr_t getByteOffset() const
    {
        return charsOffset;
    }
    /// characters in the line
    intptr_t getColumnNumber() const
    {
        return colNumber;
    }
    /// The line number
    intptr_t getLineNumber() const
    {
        return lineNumber;
    }

    intptr_t getUtf16Offset()
    {
        return -1;
    }
}

/**
By setting this using the DOMConfiguration interface,
can get to handle, report and even veto some errors
*/

class DOMErrorHandler
{
    /// Return true if error is non-fatal and it was handled.
    bool handleError(DOMError error)
    {
        return false; // stop processing
    }
}

struct SourceRef
{
    intptr_t		charsOffset; // position in stream of source haracters. Absolute or encoding dependent?
    intptr_t		lineNumber; // encoding dependent
    intptr_t        colNumber;	 // encoding dependent
};


XmlError preThrowHandler(XmlError ex, DOMErrorHandler eh, ref SourceRef spos)
{
	/* auto conf = doc_.getDomConfig();
	Variant v = conf.getParameter("error-handler");
	DOMErrorHandler* peh = v.peek!(DOMErrorHandler);
	*/

		//TODO: is it ever really going to be null?
		string msg =  ex.toString();
		// supporting DOMError
		DOMError derr = new DOMError(msg);
		DOMLocator loc = new DOMLocator(spos.charsOffset,spos.colNumber,spos.lineNumber);
		derr.setLocator(loc);
		derr.setException(ex);
		int severity;
		switch(ex.level)
		{
			case XmlErrorLevel.ERROR:
				severity = DOMError.SEVERITY_ERROR;
				break;
			case XmlErrorLevel.FATAL:
				severity = DOMError.SEVERITY_FATAL_ERROR;
				break;
			default:
				severity = DOMError.SEVERITY_WARNING;
				break;
		}

		derr.setSeverity(severity);
		eh.handleError(derr);

		return ex;
}
