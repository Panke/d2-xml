module std.xmlp.tagvisitor;

/**
Copyright: Michael Rynn 2012.
Authors: Michael Rynn
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.


Maybe XmlVisitor isn't flexible enough.
---
// so to get text content of element, only, would set
auto txtget = new TagBlock("author");
txtget[XmlResult.STR_TEXT] = (XmlReturn ret) {
	book.author = ret.scratch;
}
---

---
*/

<<<<<<< TREE
import alt.zstring;
public import std.xmlp.parseitem, std.xmlp.subparse;
import std.variant, std.stdint;

version (GC_STATS)
{
	import alt.gcstats;
}

alias void delegate(TagVisitor tv)	TagCallback;

abstract class TagHandler {
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
	version (GC_STATS)
	{
		this()
		{
			gcStatsSum.inc();
		}

		~this()
		{
			gcStatsSum.dec();
		}
	}


	/**

	Called on the getting the starttag (or emptytag) element for which a Builder was setup.
	If XmlReturn.type is TAG_EMPTY
	then the endCall callback will be called directly after Builder method init, with the XmlResult reference!
	If the XmlReturn.type is TAG_START, then parsing will continue after the init method call.
	If the Builder object wants attribute information off its initial start tag, it must access them the init method,
	Note that pushTag is not called, for the tag name which triggered using the builder instance.
	Internally the XmlVisitor sets its Builder instance to the triggered builder, and routes XmlResult events to it,
	until it gets an endtag at the same element nesting level at which it was started.
	The end callback returns the builder object to the user, in the XmlResult.node Object member,
	after which it is forgotten by the XmlVisitor object.
	pushTag and popTag will only be called for children of the element that the builder was set up for. All other child content
	will call the appropriate method, test, cdata, comment, processing instruction.

	*/
	void init(TagVisitor ret){};
	/// A new child element, with content, in the scope of the builder
	void pushTag(TagVisitor ret){ debug(TRACE_BUILDER) writeln("Push tag ", ret.scratch);}
	/// A new child element with content ends in the scope of the builder
	void popTag(TagVisitor ret){ debug(TRACE_BUILDER) writeln("Pop tag ", ret.scratch);}
	/// A new child element, maybe with attributes, but no content, in the scope of the builder
	void singleTag(TagVisitor ret){}
	/// a text node child, in ret.scratch
	void text(TagVisitor ret){}
	/// a processing instruction child. target name in ret.names[0], rest in ret.values[0]
	void processingInstruction(TagVisitor ret){}
	/// another kind of text node child, in ret.scratch
	void cdata(TagVisitor ret){}
	/// another kind of text node child, in ret.scratch
	void comment(TagVisitor ret){}
	/// attributes in names and values of ret, should be only at root level
	void xmldec(TagVisitor ret){}

	/// pass a DTDValidate object?
	void doctype(TagVisitor ret){}

	void explode(bool del)
	{
		if (del)
			delete this;
	}
}
/** The set of XmlResult enum indexed callbacks , irrespective of tag name,
	used by TagVisitor to store default callback delegates
=======
import alt.buffer;
import alt.gcstats;
import std.xml2;

import std.variant;
import std.xmlp.builder;


/**
A XmlResult enumerated array of ParseDg
Recommended for prolog and epilog callbacks
eg, XML declaration, DTD, Notation callbacks.
>>>>>>> MERGE-SOURCE
*/

class DefaultTagBlock {


	void opIndexAssign(ParseDg dg, XmlResult rtype)
	in {
		assert(rtype < XmlResult.ENUM_LENGTH);
	}
	body {
		callbacks_[rtype] = dg;
	}
	/// return a default call back delegate.
	ParseDg opIndex(XmlResult rtype)
	in {
		assert(rtype < XmlResult.ENUM_LENGTH);
	}
	body {
		return callbacks_[rtype];
	}
	/// Sets all the callbacks of builder, except init.
	void setBuilder(Builder bob)
	{
		this[XmlResult.TAG_START] = &bob.pushTag;
		this[XmlResult.TAG_SINGLE] = &bob.singleTag;
		this[XmlResult.TAG_END] = &bob.popTag;
		this[XmlResult.STR_TEXT] = &bob.text;
		this[XmlResult.STR_PI] = &bob.processingInstruction;
		this[XmlResult.STR_CDATA] = &bob.cdata;
		this[XmlResult.STR_COMMENT] = &bob.comment;
		this[XmlResult.XML_DEC] = &bob.xmldec;
		this[XmlResult.DOC_TYPE] = &bob.doctype;
	}
	this()
	{

	}

	this(const DefaultTagBlock b )
	{
		callbacks_[0..$] = b.callbacks_[0..$];
	}

	ParseDg[XmlResult.ENUM_LENGTH]	callbacks_;  // all

}

/// 
class TagBlock {
	version (GC_STATS)
	{
<<<<<<< TREE

=======
		import alt.gcstats;
>>>>>>> MERGE-SOURCE
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}

	string			tagkey_;	// key
	ParseDg[XmlResult.DOC_END]		callbacks_;  // indexed by (XmlReturn.type - 1). Can have multiple per element.

	this(string tagName)
	{
		tagkey_ = tagName; // can be null?
		version (GC_STATS)
			gcStatsSum.inc();
	}

	version (GC_STATS)
	{
		~this()
		{
			gcStatsSum.dec();
		}
	}
	void opIndexAssign(ParseDg dg, XmlResult rtype)
	in {
		assert(rtype < XmlResult.DOC_END);
	}
	body {
		callbacks_[rtype] = dg;
	}

	ParseDg opIndex(XmlResult rtype)
	in {
		assert(rtype < XmlResult.DOC_END);
	}
	body {
		return callbacks_[rtype];
	}

	bool didCall(XmlReturn ret)
	in {
		assert(ret.type < XmlResult.DOC_END);
	}
	body {
		auto dg = callbacks_[ret.type];
		if (dg !is null)
		{
			dg(ret);
			return true;
		}
		return false;
	}

}
<<<<<<< TREE

/**
Yet another version of callbacks for XML.
---
auto tv = new TagVisitor(xmlParser);

auto mytag = new TagBlock("mytag");
mytag[XmlResult.TAG_START] = (ref XmlReturn ret){

};
mytag[XmlResult.TAG_SINGLE] = (ref XmlReturn ret){

};
---

*/



/**
	TagVisitor only visits an XML parse for the subtree for which parseDocument was called.
	This should allow nesting of parseDocument calls, even if called from the same TagVisitor instance.
	The parseDocument method tracks the relative element depth on entry.
	Depth increases TAG_START, and decreases for each TAG_END. The parseDocument method exits
	as the parse leaves the original element context it was called in.

	The DefaultTagBlock member defaults is constructed with null,
	so if default visitor handlers need to set and passed around, it needs to be set or copied in user code.
<<<<<<< TREE

=======
	
	The ParseLevel stack needs to be thought out a bit more.  With each TAG_START indicating a new nesting,
	the handlers for that tag are pulled out and put at the current parse level.
	Current ParseLevel handler is current_.handlers_.
	
	
 Big question, refresh all or only some TagBlocks, after put, or remove TagBlock for tagkey, on the stack?
 Or current ParseLevel.  Allow access to ParseLevel stack?

 Does the Parselevel tagname/TagBlock instance still correlate?
 What if TagBlock was removed entirely, not replaced with put?
  Need the programmer to have good idea of what will happen.
 Idea so far. Change none of stacked TagBlock instances at all,
 for automatic 
 Provide extra TagVisitor method, get and set TagBlock, to replace current
 

>>>>>>> MERGE-SOURCE
*/

class TagVisitor  {
	// Ensure Tag name, and current associated TagBlock are easily obtained after TAG_END.
	private struct ParseLevel
	{
		string		tagName;
		TagBlock	handlers_;
	};

	Array!ParseLevel			parseStack_;
	ParseLevel					current_; // whats around now.
	intptr_t					level_; // start with just a level counter.
	
	TagBlock[string]			tagHandlers_;
	bool						called_;			// some handler was called.
public:
	DefaultTagBlock				defaults;
	XmlReturn					state;
	IXMLParser					parser;
	
	
	// flag to recheck stack TagBlock
	/// Experimental and dangerous for garbage collection. No other references must exist.
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
	/// create, add and return new named TagBlock. Does not set stack
	TagBlock create(string tag)
	{
		auto result = new TagBlock(tag);
		tagHandlers_[tag] = result;
		return result;
	}

	/// convenience for single delegate assignments for a tag string
	/// Not that null tag will not be called, only real tag names are looked up.
	/// Delegate callbacks can be set to null
	void opIndexAssign(TagCallback dg, string tag, XmlResult rtype)
	{
		auto tb = tagHandlers_.get(tag,null);
		if (tb is null)
=======
/// Nearly transparent access to AA, with convenience functions for TagBlock set and get.

struct TagHandlerSet {
	TagBlock[string] tags;

	void opIndexAssign(ParseDg dg, string tag, XmlResult rtype)
	{
		auto tb = tags.get(tag,null);
		if (tb is null) 
>>>>>>> MERGE-SOURCE
		{
			tb = new TagBlock(tag);
			tags[tag] = tb;
		}
		tb[rtype] = dg;
	}
	/// return value of a named callback
	ParseDg opIndex(string tag, XmlResult rtype)
	{
		auto tb = tags.get(tag, null);
		if (tb !is null)
			return tb[rtype];
		return null;
	}
	/// return block of call backs for tag name
	void opIndexAssign(TagBlock tb, string tag)
	{
		if (tb is null)
			tags.remove(tag);
		else
		{
			tags[tag] = tb;
		}
	}	/// return block of call backs for tag name
	TagBlock opIndex(string tag)
	{
		return tags.get(tag, null);
	}
	/// set a block of callbacks for tag name, using the blocks key value.
	void put(TagBlock tb)
	{
		tags[tb.tagkey_] = tb;
	}
	/// set a default call back delegate.

	/// remove callbacks for a tag name.
	void remove(string tbName)
	{
		tags.remove(tbName);
	}
}

class TagVisitor  {
	// Ensure Tag name, and current associated TagBlock are easily obtained after TAG_END.
	private struct ParseLevel
	{
		string		tagName;
		TagBlock	handlers_;
	};

	Buffer!ParseLevel			parseStack_;
	ParseLevel					current_; // whats around now.
	protected IXMLParser		xp_;
	intptr_t					level_; // start with just a level counter.
	TagHandlerSet				tagHandlers_;
	XmlReturn					ret;
	Buffer!TagHandlerSet		handlerStack_;
	bool						called_;			// some handler was called.
public:
	DefaultTagBlock				defaults;

	/// Experimental and dangerous for garbage collection. No other references must exist.
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}

	void pushHandlerSet(TagHandlerSet tset)
	{
		handlerStack_.put(tagHandlers_);
		tagHandlers_ = tset;
	}
	void popHandlerSet()
	{
		tagHandlers_ = (handlerStack_.length > 0) ? handlerStack_.movePopBack() : TagHandlerSet.init;
	}

	@property {
		void handlerSet(TagHandlerSet tset)
		{
			tagHandlers_ = tset;
		}

		TagHandlerSet handlerSet()
		{
			return tagHandlers_;
		}
	}
	void explode()
	{
		this.clear();
	}

	/// Construct with IXMLParser interface
	this(IXMLParser xp)
	{
		ret = new XmlReturn();

		xp_ = xp;
		version(GC_STATS)
			gcStatsSum.inc();
		// This is a low level handler.
		xp_.setParameter(xmlAttributeNormalize,Variant(true));
		defaults = new DefaultTagBlock();
		xp_.initParse();
	}

	~this()
	{
		version(GC_STATS)
			gcStatsSum.dec();
	}

    /** Do a callback controlled parse of document
		Adjust level, if already got start tag, by -1, to exit after end tag
	*/
    void parseDocument(intptr_t adjustLevel)
    {
        // Has to be depth - 1, otherwise premature exit
        intptr_t    endLevel = xp_.tagDepth() + adjustLevel;
		//intptr_t	builderLevel = 0;
		
        while(xp_.parse(ret))
        {
			called_ = false;
			switch(ret.type)
			{
				case XmlResult.TAG_START:
					// a new tag.
					parseStack_.put(current_);
					current_.tagName = ret.scratch;
					current_.handlers_ = tagHandlers_.tags.get(ret.scratch,null);
					if (current_.handlers_ !is null)
						called_ = current_.handlers_.didCall(ret);
					break;
				case XmlResult.TAG_SINGLE:
					// no push required, but check after
					auto tb = tagHandlers_.tags.get(ret.scratch,null);
					if (tb !is null)
					{
						called_ = tb.didCall(ret);
					}
					break;
				case XmlResult.TAG_END:
					if (current_.handlers_ !is null)
						called_ = current_.handlers_.didCall(ret);
					auto depth = xp_.tagDepth();
					if (depth <= endLevel || depth == 0)
						return; // loopbreaker
					if (parseStack_.length > 0)
<<<<<<< TREE
<<<<<<< TREE
					{
						current_ = parseStack_.back();
=======
					{// This allows callback to set for outer level, if it exists.
						current_ = parseStack_.back();	
>>>>>>> MERGE-SOURCE
						parseStack_.popBack();
					}
					if (taghandlers !is null)
						called_ = taghandlers.didCall(this);
					
					if (elementDepth==0)
						return; // leave the nest
					elementDepth--;
=======
						current_ = parseStack_.movePopBack();
>>>>>>> MERGE-SOURCE
					break;
				default:
					if (ret.type < XmlResult.DOC_END)
					{
						if (current_.handlers_ !is null)
							called_ = current_.handlers_.didCall(ret);
					}
					else if (ret.type == XmlResult.DOC_END)
					{
						return;
					}

					break;
			}
			if (!called_)
			{
				auto dg = defaults.callbacks_[ret.type];
				if (dg !is null)
					dg(ret);
			}
        }
    }
}
