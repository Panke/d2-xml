/**
Test for std.xpath syntax and transform using XSLT

Command line:  
	xslt xml <path-to-xml> xsl <path-to-xsl> out <output file>

Output not implemented yet. Only to console.

Authors: Michael Rynn

*/

module xslt;

import std.stdio;
import std.xpath.syntax;
import std.xpath.transform;
import std.xml2;

int main(string[] argv)
{
	writeln("Hello D-World!");
	uint act = argv.length;

	uint i = 0;
	while (i < act)
	{
		string arg = argv[i++];
		if (arg == "xml" && i < act)
			inputXml = argv[i++];
		else if (arg == "xsl" && i < act)
			inputXsl = argv[i++];
		else if (arg == "out" && i < act)
			outputXml = argv[i++];
	}

	if (inputXml.length == 0 || inputXsl.length == 0)
	{
		writeln("sxml.exe  xml <path> xsl <path> [out <path>]");
		return 0;
	}
   
	void putConsole(const(char)[] s)
	{
		write(s);
	}
   
	Document xmldoc = DocumentParser.Load(inputXml);
	Document xsldoc = DocumentParser.Load(inputXsl);
   
	XSLTransform xt = new XSLTransform();
	xt.transform(xmldoc, xsldoc, &putConsole);
	
	string dinp;
	stdin.readln(dinp);
  
	return 0;
}
