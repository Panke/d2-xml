/**


Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

Functions to pre-filter a file source, or string source, to a produce a UTF-8 string
usable by XmlStringParser in std.xmlp.sliceparse.

This uses the filter and recoding capabilities, and encoding
recognition ability of XmlParser in std.xmlp.xmlparse.

The extra overhead may mean not much performance difference to
using directly the XmlDtdParser in std.xmlp.doctype, or CoreParser in std.xmlp.xmlparse.

*/
module std.xmlp.slicedoc;

import std.stdint;
import std.xmlp.error;
import std.xmlp.sliceparse;
import std.xmlp.linkdom;
import alt.buffer;
import std.xmlp.parseitem;
import std.xmlp.subparse;
import std.xmlp.charinput;
import std.xmlp.xmlparse;
import std.xmlp.coreprint;

import std.conv;
import std.string;
import std.variant;
import std.stream;

/// convenience creator function
IXMLParser parseSliceXml(string s)
{
    return new XmlStringParser(s);
}
//
/**
	Filter XML characters, strip original encoding
*/
string decodeXml(XmlParser ps, double XMLVersion, uintptr_t origSize)
{
    Buffer!char	docString; // expanding buffer
	void putXmlDec(const(char)[] s)
	{
		docString.put(s); // put the declaration back without encoding
	}
    if (!ps.empty)
    {
        // declaration must be first, if it exists
        if (ps.matchInput("<?xml"d))
        {
            XmlReturn xmldec = new XmlReturn();
            ps.doXmlDeclaration(xmldec);
            // we swallowed the XML declaration, so re-create it,
            // Leave out encoding.
            // TODO: return what the original source encoding was?
            // not fair on parser to declare encoding to be something else.

			printXmlDeclaration(xmldec.attr, &putXmlDec);
        }
        // get the character type size, and length to reserve space?
        // only approximate, especially when recoding, but so what.

        docString.reserve(origSize);
		ps.notifyEmpty = null; // break apart from context end handler
        while(!ps.empty)
        {
            docString.put(ps.front);
            ps.popFront();
        }
    }
    return docString.idup;	/// TODO: would idup result in smaller (but copied) buffer?   allocator still uses powers of 2.
}

// Filter a string of XML according to XML source rules.
string decodeXmlString(string content, double XMLVersion=1.0)
{
    auto sf = new SliceFill!(char)(content);

    auto ps = new XmlParser(sf,XMLVersion); // filtering parser.
    ps.pumpStart();

    return decodeXml(ps, XMLVersion, content.length);
}

/** Convert any XML file into a UTF-8 encoded string, and filter XML characters
	Strips out original encoding from xml declaration.
*/

string decodeXmlFile(string path, double XMLVersion=1.0)
{
    auto s = new BufferedFile(path);
    scope(exit)
	    s.close();
    
    auto sf = new XmlStreamFiller(s);

    ulong savePosition = s.position;
    ulong endPosition = s.seekEnd(0);
    s.position(savePosition);

    auto ps = new XmlParser(sf,XMLVersion); // filtering parser.
    ps.pumpStart();
    uint slen = cast(uint) (endPosition / sf.charBytes);

    return decodeXml(ps, XMLVersion, slen);

}

unittest
{
string s = q"EOS
<?xml version="1.0"?>
<set>
	<one>A</one>
	<!-- comment -->
	<two>B</two>
</set>
EOS";
    try
    {
        auto xp = new XmlStringParser(s);
		XmlReturn ret;
		while(xp.parse(ret)){}
    }
    catch (Exception e)
    {
        assert(0, e.toString());
    }
}
