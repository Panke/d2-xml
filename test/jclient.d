/*
HTMLget written by Christopher E. Miller
This code is public domain.
You may use it for any purpose.
This code has no warranties and is provided 'as-is'.
*/

module jclient;

// debug = HTMLGET;

import std.string, std.conv, std.stream, std.stdio;
import std.socket, std.socketstream, std.random;

import std.xmlp.linkdom, std.xmlp.parseitem, std.xmlp.coreprint, alt.jabber;
import std.variant, core.thread, std.datetime, std.stdint;

alias std.conv.text concat;

void getDomainPort(string url, ref string domain, ref ushort port)
{
	int i;
    i = indexOf(url, '#');

    if (i != -1) // Remove anchor ref.
        url = url[0 .. i];


    i = indexOf(url, "://");

    if (i != -1)
    {
        if (icmp(url[0 .. i], "http"))
            throw new Exception("http:// expected");
        url = url[i + 3 .. $];
    }
    i = indexOf(url, '/');
    if (i == -1)
    {
        domain = url;
        url = "/";
    }
    else
    {
        domain = url[0 .. i];
        url = url[i .. url.length];
    }

    i = indexOf(domain, ':');

    if (i == -1)
    {
        port = 5222; // Default HTTP port.
    }
    else
    {
        port = to!ushort(domain[i + 1 .. domain.length]);
        domain = domain[0 .. i];
    }

}


void runClient()
{
	auto domain = "127.0.0.1";
	ushort port = 5222;


	Jabber jsess = new Jabber(domain, port);
	jsess.fromId_ = "me@jabber.client";
	jsess.sendClientStart();

	jsess.getRemoteStart();
	auto i = uniform(0, 50);
	writeln("Delay ",i);
	Thread.sleep(dur!"msecs"(i));
	jsess.sendMessage("simple message");

	jsess.getRemoteMessage(); // wait for reply.

	jsess.sendCloseDocument(); // had enough for now.

	bool result = jsess.getRemoteMessage();
	if (!result)
		writeln("Session completed");
}




int main(string[] args)
{
	uintptr_t client_ct = 1;

    if (args.length > 1)
    {
		client_ct = to!uintptr_t(args[1]);
    }

	
	auto group = new ThreadGroup();

	for(auto i = 0; i < client_ct; i++)
		group.create(&runClient);

	//group.joinAll(false);



   /*
    // Skip HTTP header.
    while (true)
    {
        auto line = ss.readLine();

        if (!line.length)
            break;

        enum CONTENT_TYPE_NAME = "Content-Type: ";

        if (line.length > CONTENT_TYPE_NAME.length &&
            !icmp(CONTENT_TYPE_NAME, line[0 .. CONTENT_TYPE_NAME.length]))
        {
            auto type = line[CONTENT_TYPE_NAME.length .. line.length];

            if (type.length <= 5 || icmp("text/", type[0 .. 5]))
                throw new Exception("URL is not text");
        }
    }

    while (!ss.eof())
    {
        auto line = ss.readLine();
        writeln(line);
    }
	*/
    return 0;
}