with Ada.Strings.Fixed;
with Interfaces.C;
with Lua.Platform_Streams;
with Lua.Engine.Stacks;
with System;

package body Lua.Engine.Warnings is
   use type Interfaces.C.size_t;
   use type Interfaces.C.unsigned_long_long;
   use type System.Address;

   Prefix : aliased constant String := "Lua warning: " & Character'Val (0);
   New_Line : aliased constant String :=
     Character'Val (10) & Character'Val (0);

   function C_View (Message : Byte_String) return Byte_String;
   procedure Write (Message : Byte_String);
   procedure Restore_View (Activation : not null Frame_Access);

   function C_View (Message : Byte_String) return Byte_String is
      Result : Byte_String := Message;
   begin
      --  Lua strings are byte strings, whereas lua_warning receives a C
      --  string. Embedded NUL ends this particular warning fragment.
      for Index in 1 .. Message.Size loop
         if Element (Message, Index) = Character'Val (0) then
            Result.Size := Index - 1;
            exit;
         end if;
      end loop;
      return Result;
   end C_View;

   procedure Write (Message : Byte_String) is
      Error : aliased Interfaces.C.int := 0;
      Written : Interfaces.C.size_t;
   begin
      --  Pinned warning output is stderr, independently of captured stdout.
      --  Like lua_writestringerror, a host stdio error is not a Lua error.
      Written := Lua.Platform_Streams.Write
        (Lua.Platform_Streams.Standard
           (Lua.Platform_Streams.Standard_Error), Message.Address,
         Interfaces.C.size_t (Message.Size), Error'Access);
      if Written /= Interfaces.C.size_t (Message.Size) then
         return;
      end if;
   end Write;

   procedure Emit
     (State : in out World; Message : Value;
      To_Continue : Boolean := False)
   is
   begin
      if Message.Kind /= String_Kind then
         raise Program_Error with "warning requires its owned string value";
      end if;
      Emit (State, Message.Reference.Bytes, Message, To_Continue);
   end Emit;

   procedure Emit
     (State : in out World; Message : Byte_String;
      Root : Value := Nil_Value; To_Continue : Boolean := False)
   is
      Text : constant Byte_String := C_View (Message);
      Activation : Frame_Access;
   begin
      if State.Warning_Mode = No_Warning_Handler then
         return;
      elsif State.Warning_Mode /= Custom_Warning_Handler then
         --  Only the default auxiliary handler interprets control commands.
         --  A continued fragment, including an @off spelling, is plain text.
         if State.Warning_Mode /= Default_Warning_Continuation and then
           not To_Continue and then Text.Size /= 0 and then
           Element (Text, 1) = '@'
         then
            if Text = "@on" then
               State.Warning_Mode := Default_Warnings_On;
            elsif Text = "@off" then
               State.Warning_Mode := Default_Warnings_Off;
            end if;
            return;
         elsif State.Warning_Mode = Default_Warnings_Off then
            return;
         end if;
         if State.Warning_Mode = Default_Warnings_On then
            Write ((Prefix (Prefix'First)'Address, Prefix'Length - 1));
         end if;
         Write (Text);
         if To_Continue then
            State.Warning_Mode := Default_Warning_Continuation;
         else
            Write ((New_Line (New_Line'First)'Address, 1));
            State.Warning_Mode := Default_Warnings_On;
         end if;
         return;
      end if;
      if State.Current.Stack.Is_Empty then
         raise Program_Error with "deferred warning has no origin frame";
      end if;
      Activation := State.Current.Stack.Last_Element;
      if Activation.Warning_Phase /= No_Pending_Warning then
         raise Program_Error with "warning origin already owns an event";
      elsif State.Next_Foreign_Ticket =
        Interfaces.C.unsigned_long_long'Last
      then
         Fail (State, "warning callback identity exhausted", Resource => True);
      end if;
      --  Publication is allocation-free. The origin's embedded value is a
      --  real GC root while a custom handler reenters Lua and collects.
      State.Next_Foreign_Ticket := State.Next_Foreign_Ticket + 1;
      Activation.Warning_Ticket := State.Next_Foreign_Ticket;
      Activation.Warning_Message := Text;
      Root_Barrier (State, Root);
      Activation.Warning_Root := Root;
      Activation.Warning_To_Continue := To_Continue;
      Activation.Warning_Handler := State.Warning_Handler;
      Activation.Warning_Data := State.Warning_Data;
      Activation.Warning_Previous := State.Warning_Head;
      Activation.Warning_Phase := Warning_Requested;
      State.Warning_Head := Activation;
   end Emit;

   function Pending (State : World) return Boolean is
     (State.Warning_Head /= null and then
      State.Warning_Head.Warning_Phase = Warning_Requested);

   function Identity (State : World) return Callback_Identity is
   begin
      if not Pending (State) then
         raise Program_Error with "no requested warning identity";
      end if;
      return (State.Warning_Head.all'Address,
              State.Warning_Head.Warning_Ticket);
   end Identity;

   procedure Begin_Callback (State : in out World) is
      Activation : constant Frame_Access := State.Warning_Head;
      Context : Context_Access;
      Window : Frame_Access;
   begin
      if not Pending (State) then
         raise Program_Error with "no requested warning callback";
      end if;
      Context := Activation.Context;
      Window := Context.Stack_Window;
      Activation.Warning_Previous_Base := Context.Foreign_Base;
      Activation.Warning_Previous_Top := Context.Foreign_Top;
      Activation.Warning_Previous_Frame := Context.Foreign_Activation;
      --  The handler is invisible to Lua inspection. Borrow the actual
      --  current real frame rather than inventing a C frame or using the
      --  stale base of a foreign caller suspended below intervening Lua.
      if Window /= null then
         Activation.Warning_Window := Window;
         Window.Warning_Borrow_Depth := Window.Warning_Borrow_Depth + 1;
         Context.Foreign_Base := Window.Stack_Base;
         Context.Foreign_Top :=
           (if Window.Is_Native then Window.Stack_Live_Top else
              Window.Stack_Base + Window.Canonical_Top);
         Window.Stack_Live_Top := Context.Foreign_Top;
         Context.Foreign_Activation := Window;
      end if;
      Activation.Warning_Phase := Warning_Callback_Active;
   end Begin_Callback;

   procedure Restore_View (Activation : not null Frame_Access) is
      Context : constant Context_Access := Activation.Context;
   begin
      if Activation.Warning_Phase = Warning_Callback_Active then
         Context.Foreign_Base := Activation.Warning_Previous_Base;
         Context.Foreign_Top := Activation.Warning_Previous_Top;
         Context.Foreign_Activation := Activation.Warning_Previous_Frame;
      end if;
   end Restore_View;

   procedure Acknowledge
     (State : in out World; Token : Callback_Identity)
   is
      Activation : constant Frame_Access := State.Warning_Head;
   begin
      if Activation = null or else
        Activation.Warning_Phase /= Warning_Callback_Active or else
        Activation.all'Address /= Token.Activation or else
        Activation.Warning_Ticket /= Token.Serial
      then
         raise Program_Error with "stale warning callback identity";
      end if;
      Discard (State, Activation);
   end Acknowledge;

   procedure Discard (State : in out World; Activation : Frame_Access) is
   begin
      if Activation.Warning_Phase = No_Pending_Warning then return; end if;
      if State.Warning_Head /= Activation then
         raise Program_Error with "warning event retirement is not LIFO";
      end if;
      Restore_View (Activation);
      if Activation.Warning_Window /= null then
         Activation.Warning_Window.Warning_Borrow_Depth :=
           Activation.Warning_Window.Warning_Borrow_Depth - 1;
         Activation.Warning_Window := null;
      end if;
      State.Warning_Head := Activation.Warning_Previous;
      Activation.Warning_Phase := No_Pending_Warning;
      Activation.Warning_Previous := null;
      Activation.Warning_Root := Nil_Value;
      Activation.Warning_Message := (others => <>);
      Activation.Warning_Handler := System.Null_Address;
      Activation.Warning_Data := System.Null_Address;
   end Discard;

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Result : Native_Action := New_Action (State);
      Count : constant Natural :=
        Natural (Activation.Native_Arguments.Length);
      Item : Value;
   begin
      if Count = 0 then
         Fail (State, "bad argument #1 to 'warn' (string expected)");
      end if;
      --  Validate/convert one argument per scheduler step. A later invalid
      --  argument must prevent earlier warning output, even in default-on
      --  mode. Each pass is charged to the shared instruction budget.
      if Activation.Native_Stage = 0 then
         Activation.Native_Index := Activation.Native_Index + 1;
         Item := Activation.Native_Arguments (Activation.Native_Index);
         if Item.Kind in Integer_Kind | Real_Kind then
            Item := New_String (State, Image (State.Current.Memory, Item));
            Activation.Native_Arguments.Replace_Element
              (Activation.Native_Index, Item);
            Lua.Engine.Stacks.Write
              (State, Activation.Context,
               Activation.Stack_Base + Activation.Native_Index, Item);
         elsif Item.Kind /= String_Kind then
            Fail (State, "bad argument #" & Ada.Strings.Fixed.Trim
              (Activation.Native_Index'Image, Ada.Strings.Both) &
              " to 'warn' (string expected)");
         end if;
         if Activation.Native_Index = Count then
            Activation.Native_Stage := 1;
            Activation.Native_Index := 0;
         end if;
         Result.Kind := Continue_Step;
      elsif Activation.Native_Index < Count then
         Activation.Native_Index := Activation.Native_Index + 1;
         Emit (State,
               Activation.Native_Arguments (Activation.Native_Index),
               Activation.Native_Index < Count);
         --  Even the final custom fragment must be acknowledged before its
         --  origin frame may retire and release its borrowed message root.
         Result.Kind := Continue_Step;
      end if;
      return Result;
   end Advance;
end Lua.Engine.Warnings;
