module alt.js.parse;
/**
	Trying to create a subset of javascript. Not expecting to get too far.

*/

import std.stdint, std.ascii, std.conv, std.variant;
import std.xmlp.charinput;
import std.stdio;

import alt.textfeed, alt.zstring, alt.jschar;
import alt.js.script;

enum string sIF = "if";
enum string sELSE = "else";
enum string sDO = "do";
enum string sWHILE = "while";
enum string sFOR = "for";
enum string sBREAK = "break";
enum string sCONTINUE = "continue";
enum string sFUNCTION = "function";
enum string sRETURN = "return";
enum string sVAR = "var";
enum string sTRUE = "true";
enum string sFALSE = "false";
enum string sNULL = "null";
enum string sUNDEFINED = "undefined";
enum string sVOID = "void";
enum string sNEW = "new";
enum string sDELETE = "delete";
enum string sTYPEOF = "typeof";
enum string sINSTANCEOF = "instanceof";

immutable string[] sSymbols = [	
// keywords
	sIF, sELSE, sDO, sWHILE, sFOR, 
	sBREAK, sCONTINUE, sFUNCTION, sRETURN,
	sVAR, sTRUE, sFALSE,sNULL, sUNDEFINED,
	sVOID, sNEW, sDELETE, sTYPEOF, sINSTANCEOF, //19
// operator precedence
	".", "(", ")", "[", "]",
	"++", "--",  "~", "!", sDELETE, sNEW, sTYPEOF, sVOID,
	"*", "/", "%", //35
	"+", "-", "+", 
	"<<", "<<=", ">>", ">>>", ">>=",
	"<", "<=", ">", ">=", sINSTANCEOF,
	"==", "!=", "===", "!==", //52
	"&", "^", "|", 
	"&&", "||",	
	"=", "&=", "|=", "^=", "+=", "-=",
	",",
// other
	"{","}",";" // 67
];

enum Tokjs {
    // reserved words
	KEYWORDS,
	R_IF = KEYWORDS,
    R_ELSE,
    R_DO,
    R_WHILE,
    R_FOR,
    R_BREAK,
    R_CONTINUE,
    R_FUNCTION,
    R_RETURN,
    R_VAR,
    R_TRUE,
    R_FALSE,
    R_NULL,
    R_UNDEFINED,
	OPERATOR_WORDS,
	R_VOID = OPERATOR_WORDS,
    R_NEW,
	R_DELETE,
	R_TYPEOF,
	R_INSTANCEOF, //19
	KEYWORDS_END,
	OPERATOR_WORDS_END = KEYWORDS_END,

	// operators, should be precedential
	OPERATORS = KEYWORDS_END,
    DOT = OPERATORS,
	LPAREN,
	RPAREN,
	LSQUARE,
	RSQUARE,
	// unary
    PLUSPLUS,
    MINUSMINUS,
	TILDE,
	NOT,
	DELETEOP,
	NEWOP,
	TYPEOF,
	VOIDOP,
	// binary ops 1
	MULT,
	DIVIDE,
	MODULO,
	// binary ops 2
	PLUS,
	MINUS,
	CONCAT,
	// SHIFTS
    LSHIFT,
    LSHIFTEQUAL,
    RSHIFT,
    RSHIFTUNSIGNED,
    RSHIFTEQUAL,
	// ordering ops

	LESS,
    LEQUAL,
	GREATER,
    GEQUAL,
	INSTANCEOF,
	// Equality

	EQUAL,
	NEQUAL,
    TYPEEQUAL,
    NTYPEEQUAL,
	// bit ops
	AND,
	XOR,
	OR,

	// boolean shortcut ops
	ANDAND,
	OROR,

	// assign ops
	ASSIGN,
    ANDEQUAL,
    XOREQUAL,
    OREQUAL,
	PLUSEQUAL,
    MINUSEQUAL,   
	
	// Multi evaluate, argument seperator,
	COMMA,
	OPERATORS_END,
	SYMBOLS = OPERATORS_END,
	LBRACE = SYMBOLS,
	RBRACE,
	SEMICOLON,
	SYMBOLS_END,
	// values or identifier
	VALUES = SYMBOLS_END,
    ID = VALUES,
    INT,
	HEX,
    FLOAT,
    SGL_STRING,
	DBL_STRING,
	VALUES_END,
}


enum Varjs {
    UNDEFINED   = 0,
    FUNCTION    = 1,
    OBJECT      = 2,
    ARRAY       = 4,
    DOUBLE      = 8,  // floating point double
    INTEGER     = 16, // integer number
    STRING      = 32, // string
    NULL        = 64, // it seems null is its own data type

    NATIVE      = 128, // to specify this is a native function
    NUMERICMASK = NULL |
		DOUBLE |
		INTEGER,
    VARTYPEMASK = DOUBLE |
		INTEGER |
		STRING |
		FUNCTION |
		OBJECT |
		ARRAY |
		NULL,

};

enum ErrorCode {
	EMPTY = 1,
	EMPTY_COMMENT, 
	EMPTY_ID,
	EMPTY_NUMBER,
	EMPTY_QUOTE,
	BAD_HEX,
	BAD_NUMBER,
	BAD_CHARACTER,
	CALC_STACK_EMPTY,
	NEED_VARNAME,
	NEED_SEMI,
	KEYWORD_UNSUPPORTED,
	MISSING_ARGUMENT,
	SYNTAX_ERROR,
	VAR_EXISTS,
	VAR_ABSENT,
	TOOMANY_RPAREN,
	TOOHARD_EXPRESSION,
	INVALID_RESULT,
	NOT_VALUE_TYPE,
	NOT_STRING_KEY,
	NOT_OBJECT_ID,
	NONSENSE,
}


pure Tokjs matchID(const(char)[] id)
{
	switch(id)
	{
		case sIF: return Tokjs.R_IF;
		case sELSE: return Tokjs.R_ELSE;
		case sDO: return Tokjs.R_DO;
		case sWHILE: return Tokjs.R_WHILE;
		case sFOR: return Tokjs.R_FOR;
		case sBREAK: return Tokjs.R_BREAK;
		case sCONTINUE: return Tokjs.R_CONTINUE;
		case sFUNCTION: return Tokjs.R_FUNCTION;
		case sRETURN: return Tokjs.R_RETURN;
		case sVAR: return Tokjs.R_VAR;
		case sTRUE: return Tokjs.R_TRUE;
		case sFALSE: return Tokjs.R_FALSE;
		case sNULL: return Tokjs.R_NULL;
		case sUNDEFINED: return Tokjs.R_UNDEFINED;
		case sNEW: return Tokjs.NEWOP;
		case sDELETE: return Tokjs.DELETEOP;
		case sVOID: return Tokjs.VOIDOP;
		case sTYPEOF: return Tokjs.TYPEOF;
		case sINSTANCEOF: return Tokjs.INSTANCEOF;
		default:
			return Tokjs.ID;
			break;
	}
}
/// VM done with JsScript objects, for now.
class JsException : Exception {
	this(string s)
	{
		super(s);
	}
}

package Exception getException(uintptr_t code)
{
	return new JsException(getErrorCodeMsg(code));
}

class ScriptParse : TextFeed {
	Array!char	token_;
	ulong		tokenStart_;
	Tokjs		type_;

	Tokjs nextToken()
	{
		popToken();
		return type_;
	}

	auto token() @property
	{
		return (type_ >= Tokjs.VALUES && type_ < Tokjs.VALUES_END) ? token_.toConstArray() : null;
	}

	string idup() @property
	{
		auto result = token();
		return (result is null) ? null : result.idup;
	}

	this(DataFiller df)
	{
		super(df);
		pumpStart();
	}
	/// go till end of line or empty
	void skipLine()
	{
		for(;;)
		{
			popFront();
			if (empty)
				break;
			if (front == '\n')
			{
				popFront();
			}
		}			
	}
	// presume front contains first quote character
	bool isQuoted()
	{
		auto quoteChar = front;
		switch(quoteChar)
		{
		case '\'':
			type_ = Tokjs.SGL_STRING;
			break;
		case '\"':
			type_ = Tokjs.DBL_STRING;
			break;
		default:
			return false;
		}
		popFront();
		if (empty)
			throw getException(ErrorCode.EMPTY_QUOTE);
		for(;;)
		{
			if (empty)
				throw getException(ErrorCode.EMPTY_QUOTE);
			if (front != quoteChar)
				token_.put(front);
			else
			{
				popFront();
				break;
			}
			popFront();
		}
		return true;
	}
	/// in comment, skip till terminates, exception on empty
	void skipBlockComment()
	{
		for(;;)
		{
			popFront();
			if (empty)
				throw getException( ErrorCode.EMPTY_COMMENT );
			while (front=='*')
			{
				popFront();
				if (empty)
					throw getException( ErrorCode.EMPTY_COMMENT );
				if (front == '/')
				{
					popFront();
					return;
				}
			}
		}
	}
	/// TODO: escaped Unicode characters
	void collectID()
	{
		token_.length = 0;
		token_.put(front);
		tokenStart_ = sourceRef();
		for(;;)
		{
			popFront();
			if (empty)
				throw getException(ErrorCode.EMPTY_ID);
			if (isIDNext(front))
				token_.put(front);
			else
				break;
		}
	}
	void collectHex()
	{
		uintptr_t digits = 0;
		for(;;)
		{
			if (isHexDigit(front))
			{
				digits++;
				token_.put(front); 
			}
			else
				break;
			popFront();
			if (empty)
				throw getException(ErrorCode.EMPTY_NUMBER);
		}
		if (digits == 0)
			throw getException(ErrorCode.BAD_HEX);

		type_ = Tokjs.HEX;
	}
	Tokjs collectDecimal(int recurse = 0 )
	{
		int   digitct = 0;
		bool  done = empty;
		bool  decPoint = false;
		for(;;)
		{
			if (done)
				break;
			auto test = front;
			switch(test)
			{
				case '-':
				case '+':
					if (digitct > 0)
					{
						done = true;
					}
					break;
				case '.':
					if (!decPoint)
						decPoint = true;
					else
						done = true;
					break;
				default:
					if (!std.ascii.isDigit(test))
					{
						done = true;
						if (test == 'e' || test == 'E')
						{
							// Ambiguous end of number, or exponent?
							if (recurse == 0)
							{
								token_.put(cast(char)test);
								popFront();
								if (collectDecimal(recurse+1)==Tokjs.INT)
									return Tokjs.FLOAT;
								else
									throw getException(ErrorCode.BAD_NUMBER);
							}
							// assume end of number
						}
					}
					else
						digitct++;
					break;
			}
			if (done)
				break;
			token_.put(cast(char)test);
			popFront();
			done = empty;
		}
		if (decPoint)
			return Tokjs.FLOAT;
		if (digitct == 0)
			throw getException(ErrorCode.BAD_NUMBER);
		return Tokjs.INT;
	};

	void checkNextChar()
	{
		popFront();
		if (empty)
			throw getException(ErrorCode.EMPTY);
	}

	void collectNumber()
	{
		bool isHex = false;
		token_.length = 0;

        if (front=='0') 
		{
			popFront();
			if (empty)
				throw getException(ErrorCode.EMPTY_NUMBER);
			if (front=='x')
			{
				isHex = true;
				popFront();
				if (empty)
					throw getException(ErrorCode.EMPTY_NUMBER);
				collectHex();
				return;
			}
			else {
				pushFront('0');
			}
		}
		type_ = collectDecimal(0);
	}
	/// skip whitespace and comment till something good turns up or empty
	private void popToken()
	{
		if (empty || (munchSpace() && empty))
			throw getException( ErrorCode.EMPTY );
		if (front == '/')
		{
			popFront();
			if (empty)
				throw getException( ErrorCode.EMPTY );
			if (front == '/')
				skipLine();
			if (front == '*')
				skipBlockComment();
			else  {
				type_ = Tokjs.DIVIDE;
				return;
			}
		}
		else if (isIDStart(front))
		{
			collectID();
			auto temp = token_.toConstArray();
			type_ = matchID(temp);
		}
		else if (isDigit(front))
		{
			collectNumber();
		}
		else if (!isQuoted())
		{
			// operators
			auto first = front;
			switch(first)
			{
			case '{':
				type_ = Tokjs.LBRACE;
				checkNextChar();
				break;
			case '}':
				type_ = Tokjs.RBRACE;
				popFront();
				break;
			case '(':
				type_ = Tokjs.LPAREN;
				checkNextChar();
				break;
			case ')':
				type_ = Tokjs.RPAREN;
				checkNextChar();
				break;
			case '.':
				type_ = Tokjs.DOT;
				checkNextChar();
				break;
			case ',':
				type_ = Tokjs.COMMA;
				checkNextChar();
				break;
			case ';':
				type_ = Tokjs.SEMICOLON;
				popFront();
				break;
			case '*':
				type_ = Tokjs.MULT;
				checkNextChar();
				break;
			case '=':
				type_ = Tokjs.ASSIGN;
				checkNextChar();
				if(front=='=')
				{
					type_ = Tokjs.EQUAL;
					checkNextChar();
					if (front=='=')
					{
						type_ = Tokjs.TYPEEQUAL;
						checkNextChar();
					}
				}
				break;
			case '!':
				type_ = Tokjs.NOT;
				checkNextChar();
				if(front=='=')
				{
					type_ = Tokjs.NEQUAL;
					checkNextChar();
					if (front=='=')
					{
						type_ = Tokjs.NTYPEEQUAL;
						checkNextChar();
					}
				}
				break;
			case '<':
				type_ = Tokjs.LESS;
				checkNextChar();
				if(front=='=') {
					type_ = Tokjs.LEQUAL;
					checkNextChar();
				}
				else if (front=='<')
				{
					type_ = Tokjs.LSHIFT;
					checkNextChar();
					if (front=='=')
					{
						type_ = Tokjs.LSHIFTEQUAL;
						popFront();
					}
				}
				break;
			case '>':
				type_ = Tokjs.GREATER;
				checkNextChar();
				if(front=='=') {
					type_ = Tokjs.GEQUAL;
					checkNextChar();
				}
				else if (front=='>')
				{
					type_ = Tokjs.RSHIFT;
					checkNextChar();
					if (front=='=')
					{
						type_ = Tokjs.RSHIFTEQUAL;
						checkNextChar();
					}
					else if (front=='>')
					{
						type_ = Tokjs.RSHIFTUNSIGNED;
						checkNextChar();
					}
				}
				break;
			case '+':
				type_ = Tokjs.PLUS;
				checkNextChar();
				if (front=='=')
				{
					type_ = Tokjs.PLUSEQUAL;
					checkNextChar();
				}
				else if (front=='+')
				{
					type_ = Tokjs.PLUSPLUS;
					checkNextChar();
				}
				break;
			case '-':
				type_ = Tokjs.MINUS;
				checkNextChar();
				if (front=='=')
				{
					type_ = Tokjs.MINUSEQUAL;
					checkNextChar();
				}
				else if (front=='-')
				{
					type_ = Tokjs.MINUSMINUS;
					checkNextChar();
				}
				break;
			case '&':
				checkNextChar();
				type_ = Tokjs.AND;
				if (front=='=') {
					type_ = Tokjs.ANDEQUAL;
					checkNextChar();
				}
				else if (front=='&')
				{
					type_ = Tokjs.ANDAND;
					checkNextChar();
				}
				break;
			case '|':
				type_ = Tokjs.OR;
				checkNextChar();
				if (front=='|')
				{
					type_ = Tokjs.OROR;
					checkNextChar();
				}
				else if (front=='=')
				{
					type_ = Tokjs.OREQUAL;
					checkNextChar();
				}
				break;
			case '^':
				type_ = Tokjs.XOR;
				checkNextChar();
				if (front=='=')
				{
					type_ = Tokjs.XOREQUAL;
					checkNextChar();
				}
				break;
			default:
				throw getException(ErrorCode.BAD_CHARACTER);
				break;
			}
		}
	}


}

/+
	Inaccurate, to be fixed.
	Program = Block
	Block = blockstart Statement [Statement] blockend
	Statement = Block | VarDeclaration | Assignment | function |  LoopBlock
	LoopBlock = if | for | while
	VarDeclaration = var ID
	Assignment = ID = Expression
	Expression = function | arithmetic | stringExpression | objectValue
	if = "if" (condition) Statement ["else"] Statement
	while = "while (condition) Statement
	for = blockstart forinit while( forcondition)  Statement forstep blockend
	blockstart = {
	blockend = }
	function declaration = ID( ArgumentIDs ) { Statements }
	Expression = AddExpression | MulExpression | unaryOp
	MulExpression = function | Expression | ObjectValue
	AddExpression = MulExpression op MulExpression
	
	StringExpression = funtion | String op String
	ObjectValue = ID.key | ID [key]
	


+/




unittest {
	

	string test1 = "var a = 5; if (a==5) a=4; else a=3;";
	string test2 = "{ var a = 4; var b = 1; while (a>0) { /*b = b * 2; */ a = a - 1; } var c = 5; }";
	string test3 = "{ var b = 1; for (var i=0;i<4;i=i+1) b = b * 2; }";
	string test4 = "function myfunc(x, y) { return x + y; } var a = myfunc(1,2); print(a);";

	bool passed = true;

	Array!char	outbuf;
	void doParse(string sbit)
	{
		auto p = new ScriptParse(new SliceFill!char(sbit));
		bool ws = false;
		
		try {
			outbuf.length = 0;
			while(!p.empty)
			{
				immutable tt = p.nextToken();
				if (tt < Tokjs.KEYWORDS_END)
				{
					if (ws)
						outbuf.put(' ');
					outbuf.put(sSymbols[tt-Tokjs.KEYWORDS]);
					ws = true;
				}
				else if (tt >= Tokjs.VALUES)
				{
					if (ws)
						outbuf.put(' ');
					auto temp = p.token();
					outbuf.put(temp);
					ws = true;
				}
				else { // operator
					if(tt >= Tokjs.SYMBOLS_END)
						break;
					outbuf.put(sSymbols[tt-Tokjs.KEYWORDS]);
					ws = false;
				}
			}
			writeln(outbuf.toArray);
		}
		

		catch(Exception e)
		{
			passed = false;
			writeln("Error: ",p.getErrorContext());
		}
	}
	doParse(test1);
	doParse(test2);
	doParse(test3);
	doParse(test4);
	assert(passed);

}
