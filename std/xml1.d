/**
	This module provides an ElementParser behaviour that loosely resembles that of the original std.xml
	A difference is that this ElementParser provides HandlerSet, which can be set, exchanged, pushed and
	popped during a parse.


===


===

*/
module std.xml1;

public import std.xmlp.parseitem;
public import std.xmlp.arraydom;
public import std.xmlp.sliceparse;

import std.xmlp.subparse;
import std.string, std.stdint, std.variant;

import alt.buffer, alt.gcstats;

class ElementParser 
{
	alias string XmlString;
	alias void delegate(XmlReturn r) Handler; // event object
	alias void delegate(in Element) ElementHandler; // end tag constructed element tree
	alias void delegate(ElementParser) ParserHandler; // event object is property of parser

	class HandlerSet {
		Handler					  onText;
		Handler					  onPI;
		Handler					  onCDATA;
		Handler					  onComment;
		ParserHandler[XmlString]  onStartTag;
		ElementHandler[XmlString] onEndTag; // A start match starts an Element tree
	}
	private {
		XmlString			src_;
		XmlStringParser		parser_;
		Buffer!HandlerSet	stack_;
		Buffer!Element		elemStack_; 
		// track Element parents, because ArrayDom has no parent field
		// working set
		Handler					  onText_;
		Handler					  onPI_;
		Handler					  onCDATA_;
		Handler					  onComment_;
		Handler					  onXmlDec_;

		bool called_;
	}
public:	
	ParserHandler[XmlString]  onStartTag;
	ElementHandler[XmlString] onEndTag; // A start match starts an Element tree
	@property {
		void onPI(Handler handler) { onPI_ = handler; }
		void onText(Handler handler) { onText_ = handler; }
		void onCDATA(Handler handler) { onCDATA_ = handler; }
		void onComment(Handler handler) { onComment_ = handler; }
		void onXI(Handler handler) { onXmlDec_ = handler; }
	}

	XmlReturn	tag;

	version (GC_STATS)
	{
		mixin GC_statistics;
	}

	this(XmlString s)
	{
		version(GC_STATS)
			gcStatsSum.inc();


		src_ = s;
		parser_ = new XmlStringParser(s);
		tag = new XmlReturn();
		stack_.reserve(10);
	}

	version(GC_STATS)
	{
		~this()
		{
		gcStatsSum.inc();
		}
	}
	// Save existing handlers on stack, employ a new set
	void pushHandlerSet(HandlerSet hs)
	{
		auto hset = new HandlerSet();
		getHandlers(hset);
		stack_.put(hset);
		setHandlers(hs);	
	}

	/// replace existing handlers with set saved on stack. Return popped set, if any
	void popHandlerSet()
	{
		if (stack_.length > 0)
		{
			auto hset = stack_.movePopBack();
			setHandlers(hset);
		}
	}
	/// Get current handlers as a set, leaving values unchanged. Uninitialised AA ambiguity may apply. 
	void getHandlers(HandlerSet hset)
	{
		hset.onText = onText_;
		hset.onPI = onPI_;
		hset.onCDATA = onCDATA_;
		hset.onComment = onComment_;
		hset.onStartTag = this.onStartTag;
		hset.onEndTag = this.onEndTag;
	}
	/// Apply set to overwrite existing handlers.
	void setHandlers(HandlerSet hset)
	{
		onText_ = hset.onText;
		onPI_ = hset.onPI;
		onCDATA_ = hset.onCDATA;
		onComment_ = hset.onComment;
		this.onStartTag = hset.onStartTag;
		this.onEndTag = hset.onEndTag;
	}
	void setupRaw()
	{
		parser_.setParameter(xmlCharFilter,Variant(false));
		parser_.setParameter(xmlAttributeNormalize,Variant(false));
		parser_.initSource(src_);
	}
	void setupNormalize()
	{
		parser_.setParameter(xmlAttributeNormalize,Variant(true));
		parser_.initSource(src_);
	}

	/** 
	Loop each parse event, until current Element endtag 

	*/
	void parse(intptr_t relativeAdjust = 0)
	{
		auto   startLevel = parser_.tagDepth() + relativeAdjust;

		while(true)
		{
			parser_.parse(tag);
			called_ = false;
			switch(tag.type)
			{
				case XmlResult.TAG_START:
					// a new tag.
					if (onStartTag !is null)
					{
						auto callMyStart = onStartTag.get(tag.name,null);
						if (callMyStart !is null)
						{
							callMyStart(this);
						}
					}
					auto parent = (elemStack_.length > 0) ? elemStack_.back() : null;
					if (parent !is null)
					{	// building already
						auto e = createElement(tag);
						parent.appendChild(e);
						parent = e;
					}
					else if ((onEndTag !is null) && (tag.data in onEndTag))
					{
						// start building here
						parent = createElement(tag);
					}	
					elemStack_.put(parent); // null or not
					break;
				case XmlResult.TAG_SINGLE:
					// no push required, but check after
					auto parent = (elemStack_.length > 0) ? elemStack_.back() : null;
					if (parent !is null)
					{	// building already
						auto e = createElement(tag);
						parent.appendChild(e);
					}
					if (onStartTag !is null)
					{
						auto callMyStart = onStartTag.get(tag.name,null);
						if (callMyStart !is null)
						{
							callMyStart(this);
						}
					}   
					// solo tag is an start + endTag with no content.
					if (onEndTag !is null)
					{
						auto p = onEndTag.get(tag.name,null);

						if (p !is null)
						{
							if (parent is null)
								// make isolated Element
								parent = createElement(tag);
							p(parent);
						}
					}
					break;
				case XmlResult.TAG_END:
					if (onEndTag !is null)
					{
						auto p = onEndTag.get(tag.name,null);
						auto e = (elemStack_.length > 0) ? elemStack_.movePopBack() : null;
						if ((p !is null) && ( e !is null))
							p(e);
					}
					debug(VERBOSE)
						writefln("Start level %s, tag = %s %s", startLevel, parser_.tagDepth, tag.name);
					auto depth = parser_.tagDepth();

					if ((startLevel == depth) || (depth == 0))
						return;

					break;
				case XmlResult.STR_TEXT:
					auto parent = (elemStack_.length > 0) ? elemStack_.back() : null;
					if (parent !is null)
						parent.addText(tag.data);
					if (onText_ !is null)
						onText_(tag);
					break;
				default:

					break;
			}
		}
	}
	void explode()
	{

	}
}

alias ElementParser DocumentParser;