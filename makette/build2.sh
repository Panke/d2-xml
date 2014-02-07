#!/bin/bash

function makeit()
{
echo $1
$1
if [ $? -ne 0 ] 
then
	exit
fi	
}

plib=~/dmd2/src/phobos/
xp=../xmlp/
dcomp2=~/dmd2/linux/bin/dmd
irn=../inrange/

src="${irn}instring.d ${irn}instream.d ${irn}recode.d  ${xp}parse.d ${xp}shortxpath.d ${xp}format.d ${xp}compatible.d ${xp}xmlrules.d ${xp}except.d ${xp}xmldom.d ${xp}input.d ${xp}pieceparser.d ${xp}catalog.d  ${xp}delegater.d"


psrc="${plib}std/ctype.d ${plib}std/utf.d ${plib}std/file.d"  

makeit "${dcomp2} -g -ofdbg-makette ${src} ${psrc} makette.d"

makeit "${dcomp2} -release -ofmakette ${src} ${psrc} makette.d "


