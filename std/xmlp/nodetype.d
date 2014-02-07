module std.xmlp.nodetype;

enum NodeType
{
    None = 0,
	Element_node = 1,
	Attribute_node = 2,
	Text_node = 3,
	CDATA_Section_node = 4,
	Entity_Reference_node = 5,
	Entity_node = 6,
	Processing_Instruction_node = 7,
	Comment_node = 8,
	Document_node = 9,
	Document_type_node = 10,
	Document_fragment_node = 11,
	Notation_node = 12
};

enum EntityType { Parameter, General, Notation }

enum RefTagType { UNKNOWN_REF, ENTITY_REF, SYSTEM_REF, NOTATION_REF}

/// Kind of default value for attributes
enum AttributeDefault
{
    df_none,
    df_implied,
    df_required,
    df_fixed
}

/** Distinguish various kinds of attribute data.
The value att_enumeration means a choice of pre-defined values.
**/
enum AttributeType
{
    att_cdata,
    att_id,
    att_idref,
    att_idrefs,
    att_entity,
    att_entities,
    att_nmtoken,
    att_nmtokens,
    att_notation,
    att_enumeration
}