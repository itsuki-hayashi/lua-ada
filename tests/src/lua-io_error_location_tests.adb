with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.IO_Error_Location_Tests is
   use type Lua.Storage.Byte_Count;
   procedure Check (Source : String);
   procedure Check (Source : String) is
      State : World;
   begin
      Initialize (State, (others => <>));
      Assert (Execute (State, Source, "io-location"),
              Failure_Image (State.Current));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "IO error fixture releases actual managed storage");
   exception
      when others => Finalize (State); raise;
   end Check;

   procedure Output_Named;
   procedure Output_Named is
   begin
      --  Execute only this source-linked public IO boundary; the native
      --  companion fixture exercises the same setup and exact assertion.
      Check
        ("-- Auxiliary IO failures use the actual " &
         "immediate public caller's location." & ASCII.LF &
         "local path='missing-io-parent-72bc472c12" &
         "e74b2787889d993035891f/file'" & ASCII.LF &
         "local detail=""cannot open file '""..path." &
         ".""' (No such file or directory)""" & ASCII.LF &
         "local function caught(f,...)" & ASCII.LF &
         "  local ok,msg=pcall(f,...)" & ASCII.LF &
         "  assert(not ok and type(msg)=='string')" & ASCII.LF &
         "  return msg" & ASCII.LF &
         "end" & ASCII.LF &
         "local function named(operation,name)" & ASCII.LF &
         "  return assert(load('return function(pa" &
         "th)\n  io.'..operation..'(path)\nend',na" &
         "me))()" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local f=named('output','@io-output-sit" &
         "e.lua')" & ASCII.LF &
         "  assert(caught(f,path)=='io-output-site" &
         ".lua:2: '..detail)" & ASCII.LF &
         "end");
   end Output_Named;

   procedure Input_Named;
   procedure Input_Named is
   begin
      --  Execute only this source-linked public IO boundary; the native
      --  companion fixture exercises the same setup and exact assertion.
      Check
        ("-- Auxiliary IO failures use the actual " &
         "immediate public caller's location." & ASCII.LF &
         "local path='missing-io-parent-72bc472c12" &
         "e74b2787889d993035891f/file'" & ASCII.LF &
         "local detail=""cannot open file '""..path." &
         ".""' (No such file or directory)""" & ASCII.LF &
         "local function caught(f,...)" & ASCII.LF &
         "  local ok,msg=pcall(f,...)" & ASCII.LF &
         "  assert(not ok and type(msg)=='string')" & ASCII.LF &
         "  return msg" & ASCII.LF &
         "end" & ASCII.LF &
         "local function named(operation,name)" & ASCII.LF &
         "  return assert(load('return function(pa" &
         "th)\n  io.'..operation..'(path)\nend',na" &
         "me))()" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local f=named('input','@io-input-site." &
         "lua')" & ASCII.LF &
         "  assert(caught(f,path)=='io-input-site." &
         "lua:2: '..detail)" & ASCII.LF &
         "end");
   end Input_Named;

   procedure Output_C_Caller;
   procedure Output_C_Caller is
   begin
      --  Execute only this source-linked public IO boundary; the native
      --  companion fixture exercises the same setup and exact assertion.
      Check
        ("-- Auxiliary IO failures use the actual " &
         "immediate public caller's location." & ASCII.LF &
         "local path='missing-io-parent-72bc472c12" &
         "e74b2787889d993035891f/file'" & ASCII.LF &
         "local detail=""cannot open file '""..path." &
         ".""' (No such file or directory)""" & ASCII.LF &
         "local function caught(f,...)" & ASCII.LF &
         "  local ok,msg=pcall(f,...)" & ASCII.LF &
         "  assert(not ok and type(msg)=='string')" & ASCII.LF &
         "  return msg" & ASCII.LF &
         "end" & ASCII.LF &
         "local function named(operation,name)" & ASCII.LF &
         "  return assert(load('return function(pa" &
         "th)\n  io.'..operation..'(path)\nend',na" &
         "me))()" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  assert(caught(io.output,path)==detail)" & ASCII.LF &
         "end");
   end Output_C_Caller;

   procedure Input_C_Caller;
   procedure Input_C_Caller is
   begin
      --  Execute only this source-linked public IO boundary; the native
      --  companion fixture exercises the same setup and exact assertion.
      Check
        ("-- Auxiliary IO failures use the actual " &
         "immediate public caller's location." & ASCII.LF &
         "local path='missing-io-parent-72bc472c12" &
         "e74b2787889d993035891f/file'" & ASCII.LF &
         "local detail=""cannot open file '""..path." &
         ".""' (No such file or directory)""" & ASCII.LF &
         "local function caught(f,...)" & ASCII.LF &
         "  local ok,msg=pcall(f,...)" & ASCII.LF &
         "  assert(not ok and type(msg)=='string')" & ASCII.LF &
         "  return msg" & ASCII.LF &
         "end" & ASCII.LF &
         "local function named(operation,name)" & ASCII.LF &
         "  return assert(load('return function(pa" &
         "th)\n  io.'..operation..'(path)\nend',na" &
         "me))()" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  assert(caught(io.input,path)==detail)" & ASCII.LF &
         "end");
   end Input_C_Caller;

   procedure Stripped_Caller;
   procedure Stripped_Caller is
   begin
      --  Execute only this source-linked public IO boundary; the native
      --  companion fixture exercises the same setup and exact assertion.
      Check
        ("-- Auxiliary IO failures use the actual " &
         "immediate public caller's location." & ASCII.LF &
         "local path='missing-io-parent-72bc472c12" &
         "e74b2787889d993035891f/file'" & ASCII.LF &
         "local detail=""cannot open file '""..path." &
         ".""' (No such file or directory)""" & ASCII.LF &
         "local function caught(f,...)" & ASCII.LF &
         "  local ok,msg=pcall(f,...)" & ASCII.LF &
         "  assert(not ok and type(msg)=='string')" & ASCII.LF &
         "  return msg" & ASCII.LF &
         "end" & ASCII.LF &
         "local function named(operation,name)" & ASCII.LF &
         "  return assert(load('return function(pa" &
         "th)\n  io.'..operation..'(path)\nend',na" &
         "me))()" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local f=named('output','@io-stripped-s" &
         "ite.lua')" & ASCII.LF &
         "  local stripped=assert(load(string.dump" &
         "(f,true)))" & ASCII.LF &
         "  assert(caught(stripped,path)==detail)" & ASCII.LF &
         "end");
   end Stripped_Caller;

   procedure Binary_Source_Name;
   procedure Binary_Source_Name is
   begin
      --  Execute only this source-linked public IO boundary; the native
      --  companion fixture exercises the same setup and exact assertion.
      Check
        ("-- Auxiliary IO failures use the actual " &
         "immediate public caller's location." & ASCII.LF &
         "local path='missing-io-parent-72bc472c12" &
         "e74b2787889d993035891f/file'" & ASCII.LF &
         "local detail=""cannot open file '""..path." &
         ".""' (No such file or directory)""" & ASCII.LF &
         "local function caught(f,...)" & ASCII.LF &
         "  local ok,msg=pcall(f,...)" & ASCII.LF &
         "  assert(not ok and type(msg)=='string')" & ASCII.LF &
         "  return msg" & ASCII.LF &
         "end" & ASCII.LF &
         "local function named(operation,name)" & ASCII.LF &
         "  return assert(load('return function(pa" &
         "th)\n  io.'..operation..'(path)\nend',na" &
         "me))()" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local f=named('output','@io-source'..s" &
         "tring.char(0)..'hidden')" & ASCII.LF &
         "  assert(caught(f,path)=='io-source:2: '" &
         "..detail)" & ASCII.LF &
         "end");
   end Binary_Source_Name;

   procedure Returned_File_Error;
   procedure Returned_File_Error is
   begin
      --  Execute only this source-linked public IO boundary; the native
      --  companion fixture exercises the same setup and exact assertion.
      Check
        ("-- Auxiliary IO failures use the actual " &
         "immediate public caller's location." & ASCII.LF &
         "local path='missing-io-parent-72bc472c12" &
         "e74b2787889d993035891f/file'" & ASCII.LF &
         "local detail=""cannot open file '""..path." &
         ".""' (No such file or directory)""" & ASCII.LF &
         "local function caught(f,...)" & ASCII.LF &
         "  local ok,msg=pcall(f,...)" & ASCII.LF &
         "  assert(not ok and type(msg)=='string')" & ASCII.LF &
         "  return msg" & ASCII.LF &
         "end" & ASCII.LF &
         "local function named(operation,name)" & ASCII.LF &
         "  return assert(load('return function(pa" &
         "th)\n  io.'..operation..'(path)\nend',na" &
         "me))()" & ASCII.LF &
         "end" & ASCII.LF &
         "" & ASCII.LF &
         "do" & ASCII.LF &
         "  local result=table.pack(io.open(path,'" &
         "r'))" & ASCII.LF &
         "  assert(result.n==3 and result[1]==nil)" & ASCII.LF &
         "  assert(result[2]==path..': No such fil" &
         "e or directory')" & ASCII.LF &
         "  assert(result[3]==2 and math.type(resu" &
         "lt[3])=='integer')" & ASCII.LF &
         "end");
   end Returned_File_Error;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "IO error location: output named",
         Output_Named'Access);
      Test_Support.Add
        (Suite, "IO error location: input named",
         Input_Named'Access);
      Test_Support.Add
        (Suite, "IO error location: output c caller",
         Output_C_Caller'Access);
      Test_Support.Add
        (Suite, "IO error location: input c caller",
         Input_C_Caller'Access);
      Test_Support.Add
        (Suite, "IO error location: stripped caller",
         Stripped_Caller'Access);
      Test_Support.Add
        (Suite, "IO error location: binary source name",
         Binary_Source_Name'Access);
      Test_Support.Add
        (Suite, "IO error location: returned file error",
         Returned_File_Error'Access);
   end Register;
end Lua.IO_Error_Location_Tests;
