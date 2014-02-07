set DROOT=C:\D\tango\
set PLIB=%DROOT%lib\import\
set XP=xmlp\
set IR=inrange\
set DCOMP=%DROOT%bin\dmd

set src=%IR%instring.d %IR%instream.d %XP%format.d %XP%xmlrules.d %IR%recode.d %XP%except.d %XP%xmldom.d %XP%input.d %XP%pieceparser.d %XP%delegater.d %XP%compatible.d

%DCOMP% -g -debug -ofTango-TestXmlConf %SRC% XmlConf.d"
%DCOMP% -g -debug -ofTango-TestBooks %SRC% ElementHandler.d"

%DCOMP% -release -ofTango-RelXmlConf %SRC% XmlConf.d"
%DCOMP% -release -ofTango-RelBooks %SRC% ElementHandler.d"




