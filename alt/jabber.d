module alt.jabber;

import std.xmlp.linkdom, std.xmlp.coreprint, std.xmlp.subparse, std.xmlp.parseitem, std.xmlp.domparse;
import std.xmlp.charinput, std.xmlp.xmlparse, std.concurrency;

import std.socket, std.stream, std.socketstream;
import std.conv, std.variant;

alias std.conv.text concat;

import core.thread;
import alt.buffer;
/**
	Shared jabber strings and functions, for client and server jabber.
	Simple toy jabber client - server feasibility example
	Sockets usage or implementation not robust.
	@Author: Michael Rynn
	@Date: 2012
*/

debug = JABBER;

debug(JABBER)
{
	import std.stdio;
}
/// Without a delay of Thread.sleep, at least greater than 25 ms, the client example will eventually do socket.ERROR on a read.
/// Why?
version = littleSleep; 
version(littleSleep)
{
	private enum delayms = 50;
}
const string streamNS = "http://etherx.jabber.org/streams";
const string streamAlias = "stream";	
const string streamPrefix = "stream:";
const string toAttr = "to";
const string fromAttr = "from";
const string idAttr = "id";
const string versAttr = "version";
const string nsPrefix = "xmlns:";
const string xmlns = "xmlns";
const string jabberPrefix = "jabber:";
const string client = "client";
const string jbMessage = "message";
const string jbBody = "body";

/// Jabber server thread.
/// Use core.thread, because std.concurrency is limited to passing immutable data, and sockets are not immutable data
class JabberThread : Thread {
private:
	__gshared	uintptr_t	gsJabberCount;
	__gshared	JabberThread[Tid]	gsRunning;

	Jabber	jb_;


	synchronized static void removeThread(Tid id)
	{
		gsRunning.remove(id);
	}
	synchronized static void addThread(JabberThread jt, Tid id)
	{
		gsRunning[id] = jt;
	}
public:
	static uintptr_t  runningCount()
	{
		return gsRunning.length;
	}

	this(Jabber jb)
	{
		jb_ = jb;
		super(&run);
	}
private:

	void cleanup()
	{
		jb_.close();
		removeThread(thisTid);
		debug(JABBER) writeln("Sessions left = ", runningCount());
	}

	void run()
	{
		addThread(this,thisTid);

		scope(exit)
			cleanup();
		jb_.getRemoteStart(); // get client document start;
		jb_.sendServerStart("jabber.dserver.com"); // send server document start
		while (jb_.getRemoteMessage())
		{
			
		}
		
	}

}


/// Jabber class used by client and server.
class Jabber {
	/// client and server document
	Document hereDoc_; // what is sent from here		
	Document remoteDoc_; // what is received
	string fromId_;
	string toId_;
	string  domain_;
	ushort	port_;
	Socket	sock_;
	Buffer!ElementNS	messageLog_; // TODO: ordered sequence of here and remote element messages
	XmlPrintOptions printOptions_;
	
	DocumentBuilder	remoteBob_; // build what is received
	bool isServer_;
	string remoteAddress_;
	Buffer!char		sendBuffer_;


	/// client setup
	this(string domain, ushort port)
	{
		domain_ = domain;
		port_ = port;
		printOptions_.putDg = &writeSocket;
	}
	/// server setup
	this(Socket s, string remoteAddr)
	{
		sock_ = s;
		isServer_ = true;
		remoteAddress_ = remoteAddr;
		printOptions_.putDg = &writeSocket;
	}

	void close()
	{
		if (sock_ !is null)
		{
			sock_.close();
			sock_ = null;
		}
	}

	~this()
	{
		close();
	}
	
	void sendCloseDocument()
	{
		auto de = hereDoc_.getDocumentElement(); // which one it is doesn't matter
		auto tp = XmlPrinter(printOptions_);

		tp.putEndTag(de.getNodeName());
		dispatchSend();
	}

	void sendMessage(string msg)
	{
		// construct and attach element
		auto elem = cast(ElementNS) hereDoc_.createElementNS(null,jbMessage);
		auto de = hereDoc_.getDocumentElement();
		de.appendChild(elem);
		elem.setAttribute(fromAttr,fromId_);
		elem.setAttribute(toAttr,domain_);
		auto bod = cast(ElementNS) hereDoc_.createElementNS(null,jbBody);
		elem.appendChild(bod);
		bod.appendChild(new Text(msg));

		// send it
		printMessage(elem);
	}

	bool handleRemoteMessage(ElementNS msg)
	{
		writeln("Got ", msg.getNodeName());
		// this dumb server can only echo!
		if (isServer_)
		{
			version (littleSleep) Thread.sleep(dur!("msecs")( delayms ) ); 
			printMessage(msg);
		}
		return true;
	}

	/// DocumentBuilder is at level 1. parse anything.
	bool getRemoteMessage()
	{
		// A small sleep seems to prevent error on socket read on client. Why?
		version (littleSleep) Thread.sleep(dur!("msecs")( delayms ) ); 
		remoteBob_.buildUntil(1);	
		writeln("parsed message");
		auto level = remoteBob_.stackLevel();
		if (level == 1)
		{
			auto msgElement = cast(ElementNS) remoteBob_.getParent();
			msgElement = cast(ElementNS) msgElement.getLastChild();
			writeln("text: ", msgElement.text());
			return handleRemoteMessage(msgElement);
		}
		else {
			writeln("Got close message");
			sendCloseDocument();
			version (littleSleep) Thread.sleep(dur!("msecs")( delayms ) ); 
			return false;
		}
	}
	/// setup a document, and documentbuilder to receive start document from server
	bool getRemoteStart()
	{
		/// setup a DocumentBuilder, using socket
		/// get it up to level 1 parse, and get messages from client as events to respond to
		/// then abandon!
		auto df = new SocketFill(sock_);
		auto pfrag = new XmlParser(df, 1.0);
		// Jabber specific hack. Tell parser to fragment parse at start element depth of 1
		pfrag.setParameter("fragment",Variant(true));

		remoteDoc_ = new Document();
		remoteBob_ = new DocumentBuilder(pfrag,remoteDoc_);
		XmlReturn ret;
		
		try {
			while(pfrag.parse(ret))
			{
				switch(ret.type)
				{
					case XmlResult.TAG_START:
						remoteBob_.pushTag(ret);
						auto level = remoteBob_.stackLevel;
						auto msgElement = cast(ElementNS) remoteBob_.getParent();
						if (level == 1)
						{
							string idname = isServer_ ? toAttr : idAttr;
							debug(JABBER) writeln("open document from ", msgElement.getAttribute(idname));
							return true;
						}
						break;
					default: //TODO: stuff
						break;

				}
			}
		}
		catch (Exception e)
		{
			writeln("Server start document error ", e.toString());
			
		}
		return false;
	}

	void dispatchSend()
	{
		if (sendBuffer_.length > 0)
		{
			auto data = sendBuffer_.idup;
			sock_.send(data);
			sendBuffer_.length = 0;
			
			writeln("sent: ", data);
		}
	}

	void writeSocket(const(char)[] s)
	{
		sendBuffer_.put(s);
	}
	/// this object is on the server, so 
	void serverSocket(Socket s)
	{
		sock_ = s;
	}
	/// client starts connection to server.
	void clientConnect()
	{
		sock_ = new TcpSocket(new InternetAddress(domain_, port_));
		sock_.setKeepAlive(60,1);
	}

	private void printMessage(ElementNS e)
	{
		auto tp = XmlPrinter(printOptions_);
		printElement(e, tp);
		dispatchSend();
	}

	private void printStartTag(ref XmlPrinter tp, Element e)
	{
		string tag = e.getTagName();
		AttributeMap smap;
		if (e.hasAttributes())
			smap = toAttributeMap(e);
		tp.putStartTag(tag, smap, false);
		dispatchSend();
	}
	/// clientDoc_ , originated from client or server q
	ElementNS makeStartDocument()
	{
		hereDoc_ = new Document();
		ElementNS ns = cast(ElementNS) hereDoc_.createElementNS(streamNS, concat(streamPrefix,streamAlias));
		hereDoc_.appendChild(ns); // sets DocElement

	
		ns.setAttribute(versAttr, "1.0");
		ns.setAttribute(concat(nsPrefix,streamAlias),streamNS);
		ns.setAttribute(xmlns,concat(jabberPrefix, client));

		return ns;
	}

	void sendServerStart(string id)
	{
		ElementNS ns = makeStartDocument();

		ns.setAttribute(idAttr, "server.me");	

		sendStartDocument(ns);
		writeln("Start sent");
	}

	void sendStartDocument(ElementNS ns)
	{
		auto tp = XmlPrinter(printOptions_);

		AttributeMap xmldec;

		xmldec["version"] = "1.0";

		printXmlDeclaration(xmldec, &writeSocket);
		printStartTag(tp, ns);
		dispatchSend();
	}

	void sendClientStart()
	{
		if (sock_ is null)
			clientConnect();
		ElementNS ns = makeStartDocument();

		ns.setAttribute(toAttr, domain_);	

		sendStartDocument(ns);
	}
}
