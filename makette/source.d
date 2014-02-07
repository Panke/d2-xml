module makette.source;

import std.xmlp.subparse, std.xml2, std.xmlp.xpath1, std.xmlp.linkdom, std.xmlp.error;
import std.path, std.file, std.string, std.stdio, std.variant, std.conv, std.array, std.regex;
import std.datetime, std.ascii;
import std.c.stdlib, std.c.stdio, std.c.string;
import alt.strutil, alt.zstring, alt.filereader, alt.bomstring;
import insp = alt.simpleparse;

alias Action function(JNode jf, Element e) ActionRegFn;

shared ActionRegFn[string] gActions;

void registerAction(string name, ActionRegFn fn)
{
    gActions[name] = fn;
}
void showUsage()
{
    writefln(r"makit --file <build.xml> ] [--noexec] [--list] [target=xx] [build=xx] [toolset=xx]
             -f, --file : xml build file
             Default file is build.xml in current directory.
             -n, --noexec : No execution, emit commands to stdout
             -l, --list : List targets to standard output
             -c, --cwd : Change current working directory
             Default target is all.");
}
class NoModuleException : Exception {
    this()
    {
        super("No module name first");
    }
}
class EOFException : Exception {
    this()
    {
        super("EOF");
    }
}

class BuildException : Exception {
    this(string msg)
    {
        super(msg);
    }
}

class FileSpec {
    string    filePath;
    SysTime   lastMod;
    bool      fileExists; // maybe use lastMod == SysTime.init ?

    this(string path)
    {
        filePath = path;
    }
    void refreshMod()
    {
        fileExists = exists(filePath);
        if (fileExists)
            lastMod = timeLastModified(filePath);
    }
}

class BComponent {
    string    id;
    FileSpec  fspec;
    string    cmd; // the command.

    BComponent[] dependents;
    /** init from a package (folder) container, see if
    file path belongs */
    this(string modName, string filePath)
    {
        id = modName;
        fspec = new FileSpec(filePath);
        fspec.refreshMod();
    }

    @property string path()
    {
        return fspec.filePath;
    }
}

struct CommandOptions {
    string inputFile;
    string outputFile;
    string cwd;

    string[string]    gValues;

    bool   doList;
    bool   noExec;

    void set(string[] args)
    {
        if (args.length > 1)
        {
            int aix = 1;
            while (aix < args.length)
            {
                auto arg = args[aix];
                aix++;
                switch(arg)
                {
                case "--list":
                case "-l":
                    doList = true;
                    break;
                case "--cwd":
                case "-c":
                    if (aix < args.length)
                    {
                        cwd = args[aix];
                        aix++;
                        if (!isAbsolute(cwd))
                            cwd = buildNormalizedPath(cwd);
                        chdir(cwd);
                    }
                    break;
                case "--file":
                case "-f":
                    if (aix < args.length)
                    {
                        inputFile = args[aix];
                        aix++;
                    }
                    break;
                case "--gen":
                case "-g":
                    if (aix < args.length)
                    {
                        outputFile = args[aix];
                    }
                    break;
                case "--noexec":
                case "-n":
                    noExec = true;
                    break;
                case "--help":
                case "-h":
                    showUsage();
                    break;
                default:
                    auto vix = arg.indexOf("=");
                    if (vix >= 0)
                    {
                        if (vix==0)
                        {
                            writeln("Error command line: need name=value ", arg);
                            return;
                        }
                        gValues[arg[0..vix]] = arg[vix+1..$];
                    }
                    break;
                }
            }
        }

    }

    void show()
    {
        writeln("input file: ", inputFile);
    }
}

class JNode {
    string          id_;
    string[string]  values_;

    string varsub(string original)
    {
        Array!char  buf;
        auto src = original;
        auto ix = src.indexOf("$(");
        while (ix >= 0)
        {
            if (ix > 0)
                buf ~= src[0..ix];
            src = src[ix+2..$];
            auto jix = src.indexOf(")");
            if (jix >= 0)
            {
                auto svar = src[0..jix];
                auto replace = svar in values_;
                if (replace !is null)
                    buf ~= *replace;
                else
                    buf ~= text("$(", svar, ")");
                src = src[jix+1..$];
            }
            else {
                throw new BuildException(format("Error parse of %s", original));
            }
            ix = src.indexOf("$(");
        }
        if (src.length > 0)
            buf ~= src;
        return buf.unique();
    }
    void set(string id, string value)
    {
        values_[id] = value;
    }
    void opIndexAssign(string value, string id)
    {
        values_[id] = value;
    }
    string opIndex(string id)
    {
        auto value = id in values_;
        if (value !is null)
        {
            return *value;
        }
        else {
            return "";
        }
    }
    string get(string vname)
    {
        auto value = vname in values_;
        if (value !is null)
        {
            return *value;
        }
        else {
            return "";
        }
    }
}

class Action : JNode {
    abstract void run(JobFile jf);
    abstract void init(JNode jn, Element e);
}



string[string] toAttributeMap(NamedNodeMap amap)
{
    string[string] result;

    foreach(a ; amap)
    {
        string aname = a.getNodeName();
        string aval = a.getNodeValue();
        result[aname] = aval;
    }
    return result;
}


string getModuleName(string depfile)
{
    Array!char  fname = depfile;
    fname.nullTerminate();
    enum buflen = 80;

    FILE* f = fopen(fname.ptr, "r" );

    if (f is null)
        return "";
    scope(exit)
        fclose(f);
    Array!char  buf;
    buf.length = buflen;

    auto ptr = fgets(buf.ptr, buflen, f);
    buf.length = strlen(ptr);
    auto moduleName = buf.unique();
    auto mrange = match(moduleName,regex(r"([\w\.]*)\S*"));
    if (!mrange.empty())
    {
        auto result = mrange.front();
        return result.hit;
    }

    return "";
}
string getBaseName(string fromPath)
{
    return baseName(stripExtension(fromPath));
}

void removeFile(string fpath)
{
    if (exists(fpath) && isFile(fpath))
    {
         remove(fpath);
    }
}

void moveFile(string fromPath, string toPath)
{
    auto dirPath = dirName(toPath);
    if (!exists(dirPath))
    {
        mkdirRecurse(dirPath);
    }
    rename(fromPath, toPath);
    writeln("Move ", fromPath, " to ", toPath);
}


class  Tool : JNode {
    string[][string]  lists_;

    override string get(string vname)
    {
        auto slist = vname in lists_;
        if (slist !is null)
        {
            return std.string.join(*slist);
        }
        return super.get(vname);
    }
    void set(Element e)
    {
        id_ = e.getAttribute("id");
        debug {
            writeln("Tool ", id_);
        }
        values_ =  toAttributeMap(e.getAttributes());

        auto p = ChildElementRange(e);
        string val;
        string id;

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
                values_[id] = val;
            }
            else if (ename=="list")
            {
                id = ch.getAttribute("id");
                val = ch.getTextContent();
                auto list=splitUnquoteList(val,false);
                lists_[id] = list;
            }

        }

    }
}

class ToolSet : JNode {
    Tool[string]    tools_;

    void set(Element e)
    {
        id_ = e.getAttribute("id");
        debug {
            writeln("ToolSet ", id_);
        }
        auto p = ChildElementRange(e);

        while(!p.empty)
        {
            auto ch = p.front;
            p.popFront();
            auto tool = new Tool();
            tool.set(ch);
            tools_[tool.id_] = tool;
        }
    }

}

class Source : JNode {
    DirSource[] dirs_;
    string[] importPaths_;

    class DirSource : JNode{
        string          type_;
        string[]        files_;   // full subpaths to files
        bool	        doScan_;

        this()
        {

        }
    	this(string path, string extension, string[] files)
        {
            set("ext",extension);
            set( "path", path);
            files_ = files;
            doScan_ = (files_ is null);
        }
        string[] fileset()
        {
            string[] result;

            if (!doScan_)
            {
                auto extension = get("ext");
                foreach(f ; files_)
                {
                    auto path = buildPath( get("path"), f );
                    path = setExtension( path,  extension);
                    result ~= path;
                }
            }
            return result;
        }
    }

    this()
    {

    }
    string[] fileset()
    {
        string[] result;
        foreach(ds ; dirs_)
            result ~= ds.fileset();
        return result;
    }

    void set(Element e)
    {
        id_ = e.getAttribute("id");
        auto p = ChildElementRange(e);
        debug {
            writeln("source ", id_);
        }
        while(!p.empty)
        {
            auto ch = p.front;
            p.popFront();
            auto tag = ch.getNodeName();
            if (tag == "import")
            {
                auto path = ch.getAttribute("path");
                if (path.length > 0)
                    importPaths_ ~= path;
            }
            else if (tag == "dir")
            {
                DirSource ds = new DirSource();
                dirs_ ~= ds;

                ds.values_ = toAttributeMap(ch.getAttributes());
                auto ext = ds.get("ext");
                if (ext.length > 0)
                {
                    ds.doScan_ = false;
                    // content list to be parsed
                    string src = ch.getTextContent();
                    if (src.length > 0)
                        ds.files_ = splitUnquoteList(src);
                }
                else {
                      ds.doScan_ = true;
                }
            }
        }
    }
}

class Build : JNode {
    string  flags_;

    void set(Element e)
    {
        id_ = e.getAttribute("id");
        debug {
            writeln("build ", id_);
        }
        auto p = ChildElementRange(e);
        while(!p.empty)
        {
            auto ch = p.front;
            p.popFront();
            string ename = ch.getNodeName();
            if(ename == "flags")
            {
                flags_ = ch.getTextContent();
                super.set("flags", flags_);
            }
        }
    }
}

class Target : JNode {
    string[][string]  lists_;
    string   output_;
    Action[] actions_;

    this()
    {

    }

    void set(Element e){
        id_ = e.getAttribute("id");
        output_ = id_;
        debug {
            writeln("target ", id_);
        }
        values_ = toAttributeMap(e.getAttributes());

        auto p = ChildElementRange(e);

        string result;
        while(!p.empty)
        {
            auto ch = p.front;
            p.popFront();
            string ename = ch.getNodeName();
            auto slist = splitUnquoteList(ch.getTextContent());
            if (ename == "output")
            {
                result = ch.getTextContent();
                if (result.length > 0)
                {
                    output_ = strip(result);
                }
            }
            else if (ename == "sources")
            {
                lists_["sources"] = slist;
            }
            else if (ename == "depends")
            {
                lists_["depends"] = slist;
            }
            else if (ename == "libs")
            {
                lists_["libs"] = slist;
            }
            else if (ename == "lib-paths")
            {
                lists_["lib-paths"] = slist;
            }
            else if (ename == "run")
            {
                auto rp = ChildElementRange(ch);
                while (!rp.empty)
                {
                    auto actionE = rp.front;
                    rp.popFront();
                    string actionName = actionE.getNodeName();
                    auto makeFn = gActions[actionName];
                    auto obj = makeFn(this,actionE);
                    actions_ ~= obj;
                }
            }
        }
    }
}
/// Organize build.xml
class JobFile : JNode{

    Source[string]  sources_;
    Target[string]  targets_;
    Build[string]   builds_;
    ToolSet[string] toolsets_;
    string[]        dirStack_;
    string          currentDir_;
    ErrorStack      errors_;

    BComponent[string]  bcSource;
    BComponent[string]  bcObject;

    this()
    {
        errors_ = new ErrorStack();
    }
    void pushDir(string dir)
    {
        dirStack_ ~= currentDir_;
        currentDir_ = dir;
    }
    void addBuild(Element e)
    {
        auto b = new Build();
        b.set(e);
        builds_[b.id_] = b;
    }
    void addToolSet(Element e)
    {
        auto ts = new ToolSet();
        ts.set(e);
        toolsets_[ts.id_] = ts;
    }

    void addTarget(Element e)
    {
        auto tg = new Target();
        tg.set(e);
        writeln("Set target ", tg.id_);
        targets_[tg.id_] = tg;
    }

    /** source, list of import, and directory files */
    void addSources(Element e)
    {
        auto src = new Source();
        src.set(e);
        sources_[src.id_] = src;
    }
    void set(Document mdoc)
    {
        auto root = mdoc.getDocumentElement();
        auto nlist = xpathNodeList(root,"sources/source");
        foreach(n ; nlist.items)
        {
            addSources(cast(Element)n);
        }

        // targets
        nlist = xpathNodeList(root,"targets/target");

        foreach(n ; nlist.items)
        {
            addTarget(cast(Element)n);
        }
    // builds
        nlist = xpathNodeList(root,"builds/build");
        foreach(n ; nlist.items)
        {
            addBuild(cast(Element)n);
        }
        nlist = xpathNodeList(root,"toolsets/toolset");

        foreach(n ; nlist.items)
        {
            addToolSet(cast(Element)n);
        }
    // defaults
        nlist = xpathNodeList(root,"defaults/set");
        foreach(n ; nlist.items)
        {
            Element e = cast(Element)n;
            string name = e.getAttribute("id");
            string value = e.getAttribute("value");
            values_[name] = value;
        }

    }

    Target getTarget(string target)
    {
        if (target.length > 0)
        {
              writeln("Target ", target);
              if (targets_.length > 0)
                return targets_.get(target,null);
              else
                writeln("No available targets ");
        }
        else
            errors_.pushMsg("No target specified");
        return null;
    }


    /** get target, toolset, cwd, build */

    void run(ref CommandOptions cop)
    {
        foreach(n,v ; cop.gValues)
        {
            writeln("Set value ", n, " = ", v);
            values_[n] = v;
        }
        ToolSet ts;
        Target  tg;
        Build   bd;


        auto target = get("target");
        auto toolset = get("toolset");
        auto build = get("build");
        auto cwd = get("cwd");

         writeln("got values ");
        if (cwd.length > 0)
        {
            pushDir(cwd);
        }

        tg = getTarget(target);

        if (toolset.length > 0)
        {
            writeln("Toolset ", toolset);
            ts = toolsets_.get(toolset,null);
        }
        else
            errors_.pushMsg("No toolset specified");

        if (build.length > 0)
        {
            writeln("Build ", build);
            bd = builds_.get(build,null);
        }
        else
            errors_.pushMsg("No build specified");

        if (errors_.errorStatus)
            throw new BuildException(errors_.toString());
        if (tg is null)
            throw new BuildException(format("Target %s not found",target));
        if (ts is null)
            throw new BuildException(format("Toolset %s not found",toolset));
        if (bd is null)
            throw new BuildException(format("Build %s not found",build));


        runTarget(tg,ts,bd);
    }

    void collectSources(Target tg, BuildSubTarget sub)
    {
        bool[string] importPaths;
        auto sources = tg.lists_.get("sources",null);
        if (sources is null)
            throw new BuildException("No source list");
        writeln("sources len = ", sources.length);
        foreach(s ; sources)
        {
            auto src = sources_[s];

            foreach(ip ; src.importPaths_)
                importPaths[ip] = true;

            foreach(sdir ; src.dirs_)
            {
                if (sdir.doScan_)
                {
                    auto filter = sdir.get("filter");
                    auto dpath = sdir.get("path");
                    dpath = this.varsub(dpath);
                    auto modpack = sdir.get("package");
                    auto pack = sub.new Package();
                    pack.id = modpack;

                    if (filter.length > 0)
                    {   // read from directory

                        auto dit = dirEntries(dpath,SpanMode.shallow, false);
                        while (!dit.empty())
                        {
                            auto entry = dit.front();
                            auto sfile = entry.name;
                            if (filter == extension(sfile))
                                pack.filelist ~= sfile;
                            //writeln("added ",sfile);
                            dit.popFront();
                        }
                    }
                    sub.packages ~= pack;
                }
                else {
                    //sub.filelist ~= pack.files_;
                }
            }
        }
        foreach(i,v ; importPaths)
            sub.imports ~= i;

    }

    void makeLib(Target tg, ToolSet ts, Build bd, BuildSubTarget bsub)
    {
        auto lib = ts.tools_["lib"];

        auto libdir = varsub(tg["dest"]);

        auto libfile = text(buildPath(libdir,tg.id_),lib["ext"]);
        bsub["output"] =  libfile;

        writeln("Target ", libfile);
        if (exists(libfile))
        {
            writeln("remove ",libfile);
            removeFile(libfile);
        }
        else if (!exists(libdir))
        {
            writeln("make dir ", libdir);
            mkdirRecurse(libdir);
        }
        auto inputs =  std.array.join(bsub.objlist," ");
        bsub["inputs"] = inputs;
        Array!char cmd = bsub.varsub(lib["syntax"]);
        cmd.nullTerminate();
        auto result = system(cmd.ptr);
        writeln("result = ",result);
    }


    /** distinguish system from dependent files */
    alias ParseInputRange!char	ParseInput;
    alias void delegate(string modname, string filepath, string depmod, string deppath) AddDependFn;

    /** Just get the module name. Parse comments and space until get
        module  x.y.z; */
    bool parseModuleName(string dfile, ref string modName)
    {

        dchar test, test1, test2;
        Array!dchar   frontBuf;
        Array!char    collectBuf;

        enum CommentState { NoCmt, Cmt_star, Cmt_plus, Cmt_line};
        CommentState   state = CommentState.NoCmt;

        auto file = new TextFileBOM(dfile);
        scope(exit)
            file.close();

        auto reader = file.getReader();

        void nextChar(ref dchar refchar)
        {
            if (frontBuf.length > 0)
            {
                frontBuf.popBack(refchar);
                return;
            }

            if (!reader.readChar(refchar))
                throw new EOFException();
        }

        bool match(dstring ds)
        {
            dchar test;
            auto slen = ds.length;
            if (slen == 0)
                return false; // THROW EXCEPTION ?
            size_t ix = 0;

            while (ix < slen)
            {
                nextChar(test);
                if (test != ds[ix])
                {
                    frontBuf.put(test);
                    foreach_reverse(i ; 0..ix)
                        frontBuf.put(ds[ix]);
                    return false;
                }
                ix++;
            }
            return true;
        }
        try {

            for(;;)
            {
                nextChar(test);
                final switch(state)
                {
                case CommentState.NoCmt:
                    switch(test)
                    {
                    // likely to start a comment
                    case '/':
                        nextChar(test);
                        switch(test)
                        {
                            case '*':
                                state = CommentState.Cmt_star;
                                break;
                            case '+':
                                state = CommentState.Cmt_plus;
                                break;
                            case '/':
                                state = CommentState.Cmt_line;
                                break;
                            default:
                                throw new NoModuleException();
                        }
                        break;
                    default:
                        // whitespace or module declaration
                        if (isWhite(test))
                            break;
                        frontBuf.put(test);
                        if (!match("module"d))
                        {
                            throw new NoModuleException();
                        }
                        // fetch till get a ; or newline
                        nextChar(test);
                        while(isWhite(test))
                            nextChar(test);
                        while(test != ';' && !isWhite(test))
                        {
                            collectBuf.put(test);
                            nextChar(test);
                        }
                        modName = collectBuf.unique();
                        return true;

                    }
                    break;
                case CommentState.Cmt_star:
                    if (test == '*')
                    {
                        nextChar(test);
                        if (test == '/')
                            state = CommentState.NoCmt;
                        else
                            frontBuf.put(test);
                    }
                    break;
                case CommentState.Cmt_plus:
                    if (test == '+')
                    {
                        nextChar(test);
                        if (test == '/')
                            state = CommentState.NoCmt;
                        else
                            frontBuf.put(test);
                    }
                    break;
                case CommentState.Cmt_line:
                    if (test == 0x0A || test == 0x0D)
                    {
                        if (test == 0x0A)
                        {
                            nextChar(test);
                            if (test != 0x0D)
                                frontBuf.put(test);
                        }
                        state = CommentState.NoCmt;
                    }
                    break;
                }

            }
        }
        catch(NoModuleException)
        {

        }
        catch(EOFException eof)
        {

        }
        return false;
    }
    void parseDepFile(string dfile, AddDependFn fn)
    {
        // stream, cstream modules are to be replaced, with what?
        auto file = new TextFileBOM(dfile);
        auto reader = file.getReader();
        dstring sepset = " \n\t"d;
        enum : dchar {  parenOpen = '(',  parenClose = ')', colon = ':'}

        BomString   s;
        char[] linebuf;

        string rest(ref ParseInput  ir)
        {
            Array!char buf;
            while(!ir.empty)
            {
                buf.put(ir.front);
                ir.popFront();
            }
            return buf.unique;
        }
        void badScan(ref ParseInput  ir, int i)
        {
            auto s = rest(ir);

            throw new BuildException( format("Bad dependency scan %d %s %s", i,s, linebuf));
        }

        while (reader.readLine(s))
        {
            linebuf = s.get!(char[]);
            if (linebuf.length > 0)
            {
				auto ir = ParseInput(linebuf);

                if(ir.empty)
                    continue;
                string srcfile,srcmod, depmod, depfile, modtype;

				Array!char pout;

                insp.countSpace(ir);
                if (!insp.readToken(ir, sepset, pout))
                   badScan(ir,1);
				srcmod = pout.unique();
                //writeln("srcmod: ",srcmod);
                insp.countSpace(ir);
                if (!insp.matchChar(ir,parenOpen))
                {
                     badScan(ir,2);
                }

                if (!insp.readToken(ir,parenClose,pout))
                     badScan(ir,3);
				srcfile = pout.unique();
				//writeln("srcfile: ",srcfile);
				ir.popFront;
                insp.countSpace(ir);

                if (!insp.matchChar(ir,colon))
                {
                    badScan(ir,9);
                }
                insp.countSpace(ir);
                if (insp.match(ir,"public"d) || insp.match(ir,"private"d))
                {
                    insp.countSpace(ir);
                    if (!insp.matchChar(ir,colon))
                    {
                         //writeln("got ", srcfile, " rest ", rest(ir));
                        if (!insp.match(ir,"static"d))
                            badScan(ir,10);
                        else {
                            insp.countSpace(ir);
                            if (!insp.matchChar(ir,colon))
                            {
                                badScan(ir,11);
                            }
                        }

                    }

                }

                insp.countSpace(ir);

                if(!insp.readToken(ir, sepset, pout))
                    badScan(ir,6);
				depmod = pout.unique();
				//writeln("depmod: ",depmod);
                insp.countSpace(ir);

                if (!insp.matchChar(ir,parenOpen))
                    badScan(ir,7);
                if (!insp.readToken(ir,parenClose,pout))
                     badScan(ir,8);
				ir.popFront;
				depfile = pout.unique();
                //writeln("depfile: ",depfile);
                fn(srcmod, srcfile, depmod, depfile);

                // ignore rest of line

            }
            // error if deplist is null?
        }


        /*
        if (f is null)
            return "";
        scope(exit)
            fclose(f);
        Array!char  buf;
        buf.length = buflen;

        auto ptr = fgets(buf.ptr, buflen, f);
        buf.length = strlen(ptr);
        auto moduleName = buf.unique();
        auto mrange = match(moduleName,regex(r"([\w\.]*)\S*"));
        if (!mrange.empty())
        {
            auto result = mrange.front();
            return result.hit;
        }

        return ""; */

    }

    void addDependency(string modname, string modpath, string depmod, string deppath)
    {

    }
    void makeBin(Target tg, ToolSet ts, Build bd, BuildSubTarget bsub)
    {
        auto linker = ts.tools_["linker"];
        //auto objdir = varsub(tg["obj"]);
        auto syntax = linker["syntax"];
//gcc -o $(output) $(lib_paths) $(inputs) $(libs)
        auto lib_path = linker["lib_path"];
        auto lib_flag = linker["lib"];

        bsub["output"] = tg.id_;
        auto slist = linker.lists_["default_libs"];
        Array!char  cmd;
        auto libs = tg.lists_.get("libs",null);
        if (libs !is null)
            slist ~= libs;

        foreach(s ; slist)
        {
            if (cmd.length > 0)
                cmd.put(' ');
            cmd.put(replace(lib_flag,"$(val)", s));
        }
        bsub["libs"] = cmd.unique();
        bsub["inputs"] = std.string.join(bsub.objlist," ");

        slist = linker.lists_.get("search_paths",null);
        libs = tg.lists_.get("lib-paths",null);
        if (libs !is null)
            if (slist !is null)
                slist ~= libs;
            else
                slist = libs;
        foreach(s ; slist)
        {
            s = varsub(s);
            if (cmd.length > 0)
                cmd.put(' ');
            cmd.put(replace(lib_path,"$(val)", s));
        }

        bsub["lib_paths"] = cmd.unique();
        cmd = bsub.varsub(syntax);
        cmd.nullTerminate();
        auto result = system(cmd.ptr);
        writeln(cmd.toConstArray);
        writeln("Link result = ", result);

    }
    void makeObjects(Target tg, ToolSet ts, Build bd, BuildSubTarget bsub)
    {
        Array!char  cmd;

        auto compiler = ts.tools_["compiler"];
        auto objdir = varsub(tg["obj"]);
        auto output_file = compiler["output_file"];
        auto deps_file = compiler["deps_file"];
        auto syntax = compiler["syntax"];
        auto combine = tg["combine"];
        if (combine.length == 0)
            combine = "single";

        if (!exists(objdir))
            mkdirRecurse(objdir);

        auto depfile = buildPath(objdir,"_dep.txt");
        auto tempobj = buildPath(objdir,"_temp.o");

        auto importDirFlag = compiler["import_path"];
        string[] allImports;

        Array!char  importCmd;

        foreach(imp ; bsub.imports)
        {
            imp = varsub(imp);
            if (importCmd.length > 0)
                importCmd.put(' ');
            importCmd.put(replace(importDirFlag,"$(val)", imp));
        }

        //writeln(importCmd.toConstArray);
        bsub["import_paths"] = importCmd.unique;

        if (combine != "all")
        {
            bsub["flags"] = text(bd["flags"], " ", compiler["no_link"], " ", replace(deps_file, "$(val)", depfile));
            bsub["output"] = replace(output_file, "$(val)", tempobj);
        }

        void moveObject(string moduleName)
        {
            auto modulePath = text(moduleName, ".o");
            moveFile(tempobj, buildPath(objdir,modulePath));
            bsub.objlist ~= modulePath;
        }

        if (combine == "single")
        {
            foreach(p ; bsub.packages)
            {
                writeln("Compile package files ", p.filelist.length);

                auto packageDir = (p.id.length > 0) ? replace(p.id,".", dirSeparator) : "";
                string objname;
                string objpath;
                string modName;
                string modPath;
                string baseName;

                foreach(f ; p.filelist)
                {
                    if (!exists(f))
                        throw new BuildException(format("build source not found: %s",f));

                    if (!parseModuleName(f, modName))
                    {
                        // file doesn't contain a module name , use base file name.
                        modName = getBaseName(f);
                    }
                    // standard make will use just file name, not internal module name
                    modPath = replace(modName,".", dirSeparator);
                    baseName = getBaseName(f);
                    if (packageDir.length > 0)
                    {
                        bool matchesPackage = (indexOf(p.id, modName)==0);
                    }
                    objpath = text(buildPath(objdir, modPath), ".o");
                    // this is the place to make a build rule ?
                    auto srcComp = bcSource.get(modName,null);
                    if (srcComp is null)
                    {
                        srcComp = new BComponent(modName,f);
                        bcSource[modName] = srcComp;
                    }
                    else
                        srcComp.fspec.refreshMod();

                    auto objComp = bcObject.get(modName,null);
                    if (objComp is null)
                    {

                        objComp = new BComponent(modName,objpath);
                        bcObject[modName] = objComp;

                    }
                    else
                        objComp.fspec.refreshMod();
                    bsub.objlist ~= objpath;

                    srcComp.dependents ~= objComp;
                    auto srcMod = srcComp.fspec.lastMod;
                    if (!objComp.fspec.fileExists || (srcMod > objComp.fspec.lastMod))
                    {
                        bsub["output"] = replace(output_file, "$(val)", objpath);
                        bsub["inputs"] = f;
                        cmd = bsub.varsub(syntax);
                        cmd.put(" > _compile_errors.txt 2<&1");
                        cmd.nullTerminate();
                        auto result = system(cmd.ptr);
                        objComp.cmd = cmd.unique();
                        writeln(objComp.cmd);
                        if (result != 0)
                        {
                            writeln("Result = ",result);
                            auto errorText = new TextFileBOM("_compile_errors.txt");
                            auto errorRdr = errorText.getReader();
                            BomString s;
                            while (errorRdr.readLine(s))
                                writeln(s);
                            throw new BuildException("Compile errors");
                        }
                        objComp.fspec.refreshMod();
                        parseDepFile(depfile, &addDependency);
                    }
                    /*
                        auto modname = getModuleName(depfile);
                        if (modname.length == 0)
                             throw new BuildException("Module name missing");
                        objname = (modname.length > 0) ? replace(modname,".", dirSeparator) : "";
                        moveObject(objname);
                    */
                }

            }



            /*
            print("package ",iset, #files, pkgName)
            for i,v in ipairs(files) do
                vt['inputs'] = v
                cmd = varsub(syntax,vt)
                print( "cmd ", cmd)
                local result = os.execute(cmd)
                print( "result = ", result)
                if result ~= 0 then
                    return result
                end
                local moduleName = ""
                if pkgName then
                    moveObject(pkgName .. "." .. getBaseName(v))
                else
                    moveObject(getModuleName(depfile))
                end
            end
            end*/

        }


    }
    void runTarget(Target tg, ToolSet ts, Build bd)
    {
        string ttype = tg.get("type");
        if (ttype == "clean")
        {
            foreach(action ; tg.actions_)
            {
                action.run(this);
            }
        }
        else if (ttype == "lib")
        {
             auto bsub = new BuildSubTarget();
             collectSources(tg, bsub);
             makeObjects(tg,ts,bd,bsub);
             makeLib(tg,ts,bd,bsub);
             /*showLibCmd(vt)
             makeObjects(vt)
             makeLib(vt)*/
        }
        else if (ttype == "bin")
        {
            auto bsub = new BuildSubTarget();
            collectSources(tg, bsub);
            makeObjects(tg,ts,bd,bsub);
            makeBin(tg,ts,bd,bsub);
        }
        else if (ttype == "meta")
        {
            auto targlist = tg.lists_.get("depends",null);
            if (targlist is null)
                throw new BuildException("No targets in meta target");
            foreach(tgname ; targlist)
            {
                tg = getTarget(tgname);
                if (tg !is null)
                {
                    runTarget(tg,ts,bd);
                }
            }
        }
        else {
            throw new BuildException(format("Unknown target type %s",ttype));
        }
        writeln("Target type ", ttype);
    }
 }



class BuildSubTarget : JNode {
    string[]        imports;
    Package[]       packages;
    string[]        objlist;

    class Package {
        string          id;
        string[]        filelist;
    }
}

class Builder {
	string      toolCmd_;
	string      targetPath_;
    ToolSet     toolset_;
	Source[]    sources_;
	int	        result_;

	this(string tool, Source[] sources, string target)
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
