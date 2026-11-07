with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Lua.Platform_Modules;
with Lua.Platform_OS;
with Lua_Ada_Config;

package body Lua.Engine.Native_Modules is
   package Platform renames Lua.Platform_Modules;
   package C renames Interfaces.C;
   use type System.Address;
   use type C.int;

   function Windows_Host
     (Host : String := Lua_Ada_Config.Alire_Host_OS) return Boolean is
     (Host = "windows");

   procedure Free is new Ada.Unchecked_Deallocation
     (Native_Library_Node, Native_Library_Access);
   function Allocator_Address is new Ada.Unchecked_Conversion
     (Lua.Storage.Allocation_Function, System.Address);

   procedure Work (State : in out World);
   procedure Work (State : in out World) is
   begin
      if State.Policy = Bounded then
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + 1;
      end if;
   end Work;

   function C_Length (State : in out World; Text : String) return Natural;
   function C_Length (State : in out World; Text : String) return Natural is
      Size : Natural := 0;
   begin
      for Byte of Text loop
         Work (State);
         exit when Byte = Character'Val (0);
         Size := Size + 1;
      end loop;
      return Size;
   end C_Length;

   procedure Copy_C_Text
     (State : in out World; Pointer : System.Address;
      Output : in out Owned_Buffer);
   procedure Copy_C_Text
     (State : in out World; Pointer : System.Address;
      Output : in out Owned_Buffer)
   is
   begin
      Output.Clear;
      if Pointer = System.Null_Address then return; end if;
      declare
         --  Native loader/environment text is a synchronous C borrow. The
         --  fixed view's limit is checked before accessing each next byte;
         --  no unconstrained host String copy precedes owned publication.
         Text : String (1 .. Natural'Last)
           with Import, Address => Pointer;
         Index : Positive := 1;
      begin
         while Text (Index) /= Character'Val (0) loop
            Work (State);
            if State.Policy = Bounded and then
              Output.Length >= State.Bounds.String_Bytes
            then
               Fail (State, "path byte limit exceeded", Resource => True);
            end if;
            Output.Append (Text (Index));
            Index := Index + 1;
         end loop;
      end;
   end Copy_C_Text;

   procedure Resolve
     (State : in out World; Path, Symbol : String;
      Item : out Value; Error : in out Owned_Buffer;
      Stage : out Failure_Stage)
   is
      Node : Native_Library_Access := State.Native_Libraries;
      Fresh : Native_Library_Access;
      Path_Size : constant Natural := C_Length (State, Path);
      Symbol_Size : constant Natural := C_Length (State, Symbol);
      Symbol_Text : Owned_Buffer;
      Native_Error : aliased System.Address := System.Null_Address;
      Error_Bytes : String (1 .. Natural (Platform.Error_Buffer_Size));
      Function_Address : System.Address;
      Global : constant Boolean := Symbol_Size > 0 and then
        Symbol (Symbol'First) = '*';
      Same : Boolean;
   begin
      Item := Nil_Value;
      Stage := Loaded;
      Error.Set_Owner (Lua.Storage.Reference (State.Memory));
      Error.Clear;
      --  Cache by the exact C-string key, like the pinned loader. A second
      --  spelling may acquire another OS reference to the same image; each
      --  owns its corresponding release, without assuming handle uniqueness.
      while Node /= null loop
         Work (State);
         Same := Node.Path.Length = Path_Size;
         if Same then
            for Index in 1 .. Path_Size loop
               Work (State);
               if Node.Path.Element (Index) /=
                 Path (Path'First + Index - 1)
               then
                  Same := False;
                  exit;
               end if;
            end loop;
         end if;
         exit when Same;
         Node := Node.Previous;
      end loop;
      if Node = null then
         --  Construct every provider-owned byte before opening the image.
         --  Publishing the successful OS reference is then allocation-free;
         --  refusal cannot strand an unregistered loader reference.
         Fresh := new (Lua.Storage.Handle (State.Memory)) Native_Library_Node;
         begin
            Fresh.Path.Set_Owner (Lua.Storage.Reference (State.Memory));
            Fresh.Path.Set_Value
              (Path (Path'First .. Path'First + Path_Size - 1));
            Fresh.Handle := Platform.Open
              (Fresh.Path.C_Address, Boolean'Pos (Global),
               Error_Bytes'Address, Native_Error'Access);
            if Fresh.Handle = System.Null_Address then
               Copy_C_Text (State, Native_Error, Error);
               Stage := Open_Failed;
               Free (Fresh);
               return;
            end if;
         exception
            when others => Free (Fresh); raise;
         end;
         Fresh.Previous := State.Native_Libraries;
         State.Native_Libraries := Fresh;
         Node := Fresh;
      end if;
      if Global then
         Item := (Boolean_Kind, True);
         return;
      end if;
      Symbol_Text.Set_Owner (Lua.Storage.Reference (State.Memory));
      Symbol_Text.Set_Value
        (Symbol (Symbol'First .. Symbol'First + Symbol_Size - 1));
      Function_Address := Platform.Symbol
        (Node.Handle, Symbol_Text.C_Address,
         Error_Bytes'Address, Native_Error'Access);
      if Function_Address = System.Null_Address then
         Copy_C_Text (State, Native_Error, Error);
         Stage := Symbol_Failed;
      else
         Item := (Foreign_Function_Kind, Function_Address);
      end if;
   end Resolve;

   procedure Configure_Paths
     (State : in out World; Package_Value : Value;
      Native_Defaults : Boolean)
   is
      Default, Selected, Variable, Program_Directory : Owned_Buffer;
      Pointer : System.Address;
      Directory : String (1 .. 261);
      Ignoring_Environment : constant Boolean := not Native_Defaults or else
        Truth (Get ((Table_Kind, State.Foreign_Registry),
                    New_String (State, "LUA_NOENV")));

      procedure Apply (Field, Environment_Name : String;
                       Native_Default : System.Address);
      procedure Apply (Field, Environment_Name : String;
                       Native_Default : System.Address)
      is
         Mark : Natural := 0;
         Result : Owned_Buffer;
      begin
         Result.Set_Owner (Lua.Storage.Reference (State.Memory));
         if Native_Defaults then
            Copy_C_Text (State, Native_Default, Default);
         else
            Default.Set_Value
              ((if Field = "path" then "./?.lua;./?/init.lua"
                elsif Windows_Host
                then ".\?.dll" else "./?.so"));
         end if;
         Selected.Clear;
         Selected.Append (Default);
         if not Ignoring_Environment then
            Variable.Set_Value (Environment_Name & "_5_5");
            Pointer := Lua.Platform_OS.Environment (Variable.C_Address);
            if Pointer = System.Null_Address then
               Variable.Set_Value (Environment_Name);
               Pointer := Lua.Platform_OS.Environment (Variable.C_Address);
            end if;
            if Pointer /= System.Null_Address then
               Copy_C_Text (State, Pointer, Selected);
               --  Only the first double separator expands. Later pairs are
               --  literal empty templates, matching pinned setpath.
               for Index in 1 .. Selected.Length -
                 Natural'Min (Selected.Length, 1)
               loop
                  Work (State);
                  if Selected.Element (Index) = ';' and then
                    Selected.Element (Index + 1) = ';'
                  then
                     Mark := Index;
                     exit;
                  end if;
               end loop;
            end if;
         end if;
         if Mark = 0 then
            Result.Append (Selected);
         else
            for Index in 1 .. Mark - 1 loop
               Result.Append (Selected.Element (Index));
            end loop;
            if Mark > 1 then Result.Append (';'); end if;
            Result.Append (Default);
            if Mark + 1 < Selected.Length then Result.Append (';'); end if;
            for Index in Mark + 2 .. Selected.Length loop
               Result.Append (Selected.Element (Index));
            end loop;
         end if;
         if Native_Defaults and then Windows_Host then
            if Platform.Program_Directory
              (Directory'Address, C.size_t (Directory'Length)) = 0
            then
               Fail (State, "unable to get ModuleFileName");
            end if;
            Copy_C_Text (State, Directory'Address, Program_Directory);
            Selected.Clear;
            for Index in 1 .. Result.Length loop
               Work (State);
               if Result.Element (Index) = '!' then
                  Selected.Append (Program_Directory);
               else
                  Selected.Append (Result.Element (Index));
               end if;
            end loop;
            Result.Clear;
            Result.Append (Selected);
         end if;
         Set (State, Package_Value, New_String (State, Field),
              New_String (State, Result));
      end Apply;
   begin
      Default.Set_Owner (Lua.Storage.Reference (State.Memory));
      Selected.Set_Owner (Lua.Storage.Reference (State.Memory));
      Variable.Set_Owner (Lua.Storage.Reference (State.Memory));
      Program_Directory.Set_Owner (Lua.Storage.Reference (State.Memory));
      Apply ("path", "LUA_PATH", Platform.Default_Path);
      Apply ("cpath", "LUA_CPATH", Platform.Default_CPath);
   end Configure_Paths;

   procedure Close_All (State : in out World) is
      Code : constant System.Address := Allocator_Address
        (Lua.Storage.Allocator (State.Memory));
      Node : Native_Library_Access;
      Handle : System.Address;
   begin
      if State.Native_Libraries = null then return; end if;
      State.Module_Code.Handle := Platform.Keep_Code (Code);
      while State.Native_Libraries /= null loop
         Node := State.Native_Libraries;
         State.Native_Libraries := Node.Previous;
         Handle := Node.Handle;
         Free (Node);
         Platform.Close (Handle);
      end loop;
      --  The lease precedes Memory in World. Its controlled finalization
      --  therefore releases code after the owner's residual block cleanup,
      --  as well as these cache-record frees, without a secondary handle list.
   end Close_All;
end Lua.Engine.Native_Modules;
