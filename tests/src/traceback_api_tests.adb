with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Traceback_API_Tests is
   use type Interfaces.C.int;
   function Check (Which : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_traceback";
   procedure Lua_Nul_Message;
   procedure Lua_Numeric_Message;
   procedure Lua_Message_Identity;
   procedure Lua_Level_Cast;
   procedure Message_Work_Quota;
   procedure Result_Extent_Quota;
   procedure Deep_Stack;
   procedure Shortening_Boundary;
   procedure Hook_Origin;
   procedure Closed_Thread;
   procedure No_Message;
   procedure Host_Message;
   procedure Empty_Message;
   procedure Nul_Message;
   procedure Negative_Level;
   procedure Nested_Frames;
   procedure Skip_Current;
   procedure Out_Of_Stack;
   procedure Stack_Prefix;
   procedure Inactive_Thread;
   procedure Suspended_Thread;
   procedure Independent_Destination;
   procedure Shared_Lua_Renderer;
   procedure Refusal_And_Retry;

   --  A host with no frames returns only the heading when message is null.
   procedure No_Message is
   begin
      Assert (Check (0) = 1, "public traceback: no_message");
   end No_Message;

   --  A nonempty message precedes the heading with exactly one newline.
   procedure Host_Message is
   begin
      Assert (Check (1) = 1, "public traceback: host_message");
   end Host_Message;

   --  An empty nonnull message still contributes its separating newline.
   procedure Empty_Message is
   begin
      Assert (Check (2) = 1, "public traceback: empty_message");
   end Empty_Message;

   --  A message stops at the first C NUL without copying its suffix.
   procedure Nul_Message is
   begin
      Assert (Check (3) = 1, "public traceback: nul_message");
   end Nul_Message;

   --  A negative level suppresses actual frames without changing the prefix.
   procedure Negative_Level is
   begin
      Assert (Check (4) = 1, "public traceback: negative_level");
   end Negative_Level;

   --  Real nested C and Lua frames retain exact names, sources and lines.
   procedure Nested_Frames is
   begin
      Assert (Check (5) = 1, "public traceback: nested_frames");
   end Nested_Frames;

   --  Level one skips the current C callback while retaining its Lua caller.
   procedure Skip_Current is
   begin
      Assert (Check (6) = 1, "public traceback: skip_current");
   end Skip_Current;

   --  A level beyond the actual stack returns only the heading.
   procedure Out_Of_Stack is
   begin
      Assert (Check (7) = 1, "public traceback: out_of_stack");
   end Out_Of_Stack;

   --  The result appends above intact table identity and integer prefix slots.
   procedure Stack_Prefix is
   begin
      Assert (Check (8) = 1, "public traceback: stack_prefix");
   end Stack_Prefix;

   --  An inactive thread contributes no invented activations or stack values.
   procedure Inactive_Thread is
   begin
      Assert (Check (9) = 1, "public traceback: inactive_thread");
   end Inactive_Thread;

   --  A suspended thread retains yield metadata and resumes after inspection.
   procedure Suspended_Thread is
   begin
      Assert (Check (10) = 1, "public traceback: suspended_thread");
   end Suspended_Thread;

   --  An independent destination owns output without modifying the source.
   procedure Independent_Destination is
   begin
      Assert (Check (11) = 1, "public traceback: independent_destination");
   end Independent_Destination;

   --  The Lua debug function and C auxiliary export share exact rendering.
   procedure Shared_Lua_Renderer is
   begin
      Assert (Check (12) = 1, "public traceback: shared_lua_renderer");
   end Shared_Lua_Renderer;

   --  Actual refusal is catchable; retry and close release every block.
   procedure Refusal_And_Retry is
   begin
      Assert (Check (13) = 1, "public traceback: refusal_and_retry");
   end Refusal_And_Retry;

   --  The Lua wrapper renders only the C prefix of a counted NUL message.
   procedure Lua_Nul_Message is
   begin
      Assert (Check (14) = 1, "public traceback: lua_nul_message");
   end Lua_Nul_Message;

   --  A numeric message retains the pinned conversion before rendering.
   procedure Lua_Numeric_Message is
   begin
      Assert (Check (15) = 1, "public traceback: lua_numeric_message");
   end Lua_Numeric_Message;

   --  A nonstring message returns by identity without validating its level.
   procedure Lua_Message_Identity is
   begin
      Assert (Check (16) = 1, "public traceback: lua_message_identity");
   end Lua_Message_Identity;

   --  Lua levels wrap through the actual C-int cast before frame selection.
   procedure Lua_Level_Cast is
   begin
      Assert (Check (17) = 1, "public traceback: lua_level_cast");
   end Lua_Level_Cast;

   --  A deep real stack retains the pinned first/last frames and skip count.
   procedure Deep_Stack is
   begin
      Assert (Check (18) = 1, "public traceback: deep_stack");
   end Deep_Stack;

   --  The 22/23-frame boundary selects shortening without invented frames.
   procedure Shortening_Boundary is
   begin
      Assert (Check (19) = 1, "public traceback: shortening_boundary");
   end Shortening_Boundary;

   --  A C query from a line hook retains the actual hooked caller origin.
   procedure Hook_Origin is
   begin
      Assert (Check (20) = 1, "public traceback: hook_origin");
   end Hook_Origin;

   --  A successfully closed thread contributes no stale suspended frames.
   procedure Closed_Thread is
   begin
      Assert (Check (21) = 1, "public traceback: closed_thread");
   end Closed_Thread;

   procedure Message_Work_Quota is
      Universe : Session;
   begin
      --  Prepare the input before reducing the instruction budget, so only
      --  actual traceback scanning/copying can exhaust this small execution.
      Assert (Universe.Execute ("message=string.rep('x',700)").Status =
                Succeeded, "prepare retained message");
      Universe.Set_Limits ((Instructions => 1_000, others => <>));
      declare
         Result : constant Execution_Result := Universe.Execute
           ("pcall(debug.traceback,message,-1);error('quota was caught')");
      begin
         Assert (Result.Status = Resource_Error,
                 To_String (Result.Error.Message));
      end;
      Assert (Universe.Execute ("return 37").Status = Succeeded,
              "traceback host stop damaged reusable session");
   end Message_Work_Quota;

   procedure Result_Extent_Quota is
      Universe : Session;
   begin
      --  The retained input predates the result ceiling. Its diagnostic
      --  builder must release on refusal and pcall cannot hide host policy.
      Assert (Universe.Execute ("message=string.rep('x',700)").Status =
                Succeeded, "prepare retained message");
      Universe.Set_Limits ((String_Bytes => 200, others => <>));
      declare
         Result : constant Execution_Result := Universe.Execute
           ("pcall(debug.traceback,message,-1);error('extent was caught')");
      begin
         Assert (Result.Status = Resource_Error,
                 To_String (Result.Error.Message));
      end;
      Assert (Universe.Execute ("return 37").Status = Succeeded,
              "traceback extent stop damaged reusable session");
   end Result_Extent_Quota;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "public traceback: no message",
                        No_Message'Access);
      Test_Support.Add (Suite, "public traceback: host message",
                        Host_Message'Access);
      Test_Support.Add (Suite, "public traceback: empty message",
                        Empty_Message'Access);
      Test_Support.Add (Suite, "public traceback: nul message",
                        Nul_Message'Access);
      Test_Support.Add (Suite, "public traceback: negative level",
                        Negative_Level'Access);
      Test_Support.Add (Suite, "public traceback: nested frames",
                        Nested_Frames'Access);
      Test_Support.Add (Suite, "public traceback: skip current",
                        Skip_Current'Access);
      Test_Support.Add (Suite, "public traceback: out of stack",
                        Out_Of_Stack'Access);
      Test_Support.Add (Suite, "public traceback: stack prefix",
                        Stack_Prefix'Access);
      Test_Support.Add (Suite, "public traceback: inactive thread",
                        Inactive_Thread'Access);
      Test_Support.Add (Suite, "public traceback: suspended thread",
                        Suspended_Thread'Access);
      Test_Support.Add (Suite, "public traceback: independent destination",
                        Independent_Destination'Access);
      Test_Support.Add (Suite, "public traceback: shared lua renderer",
                        Shared_Lua_Renderer'Access);
      Test_Support.Add (Suite, "public traceback: refusal and retry",
                        Refusal_And_Retry'Access);
      Test_Support.Add (Suite, "public traceback: lua nul message",
                        Lua_Nul_Message'Access);
      Test_Support.Add (Suite, "public traceback: lua numeric message",
                        Lua_Numeric_Message'Access);
      Test_Support.Add (Suite, "public traceback: lua message identity",
                        Lua_Message_Identity'Access);
      Test_Support.Add (Suite, "public traceback: lua level cast",
                        Lua_Level_Cast'Access);
      Test_Support.Add (Suite, "public traceback: deep stack",
                        Deep_Stack'Access);
      Test_Support.Add (Suite, "public traceback: shortening boundary",
                        Shortening_Boundary'Access);
      Test_Support.Add (Suite, "public traceback: hook origin",
                        Hook_Origin'Access);
      Test_Support.Add (Suite, "public traceback: closed thread",
                        Closed_Thread'Access);
      Test_Support.Add (Suite, "public traceback: message work quota",
                        Message_Work_Quota'Access);
      Test_Support.Add (Suite, "public traceback: result extent quota",
                        Result_Extent_Quota'Access);
   end Register;
end Traceback_API_Tests;
