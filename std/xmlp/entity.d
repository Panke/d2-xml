module std.xmlp.entity;

import std.xmlp.subparse;
import std.xmlp.doctype, std.xmlp.charinput;
import std.xmlp.linkdom;
import std.xmlp.error;
import std.xmlp.dtdtype;
import std.xmlp.dtdvalidate;

import std.file, std.path, std.stream;


    /// parse the External DTD reference, for a parser, add its specifications to a DtdValidate
extern(C) bool getExternalDTD(IXMLParser vp,in ExternalDTD edtd, DTDValidate dtd)
    {
        string uri;

        if (!vp.getSystemPath(edtd.src_.systemId_, uri))
            return false;

        auto s = new BufferedFile(uri);
        auto sf = new XmlStreamFiller(s);

        auto dtp = new XmlDtdParser(sf,vp.validate());

        return dtp.processExternalDTD(vp, dtd);

    }
    
/// External C linkage to defeat module dynamic load dependency
extern(C)
bool getSystemEntity(IXMLParser vp,string sysid, ref string opt, ref string baseDir)
    {
        string uri;
        if (!vp.getSystemPath(sysid, uri))
            return false;

        // absolute:
        // relative: file exists in system path

        std.stream.File f = new std.stream.File();
        f.open(uri);

        if (!f.isOpen)
            vp.throwParseError("Unable to open file");

        baseDir = dirName(uri);
        bool	startedPump = false;// A hack for conformance case  invalid-bo-7
        try
        {
            auto s = new BufferedFile(uri);
            auto sf = new XmlStreamFiller(s);

            startedPump = true;

            auto dtp = new XmlDtdParser(sf, vp.validate());
            opt = dtp.parseSystemEntity(vp);

         }
        catch(ParseError pe)
        {
            // redirect exceptions to the original error handler.
            // alternative : ?Adopt the original error handler?
            // This will make the exception string extra confusing
            vp.throwParseError(pe.toString());
        }
        return true;
    }
