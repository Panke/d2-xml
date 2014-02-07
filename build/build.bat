rem Delete all outputs
SET BDIR=%CD%

del xmlp.lib sxmltest.exe bookstest.exe conformance.exe 2>NUL

CD ..
rem Go to Root
SET ROOT=%CD%

dmd -property -lib -of%BDIR%\xmlp.lib -O -noboundscheck -release -w ^
	"alt/zstring.d"	"alt/aahash.d" "alt/hashutil.d" "alt/blockheap.d" ^
	"std/xmlp/arraydom.d" "std/xmlp/arraydombuilder.d" "std/xmlp/builder.d" 
	"std/xmlp/domparse.d" "std/xmlp/dtdtype.d" ^
	"std/xmlp/entitydata.d" "std/xmlp/error.d" "std/xmlp/slicedoc.d" ^
	"std/xmlp/sliceparse.d" "std/xmlp/source.d" "std/xmlp/xmlparse.d" ^
	"std/xml2.d" "std/xmlp/xmlchar.d" "std/xmlp/domvisitor.d" ^
	"std/xmlp/parseitem.d" "std/xmlp/subparse.d" ^
	"std/xmlp/doctype.d"  "std/xmlp/linkdom.d" ^
	"std/xmlp/tagvisitor.d" "std/xmlp/dtdvalidate.d" ^
	"std/xmlp/entity.d" "std/xmlp/feeder.d" "std/xmlp/validate.d" ^
	"std/xmlp/charinput.d" "std/xmlp/inputencode.d" "std/xmlp/coreprint.d"

IF ERRORLEVEL 1 exit /B

dmd -property -of%BDIR%\sxmltest -O -noboundscheck -release "./test/sxml" "./std/xml1" %BDIR%\xmlp.lib

IF ERRORLEVEL 1 exit /B

dmd -property -of%BDIR%\bookstest -O -noboundscheck -release "./test/books" %BDIR%\xmlp.lib

IF ERRORLEVEL 1 exit /B

dmd -property -of%BDIR%\conformance -O -noboundscheck -release ^
	"./test/conformance.d"  "std/xmlp/jisx0208.d"  %BDIR%\xmlp.lib

IF ERRORLEVEL 1 exit /B

CD %BDIR%

sxmltest input %ROOT%\books.xml

bookstest input  %ROOT%\books.xml

REM This is a subset of all the tests
conformance input  %ROOT%\test\xmltest\xmltest.xml
