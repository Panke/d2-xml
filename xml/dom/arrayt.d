/**
A very abbreviated Xml tree, with array of Item instead of links.
DOM features:  NodeType in base class Item.

Authors: Michael Rynn
*/

module xml.dom.arrayt;


import alt.buffer;
import xml.util.print;

import std.string, std.conv, std.exception, std.stream;
import std.variant;
version(GC_STATS)
import alt.gcstats;

//debug = VERBOSE;
debug(VERBOSE)
{
	import std.stdio;
}

/// Features like std.xml.  Limited functionality.
/// Template for string character type.
/// Base class Object string toString() may require translation.
/// toXml()
/// Elements, Attributes, nodes, have no parent or owner member.
import xml.ixml, xml.util.print;

template XMLARRAY(T) {


	alias XMLPrint!T.makeXmlComment makeXmlComment;
	alias XMLPrint!T.makeXmlCDATA makeXmlCDATA;
	alias XMLPrint!T.makeXmlProcessingInstruction makeXmlProcessingInstruction;
	alias XMLPrint!T.printXmlDeclaration printXmlDeclaration;
	alias XMLPrint!T.XmlPrintOptions XmlPrintOptions;
	alias XMLPrint!T.XmlPrinter XmlPrinter;
	alias XMLPrint!T.StringPutDg		StringPutDg;

	alias immutable(T)[]				XmlString;
	alias XmlEvent!T.AttributeMap		AttributeMap;
	alias XmlEvent!T					XmlReturn;
	alias Buffer!Item ItemList;


	abstract class Item
	{
		version(GC_STATS)
		{
			mixin GC_statistics;
			static this()
			{
				setStatsId(typeid(typeof(this)).toString());
			}

			this()
			{
				gcStatsSum.inc();
			}
			~this()
			{
				gcStatsSum.dec();
			}
		}


		void explode()
		{

		}

		abstract XmlString toXml() const;

		/// This item as text
		override string toString() const
		{
			return to!string(toXml());
		}
		///  Item tree as text array
		XmlString[] pretty(uint indent)
		{
			XmlString s = strip(toXml());
			return s.length == 0 ? [] : [ s ];
		}

		final NodeType nodeType()   const @property
		{
			return nodeType_;
		}
	private:
		NodeType	nodeType_;
	}


/// For Text, CDATA, and Comment
class Text :  Item
{
    ///
    XmlString content;

    this(immutable(T)[] c)
    {
        content = c;
        nodeType_ = NodeType.Text_node;
    }

    XmlString getContent()
    {
        return content;
    }

    override  XmlString toXml() const
    {
        return content;
    }
}

/// Comments
class Comment :  Text
{
    this(XmlString s)
    {
        super(s);
        nodeType_ = NodeType.Comment_node;
    }
    override XmlString toXml() const
    {
        return makeXmlComment(content);
    }
};

/// CDATA for text with markup
class CData :  Text
{
    this(XmlString s)
    {
        super(s);
        nodeType_ = NodeType.CDATA_Section_node;
    }
    override  XmlString toXml() const
    {
        return makeXmlCDATA(content);
    }
}


/**
ProcessingInstruction has target name, and data content
*/
class ProcessingInstruction : Text
{
    XmlString target;

    this(XmlString target, XmlString data)
    {
        super(data);
        this.target = target;
        nodeType_ = NodeType.Processing_Instruction_node;
    }
    override  XmlString toXml() const
    {
        return makeXmlProcessingInstruction(target,content);
    }
}



/**
Simplified Element, name in content field,  with all children in array, attributes in a block
*/
class Element :  Item
{
    AttributeMap   			attr;
    ItemList				children;
    XmlString				tag;

    this(XmlString id, AttributeMap amap)
    {
        this(id);
        attr = amap;
    }
    this(XmlString id, XmlString content)
    {
        this(id);
        children.put(new Text(content));

    }

    bool hasAttributes()
    {
        return (attr.length > 0);
    }
    ref auto getAttributes()
    {
        return attr;
    }
    alias getAttributes attributes;

    this(XmlString id)
    {
        tag = id;
        nodeType_ = NodeType.Element_node;
    }

    this()
    {
        nodeType_ = NodeType.Element_node;
    }

	override void explode()
	{
		attr.explode();

		foreach(item ; children)
		{
			item.explode();
		}
		children.reset();
		super.explode();
	}

	int opApply(int delegate(Item item) dg)
	{
		foreach(item ; children)
		{
            int result = dg(item);
            if (result)
                return result;
		}
		return 0;
	}

    auto childElements()
    {
		return children[];
    }

    void setChildren(ItemList chList)
    {
        children = chList;
    }

    auto getChildren()
    {
		return children[];
    }

    void removeAttribute(XmlString key)
    {
		attr.remove(key);
    }
    void setAttribute(XmlString name, XmlString value)
    {
		attr[name] = value;
    }

    final bool empty()
    {
        return children.length == 0;
    }

    void appendChild(Item n)
    {
		children.put(n);
    }
    alias appendChild opCatAssign;

	void addText(XmlString s)
	{
		appendChild(new Text(s));
	}

	void addCDATA(XmlString s)
	{
		appendChild(new CData(s));
	}

	void addComment(XmlString s)
	{
		appendChild(new Comment(s));
	}

    /**
	* Returns the decoded interior of an element.
	*
	* The element is assumed to containt text <i>only</i>. So, for
	* example, given XML such as "&lt;title&gt;Good &amp;amp;
	* Bad&lt;/title&gt;", will return "Good &amp; Bad".
	*
	* Params:
	*      mode = (optional) Mode to use for decoding. (Defaults to LOOSE).
	*
	* Throws: DecodeException if decode fails
	*/
    @property  XmlString text() const
    {

        Buffer!T	app;
        foreach(item; children.peek)
        {
			auto nt = item.nodeType;
			switch(nt)
			{
				case NodeType.Text_node:
					Text t = cast(Text) cast(void*) item;
					if (t !is null)
						app.put(t.content);
					break;
				case NodeType.Element_node:
					Element e = cast(Element) cast(void*) item;
					if (e !is null)
						app.put(e.text);
					break;
				default:
					break;

			}

        }
        return app.idup;
    }


    /**
	* Returns an indented string representation of this item
	*
	* Params:
	*      indent = (optional) number of spaces by which to indent this
	*          element. Defaults to 2.
	*/
    override XmlString[] pretty(uint indent)
    {
        Buffer!XmlString app;

        void addstr(const(T)[] s)
        {
            app.put(s.idup);
        }
        auto opt = XmlPrintOptions(&addstr);

        auto tp = XmlPrinter(opt, indent);

        printElement(cast(Element)this, tp);

        return app.toArray;
    }

    override XmlString toXml() const
    {
        Buffer!T result;

        void addstr(const(T)[] s)
        {
            result.put(s);
        }
        auto opt = XmlPrintOptions(&addstr);
        auto tp = XmlPrinter(opt);
        printElement(cast(Element)this, tp);
        return result.idup();
    }

}


class XmlDec : Item
{
private:
    AttributeMap attributes_;
public:
    auto ref getAttributes()
    {
        return attributes_;
    }

    void removeAttribute(XmlString key)
    {
        attributes_.remove(key);
    }

    void setAttribute(XmlString name, XmlString value)
    {
        attributes_[name] = value;
    }
}

/// Document is an Element with a member for the document Element
class Document : Element
{
private:
    Element			docElement_;
public:

    this(Element e = null)
    {
        nodeType_ = NodeType.Document_node;
        if (e !is null)
        {
			children.put(e);
            docElement_ = e;
        }
    }

	Element  docElement() @property
	{
		return docElement_;
	}
    void setXmlVersion(XmlString v)
    {
        attr["version"] = v;
    }

    void setStandalone(bool value)
    {
        XmlString s = value ? "yes" : "no";
        attr["standalone"] = s;
    }

    void setEncoding(XmlString enc)
    {
        attr["encoding"] = enc;
    }

	override void explode()
	{
		docElement_ = null; // avoid dangler
		super.explode();
	}

    override void appendChild(Item e)
    {
        Element elem = cast(Element) e;
        if (elem !is null)
        {
            if (docElement_ is null)
            {
                docElement_ = elem;
            }
            else
            {
                docElement_.appendChild(elem);
                return;
            }
        }
		children.put(e);

    }
    /**
	* Returns an indented string representation of this item
	*
	* Params:
	*      indent = (optional) number of spaces by which to indent this
	*          element
	*/
    override XmlString[] pretty(uint indent = 2)
    {
        Buffer!XmlString app;

        void addstr(const(T)[] s)
        {
            app.put(s.idup);
        }
        printOut(&addstr, indent);
        return app.toArray;
    }

    void printOut(StringPutDg dg, uint indent = 2)
    {
        auto opt = XmlPrintOptions(dg);
        auto tp = XmlPrinter(opt, indent);
        size_t alen = attr.length;
        if (alen > 0)
        {
            printXmlDeclaration((cast(Document) this).getAttributes(), dg);
        }
		printItems(children.peek, tp);

    }

};
/// print element children
void printItems(const Item[] items, ref XmlPrinter tp)
{
    if (items.length == 0)
        return;

    foreach(item ; items)
    {
        Element child = cast(Element) item;
        if (child is null)
        {
            tp.putIndent(item.toXml());
        }
        else
        {
            printElement(child, tp);
        }
    }
}

/// Output with core print
void printElement(Element e, ref XmlPrinter tp)
{
    auto ilen = e.children.length;
    auto atlen = e.attr.length;

    if (ilen==0 && atlen==0)
    {
        tp.putEmptyTag(e.tag);
        return;
    }
    if (e.children.length == 0)
    {
        tp.putStartTag(e.tag, e.attributes(),true);
        return;
    }

    if (e.children.length == 1)
    {
        Text t = cast(Text)(e.children[0]);
        if (t !is null)
        {
            tp.putTextElement(e.tag, e.attributes(), t.toXml());
            return;
        }
    }

    tp.putStartTag(e.tag, e.attr,false);

    auto tp2 = XmlPrinter(tp);

	printItems(e.children.peek, tp2);

    tp.putEndTag(e.tag);
}


/// Element from TAG_START or TAG_EMPTY
Element createElement(XmlReturn ret)
{
    Element e = new Element(ret.scratch);
	e.attr = ret.attr;
    return e;
}




}


