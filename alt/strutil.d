module alt.strutil;

import alt.zstring;
import std.xmlp.parseitem;
import std.xmlp.charinput;
import alt.zstring;
import std.traits;
import std.stdint;


/// Return full path to current process
version(Windows)
{
	import std.c.windows.windows;

    string getApplicationPath()
    {
        char name[MAX_PATH+1];

        HMODULE hm = GetModuleHandleA(null);
        DWORD res = GetModuleFileNameA(hm, name.ptr, MAX_PATH);

		return (res > 0) ? name[0..res].idup : null;
    }

}
version(linux)
{
    private import std.c.stdlib;
    private import std.file;

    string getApplicationPath ()
    {
        return readLink("/proc/self/exe");
    }
}
/// Custom arse to split by space, comma, and anything between quotes, but unquote.

S[][] splitUnquoteList(S)(S[] src, bool addEmpty = false)
if (isSomeString!(S[]))
{

    auto ir = new ParseInputRange!S(src);
    const(S)[][] result;
    uintptr_t   dataStart = 0;
    bool inData = false;
    uintptr_t   commaCt = 0;

    void grab()
    {
        auto seg = src[dataStart .. ir.index];
        result ~= seg;
        inData = false;
        commaCt = 0;
    }

    while(!ir.empty)
    {
        dchar test = ir.front;
        switch(test)
        {
        case ' ':
        case '\t':
        case '\n':
        case '\r':
            if (inData)
                grab();
            ir.popFront();
            break;
        case '\"':
        case '\'':
            // simple inline unquote, unless in data
            if (inData)
                goto default;
            inData = true;
            ir.popFront();
            dataStart = ir.index;
            while (!ir.empty)
            {
                if (ir.front == test)
                {
                    grab();
                    ir.popFront();
                    break;
                }
                ir.popFront();
            }
            if (inData)
            {
                throw new AltStringError("unmatched quote in list");
            }
            break;
        case ',':
            if (inData)
                grab();
            else if (addEmpty)
            {
                commaCt++;
                if (commaCt > 1)
                    result ~= src[ir.index..ir.index];
            }

            ir.popFront();
            break;
        default: // some none white space , none separator
            if (!inData)
            {
                inData = true;
                dataStart = ir.index;
            }
            ir.popFront();
            break;
        }
    }
    if (inData)
        grab();
    return result;
}

void strutil_unittest()
{
    string test = `"Hello D" , , Hickory, Dickory Dock`;
    auto noEmpty = splitUnquoteList(test,false);
    auto empty = splitUnquoteList(test,true);
    assert(noEmpty == ["Hello D", "Hickory", "Dickory",  "Dock"]);
    assert(empty == ["Hello D", "", "Hickory", "Dickory",  "Dock"]);


}
unittest
{

    strutil_unittest();
}
