import std.stdio, std.file, std.string, std.utf,std.path,  std.conv, std.stream;
import std.c.stdlib, std.c.string;

import std.xmlp.xpath1, std.xml2, std.xmlp.linkdom, std.xmlp.domparse;
import alt.strutil, alt.bomstring;

import makette.source;

string gAppPath;
string gAppDirectory;
string gWorkDirectory;
string gBuildXML;

void showGlobalPaths()
{
    writeln("Running ", gAppPath);
    writeln("Working dir = ", gWorkDirectory);
}

void processXml(ref CommandOptions cop)
{
    Document mdoc;
    try
    {
        mdoc = loadFile(cop.inputFile);
    }
    catch(Exception ex)
    {
        writeln("Load error ", cop.inputFile, " ", ex.toString());
        debug {getchar();}
        return;
    }
    catch (Throwable t)
    {
        writeln("unknown exception");
        debug {getchar();}
        return;
    }
    processDocument(cop, mdoc);

}

void processDocument(ref CommandOptions cop, Document mdoc )
{
    auto jf = new JobFile();
    jf.set(mdoc);
    jf.run(cop);
}
void main(string[] args)
{
    gWorkDirectory = getcwd();
    gAppPath = getApplicationPath();
    gAppDirectory = dirName(gAppPath);

    CommandOptions cop;

    cop.set(args);

    if (cop.cwd.length > 0 && cop.cwd != gWorkDirectory)
    {
        gWorkDirectory = cop.cwd;
    }
    if (cop.inputFile.length == 0)
        cop.inputFile = "build.xml";

    cop.show();
    showGlobalPaths();
    processXml(cop);

}
