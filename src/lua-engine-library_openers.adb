with Ada.Numerics;
with Lua.Engine.IO_Libraries;
with Lua.Engine.Mathematics;
with Lua.Engine.Operating_System;
with Lua.Engine.Unicode;
with Lua_Ada_Config;

package body Lua.Engine.Library_Openers is
   function Open_Module
     (State : in out World; Kind : Module_Kind) return Value
   is
      Globals : constant Value := Global_Environment (State);
      Module : constant Value :=
        (if Kind = Base_Module then Globals else New_Table (State));

      procedure Native (Name, Implementation : String);
      procedure Members (Prefix, Names : String);

      procedure Native (Name, Implementation : String) is
      begin
         Set (State, Module, New_String (State, Name),
              New_Native (State, Implementation));
      end Native;

      procedure Members (Prefix, Names : String) is
         First : Positive := Names'First;
         Last : Natural;
      begin
         --  Export names select the same native continuation drivers used
         --  by ordinary sessions. Creating a C-visible module never opens a
         --  second interpreter or borrows another world's closures.
         while First <= Names'Last loop
            Last := First;
            while Last < Names'Last and then Names (Last + 1) /= ' ' loop
               Last := Last + 1;
            end loop;
            Native (Names (First .. Last),
                    Prefix & "." & Names (First .. Last));
            First := Last + 2;
         end loop;
      end Members;
   begin
      case Kind is
         when Base_Module =>
            --  The base initializer extends the existing global table.
            --  Opening it again deliberately restores standard bindings,
            --  while leaving unrelated user fields and other modules alone.
            Set (State, Module, New_String (State, "_G"), Module);
            Set (State, Module, New_String (State, "_VERSION"),
                 New_String (State, Language_Version));
            Set (State, Module, New_String (State, "assert"),
                 (Native_Kind_Value, Assert_Function));
            Set (State, Module, New_String (State, "error"),
                 (Native_Kind_Value, Error_Function));
            Set (State, Module, New_String (State, "pcall"),
                 (Native_Kind_Value, Pcall_Function));
            Set (State, Module, New_String (State, "type"),
                 (Native_Kind_Value, Type_Function));
            Set (State, Module, New_String (State, "tonumber"),
                 (Native_Kind_Value, Tonumber_Function));
            Set (State, Module, New_String (State, "select"),
                 (Native_Kind_Value, Select_Function));
            Set (State, Module, New_String (State, "next"),
                 (Native_Kind_Value, Next_Function));
            Set (State, Module, New_String (State, "rawequal"),
                 (Native_Kind_Value, Rawequal_Function));
            Set (State, Module, New_String (State, "rawget"),
                 (Native_Kind_Value, Rawget_Function));
            Set (State, Module, New_String (State, "rawset"),
                 (Native_Kind_Value, Rawset_Function));
            Set (State, Module, New_String (State, "rawlen"),
                 (Native_Kind_Value, Rawlen_Function));
            Members ("base",
              "print tostring pairs ipairs collectgarbage load warn " &
              "xpcall loadfile dofile getmetatable setmetatable");

         when Package_Module =>
            declare
               Searchers : constant Value := New_Table (State);
               Captures : constant Values.Vector := One_Value (State, Module);
               Separator : constant String :=
                 (if Lua_Ada_Config.Alire_Host_OS = "windows" then "\"
                  else "/");
            begin
               --  Capture this package object, and preserve the original
               --  owning registry tables even if package.loaded/preload are
               --  later replaced publicly. Reopening creates a new package
               --  table with its own searchers and require capture.
               Set (State, Module, New_String (State, "loaded"),
                    (Table_Kind, State.Loaded_Modules));
               Set (State, Module, New_String (State, "preload"),
                    (Table_Kind, State.Preload_Modules));
               Set (State, Module, New_String (State, "path"),
                    New_String (State, "./?.lua;./?/init.lua"));
               Set (State, Module, New_String (State, "config"),
                    New_String (State, Separator & Character'Val (10) & ";" &
                      Character'Val (10) & "?" & Character'Val (10) & "!" &
                      Character'Val (10) & "-" & Character'Val (10)));
               Set (State, Module, New_String (State, "searchers"), Searchers);
               Set (State, Module, New_String (State, "searchpath"),
                    New_Native (State, "package.searchpath", Captures));
               Set (State, Searchers, (Integer_Kind, 1),
                    New_Native (State, "package.preload_searcher", Captures));
               Set (State, Searchers, (Integer_Kind, 2),
                    New_Native (State, "package.lua_searcher", Captures));
               Set (State, Globals, New_String (State, "require"),
                    New_Native (State, "base.require", Captures));
            end;

         when Coroutine_Module =>
            Members ("coroutine",
              "create resume yield wrap status running isyieldable close");

         when Debug_Module =>
            Members ("debug",
              "getinfo getlocal setlocal getupvalue setupvalue " &
              "upvalueid upvaluejoin getregistry getmetatable setmetatable " &
              "getuservalue setuservalue sethook gethook traceback");

         when Math_Module =>
            Members ("math",
              "abs ceil floor fmod max min modf tointeger type ult " &
              "acos asin atan cos deg exp frexp ldexp log rad sin sqrt tan" &
              (if State.Math_Compatibility then
                 " atan2 cosh sinh tanh pow log10" else ""));
            Set (State, Module, New_String (State, "maxinteger"),
                 (Integer_Kind, Integer_Value'Last));
            Set (State, Module, New_String (State, "mininteger"),
                 (Integer_Kind, Integer_Value'First));
            Set (State, Module, New_String (State, "pi"),
                 (Real_Kind, Ada.Numerics.Pi));
            Set (State, Module, New_String (State, "huge"),
                 (Real_Kind, Read_Number
                   (Lua.Storage.Reference (State.Memory), "1e999").Real_Item));
            declare
               Generator : constant Value :=
                 Mathematics.New_Generator (State);
               Captures : constant Values.Vector :=
                 One_Value (State, Generator);
            begin
               --  The two exports share one retained generator. A later
               --  luaopen_math creates another userdata rather than reseeding
               --  existing closures or redirecting them through global math.
               Set (State, Module, New_String (State, "random"),
                    New_Native (State, "math.random", Captures));
               Set (State, Module, New_String (State, "randomseed"),
                    New_Native (State, "math.randomseed", Captures));
            end;

         when String_Module =>
            Members ("string",
              "byte char len lower upper sub reverse rep dump format " &
              "find match gmatch gsub pack packsize unpack");
            declare
               Meta : constant Value := New_Table (State);
               Names : constant String :=
                 "__add __sub __mul __mod __pow __div __idiv __unm";
               First : Positive := Names'First;
               Last : Natural;
            begin
               --  The string type owns one metatable in this universe.
               --  Opening the module replaces it with a fresh arithmetic
               --  table and makes string method lookup find this module.
               State.String_Metatable := Meta.Reference;
               Set (State, Meta, New_String (State, "__index"), Module);
               while First <= Names'Last loop
                  Last := First;
                  while Last < Names'Last and then
                    Names (Last + 1) /= ' '
                  loop
                     Last := Last + 1;
                  end loop;
                  Set (State, Meta, New_String (State, Names (First .. Last)),
                       New_Native (State, "arith." & Names (First .. Last)));
                  First := Last + 2;
               end loop;
            end;

         when Table_Module =>
            Members ("table",
                     "concat create insert remove move pack sort unpack");

         when UTF8_Module =>
            Members ("utf8", "char len codepoint offset codes");
            Set (State, Module, New_String (State, "charpattern"),
                 New_String (State, Unicode.Charpattern));
      end case;
      return Module;
   end Open_Module;

   procedure Open_All (State : in out World) is
      Globals : constant Value := Global_Environment (State);
      procedure Publish (Name : String; Module : Value);
      procedure Publish (Name : String; Module : Value) is
      begin
         Set (State, Globals, New_String (State, Name), Module);
         Set (State, (Table_Kind, State.Loaded_Modules),
              New_String (State, Name), Module);
      end Publish;
   begin
      --  Eager Ada sessions use the same constructors as C-selected opening.
      --  Publication happens inside initialization's rooted, noncollecting
      --  operation; final bootstrap collection removes temporary bindings.
      Publish ("_G", Open_Module (State, Base_Module));
      Publish ("debug", Open_Module (State, Debug_Module));
      Publish ("coroutine", Open_Module (State, Coroutine_Module));
      Publish ("string", Open_Module (State, String_Module));
      Publish ("utf8", Open_Module (State, UTF8_Module));
      Publish ("table", Open_Module (State, Table_Module));
      Publish ("math", Open_Module (State, Math_Module));
      IO_Libraries.Install (State);
      Publish ("os", Operating_System.Open_Module (State));
      Publish ("package", Open_Module (State, Package_Module));
   end Open_All;
end Lua.Engine.Library_Openers;
