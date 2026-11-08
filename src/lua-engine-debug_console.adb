with Interfaces.C;
with Lua.Engine.Loaders;
with Lua.Engine.Foreign;
with Lua.Engine.Stacks;
with Lua.Engine.Stack_Views;
with Lua.Platform_Streams;

package body Lua.Engine.Debug_Console is
   package Streams renames Lua.Platform_Streams;
   use type Interfaces.C.int;

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Result : Native_Action := New_Action (State);
      Item, Handler : Value;

      procedure Write_Error (Bytes : String);
      procedure Print_Error (Error_Value : Value);
      procedure Clear_Command;
      procedure Finish_Command;

      procedure Clear_Command is
         Owner : constant Frame_Access :=
           (if Activation.Has_Stack_Window then Activation
            else Stack_Views.Physical_Owner (State.Current));
         Public_Owner : constant Frame_Access :=
           Stack_Views.Physical_Owner (State.Current);
      begin
         --  db_debug sets its actual C top to zero after each command. This
         --  releases even initial arguments; clearing only copied packets
         --  would leave those objects alive in the scalar C window. A saved
         --  builtin pointer borrows the real caller's window instead.
         if Owner = null then
            --  A host may call the saved C pointer directly, without a Lua
            --  activation. Its actual base prefix is the physical C stack.
            Stacks.Clear_Range
              (State.Current, State.Current.Foreign_Base + 1,
               State.Current.Foreign_Top);
            State.Current.Foreign_Top := State.Current.Foreign_Base;
            State.Current.Host_Stack_Top := State.Current.Foreign_Base;
         elsif not Owner.Is_Native then
            raise Program_Error with "debug console lost its C stack owner";
         else
            Stacks.Clear_Range
              (State.Current, Owner.Stack_Base + 1, Owner.Stack_Live_Top);
            Owner.Stack_Live_Top := Owner.Stack_Base;
            Owner.Native_Arguments.Clear;
            if State.Current.Foreign_View = Owner then
               State.Current.Foreign_Top := Owner.Stack_Base;
            end if;
         end if;
         Activation.Native_Arguments.Clear;
         if Activation.Native_Builtin_Direct then
            --  The private phase has its own window above the real caller.
            --  Drop the actual original prefix too, then publish that cursor
            --  to this call's boundary record so return cannot resurrect it.
            if Public_Owner = null then
               Stacks.Clear_Range
                 (State.Current, State.Current.Foreign_Base + 1,
                  State.Current.Host_Stack_Top);
               State.Current.Host_Stack_Top := State.Current.Foreign_Base;
               State.Current.Foreign_Top := State.Current.Foreign_Base;
               Activation.Saved_Foreign_Top := State.Current.Foreign_Base;
            elsif Public_Owner /= Owner then
               Stacks.Clear_Range
                 (State.Current, Public_Owner.Stack_Base + 1,
                  Public_Owner.Stack_Live_Top);
               Public_Owner.Stack_Live_Top := Public_Owner.Stack_Base;
               Public_Owner.Native_Arguments.Clear;
               State.Current.Foreign_Top := Public_Owner.Stack_Base;
            end if;
            Foreign.Publish_Direct_Builtin_Base
              (State, State.Current.Foreign_Base);
         end if;
         Activation.Native_Captures.Clear;
         Activation.Native_Results.Clear;
         Activation.Native_Stage := 0;
      end Clear_Command;

      procedure Finish_Command is
         Owner : constant Frame_Access :=
           (if Activation.Native_Builtin_Direct then
               Stack_Views.Physical_Owner (State.Current) else Activation);
      begin
         if Owner /= null and then
           Owner.C_Closing_Level > Owner.Stack_Base
         then
            --  Reuse lua_settop's existing iterative C-slot close operation.
            --  Keep original values until every actual closer has run; a
            --  closer error escapes the console's command protection.
            Result.Arguments.Append
              (Value'(Light_Identity_Kind, Owner.all'Address));
            Result.Arguments.Append
              (Value'(Integer_Kind, Integer_Value (Owner.Stack_Base)));
            Result.Function_Value := New_Native
              (State, "@foreign.close", Result.Arguments);
            Result.Arguments.Clear;
            Result.Kind := Invoke;
            Activation.Native_Stage := 3;
         else
            Clear_Command;
            Result.Kind := Continue_Step;
         end if;
      end Finish_Command;

      procedure Write_Error (Bytes : String) is
         Error : aliased Interfaces.C.int := 0;
         Count : Interfaces.C.size_t;
         Status : Interfaces.C.int;
      begin
         --  ldblib writes directly to stderr, independent of io.output and
         --  replaceable Lua fields. Native write errors are ignored by its
         --  diagnostic macro; account work without inventing a Lua IOError.
         Diagnostic_Work (State, Bytes'Length);
         Count := Streams.Write
           (Streams.Standard (Streams.Standard_Error), Bytes'Address,
            Interfaces.C.size_t (Bytes'Length), Error'Access);
         Status := Streams.Flush
           (Streams.Standard (Streams.Standard_Error), Error'Access);
         pragma Unreferenced (Count, Status);
      end Write_Error;

      procedure Print_Error (Error_Value : Value) is
         procedure Print_Prefix (Bytes : String);
         procedure Print_Prefix (Bytes : String) is
            Last : Natural := Bytes'Last;
         begin
            --  lua_writestringerror("%s") uses the first NUL as its end.
            --  Preserve the actual counted Lua object until after the write.
            for Index in Bytes'Range loop
               if Bytes (Index) = Character'Val (0) then
                  Last := Index - 1;
                  exit;
               end if;
            end loop;
            Write_Error (Bytes (Bytes'First .. Last));
         end Print_Prefix;
      begin
         Describe_Value (State, Error_Value, Activation.Native_Buffer);
         Activation.Native_Buffer.Query (Print_Prefix'Access);
         Write_Error ([Character'Val (10)]);
         Finish_Command;
      end Print_Error;
   begin
      if Activation.Native_Stage = 3 then
         Clear_Command;
         Result.Kind := Continue_Step;
         return Result;
      elsif Activation.Native_Stage = 2 then
         Item :=
           (if Activation.Native_Results.Is_Empty then Nil_Value
            else Activation.Native_Results.First_Element);
         if Item.Kind not in String_Kind | Integer_Kind | Real_Kind then
            Fail (State, "'__tostring' must return a string");
         end if;
         Print_Error (Item);
         return Result;
      elsif Activation.Native_Stage = 1 then
         --  The existing recovery controller resumes this same protected
         --  holder with false/error on failure. Successful command results
         --  are discarded, as lua_pcall(...,0,...) does in the C console.
         Activation.Protection := 0;
         if Activation.Result_Failure_Class = No_Failure then
            Finish_Command;
            return Result;
         end if;
         Item := Activation.Native_Results (2);
         Copy_Roots
           (State, Activation.Native_Captures, One_Value (State, Item));
      else
         declare
            --  Match fgets(buffer,250): at most249 bytes, including a final
            --  LF. Embedded NUL ends compilation, but not the actual read.
            Buffer : String (1 .. 249);
            Used, Prefix : Natural := 0;
            Byte : Interfaces.C.int;
            Error : aliased Interfaces.C.int := 0;
         begin
            Activation.Error_Packet.Reserve_Capacity (2);
            Activation.Retain_On_Failure := True;
            Write_Error ("lua_debug> ");
            while Used < Buffer'Length loop
               Diagnostic_Work (State, 1);
               Byte := Streams.Get_Byte
                 (Streams.Standard (Streams.Standard_Input), Error'Access);
               exit when Byte = Streams.End_Marker;
               Used := Used + 1;
               Buffer (Used) := Character'Val (Byte);
               exit when Buffer (Used) = Character'Val (10);
            end loop;
            if Used = 0 or else Buffer (1 .. Used) = "cont" &
              Character'Val (10)
            then
               return Result;
            end if;
            Prefix := Used;
            for Index in 1 .. Used loop
               if Buffer (Index) = Character'Val (0) then
                  Prefix := Index - 1;
                  exit;
               end if;
            end loop;
            Copy_Roots
              (State, Activation.Native_Captures,
               Loaders.Compile_Chunk
                 (State, Activation, Buffer (1 .. Prefix),
                  "=(debug command)", "t", Global_Environment (State)));
            Item := Activation.Native_Captures.First_Element;
            if Item.Kind /= Nil_Kind then
               Activation.Protection := 1;
               Activation.Result_Failure_Class := No_Failure;
               Activation.Native_Stage := 1;
               Result.Kind := Invoke;
               Result.Function_Value := Item;
               return Result;
            end if;
            Item := Activation.Native_Captures (2);
         end;
      end if;

      --  Auxiliary conversion runs outside the command's protection. A
      --  failing __tostring must escape debug.debug instead of being silently
      --  swallowed. Invoke it directly, without a Lua shim or tostring frame.
      Handler := Metafield (State, Item, "__tostring");
      if Handler.Kind = Nil_Kind then
         Print_Error (Item);
      else
         Activation.Native_Stage := 2;
         Result.Kind := Invoke;
         Result.Function_Value := Handler;
         Result.Arguments.Append (Item);
      end if;
      return Result;
   end Advance;
end Lua.Engine.Debug_Console;
