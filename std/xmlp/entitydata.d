module std.xmlp.entitydata;

import std.conv;
import std.xmlp.nodetype;

struct ExternalID
{
    string publicId_;
    string systemId_;
}



/// Keeps track of value and processing status of external or internal entities.
class EntityData
{
    enum
    {
        Unknown, Found, Expanded, Failed
    }
    int				status_;				// unknown, found, expanded or failed
    string			name_;				// key for AA lookup
    string			value_;				// processed value
    ExternalID		src_;				// public and system id
    EntityType		etype_;				// Parameter, General or Notation?
    RefTagType		reftype_;			// SYSTEM or what?

    bool			isInternal_;	// This was defined in the internal subset of DTD

    string			encoding_;		// original encoding?
    string			version_;	//
    string			ndataref_;		// name of notation data, if any

    //Notation		ndata_;         // if we are a notation, here is whatever it is
    string			baseDir_;		// if was found, where was it?
    EntityData		context_;		// if the entity was declared in another entity

    this(string id, EntityType et)
    {
        name_ = id;
        etype_ = et;
        status_ = EntityData.Unknown;
    }

	@property void value(const(char)[] s)
	{
		value_ = to!string(s);
	}
	@property string value()
	{
		return value_;
	}
}


version (CustomAA)
{
    import alt.arraymap;
    alias HashTable!(string, EntityData)	EntityDataMap;

}
else
{
    alias AssociativeArray!(string, EntityData)	EntityDataMapTpl;
    alias EntityData[string]    EntityDataMap;

}


