

import alt.xmlbuffer;
import org.w3c.dom;
import org.w3c.xmlparse;
import org.w3c.xmlformat;

import std.stream;
import std.stdio;


mixin(import_xmlparser("wstring"));

alias XmlFormat!(wstring).DOMFormat	DOMFormat;

int main(char[][] args)
{
    if(args.length > 1)
    {
        string name = args[1].idup;
        std.stream.File f = new std.stream.File(name);

        XmlInputStream xis  = new XmlInputStream(f);
		
		auto p = new DOMReader(xis,getDOMImplementation());
		
		Document doc = null;
		
		try {
			Node n = p.nextNode();
			// the first call creates the empty document node
			// after parsing the xml declaration
			if (n !is null)
			{
				doc = cast(Document) n;
				if (doc is null)
					throw new DOMFail("Not a document node");
				
				do {
					n = p.nextNode();
				} 
				while (n !is null);
			}
		}
		catch(Exception e)
		{
			writeln(e.toString());
		}
		if (doc !is null)
		{
			DOMFormat df = new DOMFormat();
			
			void putout(const(char)[] buf)
			{
				write(buf);
				stdout.flush();
			}
			df.documentOut(doc, &putout, 0);
		}
    }
    return 0;
}
