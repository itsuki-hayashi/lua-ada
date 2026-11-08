separate (Lua.Engine.Machine)
procedure Publish_Native_Return
  (State : in out World; Activation : not null Frame_Access;
   Result, Retained_Result : Values.Vector)
is
   Context : constant Context_Access := Activation.Context;
   Name : constant String := Native_Operation_Name (Activation);
   --  Transfer_Count still records entry arguments until Complete_Packet
   --  publishes the return event. Some drivers have already consumed their
   --  input packet, so the scalar window is the authoritative argument view.
   Arguments : constant Natural := Activation.Transfer_Count;
   Count : constant Natural := Natural (Result.Length);
   First : Positive := Arguments + 1;
   Old_Top : constant Natural := Activation.Stack_Live_Top;
   New_Top : Natural;
   function Arg (Index : Positive) return Value;
   function Succeeded return Boolean;
   procedure Write (Index : Positive; Item : Value);

   function Arg (Index : Positive) return Value is
     (if Index <= Arguments then
         Stacks.Read (Context, Activation.Stack_Base + Index)
      else Nil_Value);

   function Succeeded return Boolean is
     (not Result.Is_Empty and then Result.First_Element.Kind = Boolean_Kind
      and then Result.First_Element.Boolean_Data);

   procedure Write (Index : Positive; Item : Value) is
   begin
      Stacks.Write (State, Context, Activation.Stack_Base + Index, Item);
   end Write;
begin
   --  This is result publication into the same real activation window used
   --  by C getlocal and tracing. It never invents a getlocal-only workspace
   --  or aliases result position one to an unrelated input value. Placement
   --  follows the pinned operation's stack transformation, not result/input
   --  value equality (abs(4), for example, still appends another 4).
   if Activation.Native_Return_First > 0 then
      First := Activation.Native_Return_First;
   elsif Name = "base.primitive" then
      case Activation.Native_Id is
         when Assert_Function | Rawset_Function => First := 1;
         when Rawget_Function | Next_Function => First := 2;
         when Tonumber_Function =>
            if Arg (1).Kind in Integer_Kind | Real_Kind and then
              Arg (2).Kind = Nil_Kind
            then
               First := 1;
            end if;
         when Select_Function =>
            if not (Arg (1).Kind = String_Kind and then
                    Length (Arg (1).Reference.Bytes) > 0 and then
                    Element (Arg (1).Reference.Bytes, 1) = '#')
            then
               --  select's numeric form returns the existing suffix, even
               --  when that suffix is empty. It pushes no replacement copy.
               First := Arguments - Count + 1;
            end if;
         when others => null;
      end case;
   elsif Name in "base.setmetatable" | "debug.setmetatable" |
     "string.gmatch"
   then
      First := 1;
   elsif Name = "base.getmetatable" then
      if Metafield (State, Arg (1), "__metatable").Kind /= Nil_Kind then
         --  The protected value follows the retained metatable slot.
         First := Arguments + 2;
      end if;
   elsif Name = "base.pcall" then
      First := (if Succeeded then 1 else 3);
   elsif Name = "base.xpcall" then
      First := (if Succeeded then 3 else 5);
   elsif Name in "math.floor" | "math.ceil" | "math.modf" then
      if Arg (1).Kind = Integer_Kind then First := 1; end if;
   elsif Name = "table.insert" then
      --  lua_seti consumes the final value; zero results follow that top.
      First := Arguments;
   elsif Name = "ipairs.iterator" and then Count = 1 then
      --  The exhausted nil follows the just-pushed integer control slot.
      First := Arguments + 2;
   elsif Name = "utf8.step" or else Name = "utf8.lax_step" then
      First := 3;
   elsif Name = "coroutine.resume" then
      First := 2;
   elsif Name in "coroutine.yield" | "coroutine.wrapped" then
      First := 1;
   elsif Name in "debug.getinfo" | "debug.getlocal" then
      declare
         Base : constant Positive :=
           (if Arg (1).Kind = Thread_Kind then 2 else 1);
      begin
         if Arg (Base).Kind in Closure_Kind | Native_Closure_Kind |
           Native_Kind_Value | Foreign_Function_Kind
         then
            --  The debug library retains its prefixed option string or
            --  copied inactive function below its one returned value.
            First := Arguments + 2;
         end if;
      end;
   elsif Name = "debug.setlocal" then
      First := (if Arg (1).Kind = Thread_Kind then 4 else 3);
   elsif Name = "debug.setupvalue" and then Count = 1 then
      --  The API consumes the top value before the library pushes its name.
      First := Arguments;
   end if;

   if Count > Natural'Last - First + 1 or else
     First - 1 + Count > Natural'Last - Activation.Stack_Base
   then
      Fail (State, "stack overflow");
   end if;
   if State.Policy = Bounded then
      if State.Steps > State.Bounds.Instructions or else
        Count > State.Bounds.Instructions - State.Steps
      then
         Fail (State, "instruction limit exceeded", Resource => True);
      end if;
      State.Steps := State.Steps + Count;
   end if;
   New_Top := Activation.Stack_Base + First - 1 + Count;
   --  Result was pinned by Complete_Packet before capacity can grow/collect.
   --  Resize real stack storage without expanding another argument packet
   --  merely to clear it immediately afterwards. Prefix/gap slots are real
   --  initialized arena values, and trimmed inputs cease to be GC roots.
   Resize_Stack_Window
     (State, Activation, Natural'Max
        (Activation.Stack_Window_Length, First - 1 + Count));
   if New_Top < Old_Top then
      Stacks.Clear_Range (Context, New_Top + 1, Old_Top);
   else
      for Index in Old_Top + 1 .. New_Top loop
         Stacks.Write (State, Context, Index, Nil_Value);
      end loop;
   end if;
   if Name = "base.pcall" and then not Succeeded and then Count = 2 then
      Write (1, (Boolean_Kind, True));
      Write (2, Result (2));
   elsif Name = "base.xpcall" and then not Succeeded and then Count = 2 then
      Write (3, (Boolean_Kind, True));
      Write (4, Result (2));
   end if;
   for Index in 1 .. Count loop
      Write (First + Index - 1, Result (Index));
   end loop;
   Activation.Stack_Live_Top := New_Top;
   Context.Foreign_Top := New_Top;
   Activation.Transfer_First := First;
   Activation.Transfer_Count := Count;
   Activation.Return_Window_Published := True;

   --  The physical prefix/results now own every semantically live value.
   --  A previous callback's packet or a consumed input/capture must not keep
   --  discarded weak objects alive while the return hook can collect. An
   --  exact Result-vector alias already holds precisely these live results.
   if Activation.Native_Arguments'Address /= Result'Address and then
     Activation.Native_Arguments'Address /= Retained_Result'Address
   then
      Activation.Native_Arguments.Clear;
   end if;
   if Activation.Native_Results'Address /= Result'Address and then
     Activation.Native_Results'Address /= Retained_Result'Address
   then
      Activation.Native_Results.Clear;
   end if;
   if Activation.Native_Captures'Address /= Result'Address and then
     Activation.Native_Captures'Address /= Retained_Result'Address
   then
      Activation.Native_Captures.Clear;
   end if;
end Publish_Native_Return;
