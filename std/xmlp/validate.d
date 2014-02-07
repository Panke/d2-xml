module std.xmlp.validate;

import std.xmlp.subparse, std.xmlp.linkdom, std.xmlp.parseitem;

/// Take the attributes from
public void normalizeAttributes(IXMLParser cp, XmlReturn iret)
{
	foreach(n,v ; iret.attr)
	{
		if (n == "xml:space")
		{
			if (v == "preserve")
			{

			}
			else if (v == "default")
			{

			}
			else
			{
				cp.throwParseError("xml:space must equal 'preserve' or 'default'");
			}
		}
		auto newValue = cp.attributeNormalize(v);
		if (cast(void*)v != cast(void*)newValue)
			iret.attr[n] = newValue;
	}	
}

