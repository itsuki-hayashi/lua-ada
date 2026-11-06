with Ada.Unchecked_Deallocation;
with Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Compiler;
with Lua.Engine.Machine;
with Lua.Engine.Stacks;
with Lua.Engine.Warnings;
with System.Storage_Elements;
with Test_Support;

package body Lua.Warning_Tests is
   use type Interfaces.C.unsigned_long_long;
   package VM renames Lua.Engine.Machine;
   package Alerts renames Lua.Engine.Warnings;
   procedure Free_World is new Ada.Unchecked_Deallocation
     (World, World_Access);

   generic
      with procedure Action (State : World_Access);
   procedure Fixture;

   procedure Fixture is
      State : World_Access := new World;
   begin
      Initialize (State.all, (others => <>));
      begin
         Action (State);
      exception
         when others =>
            Finalize (State.all);
            Free_World (State);
            raise;
      end;
      Finalize (State.all);
      Free_World (State);
   end Fixture;

   procedure Start (State : World_Access; Driver : in out VM.Driver);
   procedure Finish (Driver : in out VM.Driver);
   procedure Default_Mode (State : World_Access);
   procedure Default_Controls (State : World_Access);
   procedure Validate_All_Arguments (State : World_Access);
   procedure Numeric_Arguments (State : World_Access);
   procedure Owned_Message_Root (State : World_Access);
   procedure Invalid_Event_Token (State : World_Access);
   procedure Nested_Event_Roots (State : World_Access);
   procedure Borrowed_Window_Roots (State : World_Access);

   procedure Start (State : World_Access; Driver : in out VM.Driver) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "local x=1;x=x+1;return x", "warning-origin");
   begin
      VM.Start (Driver, State, Code);
      State.Warning_Mode := Custom_Warning_Handler;
      --  Private queue tests do not call this nonnull sentinel. Actual C
      --  callbacks and their userdata are exercised by the plain C consumer.
      State.Warning_Handler := System.Storage_Elements.To_Address (1);
   end Start;

   procedure Finish (Driver : in out VM.Driver) is
   begin
      for Iteration in 1 .. 100 loop
         exit when VM.Is_Complete (Driver);
         VM.Step (Driver);
      end loop;
      Assert (VM.Is_Complete (Driver), "warning origin did not complete");
      VM.Finish (Driver);
   end Finish;

   procedure Default_Mode (State : World_Access) is
   begin
      --  Lua5.5.1 luaL_newstate installs warnfon, unlike older assumptions.
      --  Ada initialization follows that default, independently of stdout.
      Assert (State.Warning_Mode = Default_Warnings_On,
              "session default warnings are not enabled");
      Assert (State.Warning_Head = null, "initial pending warning");
   end Default_Mode;

   procedure Default_Controls (State : World_Access) is
   begin
      --  Off ignores continued controls; only a final @on enables output.
      --  Unknown commands remain invisible instead of becoming messages.
      Emit_Warning (State.all, New_String (State.all, "@off"));
      Assert (State.Warning_Mode = Default_Warnings_Off, "off control");
      Emit_Warning (State.all, New_String (State.all, "@on"), True);
      Assert (State.Warning_Mode = Default_Warnings_Off, "continued control");
      Emit_Warning (State.all, New_String (State.all, "@unknown"));
      Emit_Warning (State.all, New_String (State.all, "@on"));
      Assert (State.Warning_Mode = Default_Warnings_On, "on control");
      Emit_Warning (State.all, New_String (State.all, "@unknown"));
      Assert (State.Warning_Mode = Default_Warnings_On, "unknown control");
   end Default_Controls;

   procedure Validate_All_Arguments (State : World_Access) is
   begin
      --  No warning fragment may precede a later argument error. @on would
      --  expose an incorrect early emission by changing the mode from off.
      Assert (Execute (State.all,
        "warn('@off');local ok,e=pcall(warn,'@on',{});" &
        "assert(not ok and type(e)=='string')", "warning-validation"),
        "warn did not reject its later nonstring argument");
      Assert (State.Warning_Mode = Default_Warnings_Off,
              "warn emitted before validating every argument");
   end Validate_All_Arguments;

   procedure Numeric_Arguments (State : World_Access) is
   begin
      --  luaL_checkstring converts numbers, and warn returns no results.
      --  Turning output off isolates these semantics from process stderr.
      Assert (Execute (State.all,
        "warn('@off');assert(select('#',warn(12,2.5))==0);" &
        "assert(not pcall(warn))", "warning-numbers"),
        "numeric warning conversion or result adjustment failed");
   end Numeric_Arguments;

   procedure Owned_Message_Root (State : World_Access) is
      Driver : VM.Driver;
      Message : Value;
      Token : Callback_Identity;
   begin
      --  The embedded event is the sole Lua reference across collection.
      --  Acknowledgment releases it after the C consumer could use the view.
      Start (State, Driver);
      Message := New_String (State.all, "owned-warning-message");
      Emit_Warning (State.all, Message);
      Collect (State.all);
      Assert (State.Heap.Contains (Message.Reference), "warning was unrooted");
      Token := Alerts.Identity (State.all);
      Alerts.Begin_Callback (State.all);
      Alerts.Acknowledge (State.all, Token);
      Finish (Driver);
      Collect (State.all);
      Assert (not State.Heap.Contains (Message.Reference),
              "acknowledged warning retained its message");
   end Owned_Message_Root;

   procedure Invalid_Event_Token (State : World_Access) is
      Driver : VM.Driver;
      Token, Invalid : Callback_Identity;
      Rejected : Boolean := False;
   begin
      --  A wrong serial cannot pop an event or release its borrowed bytes.
      --  The original guard identity still acknowledges that same event.
      Start (State, Driver);
      Emit_Warning (State.all, New_String (State.all, "token"));
      Token := Alerts.Identity (State.all);
      Alerts.Begin_Callback (State.all);
      Invalid := Token;
      Invalid.Serial := Invalid.Serial + 1;
      begin
         Alerts.Acknowledge (State.all, Invalid);
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected and then State.Warning_Head /= null,
              "wrong warning identity released the event");
      Alerts.Acknowledge (State.all, Token);
      Finish (Driver);
   end Invalid_Event_Token;

   procedure Nested_Event_Roots (State : World_Access) is
      Driver : VM.Driver;
      Outer, Inner : Value;
      Outer_Token, Inner_Token : Callback_Identity;
      Holder : Frame_Access;
   begin
      --  Reentrant work has another real holder. Its event temporarily tops
      --  the linked queue; both message roots must survive a nested collect.
      Start (State, Driver);
      Outer := New_String (State.all, "outer-warning");
      Emit_Warning (State.all, Outer);
      Outer_Token := Alerts.Identity (State.all);
      Alerts.Begin_Callback (State.all);
      Holder := New_Frame (State.all);
      State.Current.Stack.Append (Holder);
      Holder.Is_Native := True;
      Holder.Native_Name :=
        Ada.Strings.Unbounded.To_Unbounded_String ("@warning-test");
      Inner := New_String (State.all, "inner-warning");
      Emit_Warning (State.all, Inner);
      Inner_Token := Alerts.Identity (State.all);
      Alerts.Begin_Callback (State.all);
      Collect (State.all);
      Assert (State.Heap.Contains (Outer.Reference) and then
                State.Heap.Contains (Inner.Reference), "nested roots lost");
      Alerts.Acknowledge (State.all, Inner_Token);
      State.Current.Stack.Delete_Last;
      Return_Frame (Holder);
      Assert (State.Warning_Head /= null and then
                State.Warning_Head.Warning_Ticket = Outer_Token.Serial,
              "nested callback replaced its outer event");
      Alerts.Acknowledge (State.all, Outer_Token);
      Finish (Driver);
   end Nested_Event_Roots;

   procedure Borrowed_Window_Roots (State : World_Access) is
      Driver : VM.Driver;
      Token : Callback_Identity;
      Window : Frame_Access;
      Item : Value;
      Top : Natural;
      Depth : Natural;
   begin
      --  A custom warnf often uses its lua_State userdata. API pushes borrow
      --  the real current window and remain GC roots without a fake frame.
      Start (State, Driver);
      Window := State.Current.Stack_Window;
      Depth := Natural (State.Current.Stack.Length);
      Emit_Warning (State.all, New_String (State.all, "borrow"));
      Token := Alerts.Identity (State.all);
      Alerts.Begin_Callback (State.all);
      Top := State.Current.Foreign_Top + 1;
      Item := New_Table (State.all);
      Lua.Engine.Stacks.Write (State.all, State.Current, Top, Item);
      State.Current.Foreign_Top := Top;
      Window.Stack_Live_Top := Top;
      Collect (State.all);
      Assert (State.Heap.Contains (Item.Reference), "borrowed push unrooted");
      Assert (Natural (State.Current.Stack.Length) = Depth,
              "warning introduced a logical debug frame");
      Alerts.Acknowledge (State.all, Token);
      Finish (Driver);
   end Borrowed_Window_Roots;

   procedure Native_Trim_Roots (State : World_Access);
   procedure Native_Grow_Nils (State : World_Access);
   procedure Native_Push_Root (State : World_Access);

   procedure Native_Trim_Roots (State : World_Access) is
      Driver : VM.Driver;
      Args : Values.Vector := Owned_Values (State.all);
      Removed : Value;
      Activation : Frame_Access;
   begin
      --  IO iterator control arguments are discarded before reads. Both
      --  the actual slots and owned native view must stop retaining them.
      Args.Append (Value'(Integer_Kind, 7));
      Removed := New_Table (State.all);
      Args.Append (Removed);
      VM.Start (Driver, State, New_Native (State.all, "base.print"), Args);
      Args.Clear;
      Activation := State.Current.Stack.Last_Element;
      VM.Set_Native_Top (State.all, Activation, 1);
      Assert (Natural (Activation.Native_Arguments.Length) = 1 and then
                Activation.Stack_Live_Top = Activation.Stack_Base + 1,
              "trim left competing native argument views");
      Collect (State.all);
      Assert (not State.Heap.Contains (Removed.Reference),
              "discarded iterator control remains a root");
      Finish (Driver);
   end Native_Trim_Roots;

   procedure Native_Grow_Nils (State : World_Access) is
      Driver : VM.Driver;
      Args : Values.Vector := One_Value (State.all, (Integer_Kind, 7));
      Activation : Frame_Access;
   begin
      --  lua_settop growth creates actual nil slots. Ada-native code sees
      --  the same nils through its argument packet, with a consistent top.
      VM.Start (Driver, State, New_Native (State.all, "base.print"), Args);
      Args.Clear;
      Activation := State.Current.Stack.Last_Element;
      VM.Set_Native_Top (State.all, Activation, 4);
      for Index in 2 .. 4 loop
         Assert (Activation.Native_Arguments (Index).Kind = Nil_Kind and then
                   Lua.Engine.Stacks.Read
                     (State.Current, Activation.Stack_Base + Index).Kind =
                       Nil_Kind, "grown native slots disagree");
      end loop;
      Assert (State.Current.Foreign_Top = Activation.Stack_Base + 4,
              "grown native public top differs");
      Finish (Driver);
   end Native_Grow_Nils;

   procedure Native_Push_Root (State : World_Access) is
      Driver : VM.Driver;
      Activation : Frame_Access;
      Item : Value;
   begin
      --  Default IO files are pushed before reservation checks. Publication
      --  through this helper must retain one value in both actual views.
      VM.Start (Driver, State, New_Native (State.all, "base.print"),
                State.Current.Arguments);
      Activation := State.Current.Stack.Last_Element;
      Item := New_Table (State.all);
      VM.Push_Native_Value (State.all, Activation, Item);
      Collect (State.all);
      Assert (State.Heap.Contains (Item.Reference) and then
                Activation.Native_Arguments (1) = Item and then
                Lua.Engine.Stacks.Read
                  (State.Current, Activation.Stack_Base + 1) = Item,
              "native push was not published into both roots");
      Finish (Driver);
   end Native_Push_Root;

   procedure Trim_Case is new Fixture (Native_Trim_Roots);
   procedure Grow_Case is new Fixture (Native_Grow_Nils);
   procedure Push_Case is new Fixture (Native_Push_Root);
   procedure Default_Case is new Fixture (Default_Mode);
   procedure Controls_Case is new Fixture (Default_Controls);
   procedure Validation_Case is new Fixture (Validate_All_Arguments);
   procedure Numeric_Case is new Fixture (Numeric_Arguments);
   procedure Root_Case is new Fixture (Owned_Message_Root);
   procedure Token_Case is new Fixture (Invalid_Event_Token);
   procedure Nested_Case is new Fixture (Nested_Event_Roots);
   procedure Borrow_Case is new Fixture (Borrowed_Window_Roots);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "native stack: discarded argument roots",
                        Trim_Case'Access);
      Test_Support.Add (Suite, "native stack: grown nil slots",
                        Grow_Case'Access);
      Test_Support.Add (Suite, "native stack: pushed root publication",
                        Push_Case'Access);
      Test_Support.Add (Suite, "warnings: session default on",
                        Default_Case'Access);
      Test_Support.Add (Suite, "warnings: default control commands",
                        Controls_Case'Access);
      Test_Support.Add (Suite, "warnings: validate all arguments first",
                        Validation_Case'Access);
      Test_Support.Add (Suite, "warnings: numeric strings and no results",
                        Numeric_Case'Access);
      Test_Support.Add (Suite, "warnings: owned message root",
                        Root_Case'Access);
      Test_Support.Add (Suite, "warnings: exact event identity",
                        Token_Case'Access);
      Test_Support.Add (Suite, "warnings: nested event roots",
                        Nested_Case'Access);
      Test_Support.Add (Suite, "warnings: actual borrowed stack roots",
                        Borrow_Case'Access);
   end Register;
end Lua.Warning_Tests;
