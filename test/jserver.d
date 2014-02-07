/*
D listener written by Christopher E. Miller
This code is public domain.
You may use it for any purpose.
This code has no warranties and is provided 'as-is'.
*/

import std.conv, std.socket, std.stdio;
import std.xmlp.linkdom, std.xmlp.parseitem, std.xmlp.coreprint;
import std.xmlp.charinput, std.xmlp.domparse,  std.xmlp.subparse, std.xmlp.xmlparse;
import xmlErr = std.xmlp.error;
import std.variant;
import std.concurrency;
import std.stdint;
import alt.buffer, std.xmlp.inputencode, alt.jabber;
/// make an InputRange, that blocks until more data is read.
/// popFront blocks until recieves another block of data.


string streamNS = "http://etherx.jabber.org/stream";
string streamAlias = "stream";	
string streamPrefix = "stream:";
string toAttr = "to";
string versAttr = "version";
string nsPrefix = "xmlns:";
string xmlns = "xmlns";
string jabberPrefix = "jabber:";
string client = "client";


int main(char[][] args)
{
    ushort port;

    if (args.length >= 2)
        port = to!ushort(args[1]);
    else
        port = 5222;

    Socket listener = new TcpSocket;
    assert(listener.isAlive);
    listener.blocking = false;
    listener.bind(new InternetAddress(port));
    listener.listen(10);
    writefln("Listening on port %d.", port);

    const int MAX_CONNECTIONS = 60;
    SocketSet sset = new SocketSet(1); // Room for listener.
    Socket[] reads;

    for (;; sset.reset())
    {
        sset.add(listener);

        Socket.select(sset, null, null);

        int i;

        if (sset.isSet(listener)) // connection request
        {
            Socket sn;
            try
            {
                if (JabberThread.runningCount() < MAX_CONNECTIONS)
                {
                    sn = listener.accept();
					string fromAddr = sn.remoteAddress().toString();

                    writefln("Connection from %s established.", fromAddr);
                    assert(sn.isAlive);
                    assert(listener.isAlive);
					sn.setKeepAlive(60,1);
                    auto job = new Jabber(sn,fromAddr);
					auto jt = new JabberThread(job);
					jt.start();
					
                    writefln("\tAdded thread %d",JabberThread.runningCount());
                }
                else
                {
                    sn = listener.accept();
                    writefln("Rejected connection from %s; too many connections.", sn.remoteAddress().toString());
                    assert(sn.isAlive);

                    sn.close();
                    assert(!sn.isAlive);
                    assert(listener.isAlive);
                }
            }
            catch (Exception e)
            {
                writefln("Error accepting: %s", e.toString());

                if (sn)
                    sn.close();
            }
        }
    }

    return 0;
}