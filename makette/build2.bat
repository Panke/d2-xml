set DROOT=C:\D\
set PLIB=%DROOT%dmd2\src\phobos\
set XP=..\xmlp\
set IR=..\inrange\
set DCOMP=%DROOT%dmd2\windows\bin\dmd


set SRC1=%IR%instring.d %IR%recode.d %IR%parse.d %IR%instream.d %XP%format.d %XP%compatible.d %XP%xmlrules.d %XP%except.d
set SRC2=%XP%xmldom.d %XP%input.d %XP%pieceparser.d %XP%delegater.d %XP%catalog.d %XP%shortxpath.d %XP%parse.d
rem %PLIB%std/file.d
%DCOMP% -g -debug -ofmakette-d %SRC1% %SRC2% makette.d"
%DCOMP% -release -ofmakette %SRC1% %SRC2% makette.d"





