with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body IO_Runtime_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result :=
        Universe.Execute (Source, "io-runtime-test");
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Temporary_Identity;
   procedure Binary_Roundtrip;
   procedure Zero_Count_Peek;
   procedure Empty_Read_All;
   procedure Line_Chopping;
   procedure Long_Line;
   procedure Multiple_Formats;
   procedure Explicit_Nil_Format;
   procedure Format_Prefix;
   procedure Sequential_Format_Error;
   procedure Decimal_Read;
   procedure Hexadecimal_Read;
   procedure Malformed_Number;
   procedure Numeral_Length_Boundary;
   procedure Negative_Count_Limit;
   procedure Huge_Count_Memory;
   procedure Write_Result;
   procedure Numeric_Write;
   procedure Sequential_Write_Error;
   procedure Seek_Origins;
   procedure Invalid_Seek_Origin;
   procedure Buffering_Modes;
   procedure Closed_File;
   procedure Standard_Close;
   procedure Iterator_Results;
   procedure Iterator_Upvalues;
   procedure Iterator_Roots_File;
   procedure Iterator_Count_Mutation;
   procedure Iterator_Count_Narrowing;
   procedure Iterator_Closed;
   procedure Iterator_Format_Error;
   procedure File_Iterator_Does_Not_Close;
   procedure Captured_Stdout;
   procedure Captured_Flush;
   procedure Default_Output;
   procedure Default_Input;
   procedure Invalid_Open_Mode;
   procedure Missing_File_Result;
   procedure Named_File_Lifecycle;
   procedure Named_Lines_Close;
   procedure Named_Lines_Fourth_Result;
   procedure Registry_Identity;
   procedure Session_Default_Isolation;
   procedure Collection_Closes_File;
   procedure Replaced_Finalizer_Resurrects;
   procedure Manual_Close_Collection;
   procedure Closing_Attribute;
   procedure Error_Closes_File;
   procedure Reverse_Close_Order;
   procedure Suspended_File_Close;
   procedure Abandoned_Coroutine_File;
   procedure Failed_Open_Finalizer_State;
   procedure Missing_File_Method_Argument;

   procedure Temporary_Identity is
   begin
      --  A real tmpfile is userdata with the actual FILE* metatable and a
      --  unique identity; explicit close changes its observable open state.
      Check ("local a=assert(io.tmpfile()); local b=assert(io.tmpfile()); " &
             "assert(type(a)=='userdata' and io.type(a)=='file' and a~=b); " &
             "assert(a:close()); assert(io.type(a)=='closed file'); " &
             "assert(b:close()); assert(io.type({})==nil)");
   end Temporary_Identity;

   procedure Binary_Roundtrip is
   begin
      --  Native binary streams retain NUL, high bytes and newline exactly.
      Check ("local f=assert(io.tmpfile()); " &
             "local s=string.char(0,255,10,13); " &
             "assert(f:write(s)==f); assert(f:seek('set',0)==0); " &
             "assert(f:read('a')==s); assert(f:close())");
   end Binary_Roundtrip;

   procedure Zero_Count_Peek is
   begin
      --  A zero-count read observes EOF without consuming the next byte.
      Check ("local f=assert(io.tmpfile()); f:write('x'); f:seek('set'); " &
             "assert(f:read(0)==''); assert(f:read(1)=='x'); " &
             "assert(f:read(0)==nil); assert(f:close())");
   end Zero_Count_Peek;

   procedure Empty_Read_All is
   begin
      --  Whole-file reads succeed with an empty string even at EOF, while
      --  line/count reads fail with a single nil result on the same stream.
      Check ("local f=assert(io.tmpfile()); assert(f:read('a')==''); " &
             "assert(f:read('l')==nil and f:read(1)==nil); f:close()");
   end Empty_Read_All;

   procedure Line_Chopping is
   begin
      --  Chopped/retained newline formats differ, including empty lines and
      --  the final unterminated line. No CR normalization is invented here.
      Check ("local f=assert(io.tmpfile()); f:write('a\n\nlast'); " &
             "f:seek('set'); assert(f:read('L')=='a\n'); " &
             "assert(f:read('l')==''); assert(f:read('L')=='last'); " &
             "assert(f:read('l')==nil); f:close()");
   end Line_Chopping;

   procedure Long_Line is
   begin
      --  A line crosses several managed reservation chunks; the boundary
      --  must not truncate bytes or consume the first byte of the next line.
      Check ("local f=assert(io.tmpfile()); local s=string.rep('z',9001); " &
             "f:write(s,'\nnext'); f:seek('set'); assert(f:read()==s); " &
             "assert(f:read()=='next'); f:close()");
   end Long_Line;

   procedure Multiple_Formats is
   begin
      --  Every requested result is preserved, stopping after the first nil.
      Check ("local f=assert(io.tmpfile()); f:write('abc'); f:seek('set'); " &
             "local a,b,c=f:read(1,2,1); assert(a=='a' and b=='bc' and " &
             "c==nil); assert(select('#',f:read(1,1))==1); f:close()");
   end Multiple_Formats;

   procedure Explicit_Nil_Format is
   begin
      --  Omitted format means line input; an explicitly supplied nil is an
      --  invalid argument, rather than another spelling of the default.
      Check ("local f=assert(io.tmpfile()); " &
             "assert(not pcall(f.read,f,nil)); " &
             "f:close()");
   end Explicit_Nil_Format;

   procedure Format_Prefix is
   begin
      --  Pinned C IO dispatches on the first byte after an optional '*'.
      Check ("local f=assert(io.tmpfile()); f:write('abc\nrest'); " &
             "f:seek('set'); assert(f:read('*line suffix')=='abc'); " &
             "assert(f:read('all suffix')=='rest'); f:close()");
   end Format_Prefix;

   procedure Sequential_Format_Error is
   begin
      --  Rejecting a later format does not undo bytes read by earlier ones.
      Check ("local f=assert(io.tmpfile()); f:write('abc'); f:seek('set'); " &
             "assert(not pcall(f.read,f,1,'?')); " &
             "assert(f:read('a')=='bc'); f:close()");
   end Sequential_Format_Error;

   procedure Decimal_Read is
   begin
      --  Numeric scanning skips whitespace, accepts signs/exponents, and
      --  puts back the first byte outside the numeral's lexical prefix.
      Check ("local f=assert(io.tmpfile()); f:write('  -1.25e2;7'); " &
             "f:seek('set'); assert(f:read('n')==-125); " &
             "assert(f:read(1)==';' and f:read('n')==7); f:close()");
   end Decimal_Read;

   procedure Hexadecimal_Read is
   begin
      --  Hexadecimal fractions use p/P exponents and leave delimiters intact.
      Check ("local f=assert(io.tmpfile()); f:write('+0x1.8p+2!'); " &
             "f:seek('set'); assert(f:read('*n')==6); " &
             "assert(f:read(1)=='!'); f:close()");
   end Hexadecimal_Read;

   procedure Malformed_Number is
   begin
      --  A malformed exponent consumes its valid-looking prefix, returns nil
      --  and unreads only the first byte that did not belong to that prefix.
      Check ("local f=assert(io.tmpfile()); f:write('1e+z'); f:seek('set'); " &
             "assert(f:read('n')==nil); assert(f:read('a')=='z'); f:close()");
   end Malformed_Number;

   procedure Numeral_Length_Boundary is
   begin
      --  The 200-byte native numeral bound fails predictably, preserving its
      --  201st byte as lookahead rather than scanning arbitrarily long input.
      Check ("local f=assert(io.tmpfile()); " &
             "f:write(string.rep('1',201),'!'); " &
             "f:seek('set'); assert(f:read('n')==nil); " &
             "assert(f:read('a')=='1!'); f:close()");
   end Numeral_Length_Boundary;

   procedure Negative_Count_Limit is
   begin
      --  Converting -1 to size_t exceeds Lua's signed MAX_SIZE. Its semantic
      --  string-size error precedes any allocator request or host quota.
      Check ("local f=assert(io.tmpfile()); f:write('x'); f:seek('set'); " &
             "local ok,e=pcall(f.read,f,-1); assert(not ok and " &
             "tostring(e):match('resulting string too large')); " &
             "assert(f:read(1)=='x'); f:close()");
   end Negative_Count_Limit;

   procedure Huge_Count_Memory is
   begin
      --  A mathematically valid but physically impossible allocation is a
      --  distinct catchable memory failure, preserving the original cursor.
      Check ("local f=assert(io.tmpfile()); f:write('x'); f:seek('set'); " &
             "local ok,e=pcall(f.read,f,math.maxinteger-1); " &
             "assert(not ok and tostring(e):match('memory')); " &
             "assert(f:read(1)=='x'); f:close()");
   end Huge_Count_Memory;

   procedure Write_Result is
   begin
      --  Empty and ordinary successful writes return exactly the same file.
      Check ("local f=assert(io.tmpfile()); assert(f:write()==f); " &
             "assert(select('#',f:write('x'))==1); f:close()");
   end Write_Result;

   procedure Numeric_Write is
   begin
      --  Numeric arguments use Lua's scalar number presentation, preserving
      --  the distinction between integer values and integer-looking floats.
      Check ("local f=assert(io.tmpfile()); f:write(12,' ',1.0); " &
             "f:seek('set'); assert(f:read('a')=='12 1.0'); f:close()");
   end Numeric_Write;

   procedure Sequential_Write_Error is
   begin
      --  Type-check arguments in write order. A later table cannot erase a
      --  preceding successful write, and __tostring is not consulted by IO.
      Check ("local f=assert(io.tmpfile()); assert(not pcall(f.write,f,'a'," &
             "setmetatable({}, {__tostring=function() return 'bad' end}))); " &
             "f:seek('set'); assert(f:read('a')=='a'); f:close()");
   end Sequential_Write_Error;

   procedure Seek_Origins is
   begin
      --  Native set/cur/end positions are returned as integers and select
      --  actual subsequent read offsets, rather than a simulated cursor.
      Check ("local f=assert(io.tmpfile()); f:write('abcd'); " &
             "assert(f:seek('set',1)==1); assert(f:read(1)=='b'); " &
             "assert(f:seek('cur',1)==3); assert(f:read(1)=='d'); " &
             "assert(f:seek('end',-2)==2); assert(f:read('a')=='cd'); " &
             "f:close()");
   end Seek_Origins;

   procedure Invalid_Seek_Origin is
   begin
      --  Invalid options are ordinary protected argument errors, leaving the
      --  stream usable at its prior position.
      Check ("local f=assert(io.tmpfile()); f:write('x'); f:seek('set'); " &
             "assert(not pcall(f.seek,f,'bad')); assert(f:read(1)=='x'); " &
             "f:close()");
   end Invalid_Seek_Origin;

   procedure Buffering_Modes is
   begin
      --  libc owns buffering memory. Test all public modes before any IO on
      --  separate streams so setvbuf's native ordering contract is respected.
      Check ("for _,mode in ipairs{'no','full','line'} do " &
             "local f=assert(io.tmpfile()); assert(f:setvbuf(mode,128)); " &
             "assert(f:write('x')); assert(f:flush()); f:close() end");
   end Buffering_Modes;

   procedure Closed_File is
   begin
      --  A cleared closef marks a file closed even though its FILE pointer is
      --  intentionally stale. Operations must not dereference that pointer.
      Check ("local f=assert(io.tmpfile()); f:close(); " &
             "assert(tostring(f)=='file (closed)'); " &
             "assert(not pcall(f.read,f)); assert(not pcall(f.close,f))");
   end Closed_File;

   procedure Standard_Close is
   begin
      --  Standard borrowed streams refuse close and restore their actual
      --  callback, remaining open for later use in this interpreter.
      Check ("local a,b=io.stdout:close(); " &
             "assert(a==nil and b=='cannot close standard file'); " &
             "assert(io.type(io.stdout)=='file'); io.stdout:write('')");
   end Standard_Close;

   procedure Iterator_Results is
   begin
      --  Stateful native iterators retain the file and all format values,
      --  returning the correct multi-result packet for every invocation.
      Check ("local f=assert(io.tmpfile()); f:write('ab\ncd\n'); " &
             "f:seek('set'); local it=f:lines(1,'l'); " &
             "local a,b=it(); assert(a=='a' and b=='b'); " &
             "a,b=it(); assert(a=='c' and b=='d'); " &
             "assert(select('#',it())==0); f:close()");
   end Iterator_Results;

   procedure Iterator_Upvalues is
   begin
      --  Preserve the actual C closure's ordered file/count/autoclose/format
      --  upvalues, rather than exposing an invented shorter state layout.
      Check ("local f=assert(io.tmpfile()); local it=f:lines('l',1); " &
             "local n,v=debug.getupvalue(it,1); assert(n=='' and v==f); " &
             "n,v=debug.getupvalue(it,2); assert(n=='' and v==2); " &
             "n,v=debug.getupvalue(it,3); assert(n=='' and v==false); " &
             "assert(select(2,debug.getupvalue(it,4))=='l'); " &
             "assert(select(2,debug.getupvalue(it,5))==1); " &
             "assert(debug.getupvalue(it,6)==nil); f:close()");
   end Iterator_Upvalues;

   procedure Iterator_Roots_File is
   begin
      --  The iterator's real native captures retain its otherwise weakly
      --  referenced file through collection, and disappear when it is gone.
      Check ("local f=assert(io.tmpfile()); " &
             "f:write('alive'); f:seek('set'); " &
             "local weak=setmetatable({f},{__mode='v'}); " &
             "local it=f:lines(); " &
             "f=nil; collectgarbage(); assert(io.type(weak[1])=='file'); " &
             "assert(it()=='alive'); it=nil; collectgarbage(); " &
             "collectgarbage(); assert(weak[1]==nil)");
   end Iterator_Roots_File;

   procedure Iterator_Count_Mutation is
   begin
      --  Native closure state is real mutable upvalue storage. Reducing the
      --  count changes subsequent result arity without changing the file.
      Check ("local f=assert(io.tmpfile()); f:write('abc'); f:seek('set'); " &
             "local it=f:lines(1,1); assert(debug.setupvalue(it,2,1)==''); " &
             "assert(select('#',it())==1); assert(it()=='b'); f:close()");
   end Iterator_Count_Mutation;

   procedure Iterator_Count_Narrowing is
   begin
      --  The C iterator narrows its mutable integer count to native int.
      --  A full 32-bit wrap selects zero formats, hence default line input.
      Check ("local f=assert(io.tmpfile()); f:write('abc'); f:seek('set'); " &
             "local it=f:lines(1); debug.setupvalue(it,2,1<<32); " &
             "assert(it()=='abc'); f:close()");
   end Iterator_Count_Narrowing;

   procedure Iterator_Closed is
   begin
      --  An iterator cannot silently continue using a FILE closed elsewhere.
      Check ("local f=assert(io.tmpfile()); local it=f:lines(); f:close(); " &
             "local ok,e=pcall(it); assert(not ok and " &
             "tostring(e):match('file is already closed'))");
   end Iterator_Closed;

   procedure Iterator_Format_Error is
   begin
      --  Format validation is deferred until iteration; construction alone
      --  does not read a byte or preempt an earlier observable statement.
      Check ("local f=assert(io.tmpfile()); local it=f:lines('?'); " &
             "assert(type(it)=='function'); assert(not pcall(it)); f:close()");
   end Iterator_Format_Error;

   procedure File_Iterator_Does_Not_Close is
   begin
      --  file:lines borrows the caller's file. EOF does not auto-close it.
      Check ("local f=assert(io.tmpfile()); for x in f:lines() do " &
             "error('empty iterator yielded') end; " &
             "assert(io.type(f)=='file'); assert(f:write('x')); f:close()");
   end File_Iterator_Does_Not_Close;

   procedure Captured_Stdout is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("assert(io.write('a',1)==io.stdout); " &
         "io.stdout:write('b'); print('c')",
         "stdout-capture");
   begin
      --  All stdout producers use one capture policy and preserve ordering.
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Assert (To_String (Result.Output) = "a1bc" & ASCII.LF,
              "IO stdout bypassed capture or reordered print");
   end Captured_Stdout;

   procedure Captured_Flush is
   begin
      --  Captured stdout has no native bytes to flush, but Lua receives the
      --  same successful one-result status as for an actual stdio stream.
      Check ("assert(io.flush()); assert(io.stdout:flush()); " &
             "assert(select('#',io.flush())==1)");
   end Captured_Flush;

   procedure Default_Output is
   begin
      --  The registry default, not the replaceable io.stdout field, supplies
      --  implicit write. Restore it before explicitly closing the temporary.
      Check ("local f=assert(io.tmpfile()); local old=io.output(); " &
             "assert(io.output(f)==f); assert(io.write('x')==f); " &
             "io.output(old); f:seek('set'); assert(f:read('a')=='x'); " &
             "f:close()");
   end Default_Output;

   procedure Default_Input is
   begin
      --  Default input is also registry-owned and preserves multiple formats.
      Check ("local f=assert(io.tmpfile()); f:write('xy'); f:seek('set'); " &
             "local old=io.input(); assert(io.input(f)==f); " &
             "local a,b=io.read(1,1); assert(a=='x' and b=='y'); " &
             "io.input(old); f:close()");
   end Default_Input;

   procedure Invalid_Open_Mode is
   begin
      --  Validate the native mode grammar before opening/truncating a file.
      Check ("assert(not pcall(io.open,'not-opened','?')); " &
             "assert(not pcall(io.popen,'not-executed','a'))");
   end Invalid_Open_Mode;

   procedure Missing_File_Result is
   begin
      --  Open failure is the native nil/message/errno tuple, not an Ada
      --  exception or a fabricated generic failure with no errno.
      Check ("local a,b,c=" &
             "io.open('reports/io-library-tests/no-such/sub/x'); " &
             "assert(a==nil and type(b)=='string' and " &
             "type(c)=='number' and c~=0)");
   end Missing_File_Result;

   procedure Named_File_Lifecycle is
   begin
      --  The fixture is explicitly inside the checkout's disposable reports.
      Ada.Directories.Create_Path ("reports/io-library-tests");
      Check ("local path='reports/io-library-tests/named-file.tmp'; " &
             "local f=assert(io.open(path,'wb')); f:write('native'); " &
             "f:close(); f=assert(io.open(path,'rb')); " &
             "assert(f:read('a')=='native'); f:close()");
      Ada.Directories.Delete_File
        ("reports/io-library-tests/named-file.tmp");
   end Named_File_Lifecycle;

   procedure Named_Lines_Close is
   begin
      --  io.lines(filename) owns its file and closes it at EOF; a later
      --  generic-for scope cleanup must see it already closed safely.
      Ada.Directories.Create_Path ("reports/io-library-tests");
      Check ("local path='reports/io-library-tests/lines-close.tmp'; " &
             "local f=assert(io.open(path,'w')); " &
             "f:write('a\nb\n'); f:close(); " &
             "local it,_,_,owned=io.lines(path); " &
             "assert(it()=='a' and it()=='b'); assert(it()==nil); " &
             "assert(io.type(owned)=='closed file')");
      Ada.Directories.Delete_File
        ("reports/io-library-tests/lines-close.tmp");
   end Named_Lines_Close;

   procedure Named_Lines_Fourth_Result is
   begin
      --  Early break uses io.lines' real fourth to-be-closed result. This
      --  proves integration with existing generic-for closing semantics.
      Ada.Directories.Create_Path ("reports/io-library-tests");
      Check ("local path='reports/io-library-tests/lines-break.tmp'; " &
             "local f=assert(io.open(path,'w')); " &
             "f:write('a\nb\n'); f:close(); " &
             "local it,s,c,owned=io.lines(path); " &
             "assert(s==nil and c==nil and type(owned)=='userdata'); " &
             "for line in it,s,c,owned do assert(line=='a'); break end; " &
             "assert(io.type(owned)=='closed file')");
      Ada.Directories.Delete_File
        ("reports/io-library-tests/lines-break.tmp");
   end Named_Lines_Fourth_Result;

   procedure Registry_Identity is
   begin
      --  The default stream is the registry value; changing the public field
      --  does not silently retarget this internal ownership relationship.
      Check ("local original=io.output(); io.stdout=false; " &
             "assert(io.output()==original); io.stdout=original; " &
             "assert(debug.getregistry()['_IO_output']==original)");
   end Registry_Identity;

   procedure Session_Default_Isolation is
      First, Second : Session;
      Result : Execution_Result;
   begin
      --  Native standard FILEs are process resources, but Lua wrappers and
      --  defaults are distinct session state. Mutating one registry cannot
      --  redirect or close another session's default temporary wrapper.
      Result := First.Execute
        ("f=assert(io.tmpfile()); io.output(f)", "first-io-session");
      Assert (Result.Status = Succeeded, "first IO setup failed");
      Result := Second.Execute
        ("assert(io.output()==io.stdout); io.write('second')", "second-io");
      Assert (Result.Status = Succeeded and then
                To_String (Result.Output) = "second",
              "IO defaults leaked between sessions");
      Result := First.Execute
        ("assert(io.output()==f); f:close()", "first-io");
      Assert (Result.Status = Succeeded, "first session lost its IO default");
   end Session_Default_Isolation;

   procedure Collection_Closes_File is
   begin
      --  Observe the real handler closing the unreachable target, without
      --  retaining that target through the observing closure's upvalues.
      Check ("local f=assert(io.tmpfile()); local wanted=tostring(f); " &
             "local mt=getmetatable(f); local old=mt.__gc; local state; " &
             "mt.__gc=function(p) local match=tostring(p)==wanted; old(p); " &
             "if match then state=io.type(p) end end; f=nil; " &
             "collectgarbage(); collectgarbage(); mt.__gc=old; " &
             "assert(state=='closed file')");
   end Collection_Closes_File;

   procedure Replaced_Finalizer_Resurrects is
   begin
      --  A replacement __gc deliberately does not close. Resurrection must
      --  retain a valid payload/open FILE, not trigger hidden host fallback.
      Check ("local f=assert(io.tmpfile()); local mt=getmetatable(f); " &
             "local old=mt.__gc; local held; " &
             "mt.__gc=function(p) held=p end; " &
             "f=nil; collectgarbage(); mt.__gc=old; " &
             "assert(io.type(held)=='file'); held:write('alive'); " &
             "held:seek('set'); assert(held:read('a')=='alive'); " &
             "held:close(); held=nil; collectgarbage()");
   end Replaced_Finalizer_Resurrects;

   procedure Manual_Close_Collection is
   begin
      --  The object can still be finalized once, but its existing cleared
      --  closef makes f_gc skip the stale FILE rather than fclose it twice.
      Check ("local f=assert(io.tmpfile()); local mt=getmetatable(f); " &
             "local old=mt.__gc; local calls=0; mt.__gc=function(p) " &
             "if io.type(p)=='closed file' then calls=calls+1 end; " &
             "old(p) end;" &
             "f:close(); f=nil; collectgarbage(); collectgarbage(); " &
             "mt.__gc=old; assert(calls==1)");
   end Manual_Close_Collection;

   procedure Closing_Attribute is
   begin
      --  A real file satisfies the language's closing declaration, and a
      --  reachable alias observes that it closes at ordinary block exit.
      Check ("local held; do local f <close> = assert(io.tmpfile()); " &
             "held=f; f:write('block') end; " &
             "assert(io.type(held)=='closed file')");
   end Closing_Attribute;

   procedure Error_Closes_File is
   begin
      --  Error unwinding closes the same payload before pcall resumes, while
      --  preserving the original error and the surviving alias's identity.
      Check ("local held; local ok,e=pcall(function() " &
             "local f <close> = assert(io.tmpfile()); held=f; " &
             "error('file scope failed') end); assert(not ok and " &
             "e:match('file scope failed')); " &
             "assert(io.type(held)=='closed file')");
   end Error_Closes_File;

   procedure Reverse_Close_Order is
   begin
      --  Both actual file handlers run through normal callable dispatch in
      --  reverse declaration order, rather than an unordered resource sweep.
      Check ("local names,order={},{}; local a=assert(io.tmpfile()); " &
             "local b=assert(io.tmpfile()); names[a]='a'; names[b]='b'; " &
             "local mt=getmetatable(a); local old=mt.__close; " &
             "mt.__close=function(p,e) " &
             "order[#order+1]=names[p]; old(p,e) end;" &
             "do local x <close> = a; local y <close> = b end; " &
             "mt.__close=old; assert(table.concat(order,',')=='b,a'); " &
             "assert(io.type(a)=='closed file' and " &
             "io.type(b)=='closed file')");
   end Reverse_Close_Order;

   procedure Suspended_File_Close is
   begin
      --  Yield preserves the active closing variable; explicit coroutine
      --  close runs its handler and changes the retained file's real state.
      Check ("local held; local co=coroutine.create(function() " &
             "local f <close> = assert(io.tmpfile()); held=f; " &
             "coroutine.yield() end); assert(coroutine.resume(co)); " &
             "assert(io.type(held)=='file'); assert(coroutine.close(co)); " &
             "assert(io.type(held)=='closed file')");
   end Suspended_File_Close;

   procedure Abandoned_Coroutine_File is
   begin
      --  Collecting abandoned coroutine storage must not run its TBC list.
      --  The file survives through a separate reachable alias and stays open.
      Check ("local held; local co=coroutine.create(function() " &
             "local f <close> = assert(io.tmpfile()); held=f; " &
             "coroutine.yield() end); assert(coroutine.resume(co)); co=nil; " &
             "collectgarbage(); assert(io.type(held)=='file'); " &
             "assert(held:write('still open')); held:close()");
   end Abandoned_Coroutine_File;

   procedure Failed_Open_Finalizer_State is
   begin
      --  newfile installs its real closef before fopen. A replacement __gc
      --  can observe the failed prefile as 'file' with null native storage;
      --  the original f_gc safely ignores that incomplete native resource.
      Check ("collectgarbage(); collectgarbage(); " &
             "local mt=getmetatable(io.stdout); local old=mt.__gc; " &
             "local seen; mt.__gc=function(p) seen=io.type(p); old(p) end; " &
             "assert(io.open('reports/no-such-io-fixture-527/a')==nil); " &
             "collectgarbage(); mt.__gc=old; assert(seen=='file')");
   end Failed_Open_Finalizer_State;

   procedure Missing_File_Method_Argument is
   begin
      --  Saved methods remain ordinary functions. An omitted receiver must
      --  be diagnosed before any native stream borrow, including close/read.
      Check ("for _,fn in ipairs{io.stdin.close,io.stdin.read," &
             "io.stdout.write} do local ok,e=pcall(fn); " &
             "assert(not ok and e:find('got no value',1,true)) end");
   end Missing_File_Method_Argument;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "IO: real temporary userdata identity",
                        Temporary_Identity'Access);
      Test_Support.Add (Suite, "IO: native binary byte roundtrip",
                        Binary_Roundtrip'Access);
      Test_Support.Add (Suite, "IO: zero-count EOF lookahead",
                        Zero_Count_Peek'Access);
      Test_Support.Add (Suite, "IO: empty whole-file read succeeds",
                        Empty_Read_All'Access);
      Test_Support.Add (Suite, "IO: chopped and retained newlines",
                        Line_Chopping'Access);
      Test_Support.Add (Suite, "IO: line crosses buffer reservations",
                        Long_Line'Access);
      Test_Support.Add (Suite, "IO: sequential multi-result formats",
                        Multiple_Formats'Access);
      Test_Support.Add (Suite, "IO: explicit nil is an invalid format",
                        Explicit_Nil_Format'Access);
      Test_Support.Add (Suite, "IO: C format prefix dispatch",
                        Format_Prefix'Access);
      Test_Support.Add (Suite, "IO: later format error preserves read cursor",
                        Sequential_Format_Error'Access);
      Test_Support.Add (Suite, "IO: decimal numeral lookahead",
                        Decimal_Read'Access);
      Test_Support.Add (Suite, "IO: hexadecimal numeral lookahead",
                        Hexadecimal_Read'Access);
      Test_Support.Add (Suite, "IO: malformed numeral consumption",
                        Malformed_Number'Access);
      Test_Support.Add (Suite, "IO: bounded native numeral scanner",
                        Numeral_Length_Boundary'Access);
      Test_Support.Add (Suite, "IO: unsigned negative count exceeds MAX_SIZE",
                        Negative_Count_Limit'Access);
      Test_Support.Add (Suite, "IO: valid huge count is a memory failure",
                        Huge_Count_Memory'Access);
      Test_Support.Add (Suite, "IO: successful write returns file identity",
                        Write_Result'Access);
      Test_Support.Add (Suite, "IO: native numeric write presentation",
                        Numeric_Write'Access);
      Test_Support.Add (Suite, "IO: later write argument preserves bytes",
                        Sequential_Write_Error'Access);
      Test_Support.Add (Suite, "IO: native seek origins and positions",
                        Seek_Origins'Access);
      Test_Support.Add (Suite, "IO: invalid seek option preserves cursor",
                        Invalid_Seek_Origin'Access);
      Test_Support.Add (Suite, "IO: actual libc buffering modes",
                        Buffering_Modes'Access);
      Test_Support.Add (Suite, "IO: closed payload never dereferences FILE",
                        Closed_File'Access);
      Test_Support.Add (Suite, "IO: borrowed standard stream refuses close",
                        Standard_Close'Access);
      Test_Support.Add (Suite, "IO: iterator retains formats and results",
                        Iterator_Results'Access);
      Test_Support.Add (Suite, "IO: iterator exposes ordered actual upvalues",
                        Iterator_Upvalues'Access);
      Test_Support.Add (Suite, "IO: iterator traces its retained file",
                        Iterator_Roots_File'Access);
      Test_Support.Add (Suite, "IO: iterator reads mutable count upvalue",
                        Iterator_Count_Mutation'Access);
      Test_Support.Add (Suite, "IO: iterator count uses native C narrowing",
                        Iterator_Count_Narrowing'Access);
      Test_Support.Add (Suite, "IO: iterator rejects externally closed file",
                        Iterator_Closed'Access);
      Test_Support.Add (Suite, "IO: iterator defers format validation",
                        Iterator_Format_Error'Access);
      Test_Support.Add (Suite, "IO: file iterator borrows its stream",
                        File_Iterator_Does_Not_Close'Access);
      Test_Support.Add (Suite, "IO: stdout shares print capture policy",
                        Captured_Stdout'Access);
      Test_Support.Add (Suite, "IO: captured flush result arity",
                        Captured_Flush'Access);
      Test_Support.Add (Suite, "IO: default output uses registry stream",
                        Default_Output'Access);
      Test_Support.Add (Suite, "IO: default input uses registry stream",
                        Default_Input'Access);
      Test_Support.Add (Suite, "IO: invalid modes precede native open",
                        Invalid_Open_Mode'Access);
      Test_Support.Add (Suite, "IO: native missing-file failure tuple",
                        Missing_File_Result'Access);
      Test_Support.Add (Suite, "IO: real named file open and close",
                        Named_File_Lifecycle'Access);
      Test_Support.Add (Suite, "IO: named lines iterator closes at EOF",
                        Named_Lines_Close'Access);
      Test_Support.Add (Suite, "IO: named lines supplies generic-for close",
                        Named_Lines_Fourth_Result'Access);
      Test_Support.Add (Suite, "IO: public fields do not replace defaults",
                        Registry_Identity'Access);
      Test_Support.Add (Suite, "IO: independent session defaults",
                        Session_Default_Isolation'Access);
      Test_Support.Add (Suite, "IO: real collection invokes file finalizer",
                        Collection_Closes_File'Access);
      Test_Support.Add (Suite, "IO: replaced finalizer retains open payload",
                        Replaced_Finalizer_Resurrects'Access);
      Test_Support.Add (Suite, "IO: collection skips already closed FILE",
                        Manual_Close_Collection'Access);
      Test_Support.Add (Suite, "IO: closing declaration closes actual file",
                        Closing_Attribute'Access);
      Test_Support.Add (Suite, "IO: Lua error unwinds actual file close",
                        Error_Closes_File'Access);
      Test_Support.Add (Suite, "IO: real file close order is reverse lexical",
                        Reverse_Close_Order'Access);
      Test_Support.Add (Suite, "IO: coroutine close drains suspended file",
                        Suspended_File_Close'Access);
      Test_Support.Add (Suite, "IO: abandoned coroutine does not run file TBC",
                        Abandoned_Coroutine_File'Access);
      Test_Support.Add (Suite, "IO: failed open retains actual prefile state",
                        Failed_Open_Finalizer_State'Access);
      Test_Support.Add (Suite, "IO: omitted method receiver is controlled",
                        Missing_File_Method_Argument'Access);
   end Register;
end IO_Runtime_Tests;
