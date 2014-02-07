/**
Custom build d-script, at the moment just for dmd2

*/

module build;

import std.stdio, std.c.stdlib;
import std.path, std.conv, std.string;
import alt.zstring;

string[]  altSource = [ "zstring"];

string[] stdSource= [ "xml1",   "xml2"];

version(linux)
{
	enum libsuffix = "a";
}
version(Windows)
{
	enum libsuffix = "lib";
}
string[] xmlpSource = [
	"arraydom",
	"arraydombuild",
	"builder",
	"domparse",
	"dtdtype" ,
	"entitydata",
	"error",
	"slicedoc" ,
	"sliceparse" ,
	"xmlparse" ,
	"xmlchar" , "domvisitor" ,
	"parseitem" , "subparse",
	"doctype" , "linkdom" ,
	"tagvisitor" , "validate" ,
	"entity" , "feeder" ,"dtdvalidate" ,
	"elemvalidate" ,
	"charinput","inputencode" ,"coreprint"];

/// Specify set of files to be compiled, with common extension and path, with list of file names
/// If files are omitted, then all file names in the root path with given extension will be read in.
class  CommonSource {
	string	extension_;
	string 	path_;  // root path
	string[]     files_;   // full subpaths to files
	bool	 doScan_;

	this(string path, string extension, string[] files)
	{
		extension_ = extension;
		path_= path;
		files_ = files;
		doScan_ = (files_ is null);
	}

	string[] fileset()
	{
		string[] result;

		if (!doScan_)
		{
			foreach(f ; files_)
			{
				auto path = buildPath( path_, f );
				path = setExtension( path,  extension_);
				result ~= path;
			}
		}
		return result;
	}

}



class Builder {
	string toolCmd_;
	string targetPath_;

	CommonSource[] sources_;
	int	result_;

	this(string tool, CommonSource[] sources, string target)
	{
		toolCmd_ = tool;
		sources_ = sources;
		targetPath_ = target;
	}

	int resultCode() @property @safe nothrow
	{
		return result_;
	}

	void build(string buildFlags)
	{
		Array!char	cmd;

		cmd.put(toolCmd_);
		cmd.put(targetPath_);
		cmd.put(" ");
		cmd.put(buildFlags);

		foreach ( src ; sources_)
		{
			auto list = src.fileset();
			foreach(s ; list)
			{
				cmd.put(" ");
				cmd.put(s);
			}
		}
		cmd.nullTerminate();
		result_ = system( cmd.ptr );
		writeln( format("%s = %s", targetPath_ , result_));

	}


}


void main(string[] args)
{
	CommonSource srclist[] ;

	srclist ~= new CommonSource("alt", "d", altSource);
	srclist ~= new CommonSource("std/xmlp", "d", xmlpSource);
	srclist ~= new CommonSource("std", "d", stdSource);

	auto buildflags = "-debug -w -property";

	auto lib = new Builder("dmd -lib -of", srclist, "xmlp");
	lib.build(buildflags);

	if (lib.resultCode)
		return;

	srclist.length = 0;
	srclist ~= new CommonSource("test","d", ["sxml"]);
	srclist ~= new CommonSource("",libsuffix, ["xmlp"]);

	auto app = new Builder("dmd -of", srclist, "sxml");
	app.build(buildflags);

	if (app.resultCode)
		return;

	srclist.length = 0;
	srclist ~= new CommonSource("test","d", ["books"]);
	srclist ~= new CommonSource("",libsuffix, ["xmlp"]);

	app = new Builder("dmd -of", srclist, "bookstest");
	app.build(buildflags);
	if (app.resultCode)
		return;

	srclist.length = 0;
	srclist ~= new CommonSource("test","d", ["Conformance"]);
	srclist ~= new CommonSource("std/xmlp","d", ["jisx0208"]);
	srclist ~= new CommonSource("",libsuffix, ["xmlp"]);

	app = new Builder("dmd -of", srclist, "conformance");
	app.build(buildflags);
	if (app.resultCode)
		return;


}

