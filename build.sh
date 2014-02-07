#!/bin/bash
# Build the builder with dmd and then run it
rdmd dmdbuild

echo "if all compiled, some simple tests"
echo "eg. sxml input books.xml"
echo "eg. bookstest input books.xml"
echo "eg. conformance input test/xmltest/xmltest.xml"

rm *.o

