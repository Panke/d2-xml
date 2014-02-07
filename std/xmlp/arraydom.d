/**
	A very abbreviated Xml tree, with array of Item instead of links.

Authors: Michael Rynn
*/

module std.xmlp.arraydom;


import alt.buffer;

//import std.xmlp.subparse;
import std.xmlp.parseitem;
import std.xmlp.coreprint;
//import std.xmlp.charinput;
import std.xmlp.nodetype;
import core.stdc.string;
import std.string;
import std.conv;
import std.array;
import std.exception;
import std.stream;

/** Specifically made for taking attributes from XmlReturn */
/** When shared with linkdom, take care to distinguish which module */

version(GC_STATS)
	import alt.gcstats;

alias Buffer!Item ItemList;

/// Base class of all XML nodes.
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
		this.clear();
	}

    /// This item as text
    abstract override string toString() const;
    ///  Item tree as text array
    string[] pretty(uint indent)
    {
        string s = strip(toString());
        return s.length == 0 ? [] : [ s ];
    }

    final NodeType nodeType()  const  @property 
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
    string content;

    this(string c)
    {
        content = c;
        nodeType_ = NodeType.Text_node;
    }

    string getContent()
    {
        return content;
    }

    override  string toString() const
    {
        return content;
    }
}

/// Comments
class Comment :  Text
{
    this(string s)
    {
        super(s);
        nodeType_ = NodeType.Comment_node;
    }
    override string toString() const
    {
        return makeXmlComment(content);
    }
};

/// CDATA for text with markup
class CData :  Text
{
    this(string s)
    {
        super(s);
        nodeType_ = NodeType.CDATA_Section_node;
    }
    override  string toString() const
    {
        return makeXmlCDATA(content);
    }
}


/**
	ProcessingInstruction has target name, and data content
*/
class ProcessingInstruction : Text
{
    string target;

    this(string target, string data)
    {
        super(data);
        this.target = target;
        nodeType_ = NodeType.Processing_Instruction_node;
    }
    override  string toString() const
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
    string	tag;

    this(string id, AttributeMap amap)
    {
        this(id);
        attr = amap;
    }
    this(string id, string content)
    {
        this(id);
        children.put(new Text(content));
    }

    bool hasAttributes()
    {
        return (attr.length > 0);
    }
    ref AttributeMap getAttributes()
    {
        return attr;
    }
    alias getAttributes attributes;

    this(string id)
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

	void addText(string text)
	{
		children.put(new Text(text));
	}

    void removeAttribute(string key)
    {
		attr.remove(key);
    }
    void setAttribute(string name, string value)
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
    @property  string text() const
    {

        Buffer!char	app;

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
    override string[] pretty(uint indent)
    {
        Buffer!string app;
        ImmuteAlloc!char   imut;

        void addstr(const(char)[] s)
        {
            app.put(imut.alloc(s));
        }
        auto opt = XmlPrintOptions(&addstr);

        auto tp = XmlPrinter(opt, indent);

        printElement(cast(Element)this, tp);

        return app.toArray;
    }

    override string toString() const
    {
        Buffer!char result;

        void addstr(const(char)[] s)
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
    ref AttributeMap getAttributes()
    {
        return attributes_;
    }

    void removeAttribute(string key)
    {
        attributes_.remove(key);
    }

    void setAttribute(string name, string value)
    {
        attributes_[name] = value;
    }
}

/// A Document should be a node
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

    void setXmlVersion(string v)
    {
        attr["version"] = v;
    }

    void setStandalone(bool value)
    {
        string s = value ? "yes" : "no";
        attr["standalone"] = s;
    }

    void setEncoding(string enc)
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
    override string[] pretty(uint indent = 2)
    {
        Buffer!string app;
        ImmuteAlloc!char	imute;

        void addstr(const(char)[] s)
        {
            app.put(imute.alloc(s));
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
        printItems(children.toArray, tp);
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
            tp.putIndent(item.toString());
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
            tp.putTextElement(e.tag, e.attributes(), t.toString());
            return;
        }
    }

    tp.putStartTag(e.tag, e.attr,false);

    auto tp2 = XmlPrinter(tp);
	printItems(e.children.toArray, tp2);
    tp.putEndTag(e.tag);
}


/// Element from TAG_START or TAG_EMPTY
Element createElement(XmlReturn ret)
{
    Element e = new Element(ret.scratch);
	e.attr = ret.attr;
    return e;
}



