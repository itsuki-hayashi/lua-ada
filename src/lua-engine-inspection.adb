with Lua.Engine.Call_Names;
with Lua.Engine.Hooks;
with Lua.Engine.Canonical;
with Lua.Engine.Stacks;
with Lua.Prototypes;
with Lua.Engine.Strings;
with Ada.Strings.Fixed;
with Interfaces.C;
with System;

package body Lua.Engine.Inspection is
   use type Integer_Value;
   use type Ada.Containers.Count_Type;
   use type Lua.Prototypes.Prototype_Access;
   use type Interfaces.C.int;
   use type System.Address;

   function Short_Source (Source : String) return String is
      Newline : constant Natural :=
        Ada.Strings.Fixed.Index (Source, "" & Character'Val (10));
      Size : Natural := Source'Length;
      Truncated : Boolean := False;
   begin
      --  A default debug identifier has 59 payload bytes plus its C NUL.
      --  File identifiers retain the tail; snippets retain the first
      --  line with a quoted prefix/suffix. No native record layout is
      --  involved.
      if Source'Length > 0 and then Source (Source'First) in '=' | '@' then
         if Source'Length <= 60 or else Source (Source'First) = '=' then
            return Source (Source'First + 1 ..
              Natural'Min (Source'Last, Source'First + 59));
         end if;
         return "..." & Source (Source'Last - 55 .. Source'Last);
      end if;
      if Newline /= 0 then
         Size := Newline - Source'First;
         Truncated := True;
      end if;
      if Source'Length >= 45 then
         Truncated := True;
      end if;
      Size := Natural'Min (45, Size);
      return "[string """ & Source (Source'First .. Source'First + Size - 1) &
        (if Truncated then "..." else "") & """]";
   end Short_Source;

   function Visible_Local_Top
     (Context : not null Context_Access; Item : not null Frame_Access)
      return Natural
   is
      Window : Frame_Access := Context.Stack_Window;
      Child : Frame_Access;
      Limit : constant Natural :=
        (if not Item.Is_Native then Item.Canonical_GC_Top
         elsif Item.Has_Stack_Window then
            Item.Stack_Live_Top - Item.Stack_Base
         else Natural (Item.Native_Arguments.Length));
   begin
      --  ldebug.c:luaG_findlocal distinguishes a frame's live top from the
      --  next function's slot. Our collector must root that slot, but debug
      --  temporaries cannot expose the child's callee/arguments as the
      --  parent's locals. Follow the real window links, not opcode guesses
      --  or a fabricated stack layout. A C hook borrows its interrupted
      --  frame, so its immutable transport marker contributes no boundary.
      while Window /= null and then Window /= Item loop
         if not Window.Is_C_Hook_Transport then
            Child := Window;
         end if;
         Window := Window.Previous_Stack_Window;
      end loop;
      if Window = Item and then Child /= null then
         return (if Child.Call_Base > Item.Stack_Base then
                   Natural'Min
                     (Limit, Child.Call_Base - Item.Stack_Base - 1)
                 else 0);
      end if;
      return Limit;
   end Visible_Local_Top;

   function Inspect
     (State : in out World; Activation : Frame_Access;
      Target_Frame : Frame_Access := null) return Values.Vector
   is
      Name : constant String := To_String (Activation.Native_Name);
      Args : constant Values.Vector := Activation.Native_Arguments;
      Context : Context_Access := State.Current;
      Base : Positive := 1;
      Result : Values.Vector := Owned_Values (State);
      Selected : Frame_Access;
      Function_Value : Value;
      Code : Prototype_Access;

      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Args.Length) then Args (Index) else Nil_Value);
      function Integer_Arg (Index : Positive) return Integer_Value;
      function Logical_Frame (Level : Natural) return Frame_Access;
      function Public_Frame (Item : Frame_Access) return Boolean;
      function Caller_Of (Callee : Frame_Access) return Frame_Access;
      function Inferred_Name
        (Item : Frame_Access) return Call_Names.Identity;
      function Symbol_Text
        (Prototype : Prototype_Access; Symbol : Positive) return String;
      procedure Append (Item : Value);
      procedure Work;
      procedure Field (Table : Value; Key : String; Item : Value);
      function Line_At (Item : Frame_Access; PC : Positive) return Natural;
      function Current_PC (Item : Frame_Access) return Natural;

      function Current_PC (Item : Frame_Access) return Natural is
        (if (Context.Hook_Active or else Context.Hook_Suspended) and then
            Item = Context.Hook_Frame then
            Item.PC - 1 else Natural'Max (1, Item.PC - 1) - 1);
      --  A hook observes the instruction about to run; a suspended caller
      --  observes its saved call PC. Both are zero-based canonical offsets.

      function Line_At (Item : Frame_Access; PC : Positive) return Natural is
        (if Item.Code.Canonical_Node /= null then
            Canonical.Source_Line (Item, PC - 1)
         elsif PC <= Item.Code.Code.Last_Index then
            Item.Code.Code (PC).Location.Line else 0);

      procedure Work is
      begin
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + 1;
         end if;
      end Work;

      function Integer_Arg (Index : Positive) return Integer_Value is
      begin
         return Strings.Integer_Argument (State, Arg (Index));
      end Integer_Arg;

      function Public_Frame (Item : Frame_Access) return Boolean is
        (not Item.Is_C_Hook_Transport and then
         (not Item.Is_Native or else
          (Length (Item.Native_Name) > 0 and then
           Element (Item.Native_Name, 1) /= '@')));

      function Logical_Frame (Level : Natural) return Frame_Access is
         Remaining : Natural := Level;
         function Failed_Owner (Candidate : Frame_Access) return Boolean;
         function Failed_Owner (Candidate : Frame_Access) return Boolean is
         begin
            --  An errored Lua activation is retained only to own its closing
            --  cells. Its logical call has already unwound to protection.
            for Driver of Context.Stack loop
               if Driver.Is_Native and then Driver.Native_Name = "@unwind"
                 and then Driver.Unwind = Error_Exit and then
                 Driver.Unwind_Owner = Candidate
               then
                  return True;
               end if;
            end loop;
            return False;
         end Failed_Owner;
      begin
         --  Scheduler helper activations are implementation phases, not Lua
         --  stack frames. Public native closures retain their logical frame.
         for Item of reverse Context.Stack loop
            Work;
            if Public_Frame (Item) and then not Failed_Owner (Item) then
               if Remaining = 0 then
                  return Item;
               end if;
               Remaining := Remaining - 1;
            end if;
         end loop;
         return null;
      end Logical_Frame;

      function Caller_Of (Callee : Frame_Access) return Frame_Access is
         Found : Boolean := False;
      begin
         --  Name inference is deliberately lazy: ordinary function calls never
         --  scan preceding code. Skip explicit scheduler phases when finding
         --  the logical caller, and preserve real native library boundaries.
         for Item of reverse Context.Stack loop
            if Item = Callee then
               Found := True;
            elsif Found and then Public_Frame (Item) then
               return Item;
            end if;
         end loop;
         return null;
      end Caller_Of;

      function Inferred_Name
        (Item : Frame_Access) return Call_Names.Identity
      is
         Caller : Frame_Access;
      begin
         --  Both getinfo and traceback derive the name from the actual call
         --  site. Tail replacement has lost that caller; synthetic calls
         --  such as hooks and metamethods carry their own explicit origin.
         if Item /= null and then Length (Item.Name_Kind) = 0 and then
           not Item.Is_Tail_Call
         then
            Caller := Caller_Of (Item);
            if Caller /= null and then not Caller.Is_Native and then
              Caller.Code.Canonical_Node /= null
            then
               return Call_Names.From_Caller (State, Caller);
            end if;
         end if;
         return (others => <>);
      end Inferred_Name;

      function Symbol_Text
        (Prototype : Prototype_Access; Symbol : Positive) return String
      is
      begin
         if Prototype /= null then
            for Item of Prototype.Names loop
               Work;
               if Item.Symbol = Symbol then
                  return To_String (Item.Name);
               end if;
            end loop;
         end if;
         return "_ENV";
      end Symbol_Text;

      procedure Append (Item : Value) is
      begin
         Result.Append (Item);
      end Append;

      procedure Field (Table : Value; Key : String; Item : Value) is
      begin
         Set (State, Table, New_String (State, Key), Item);
      end Field;
   begin
      if Arg (1).Kind = Thread_Kind then
         Context := State.Contexts (Arg (1).Reference.Context_Index);
         Base := 2;
      end if;
      if Name = "debug.sethook" then
         declare
            Callback : constant Value := Arg (Base);
            Mask : Unbounded_String;
            Flags : constant String := "crl";
            Reported : Integer_Value := 0;
            Count : Natural := 0;
         begin
            --  Validate first, then publish callback storage, then commit the
            --  installation controls. A bad argument or failed table growth
            --  must not remove an existing C/Lua hook. The registry entry is
            --  retained even for a valid zero-mask installation, as in
            --  ldblib.c:db_sethook followed by ldebug.c:lua_sethook.
            if Callback.Kind /= Nil_Kind then
               if Callback.Kind not in Closure_Kind | Native_Closure_Kind |
                 Native_Kind_Value | Foreign_Function_Kind
               then
                  Fail (State, "function expected");
               end if;
               if Arg (Base + 1).Kind /= String_Kind then
                  Fail (State, "string expected");
               end if;
               if Arg (Base + 2).Kind /= Nil_Kind then
                  Reported := Integer_Arg (Base + 2);
                  if Reported > Integer_Value (Natural'Last) or else
                    Reported < Integer_Value (Integer'First)
                  then
                     Fail (State, "hook count out of range");
                  end if;
                  Count := Natural (Integer_Value'Max (0, Reported));
               end if;
               for Flag of Flags loop
                  if Ada.Strings.Fixed.Index
                    (C_Option (Image (State.Current.Memory, Arg (Base + 1))),
                     "" & Flag) /= 0
                  then
                     Append (Mask, Flag);
                  end if;
               end loop;
            end if;
            Hooks.Store_Callback (State, Context, Callback);
            Context.Foreign_Hook := System.Null_Address;
            Context.Foreign_Hook_Mask := 0;
            for Bit in 0 .. 2 loop
               if Ada.Strings.Fixed.Index
                 (To_String (Mask), "" & Flags (Bit + 1)) /= 0
               then
                  Context.Foreign_Hook_Mask := Context.Foreign_Hook_Mask +
                    2 ** Bit;
               end if;
            end loop;
            if Count > 0 then
               Context.Foreign_Hook_Mask := Context.Foreign_Hook_Mask + 8;
            end if;
            Context.Hook := Nil_Value;
            Context.Hook_Mask := Mask;
            Context.Lua_Hook_Installed := Callback.Kind /= Nil_Kind and then
              (Length (Mask) > 0 or else Count > 0);
            --  Reflection preserves a signed requested count, while only a
            --  positive interval enables instruction-count events.
            Context.Hook_Reported_Count := Reported;
            Context.Hook_Count := Count;
            Context.Hook_Remaining := Count;
         end;
      elsif Name = "debug.gethook" then
         --  Pinned debug.gethook reports an externally installed C callback
         --  with this string, rather than exposing an uncallable proxy or
         --  treating the C callback pointer as a Lua hook function.
         --  With no hook, C Lua returns one nil, not a padded triple. Result
         --  counts remain observable through select, varargs and table.pack.
         if not Hooks.Enabled (Context) then
            Append (Nil_Value);
            return Result;
         end if;
         Append
           ((if Context.Foreign_Hook /= System.Null_Address then
                 New_String (State, "external hook")
             else Hooks.Callback (State, Context)));
         if Context.Foreign_Hook /= System.Null_Address then
            declare
               Mask : Unbounded_String;
               Characters : constant String := "crl";
            begin
               for Bit in 0 .. 2 loop
                  if (Context.Foreign_Hook_Mask / 2 ** Bit) mod 2 /= 0
                  then
                     Append (Mask, Characters (Bit + 1));
                  end if;
               end loop;
               Append (New_String (State, To_String (Mask)));
            end;
         else
            Append (New_String (State, To_String (Context.Hook_Mask)));
         end if;
         Append ((Integer_Kind, Context.Hook_Reported_Count));
      elsif Name in "debug.getuservalue" | "debug.setuservalue" then
         declare
            Setting : constant Boolean := Name = "debug.setuservalue";
            Slot : constant Positive := (if Setting then 3 else 2);
            Number : Integer_Value :=
              (if Arg (Slot).Kind = Nil_Kind then 1 else Integer_Arg (Slot));
         begin
            --  The library's optional Lua integer is converted to native C
            --  int before indexing, including its low-bit wrap on every
            --  supported ABI. Keep absent/nil defaults distinct from an
            --  existing uservalue whose stored value happens to be nil.
            Number := Number mod (2 ** Interfaces.C.int'Size);
            if Number >= 2 ** (Interfaces.C.int'Size - 1) then
               Number := Number - 2 ** Interfaces.C.int'Size;
            end if;
            if Setting then
               if Arg (1).Kind /= Userdata_Kind then
                  Fail (State, "full userdata expected");
               elsif Args.Length < 2 then
                  Fail (State, "value expected");
               end if;
            end if;
            if Arg (1).Kind /= Userdata_Kind or else Number < 1 or else
              Number > Integer_Value (Arg (1).Reference.Uservalues.Length)
            then
               Append (Nil_Value);
            elsif Setting then
               --  Mutate the actual traced slot, without allocating a proxy
               --  table or changing the userdata's stable C payload address.
               Arg (1).Reference.Uservalues.Replace_Element
                 (Positive (Number), Arg (2));
               Back_Barrier (State, Arg (1).Reference);
               Append (Arg (1));
            else
               Append (Arg (1).Reference.Uservalues (Positive (Number)));
               Append ((Boolean_Kind, True));
            end if;
         end;
      elsif Name = "debug.getregistry" then
         Append ((Table_Kind, State.Foreign_Registry));
      elsif Name = "debug.getmetatable" then
         if Args.Is_Empty then
            Fail (State, "value expected");
         end if;
         declare
            Meta : constant Object_Access := Raw_Metatable (State, Arg (1));
         begin
            Append ((if Meta = null then Nil_Value else
                       (Table_Kind, Meta)));
         end;
      elsif Name = "debug.setmetatable" then
         if Args.Length < 2 or else
           Arg (2).Kind not in Nil_Kind | Table_Kind
         then
            Fail (State, "nil or table expected");
         end if;
         Set_Metatable
           (State, Arg (1), (if Arg (2).Kind = Nil_Kind then null else
                              Arg (2).Reference));
         Append (Arg (1));
      elsif Name = "debug.upvaluejoin" then
         declare
            Target : constant Value := Arg (1);
            Source : constant Value := Arg (3);
            Target_Index : constant Integer_Value := Integer_Arg (2);
            Source_Index : constant Integer_Value := Integer_Arg (4);
         begin
            --  This operation redirects one closure's actual cell reference;
            --  copying the cell value would break future shared mutations,
            --  upvalueid identity and collection after the source disappears.
            if Target.Kind /= Closure_Kind or else
              Source.Kind /= Closure_Kind
            then
               Fail (State, "Lua function expected");
            elsif Target_Index < 1 or else Target_Index > Integer_Value
              (Target.Reference.Upvalues.Length) or else
              Source_Index < 1 or else Source_Index > Integer_Value
                (Source.Reference.Upvalues.Length)
            then
               Fail (State, "invalid upvalue index");
            end if;
            Replace_Object_Edge
              (State, Target.Reference, Target.Reference.Upvalues,
               Positive (Target_Index),
               Source.Reference.Upvalues (Positive (Source_Index)));
         end;
      elsif Name in "debug.getupvalue" | "debug.setupvalue" | "debug.upvalueid"
      then
         if Name = "debug.setupvalue" and then Args.Length < 3 then
            Fail (State, "value expected");
         end if;
         Function_Value := Arg (1);
         declare
            Index : constant Integer_Value := Integer_Arg (2);
            Cell : Object_Access;
         begin
            if Function_Value.Kind not in Closure_Kind | Native_Closure_Kind |
              Native_Kind_Value | Foreign_Function_Kind
            then
               Fail (State, "function expected");
            end if;
            if Function_Value.Kind in Native_Kind_Value | Foreign_Function_Kind
              or else
              Index < 1 or else Index > Integer_Value
                ((if Function_Value.Kind = Closure_Kind then
                    Function_Value.Reference.Upvalues.Length else
                    Function_Value.Reference.Captures.Length))
            then
               if Name = "debug.upvalueid" then
                  Append (Nil_Value);
               end if;
               return Result;
            end if;
            Cell :=
              (if Function_Value.Kind = Closure_Kind then
                 Function_Value.Reference.Upvalues (Positive (Index)) else
                 Function_Value.Reference.Captures (Positive (Index)));
            if Name = "debug.upvalueid" then
               Append ((Light_Identity_Kind, Cell.all'Address));
            else
               if Function_Value.Kind = Closure_Kind then
                  Code := Function_Value.Reference.Code;
               end if;
               if Code /= null and then Code.Canonical_Node /= null then
                  Append (Canonical.Upvalue_Name
                    (State, Code, Positive (Index)));
               else
                  Append (New_String
                    (State, (if Code = null then "" else Symbol_Text
                       (Code, (if Code.Is_Main then Code.Environment_Symbol
                        else Code.Capture_Symbols (Positive (Index)))))));
               end if;
               if Name = "debug.setupvalue" then
                  Store_Cell (State, Cell, Arg (3));
               else
                  Append (Cell.Cell_Value);
               end if;
            end if;
         end;
      elsif Name = "debug.getinfo" then
         Function_Value := Arg (Base);
         if Function_Value.Kind = Integer_Kind then
            if Function_Value.Integer_Data < 0 or else
              Function_Value.Integer_Data > Integer_Value (Natural'Last)
            then
               Append (Nil_Value);
               return Result;
            end if;
            Selected := (if Target_Frame /= null then Target_Frame else
              Logical_Frame (Natural (Function_Value.Integer_Data)));
            if Selected = null then
               Append (Nil_Value);
               return Result;
            end if;
            Function_Value := Selected.Callee;
            if Selected.Is_Native and then
              Function_Value.Kind = Nil_Kind and then
              Selected.Native_Self /= null
            then
               Function_Value := (Native_Closure_Kind, Selected.Native_Self);
            end if;
         elsif Function_Value.Kind not in Closure_Kind | Native_Closure_Kind |
           Native_Kind_Value | Foreign_Function_Kind
         then
            Fail (State, "function or level expected");
         end if;
         if Function_Value.Kind = Closure_Kind then
            Code := Function_Value.Reference.Code;
         end if;
         declare
            Options : constant String :=
              (if Arg (Base + 1).Kind = Nil_Kind then "flnSrtu"
               else C_Option (Image (State.Current.Memory, Arg (Base + 1))));
            Info : constant Value := New_Table (State);
            Source : constant String :=
              (if Code = null then "=[C]"
               elsif Code.Canonical_Node /= null then
                 To_String (Canonical.Source_Bytes (Code))
               else To_String (Code.Name));
            Line : Integer_Value := -1;
            function Wants (Option : Character) return Boolean is
              (Ada.Strings.Fixed.Index (Options, "" & Option) /= 0);
         begin
            for Option of Options loop
               if Option not in 'f' | 'l' | 'n' | 'S' | 'r' | 't' | 'u' | 'L'
               then
                  Fail (State, "invalid option");
               end if;
            end loop;
            if Selected /= null and then not Selected.Is_Native and then
              (Selected.Code.Canonical_Node = null or else not
               Selected.Code.Canonical_Node.Lines.Is_Empty)
            then
               --  A stripped prototype has no current source line. Its
               --  decoder's zero sentinel is internal, whereas debug reports
               --  -1 for unavailable line information, just as for natives.
               Line := Integer_Value
                 (Line_At (Selected, Current_PC (Selected) + 1));
            end if;
            if Wants ('l') then
               Field (Info, "currentline", (Integer_Kind, Line));
            end if;
            if Wants ('S') then
               Field (Info, "source", New_String (State, Source));
               Field (Info, "short_src", New_String
                 (State, Short_Source (Source)));
               Field (Info, "linedefined", (Integer_Kind,
                 (if Code = null then -1 else
                    Integer_Value (Code.First_Line))));
               Field (Info, "lastlinedefined", (Integer_Kind,
                 (if Code = null then -1 else
                    Integer_Value (Code.Last_Line))));
               Field (Info, "what", New_String
                 (State, (if Code = null then "C"
                  elsif (if Code.Canonical_Node /= null then
                           Code.Canonical_Node.First_Line = 0
                         else Code.Is_Main) then "main" else "Lua")));
            end if;
            if Wants ('u') then
               Field (Info, "nups", (Integer_Kind,
                 (if Function_Value.Kind = Native_Closure_Kind then
                    Integer_Value (Function_Value.Reference.Captures.Length)
                  elsif Code = null then 0 else Integer_Value
                    (Function_Value.Reference.Upvalues.Length))));
               Field (Info, "nparams", (Integer_Kind,
                 (if Code = null then 0 else
                    (if Code.Canonical_Node /= null then
                        Integer_Value (Code.Canonical_Node.Parameters)
                     else Integer_Value (Code.Parameters.Length)))));
               Field (Info, "isvararg", (Boolean_Kind,
                 Code = null or else Code.Vararg));
            end if;
            if Wants ('n') then
               declare
                  Inferred : constant Call_Names.Identity :=
                    Inferred_Name (Selected);
                  use type Call_Names.Name_Kind;
               begin
                  if Inferred.Kind /= Call_Names.Unknown then
                     Field (Info, "namewhat", New_String
                       (State, Call_Names.Kind_Image (Inferred.Kind)));
                     Field (Info, "name", Inferred.Item);
                  else
                     Field (Info, "namewhat", New_String
                       (State, (if Selected = null then "" else
                          To_String (Selected.Name_Kind))));
                     if Selected /= null and then
                       Length (Selected.Call_Name) > 0
                     then
                        Field (Info, "name", New_String
                          (State, To_String (Selected.Call_Name)));
                     end if;
                  end if;
               end;
            end if;
            if Wants ('t') then
               Field (Info, "istailcall",
                      (Boolean_Kind, Selected /= null and then
                         Selected.Is_Tail_Call));
               Field (Info, "extraargs", (Integer_Kind,
                 (if Selected = null then 0 else
                    Integer_Value (Selected.Call_Metamethod_Count))));
            end if;
            if Wants ('f') then
               Field (Info, "func", Function_Value);
            end if;
            if Wants ('r') then
               declare
                  Transferring : constant Boolean :=
                    Context.Hook_Active and then Context.Hook_Transfer
                    and then Selected /= null and then
                    Selected = Context.Hook_Frame;
               begin
                  Field (Info, "ftransfer", (Integer_Kind,
                    (if Transferring then
                       Integer_Value (Selected.Transfer_First) else 0)));
                  Field (Info, "ntransfer", (Integer_Kind,
                    (if Transferring then
                       Integer_Value (Selected.Transfer_Count) else 0)));
               end;
            end if;
            if Wants ('L') and then Code /= null then
               declare
                  Lines : constant Value := New_Table (State);
               begin
                  --  Native functions have no line table, so their L field
                  --  remains absent. A stripped Lua function still receives
                  --  an empty table. For varargs, VARARGPREP is entry setup,
                  --  not an executable source line: including its definition
                  --  line would advertise a breakpoint that never fires.
                  if Code.Canonical_Node /= null then
                     for PC in (if Code.Vararg then 2 else 1) ..
                       Code.Canonical_Node.Lines.Last_Index
                     loop
                        Set (State, Lines, (Integer_Kind,
                          Integer_Value (Canonical.Source_Line
                            (Code, PC - 1))), (Boolean_Kind, True));
                     end loop;
                  else
                     for Instruction of Code.Code loop
                        Set (State, Lines,
                             (Integer_Kind,
                              Integer_Value (Instruction.Location.Line)),
                              (Boolean_Kind, True));
                     end loop;
                  end if;
                  Field (Info, "activelines", Lines);
               end;
            end if;
            Append (Info);
         end;
      elsif Name in "debug.getlocal" | "debug.setlocal" then
         if Name = "debug.getlocal" and then Arg (Base).Kind in
           Closure_Kind | Native_Closure_Kind | Native_Kind_Value |
           Foreign_Function_Kind
         then
            declare
               Index : constant Integer_Value := Integer_Arg (Base + 1);
            begin
               if Arg (Base).Kind = Closure_Kind then
                  Code := Arg (Base).Reference.Code;
                  if Index > 0 and then Code.Canonical_Node /= null then
                     declare
                        Local : constant Value := Canonical.Local_Name
                          (State, Code, Positive (Index), 0);
                     begin
                        if Local.Kind /= Nil_Kind then
                           Append (Local);
                           return Result;
                        end if;
                     end;
                  elsif Index > 0 and then
                    Index <= Integer_Value (Code.Parameters.Length)
                  then
                     Append (New_String
                       (State, Symbol_Text
                          (Code, Code.Parameters (Positive (Index)))));
                     return Result;
                  end if;
               end if;
               Append (Nil_Value);
               return Result;
            end;
         end if;
         if Name = "debug.setlocal" and then
           Natural (Args.Length) < Base + 2
         then
            Fail (State, "value expected");
         end if;
         declare
            Level : constant Integer_Value := Integer_Arg (Base);
            Index : constant Integer_Value := Integer_Arg (Base + 1);
            Cells : Bindings.Vector;
            Scope : Object_Access;
         begin
            Cells.Set_Owner (Lua.Storage.Reference (State.Memory));
            if Level < 0 or else Level > Integer_Value (Natural'Last) then
               Fail (State, "level out of range");
            end if;
            Selected := (if Target_Frame /= null then Target_Frame else
              Logical_Frame (Natural (Level)));
            if Selected = null then
               Fail (State, "level out of range");
            end if;
            if not Selected.Is_Native then
               if Index < 0 then
                  declare
                     Count : constant Natural :=
                       (if Selected.Code.Canonical_Node /= null then
                           Canonical.Vararg_Length (Selected) else
                           Natural (Selected.Varargs.Length));
                  begin
                     if Index >= -Integer_Value (Count) then
                        Append (New_String (State, "(vararg)"));
                        if Selected.Code.Canonical_Node /= null then
                           if Name = "debug.setlocal" then
                              Canonical.Write_Vararg
                                (State, Selected, Positive (-Index),
                                 Arg (Base + 2));
                           else
                              Append (Canonical.Read_Vararg
                                (State, Selected, Positive (-Index)));
                           end if;
                        elsif Name = "debug.setlocal" then
                           Selected.Varargs.Replace_Element
                             (Positive (-Index), Arg (Base + 2));
                        else
                           Append (Selected.Varargs (Positive (-Index)));
                        end if;
                     end if;
                  end;
                  if Result.Is_Empty then
                     Append (Nil_Value);
                  end if;
                  return Result;
               end if;
               if Selected.Code.Canonical_Node /= null then
                  if Index > 0 and then Index <= Integer_Value
                    (Visible_Local_Top (Context, Selected))
                  then
                     declare
                        Local : Value := Canonical.Local_Name
                          (State, Selected.Code, Positive (Index),
                           Current_PC (Selected));
                     begin
                        if Local.Kind = Nil_Kind then
                           Local := New_String (State, "(temporary)");
                        end if;
                        Append (Local);
                        if Name = "debug.setlocal" then
                           Canonical.Write_Register
                             (State, Selected, Natural (Index) - 1,
                              Arg (Base + 2));
                        else
                           Append (Canonical.Read_Register
                             (State, Selected, Natural (Index) - 1));
                        end if;
                     end;
                  else
                     Append (Nil_Value);
                  end if;
                  return Result;
               end if;
               Scope := Selected.Scope;
               while Scope /= null and then Scope /=
                 Selected.Callee.Reference.Capture
               loop
                  --  Inner scopes are traversed first, then prepended as a
                  --  group, preserving source declaration order for locals.
                  for Binding of reverse Scope.Locals loop
                     Cells.Prepend (Binding);
                  end loop;
                  Scope := Scope.Parent;
               end loop;
               if Index > 0 and then Index <= Integer_Value (Cells.Length) then
                  Append (New_String
                    (State, Symbol_Text
                       (Selected.Code, Cells (Positive (Index)).Symbol)));
                  if Name = "debug.setlocal" then
                     Store_Cell
                       (State, Cells (Positive (Index)).Cell, Arg (Base + 2));
                  else
                     Append (Cells (Positive (Index)).Cell.Cell_Value);
                  end if;
               end if;
            elsif Index > 0 and then
              Index <= Integer_Value
                (Visible_Local_Top (Context, Selected))
            then
               Append (New_String (State, "(C temporary)"));
               if Name = "debug.setlocal" then
                  --  Native packets drive Ada continuations, while the real
                  --  scalar window drives C API access and collection. Update
                  --  both views; foreign activations may intentionally have
                  --  no packet entry for a valid scalar C temporary.
                  if Index <=
                    Integer_Value (Selected.Native_Arguments.Length)
                  then
                     Replace_Root
                       (State, Selected.Native_Arguments, Positive (Index),
                        Arg (Base + 2));
                  end if;
                  if Selected.Has_Stack_Window then
                     Stacks.Write
                       (State, Selected.Context,
                        Selected.Stack_Base + Positive (Index),
                        Arg (Base + 2));
                  end if;
               elsif Selected.Has_Stack_Window then
                  Append (Stacks.Read
                    (State, Selected.Context,
                     Selected.Stack_Base + Positive (Index)));
               else
                  Append (Selected.Native_Arguments (Positive (Index)));
               end if;
            end if;
            if Result.Is_Empty then
               Append (Nil_Value);
            end if;
         end;
      elsif Name = "debug.traceback" then
         declare
            Text : Unbounded_String;
            Level : Natural := (if Context = State.Current then 1 else 0);
            No_Frames : Boolean := False;
            Visible, Failed : Frames.Vector;
            Shown : Natural := 0;
            Shortened : Boolean := False;
            type Located_Name is record
               Found : Boolean := False;
               Text : Unbounded_String;
            end record;

            function Decimal (Number : Natural) return String is
              (Ada.Strings.Fixed.Trim
                 (Natural'Image (Number), Ada.Strings.Both));

            function Source (Item : Frame_Access) return String is
              (Short_Source
                 ((if Item.Code.Canonical_Node /= null then
                     To_String (Canonical.Source_Bytes (Item.Code))
                   else To_String (Item.Code.Name))));

            function Find_Field
              (Table : Object_Access; Target : Value; Depth : Natural)
               return Located_Name;

            function Find_Field
              (Table : Object_Access; Target : Value; Depth : Natural)
               return Located_Name
            is
            begin
               if Table = null or else Depth = 0 then
                  return (others => <>);
               end if;
               --  lauxlib.c:findfield searches only string keys, with raw
               --  identity and two table levels. Use the actual loaded
               --  modules registry; replaceable package.loaded fields and
               --  metamethods must not affect this diagnostic traversal.
               for Row of Table.Members loop
                  Work;
                  if Row.Key.Kind = String_Kind and then
                    Row.Item.Kind /= Nil_Kind
                  then
                     if Equal (Row.Item, Target) then
                        return (True, To_Unbounded_String
                          (Image (State.Current.Memory, Row.Key)));
                     elsif Row.Item.Kind = Table_Kind and then Depth > 1 then
                        declare
                           Suffix : constant Located_Name :=
                             Find_Field
                               (Row.Item.Reference, Target, Depth - 1);
                        begin
                           if Suffix.Found then
                              return (True, To_Unbounded_String
                                (Image (State.Current.Memory, Row.Key) &
                                 "." & To_String (Suffix.Text)));
                           end if;
                        end;
                     end if;
                  end if;
               end loop;
               return (others => <>);
            end Find_Field;

            procedure Describe (Item : Frame_Access);

            procedure Describe (Item : Frame_Access) is
               Inferred : constant Call_Names.Identity :=
                 Inferred_Name (Item);
               use type Call_Names.Name_Kind;
            begin
               --  Prefer a real call-site name, then a main chunk, then a
               --  loaded-module identity. Anonymous Lua functions retain
               --  their definition location, while unknown native functions
               --  remain '?'. Internal native dispatch labels are not public
               --  function names (lauxlib.c:pushfuncname).
               if Length (Item.Name_Kind) > 0 then
                  Append (Text, To_String (Item.Name_Kind) & " '" &
                    To_String (Item.Call_Name) & "'");
               elsif Inferred.Kind /= Call_Names.Unknown then
                  Append (Text, Call_Names.Kind_Image (Inferred.Kind) &
                    " '" & Image (State.Current.Memory, Inferred.Item) & "'");
               elsif not Item.Is_Native and then
                 (if Item.Code.Canonical_Node /= null then
                     Item.Code.Canonical_Node.First_Line = 0
                  else Item.Code.Is_Main)
               then
                  Append (Text, "main chunk");
               else
                  declare
                     Global : constant Located_Name :=
                       Find_Field (State.Loaded_Modules, Item.Callee, 2);
                  begin
                     if Global.Found then
                        Append (Text, "function '");
                        if Length (Global.Text) >= 3 and then
                          Slice (Global.Text, 1, 3) = "_G."
                        then
                           Append (Text, Slice
                             (Global.Text, 4, Length (Global.Text)));
                        else
                           Append (Text, Global.Text);
                        end if;
                        Append (Text, "'");
                     elsif Item.Is_Native then
                        Append (Text, "?");
                     else
                        Append (Text, "function <" & Source (Item) & ":" &
                          Decimal (Item.Code.First_Line) & ">");
                     end if;
                  end;
               end if;
            end Describe;
         begin
            if Arg (Base).Kind not in Nil_Kind | String_Kind |
              Integer_Kind | Real_Kind
            then
               Append (Arg (Base));
               return Result;
            end if;
            if Arg (Base).Kind /= Nil_Kind then
               Text := To_Unbounded_String
                 (Image (State.Current.Memory, Arg (Base)) &
                 Character'Val (10));
            end if;
            if Arg (Base + 1).Kind /= Nil_Kind then
               if Integer_Arg (Base + 1) > Integer_Value (Natural'Last) then
                  Fail (State, "level out of range");
               end if;
               No_Frames := Integer_Arg (Base + 1) < 0;
               if not No_Frames then
                  Level := Natural (Integer_Arg (Base + 1));
               end if;
            end if;
            Append (Text, "stack traceback:");
            if not No_Frames then
               --  Snapshot borrowed frame identities once. Their context
               --  owns them throughout this synchronous, callback-free
               --  operation; both temporary vectors use its storage owner.
               --  Finding each level afresh would repeatedly traverse a deep
               --  stack. Error owners are excluded just as in getinfo.
               Frames.Set_Owner (Visible, Context.Memory);
               Frames.Set_Owner (Failed, Context.Memory);
               for Driver of Context.Stack loop
                  Work;
                  if Driver.Is_Native and then
                    Driver.Native_Name = "@unwind" and then
                    Driver.Unwind = Error_Exit
                  then
                     Failed.Append (Driver.Unwind_Owner);
                  end if;
               end loop;
               for Item of reverse Context.Stack loop
                  Work;
                  if Public_Frame (Item) and then
                    not Failed.Contains (Item)
                  then
                     Visible.Append (Item);
                  end if;
               end loop;
               Shortened := Level < Visible.Last_Index and then
                 Visible.Last_Index - Level > 22;
               while Level < Visible.Last_Index loop
                  Work;
                  if Shortened and then Shown = 10 then
                     declare
                        Skipped : constant Natural :=
                          Visible.Last_Index - Level - 12;
                     begin
                        --  Match the pinned lauxlib.c skip count, including
                        --  its already-fetched eleventh frame. Resume at the
                        --  final eleven actual frames, not synthetic entries.
                        Append (Text, Character'Val (10) & Character'Val (9) &
                          "..." & Character'Val (9) & "(skipping " &
                          Decimal (Skipped) & " levels)");
                        Level := Visible.Last_Index - 11;
                        Shortened := False;
                     end;
                  else
                     declare
                        Item : constant Frame_Access := Visible (Level + 1);
                        Line : constant Natural :=
                          (if Item.Is_Native then 0 else
                             Line_At (Item, Current_PC (Item) + 1));
                     begin
                        Append (Text, Character'Val (10) & Character'Val (9));
                        Append (Text,
                          (if Item.Is_Native then "[C]" else Source (Item)));
                        if Line > 0 then
                           Append (Text, ":" & Decimal (Line));
                        end if;
                        Append (Text, ": in ");
                        Describe (Item);
                        if Item.Is_Tail_Call then
                           Append (Text,
                             Character'Val (10) & Character'Val (9) &
                             "(...tail calls...)");
                        end if;
                     end;
                     Level := Level + 1;
                     Shown := Shown + 1;
                  end if;
               end loop;
            end if;
            Append (New_String (State, To_String (Text)));
         end;
      else
         Fail (State, "debug operation not implemented");
      end if;
      return Result;
   end Inspect;
end Lua.Engine.Inspection;
