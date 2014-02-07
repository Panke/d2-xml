module alt.filereader;

import alt.buffer;
import alt.bomstring;
import alt.inputencode;

import std.stream; // plagerize existing code
import std.conv, std.stdint;

debug {
    import std.stdio;
}
version (Windows)
{
    private import std.c.windows.windows;
}

version (Posix) {
  private import core.sys.posix.fcntl;
  private import core.sys.posix.unistd;
  alias int HANDLE;
}
/// Make it easy to read by line?
/// Handle BOM

static private void parseMode(int mode,
                     out int access,
                     out int share,
                     out int createMode) {
    version (Windows) {
        share |= FILE_SHARE_READ | FILE_SHARE_WRITE;
        if (mode & FileMode.In) {
            access |= GENERIC_READ;
            createMode = OPEN_EXISTING;
        }
        if (mode & FileMode.Out) {
            access |= GENERIC_WRITE;
            createMode = OPEN_ALWAYS; // will create if not present
        }
        if ((mode & FileMode.OutNew) == FileMode.OutNew) {
            createMode = CREATE_ALWAYS; // resets file
        }
    }
    version (Posix) {
        share = octal!666;
        if (mode & FileMode.In) {
            access = O_RDONLY;
        }
        if (mode & FileMode.Out) {
            createMode = O_CREAT; // will create if not present
            access = O_WRONLY;
        }
        if (access == (O_WRONLY | O_RDONLY)) {
            access = O_RDWR;
        }
        if ((mode & FileMode.OutNew) == FileMode.OutNew) {
            access |= O_TRUNC; // resets file
        }
    }
}
/** Maybe useful for big files? Want to find out the BOM type, and read in correct  Array!char types.
    Will be over-simplified, since the more it tries to do, the worse it gets.
    Length ? of TextStream - does not include BOM length
    Length ? of FileStream - does include BOM length!
    Compromise - return textPosition, and textLength, but also have bomLength property.
*/

class FileException : Exception {
    this(string msg)
    {
        super(msg);
    }
}
class FileBOM {
    version (Windows)
    {
        private HANDLE hFile;
    }
    version (Posix)
    {
        private HANDLE hFile = -1;
    }

    private {
        bool readEOF = false;
        bool checkedBOM = false;

        BOM            bomMark;
    }

    @property BOM bom()
    {
        return bomMark;
    }
    @property bool eof()
    {
        return readEOF;
    }

    @property bool isOpen()
    {
        version(Posix)
            return (hFile != -1);
        version(Windows)
            return (hFile != INVALID_HANDLE_VALUE);
    }
    void openRead(string path)
    {
        int access, share, createMode;
        parseMode(FileMode.In, access,share,createMode);
        version (Windows)
        {
            hFile = CreateFileW(std.utf.toUTF16z(path), access, share,
                              null, createMode, 0, null);
        }
        version (Posix)
        {
            Buffer!char  name = path;
            name.nullTerminate();
            hFile = core.sys.posix.fcntl.open(name.ptr, access | createMode, share);
        }
    }
    void close()
    {
        if (isOpen())
        {
            if(hFile)
            {
                version (Windows) {
                    CloseHandle(hFile);
                    hFile = null;
                } else version (Posix) {
                    core.sys.posix.unistd.close(hFile);
                    hFile = -1;
                }
            }
        }
    }
    private ulong seek(long offset, SeekPos rel)
    {
        version (Windows)
        {
            int hi = cast(int)(offset>>32);
            uint low = SetFilePointer(hFile, cast(int)offset, &hi, rel);
            if ((low == INVALID_SET_FILE_POINTER) && (GetLastError() != 0))
                throw new SeekException("unable to move file pointer");
            ulong result = (cast(ulong)hi << 32) + low;
        }
        else version (Posix)
        {
            auto result = lseek(hFile, cast(int)offset, rel);
            if (result == cast(typeof(result))-1)
            throw new SeekException("unable to move file pointer");
        }
        readEOF = false;
        return cast(ulong)result;
    }

    private size_t readBlock(void* buffer, size_t size)
    {
        version (Windows)
        {
            auto dwSize = to!DWORD(size);
            ReadFile(hFile, buffer, dwSize, &dwSize, null);
            size = dwSize;
        }
        else version (Posix)
        {
            size = core.sys.posix.unistd.read(hFile, buffer, size);
            if (size == -1)
                size = 0;
        }
        readEOF = (size == 0);
        return size;
    }

}

class TextFileBOM : FileBOM
{
    private {
        StreamBOM   bomMark;
        Reader      myReader;
    }
    StreamBOM getBOM()
    {
        if (bomMark is null)
        {
            ubyte data[8];
            bomMark = stripBOM(data);
            seek(bomMark.bomBytes.length,SeekPos.Set);
        }
        return bomMark;
    }
    Reader getReader()
    {
        getBOM();
        if (myReader is null)
        {
            switch(bomMark.bomEnum)
            {
            case BOM.UTF8:
                goto default;
                break;
            case BOM.UTF16LE:
            case BOM.UTF16BE:
                myReader = this.new FileReader!wchar();
                break;
            case BOM.UTF32LE:
            case BOM.UTF32BE:
                myReader = this.new FileReader!dchar();
                break;
            default:
                myReader = new FileReader!char();
                break;
            }
        }
        return myReader;
    }
    class Reader {
         // in character sizes of bomMark.type.tsize()

        /// returned buffer contents change on every call, so copy for reuse.
        abstract bool  readLine(ref BomString s);
        abstract bool  readChar(ref dchar d);
    }

    class FileReader(T) : Reader {
        T[]         buffer;
        uintptr_t   bufix;
        uintptr_t   buflen;

        alias bool delegate(ref T rawchar) FetchDg;

        this()
        {
            buffer.length = 256;
        }
        private {
         /// Return the raw character, or false for end of file
            final bool getRawChar(ref T refchar)
            {
                if (bufix >= buflen)
                {
                    if (!nextBuffer())
                    {
                       return false;
                    }
                }
                refchar = buffer[bufix];
                bufix++;
                return true;
            }


            final void unget()
            {
                assert(bufix > 0);
                bufix--;
            }
            final bool nextBuffer()
            {
                if (this.outer.eof())
                    return false;
                auto askfor = buffer.length;
                auto bufptr = buffer.ptr;
                bool saveUnget = (buflen > 0);
                if (saveUnget)
                {
                    // preserve unget()
                    *bufptr = buffer[buflen-1];
                    bufptr += 1;
                    askfor -= 1;
                }
                auto result = this.outer.readBlock(bufptr, askfor * T.sizeof);
                if (result > 0)
                {
                    bufix = saveUnget ? 1 : 0;
                    buflen = (result / T.sizeof) + bufix;

                    // take care of byte swapping
                    ubyte[] raw;

                    switch(this.outer.bomMark.bomEnum)
                    {
                    case BOM.UTF8:
                        break;
                    case BOM.UTF16LE:
                        version(BigEndian)
                        {
                            raw = cast(ubyte[]) buffer[bufix..$];
                            fromLittleEndian16(raw);
                        }

                        break;
                    case BOM.UTF16BE:
                        version(LittleEndian)
                        {
                            raw = cast(ubyte[]) buffer[bufix..$];
                            fromBigEndian16(raw);
                        }

                        break;
                    case BOM.UTF32LE:
                        version(BigEndian)
                        {
                            raw = cast(ubyte[]) buffer[bufix..$];
                            fromLittleEndian32(raw);
                        }

                        break;
                    case BOM.UTF32BE:
                        version(LitteEndian)
                        {
                             raw = cast(ubyte[]) buffer[bufix..$];
                             fromBigEndian32(raw);
                        }
                        break;
                    default:
                        break;

                    }
                    return true;
                }
                buflen = 0;
                return false;
            }
        }

        override bool readChar(ref dchar pchar)
        {
            static if (is(T==char))
            {
                return RecodeChar!FetchDg.recode_UTF8(&getRawChar,pchar);
            }
            else static if (is(T==wchar))
            {
                return RecodeWChar!FetchDg.recode_utf16(&getRawChar,pchar);
            }
            else static if (is(T==dchar))
            {
                // no decoding
                return getRawChar(pchar);
            }
        }
        /// End of line characters are never returned. LFCR, LF or CR are thrown away.
        override bool readLine(ref BomString s)
        {
            Buffer!T str;
            T test;
            while (getRawChar(test))
            {
                if (test == 0x0A || test == 0x0D)// No tests for other UTF end of line characters
                {
                    if (test == 0x0A)
                    {
                        if (getRawChar(test) && (test != 0x0D))
                            unget();
                    }
                    else {// test == 0x0D, always thrown away

                    }
                    s = str.take();
                    return true;
                }
                else {
                    str.put(test);
                }
            }
            if (str.length > 0)
            {
                s = str.take();
                return true;
            }
            return false;
        }
    }
    @property uintptr_t charSize() {
        assert(isOpen());
        return bomMark.type.tsize();
    }
    this(string path)
    {
        super.openRead(path);
        if (!isOpen())
        {
            throw new FileException(text("File open failed for ",path));
            //TODO ? throw
        }
    }
/** Loop till all but one or zero BOM arrays are eliminated,
	and one BOM sequence is exactly matched.
    Assume  data length >= maximum BOM length, which is 4 ubyte now.
    Return read ubytes in data, which were not found to be part of BOM.
    StreamBOM is a global class instance with information about the BOM.
*/

    private StreamBOM stripBOM(ref ubyte data[8])
    {
        auto boms = gStreamBOM.values[];
        auto bmct = boms.length;     // count down by excluding BOM
        assert(bmct > 1);
        auto bpos = 0;
        auto dataCount = 0;
        StreamBOM lastMatch;
        ubyte test;
        if (!isOpen())
            return gNoBOMMark; // or throw?
        OUTER_LOOP:
        while(!eof() && readBlock(&test, 1))
        {
            data[bpos] = test;
            lastMatch = null;
            foreach(ref bm ; boms)
            {
                // exclude loop
                if (bm !is null)
                {
                    if ((bpos >= bm.bomBytes.length) || (data[bpos] != bm.bomBytes[bpos]) )
                    {
                        bm = null;
                        bmct--;
                        if (bmct == 0)
                            break OUTER_LOOP;
                    }
                    else
                        lastMatch = bm;
                }
            }
            if (bmct > 1)
                bpos++;
            else if ( (bmct == 1) && (lastMatch !is null) && (lastMatch.bomBytes.length == bpos))
            {
                return lastMatch;
            }
            else
                break; // no single match
        }
        return gNoBOMMark;
    }


}
