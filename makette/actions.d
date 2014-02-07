module makette.actions;

import makette.source;
import std.file, std.path;
import std.xmlp.linkdom;

Action makeAction(JNode jf, Element e)
{
    auto act = new Action_rmdir();
    act.init(jf, e);
    return act;
}

enum kPath = "path";
enum kRmdir = "rmdir";

static this()
{
    registerAction(kRmdir, &makeAction);
}

void doFilePathDelete(string fpath, bool recurse)
{

// Make sure the file or directory exists and isn't write protected
    if (!exists(fpath))
        return;
// If it is a directory, make sure it is empty
    if (isDir(fpath))
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


class Action_rmdir : Action {
    override void init(JNode jf, Element e)
    {
        string path = e.getAttribute(kPath);
        set(kPath,path);
    }
    override void run(JobFile jf)
    {
        string path = get(kPath);
        path = jf.varsub(path);
        if (!isAbsolute(path))
        {
            path=absolutePath(path);
        }
        doFilePathDelete(path,true);
    }
}
