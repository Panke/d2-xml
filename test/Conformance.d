
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

module conformance;

//import std.xml2;


import std.conv;
import std.string;
import std.stdio;
import std.path;
import std.variant;
import std.array;
import std.exception;
import std.xmlp.nodetype;
import std.xmlp.parseitem;
import std.xmlp.domvisitor;
import std.xmlp.linkdom;
import alt.buffer;
import std.xmlp.error;
import std.xmlp.jisx0208;
import std.xmlp.inputencode;
import std.xmlp.charinput;
import std.xmlp.domparse;
import std.stdint;
/**
 * Test record from tests file
 **/

class XmlConfTest
{
    string  id;
    intptr_t order_;
    string  test_type;
    string  uri;
    string  entities;
    string  sections;
    string  description;
    string  output;
    string  baseDir;
    string  namespace;
    string  edition; // some tests are XML edition dependent (blast: why cannot this have been put in the version=?)
    bool    passed;

    override int opCmp(Object obj) const
    {
        auto cobj = cast(XmlConfTest)obj;
        if (cobj is null)
            return -1;
        else
            return cast(int)(this.order_ - cobj.order_);
    }

}

// collect all the information and put it in a string

class ParseErrorHandler : DOMErrorHandler
{
    uint	  domErrorLevel;
    string	  msg;

    override bool handleError(DOMError error)
    {
        string[]  errors;
        auto checkLevel = error.getSeverity();
        if (checkLevel > domErrorLevel)
            domErrorLevel = checkLevel;

        msg = error.getMessage();

        if (msg !is null)
        {
            errors ~= to!(string)(msg);
        }

        DOMLocator loc = error.getLocation();
        if (loc !is null)
        {
            errors ~= format("filepos %d,  line %d, col %d", loc.getByteOffset(), loc.getLineNumber(), loc.getColumnNumber());
        }


        if (errors.length == 0)
        {
            errors ~= "unknown error";

        }

        msg = std.string.join(errors,"\n");

        return false;
    }

    override string toString() const
    {
        return msg;
    }
}

/**
 * Conformance test result
 **/
class XmlConfResult : DOMErrorHandler
{
    XmlConfTest test;
    bool      validate;
    bool      passed;
    bool      outputMatch;
    bool      hadError;
    uint	  domErrorLevel;
    string    thrownException;

    string    output;
    string[]  errors;


    override bool handleError(DOMError error)
    {
        bool result = false;

        hadError = true;
        auto checkLevel = error.getSeverity();
        if (checkLevel > domErrorLevel)
            domErrorLevel = checkLevel;

        auto msg = error.getMessage();

        if (msg !is null)
        {
            errors ~= to!(string)(msg);
        }

        DOMLocator loc = error.getLocation();
        if (loc !is null)
        {
            errors ~= format("filepos %d,  line %d, col %d", loc.getByteOffset(), loc.getLineNumber(), loc.getColumnNumber());
        }


        if (errors.length == 0)
        {
            errors ~= "unknown error";

        }
        return result;
    }
}

alias XmlConfTest[string] TestArray;

/// convenience wrapper for testing, but not efficient
/// OK when DOM is using string
struct ElementWrap
{
    private Element e_;

    string getTextContent()
    {
        return e_.getTextContent();
    }

    string opIndex(string atid)
    {
        return e_.getAttribute(atid);
    }
}
/// add a new test to the array using element
XmlConfTest doTestElement(Element e, string baseDir)
{
    XmlConfTest test = new XmlConfTest();

    ElementWrap  w = ElementWrap(e);

    string ns = w["RECOMMENDATION"];
    if ((ns.length > 2) && ns[0..2] == "NS")
    {
        test.namespace = ns[2..$];
    }

    test.id = w["ID"];
    test.edition = w["EDITION"];

    test.test_type = w["TYPE"];
    test.entities = w["ENTITIES"];
    test.uri = w["URI"];


    test.sections = w["SECTIONS"];
    test.output = w["OUTPUT"];
    test.baseDir = baseDir;
    test.description = w.getTextContent();

    return  test;

}

void testCasesElement(ref XmlConfTest[string] tests, Element cases, ref intptr_t orderNum)
{
    // extract base directory, then the test cases
    ElementWrap  w = ElementWrap(cases);

    string baseDir = w["xml:base"];
    auto slen = baseDir.length;
    if (slen > 0)
    {
        slen--;
        if (baseDir[slen] == '\\' || baseDir[slen] == '/')
            baseDir.length = slen;
    }
    DOMVisitor visit;

    visit.startElement(cases);

    do
    {
        if (visit.nodeType == NodeType.Element_node)
        {
            Element e = visit.element;
            if (visit.isElement && e.getTagName() == "TEST")
            {
                auto t = doTestElement(e,baseDir);
                if (t !is null)
                {
                    t.order_ = ++orderNum;
                    tests[t.id] = t;
                }
                visit.doneElement();
            }
            else if (!visit.isElement)
            {
                //writeln("End " , e.getTagName());
            }
        }
    }
    while (visit.nextNode());

}


/**
 * Read the test specifications into the array of XmlConfTest from the xml file.
 **/
bool readTests(ref XmlConfTest[string] tests,string path)
{
    bool result= true;

    string dirName = dirName(path);
    string fileName = baseName(path);
    writeln("Test file  ", fileName, " from ", dirName);


    Document doc = new Document(null,path); // path here is just a tag label.
    auto peh = new ParseErrorHandler();

    DOMConfiguration config = doc.getDomConfig();
    //Variant v = cast(DOMErrorHandler) peh;
    config.setParameter("error-handler",Variant(cast(DOMErrorHandler) peh));
    config.setParameter("namespaces", Variant(false));

    //if (!std.path.isabs(dirName)) // should work either way
    //	dirName = rel2abs(dirName);
    try
    {

        auto parser = parseXmlFileValidate( path);
        parser.systemPaths( [dirName] );

        auto dp = new DocumentBuilder(parser,doc);
        dp.buildContent();
    }
    catch(ParseError pe)
    {
        writeln("Error reading test configuration ",pe.toString());
        return false;
    }

    catch(Exception e)
    {
        writeln(e.toString());
        return false;
    }

    DOMVisitor visit;

    visit.startElement(doc.getDocumentElement());
    intptr_t orderNum;

    do
    {
        if (visit.nodeType == NodeType.Element_node)
        {
            Element e = visit.element;
            if (visit.isElement && e.getTagName() == "TESTCASES")
            {
                testCasesElement(tests,e,orderNum);
                visit.doneElement();
            }
            else if (!visit.isElement)
            {
                //writeln("End " , e.getTagName());
            }
        }
    }
    while (visit.nextNode());

    return true;

}


/**
 * Run a single test
 */

XmlConfResult runTest(XmlConfTest t, string rootDir, bool validate)
{

    uint editions[] = null;

    uint maxEdition()
    {
        if (editions is null)
            return 5;
        uint max = 0;
        foreach(edval ; editions)
        if (edval > max)
            max = edval;
        return max;
    }

    bool hasEdition(uint ednum)
    {
        if (editions is null)
            return true;

        foreach(edval ; editions)
        {
            if (ednum == edval)
                return true;
        }
        return false;
    }

    if (t.edition.length > 0)
    {
        string[] values = split(t.edition);
        foreach(v ; values)
        {
            editions ~= to!uint(v);
        }
    }
    XmlConfResult result = new XmlConfResult();
    result.test = t;
    result.validate = validate;

    Document doc; // keep for big exceptions

    try
    {
        if (t.uri.length == 0)
            writeln("t.uri ", t.uri);
        if (t.uri.endsWith("pr-xml-euc-jp.xml") || t.uri.endsWith("weekly-euc-jp.xml"))
        {
            auto c8p = Recode8.getRecodeFunc("euc-jp");
            if (c8p !is null)
            {
                t.test_type = "valid";
            }
        }
        string sourceXml = buildPath(rootDir, t.baseDir, t.uri);
        string baseDir = dirName(sourceXml);

        string[] plist = [baseDir];

        doc = new Document(null,sourceXml);
        DOMConfiguration config = doc.getDomConfig();
        // The cast is essential, polymorphism fails for Variant.get!
        config.setParameter("error-handler",Variant( cast(DOMErrorHandler) result) );
        config.setParameter("edition", Variant( maxEdition() ) );
        config.setParameter("canonical-form",Variant(true)); // flag for output hint?

        Variant b;
        if (t.namespace.length > 0)
        {
            b = true;
        }
        else
            b = false;
        config.setParameter("namespaces", b);

        auto parser = validate ? parseXmlFileValidate(sourceXml) : parseXmlFile(sourceXml);
        parser.systemPaths(plist);
        auto dp = new DocumentBuilder(parser, doc);

        dp.buildContent();

    }
    catch(ParseError x)
    {
        // bombed
        if (result.errors.length > 0)
        {
            writefln("DOM Error Handler exception");
            foreach(s ; result.errors)
            writeln(s);
        }
        else
        {
            writefln("General exception %s", x.toString());
        }
    }

    catch(Exception ex)
    {
        // anything unexpected.
        writefln("Non parse exception %s", ex.toString());
        result.domErrorLevel = DOMError.SEVERITY_FATAL_ERROR;
        result.hadError = true;
    }

    // did we get an error
    if (t.test_type == "not-wf")
    {
        result.passed = (result.domErrorLevel == DOMError.SEVERITY_FATAL_ERROR);
    }
    else if (t.test_type == "error")
    {
        result.passed = (result.domErrorLevel == DOMError.SEVERITY_ERROR);
    }
    else if (t.test_type == "invalid")
    {
        if (validate)
            result.passed = (result.domErrorLevel == DOMError.SEVERITY_WARNING);
        else
            result.passed = (result.domErrorLevel == DOMError.NO_ERROR);
    }
    else if (t.test_type == "valid")
    {
        result.passed = !result.hadError;
    }

    if ((t.output.length > 0) && (result.domErrorLevel <= DOMError.SEVERITY_WARNING))
    {
        // output the document canonically, compare with Conformance suite output document.
        Buffer!char app;

        void output(const(char)[] s)
        {
            app.put(s);
        }
        printDocument(doc, &output, 0);

        char[] checkend = app.toArray;
        if (checkend.length > 0 && checkend[$-1] == '\n')
            app.length = checkend.length - 1;
        string sdoc = app.idup;

        /// now compare to output
        string bestPath = buildPath(rootDir,t.baseDir, t.output);
        string cmpResult =  cast(string)std.file.read(bestPath);
        bool matches = (cmp(sdoc,cmpResult) == 0);
        if (!matches)
        {
            // output the difference between the 2 versions
            auto minsize = sdoc.length;
            if (minsize > cmpResult.length)
                minsize = cmpResult.length;

            size_t lineNo = 0;
            size_t linePos = 0;
            for(size_t kix = 0; kix < minsize; kix++)
            {
                if (sdoc[kix] != cmpResult[kix])
                {
                    writeln("Difference at character ", kix, " : Line ", lineNo, " pos ", linePos);
                    writefln("got %s, expected %s  (%x, %x)", sdoc[kix], cmpResult[kix], sdoc[kix], cmpResult[kix]);
                    break;
                }
                if (sdoc[kix] == '\n')
                {
                    lineNo++;
                    linePos = 0;
                }
                else
                {
                    linePos++;
                }
            }
            if (minsize < sdoc.length)
                for(size_t kix = minsize; kix < sdoc.length; kix++)
                    writefln("extra 0x%x", sdoc[kix]);

            writeln(sdoc);
            result.passed = false;

        }
    }

    return result;
}

void showResult(XmlConfResult rt)
{
    void showValidate()
    {
        if (rt.hadError)
            writefln("validate %d error-level %d id %s", rt.passed, rt.validate, rt.test.id);
        else
            writefln("validate %d id %s", rt.validate,rt.test.id);
    }

    if (rt.passed)
    {
        write("passed: ");
        showValidate();
    }
    else
    {
        write("failed: ");
        showValidate();
        foreach(er ; rt.errors)
        {
            writefln("Error: %s",er);
        }
    }
}
/**
 * Run multiple tests.
 **/

bool summary;
bool validate;
bool namespaceAware;
bool xmlversion11;

bool runTests(XmlConfTest[string] tests, string baseDir, bool stopfail)
{
    //writefln("To run %d tests from %s", tests.length, baseDir);


    auto testList = tests.values;
    testList = testList.sort;

    int passct = 0;
    int notvalpass = 0;
    int isvalpass = 0;
    int runct = 0;


STUFF_NOW:
    foreach(ix, test ; testList)
    {
        runct++;
        if (!summary)
            writefln("test %s", test.id);

        XmlConfResult rt0 = runTest(test, baseDir, validate);

        if (rt0.passed)
        {
            passct++;
            if (!stopfail && !summary)
            {
                writefln("passed %s", test.id);
            }
        }
        else
        {
            if (!summary || stopfail)
            {
                writefln("Failed test %d", runct);
                showResult(rt0);
                writefln("Failed catagory %s, input %s", test.test_type, test.uri);

            }
            if (stopfail)
                return false;
        }

    }

    double pct(double v, double t)
    {
        return v * 100.0 / t;
    }

    double total = tests.length;

    writefln("%d tests, passed %d (%g%%)",
             tests.length, passct, pct(passct,total));

    return true;
}

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

    string testsXmlFile;
    string testName;
    bool  stopOnFail = true;
    namespaceAware = true;
    xmlversion11 = false;

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
            xmlversion11 = true;
            break;
        case "xml10":
            xmlversion11 = false;
            break;
        case "validate":
            validate = true;
            break;
        case "namespaceoff":
            namespaceAware = false;
            break;
        case "summary":
            summary = true;
            break;

        case "skipfail":
            stopOnFail = false;
            break;

        case "test":
            oix++;
            if (oix < args.length)
			{
                testName = args[oix];
            }
            break;
        case "input":
            oix++;
            if (oix < args.length)
            {
                testsXmlFile = args[oix];
            }
            break;
        default:
            break;
        }
        oix++;
    }


    string baseDir = dirName(testsXmlFile);
    if (!isAbsolute(baseDir))
        baseDir = absolutePath(baseDir);
    writeln("Test file in ", baseDir);
    if (testsXmlFile !is null)
    {
        XmlConfTest[string] tests;

        if (readTests(tests, testsXmlFile))
        {
            if (testName.length == 0)
            {
                runTests(tests, baseDir, stopOnFail);
            }
            else
            {
                bool found = false;
                auto t = tests.get(testName,null);

                if (t !is null)
                {
                    found = true;
                    writeln("Test number = ", t.order_);

                    XmlConfResult rt1 = runTest(t,baseDir,true);
                    showResult(rt1);
                    XmlConfResult rt0 = runTest(t,baseDir,false);
                    showResult(rt0);
                    t.passed = rt0.passed && rt1.passed;
                    if (!summary)
                        writeln(t.description);
                    if (!t.passed)
                        writefln("Failed catagory %s, input %s", t.test_type, t.uri);
                }
                else
                {
                    writefln("test id not found %s", testName);
                }
            }
        }
    }
    string dinp;
    stdin.readln(dinp);
    return 0;
}

