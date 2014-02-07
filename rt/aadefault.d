module rt.aadefault;


import rt.aaI;
//version = AAI_ARRAYMAP;

version(AAI_ARRAYMAP)
{
import  rt.aaArrayMap;

static this()
{
	gAAFactory = &makeAA;
}
}
else {
	import  rt.aaSLink;

	static this()
	{
		gAAFactory = &makeAA;
	}
}
