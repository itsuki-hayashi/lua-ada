with Interfaces.C.Strings;

package body Lua.Builtin_Registry is
   package C renames Interfaces.C;
   use type C.int;
   use type System.Address;
   function C_Count return C.int
     with Import, Convention => C, External_Name => "lua_ada_builtin_count";
   function C_Name (Id : C.int) return C.Strings.chars_ptr
     with Import, Convention => C, External_Name => "lua_ada_builtin_name";
   function C_Address (Id : C.int) return System.Address
     with Import, Convention => C,
          External_Name => "lua_ada_builtin_address";
   function C_Find (Address : System.Address) return C.int
     with Import, Convention => C, External_Name => "lua_ada_builtin_find";

   function Name (Id : Kind) return String is
     (case Id is
         when Print_Function => "primitive.print",
         when Assert_Function => "primitive.assert",
         when Error_Function => "primitive.error",
         when Pcall_Function => "primitive.pcall",
         when Type_Function => "primitive.type",
         when Tonumber_Function => "primitive.tonumber",
         when Tostring_Function => "primitive.tostring",
         when Select_Function => "primitive.select",
         when Next_Function => "primitive.next",
         when Pairs_Function => "primitive.pairs",
         when Ipairs_Function => "primitive.ipairs",
         when Ipairs_Step_Function => "primitive.ipairs_step",
         when Rawequal_Function => "primitive.rawequal",
         when Rawget_Function => "primitive.rawget",
         when Rawset_Function => "primitive.rawset",
         when Rawlen_Function => "primitive.rawlen",
         when Base_Print_Function => "base.print",
         when Base_Tostring_Function => "base.tostring",
         when Base_Pairs_Function => "base.pairs",
         when Base_Ipairs_Function => "base.ipairs",
         when Base_Collectgarbage_Function => "base.collectgarbage",
         when Base_Load_Function => "base.load",
         when Base_Warn_Function => "base.warn",
         when Base_Xpcall_Function => "base.xpcall",
         when Base_Loadfile_Function => "base.loadfile",
         when Base_Dofile_Function => "base.dofile",
         when Base_Getmetatable_Function => "base.getmetatable",
         when Base_Setmetatable_Function => "base.setmetatable",
         when Base_Require_Function => "base.require",
         when Package_Searchpath_Function => "package.searchpath",
         when Package_Preload_Searcher_Function => "package.preload_searcher",
         when Package_Lua_Searcher_Function => "package.lua_searcher",
         when Package_Loadlib_Function => "package.loadlib",
         when Package_C_Searcher_Function => "package.c_searcher",
         when Package_CRoot_Searcher_Function => "package.croot_searcher",
         when Coroutine_Create_Function => "coroutine.create",
         when Coroutine_Resume_Function => "coroutine.resume",
         when Coroutine_Yield_Function => "coroutine.yield",
         when Coroutine_Wrap_Function => "coroutine.wrap",
         when Coroutine_Status_Function => "coroutine.status",
         when Coroutine_Running_Function => "coroutine.running",
         when Coroutine_Isyieldable_Function => "coroutine.isyieldable",
         when Coroutine_Close_Function => "coroutine.close",
         when Coroutine_Wrapped_Function => "coroutine.wrapped",
         when Debug_Getinfo_Function => "debug.getinfo",
         when Debug_Getlocal_Function => "debug.getlocal",
         when Debug_Setlocal_Function => "debug.setlocal",
         when Debug_Getupvalue_Function => "debug.getupvalue",
         when Debug_Setupvalue_Function => "debug.setupvalue",
         when Debug_Upvalueid_Function => "debug.upvalueid",
         when Debug_Upvaluejoin_Function => "debug.upvaluejoin",
         when Debug_Getregistry_Function => "debug.getregistry",
         when Debug_Getmetatable_Function => "debug.getmetatable",
         when Debug_Setmetatable_Function => "debug.setmetatable",
         when Debug_Getuservalue_Function => "debug.getuservalue",
         when Debug_Setuservalue_Function => "debug.setuservalue",
         when Debug_Sethook_Function => "debug.sethook",
         when Debug_Gethook_Function => "debug.gethook",
         when Debug_Traceback_Function => "debug.traceback",
         when Math_Abs_Function => "math.abs",
         when Math_Ceil_Function => "math.ceil",
         when Math_Floor_Function => "math.floor",
         when Math_Fmod_Function => "math.fmod",
         when Math_Max_Function => "math.max",
         when Math_Min_Function => "math.min",
         when Math_Modf_Function => "math.modf",
         when Math_Tointeger_Function => "math.tointeger",
         when Math_Type_Function => "math.type",
         when Math_Ult_Function => "math.ult",
         when Math_Acos_Function => "math.acos",
         when Math_Asin_Function => "math.asin",
         when Math_Atan_Function => "math.atan",
         when Math_Cos_Function => "math.cos",
         when Math_Deg_Function => "math.deg",
         when Math_Exp_Function => "math.exp",
         when Math_Frexp_Function => "math.frexp",
         when Math_Ldexp_Function => "math.ldexp",
         when Math_Log_Function => "math.log",
         when Math_Rad_Function => "math.rad",
         when Math_Sin_Function => "math.sin",
         when Math_Sqrt_Function => "math.sqrt",
         when Math_Tan_Function => "math.tan",
         when Math_Atan2_Function => "math.atan2",
         when Math_Cosh_Function => "math.cosh",
         when Math_Sinh_Function => "math.sinh",
         when Math_Tanh_Function => "math.tanh",
         when Math_Pow_Function => "math.pow",
         when Math_Log10_Function => "math.log10",
         when Math_Random_Function => "math.random",
         when Math_Randomseed_Function => "math.randomseed",
         when String_Byte_Function => "string.byte",
         when String_Char_Function => "string.char",
         when String_Len_Function => "string.len",
         when String_Lower_Function => "string.lower",
         when String_Upper_Function => "string.upper",
         when String_Sub_Function => "string.sub",
         when String_Reverse_Function => "string.reverse",
         when String_Rep_Function => "string.rep",
         when String_Dump_Function => "string.dump",
         when String_Format_Function => "string.format",
         when String_Find_Function => "string.find",
         when String_Match_Function => "string.match",
         when String_Gmatch_Function => "string.gmatch",
         when String_Gsub_Function => "string.gsub",
         when String_Pack_Function => "string.pack",
         when String_Packsize_Function => "string.packsize",
         when String_Unpack_Function => "string.unpack",
         when Arith_Add_Function => "arith.__add",
         when Arith_Sub_Function => "arith.__sub",
         when Arith_Mul_Function => "arith.__mul",
         when Arith_Mod_Function => "arith.__mod",
         when Arith_Pow_Function => "arith.__pow",
         when Arith_Div_Function => "arith.__div",
         when Arith_Idiv_Function => "arith.__idiv",
         when Arith_Unm_Function => "arith.__unm",
         when Table_Concat_Function => "table.concat",
         when Table_Create_Function => "table.create",
         when Table_Insert_Function => "table.insert",
         when Table_Remove_Function => "table.remove",
         when Table_Move_Function => "table.move",
         when Table_Pack_Function => "table.pack",
         when Table_Sort_Function => "table.sort",
         when Table_Unpack_Function => "table.unpack",
         when Utf8_Char_Function => "utf8.char",
         when Utf8_Len_Function => "utf8.len",
         when Utf8_Codepoint_Function => "utf8.codepoint",
         when Utf8_Offset_Function => "utf8.offset",
         when Utf8_Codes_Function => "utf8.codes",
         when Utf8_Step_Function => "utf8.step",
         when Utf8_Lax_Step_Function => "utf8.lax_step",
         when Io_Close_Function => "io.close",
         when Io_Flush_Function => "io.flush",
         when Io_Input_Function => "io.input",
         when Io_Lines_Function => "io.lines",
         when Io_Open_Function => "io.open",
         when Io_Output_Function => "io.output",
         when Io_Popen_Function => "io.popen",
         when Io_Read_Function => "io.read",
         when Io_Tmpfile_Function => "io.tmpfile",
         when Io_Type_Function => "io.type",
         when Io_Write_Function => "io.write",
         when Io_Iterator_Function => "io.iterator",
         when Io_File_Gc_Function => "io.file.gc",
         when Io_File_Tostring_Function => "io.file.tostring",
         when Io_File_Read_Function => "io.file.read",
         when Io_File_Write_Function => "io.file.write",
         when Io_File_Lines_Function => "io.file.lines",
         when Io_File_Flush_Function => "io.file.flush",
         when Io_File_Seek_Function => "io.file.seek",
         when Io_File_Close_Function => "io.file.close",
         when Io_File_Setvbuf_Function => "io.file.setvbuf",
         when Os_Clock_Function => "os.clock",
         when Os_Date_Function => "os.date",
         when Os_Difftime_Function => "os.difftime",
         when Os_Execute_Function => "os.execute",
         when Os_Exit_Function => "os.exit",
         when Os_Getenv_Function => "os.getenv",
         when Os_Remove_Function => "os.remove",
         when Os_Rename_Function => "os.rename",
         when Os_Setlocale_Function => "os.setlocale",
         when Os_Time_Function => "os.time",
         when Os_Tmpname_Function => "os.tmpname",
         when Ipairs_Iterator_Function => "ipairs.iterator",
         when Gmatch_Iterator_Function => "gmatch.iterator");

   function Implementation (Id : Kind) return String is
     (if Id = Pcall_Function then "base.pcall"
      elsif Id in Print_Function .. Rawlen_Function then "base.primitive"
      else Name (Id));

   type Ordered_Ids is array (Positive range <>) of Kind;
   By_Name : constant Ordered_Ids :=
     [Arith_Add_Function,
      Arith_Div_Function,
      Arith_Idiv_Function,
      Arith_Mod_Function,
      Arith_Mul_Function,
      Arith_Pow_Function,
      Arith_Sub_Function,
      Arith_Unm_Function,
      Base_Collectgarbage_Function,
      Base_Dofile_Function,
      Base_Getmetatable_Function,
      Base_Ipairs_Function,
      Base_Load_Function,
      Base_Loadfile_Function,
      Base_Pairs_Function,
      Base_Print_Function,
      Base_Require_Function,
      Base_Setmetatable_Function,
      Base_Tostring_Function,
      Base_Warn_Function,
      Base_Xpcall_Function,
      Coroutine_Close_Function,
      Coroutine_Create_Function,
      Coroutine_Isyieldable_Function,
      Coroutine_Resume_Function,
      Coroutine_Running_Function,
      Coroutine_Status_Function,
      Coroutine_Wrap_Function,
      Coroutine_Wrapped_Function,
      Coroutine_Yield_Function,
      Debug_Gethook_Function,
      Debug_Getinfo_Function,
      Debug_Getlocal_Function,
      Debug_Getmetatable_Function,
      Debug_Getregistry_Function,
      Debug_Getupvalue_Function,
      Debug_Getuservalue_Function,
      Debug_Sethook_Function,
      Debug_Setlocal_Function,
      Debug_Setmetatable_Function,
      Debug_Setupvalue_Function,
      Debug_Setuservalue_Function,
      Debug_Traceback_Function,
      Debug_Upvalueid_Function,
      Debug_Upvaluejoin_Function,
      Gmatch_Iterator_Function,
      Io_Close_Function,
      Io_File_Close_Function,
      Io_File_Flush_Function,
      Io_File_Gc_Function,
      Io_File_Lines_Function,
      Io_File_Read_Function,
      Io_File_Seek_Function,
      Io_File_Setvbuf_Function,
      Io_File_Tostring_Function,
      Io_File_Write_Function,
      Io_Flush_Function,
      Io_Input_Function,
      Io_Iterator_Function,
      Io_Lines_Function,
      Io_Open_Function,
      Io_Output_Function,
      Io_Popen_Function,
      Io_Read_Function,
      Io_Tmpfile_Function,
      Io_Type_Function,
      Io_Write_Function,
      Ipairs_Iterator_Function,
      Math_Abs_Function,
      Math_Acos_Function,
      Math_Asin_Function,
      Math_Atan_Function,
      Math_Atan2_Function,
      Math_Ceil_Function,
      Math_Cos_Function,
      Math_Cosh_Function,
      Math_Deg_Function,
      Math_Exp_Function,
      Math_Floor_Function,
      Math_Fmod_Function,
      Math_Frexp_Function,
      Math_Ldexp_Function,
      Math_Log_Function,
      Math_Log10_Function,
      Math_Max_Function,
      Math_Min_Function,
      Math_Modf_Function,
      Math_Pow_Function,
      Math_Rad_Function,
      Math_Random_Function,
      Math_Randomseed_Function,
      Math_Sin_Function,
      Math_Sinh_Function,
      Math_Sqrt_Function,
      Math_Tan_Function,
      Math_Tanh_Function,
      Math_Tointeger_Function,
      Math_Type_Function,
      Math_Ult_Function,
      Os_Clock_Function,
      Os_Date_Function,
      Os_Difftime_Function,
      Os_Execute_Function,
      Os_Exit_Function,
      Os_Getenv_Function,
      Os_Remove_Function,
      Os_Rename_Function,
      Os_Setlocale_Function,
      Os_Time_Function,
      Os_Tmpname_Function,
      Package_C_Searcher_Function,
      Package_CRoot_Searcher_Function,
      Package_Loadlib_Function,
      Package_Lua_Searcher_Function,
      Package_Preload_Searcher_Function,
      Package_Searchpath_Function,
      Assert_Function,
      Error_Function,
      Ipairs_Function,
      Ipairs_Step_Function,
      Next_Function,
      Pairs_Function,
      Pcall_Function,
      Print_Function,
      Rawequal_Function,
      Rawget_Function,
      Rawlen_Function,
      Rawset_Function,
      Select_Function,
      Tonumber_Function,
      Tostring_Function,
      Type_Function,
      String_Byte_Function,
      String_Char_Function,
      String_Dump_Function,
      String_Find_Function,
      String_Format_Function,
      String_Gmatch_Function,
      String_Gsub_Function,
      String_Len_Function,
      String_Lower_Function,
      String_Match_Function,
      String_Pack_Function,
      String_Packsize_Function,
      String_Rep_Function,
      String_Reverse_Function,
      String_Sub_Function,
      String_Unpack_Function,
      String_Upper_Function,
      Table_Concat_Function,
      Table_Create_Function,
      Table_Insert_Function,
      Table_Move_Function,
      Table_Pack_Function,
      Table_Remove_Function,
      Table_Sort_Function,
      Table_Unpack_Function,
      Utf8_Char_Function,
      Utf8_Codepoint_Function,
      Utf8_Codes_Function,
      Utf8_Lax_Step_Function,
      Utf8_Len_Function,
      Utf8_Offset_Function,
      Utf8_Step_Function];

   function Find (Name : String) return Lookup is
      First : Positive := By_Name'First;
      Last : Natural := By_Name'Last;
      Middle : Positive;
   begin
      --  Binary search compares only immutable bounded registry names. It
      --  allocates no cache/object and performs no user-controlled callback.
      while First <= Last loop
         Middle := First + (Last - First) / 2;
         declare
            Candidate : constant String := Builtin_Registry.Name
              (By_Name (Middle));
         begin
            if Name = Candidate then
               return (True, By_Name (Middle));
            elsif Name < Candidate then
               Last := Middle - 1;
            else
               First := Middle + 1;
            end if;
         end;
      end loop;
      return (Exists => False);
   end Find;

   function Find (Address : System.Address) return Lookup is
      Ordinal : constant C.int := C_Find (Address);
   begin
      if Ordinal < 0 then return (Exists => False); end if;
      return (True, Kind'Val (Ordinal));
   end Find;

   function Handler_Address (Id : Kind) return System.Address is
     (C_Address (Kind'Pos (Id)));

   procedure Initialize is
   begin
      if C_Count /= Kind'Pos (Kind'Last) + 1 then
         raise Program_Error with "incompatible builtin registry count";
      end if;
      for Id in Kind loop
         if C.Strings.Value (C_Name (Kind'Pos (Id))) /= Name (Id) or else
           Handler_Address (Id) = System.Null_Address
         then
            raise Program_Error with "incompatible builtin registry entry";
         end if;
         declare
            Indexed : constant Lookup := Find (Name (Id));
         begin
            if not Indexed.Exists or else Indexed.Id /= Id then
               raise Program_Error with "incomplete builtin name index";
            end if;
         end;
      end loop;
   end Initialize;
end Lua.Builtin_Registry;
