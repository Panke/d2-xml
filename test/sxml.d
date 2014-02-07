module sxml;

import std.xml1;

import core.memory;
import std.xmlp.coreprint;
import std.stdio;
import std.datetime;
import std.string;
import std.conv;
import core.memory;
import std.variant;
import std.random;
import std.file;
import std.xml2;
import std.xmlp.tagvisitor;
import ard = std.xmlp.arraydom;
import lnk = std.xmlp.linkdom;
import ardb = std.xmlp.arraydombuild;
import std.xmlp.builder;
import alt.buffer;

version(GC_STATS)
{
	import alt.gcstats;
}

/** Peak everything */
string ImpactExample =
`<?xml version='1.0' encoding='utf-8'?>
<impact>
	<axis id='co2'>
		<label>CO2 emissions</label>
		<unit>ktonne</unit>
	</axis>
	<axis id='population'>
		<label>Population</label>
		<unit>thousand people</unit>
	</axis>
	<axis id='gdp'>
		<label>GDP</label>
		<unit>USdollar</unit>
	</axis>
	<axis id='intensity'>
		<label>Carbon Intensity</label>
		<unit>kCO2/$05p</unit>
	</axis>
	<axis id='year'>
		<label>Year</label>
		<unit>year</unit>
	</axis>
	<graph y='co2' x='year'>
		<plot id='USA' >
			<d2 x='2005' y='5,991'>This could be crappy</d2>

			<d2 x='2006' y='5,913' />
			<d2 x='2007' y='6,018' />
			<d2 x='2008' y='5,833' />
			<d2 x='2009' y='5,424' />
			<d2 x='2010' y='5638' />
			<d2 x='2011' y='5587' />
			<d2 x='2012' y='5720' />
		</plot>
	</graph>
	<graph y='population' x='year'>
		<plot id='USA'>
			<d2 x='2005' y='296,820' />
			<d2 x='2006' y='299,564' />
			<d2 x='2007' y='302,285' />	
			<d2 x='2008' y='304,989' />	
			<d2 x='2009' y='307,687' />	
			<d2 x='2010' y='310,384' />	
			<d2 x='2011' y='313,085' />	
			<d2 x='2012' y='315,791' />
		</plot>
	</graph>
	<graph y='gdp' x='year'>
		<plot id='USA'>
			<d2 x='2010' y='14,586,736,313,339' />
		</plot>		
	</graph>
	<graph y='intensity' x='year'>
		<plot id='USA'>
			<d2 x='2009' y='0.41' />
		</plot>		
	</graph>
</impact>`;

string Example4 =
    `<?xml version="1.0" encoding="utf-8"?> <A>
                                  <!-- Comment 1 -->
                                  <B> <C id="1" value="&quot;test&quot;" >
                                          <D> Xml &quot;Text&quot; in D &apos;&amp;&lt;&gt; </D> </C> <C id="2" />
                                                  <!-- Comment 2 -->
                                                  <C id="3"></C>
                                                          </B>
                                                          <![CDATA[ This is <Another sort of text ]]>
                                                          <?Lua   --[[ Dense hard to follow script
                                                                  --]]
                                                          ?>
                                                          </A>`;


struct Book
{
    string id;
    string author;
    string title;
    string genre;
    string price;
    string pubDate;
    string description;
}

class Series {
	string title;
	Buffer!double values;
	this()
	{
	}

	this(string name)
	{
		title = name;
	}

}
enum AxisLine {
	horizontal, vertical
}
class Axis {
	string id_;
	string label_;
	string unit_;
	double minValue_;
	double maxValue_;
	double minLabel_;
	double maxLabel_;
	AxisLine	orient_;

}


class Graph {
	Axis	xaxis_;
	Axis	yaxis_;
	Plot	plots_[];

	class Plot {
		string  title_;
		Series	xdata_;
		Series	ydata_;
	}
}

void outputPlot(Graph.Plot p, StringPutDg dg)
{
	dg(p.title_);

	auto xval = p.xdata_.values.toConstArray();
	auto yval = p.ydata_.values.toConstArray();

	foreach(i ; 0..xval.length)
	{
		dg(format("%s %s", xval[i], yval[i]));
	}
}

void outputGraph(Graph g, StringPutDg dg)
{
	dg(format( "%s / %s",g.yaxis_.label_ ,  g.xaxis_.label_, ));

	foreach(p ; g.plots_)
	{
		outputPlot(p,dg);
	}
}

IXMLParser getParser(string src)
{
	auto parser = new XmlStringParser(src);
	parser.setParameter(xmlAttributeNormalize,Variant(true));
	return parser;
}

double toReal(string data)
{
	string temp = std.array.replace(data,",","_");
	return to!double(temp);
}
void timeSerious()
{
	// impact document contains
	// Axis - with labels and values,
	// Graph - contains x, y axis names, and plot - a series of points.

	Graph[]	graphs;
	Axis[string]  axes;

    auto parser = getParser(ImpactExample);
    auto visitor = new TagVisitor(parser);

	TagHandlerSet	axisHandlers;
	TagHandlerSet	plotHandlers;

	visitor
	scope(exit)
	{
		mainTag.explode();
		axisTag.explode();
	}
	
	/// 
	mainTag["axis", XmlResult.TAG_START] = (XmlReturn ret)
	{
		auto ax = new Axis();	
		ax.id_ = ret.attr["id"];
		axes[ax.id_] = ax;

		axisTag["label",XmlResult.STR_TEXT] = (XmlReturn ret)
		{
			ax.label_ = ret.scratch;
		};

		axisTag["unit",XmlResult.STR_TEXT] = (XmlReturn ret)
		{
			ax.unit_ = ret.scratch;
		};

		axisTag.parseDocument(-1);
	};

	mainTag["graph", XmlResult.TAG_START] = (XmlReturn ret)
	{
		Axis xaxis = axes[ret.attr["x"]];
		Axis yaxis = axes[ret.attr["y"]];

		Graph g = new Graph();
		graphs ~= g;

		g.xaxis_ = xaxis;
		g.yaxis_ = yaxis;
		auto seriesTag = new TagVisitor(parser);
		scope(exit)
			seriesTag.explode();

		mainTag["plot",XmlResult.TAG_START] = (XmlReturn ret) {
			auto plot = g.new Plot();
			plot.title_ = ret.attr["id"];
			plot.xdata_ = new Series();
			plot.ydata_ = new Series();			
			g.plots_ ~= plot;
				
			auto pointCollect = (XmlReturn ret){
				plot.xdata_.values ~=  toReal(ret.attr["x"]);
				plot.ydata_.values ~=  toReal(ret.attr["y"]);
			};

			seriesTag["d2",XmlResult.TAG_SINGLE] = pointCollect;
			seriesTag["d2",XmlResult.TAG_START] = pointCollect;

			seriesTag.parseDocument(-1);
		};
		// ensure current content fully processed here, otherwise scope(exit) will be bad.
		mainTag.parseDocument(-1); 
		
	};
	
	mainTag.parseDocument(0);
	
	void draw(const(char)[] s)
	{
		writeln(s);
	}
	foreach(g ; graphs)
		outputGraph(g, &draw);

}

void testNewStuff()
{
    auto parser = new XmlStringParser(Example4);
    auto tv = new TagVisitor(parser);
	scope(exit)
		tv.explode();

    /// The callbacks will all have different keys, so only need one set, for this kind of document
    /// But still need to set the parser stack callback object for each level, usually in a TAG_START callback.
    ///
    string[] allText;

    /// const prebuilt keys for non tagged nodes
    auto textDg = (XmlReturn ret)
    {
        allText ~= ret.scratch;
    };

    auto piDg = (XmlReturn ret)
    {
		auto rec = ret.attr.atIndex(0);
		allText ~= text(rec.id,": ",rec.value);
    };

	auto allTags = new DefaultTagBlock();

    allTags[XmlResult.STR_TEXT] = textDg;
    allTags[XmlResult.STR_CDATA] = textDg;
    allTags[XmlResult.STR_PI] = piDg;
    allTags[XmlResult.STR_COMMENT] = textDg;


    allTags[XmlResult.XML_DEC] = (XmlReturn ret)
    {
		foreach(n,v;ret.attr)
			writefln("%s='%s'",n, v);
    };

	DefaultTagBlock[]	saveDefaults; // nested stack for saving default handler set
	auto bce = new ardb.ArrayDomBuilder();

	tv["C",XmlResult.TAG_SINGLE] = (XmlReturn ret)
	{
		if (ret.attr.length > 0)
			foreach(n, v ; ret.attr)
                writefln("%s = '%s'", n, v);
	};

    tv["C",XmlResult.TAG_START] = (XmlReturn ret)
    {
		saveDefaults ~= tv.defaults;
		tv.defaults = new DefaultTagBlock(tv.defaults);
		tv.defaults.setBuilder(bce);
		bce.init(ret);
	};
		
	tv["C",XmlResult.TAG_END] = (XmlReturn ret)
	{
		auto slen = saveDefaults.length;
		slen--;
		tv.defaults = saveDefaults[slen];
		saveDefaults.length =  slen;
		auto elem = bce.root;
		if (elem.hasAttributes())
			foreach(n, v ; elem.getAttributes())
                writefln("%s = '%s'", n, v);	
		writeln("Content: ", elem.text);
	};


	tv["B",XmlResult.TAG_START] = (XmlReturn ret)
	{
		writeln("B Start");
	};

	auto A_tags = new TagBlock("A");
	tv.put(A_tags);

    A_tags[XmlResult.TAG_START] = (XmlReturn ret)
    {
        writeln("Document A Start");
    };

	A_tags[XmlResult.TAG_END] = (XmlReturn ret)
    {
        writeln("Document A End");
    };
		
	

	tv.defaults = allTags;
    tv.parseDocument(0);
    writefln("%s",allText);
	tv.explode();

}

// another way to do it.
void books2collect(string s)
{
    auto parser = new XmlParser(s);
    auto visitor = new TagVisitor(parser);

    // get a set of callbacks at the current state.

    // Check for well-formedness. Note that this is superfluous as it does same as parse.
    //sdom.check(s);

    // Take it apart
    Book[]  books;
	Book	book;

    auto bookcb = visitor.create("book");

	bookcb[XmlResult.TAG_START] = (XmlReturn ret) {
		book.id = ret.attr["id"];
	};
	bookcb[XmlResult.TAG_END] = (XmlReturn ret) {
		books ~= book;
	};
	
	/// single delegate assignment for tag
	visitor["author", XmlResult.STR_TEXT] = (XmlReturn ret) {
		book.author = ret.scratch;
	};
	visitor["title", XmlResult.STR_TEXT] = (XmlReturn ret) {
		book.title = ret.scratch;
	};
	visitor["genre", XmlResult.STR_TEXT] = (XmlReturn ret) {
		book.genre = ret.scratch;
	};
	visitor["price",XmlResult.STR_TEXT] = (XmlReturn ret)
	{
		book.price = ret.scratch;
	};
	visitor["publish_date",XmlResult.STR_TEXT] = (XmlReturn ret)
	{
		book.pubDate = ret.scratch;
	};
	visitor["description",XmlResult.STR_TEXT] = (XmlReturn ret)
	{
		book.description = ret.scratch;
	};

	visitor.parseDocument(0);

    // Put it back together again, to see the information was extracted
    auto doc = new domDocument(new domElement("catalog"));
    foreach(bk; books)
    {
        auto element = new domElement("book");
        element.setAttribute("id",book.id);

        element ~= new domElement("author",      bk.author);
        element ~= new domElement("title",       bk.title);
        element ~= new domElement("genre",       bk.genre);
        element ~= new domElement("price",       bk.price);
        element ~= new domElement("publish_date",bk.pubDate);
        element ~= new domElement("description", bk.description);

        doc ~= element;
    }
    doc.setXmlVersion("1.0");
    // Pretty-print it
    writefln(std.string.join(doc.pretty(3),"\n"));

	doc.explode();
	visitor.explode();
}


void xml1_books(string s)
{
	with(std.xml1)
	{
		Book[] books;
		Book book;

		auto xml = new DocumentParser(s);
		auto bookHandlers = xml.new HandlerSet();

		bookHandlers.onEndTag["author"]       = (in Element e) { book.author      = e.text(); };
		bookHandlers.onEndTag["title"]        = (in Element e) { book.title       = e.text(); };
		bookHandlers.onEndTag["genre"]        = (in Element e) { book.genre       = e.text(); };
		bookHandlers.onEndTag["price"]        = (in Element e) { book.price       = e.text(); };
		bookHandlers.onEndTag["publish_date"] = (in Element e) { book.pubDate     = e.text(); };
		bookHandlers.onEndTag["description"]  = (in Element e) { book.description = e.text(); };

		
		xml.onStartTag["book"] = (ElementParser xml)
		{
			book.id = xml.tag.attr.get("id",null);
			xml.pushHandlerSet(bookHandlers);
		// -1 because want to exit after end tag of book, 0 would exit end of author tag.

			xml.parse(-1); 
			xml.popHandlerSet();

			books ~= book;
		};
		xml.parse();
		xml.explode();

		// Put it back together again;
		auto doc = new Document(new Element("catalog"));
		foreach(bk;books)
		{
			auto element = new Element("book");

			//element.tag.attr["id"] = book.id;
			element.attr["id"] = bk.id;
			element ~= new Element("author",      bk.author);
			element ~= new Element("title",       bk.title);
			element ~= new Element("genre",       bk.genre);
			element ~= new Element("price",       bk.price);
			element ~= new Element("publish_date",bk.pubDate);
			element ~= new Element("description", bk.description);

			doc ~= element;
		}

		// Pretty-print it
		writefln(join(doc.pretty(3),"\n"));
		doc.explode(); // Bits of this hang around after GC.collect otherwise
	}

}
void arraydom_speed(string s)
{
	/**
    with (ard)
    {
		Document doc = std.xmlp.arraydombuild.loadString(s);			
		doc.explode();
    }
*/
    auto parser = new XmlStringParser(s);
    auto visitor = new TagVisitor(parser);
	// Take it apart
    Book[]  books;
	Book	book;

    auto bookcb = visitor.create("book");

	bookcb[XmlResult.TAG_START] = (XmlReturn ret) {
		book.id = ret.attr["id"];
	};
	bookcb[XmlResult.TAG_END] = (XmlReturn ret) {
		books ~= book;
	};

	/// single delegate assignment for tag
	visitor["author", XmlResult.STR_TEXT] = (XmlReturn ret) {
		book.author = ret.scratch;
	};
	visitor["title", XmlResult.STR_TEXT] = (XmlReturn ret) {
		book.title = ret.scratch;
	};
	visitor["genre", XmlResult.STR_TEXT] = (XmlReturn ret) {
		book.genre = ret.scratch;
	};
	visitor["price",XmlResult.STR_TEXT] = (XmlReturn ret)
	{
		book.price = ret.scratch;
	};
	visitor["publish_date",XmlResult.STR_TEXT] = (XmlReturn ret)
	{
		book.pubDate = ret.scratch;
	};
	visitor["description",XmlResult.STR_TEXT] = (XmlReturn ret)
	{
		book.description = ret.scratch;
	};

	visitor.parseDocument(0);

}


void test_input(string text)
{
    auto buffer = new SliceFill!char(text);
    auto pin = new ParseSource(buffer, 1.0);
    pin.pumpStart();
    pin.filterAlwaysOff();
    dchar   test;
    uint ct = 0;
    while(!pin.empty)
    {
        pin.popFront();
        ct++;
    }
    // writeln("Count = ", ct);

}


/** slice parser without building a dom

*/

void slice_throughput(string text)
{
    string filtered = decodeXmlString(text);
    auto parser = new XmlStringParser(text);
    dchar   test;
    uint ct = 0;
    XmlReturn ret = new XmlReturn();
    while(parser.parse(ret))
        ct++;
    // writeln("Count = ", ct);

}

/**
Compare aspects of performance of fast slicing parser, XMLStringParser,  and the validating parser CoreParser

The difference in speed between the validating parser and the slice parser,
depends a lot on a if a source character filter is applied,
 as prescribed by the XML standard. For instance, the standard says
 carriage return characters are filtered out.
 So /r/n becomes a /n. It must have been Unix people who wrote that standard.
 There are other perculiar character rules.

 XMLStringParser does not have an input character filter, and this will not be normally be noticed for
 ASCII XML content. Controlled input XML file sources, can be "normalized" so they do not a filter.

If the string block to be parsed, is used as read from a file, the XMLStringParser
is very fast.  The CoreParser translates all characters, from all source types,
 through a filter to produce its final dchar feed.  The last stage character filter can be switched permanently off,
 by setParameter("char-filter", false), and this will result in speed up of about 10%.
 During a validating parse, this filter is switched on or off,  according parse context.
 A pre-filter for the XmlStringParser cannot be selective. It depends on slicing the source string,
 and the dchar feed is used only position.


 When a character filter step to produce a filtered string block, is put in front of the
 XmlStringParser,
    ---
        string filtered = decodeXmlString(xml);
    ---
 the total time increases to be much the same as the CoreParser.
 If the front feeds character filtering on CoreParser is turned off as well,
 CoreParser performs faster than the XmlStringParser. CoreParser allocates memory for
 strings off a big memory block, to compensate for not being able to slice them off the source text.

 */

version=CharFilterSwitch;

alias std.xmlp.error.ParseError ParseError;

void test_parse_sdom(string xml)
{
    with(lnk)
    {


        auto doc = new Document(null,""); // not the element tag name, just the id
		scope(exit)
			doc.explode();
        auto sm = new storeErrorMsg();

        auto config = doc.getDomConfig();
        config.setParameter("error-handler",Variant(cast(DOMErrorHandler) sm));
        config.setParameter("namespaces",Variant(false));
        try
        {
            //version(CharFilterSwitch) xml = decodeXmlString(xml);
            auto parser = new XmlStringParser(xml);
            parser.validate = true;
            auto builder = new DocumentBuilder(parser,doc);
			scope(exit)
				builder.explode();
            builder.buildContent();
			
        }

        catch(ParseError pe)
        {
            writeln(pe.toString());
            writeln(sm.remember);
        }
		
    }
}

/** Core parser, just throughput, no dom build */
void test_throughput(string text)
{

    auto df = new SliceFill!(char)(text);
    auto p = new XmlParser(df);
    version(CharFilterSwitch)
    p.setParameter("char-filter",Variant(false));

    dchar   test;
    uint ct = 0;
    auto ret = new XmlReturn();
    while(p.parse(ret))
        ct++;
    // writeln("Count = ", ct);

}

alias lnk.DOMErrorHandler DOMErrorHandler;
alias lnk.DOMError DOMError;



class storeErrorMsg : DOMErrorHandler
{
    string remember;

    override bool handleError(DOMError error)
    {
        remember = error.getMessage();
        return false; // stop processing
    }
}

void test_validate(string inputFile)
{
    with(lnk)
    {


        auto doc = new Document(null,""); // not the element tag name, just the id
		scope(exit)
			doc.explode();

        auto config = doc.getDomConfig();
        auto sm = new storeErrorMsg();
        config.setParameter("error-handler",Variant(cast(DOMErrorHandler) sm));
        try
        {
            auto parser = parseXmlFileValidate(inputFile);
            DocumentBuilder builder = new DocumentBuilder(parser,doc);
 			scope(exit)
				builder.explode();
			builder.buildContent();
        }
        catch(ParseError pe)
        {
            writeln(pe.toString());
            writeln(sm.remember);
        }
    }
}


/** This calls the DTD validating parser */
void test_parse_pdom(string xml)
{
    with(lnk)
    {
        auto doc = new Document(null,""); // not the element tag name, just the id
		scope(exit)
			doc.explode();
        auto sm = new storeErrorMsg();

        auto config = doc.getDomConfig();
        config.setParameter("error-handler",Variant(cast(DOMErrorHandler) sm));
        config.setParameter("namespaces",Variant(false));

		
        try
        {
            auto parser = parseXmlStringValidate(xml);
            version(CharFilterSwitch) parser.setParameter("char-filter",Variant(false));

            auto builder = new DocumentBuilder(parser,doc);
			scope(exit)
				builder.explode();
            builder.buildContent();
			
        }
        catch(ParseError pe)
        {
            writeln(pe.toString());
            writeln(sm.remember);
        }
		
    }

}

alias std.xmlp.linkdom.Element	domElement;
alias std.xmlp.linkdom.Document	domDocument;

void corePrint(string s)
{
    void output(const(char)[] p)
    {
        write(p);
    }
    auto doc = new lnk.Document();
    auto dp = new DocumentBuilder(new XmlParser(new SliceFill!(char)(s)), doc);
	scope(exit)
	{
		dp.explode();
		doc.explode();
	}
    dp.buildContent();
	

    doc.printOut(&output,2);

}

void validateTest(string s)
{
    domDocument d =  loadString(s,false,false);
	d.explode();
}

void coreTest(string s)
{
    //GC.disable();
    auto doc = new lnk.Document();
    auto dp = new DocumentBuilder(new XmlParser(new SliceFill!(char)(s)),doc);

	scope(exit)
	{
		dp.explode();
		doc.explode();
	}
    dp.buildContent();


    //GC.enable();
}

void linkDomPrint(string xml)
{


    void output(const(char)[] p)
    {
        write(p);
    }
    auto doc = new lnk.Document();
    auto builder = new DocumentBuilder(new XmlStringParser(xml),doc);
	
	scope(exit)
	{
		builder.explode();
		doc.explode();
	}
    builder.buildContent();
    writeln("String parser = slice parser");
    lnk.printDocument(doc, &output, 2);

}

void linkDomTest(string xml)
{
    auto doc = loadString(xml);
	doc.explode();

}

void stdXmlTest(string s)
{
    auto doc = std.xmlp.arraydombuild.loadString(s);
	doc.explode();
}


double timedSeconds(ref StopWatch sw)
{
    auto duration = sw.peek();

    return duration.to!("seconds",double)();
}

void fullCollect()
{
	GC.collect();
	ulong created, deleted;

	writeln("Enter to continue");
	getchar();
}

void runTests(string inputFile, uintptr_t runs)
{
	string s = cast(string)std.file.read(inputFile);

	stdXmlTest(s);
	ticketTests();
	testNewStuff();
	fullCollect();
	books2collect(s);
	writeln("That was XmlParse and TagVisitor, books array, then manual build linkdom.Document");
	fullCollect();
	test_validate(inputFile);
	fullCollect();
	testTicket12(inputFile);
	xml1_books(s);
	writeln("That was using std.xml1");
	getchar();
	linkDomPrint(s);
	writeln("That was XmlStringParser, DocumentBuilder, print linkdom.Document");
	fullCollect();
	test_input(s);
	test_throughput(s);
	slice_throughput(s);
	test_parse_pdom(s);
	fullCollect();
	test_parse_sdom(s);
	//corePrint(s);
	enum uint numTests = 6;
	double[numTests] sum;
	double[numTests]	sample;

	sum[] = 0.0;

	StopWatch sw;
	double ms2 = 0;
	writeln("\n 15 repeats., rotate sequence.");

	const uint repeat_ct = 15;
	auto testIX = new uintptr_t[numTests];
	foreach(ix, ref kn ; testIX)
        kn = ix;
	uintptr_t i;

	for (uintptr_t rpt  = 1; rpt <= repeat_ct; rpt++)
	{
		randomShuffle(testIX);
		for(uintptr_t kt = 0; kt < numTests; kt++)
		{
			auto startix = testIX[kt];

			switch(startix)
			{
                case 0:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        test_input(s);
                    }
                    sw.stop();
                    break;
                case 1:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        test_throughput(s);
                    }
                    sw.stop();
                    break;
                case 2:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        slice_throughput(s);
                        //test_throughput(s);
                    }
                    sw.stop();
                    break;
                case 3:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        test_parse_pdom(s);
                        //test_throughput(s);
                    }
                    sw.stop();
                    break;

                case 5:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        stdXmlTest(s);
                    }
                    sw.stop();
                    break;
                case 4:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        arraydom_speed(s);
                    }
                    sw.stop();
                    break;
                default:
                    break;
			}
			sample[startix] = timedSeconds(sw);
			sw.reset();
		}
		foreach(v ; sample)
            writef(" %6.3f", v);

		writeln(" ---");
		sum[] += sample[];
	}

	sum[] /= repeat_ct;

	double control = sum[$-1];
	writeln("averages: ", runs, " runs");
	writeln("input, parse, sliceparse, DocumentBuilder, TagVisitor, control(std.xml1)");
	foreach(v ; sum)
        writef(" %7.4f", v);
	writeln(" ---");

	sum[] *= (100.0/control);
	write("t/control %% = ");
	foreach(v ; sum)
        writef(" %3.0f", v);
	writeln(" ---");
}

int main(string[] argv)
{
    string inputFile;
    uintptr_t	  runs = 100;


	timeSerious();

    uintptr_t act = argv.length;

    uintptr_t i = 0;
    while (i < act)
    {
        string arg = argv[i++];
        if (arg == "input" && i < act)
            inputFile = argv[i++];
        else if (arg == "runs" && i < act)
            runs = to!(uint)(argv[i++]);
    }

    if (inputFile.length == 0)
    {
        writeln("sxml.exe  input <path to books.xml>	runs <repetitions (default==100)>");
        return 0;
    }
    if (inputFile.length > 0)
    {
        if (!exists(inputFile))
        {
            writeln("File not found : ", inputFile, "from ", getcwd());
            getchar();
            return 0;
        }
 
		runTests(inputFile,runs);

    }
	fullCollect();
	version(GC_STATS)
	{
		GCStatsSum.AllStats();
		writeln("If some objects are still alive, try calling  methods.explode");
		writeln("Enter to exit");
		getchar();
	}
    return 0;
}



bool ticketTest(string src)
{
    try
    {
        test_parse_sdom(src);
    }
    catch(Exception e)
    {
        writeln(e.toString());
        return false;
    }
    return true;
}

void emptyDocElement()
{
    string doc;

    doc =`<?xml version="1.0" encoding="utf-8"?><main test='"what&apos;s up doc?"'/>`;

    auto tv = new TagVisitor(new XmlParser(new SliceFill!(char)(doc)));
	
	scope(exit)
	{
		tv.explode();
	}
    tv["main", XmlResult.TAG_START] = (XmlReturn ret)
    {
        // main item
        writeln("Got main test=",ret.attr["test"]);
    };

    tv.parseDocument(0);
	

}
void testTicket12(string inputFile)
{
	// Load file access violation?
	auto doc = loadFile(inputFile,false,false);
	doc.explode();
}
void testTicket4()
{
    string src = Example4;
    assert(ticketTest(src));
}
void testTicket8()
{

    bool testTicket(string src)
    {
        try
        {
            auto tv = new TagVisitor(new XmlStringParser(src));
			
			scope(exit)
			{
				tv.explode();
			}

			char[]	btext;

			tv["B", XmlResult.TAG_START] = (XmlReturn ret)
			{
				btext = null;
			};

			tv["B", XmlResult.STR_TEXT] = (XmlReturn ret)
			{
				btext ~= ret.scratch;
			};

            tv["B",XmlResult.TAG_END] = (XmlReturn ret)
            {
				assert (btext == "\nhello\n\n", "Collect text only");
            };
            tv.parseDocument(0);


        }
        catch(Exception e)
        {
            writeln("Ticket 8 example error ", e.toString());
            return false;
        }
        return true;
    }

    string src = q"[<?xml version='1.0' encoding='utf-8'?>
<A>
<B>
hello
<!-- Stop me -->
</B>
</A>]";

    testTicket(src);
}


void testTicket7()
{
    bool ticketTest(string src)
    {
        try
        {
            auto xml = new TagVisitor(new XmlStringParser(src));
            xml.parseDocument(0);
			scope(exit)
				xml.explode();
		}
        catch(Exception e)
        {
            writeln("Ticket 7 example error ", e.toString());
            return false;
        }
        return true;

    }
    string src = q"[<?xml version="1.0" encoding="utf-8"?>
<Workbook>
<ExcelWorkbook><WindowHeight>11580</WindowHeight>
</ExcelWorkbook>
</Workbook>]";

    assert(ticketTest(src));
	


}
void ticketTests()
{
    emptyDocElement();
    testTicket4();
    testTicket7();
    testTicket8();
}


void testDomAssembly()
{
    auto doc = new lnk.Document(null,"TestDoc"); // not the element tag name, just the id

    string myns = "http:\\anyold.namespace.will.do";

    auto elem = doc.createElementNS(myns,"m:doc");
    elem.setAttribute("xmlns:m",myns);

    doc.appendChild(elem);
	scope(exit)
		doc.explode();

    void output(const(char)[] p)
    {
        writeln(p);
    }

    doc.printOut(&output,2);

    writeln("Dom construction. <Enter to exit>");
    string dinp;
    stdin.readln(dinp);


}
