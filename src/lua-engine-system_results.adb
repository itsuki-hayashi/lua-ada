with Lua.Platform_OS;
with Lua.Storage.Buffers;
with System;

package body Lua.Engine.System_Results is
   package C renames Interfaces.C;
   package OS renames Lua.Platform_OS;
   package Managed renames Lua.Storage.Buffers;
   use type C.int;
   use type C.size_t;

   function File_Result
     (State : in out World; Succeeded : Boolean; Error : C.int;
      Filename : String := ""; Include_Name : Boolean := False)
      return Values.Vector
   is
      Result : Values.Vector := Owned_Values (State);
      Buffer : Managed.Buffer;
   begin
      Result.Reserve_Capacity (3);
      if Succeeded then
         Result.Append ((Boolean_Kind, True));
         return Result;
      end if;
      Managed.Set_Owner (Buffer, State.Current.Memory);
      if Include_Name then
         Managed.Append (Buffer, C_Option (Filename));
         Managed.Append (Buffer, ": ");
      end if;
      if Error = 0 then
         Managed.Append (Buffer, "(no extra info)");
      else
         declare
            Address : constant System.Address := OS.Error_Text (Error);
            Size : constant C.size_t := OS.Text_Length (Address);
         begin
            if Size > C.size_t (Natural'Last) then
               raise Lua.Storage.Allocation_Error;
            end if;
            declare
               View : constant String (1 .. Natural (Size))
                 with Import, Address => Address;
            begin
               --  Copy libc's short-lived text before New_String can run
               --  emergency collection/finalizers and overwrite it. Buffer
               --  growth itself calls only the owning allocation provider.
               Managed.Append (Buffer, View);
            end;
         end;
      end if;
      Result.Append (Nil_Value);
      Result.Append (New_String (State, Buffer));
      Result.Append ((Integer_Kind, Integer_Value (Error)));
      return Result;
   end File_Result;

   function Process_Result
     (State : in out World; Status, Error : C.int) return Values.Vector
   is
      Result : Values.Vector := Owned_Values (State);
      Code, Signaled : aliased C.int := 0;
   begin
      if Status /= 0 and then Error /= 0 then
         return File_Result (State, False, Error);
      end if;
      Result.Reserve_Capacity (3);
      OS.Decode_Status (Status, Code'Access, Signaled'Access);
      Result.Append
        ((if Code = 0 and then Signaled = 0 then (Boolean_Kind, True)
          else Nil_Value));
      Result.Append (New_String
        (State, (if Signaled = 0 then "exit" else "signal")));
      Result.Append ((Integer_Kind, Integer_Value (Code)));
      return Result;
   end Process_Result;
end Lua.Engine.System_Results;
