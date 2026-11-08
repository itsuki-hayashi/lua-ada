with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Debug_Traceback_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Hook_Origin;
   procedure Hook_Origin is
   begin
      --  A line hook is entered without a source-level call expression.
      --  Inspect its own real frame and first traceback entry; both report
      --  the hook origin instead of the interrupted instruction's name.
      Check
        ("local n=0;local co=coroutine.create(function()local x=1 e" &
         "nd);debug.sethook(co,function()local i=debug.getinfo(1,'n" &
         "');assert(i.namewhat=='hook' and i.name=='?');local t=deb" &
         "ug.traceback();assert(t:match(""\n[^\n]+: in hook '%?'""));" &
         "n=n+1 end,'l');assert(coroutine.resume(co));assert(n>0)");
   end Hook_Origin;

   procedure Local_Call_Name;
   procedure Local_Call_Name is
   begin
      --  A real local call retains the caller's inferred binding name.
      --  Trace inside a non-tail body and inspect its first Lua frame.
      Check
        ("local function f()local t=debug.traceback();return t end;" &
         "local t=f();assert(t:match(""\n[^\n]+: in local 'f'""))");
   end Local_Call_Name;

   procedure Anonymous_Coroutine;
   procedure Anonymous_Coroutine is
   begin
      --  A suspended entry closure has no source-level caller.
      --  Its fallback describes its definition location, after the real
      --  yield frame, without inventing a function name.
      Check
        ("local co=coroutine.create(assert(load('return function() " &
         "coroutine.yield() end','@trace.lua'))());assert(coroutine" &
         ".resume(co));local t=debug.traceback(co);assert(t:find(""[" &
         "C]: in field 'yield'"",1,true));assert(t:find('trace.lua:1" &
         ": in function <trace.lua:1>',1,true))");
   end Anonymous_Coroutine;

   procedure Native_Registry_Name;
   procedure Native_Registry_Name is
   begin
      --  An indirect C call has no inferred name in the caller's code.
      --  The actual loaded-module registry supplies its public identity.
      Check
        ("local ok,t=(function()return pcall end)()(debug.traceback" &
         ");assert(ok);assert(t:find(""[C]: in function 'pcall'"",1,t" &
         "rue))");
   end Native_Registry_Name;

   procedure Replaced_Public_Loaded;
   procedure Replaced_Public_Loaded is
   begin
      --  Replace the public package.loaded field after installing a module.
      --  The traceback lookup must retain the actual module registry.
      Check
        ("local f=assert(load('return function()coroutine.yield()en" &
         "d','@module.lua'))();local old=package.loaded;old.tracepr" &
         "obe={entry=f};package.loaded={};local co=coroutine.create" &
         "(f);assert(coroutine.resume(co));local t=debug.traceback(" &
         "co);package.loaded=old;old.traceprobe=nil;assert(t:find(""" &
         "function 'traceprobe.entry'"",1,true))");
   end Replaced_Public_Loaded;

   procedure Empty_Registry_Field;
   procedure Empty_Registry_Field is
   begin
      --  Empty string keys are valid registry names, not absence markers.
      --  A named module with an empty field still resolves its function.
      Check
        ("local f=assert(load('return function()coroutine.yield()en" &
         "d','@module.lua'))();package.loaded.traceprobe={['']=f};l" &
         "ocal co=coroutine.create(f);assert(coroutine.resume(co));" &
         "local t=debug.traceback(co);package.loaded.traceprobe=nil" &
         ";assert(t:find(""function 'traceprobe.'"",1,true))");
   end Empty_Registry_Field;

   procedure Tail_Marker;
   procedure Tail_Marker is
   begin
      --  A Lua tail replacement remains one actual logical frame.
      --  Its traceback advertises the lost callers with the standard marker.
      Check
        ("local function f()local t=debug.traceback();return t end;" &
         "local co=coroutine.create(function()return f()end);local " &
         "ok,t=coroutine.resume(co);assert(ok);assert(t:find('\n\t(" &
         "...tail calls...)',1,true))");
   end Tail_Marker;

   procedure Negative_Level;
   procedure Negative_Level is
   begin
      --  A negative stack level selects no frame in the pinned C API.
      --  Preserve the message and header without clamping to level zero.
      Check
        ("assert(debug.traceback(nil,-1)=='stack traceback:');asser" &
         "t(debug.traceback('hi',-9)=='hi\nstack traceback:')");
   end Negative_Level;

   procedure Level_Zero;
   procedure Level_Zero is
   begin
      --  An explicit zero level includes the debug.traceback native frame.
      --  Its call-site field name is traceback, without a private prefix.
      Check
        ("local t=debug.traceback(nil,0);assert(t:find(""[C]: in fie" &
         "ld 'traceback'"",1,true));assert(not t:find(""'debug.traceb" &
         "ack'"",1,true))");
   end Level_Zero;

   procedure Stripped_Location;
   procedure Stripped_Location is
   begin
      --  A stripped suspended Lua closure has no current line information.
      --  Omit the line separator but retain its real definition location.
      Check
        ("local f=assert(load(string.dump(function()coroutine.yield" &
         "()end,true)));local co=coroutine.create(f);assert(corouti" &
         "ne.resume(co));local t=debug.traceback(co);assert(t:match" &
         "('\n\t%?: in function <%?:%d+>'));assert(not t:find('?:0:" &
         "',1,true))");
   end Stripped_Location;

   procedure Deep_Stack;
   procedure Deep_Stack is
   begin
      --  A non-tail recursive coroutine creates thirty-one Lua frames.
      --  Keep ten initial and eleven final frames with the pinned skip count;
      --  the marker is not a fabricated frame and no callback executes.
      Check
        ("local function f(n)if n==0 then local t=debug.traceback()" &
         ";return t else return(f(n-1))end end;local co=coroutine.c" &
         "reate(f);local ok,t=coroutine.resume(co,30);assert(ok);lo" &
         "cal _,n=t:gsub('\n','');assert(n==22);assert(t:find('\n\t" &
         "...\t(skipping 9 levels)',1,true))");
   end Deep_Stack;

   procedure Short_Stack_Boundary;
   procedure Short_Stack_Boundary is
   begin
      --  Twenty-two selected Lua frames fit without shortening.
      --  One extra frame crosses the pinned threshold and adds its marker.
      Check
        ("local function f(n)if n==0 then local t=debug.traceback()" &
         ";return t else return(f(n-1))end end;local co=coroutine.c" &
         "reate(f);local ok,t=coroutine.resume(co,21);assert(ok);lo" &
         "cal _,n=t:gsub('\n','');assert(n==22 and not t:find('skip" &
         "ping',1,true));co=coroutine.create(f);ok,t=coroutine.resu" &
         "me(co,22);assert(ok);local _,n=t:gsub('\n','');assert(n==" &
         "22 and t:find('(skipping 1 levels)',1,true))");
   end Short_Stack_Boundary;

   procedure Unknown_Native;
   procedure Unknown_Native is
   begin
      --  Hide the only registered public identity before an indirect C call.
      --  An unnamed native frame has the public unknown marker; it must
      --  not expose the interpreter's private dispatch label.
      Check
        ("local p=pcall;_G.pcall=nil;local ok,t=(function()return p" &
         " end)()(debug.traceback);_G.pcall=p;assert(ok);assert(t:f" &
         "ind('\n\t[C]: in ?',1,true))");
   end Unknown_Native;

   procedure Hook_Tail_Fallback;
   procedure Hook_Tail_Fallback is
   begin
      --  A hook tail-calls a Lua helper and loses its original call origin.
      --  The replacement reports the public tail flag and no inferred name.
      Check
        ("local n=0;local function capture()local i=debug.getinfo(1" &
         ",'nt');assert(i.istailcall and i.namewhat=='' and i.name=" &
         "=nil);n=n+1 end;local co=coroutine.create(function()local" &
         " x=1 end);debug.sethook(co,function()return capture()end," &
         "'l');assert(coroutine.resume(co));assert(n>0)");
   end Hook_Tail_Fallback;

   procedure Hook_Descendant_Name;
   procedure Hook_Descendant_Name is
   begin
      --  An ordinary call made inside a hook still has its own call site.
      --  The hook origin must apply only to the actual callback frame.
      Check
        ("local n=0;local function child()local i=debug.getinfo(1,'" &
         "n');assert(i.namewhat=='upvalue' and i.name=='child');n=n" &
         "+1 end;local co=coroutine.create(function()local x=1 end)" &
         ";debug.sethook(co,function()child()end,'l');assert(corout" &
         "ine.resume(co));assert(n>0)");
   end Hook_Descendant_Name;


   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "traceback: Hook_Origin", Hook_Origin'Access);
      Test_Support.Add
        (Suite, "traceback: Local_Call_Name", Local_Call_Name'Access);
      Test_Support.Add
        (Suite, "traceback: Anonymous_Coroutine", Anonymous_Coroutine'Access);
      Test_Support.Add
        (Suite, "traceback: Native_Registry_Name",
         Native_Registry_Name'Access);
      Test_Support.Add
        (Suite, "traceback: Replaced_Public_Loaded",
         Replaced_Public_Loaded'Access);
      Test_Support.Add
        (Suite, "traceback: Empty_Registry_Field",
         Empty_Registry_Field'Access);
      Test_Support.Add
        (Suite, "traceback: Tail_Marker", Tail_Marker'Access);
      Test_Support.Add
        (Suite, "traceback: Negative_Level", Negative_Level'Access);
      Test_Support.Add
        (Suite, "traceback: Level_Zero", Level_Zero'Access);
      Test_Support.Add
        (Suite, "traceback: Stripped_Location", Stripped_Location'Access);
      Test_Support.Add
        (Suite, "traceback: Deep_Stack", Deep_Stack'Access);
      Test_Support.Add
        (Suite, "traceback: Short_Stack_Boundary",
         Short_Stack_Boundary'Access);
      Test_Support.Add
        (Suite, "traceback: Unknown_Native", Unknown_Native'Access);
      Test_Support.Add
        (Suite, "traceback: Hook_Tail_Fallback", Hook_Tail_Fallback'Access);
      Test_Support.Add
        (Suite, "traceback: Hook_Descendant_Name",
         Hook_Descendant_Name'Access);
   end Register;
end Debug_Traceback_Tests;
