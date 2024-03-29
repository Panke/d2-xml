
/**
* Run the Xml Conformance Tests.
*
* Commandline  XmlConf input <pathtests.xml>  [ test <id> ] [ skipfail ]
*
* Output test results and summary statistics.
*
* A test type can be one of three main kinds.$(BR)
* Valid ;  must be passed by non-validating and validating parsers.$(BR)
* Invalid ;  well formed, passed by non-validating parsers, but warnings should be issued by a validating parser.$(BR)
* Not well formed ; All parsers will return error.$(BR)
*
* So for every test, there are two runs.
* The validate flag is set, and then not set for the xml parser.
*
* Authors: Michael Rynn, michaelrynn@optusnet.com.au
*
* The test files used are from http://www.w3.org/XML/Test.
* With this release, the only tests coded for and passed 100% have been
* the following collection of test files.
*
* Note that the sun files need a root element wrapper to be made valid

input ~/xmlconf/xmltest/xmltest.xml skipfail summary
input ~/xmlconf/oasis/oasis.xml  skipfail  summary
input ~/xmlconf/sun/sun-valid.xml  skipfail  summary
input ~/xmlconf/ibm/ibm_oasis_valid.xml   skipfail summary
input ~/xmlconf/sun/sun-not-wf.xml skipfail summary
input ~/xmlconf/ibm/ibm_oasis_not-wf.xml  skipfail  summary
input ~/xmlconf/sun/sun-invalid.xml skipfail summary
input ~/xmlconf/ibm/ibm_oasis_invalid.xml skipfail summary

both with and without the optional validate argument

* The invalid error warnings collected with "invalid" documents may vary in the
* degree of insight into the cause of the error. This program only tests that some sort
* of warning was produced for an xml input that was invalid but well-formed, and cannot
* verify that the warning was appropriate to the test case.

**/
module xml.test.conform;

import std.conv;
import std.string;
import std.stdio;
import std.path;
import std.variant;
import std.array;
import std.exception;

import alt.buffer;
import xml.ixml;
import xml.jisx0208;
import xml.parse.input;

import std.stdint;
/**
* Test record from tests file
**/

import xml.dom.domt, xml.util.read, xml.test.suite;

alias XMLTESTS!wchar.XmlString	XmlString;

void writeUsage()
{
    string usage =
        `TestXmlConf input <filepath> [test <id>] [skipfail]
        filepath -   - A special XML file in a w3c XML tests folder
        test  -      - Run only a particular test id
        skipfail -   - If run all tests do not stop on first fail
		summary -    - Do not print each test id - summary only
		namespaceoff - Namespace aware turned off -
		validate -   - turn on validation`;

    writefln("%s", usage);
}

int main(string[] args)
{
    int oix = 0;



	auto tests = new XMLTESTS!wchar.Tests();

    // this registers for this thread and call type.
    EUC_JP!(CharIR).register("EUC-JP");

    if (args.length <= 1)
    {
        writeUsage();
        return 0;
    }
    while(oix < args.length)
    {
        auto option = args[oix];

        switch(option)
        {
			case "xml11":
				tests.xmlversion11 = true;
				break;
			case "xml10":
				tests.xmlversion11 = false;
				break;
			case "validate":
				tests.validate = true;
				break;
			case "namespaceoff":
				tests.namespaceAware = false;
				break;
			case "summary":
				tests.summary = true;
				break;

			case "skipfail":
				tests.stopOnFail = false;
				break;

			case "test":
				oix++;
				if (oix < args.length)
				{
					tests.testName = to!XmlString(args[oix]);
				}
				break;
			case "input":
				oix++;
				if (oix < args.length)
				{
					tests.testsXmlFile = args[oix];
				}
				break;
			default:
				break;
        }
        oix++;
    }
	return tests.perform();


}

