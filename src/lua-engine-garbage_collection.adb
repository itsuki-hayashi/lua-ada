with Interfaces.C;
with Lua.Engine.Finalizers;
with Lua.Engine.Strings;
with Lua.Storage;

package body Lua.Engine.Garbage_Collection is
   use type Integer_Value;
   use type Real_Value;

   type Option_Kind is
     (Stop_Option, Restart_Option, Collect_Option, Count_Option,
      Step_Option, Running_Option, Generational_Option, Incremental_Option,
      Parameter_Option);

   function Name (Option : Option_Kind) return String;
   function Name (Parameter : Collector_Parameter) return String;
   function Prefix (Text, Candidate : String) return Boolean;
   function To_C_Int (Item : Integer_Value) return Integer_Value;

   function Name (Option : Option_Kind) return String is
     (case Option is
         when Stop_Option => "stop", when Restart_Option => "restart",
         when Collect_Option => "collect", when Count_Option => "count",
         when Step_Option => "step", when Running_Option => "isrunning",
         when Generational_Option => "generational",
         when Incremental_Option => "incremental",
         when Parameter_Option => "param");

   function Name (Parameter : Collector_Parameter) return String is
     (case Parameter is
         when Minor_Multiplier => "minormul",
         when Major_To_Minor => "majorminor",
         when Minor_To_Major => "minormajor", when Pause_Ratio => "pause",
         when Step_Multiplier => "stepmul", when Step_Size => "stepsize");

   function Prefix (Text, Candidate : String) return Boolean is
   begin
      --  luaL_checkoption compares C strings. A NUL after a complete option
      --  terminates that spelling; a NUL inside the option does not match.
      --  Compare the borrowed bytes without an input-sized Ada snapshot.
      if Text'Length < Candidate'Length then
         return False;
      end if;
      for Offset in 0 .. Candidate'Length - 1 loop
         if Text (Text'First + Offset) /=
           Candidate (Candidate'First + Offset)
         then
            return False;
         end if;
      end loop;
      return Text'Length = Candidate'Length or else
        Text (Text'First + Candidate'Length) = ASCII.NUL;
   end Prefix;

   function To_C_Int (Item : Integer_Value) return Integer_Value is
      Width : constant := Interfaces.C.int'Size;
      Modulus : constant Integer_Value := 2 ** Width;
      Half : constant Integer_Value := 2 ** (Width - 1);
      Reduced : constant Integer_Value := Item mod Modulus;
   begin
      --  The Lua base wrapper explicitly casts its integer to C int before
      --  lua_gc(GCPARAM). Preserve that modulo/sign behavior without an
      --  unchecked narrowing conversion or disabled Ada range check.
      return (if Reduced >= Half then Reduced - Modulus else Reduced);
   end To_C_Int;

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Result : Native_Action := New_Action (State);
      Option : Option_Kind := Collect_Option;
      Parameter : Collector_Parameter := Pause_Ratio;
      Argument : Integer_Value := 0;
      Returned : Value;
      Done, Drain : Boolean := False;
      Found : Boolean := False;

      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Arguments.Length)
         then Activation.Native_Arguments (Index) else Nil_Value);
      procedure Parse_Option (Text : String);
      procedure Parse_Parameter (Text : String);
      procedure Save (Item : Value);

      procedure Parse_Option (Text : String) is
      begin
         for Candidate in Option_Kind loop
            if Prefix (Text, Name (Candidate)) then
               Option := Candidate;
               Found := True;
               return;
            end if;
         end loop;
      end Parse_Option;

      procedure Parse_Parameter (Text : String) is
      begin
         for Candidate in Collector_Parameter loop
            if Prefix (Text, Name (Candidate)) then
               Parameter := Candidate;
               Found := True;
               return;
            end if;
         end loop;
      end Parse_Parameter;

      procedure Save (Item : Value) is
      begin
         Replace_Root (State, Activation.Native_Captures, 1, Item);
      end Save;
   begin
      if Activation.Native_Stage = 1 then
         --  The scheduler has drained or deliberately deferred the real
         --  queue after its allocation/stack preflight. Its helper returns
         --  no values; the original control result stays in owned storage.
         Move_Roots (State, Result.Results, Activation.Native_Captures);
         return Result;
      end if;
      if Arg (1).Kind /= Nil_Kind then
         Strings.Query_Argument (State, Arg (1), Parse_Option'Access);
         if not Found then
            Fail (State, "invalid option for 'collectgarbage'");
         end if;
      end if;
      if Option = Parameter_Option then
         Found := False;
         Strings.Query_Argument (State, Arg (2), Parse_Parameter'Access);
         if not Found then
            Fail (State, "invalid option for 'collectgarbage' parameter");
         end if;
         Argument := Integer_Value'Pred (0);
         if Arg (3).Kind /= Nil_Kind then
            Argument := To_C_Int (Strings.Integer_Argument (State, Arg (3)));
         end if;
      elsif Option = Step_Option and then Arg (2).Kind /= Nil_Kind then
         Argument := Strings.Integer_Argument (State, Arg (2));
      end if;

      --  Argument validation precedes Lua's internal-stop check. The param
      --  base-wrapper arm uniquely returns integer -1 on an invalid internal
      --  call; the other valid options return nil (lbaselib.c206-247).
      Activation.Native_Captures.Reserve_Capacity (1);
      Activation.Native_Captures.Set_Length (1);
      if State.Finalizer_Active or else State.Collector_Active or else
        State.State_Close_Phase
      then
         Save ((if Option = Parameter_Option then
                  Value'(Integer_Kind, Integer_Value'Pred (0))
                else Nil_Value));
      else
         case Option is
            when Stop_Option =>
               State.GC_Running := False;
               Returned := (Integer_Kind, 0);
            when Restart_Option =>
               State.GC_Running := True;
               Restart_Collection (State);
               Returned := (Integer_Kind, 0);
            when Collect_Option =>
               Collect (State);
               Returned := (Integer_Kind, 0);
               Drain := True;
            when Count_Option =>
               Returned := (Real_Kind, Real_Value
                 (Lua.Storage.Statistics (State.Memory).Raw_Bytes) / 1024.0);
            when Step_Option =>
               Step_Collection
                 (State, (if Argument <= 0 then 0
                          else Lua.Storage.Byte_Count (Argument)), Done);
               Returned := (Boolean_Kind, Done);
               Drain := State.Finalizers_Requested;
            when Running_Option =>
               Returned := (Boolean_Kind, State.GC_Running);
            when Generational_Option | Incremental_Option =>
               Returned := New_String
                 (State, (if State.GC.Mode = Incremental_Mode
                          then "incremental" else "generational"));
               Save (Returned);
               Set_Collector_Mode
                 (State, (if Option = Incremental_Option
                          then Incremental_Mode
                          else Generational_Minor_Mode));
               Drain := Option = Generational_Option and then
                 State.Finalizers_Requested;
            when Parameter_Option =>
               Returned := (Integer_Kind,
                 Collector_Parameter_Value (State, Parameter, Argument));
         end case;
         Save (Returned);
      end if;
      if Drain and then Lua.Engine.Finalizers.Has_Pending (State) then
         Activation.Native_Stage := 1;
         Result.Kind := Drain_Finalizers;
      else
         Move_Roots (State, Result.Results, Activation.Native_Captures);
      end if;
      return Result;
   end Advance;
end Lua.Engine.Garbage_Collection;
