module sxml;

import std.stdio;
import std.datetime;
import std.string;
import std.conv;
import core.memory;
import std.variant;
import std.xml2;
import std.xmlp.coreprint;
import ad = std.xmlp.arraydom;
import adb = std.xmlp.arraydombuild;
import std.xmlp.tagvisitor,std.xmlp.builder;
import xml1 = std.xml1;


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

import std.xml2;
import std.path;


void OutputBook(ref XmlPrinter p, ref Book book)
{
	auto indented = XmlPrinter(p);
	auto nextIndent = XmlPrinter(indented);
		
	AttributeMap map;
	map["id"] = book.id;
	
	indented.putStartTag("book", map, false);
	
	nextIndent.putTextElement("author", book.author);
	nextIndent.putTextElement("title",  book.title);
	nextIndent.putTextElement("genre",  book.genre);
	nextIndent.putTextElement("price",  book.price);
	nextIndent.putTextElement("publish_date",book.pubDate);
	nextIndent.putTextElement("description", book.description);
	indented.putEndTag("book");
	
}


void OutputBooksXml(Book[] books)
{
	void outputString(const(char)[] s)
	{
		writeln(s);
	}	
	
	auto options = XmlPrintOptions(&outputString);
	
	auto printer = XmlPrinter (options);
	

	// low level xml output
	
	AttributeMap map;
	
	map.appendMode = true;
	map["version"] = "1.0";
	map["encoding"] = "UTF-8";
	printXmlDeclaration(map, &outputString);
	printer.putStartTag("catalog");

	foreach(book;books)
	{
		OutputBook(printer, book);
	}
	printer.putEndTag("catalog");

}

// TagVisitor example
void books2collect(string s)
{
    auto parser = new XmlParser(s);
	parser.setParameter(xmlAttributeNormalize,Variant(true));

    auto visitor = new TagVisitor(parser);
	TagHandlerSet catalog;
	TagHandlerSet bookset;

	scope(exit) {
		visitor.explode();
		visitor = null;
	}

    // Take it apart
    Book[]  books;
	Book	book;

	bookset["author", XmlResult.STR_TEXT] = (XmlReturn ret) {
		book.author = ret.data;
	};
	bookset["title", XmlResult.STR_TEXT] = (XmlReturn ret) {
		book.title = ret.data;
	};
	bookset["genre", XmlResult.STR_TEXT] = (XmlReturn ret) {
		book.genre = ret.data;
	};
	bookset["price",XmlResult.STR_TEXT] = (XmlReturn ret)
	{
		book.price = ret.data;
	};
	bookset["publish_date",XmlResult.STR_TEXT] = (XmlReturn ret)
	{
		book.pubDate = ret.data;
	};
	bookset["description",XmlResult.STR_TEXT] = (XmlReturn ret)
	{
		book.description = ret.data;
	};

	catalog["book",XmlResult.TAG_START] = (XmlReturn ret) {
		book = Book.init;
		book.id = ret.attr["id"];
		visitor.pushHandlerSet(bookset);
	};

	catalog["book",XmlResult.TAG_END] = (XmlReturn ret) {
		books ~= book;
		visitor.popHandlerSet();
	};

	/// single delegate assignment for tag
	visitor.handlerSet = catalog;
	visitor.parseDocument(0);

	OutputBooksXml(books);
	writeln("Done with std.xmlp.tagvisitor  : Enter to continue");
	getchar();
}



void runCollector(string s)
{
	auto doc = new ad.Document();

	auto collector = new adb.ArrayDomBuilder(doc);
	auto p = new XmlParser(s);
	auto xv = new TagVisitor(p);
	auto dtag = new DefaultTagBlock();
	xv.defaults = dtag;
	xv.defaults.setBuilder(collector);

	scope(exit)
	{
		collector.clear();
		dtag.clear();
		xv.explode();
		xv = null;
		doc.explode();
		doc = null;
	}
	xv.parseDocument(0);

	
	void outline(const(char)[] s)
	{
		write(s);
	}
	doc.printOut(&outline,0);
	writeln();
	writeln("Done with std.xmlp.tagvisitor and std.xmlp.arraydombuild  : Enter to continue");
	getchar();

}

void std_xml1(string s)
{
	with(xml1)
	{

		// Check for well-formedness
		// check(s); // sorry, no more separate check

		// Take it apart
		Book[] books;
		Book book;

		auto xml = new DocumentParser(s);

		auto	bookset = xml.new HandlerSet();

		scope(exit)
		{
			xml.explode();
		}
		xml.onStartTag["book"] = (ElementParser xml)
		{

			book.id = xml.tag.attr.get( "id",null);	
			xml.pushHandlerSet(bookset);
			xml.parse(-1);
			xml.popHandlerSet();

			books ~= book;
		};

		bookset.onEndTag["author"]       = (in Element e) { book.author      = e.text(); };
		bookset.onEndTag["title"]        = (in Element e) { book.title       = e.text(); };
		bookset.onEndTag["genre"]        = (in Element e) { book.genre       = e.text(); };
		bookset.onEndTag["price"]        = (in Element e) { book.price       = e.text(); };
		bookset.onEndTag["publish-date"] = (in Element e) { book.pubDate     = e.text(); };
		bookset.onEndTag["description"]  = (in Element e) { book.description = e.text(); };

		xml.parse();

		// Put it back together again;
		auto doc = new Document(new Element("catalog"));
		scope(exit)
			doc.explode();

		foreach(bk;books)
		{
			auto element = new Element("book");
			element.attr["id"] = bk.id;

			element ~= new Element("author",      bk.author);
			element ~= new Element("title",       bk.title);
			element ~= new Element("genre",       bk.genre);
			element ~= new Element("price",       bk.price);
			element ~= new Element("publish-date",bk.pubDate);
			element ~= new Element("description", bk.description);

			doc ~= element;
		}

		// Pretty-print it
		writefln(join(doc.pretty(3),"\n"));
	}
	writeln("Done with std.xml1  : Enter to continue");
	getchar();
}

int main(string[] argv)
{
    string inputFile;

    auto act = argv.length;

	uint i = 0;
	while (i < act)
	{
		string arg = argv[i++];
		if (arg == "input" && i < act)
			inputFile = argv[i++];
	}

	if (inputFile.length == 0)
	{
		writeln(argv[0]," input <path to books.xml>");
		return 0;
	}
	if (!std.file.exists(inputFile))
	{
		string wkdir = absolutePath(".");
		writeln("File not found: ", inputFile, " from ", wkdir);
		return 0;
	}
	string s = cast(string)std.file.read(inputFile);
	
	std_xml1(s);
	books2collect(s);
	runCollector(s);
	
	GC.collect();
	GC.collect();

	version(GC_STATS)
	{
		// trust, but verify.
		ulong created, deleted, diff;


		TagVisitor.gcStats(created,deleted);
		diff = created - deleted;
		writeln("TagVisitor: created ", created," deleted ", deleted, " diff ", diff, " ", cast(double)diff*100/cast(double)created," %");

		Builder.gcStats(created,deleted);
		diff = created - deleted;
		writeln("Builder: created ", created," deleted ", deleted, " diff ", diff, " ", cast(double)diff*100/cast(double)created," %");

		ad.Item.gcStats(created,deleted);
		diff = created - deleted;
		writeln("arraydom.Item: created ", created," deleted ", deleted, " diff ", diff, " ", cast(double)diff*100/cast(double)created," %");
		
		xml1.Item.gcStats(created,deleted);
		diff = created - deleted;
		writeln("std.xml1.Item: created ", created," deleted ", deleted, " diff ", diff, " ", cast(double)diff*100/cast(double)created," %");
	}
	writeln("Done. <Enter to exit>");

	getchar();	
	return 0;
}

