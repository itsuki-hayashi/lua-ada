with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.File_Resources;
with Lua.Platform_Streams;
with Test_Support;
with System;

package body Lua.IO_Abort_Tests is
   package Streams renames Lua.Platform_Streams;
   use type Interfaces.C.int;

   function Save_Witness (File : Streams.Handle) return System.Address
     with Import, Convention => C,
       External_Name => "lua_ada_test_file_witness";
   function Is_Open (Witness : System.Address) return Interfaces.C.int
     with Import, Convention => C,
       External_Name => "lua_ada_test_file_is_open";

   generic
      with procedure Action (State : in out World);
   procedure Fixture;
   procedure Fixture is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Action (State);
      exception
         when others => Finalize (State); raise;
      end;
      Finalize (State);
   end Fixture;

   procedure Run (State : in out World; Source : String);
   procedure Run (State : in out World; Source : String) is
      Completed : constant Boolean :=
        Execute (State, Source, "file-abort-test");
   begin
      Assert (Completed,
              Failure_Image (State.Current));
   end Run;

   type Observation is record
      Witness : System.Address;
      Native : Streams.Handle;
      Serial : Positive;
   end record;
   function Observe (State : in out World) return Observation;
   function Observe (State : in out World) return Observation
   is
      File : constant Value :=
        Get (Global_Environment (State), New_String (State, "file"));
      Result : Observation;
   begin
      --  The global root retains this payload during the borrow. Afterward
      --  keep only native scalar witnesses, not an untraced Lua access value.
      Assert (File.Kind = Userdata_Kind, "fixture did not create real file");
      Result.Serial := File.Reference.Serial;
      Result.Native := File_Resources.Header (File).File;
      Result.Witness := Save_Witness (Result.Native);
      Assert (Is_Open (Result.Witness) /= 0,
              "fixture descriptor was not open");
      return Result;
   end Observe;

   function Contains (State : World; Serial : Positive) return Boolean;
   function Contains (State : World; Serial : Positive) return Boolean is
   begin
      for Item of State.Heap loop
         if Item /= null and then Item.Kind = Userdata_Object and then
           Item.Serial = Serial
         then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   procedure Abort_With_Resurrection (State : in out World);
   procedure Abort_Without_Resurrection (State : in out World);
   procedure Ordinary_Error_No_Fallback (State : in out World);

   procedure Abort_With_Resurrection (State : in out World) is
      Before : Observation;
      Completed : Boolean;
   begin
      --  The finalizer resurrects its real file and then exhausts the host's
      --  instruction quota. Aborting must not close a reachable global FILE.
      Run (State, "file=assert(io.tmpfile()); " &
           "getmetatable(file).__gc=function(p) " &
           "held=p; while true do end end");
      Before := Observe (State);
      State.Bounds.Instructions := 300;
      Completed := Execute
        (State, "file=nil; collectgarbage()", "resurrecting-abort");
      Assert (not Completed and then
                State.Current.Failure_Class = Host_Abort,
              "looping finalizer did not trigger controlled host abort");
      Assert (Is_Open (Before.Witness) /= 0,
              "host abort closed a resurrected reachable file");
      State.Bounds.Instructions := 1_000_000;
      Run (State, "assert(io.type(held)=='file'); held:write('still alive')");
      --  Only actual later unreachability permits forced non-Lua disposal of
      --  the consumed finalizer's owned resource; the callback cannot restart.
      Run (State, "held=nil; collectgarbage(); collectgarbage()");
      Assert (not Contains (State, Before.Serial),
              "aborted target remained rooted");
      Assert (Is_Open (Before.Witness) = 0,
              "unreachable aborted target leaked its native descriptor");
   end Abort_With_Resurrection;

   procedure Abort_Without_Resurrection (State : in out World) is
      Before : Observation;
      Completed : Boolean;
   begin
      --  A consumed finalizer with no surviving alias still owns a FILE until
      --  real reclamation. Its exceptional disposition must survive the
      --  aborted scheduler activation, not disappear with transient frames.
      Run (State, "file=assert(io.tmpfile()); " &
           "getmetatable(file).__gc=function() while true do end end");
      Before := Observe (State);
      State.Bounds.Instructions := 300;
      Completed := Execute
        (State, "file=nil; collectgarbage()", "unreachable-abort");
      Assert (not Completed and then
                State.Current.Failure_Class = Host_Abort,
              "unreachable finalizer did not abort");
      State.Bounds.Instructions := 1_000_000;
      Run (State, "collectgarbage(); collectgarbage()");
      Assert (not Contains (State, Before.Serial),
              "consumed finalizer was retained");
      Assert (Is_Open (Before.Witness) = 0,
              "aborted unreachable file lost its disposal obligation");
   end Abort_Without_Resurrection;

   procedure Ordinary_Error_No_Fallback (State : in out World) is
      Before : Observation;
      Error : aliased Interfaces.C.int := 0;
      Status : Interfaces.C.int;
   begin
      --  Ordinary Lua finalizer failure is deliberately different from host
      --  abort. It must preserve C's no-hidden-fclose semantics. Observe the
      --  saved descriptor before touching the native FILE for manual cleanup.
      Run (State, "file=assert(io.tmpfile()); " &
           "getmetatable(file).__gc=function() error('ordinary failure') end");
      Before := Observe (State);
      Run (State, "file=nil; collectgarbage(); collectgarbage()");
      Assert (not Contains (State, Before.Serial),
              "failed finalizer was retained");
      Assert (Is_Open (Before.Witness) /= 0,
              "ordinary finalizer error silently invoked host fclose");
      --  Reclamation released the Lua payload/metadata, so only this test's
      --  recognized still-open native stream remains. No userdata is read.
      Status := Streams.Close (Before.Native, Error'Access);
      Assert (Status = 0, "manual native fixture cleanup failed");
   end Ordinary_Error_No_Fallback;

   procedure Case_Resurrection is new Fixture (Abort_With_Resurrection);
   procedure Case_Unreachable is new Fixture (Abort_Without_Resurrection);
   procedure Case_Ordinary is new Fixture (Ordinary_Error_No_Fallback);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "IO abort: retained resurrection stays open",
                        Case_Resurrection'Access);
      Test_Support.Add (Suite, "IO abort: unreachable file retains disposal",
                        Case_Unreachable'Access);
      Test_Support.Add (Suite, "IO abort: Lua failure does not force fclose",
                        Case_Ordinary'Access);
   end Register;
end Lua.IO_Abort_Tests;
