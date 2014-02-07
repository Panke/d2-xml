/**
 * Makette.
 *
 * Toy make tool utilising XML configuration file and XPath.
 *
 * Authors: Michael Rynn, michaelrynn@optusnet.com.au
 * Date: November 25, 2009
 *
 *
 *
 *
 * Makette is one slightly higher step from writing simple shell scripts or batch
 * files.  The information required to compile an application with multiple versions
 * is specified inside an XML file. The format is yet very young, so may change any time.
 *
 * The code uses the xmlp parser I coded, and a very abbreviated XPath interpreter.
 *
 * There is some use of the xml as instructions in a very simple interpreter.
 * See the comments in the only extant use of it so far, in makette.xml used to
 * build multiple versions of the xml parser test conformance and example application.
 *
 *
 *
 **/

import std.stdio;
import std.file;
import std.string;
import std.path;
import std.datetime;
import std.conv;
import std.stream;
import std.xmlp.array;
import std.xmlp.charinput;
import std.range;
import std.xmlp.xmlchar;
import std.xml2;
import std.array;
import std.xpath.syntax;

version(Win32)
{
    pragma(msg,"windows system");
	string dirSep = "\\";
	string wrongDirSep = "/";
	string BuildOS = "Windows 32";
	string ShellComment = "REM ";
	string platform = "WINDOWS";
}
version(linux)
{
    pragma(msg,"linux system");
    string platform = "LINUX";
	string dirSep = "/";
	string wrongDirSep = "\\";
	string BuildOS = "unix";
	string ShellComment = "# ";

}

static const MaketteVersion = "0.005";



class MakeException : Exception {
	this(string msg)
	{
		super(msg);
	}
}

/// A wrapper around a string map
class VarLookup {
	string[string]	map;


	string get(string vname, string def=null)
	{
		string* test = vname in map;
		return (test !is null) ? *test : def;
	}

    void set(string name, string[] values)
    {
        char[] result;
        if (values.length > 0)
        {
            result ~= values[0];

            foreach(s ; values[1..$])
            {
                result ~= " ";
                result ~= s;
            }
            set(name, result.idup);
        }
        else {
            throw new MakeException("set empty value");
        }
    }
	void set(string name, string value)
	{
		map[name] = value;
	}
}


alias ParseInputRange!char	ParseInput;
alias ArrayBuffer!char	ParseOutput;
alias bool function(dchar) CharTestFunc;

bool collectQName(ref ParseInput ipt, ref ParseOutput opt, CharTestFunc startChar, CharTestFunc nameChar)
{
	if (ipt.empty)
		return false;
	dchar test = ipt.front;
	if (!startChar(test))
		return false;
	opt.putEncode(test);
	ipt.popFront;
	while (!ipt.empty)
	{
		test = ipt.front;
		if (nameChar(test))
		{
			opt.putEncode(test);
			ipt.popFront;
		}
		else
			break;
	}
	return true;
}

/// read in a string till encounter a character in sepChar set
bool readToken (ref ParseInput irg, dstring sepSet, ref ParseOutput pout)
{
	bool hit = false;
	pout.clear();
SCAN_LOOP:
    for(;;)
    {
        if (irg.empty)
            break;
        auto test = irg.front;
        foreach(dchar sep ; sepSet)
            if (test == sep)
                break SCAN_LOOP;
        pout.putEncode(test);
        irg.popFront;
		hit = true;
    }
	return hit;
}
/// read in a string till encounter the dchar
bool readToken (ref ParseInput irg, dchar match, ref ParseOutput pout)
{
	bool hit = false;
	pout.clear();
SCAN_LOOP:
    for(;;)
    {
        if (irg.empty)
            break;
        auto test = irg.front;
		if (test == match)
                break SCAN_LOOP;
        pout.putEncode(test);
        irg.popFront;
		hit = true;
    }
	return hit;
}
uint countSpace(ref ParseInput ipt)
{
	uint   count = 0;
	while(!ipt.empty) {
		switch(ipt.front)
		{
		case 0x020: break;
		case 0x09: break;
		case 0x0A: break;
		case 0x0D: break;
		default:
			return count;
		}
		ipt.popFront;
		count++;
	}
	return count;
}

bool matchChar(ref ParseInput ipt, dchar c)
{
	if (ipt.empty)
		return false;
	if (c == ipt.front)
	{
		ipt.popFront;
		return true;
	}
	return false;
}
	
/// A kind of execution stack for adding tempories in templates.
class VarStack {
	VarLookup[]	stack;

	VarLookup  top;
	VarLookup  env;  // bottom of stack dedicated to environment
	Element		  rootElement_; // current element
    string        currentDir_;

	bool		 noExecute;

	alias bool function(VarStack stk, Element nc) ActionFn;

	static ActionFn[string] actionMap;

	static this()
	{
		actionMap["newer"] = &doNewerSource;
		actionMap["stack-dump"] = &doStackDump;

		actionMap["newlist"] = &doNewList;
	    actionMap["module-dep"] = &doModuleDep;
		actionMap["append"] = &doAppend;
		actionMap["filename"] = &doFileName;
		actionMap["foreach"] = &doForEach;

		actionMap["chdir"] = &doChangeDir;

		actionMap["system"] = &doSystem;
		actionMap["task"] = &doTask;
		actionMap["target"] = &doTarget;
		actionMap["switch"] = &doSwitch;
		actionMap["sequence"] = &doSequence;
		actionMap["set"] = &doSet;
		actionMap["run"] = &doRecipe;
		actionMap["sourcelist"] = &doSourceList;
		actionMap["echo"] = &doEcho;

        actionMap["rmdir"]  = &doDelDir;
        actionMap["rm"] = &doDelFile;


	}

    void setCurrentDir(string cd)
    {
        top.set("CurrentDir", cd);
        currentDir_ = cd;
    }
    string getCurrentDir()
    {
        return lookup("CurrentDir", currentDir_);
    }
    VarLookup subtop()
    {
        if (stack.length > 1)
        {
            return stack[$-2];
        }
        else {
            throw new MakeException("No stack subtop");
        }
        assert(0);
    }
	this(Element root, VarLookup environ)
	{
		rootElement_ = root;
		env = environ;

		pushFrame(environ);
	}
	void pushFrame(VarLookup vf)
	{

		uint slen = stack.length;
		stack ~= vf;
		top = stack[slen];
	}

	void popFrame()
	{
		uint slen = stack.length;
		if (slen > 0)
		{
			slen--;
			stack.length = slen;
			if (slen > 0)
			{
				top = stack[slen-1];
			}
			else
				top = null;
		}
		else
			throw new MakeException("Empty variable stack");
	}

    // lookup the value and the level it is defined at
    VarLookup lookupLevel(string vname, ref string value)
    {
		foreach_reverse(vs ; stack)
		{
			string* test = vname in vs.map;
			if (test !is null)
			{
			    value = *test;
			    return vs;
			}
		}
		return null;
    }

	string lookup(string vname, string def=null)
	{
		foreach_reverse(vs ; stack)
		{
			string* test = vname in vs.map;
			if (test !is null)
				return *test;
		}
		// is it a process environment value?
		string val = std.process.getenv(vname);
		if ((val is null) || (val.length==0))
			return def;
		else {
			// not expected to change, cache it
			env.set(vname, val);
			return val;
		}
	}

	/// evaluate the unicode string for [var]
	/// and substitute lookup for <var> if found, else leave it.

	string eval(const(char)[] vs, int callct = 0)
	{
		ArrayBuffer!char	recons;
		
		dstring temp;

		if (vs is null)
			return null;

	    callct++;
	    if (callct > 50)
			throw new MakeException("Hit recursion limit in eval");


		int     ct = 0;
		bool 	isVName = false; // if first character is XMLName following a [
		bool 	ok;
		
		auto ir = ParseInput(vs);
	

		while(!ir.empty)
		{
			dchar test = ir.front;
			ir.popFront();
			if (ir.empty)
			{
				recons.putEncode(test);
				return recons.unique();
			}
			if (test == '[')
			{
				ArrayBuffer!char vout;
				
				ok = collectQName(ir,vout,&isNameStartChar10, &isNameChar10 );
				if (ok)
				{
					string varName = vout.unique();
					if (ir.empty || ir.front != ']')
						throw new MakeException("missing ']'");

					string result = this.lookup(varName);
					if (result !is null)
					{
						recons.put( eval(result,callct) );
						ct++;
						ir.popFront();
					}
					else
						throw new MakeException("lookup failed for variable named " ~ varName);

				}
				else {
					// specials
					switch(ir.front)
					{
					case '~':
						ir.popFront();
						ok = (!ir.empty && ir.front == ']');
						if (ok)
						{
							ir.popFront();
							string result = this.lookup("~");
							if (result !is null)
							{
								recons.put( eval(result) );
								ct++;
							}
							else
							{
								throw new MakeException("lookup failed for variable named ~");
							}
						}
						break;
					default:
						// some other kind of expression
						break;
					}
				}
			}
			else {
				recons.putEncode(test);
			}
		}
		if (ct > 0)
			return recons.unique();
		else
			return vs.idup;
	}
}

void appendSourceList(VarStack stk, Element nc, ref string srclist)
{
	NodeList ns = xpathNodeList(nc,"dir");
	
	
	foreach(dcat ; ns.items)
	{
		auto test = cast(Element) dcat;

		DOMString value = test.getAttribute("path");
		string dirname = stk.eval(value);
		
		value = test.getAttribute("ext");
		string ext = stk.eval(value);

		if ((dirname !is null) && (lastIndexOf(dirname,dirSep) != dirname.length-1))
		{
			dirname = dirname ~ dirSep;
		}
		string[] filelist = split(test.getTextContent());
		foreach(fname ; filelist)
		{
			 string path;

			 if (dirname is null)
				path = fname ~ ext;
			 else
				path = dirname ~ fname ~ ext;
			 path = fixOSPath(stk.eval(path));
			 srclist ~= " ";
			 srclist ~= path;
		}
	}
}

	bool doTask_foreach(VarStack stk, string rootCmd, string arg = null)
	{
		if (arg !is null)
		{
			char[] cmd = rootCmd.dup;
			cmd ~= " ";
			cmd ~= arg;
			rootCmd = cmd.idup;
		}

		if (stk.noExecute)
		{
			writefln("%s",rootCmd);
			return true;
		}
		else {
			int cmdresult = std.process.system(rootCmd);
			return (cmdresult == 0);
		}
	}

	static string fixOSPath(string path)
	{
		return std.array.replace(path, wrongDirSep, dirSep);
	}
    bool getModTime(string path, ref SysTime tmod)
    {
  
       try {
		   version(Windows)
		   {
				SysTime ftc, fta, ftm;
				getTimesWin(path, ftc, fta, ftm);
				tmod = ftm;
		   }
       }
       catch(Exception e)
       {
           return false;
       }
       
       return true;
    }
	bool doStackDump(VarStack stk, Element task)
	{
            foreach_reverse(ix,v ; stk.stack)
            {
                writeln("Level ", ix);
                foreach(k,v ; v.map)
                {
                    writeln("k,v ",k," | ",v);
                }
            }
            return true;
	}

	bool doNewerSource(VarStack stk, Element task)
	{
		string value = task.getAttribute("depends");
		string srcList = stk.eval(value);
		value = task.getAttribute("list");
		string changed = stk.eval(value);

        if (srcList.length == 0 || changed.length == 0)
        {
            throw new MakeException("changed or depends not set");
        }

        string[] src = split(srcList);
        string[size_t] newlist;

        SysTime[]  srcmod = new SysTime[src.length];

        foreach(ix,sfile; src)
        {
            SysTime tmod;

            if (!getModTime(sfile, tmod))
                throw new MakeException(text("Cannot find", sfile));
            srcmod[ix] = tmod;
        }

		NodeList ns = xpathNodeList(task,"target@path");
		if (ns.length == 0)
		{
		    throw new MakeException("No target files");
		}
        for(int i = 0; i < ns.length; i++)
        {
            string tfile = NodeAsString(ns[i]);
            SysTime tmod;

            if (getModTime(tfile, tmod))
            {
                foreach(ix,dt ; srcmod)
                    if (dt > tmod)
                        newlist[ix]=src[ix];
            }
            else {
                foreach(ix,dt ; srcmod)
                    newlist[ix]=src[ix];
                break;
            }
        }
        string[] nlist;
        if (newlist.length > 0)
        {
            foreach(nfk, nfv ; newlist)
            {
               nlist ~= nfv;
            }
        }
        if (nlist.length > 0)
        {
            srcList = std.string.join(nlist," ");
        }
        else
            srcList = "";

        stk.top.set(changed, srcList);

        return true;

	}

	void doFilePathDelete(VarStack stk, string fpath, bool recurse)
	{
        try {
            if (!isabs(fpath))
            {

                string currentDir = stk.getCurrentDir();
                fpath = currentDir ~ sep ~ fpath;
            }


        // Make sure the file or directory exists and isn't write protected
            if (!exists(fpath))
                return;


        // If it is a directory, make sure it is empty
            if (isdir(fpath))
            {
                 auto mode = (recurse ? SpanMode.depth : SpanMode.breadth);
                 foreach (string name; dirEntries(fpath, mode))
                 {
                     remove(name);
                 }
                 return;
            }
            remove(fpath);
        }
        catch (FileException fe)
        {
            throw new MakeException(fe.toString());
        }


	}
	bool doDelFile(VarStack stk, Element task)
	{
			 string fpath = task.getAttribute("path");
             if (fpath.length == 0)
                 throw new MakeException("Empty file path for rm");
              doFilePathDelete(stk,fpath,false);
              return true;
	}
	bool doDelDir(VarStack stk, Element task)
	{
			string fpath = task.getAttribute("path");
             if (fpath.length == 0)
                 throw new MakeException("Empty file path for rm");
             doFilePathDelete(stk,fpath,true);
             return true;
	}
	bool doForEach(VarStack stk, Element task)
	{
		// foreach item in seperated list "list",
		// put the item text in variable "var"

		// execute children sequence
		string value = task.getAttribute("list");

		string valueList = stk.eval(value);
		value = task.getAttribute("name");
		string varName = stk.eval(value);
        if (valueList.length > 0)
        {
            string[] src = split(valueList);
            foreach (s ; src)
            {
                VarLookup vl = new VarLookup();
                vl.set(varName, s);
                stk.pushFrame(vl);
                doSequence(stk, task);
                stk.popFrame();
            }
		}

		return true;

	}

	bool doTask(VarStack stk, Element task)
	{
		// from environment get the name of the tool attribute
		string value = task.getAttribute("tool");
		string toolid = stk.eval(value);

		// put together a command line

        NodeList ns = xpathNodeList(stk.rootElement_, format("/makette/tool[@name='%s']",toolid));

        if (ns.length == 0)
            throw new MakeException("tool name not found: " ~ toolid);

		string cmd = NodeAsString(xpathNodeList(cast(Element) ns[0], "@path")[0]);
		

		if (cmd !is null)
			cmd = stk.eval(cmd);
		else
			throw new MakeException("tool path not found: " ~ cmd);


		cmd = fixOSPath(cmd);

		NodeList opset = xpathNodeList(task,"option");
		opset ~= xpathNodeList(cast(Element) ns[0], "option").items;

		// see if there is a for each, to invoke task on each for last argument
		// make the executable command with options, assume same for each
		char[] exec_cmd = cmd.dup;

		foreach( optcat; opset.items)
		{
			Element e = cast(Element) optcat;
			string ocmd = e.getAttribute("cmd");
			string oval = e.getAttribute("val");

			if (ocmd !is null)
			{
				exec_cmd ~= " ";
				exec_cmd ~= stk.eval(ocmd);
				if (oval !is null)
				{
					oval = stk.eval(oval);
					string vtype=e.getAttribute("vtype");
					if (vtype.length > 0)
					{
						switch (vtype)
						{
						case "syspath":
							oval = fixOSPath(oval);
							break;
						default:
							throw new MakeException("unknown vtype value " ~ vtype);
						}
					}
					exec_cmd ~= stk.eval(oval);
				}
			}
		}

		// set the working directory once
		NodeList chset = xpathNodeList(task, "chdir/@path");
		if (chset.length > 0)
		{
			string chdirpath = NodeAsString(chset[0]);
			chdirpath = stk.eval(chdirpath);
			if (chdirpath.length > 0)
			{
				chdirpath = expandTilde(chdirpath);
				if (stk.noExecute)
					writefln("cd %s",chdirpath);
				else
					chdir(chdirpath);
			}
		}
		string foreach_list = task.getAttribute("foreach");
		string exec_cmd2 = exec_cmd.idup;
		if (foreach_list.length > 0)
		{
			foreach_list = stk.eval(foreach_list);
			string[] src = split(foreach_list);
			foreach (s ; src)
			{
				if (!doTask_foreach(stk, exec_cmd2, s))
					return false;
			}
			return true;
		}
		else {
			return doTask_foreach(stk, exec_cmd2);
		}
	}

/** Split on last directory separator if found, keep the separator */
string getNamePath(string fullpath, ref string remaining)
{
	immutable lastix = fullpath.length-1;

    foreach_reverse(int ix, dchar c; fullpath)
    {
		// if no extension found
		// remaining == fullpath, return null
		version(Win32)
		{
			if ((c == '\\') || (c == ':'))
			{
				remaining = fullpath[0 .. ix+1]; // include separator
				return (ix < lastix) ? fullpath[ix+1 .. $] : null;
			}
		}
		else version(unix)
		{
			if (c == '/')
			{
				remaining = fullpath[0 .. ix+1]; // include separator
				return (ix < lastix) ? fullpath[ix+1 .. $] : null;
			}
		}
	}
	// no path separators, so the name is the entire path, nothing remaining
	remaining = null;
	return fullpath;
}

/** Split path and extension, if found **/
bool matchesAny(string test, string[] list)
{
    foreach(s ; list)
        if (test == s)
            return true;
    return false;
}
bool containsAny(string test, string[] list)
{
    foreach(s ; list)
        if (test.indexOf(s) >= 0)
            return true;
    return false;
}
bool startsWithAny(string test, string[] list)
{
    foreach(s ; list)
        if (test.startsWith(s))
            return true;
    return false;
}
string getExtensionPath(string fullpath, ref string remaining)
{
	immutable lastix = fullpath.length-1;
    foreach_reverse(int ix, dchar c; fullpath)
    {
		// if no extension found
		// remaining == fullpath, return null
		version(Win32)
		{
			if ((c == '\\') || (c == ':'))
			{
				break;
			}
		}
		version(Posix)
		{
			if (c == '/')
			{
				break;
			}
		}
		if (c == '.')
		{
			// split either side
			remaining = fullpath[0 .. ix]; // do not include ix
			return (ix < lastix) ? fullpath[ix+1 .. $] : null;
		}
	}
	// no path or extension separators
	remaining = fullpath;
	return null;
}
	/**
	 * Make a new list of filenames (string seperated by blanks).
	 * Make the same file names a tool might do.
	 * Attributes in newlist are :
	 * 	name : name of new string variable
	 *  fromlist : string variable, understood as blank separated.
	 *  newpath : substitute new path for existing file path, even if original has no path.
	 *  newext  : substitute old extension for new extension, even if original has no extension.
	 *
	 */
	bool doNewList(VarStack stk, Element nc)
	{

		
		string newlistname = stk.eval(nc.getAttribute("name"));
		if (newlistname is null)
			throw new MakeException("Missing attribute name for newlist");

		string fromlist = stk.eval(nc.getAttribute("fromlist"));
		if (fromlist is null)
			throw new MakeException("Missing attribute fromlist for newlist");

		string newext = stk.eval(nc.getAttribute("newext"));
		if (newext !is null)
		{
			if (newext[0] != '.')
				newext = "." ~ newext;
		}

		string newpath = stk.eval(nc.getAttribute("newpath"));
		if (newpath !is null)
		{
			if (lastIndexOf(newpath,dirSep) != newpath.length-1)
				newpath = newpath ~ dirSep;
		}

		string[] src = split(fromlist);
		string[] newsrc;

		newsrc.length = src.length;
		foreach(int ix, s ; src)
		{
			// split path + extension
			string rootPath;
			string extension = getExtensionPath(s, rootPath);
			string baseName = getNamePath(rootPath, rootPath);

			if (newpath !is null)
			{
				rootPath = newpath;
			}

			if (newext !is null)
			{
				extension = newext;
			}

			// reconstruct
			string rpath = rootPath ~ baseName ~ extension;
			newsrc[ix] = rpath;
		}
		stk.top.set(newlistname, std.string.join(newsrc," "));
		return true;
	}

	bool doEcho(VarStack stk, Element nc)
	{
		string value = stk.eval(nc.getTextContent());
		if (stk.noExecute)
			value = "echo " ~ value;
		writefln("%s",value);
		return true;
	}

     /**
        <module-dep name="sourcelist">
        <source path="[WKDIR]\[moddep]" />
        <lib-source path="C:\\D\\dmd2\\src"/> <!-- ignore files here -->
    </module-dep>
        Create a  list of files saved in variable name.
        Read the dmd output of dependencies in source@path.
        Ignore any paths that are in lib-source@path ( Presume they will be linked )
    **/
    bool doModuleDep(VarStack stk, Element nc)
    {
        string[string]    dependents; // key is module, value is filepath
        string[]   exclude_mod;
        string[]   exclude_ext;
        string[]   exclude_contain;

        void check_dependency(string mod_name, string file_name)
        {
            if(startsWithAny(mod_name, exclude_mod))
                return;
            string* findmod = mod_name in dependents;

            if (findmod is null)
            {
                string path = file_name.replace("\\\\","\\");
                if (containsAny(path, exclude_contain))
                    return;
                string ext = getExt(path);
                if (matchesAny(ext, exclude_ext))
                    return;
                dependents[mod_name] = path;
            }
        }

		string var_name = stk.eval(nc.getAttribute("name"));

        if (var_name.length == 0)
            throw new MakeException("No variable name for dependency list");

        NodeList ns = xpathNodeList(nc, "source@path");
        if (ns.length == 0)
            throw new MakeException("No path for module dependency file");

        string srcpath = stk.eval(NodeAsString(ns[0]));


        // build up a list of excludes
         ns = xpathNodeList(nc, "exclude-module@starts-with");
        for(size_t i = 0; i <  ns.length; i++)
            exclude_mod ~=  fixOSPath(NodeAsString(ns[i]));

        ns = xpathNodeList(nc, "exclude-file@ext");
        for(size_t i = 0; i <  ns.length; i++)
            exclude_ext ~=  NodeAsString(ns[i]);

        ns = xpathNodeList(nc, "exclude-file@contains");
        for(size_t i = 0; i <  ns.length; i++)
            exclude_contain ~=  fixOSPath(NodeAsString(ns[i]));

        std.stream.File f = new std.stream.File();
        f.open(srcpath);

        /*
            <module> = module.tree.name;
            <import type> =   private| public
            dependency =  <module> (<filepath>) : <import type> : <module> (filepath)
        */

        dstring sepset = " ";
        
		char[] linebuf;
		
        void badScan()
        {
            throw new MakeException( format("Bad dependency scan %s", linebuf));
        }
        enum : dchar {  parenOpen = '(',  parenClose = ')', colon = ':'}

        // scan the file until the pattern stops

        scope(exit)
            f.close();

		
		
        SCAN_FILE: while(!f.eof())
        {
			linebuf.length = 0;
            linebuf = f.readLine(linebuf);
            if (linebuf.length > 0)
            {
				auto ir = ParseInput(linebuf);

                if(ir.empty)
                    continue;
                string srcfile,srcmod, depmod, depfile, modtype;
				
				ArrayBuffer!char pout;
				
                if (!readToken(ir, sepset, pout))
                   badScan();
				srcmod = pout.unique();
				
                countSpace(ir);
                if (!matchChar(ir,parenOpen))
                    badScan();

                if (!readToken(ir,parenClose,pout))
                     badScan();
				srcfile = pout.unique();
				ir.popFront;
                countSpace(ir);
                if (!matchChar(ir,colon))
                    badScan();
                countSpace(ir);
				
                if (!readToken(ir, sepset, pout))
                    badScan();
				
				modtype = pout.unique();
                countSpace(ir);
                if (!matchChar(ir,colon))
                    badScan();
                countSpace(ir);

                if(!readToken(ir, sepset, pout))
                    badScan();
				depmod = pout.unique();
                countSpace(ir);
                if (!matchChar(ir,parenOpen))
                    badScan();
                if (!readToken(ir,parenClose,pout))
                     badScan();
				ir.popFront;
				depfile = pout.unique();

                check_dependency(srcmod, srcfile);
                check_dependency(depmod, depfile);
                // ignore rest of line

            }
            // error if deplist is null?

        }
        if (dependents.length == 0)
            throw new MakeException("Empty dependency list");

        stk.top.set(var_name, dependents.values);

        return true;
   }
	bool doRecipe(VarStack stk, Element nc)
	{
		string pname = nc.getAttribute("recipe");

		if (pname !is null)
		{
			VarLookup vl = new VarLookup();
			vl.set("recipe", pname);
			stk.pushFrame(vl);

			// do count check

			NodeList ns = xpathNodeList(stk.rootElement_, format("/makette/recipe[@name='%s']",pname));

			if (ns.length == 0)
				throw new MakeException("No recipe named " ~ pname);
			if (ns.length > 1)
				throw new MakeException("More than 1 recipe named " ~ pname);

			// before running the recipe , push each attribute value
			// includes recipe attribute
			NamedNodeMap map = nc.getAttributes();
			for(int i =0; i < map.getLength(); i++)
			{
				Attr atr = cast(Attr) map.item(i);
				DOMString nm = atr.getNodeName();
				DOMString val = atr.getNodeValue();
				stk.top.set(nm, val);
			}
			bool result = doSequence(stk,cast(Element) ns[0]);
			stk.popFrame();
			return result;
		}
		else {
			pname = nc.getAttribute("target");
			if (pname is null)
			{
				throw new MakeException("No recipe or target attribute for run");
			}
			nc = findSingleTarget(stk.rootElement_, pname);
			return doTarget(stk, nc);
		}
		assert(0);

	}

	bool doSet(VarStack stk, Element nc)
	{
		string pname = nc.getAttribute("name");
		string pvalue = nc.getAttribute("value");
		if (pname is null)
			throw new MakeException("set name is null");
		if (pvalue is null)
			pvalue = "";
		string vtype = nc.getAttribute("vtype");
		if (vtype.length > 0)
		switch(vtype)
		{
		case "syspath":
			version(Windows)
			{
				pvalue=replace(pvalue,"/","\\");
			}
			else
			{
				pvalue=replace(pvalue,"\\","/");
			}
			break;
		default:
			throw new MakeException(text("Unknown vtype in set ", pname, " ", pvalue));
			break;
		}
		stk.top.set(pname,pvalue);
		return true;
	}
	/// children are the sequence.
	bool doSequence(VarStack stk, Element nc)
	{
		NodeList ns = xpathNodeList(nc, "*");
		if (ns is null)
			return true;
		foreach(chcat ; ns.items)
		{
			Element e = cast(Element) chcat;
			DOMString ename = e.getNodeName();
			VarStack.ActionFn*  af = ename in VarStack.actionMap;
			if (af !is null)
			{
				bool check = (*af)(stk, e);
				if (!check)
					return false;
			}
			else {
				throw new MakeException("No action for " ~ ename);
			}
		}

		return true;
	}

	bool doFileName(VarStack stk, Element e)
	{
		//name="objfile" value="[srcfile]" newpath="[objd]" newext="obj"/>
		string varname = stk.eval(e.getAttribute("name"));
		if (varname is null)
			throw new MakeException("Missing attribute 'name' for newlist");

		string value = stk.eval(e.getAttribute("value"));
		if (value is null)
			throw new MakeException("Missing attribute 'value' for newlist");

		string newext = stk.eval(e.getAttribute("newext"));
		if (newext !is null)
		{
			if (newext[0] != '.')
				newext = "." ~ newext;
		}

		string newpath = stk.eval(e.getAttribute("newpath"));
		if (newpath !is null)
		{
			if (lastIndexOf(newpath,dirSep) != newpath.length-1)
				newpath = newpath ~ dirSep;
		}


		// split path + extension
		string rootPath;
		string extension = getExtensionPath(value, rootPath);
		string baseName = getNamePath(rootPath, rootPath);

		if (newpath !is null)
		{
			rootPath = newpath;
		}

		if (newext !is null)
		{
			extension = newext;
		}

		// reconstruct
		string rpath = rootPath ~ baseName ~ extension;

		stk.top.set(varname, rpath);
		return true;
	}


	bool doAppend(VarStack stk, Element e)
	{
		//<append name="objlist" value="[objfile]" />

		string varname = stk.eval(e.getAttribute("name"));
		if (varname is null)
			throw new MakeException("missing attribute 'name'");

        string value;
        VarLookup level = stk.lookupLevel(varname, value);
        if (level is null)
        {
            value = "";
            level = stk.top;
        }
		string addval = stk.eval(e.getAttribute("value"));
		if (addval is null)
			throw new MakeException("missing attribute 'value'");
		if (value.length == 0)
			value = addval;
		else
			value = value ~ " " ~ addval;

		level.set(varname, value);
		return true;
	}

	bool doSourceList(VarStack stk, Element e)
	{
		string srctext = e.getTextContent();
		string[] src = split(srctext);

		string srclist =  " ";
		foreach (s ; src)
		{
			NodeList ns = xpathNodeList(stk.rootElement_,format("/makette/source[@name='%s']",s));
			invariant nlen = ns.getLength;
			if (nlen == 0)
				throw new MakeException("No sourcelist found: " ~ s);
			if (nlen > 1)
				throw new MakeException("More than one sourcelist named " ~ s);

			appendSourceList(stk, cast(Element) ns[0], srclist);
		}
		stk.top.set("sourcelist", srclist);
		return true;
	}

	bool doSwitch(VarStack stk, Element e)
	{
		// execute one item
		// children are case
		NodeList cases = xpathNodeList(e,"case");

		// get the variable name

		string pname = e.getAttribute("name");
		string pvalue = stk.lookup(pname);
		if (pvalue is null)
			throw new MakeException("switch value is null");

		foreach(ncase ; cases.items)
		{
			Element ce = cast(Element) ncase;

			string cvalue = ce.getAttribute("value");
			if (cvalue is null)
			{
				if (pvalue is null)
					throw new MakeException("case value is null");
			}
			cvalue = stk.eval(cvalue);
			if (cvalue[] == pvalue[])
				return doSequence(stk, ce);
		}
		// check for default?
		cases = xpathNodeList(e,"default");
		if (cases.getLength > 0)
		{
			return doSequence(stk, cast(Element) cases[0]);
		}
		return true;

	}

	bool doChangeDir(VarStack stk, Element e)
	{
		string wkdir = e.getAttribute("path");

		if (wkdir.length > 0)
		{
			wkdir = stk.eval(wkdir);
			wkdir = expandTilde(wkdir);
			stk.setCurrentDir(wkdir); // use virtual cd
			if (stk.noExecute)
			{

				writefln("cd %s",wkdir);
			}
			else {
				try {
					chdir(wkdir); // TODO: stop using chdir
				}
				catch(FileException fe)
				{
					writefln("Unable to chdir %s", wkdir);
					return false;
				}
			}
		}
		return true;
	}

	bool doTarget(VarStack stk, Element e)
	{
		VarLookup vl = new VarLookup();
		string targetname = e.getAttribute("name");
		vl.set("target",targetname);
		stk.pushFrame(vl);
		bool result = doSequence(stk, e);
		stk.popFrame();
		return result;
	}


	bool doSystem(VarStack stk, Element e)
	{
		string  onError = e.getAttribute("error");
		bool ignoreError = (onError is null) ? false : (onError == "ignore");
		string  cmd = e.getTextContent();
		if (cmd is null)
			throw new MakeException("system element has no text");
		cmd = stk.eval(cmd);
		if (!stk.noExecute)
		{
			int result = std.process.system(cmd);
			if (result != 0)
				writefln("Error %d with %s", result, cmd);
			return ((result==0) || ignoreError);
		}
		else {
			writefln("%s",cmd);
			return true;
		}
		assert(0);

	}



Element findSingleTarget(Element ecat, string tname)
{
	string xps = format("/makette/target[@name='%s']",tname);
	NodeList ns = xpathNodeList(ecat, xps);
	if (ns.length == 0)
	{
		throw new MakeException("No target found named " ~ tname);
	}
	if (ns.getLength > 1)
	{
		throw new MakeException("More than one target found named " ~ tname);
	}
	return cast(Element) ns[0];
}

void main(char[][] args)
{
	string config = "makette.xml";
	string[] targetlist;
	bool noExecute = false;
	bool doList = false;

	if (args.length > 1)
	{
		int aix = 1;
		while (aix < args.length)
		{
			char[] arg = args[aix];
			aix++;
			switch(arg)
			{
			case "-l":
				doList = true;
				break;
			case "-f":
				if (aix < args.length)
				{
					config = args[aix].idup;
					aix++;
				}
				break;
			case "-n":
				noExecute = true;
				break;
			default:
				targetlist ~= arg.idup;
				break;
			}
		}
	}
	else {
		writefln(r"makette -f <makette.xml> ] [-n] [-l] [target]*
			-f : xml build file
			Default file is makette.xml in current directory.
			-n : No execution, emit commands to stdout
			-l : List names of targets
			Default target is all.");
		config = "makette.xml";
	}


	Document mdoc = DomBuilder.LoadFile(config);

	// what platform is this?
	VarLookup environ = new VarLookup();

	version(linux)
	{
		environ.set("~",expandTilde("~")); // maybe should just use HOME
	}


	// defaults
	environ.set("platform",platform);

	Element root = mdoc.getDocumentElement();
	root = cast(Element) root.getParentNode();
	
	VarStack vstack = new VarStack(root,environ);
	vstack.noExecute = noExecute;

	if(noExecute)
	{
		writefln("%s makette %s generated for %s",ShellComment, MaketteVersion, BuildOS);
	}
	// read init

	NodeList ns;

	ns = xpathNodeList(root, "/makette/init");

	foreach(nscat ; ns.items)
	{
		doSequence(vstack, cast(Element) nscat);
	}


	// if list, get all the target names and exit
	if (doList)
	{
		ns = xpathNodeList(root, "/makette/target/@name");
		writef("targets:");
		foreach(ts ; ns.items)
		{
			auto atr = cast(Attr)  ts;
			writef(" %s",atr.getNodeValue());
		}
		writefln("");
		return;
	}

	if (targetlist.length == 0)
	{	// get target named all
		targetlist ~= "all";
	}

	// check each target
	ns = new NodeList();

	foreach(ts ; targetlist)
	{
		Element nc = findSingleTarget(root, ts);
		ns ~= nc;
	}

	/// build each target
	foreach(tcat ; ns.items)
	{
		doTarget(vstack,cast(Element) tcat);
	}

}
