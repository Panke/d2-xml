@echo off
echo Delete all outputs
del xmlp.lib sxml.exe bookstest.exe conformance.exe 2>NUL
rdmd dmdbuild

echo if all compiled, some simple tests
echo eg. sxml input books.xml
echo eg. bookstest input books.xml
echo eg. conformance input test/xmltest/xmltest.xml

del *.obj