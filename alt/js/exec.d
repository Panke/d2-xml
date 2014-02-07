module alt.js.exec;

import alt.js.script,alt.js.parse, alt.zstring;
import std.stdint, std.conv;
debug import std.stdio;
import std.xmlp.charinput;

/** 
	Not a binary code in traditional sense, because the two operands reg1_ and reg2_, 
	can point to an object or a string.  To make a linear binary code, need to have 
	a flattened JsValue, for any string and a flattened object, perhaps embedded in data segment. No idea what objects
	might be encoded yet.
*/
struct BinCode {
	JsValue	reg1_;
	JsValue	reg2_;
	BinOp	op_;

	this(JsValue* v1, JsValue *v2, BinOp op)
	{
		if (v1 !is null)
			reg1_ = *v1;
		else
			reg1_.zero();
		if (v2 !is null)
			reg2_ = *v2;
		else
			reg2_.zero();
		op_ = op;
	}
	// assign "index" register for jumps
	void setIndex(uintptr_t index)
	{
		reg1_.assign(index);
	}

	this(uintptr_t index, BinOp op)
	{
		reg1_.assign(index);
		op_ = op;
	}
}


enum BinOp {
	NOP,
	MAKE_VAR,
	ECALC_VAR, // pop calc stack top into var
	GET_VALUE,
	SET_VALUE,
	COPY_VALUE,
	EQUAL_OP,
	LESS_OP,
	GREATER_OP,
	JMP_ABS, // unconditional jump to index
	JMPP_ABS, // jump if condition flag is positive
	JMPZ_ABS, // jump if condition flag is zero
	JMPN_ABS, // jump if condition flag is negative
	PUSH_FRAME,
	POP_FRAME,
	EPUSH_VALUE, // push value on expression stack.
	ECALC_OP,	 // calculate with top of expression stack.
	ECOPY_OP,	// copy result of expression stack
	SET_FUNC,  // following code is a function, length of code given.

}




class ParseToken {
	ParseToken	next_;
	Tokjs		type_;
	JsValue	value_;
	uintptr_t	ix_;
}

struct ParseTokenList {
	ParseToken	start_;
	ParseToken	end_;
	uintptr_t	length_;

	static uintptr_t	freeLength_;
	static ParseToken	free_;


	uintptr_t length() const @property 
	{
		return length_;
	}
	bool empty() @property
	{
		return (start_ is null);
	}

	void appendList(ref ParseTokenList taken)
	{

		ParseToken test = taken.start_;
		if (test is null)
			return;

		end_ = taken.end_;
		if (start_ is null)
		{
			start_ = test;
			length_ = taken.length_;
		}
		else {
			start_.next_ = test;
			length_ += taken.length_;
		}
		taken.start_ = null;
		taken.end_ = null;
		taken.length_ = 0;
	}
	private void addFree(ParseToken f)
	{
		f.next_ = free_;
		free_ = f;
		free_.value_.zero();
		freeLength_++;
	}
	void popFront()
	{
		if (start_ is null)
			return;
		ParseToken next = start_.next_;
		addFree(start_);
		length_--;
		start_ = next;
		if (start_ is null)
			end_ = null;
	}

	ParseToken front() @property
	{
		return start_;
	}
	ParseToken getUnused(Tokjs tt, JsValue* data, uintptr_t ix)
	{
		ParseToken item = void;
		if (free_ is null)
			item = new ParseToken();
		else
		{
			item = free_;
			free_ = free_.next_;
			freeLength_--;
		}
		item.value_ =  (data is null) ? JsValue.init : *data;
		item.type_ = tt;
		item.ix_ = ix;
		return item;
	}
	void pushFront(ParseToken item)
	{
		if (start_ is null)
		{
			start_ = item;
			end_ = item;
			item.next_ = null;
		}
		else {
			item.next_ = start_;
			start_ = item;
		}
		length_++;
	}

	void pushBack(ParseToken item)
	{
		if (start_ is null)
		{
			start_ = item;
			end_ = item;
		}
		else {
			end_.next_ = item;
			end_ = item;
		}
		item.next_ = null;
		length_++;
	}
}

private auto BinaryOp(T)(Tokjs op, T d2, T d1)
{
	T result = void;
	switch(op)
	{
		case Tokjs.MULT:
			result = d1*d2;
			//debug writeln (d2, " * ", d1, " = ", result);
			break;
		case Tokjs.DIVIDE:
			result = d2/d1;
			//debug writeln (d2, " / ", d1, " = ", result);
			break;
		case Tokjs.PLUS:
			result = d2 + d1;
			//debug writeln (d2, " + ", d1, " = ", result);
			break;
		case Tokjs.MINUS:
			result = d2 - d1;
			//debug writeln (d2, " - ", d1, " = ", result);
			break;
		default:
			break;
	}	
	return result;
}

class AstroParse {
	Tokjs			 tt_;
	ParseToken		 token_;
	ParseTokenList	 list_;
	uintptr_t		 tokenCount_ = 0;
	uintptr_t		 tokenNumber_ = 0;
	ScriptParse		 tokenFeed_;
	Array!BinCode	 codes_;
	JsValue			 value_;
	Array!uintptr_t  jumpStack_;  // unresolved forwarded jump index to codes
	Array!Tokjs		 syntaxStack_;

	/// Get a fresh token from the parser
	void requireNextToken()
	{
		if (!tokenFeed_.empty)
		{
			tt_ = tokenFeed_.nextToken();
			tokenCount_++;
			tokenNumber_ = tokenCount_;

			if (tt_ < Tokjs.KEYWORDS_END)
			{
				value_.zero();
			}
			else if (tt_ >= Tokjs.VALUES)
			{
				switch(tt_)
				{
					case Tokjs.FLOAT:
						value_.assign(to!double(tokenFeed_.token()));
						break;
					case Tokjs.INT:
						value_.assign(to!long(tokenFeed_.token()));
						break;
					case Tokjs.ID:
						value_.assign(tokenFeed_.idup);
						value_.id.flags_ |= ObjFlags.ObjectId;
						break;
					case Tokjs.SGL_STRING:
						value_.assign(tokenFeed_.idup);
						break;
					case Tokjs.DBL_STRING:
						value_.assign(tokenFeed_.idup);
						break;
					default:
						break;
				}
			}
			else {
				value_.zero();
			}
		}
	}
	void pushFeed(ref ParseTokenList list)
	{
		list.pushBack(list.getUnused(tt_, &value_, tokenCount_));
	}
	// assignings expression to name
	void getExpression(JsValue* vname)
	{
		ParseTokenList	mylist;
		Array!Tokjs		pattern;

		for(;;)
		{
			popFeed(); // global feed.
			if (tt_ == Tokjs.SEMICOLON)
				break;
			pushFeed(mylist);
			pattern.put(tt_);
		}
		if (mylist.length > 0)
		{
			auto temp = pattern.toConstArray();
			if (temp.length==1)
			{
				ParseToken tok = mylist.front();
				bool ok = false;
				auto codesLength = codes_.length;
				if (codesLength > 0)
				{
					auto lastCode = &codes_.ptr[codesLength-1];

					if (lastCode.op_ == BinOp.MAKE_VAR)
					{
						lastCode.reg2_ = tok.value_;
						ok = true;
					}
				}
				if (!ok)
					codes_.put(BinCode(vname ,&tok.value_,BinOp.COPY_VALUE));
				mylist.popFront();
			}
			else {
				// postfix expression stacker
				int parenStack = 0;
				Array!Tokjs	opStack;

				while (!mylist.empty)
				{
					auto pt = mylist.front();
					auto op = pt.type_;
					if ((op >= Tokjs.OPERATORS) && (op < Tokjs.OPERATORS_END))
					{
						auto slen = opStack.length;
						if (slen==0)
						{
							opStack.put(op);
						}
						else {
							auto lastOp = opStack[slen-1];
							if (lastOp >= op)
							{
								codes_.put(BinCode(lastOp,BinOp.ECALC_OP));
								opStack[slen-1] = op;
							}
							else 
								opStack.put(op);
						}
					}	
					else if (op >= Tokjs.VALUES)
					{
						codes_.put(BinCode(&pt.value_,null, BinOp.EPUSH_VALUE));
					}
					mylist.popFront();
				}
				while(!opStack.empty)
				{
					codes_.put(BinCode(opStack.back(),BinOp.ECALC_OP));
					opStack.popBack();
				}
				codes_.put(BinCode(vname ,null,BinOp.ECOPY_OP));
			}

			checkEndStatement();
		}
	}

	// a statement ended with a ';'.  Check for stacked if and else.
	void checkEndStatement()
	{
		immutable slen = syntaxStack_.length;
		if (slen > 0)
		{
			auto top = syntaxStack_.back();
			switch(top)
			{
				case  Tokjs.R_IF:
					// if just got end of statement, and no else, then next statement is jump over point.
					popFeed();
					syntaxStack_.popBack();
					if (tt_ == Tokjs.R_ELSE)
					{
						setElseJump();
						syntaxStack_.put(Tokjs.R_ELSE);
					}
					else {
						setLastJump();
						pushFeed(list_);
					}
					break;
				case Tokjs.R_ELSE:
					syntaxStack_.popBack();
					setLastJump();
					break;

				case Tokjs.R_FOR:
					syntaxStack_.popBack();
					//setLastJump(); // no set last jump, next_statement check first.
					break;
				case Tokjs.R_WHILE:
					// Jump back to check condition
					syntaxStack_.popBack();
					auto jmpdone = jumpStack_.back(); // position of jmpz
					jumpStack_.popBack();
					auto jmpwhile = jumpStack_.back(); // position of conditional
					jumpStack_.popBack(); 
					codes_.put(BinCode(jmpwhile,BinOp.JMP_ABS)); // jump back to conditional
					codes_.ptr[jmpdone].setIndex(codes_.length); // jump forwards if done.
					break;
				default:
					break;
			}
		}
	}
	void setLastJump()
	{
		immutable jix = jumpStack_.back();
		codes_.ptr[jix].setIndex(codes_.length);
		jumpStack_.popBack();
	}

	void setElseJump()
	{
		immutable jlen = jumpStack_.length;
		if (jlen > 0)
		{
			immutable jmpElse = codes_.length;
			codes_.put(BinCode(0,BinOp.JMP_ABS)); // placing this before else code
			immutable jix = jumpStack_[jlen-1]; // index of jump over if code, to jump to else code
			codes_.ptr[jix].setIndex(codes_.length); // where else code will start.
			jumpStack_[jlen-1] = jmpElse; // where to jump over else
		}
	}

	void getAssign()
	{
		if (tt_ == Tokjs.ID)
		{
			codes_.put(BinCode(&value_, null, BinOp.MAKE_VAR));
			popFeed();
			if (tt_ == Tokjs.ASSIGN)
				getExpression(&value_);	
			else if (tt_ != Tokjs.SEMICOLON)
				throw getException(ErrorCode.NEED_SEMI);
		}
		else
			throw getException(ErrorCode.NEED_VARNAME);
	}
	
	void getFunction()
	{
		syntaxStack_.put(Tokjs.R_FUNCTION);	
		popFeed();
		
		if (tt_ != Tokjs.ID)
		{
			throw getException(ErrorCode.NEED_VARNAME);
		}	
		auto fname = value_.data.str_;
		popFeed();
		// expect comma separated VAR name list (a,b,c)
		if (tt_ != Tokjs.LPAREN)
			throw getException(ErrorCode.SYNTAX_ERROR);
		intptr_t commaCt = 0;
		intptr_t argCt = 0;
		auto funct = new JsFunction();

		for(;;)
		{
			popFeed();
			if (tt_ == Tokjs.RPAREN)
			{
				break;		
			}
			if (tt_ == Tokjs.ID)
			{
				if ( (commaCt == 0) && (argCt > 0))
					throw getException(ErrorCode.SYNTAX_ERROR);
				funct.argNames_.put(value_.data.str_);
				argCt++;
				commaCt = 0;
			}
			else if (tt_ == Tokjs.COMMA)
			{
				commaCt++;
				if (commaCt > 1)
					throw getException(ErrorCode.SYNTAX_ERROR);
			}
			else {
				throw getException(ErrorCode.SYNTAX_ERROR);
			}
		}
		// How to code for function?, and return value, stack ?
		auto execJump = codes_.length;

		codes_.put(BinCode(0,BinOp.JMP_ABS)); // Jump over the code, if not being called.
		funct.fnAddress_ = codes_.length; // start function execution here
		popFeed();
		if (tt_ != Tokjs.LBRACE)
		{
			throw getException(ErrorCode.SYNTAX_ERROR);
		}
		auto fvalue = JsValue(funct);
		codes_.put(BinCode(&fvalue, null,BinOp.PUSH_FRAME)); 
		foreach(name ; funct.argNames)
		{
			JsValue	vname(name);
			vname.id.flags_ |= ObjFlags.ObjectId;

			codes_.put(BinCode(&vname, null,BinOp.ECALC_VAR));
		}

		// the first thing a function does is pop its named arguments in order off the calc stack, into its
		// named variables as if declared var arg1 = pop1.

		auto stackpos = syntaxStack_.length;

		while (syntaxStack_.length >= stackpos)
		{
			popFeed();
			handFeed();
		}
		codes_.ptr[execJump].setIndex(codes_.length); 
	}

	void getFor()
	{
		// forloop is rewritten { assign_expr; LABEL_if (!test_expr) JUMP_endif else  statements;  next_expr;  JUMP_if; LABEL_endif; }
		// how to do that?   
		
		codes_.put(BinCode(null,null,BinOp.PUSH_FRAME));
		popFeed();
		if (tt_ != Tokjs.LPAREN)
			throw getException(ErrorCode.SYNTAX_ERROR);
		// get assign expression(s,s) TODO: ,
		popFeed();
		if (tt_ == Tokjs.R_VAR)
		{
			popFeed();
			getAssign();
		}
		else if (tt_ == Tokjs.ID)
		{
			auto vname = value_;
			popFeed();
			if (tt_ == Tokjs.ASSIGN)
				getExpression(&vname);	
			else
				throw getException(ErrorCode.SYNTAX_ERROR);
		}
		else if (tt_ == Tokjs.SEMICOLON)
		{
			/* empty assign_expr */
		}
		else {
			throw getException(ErrorCode.SYNTAX_ERROR);
		}
		auto labelIf = codes_.length;// REMEMBER LABEL_IF position.

		// get test expression 
		ParseTokenList	mylist;
		Array!Tokjs		pattern;

		for(;;)
		{
			popFeed();
			if (tt_ == Tokjs.SEMICOLON)
				break;
			pushFeed(mylist);
			pattern.put(tt_);
		}	
		
		if (mylist.length > 0)
		{
			codeIfCondition(mylist, pattern);
			while(!mylist.empty)
				mylist.popFront();
		}
		else  {
			// No jump to endif
		}
		// continue to end RPAREN
		// collect to end next_for
		for(intptr_t parenDepth = 0;;)
		{
			popFeed();
			if (tt_ == Tokjs.LPAREN)
			{
				parenDepth++;
			}
			else if (tt_ == Tokjs.RPAREN)
			{
				parenDepth--;
			}

			if(parenDepth < 0)
				break;
			pushFeed(mylist);
		}
		// 
		syntaxStack_.put(Tokjs.R_FOR);	
		
		auto trigger = syntaxStack_.length;
		// handle feed of for statements until pop
		while(syntaxStack_.length >= trigger)
		{
			if (popFeed())
				handFeed();
			else {
				throw getException(ErrorCode.SYNTAX_ERROR);
			}
		}
		
		list_.appendList(mylist);
		list_.pushBack(list_.getUnused(Tokjs.SEMICOLON, null, 0));
		// 
		syntaxStack_.put(Tokjs.R_FOR);	
		trigger = syntaxStack_.length;
		while(syntaxStack_.length >= trigger)
		{
			if (popFeed())
				handFeed();
			else {
				throw getException(ErrorCode.SYNTAX_ERROR);
			}
		}
		//jumpstack has position of JUMP_endif, and the position of LABEL_if 
		auto endifPos = jumpStack_.back();
		jumpStack_.popBack();

		codes_.put(BinCode(labelIf,BinOp.JMP_ABS));  // always jump back to if, after next.
		codes_.ptr[endifPos].setIndex(codes_.length); // jump here when loop is done. Also a destination for break.
		codes_.put(BinCode(null,null,BinOp.POP_FRAME)); // also gives an instruction to jump to.

	}

	void getWhile()
	{
		syntaxStack_.put(Tokjs.R_WHILE);
		jumpStack_.put(codes_.length); // jump back point for while loop
		getParenCondition();
	}

	void getIf()
	{
		syntaxStack_.put(Tokjs.R_IF);
		getParenCondition();
	}
	void popFrame()
	{
		auto slen = syntaxStack_.length;
		if (slen > 0)
		{	
			if (syntaxStack_.back() != Tokjs.LBRACE)
			{
				throw getException(ErrorCode.SYNTAX_ERROR);	
			}
			codes_.put(BinCode(null,null,BinOp.POP_FRAME));
			syntaxStack_.popBack();
		}
		else {
			throw getException(ErrorCode.SYNTAX_ERROR);	
		}
		checkEndStatement();		
	}

	void pushFrame()
	{
		syntaxStack_.put(Tokjs.LBRACE);
		codes_.put(BinCode(null,null,BinOp.PUSH_FRAME));
	}
	//TODO: only binary op tests handled.
	void codeIfCondition(ref ParseTokenList mylist, ref Array!Tokjs pattern)
	{
		auto plen = pattern.length;
		auto test = pattern.toArray();
		uintptr_t endpops = 0;
		for(;;)
		{
			if ((plen > 1) && (test[0]==Tokjs.LPAREN) && (test[plen-1]==Tokjs.RPAREN))
			{
				mylist.popFront();
				test = test[1..plen-1];
				plen -= 2;
				endpops += 1;
			}
			else 
				break;
		}
		if (test.length < pattern.length)
		{
			pattern = test;
			test = pattern.toArray();
		}
		if (pattern.length==3)
		{
			// value op value?
			auto tok = pattern[1];

			if (tok >= Tokjs.OPERATORS && tok < Tokjs.OPERATORS_END)
			{
				auto v1 = mylist.front.value_;
				mylist.popFront();
				mylist.popFront();
				auto v2 = mylist.front.value_;
				mylist.popFront();
				if (v1.id.type_ == ObjType.Undefined || (v2.id.type_ == ObjType.Undefined))
				{
					throw getException(ErrorCode.MISSING_ARGUMENT);
				}
				BinOp myop = BinOp.NOP;
				switch(tok)
				{
					case Tokjs.LESS:
						myop = BinOp.LESS_OP;
						break;
					case Tokjs.GREATER:
						myop = BinOp.GREATER_OP;
						break;
					case Tokjs.EQUAL:
						myop = BinOp.EQUAL_OP;
						break;
					default:
						break;
				}
				codes_.put(BinCode(&v1,&v2,cast(ushort)myop));
				jumpStack_.put(codes_.length);
				codes_.put(BinCode(0,BinOp.JMPZ_ABS)); 			}
		}
		// empty condition?
	}

	void getParenCondition()
	{
		ParseTokenList	mylist;
		Array!Tokjs		pattern;

		popFeed();
		if (tt_==Tokjs.LPAREN)
		{
			for(intptr_t parenDepth = 0;;)
			{
				popFeed();
				if (tt_ == Tokjs.LPAREN)
				{
					parenDepth++;
				}
				else if (tt_ == Tokjs.RPAREN)
				{
					parenDepth--;
				}				
				if (parenDepth < 0)
					break;
				pushFeed(mylist);
				pattern.put(tt_);
			}	
			codeIfCondition(mylist, pattern);
		}
	}

	bool popFeed()
	{
		try {
			if (list_.length > 0)
			{
				auto pt = list_.front;
				tt_ = pt.type_;
				value_ = pt.value_;
				tokenNumber_ = pt.ix_;
				list_.popFront();
				return true;
			}
			if (tokenFeed_.empty)
				return false;

			requireNextToken();
			return true;

		}
		catch(Exception e)
		{
			writeln(e.toString());
		}
		return  false;
	}

	
	// Any kind of recursive coding called from here
	void handFeed()
	{
		switch(tt_)
		{
			case Tokjs.R_VAR:
				popFeed();
				getAssign();
				break;
			case Tokjs.R_ELSE:
				// going to be error
				throw getException(ErrorCode.SYNTAX_ERROR);
				break;
			case Tokjs.R_FOR:
				getFor();
				break;
			case Tokjs.R_FUNCTION:
				getFunction();
				break;
			case Tokjs.R_WHILE:
				getWhile();
				break;
			case Tokjs.RBRACE:
				popFrame();
				break;
			case Tokjs.R_IF:
				getIf();
				break;
			case Tokjs.LBRACE:
				pushFrame();
				break;
			case Tokjs.ID:
				auto vname = value_;
				popFeed();
				if (tt_ == Tokjs.ASSIGN)
					getExpression(&vname);	
				else
					throw getException(ErrorCode.SYNTAX_ERROR);
				break;
			default:
				throw getException(ErrorCode.KEYWORD_UNSUPPORTED);
		}

	}

	void loop()
	{
		while(popFeed())
		{
			handFeed();
		}
	}


	void doParse(string s)
	{
		tokenFeed_ = new ScriptParse(new SliceFill!char(s));
		loop();
	}

}


void  astroExec(BinCode[] ops)
{
	intptr_t		testResult;
	uintptr_t		pc = 0;

	auto   opp = ops.ptr;
	JsTable					local;
	Array!JsTable			frames;
	JsObject				obj;
	Array!JsValue			stack;
	Array!JsValue			calc;
	
	JsValue*	val1;
	JsValue*	val2;

	void onExit()
	{
		calc.forget();
		val1.zero();
		val2.zero();
	}
	// update object value with calculation result

	void pushCalc(JsValue* v)
	{
		writeln("push ", *v);
		calc.put(v);

	}

	void assignCalc(JsValue* v)
	{
		auto nodeRef = local.getchain(*v);
		/// get a JsObject
		JsObject obj;

		if (nodeRef.valid())
		{

			auto objval = nodeRef.value;
			if (objval.id.type_ == ObjType.Class)
			{
				obj = cast(JsObject) objval.data.obj_;
			}
		}
		if (obj is null)
			throw getException(ErrorCode.VAR_ABSENT);

		if (calc.length==1)
		{
			obj.value = calc.ptr[0];
			writeln(*v, " = ", obj.value);
			calc.length = 0; // reset
		}
		else
			throw getException(ErrorCode.INVALID_RESULT);
	}

	void doCalc(Tokjs op)
	{
		auto slen = calc.length;
		if (slen < 2)
			throw getException(ErrorCode.TOOHARD_EXPRESSION);
		auto op2 = &calc.ptr[slen-2]; // lhs
		auto op1 = &calc.ptr[slen-1]; // rhs

		//conversions depend on operator
		immutable op1type = op1.id.type_;
		if (op1type == op2.id.type_)
		{
			if (op1type == ObjType.Double)
			{
				auto result = BinaryOp(op,op2.data.float_, op1.data.float_);	
				calc.popBack();
				calc.ptr[slen-2].assign(result);
				return;
			}
			else if (op1type == ObjType.Integer)
			{
				
				auto result = BinaryOp(op,op2.data.long_, op1.data.long_);	
				calc.popBack();
				calc.ptr[slen-2].assign(result);
				return;
			}
		}
		throw getException(ErrorCode.TOOHARD_EXPRESSION);
	}


	void pushFrame()
	{
		auto oldFrame = local;
		frames.put(local);
		local = new JsTable();
		local.chain(oldFrame);
	}

	void popFrame()
	{
		local = frames.back();
		frames.popBack();
	}
	
	/// if JsValue refers to object, get its value, else return
	JsValue* objectValue(JsValue* v)
	{
		if ((v.id.flags_ & ObjFlags.ObjectId)!=0)
		{
			auto var = local.getchain(*v);
			if (!var.valid)
				throw getException(ErrorCode.VAR_ABSENT);
			obj = cast(JsObject) var.value.data.obj_;
			return &obj.value_;
		}
		return v;
	}
	// get object variable name refers to.
	JsObject dereference(JsValue* v)
	{
		JsObject obj;
		if ((v.id.flags_ & ObjFlags.ObjectId)!=0)
		{
			auto var = local.getchain(*v);
			if (!var.valid)
				throw getException(ErrorCode.VAR_ABSENT);
			obj = cast(JsObject) var.value.data.obj_;
		}
		return obj;
	}


NEXT_CODE:
	while (pc < ops.length)
	{
		auto code = opp + pc;
		switch(code.op_)
		{
		case BinOp.ECALC_VAR:
			auto clen = calc.length;
			if (clen == 0)
				throw getException(ErrorCode.CALC_STACK_EMPTY);
			clen--;
			JsValue val = calc.ptr[clen];
			obj = new JsObject();
			obj.value = val;
			calc.length = clen;
			break;
		case BinOp.MAKE_VAR:
			//TODO: maybe do not need ObjName types
			if ((code.reg1_.id.flags_ & ObjFlags.ObjectId) == 0)
			{
				throw getException(ErrorCode.NOT_OBJECT_ID);
			}

			auto var = local.getlocal(code.reg1_);
			if (var.valid)
				throw getException(ErrorCode.VAR_EXISTS);

			if ((code.reg2_.id.flags_ & ObjFlags.ObjectId) != 0)
			{
				/// going to share a JsObject instance
				auto objRef = local.getchain(code.reg2_);
				if (objRef.valid)
				{
					local[code.reg1_] = objRef.value;
				}
				break;
			}
			// going to assign a value to a new object
			obj = new JsObject();
			obj.value = code.reg2_;
			JsValue objval;
			objval.assign(obj);
			local[code.reg1_] = objval;
			break;
		case BinOp.GET_VALUE:
		case BinOp.SET_VALUE:
			break;
		case BinOp.COPY_VALUE: // sets an object to a new value
			obj = dereference(&code.reg1_);
			if (obj !is null)
				obj.value = code.reg2_;
			break;
		case BinOp.GREATER_OP:
			val1 = objectValue(&code.reg1_);
			val2 = objectValue(&code.reg2_);
			testResult = (val1.opCmp(*val2) > 0 );
			break;
		case BinOp.LESS_OP:
			val1 = objectValue(&code.reg1_);
			val2 = objectValue(&code.reg2_);
			testResult = (val1.opCmp(*val2) < 0 );
			break;
		case BinOp.EQUAL_OP:
			val1 = objectValue(&code.reg1_);
			val2 = objectValue(&code.reg2_);
			testResult = (val1.opEquals(*val2));
			break;
		case BinOp.JMP_ABS:
			pc = cast(uintptr_t) code.reg1_.data.long_;
			goto NEXT_CODE;
		case BinOp.JMPZ_ABS:
			if (testResult==0)
			{
				pc = cast(uintptr_t) code.reg1_.data.long_;
				goto NEXT_CODE;
			}
			break;		
		case BinOp.JMPP_ABS:
			if (testResult>0)
			{
				pc = cast(uintptr_t) code.reg1_.data.long_;
				goto NEXT_CODE;
			}
			break;
		case BinOp.JMPN_ABS:
			if (testResult<0)
			{
				pc = cast(uintptr_t) code.reg1_.data.long_;
				goto NEXT_CODE;
			}
			break;
		case BinOp.PUSH_FRAME:
			pushFrame();
			break;
		case BinOp.POP_FRAME:
			popFrame();
			break;
		case BinOp.EPUSH_VALUE:
			val1 = objectValue(&code.reg1_);
			pushCalc(val1);
			break;
		case BinOp.ECALC_OP:
			doCalc(cast(Tokjs) code.reg1_.data.long_);
			break;
		case BinOp.ECOPY_OP:
			assignCalc(&code.reg1_);
			break;
		default:
			break;
		}
		pc += 1;
	}
}