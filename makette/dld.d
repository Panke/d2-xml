/**
    Reworking of makette. The programmer lost the way.
    @author Michael Rynn


	dlua make uses two sorts of information
*/

module dld;

import std.stdio;
import std.file;
import std.string;
import std.path;
import std.datetime;
import std.conv;
import std.stream;
import luad.state;
import luad.all;
import luad.c.lua;
import luad.stack;
import std.xmlp.xpath1;
import std.xml2;
import std.xmlp.linkdom;
import alt.strutil;
import alt.bomstring;

string gAppPath;
string gAppDirectory;

void main(char[][] args)
{
    strutil_unittest();
    string defaultFile = "build.xml";
    string defaultOut = "_build.lua";

    string[] targetlist;
    string[] varlist;

    bool noExecute = false;
    bool doList = false;
    bool generateBS = false;


    if (args.length > 1)
    {
        int aix = 1;
        while (aix < args.length)
        {
            char[] arg = args[aix];
            aix++;
            switch(arg)
            {
            case "--list":
            case "-l":
                doList = true;
                break;
            case "--file":
            case "-f":
                if (aix < args.length)
                {
                    defaultFile = args[aix].idup;
                    aix++;
                }
                break;
            case "--gen":
            case "-g":
                if (aix < args.length)
                {
                    defaultOut = args[aix].idup;
                }
                break;
            case "--set":
            case "-s":
                if (aix < args.length)
                {
                    // "varname = value"
                    varlist ~= args[aix].idup;
                    aix++;
                }
                break;
            case "--noexec":
            case "-n":
                noExecute = true;
                break;
            default:
                targetlist ~= arg.idup;
                break;
            }
        }
    }

    gAppPath = getApplicationPath();
    gAppDirectory = dirName(gAppPath);

    writeln("Running ", gAppPath);
    writeln("Input ", defaultFile);
    writeln("Working dir = ", getcwd());
    if (!exists(defaultFile))
    {
        writeln(defaultFile," not found!");
        showUsage();
        return;
    }
    if (!isFile(defaultFile))
    {
        writeln(defaultFile,"  is not a file!");
        showUsage();
        return;
    }

    string fileext = extension(defaultFile);
    if (fileext == ".xml")
    {
        writeln("processXml");
        processXml(defaultFile,defaultOut);
    }
    else if (fileext == ".lua")
    {
        writeln("processLua");
        processLua(defaultFile,defaultOut);
    }
    // get the location of this binary, so as to be able to read default configuration
    debug {getchar();}
}

void showUsage()
{
    writefln(r"dxd --file <build.xml> ] [--noexec] [--list] [target,...]*
             -f, --file : xml build file
             Default file is makette.xml in current directory.
             -n, --noexec : No execution, emit commands to stdout
             -l, --list : List targets to standard output
             -s, --set : define a variable eg -set build=release
             Default target is all.");
}


class LuaSource
{
    string[] lines;

    void put(string s)
    {
        lines ~= s;
    }

    void putTableList(string[] slist)
    {
        foreach(s ; slist)
        {
            this.put(format("'%s',",s));
        }
    }
    void outputFile(string fname)
    {
        auto tattoo = getBomBytes(BOM.UTF8);
        backupOldFile(fname);
        auto fout = new std.stream.File(fname, FileMode.OutNew);
        //fout.writeBlock(tattoo.ptr, tattoo.length);
        foreach(s ; lines)
        {
            fout.writeBlock(s.ptr, s.length);
            fout.write('\n');
        }
        fout.close();
    }
}

void addAttributeMap(NamedNodeMap amap, LuaSource ss)
{
    foreach(a ; amap)
    {
        string aname = a.getNodeName();
        string aval = a.getNodeValue();
        ss.put(format("%s='%s',",aname,aval));
    }
}

void addTool(Element e, LuaSource ss)
{
    string id = e.getAttribute("id");
    ss.put(format(`["%s"] = { id="%s",`,id,id));
    auto p = ChildElementRange(e);
    string val;
    while(!p.empty)
    {
        auto ch = p.front;
        p.popFront();
        string ename = ch.getNodeName();
        if (ename=="set")
        {
            id = ch.getAttribute("id");
            val = ch.getAttribute("value");
            if (val.length == 0)
            {
                val = ch.getTextContent();
            }
            ss.put(format("%s='%s',",id,val));
        }
        else if (ename=="list")
        {
            id = ch.getAttribute("id");
            val = ch.getTextContent();
            auto list=splitUnquoteList(val,false);
            ss.put(format(`["%s"]={`,id));
            foreach(item ; list)
            {
                ss.put(format(`'%s',`,item));
            }
            ss.put("},");
        }

    }
    ss.put("}, -- end addTool");
}
void addToolSet(Element e, LuaSource ss)
{
    string id = e.getAttribute("id");
    ss.put(format(`["%s"] = { id="%s", `,id,id));
    auto p = ChildElementRange(e);
    string val;
    while(!p.empty)
    {
        auto ch = p.front;
        p.popFront();
        addTool(ch,ss);
    }
    ss.put("}, -- end addToolSet");
}
/** target, attributes and source id list */
void addBuilds(Element e, LuaSource ss)
{
    string id = e.getAttribute("id");
    ss.put(format(`["%s"] = { id="%s", `,id,id));
    auto p = ChildElementRange(e);
    while(!p.empty)
    {
        auto ch = p.front;
        p.popFront();
        string ename = ch.getNodeName();
        if(ename == "flags")
        {
            ss.put(format("flags = '%s', ", ch.getTextContent()));
        }
    }
    ss.put("},");
}

/** target, attributes and source id list */
void addTargets(Element e, LuaSource ss)
{
    string id = e.getAttribute("id");
    ss.put(format(`["%s"] = { id="%s", `,id,id));
    addAttributeMap(e.getAttributes(),ss);
    auto p = ChildElementRange(e);
    string[] srclist;
    string[] deplist;
    while(!p.empty)
    {
        auto ch = p.front;
        p.popFront();
        string ename = ch.getNodeName();
        auto slist = splitUnquoteList(ch.getTextContent());
        if (ename == "output")
        {
            string result=ch.getTextContent();
            if (result.length > 0)
            {
                result = strip(result);
                ss.put(format("output='%s',",result));
            }

        }
        if (ename == "sources")
        {
            srclist ~= slist;
        }
        else if (ename == "depends")
        {
            deplist ~= slist;
        }
    }
    if (srclist.length > 0)
    {
        ss.put("sources = {");
        ss.putTableList(srclist);
        ss.put("},");
    }
    if (deplist.length > 0)
    {
        ss.put("depends = {");
        ss.putTableList(deplist);
        ss.put("},");
    }
    ss.put("},");
}

/** source, list of import, and directory files */
void addSources(Element e, LuaSource ss)
{
    string id = e.getAttribute("id");
    ss.put(format(`["%s"] = {`,id));

    auto p = ChildElementRange(e);

    while(!p.empty)
    {
        auto ch = p.front;
        p.popFront();
        string ename = ch.getNodeName();
        ss.put(format("{ type='%s',",ename));
        addAttributeMap(ch.getAttributes(),ss);
        if (ename == "dir")
        {
            // content list to be parsed
            string test = ch.getAttribute("ext");
            string[] filelist;
            if (test.length > 0)
            {
                string src = ch.getTextContent();
                filelist = splitUnquoteList(src);
            }
            else
            {
                test = ch.getAttribute("filter");
                if (test.length > 0)
                {
                    string dpath = ch.getAttribute("path");
                    auto dfiles = dirEntries(dpath, SpanMode.shallow, false);
                    foreach(DirEntry df; dfiles)
                    {
                        if (endsWith(df.name, test))
                        {
                            filelist ~= df.name;
                        }
                    }
                }
            }
            if (filelist.length > 0)
            {
                ss.put("list = {");
                ss.putTableList(filelist);
                ss.put("},");
            }
        }
        ss.put("},");
    }
    ss.put("},");
}


void processXml(string defaultFile, string defaultOut)
{
    Document mdoc;
    try
    {
        mdoc = loadFile(defaultFile);
    }
    catch(Exception ex)
    {
        writeln("Load error ", defaultFile, " ", ex.toString());
        debug {getchar();}
        return;
    }
    catch (Throwable t)
    {
        writeln("unknown exception");
        debug {getchar();}
        return;
    }
    // what platform is this?
    processDocument(defaultOut, mdoc);
    processLua(defaultOut, "_luaOut.txt");

}
/** Use xml to generate lua code */
void processDocument(string luafile, Document mdoc)
{
    LuaSource srcLua = new LuaSource();

    // create sources table

    srcLua.put("sources = {");
    auto root = mdoc.getDocumentElement();
    auto nlist = xpathNodeList(root,"sources/source");
    foreach(n ; nlist.items)
    {
        addSources(cast(Element)n, srcLua);
    }
    srcLua.put("}");
    // targets
    nlist = xpathNodeList(root,"targets/target");
    srcLua.put("targets = {");

    foreach(n ; nlist.items)
    {
        addTargets(cast(Element)n, srcLua);
    }
    srcLua.put("}");
    // builds
    nlist = xpathNodeList(root,"builds/build");
    srcLua.put("builds = {");
    foreach(n ; nlist.items)
    {
        addBuilds(cast(Element)n, srcLua);
    }
    srcLua.put("}");
    // toolsets
    nlist = xpathNodeList(root,"toolsets/toolset");
    srcLua.put("toolsets = {");
    foreach(n ; nlist.items)
    {
        addToolSet(cast(Element)n, srcLua);
    }
    srcLua.put("}");
    // get real lua source
    // process includes --
    nlist = xpathNodeList(root,"processing-instruction('Lua')");
    foreach(n ; nlist.items)
    {
        ProcessingInstruction pro = cast(ProcessingInstruction) n;
        string code = pro.getData();
        srcLua.put(code);
    }
    srcLua.outputFile(luafile);


}
static const(char)[] luaFn_getBaseName(const(char)[] fromPath)
{
    return baseName(stripExtension(fromPath));
}
/** try everything, delete destination file if exists */
static bool luaFn_MoveFile(const(char)[] fromPath, const(char)[] toPath)
{
    try
    {
        auto dirPath = dirName(toPath);
        if (!exists(dirPath))
        {
            mkdirRecurse(dirPath);
        }
        rename(fromPath, toPath);
        return true;
    }
    catch(FileException fex)
    {
        return false;
    }
}
static bool luaFn_mkdirRecurse(const(char)[] dirPath)
{
    try
    {
        if (!exists(dirPath))
        {
            mkdirRecurse(dirPath);
        }
        return true;
    }
    catch(FileException fex)
    {
        return false;
    }
}


void processLua(string defaultFile, string defaultOut)
{
    auto LS = new LuaState();
    LS.openLibs();
    auto L = LS.state;
    pushValue(L, dirSeparator);
    lua_setglobal(L, "dirSeparator");

    pushValue(L, gAppDirectory);
    lua_setglobal(L, "gAppDirectory");

    pushValue(L, dirSeparator);
    lua_setglobal(L, "dirSeparator");


    pushValue(L, &luaFn_MoveFile);
    lua_setglobal(L, "moveFile");


    pushValue(L, &luaFn_mkdirRecurse);
    lua_setglobal(L, "mkdirRecurse");

    pushValue(L, &luaFn_getBaseName);
    lua_setglobal(L, "getBaseName");

    LS.doFile(defaultFile);

}
