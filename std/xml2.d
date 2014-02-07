/**

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.

Classes and functions for creating and parsing XML documents.

Two XML Parsers:

std.xmlp.doctype.XmlDtdParser	: Able to validate fully against a DTD. Does well on published conformance tests.
std.xmlp.sliceparse.XmlStringParser : Able to slice up XML documents in one string at high speed.

There is an intermediate parser.
std.xmlp.xmlparse.CoreParser : Base class for XmlDtdParser.


One DOM, classes and methods similar to Java DOM.
std.xmlp.linkdom.

Compared to the std.xml, this offers a better DOM, speed, validation and flexibility and D source,

There is a semi-functioning XPath 1.0 implementation, and a toy transform test.
std.xpath.syntax
std.xpath.transform.

There may be some interest in std.xmlp.array, which uses a simple custom string allocater,
to gain some speed over the standard idup function.

Example applications:

books.d
sxml.d
conformance.d
xslt.d
makette.d

*/

module std.xml2;

public import std.xmlp.parseitem;

public import std.xmlp.domvisitor;

public import std.xmlp.charinput;
public import std.xmlp.feeder;
public import std.xmlp.sliceparse;
public import std.xmlp.slicedoc;
public import std.xmlp.domparse;
public import std.xmlp.xmlparse;
public import std.xmlp.doctype;
public import std.xmlp.subparse;

