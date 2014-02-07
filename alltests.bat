@echo off

echo Non-validating mode
set exe=RelXmlConf

%exe% input %CD%/xmlconf/xmltest/xmltest.xml skipfail summary
%exe% input %CD%/xmlconf/oasis/oasis.xml  skipfail  summary
%exe% input %CD%/xmlconf/sun/sun-valid.xml  skipfail  summary
%exe% input %CD%/xmlconf/ibm/ibm_oasis_valid.xml   skipfail summary
%exe% input %CD%/xmlconf/sun/sun-not-wf.xml skipfail summary
%exe% input %CD%/xmlconf/ibm/ibm_oasis_not-wf.xml  skipfail  summary
%exe% input %CD%/xmlconf/sun/sun-invalid.xml skipfail summary
%exe% input %CD%/xmlconf/ibm/ibm_oasis_invalid.xml skipfail summary

echo Validating mode
%exe% validate input %CD%/xmlconf/xmltest/xmltest.xml skipfail summary
%exe% validate input %CD%/xmlconf/oasis/oasis.xml  skipfail  summary
%exe% validate input %CD%/xmlconf/sun/sun-valid.xml  skipfail  summary
%exe% validate input %CD%/xmlconf/ibm/ibm_oasis_valid.xml   skipfail summary
%exe% validate input %CD%/xmlconf/sun/sun-not-wf.xml skipfail summary
%exe% validate input %CD%/xmlconf/ibm/ibm_oasis_not-wf.xml  skipfail  summary
%exe% validate input %CD%/xmlconf/sun/sun-invalid.xml skipfail summary
%exe% validate input %CD%/xmlconf/ibm/ibm_oasis_invalid.xml skipfail summary


