module main;

import std.stdio, std.xml2, std.datetime, std.xmlp.linkdom;
import core.memory, alt.buffer, alt.gcstats;
import ard = std.xmlp.arraydom;
import ardb = std.xmlp.arraydombuild;
import std.stream;
import stdxml = std.xml1;
import std.xmlp.tagvisitor;

//import stdxml = std.xml; // only if modified as for GC_STATS

// How good is your garbage collection service. Is it fast? Does it work?
// Can it cope with entropy? How about a large XML document into linked DOM structure?
// help the GC by blowing up intransigant referencing data structures

void fullCollectNode()
{
	writeln("full GC");
	auto sw = StopWatch();
	sw.start();
	GC.collect();
	sw.stop();
	writeln("Full collection in ", sw.peek().msecs, " [ms]");

}

void nodeGCStats()
{
	version (GC_STATS) 
	{
		ulong created, deleted;
		Node.gcStatsSum.stats(created, deleted);
		writeln("Node: created ",created, " deleted ", deleted, " diff ", created - deleted, " %", ((created-deleted)*100.0)/created);
	}
}

void fullCollectItem()
{
	writeln("full GC");
	auto sw = StopWatch();
	sw.start();
	GC.collect();
	sw.stop();

	writeln("Full collection in ", sw.peek().msecs, " [ms]");

}

void ardGCStats()
{
	version (GC_STATS) 
	{
		ulong created, deleted;
		ard.Item.gcStatsSum.stats(created, deleted);
		writeln("Item: created ",created, " deleted ", deleted, " diff ", created - deleted, " %", ((created-deleted)*100.0)/created);
	}
}


void fullCollectStdXml()
{
	writeln("full GC");
	auto sw = StopWatch();
	sw.start();
	GC.collect();
	sw.stop();

	writeln("Full collection in ", sw.peek().msecs, " [ms]");

}

void stdGCStats()
{
	version (GC_STATS) 
	{
		ulong created, deleted;
		stdxml.Item.gcStatsSum.stats(created, deleted);
		writeln("Item: created ",created, " deleted ", deleted, " diff ", created - deleted, " %", ((created-deleted)*100.0)/created);
		stdxml.ElementParser.gcStats(created, deleted);
		writeln("ElementParser: created ",created, " deleted ", deleted, " diff ", created - deleted, " %", ((created-deleted)*100.0)/created);
	}
}

// This is faster because of the single file load
void loadFileStdXml(string fname)
{
    with (stdxml)
    {
		auto sw = StopWatch();
		sw.start();
		 
		string s = cast(string)std.file.read(fname);

		Document doc = std.xmlp.arraydombuild.loadString(s);
		
		sw.stop();

		writeln(fname, " std.xml1 loaded in ", sw.peek().msecs, " [ms]");
		doc.explode();
		//delete doc; // no backpointers;
    }
}

version=FILE_LOAD;

void loadFileArrayDom(string fname)
{
    with (ard)
    {
		auto sw = StopWatch();
		sw.start();

		version(FILE_LOAD)
		{
			string s = cast(string)std.file.read(fname);
			auto p = new XmlStringParser(s);
			//auto sf = new SliceFill!char(s);
			//auto p = new XmlParser(sf);

		}
		else {
			auto fstream = new BufferedFile(fname);
			auto sf = new XmlStreamFiller(fstream);
			auto p = new XmlParser(sf);
			
		}
		auto tv = new TagVisitor(p);
		Document doc = new Document();

        auto bc = new ardb.ArrayDomBuilder(doc);
		auto dtag = new DefaultTagBlock();
		dtag.setBuilder(bc);
        tv.defaults = dtag;

        tv.parseDocument(0);
		sw.stop();

		writeln(fname, " to arraydom loaded in ", sw.peek().msecs, " [ms]");
		doc.explode();
		tv.explode();
    }
}

void loadFileTest(string fname)
{
	writeln("start.. ", fname);
	auto sw = StopWatch();
	sw.start();
	Document d = loadFile(fname);
	sw.stop();
	writeln(fname, " to linkdom loaded in ", sw.peek().msecs, " [ms]");

	d.explode();
}


void showBlockBits(const(void)* p)
{
	auto bits = GC.getAttr(p);
	Buffer!char	bitset;

	if ((bits & GC.BlkAttr.NO_SCAN) != 0)
		bitset.put("no_scan,");
	if ((bits & GC.BlkAttr.FINALIZE) != 0)
		bitset.put("finalize,");
	if ((bits & GC.BlkAttr.NO_MOVE) != 0)
		bitset.put("no_move,");
	if ((bits & GC.BlkAttr.APPENDABLE) != 0)
		bitset.put("appendable,");
	if ((bits & GC.BlkAttr.NO_INTERIOR) != 0)
		bitset.put("no_interior,");
	writefln("Pointer %x bits %x  %s",p, bits, bitset.toArray);
}

void printUsage()
{
	writeln("arguments:  inputfile1 [inputfile2]* ");
}
void main(string[] argv)
{
	if (argv.length <= 1)
	{
		printUsage();
		return;
	}
	enum repeats = 4;
	writeln("Repeats = ",repeats);



	getchar();
	foreach(arg ; argv[1..$])
	{
		for(auto i = 0; i < repeats; i++)
		{
			writeln("test ", i+1);
			loadFileTest(arg);
			fullCollectNode();
		}
		fullCollectNode();
		nodeGCStats();
		writeln(" linkdom.Node results. Enter to continue");
		getchar();
		

		for(auto i = 0; i < repeats; i++)
		{
			writeln("test ", i+1);
			loadFileArrayDom(arg);
			fullCollectItem();
		}
		
		fullCollectItem();
		ardGCStats();
		writeln(" arraydom.Item results. Enter to continue");
		getchar();

		for(auto i = 0; i < repeats; i++)
		{
			writeln("test ", i+1);
			loadFileStdXml(arg);
			fullCollectStdXml();
		}
	
		fullCollectStdXml();
		stdGCStats();
		writeln(" std.xml1 Results. Enter to continue");

		GCStatsSum.AllStats();
		getchar();
	}

	writeln("All done -- Enter to exit");
	getchar();
	writeln("Shutting down now . . .");

}
