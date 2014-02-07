
module std.xmlp.arraydombuild;

import std.xmlp.arraydom;
import std.xmlp.tagvisitor;

import std.xmlp.sliceparse;
import std.xmlp.xmlparse;
import std.xmlp.doctype;

import std.xmlp.subparse, std.xmlp.parseitem, std.xmlp.charinput;
import std.xmlp.builder;
import alt.buffer;
import std.stream;
import std.variant;


Document buildArrayDom(IXMLParser xp)
{
	auto tv = new TagVisitor(xp);
	auto xbuild = new ArrayDomBuilder();
	auto result = new Document();
	xbuild.init(result);
	tv.defaults.setBuilder(xbuild);
	tv.parseDocument(0);
	return result;
}


Document loadString(string xml, bool validate = true, bool useNamespaces = false)
{
    IXMLParser cp = new XmlStringParser(xml);
	cp.validate(validate);
	return buildArrayDom(cp);
}


/** Parse from a file $(I path).
Params:
path = System file path to XML document
validate = true to invoke ValidateParser with DOCTYPE support,
false (default) for simple well formed XML using CoreParser
useNamespaces = true.  Creates ElementNS objects instead of Element for DOM.


*/
Document loadFile(string path, bool validate = true, bool useNamespaces = false)
{
    auto s = new BufferedFile(path);
    auto sf = new XmlStreamFiller(s);
	IXMLParser cp = new XmlDtdParser(sf,validate);
	cp.setParameter(xmlAttributeNormalize,Variant(true));
	return buildArrayDom(cp);

}

/// collector callback class, used with XmlVisitor
class ArrayDomBuilder : Builder
{
    Buffer!Element		elemStack_;
    Element			    root;
    Element				parent;

    this()
    {
    }

    this(Element d)
    {
        init(d);
    }
    void init(Element d)
    {
        root = d;
        parent = root;
        elemStack_.reset();
        elemStack_.put(root);
    }
    override void init(XmlReturn ret)
    {
        auto e = createElement(ret);
        init(e);
    }
    override void pushTag(XmlReturn ret)
    {
        auto e = createElement(ret);
        elemStack_.put(e);
        parent.appendChild(e);
        parent = e;
    }
    override void singleTag(XmlReturn ret)
    {
        parent ~= createElement(ret);
    }

    override void popTag(XmlReturn ret)
    {
        elemStack_.popBack();
        parent =  (elemStack_.length > 0) ? elemStack_.back() : null;
    }
    override void text(XmlReturn ret)
    {
        parent ~= new Text(ret.scratch);
    }
    override void cdata(XmlReturn ret)
    {
        parent ~= new CData(ret.scratch);
    }
    override void comment(XmlReturn ret)
    {
        parent.appendChild(new Comment(ret.scratch));
    }
    override void processingInstruction(XmlReturn ret)
    {
		auto rec = ret.attr.atIndex(0);
		parent.appendChild(new ProcessingInstruction(rec.id, rec.value));
    }
    override void xmldec(XmlReturn ret)
    {
		root.attr = ret.attr;
    }
	override void explode()
	{
		elemStack_.reset();
		super.explode();
	}
}