module alt.simpleparse;

import std.xmlp.charinput;
import alt.zstring;

alias ParseInputRange!char	ParseInput;
alias Array!char	ParseOutput;
alias bool function(dchar) CharTestFunc;

bool collectQName(ref ParseInput ipt, ref ParseOutput opt, CharTestFunc startChar, CharTestFunc nameChar)
{
	if (ipt.empty)
		return false;
	dchar test = ipt.front;
	if (!startChar(test))
		return false;
	opt.put(test);
	ipt.popFront;
	while (!ipt.empty)
	{
		test = ipt.front;
		if (nameChar(test))
		{
			opt.put(test);
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
        pout.put(test);
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
        pout.put(test);
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
/** eat up exact match and return true. */
bool match(ref ParseInput ipt, dstring ds)
{
    auto slen = ds.length;
    if (slen == 0)
        return false; // THROW EXCEPTION ?
    size_t ix = 0;
    while ((ix < slen) && !ipt.empty && (ipt.front == ds[ix]))
    {
        ix++;
        ipt.popFront();
    }
    if (ix==slen)
        return true;
    if (ix > 0)
        ipt.pushFront(ds[0..ix]);
    return false;
}
