module main;

/**
	Generates a formatted dstring[], code range pairing table,
	filtering the xml character codes, according to the attribute values passed
	Example arguments.

--input ucd.all.flat.xml --output numberConnects.d gc=Mn gc=Mc gc=Nd gc=Pc

	The input file for this is ucd.all.flat.xml, found in http://www.unicode.org/Public/6.1.0/ucdxml/ucd.all.flat.zip

	Authors: Michael Rynn
	Date: Mar 2012
*/
import std.stdio, std.xml2, std.string, std.stream, std.conv;
import std.xmlp.charinput;
import alt.buffer;
import std.datetime;
import core.memory;
import std.xmlp.tagvisitor;

version(GC_STATS)
{
	import alt.gcstats;
}

void showUsage()
{
    writefln(r"unicodedb --input <unicodedb.xml> [--output file]  [attr=xx]"
			"output unicode characters as a single pair range table, if they match any of the attribute values (no quotes)");
}


string inputFile;
string outputFile;
string[][string] gEnv;

void process()
{

	auto fstream = new BufferedFile(inputFile);
	auto sf = new XmlStreamFiller(fstream);
	auto p = new XmlParser(sf);
	auto v = new TagVisitor(p);
	TagHandlerSet	tags;

	struct PairRange {
		dchar first_;
		dchar last_;
	}

	Buffer!PairRange	set;

	PairRange next = PairRange(0,0);
	bool	  hasPair = false;	// has a pair in progress

	void addCodePoint(string cp)
	{
		immutable validChar = to!uint(cp,16);
		if (next.first_ == 0) // very first time
		{
			next = PairRange(validChar,validChar);
			hasPair = true; // always true now
		}
		else if (next.last_ == (validChar-1))
		{
			next.last_ = validChar;
		}
		else {
			// must have skipped. Save range and start new range
			set.put(next);
			next = PairRange(validChar,validChar);
		}
	}

	// This element should be always empty, with just attributes?
	tags["char",XmlResult.TAG_EMPTY] = (XmlReturn ret) {

		foreach(n,v ; gEnv)
		{
			auto value = ret.attr[n];

			foreach(s ; v)
			{
				if (value==s)
				{
					addCodePoint(ret.attr["cp"]);
					return;
				}
			}
		}
	};
	v.handlerSet = tags;
	writeln("Waiting for parse of ",inputFile);
	StopWatch sw;
	sw.start();
	v.parseDocument(0);
	sw.stop();
	double ms = sw.peek.msecs()/ 1000.0;


	if (hasPair)
		set.put(next); // complete last.

	auto pairs = set.toConstArray();
	BufferedFile	outFile;

	if (outputFile.length > 0)
	{
		outFile = new BufferedFile(outputFile,FileMode.OutNew);
	}

	Buffer!char	outbuf;
	auto pct = 0;
	foreach(r ; pairs)
	{
		pct++;
		auto s = format("0x%x, 0x%x, ",r.first_, r.last_);
		outbuf.put(s);
		if (pct==3)
		{
			pct=0;
			outbuf.put('\n');
			auto temp = outbuf.toConstArray();
			write(temp);
			if (outFile)
				outFile.writeString(temp);

			outbuf.length = 0;
		}
	}
	if (outbuf.length > 0)
	{
		outbuf.put('\n');
		auto temp = outbuf.toConstArray();
		write(temp);
		if (outFile)
			outFile.writeString(temp);

	}
	if (outFile)
		outFile.close();
	writeln("Parse Time (secs) : ", ms);

}

void main(string[] args)
{
	if (args.length <= 1)
	{
		showUsage();
		return;
	}
	uintptr_t aix = 1;
	while(aix < args.length)
	{	
		auto arg = args[aix];
		aix++;
		switch(arg)
		{
			case "--input":
			case "-i":
				if (aix < args.length)
				{
					inputFile = args[aix];
					aix++;
				}
				break;
			case "--output":
			case "-o":
				if (aix < args.length)
				{
					outputFile = args[aix];
					aix++;
				}
				break;
			default:
				auto vix = arg.indexOf("=");
				if (vix >= 0)
				{
					if (vix==0)
					{
						writeln("Error command line: need name=value ", arg);
						showUsage();
						return;
					}
					auto atrName = arg[0..vix];
					auto atrValue = arg[vix+1..$];

					string[] list = gEnv.get(atrName,null);
					// no check for repeated values
					list ~= atrValue;
					gEnv[atrName] = list;
				}
				break;
		}

	}
	process();

	version(GC_STATS)
	{
		GC.collect();
		GCStatsSum.AllStats();
	}
	writeln("Enter to exit");
	getchar();
}
