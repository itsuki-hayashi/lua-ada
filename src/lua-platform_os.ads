with Interfaces.C;
with System;

private package Lua.Platform_OS is
   --  Native OS/libc mechanics only. Lua option validation, table access,
   --  continuations and error/result construction belong to Ada libraries.
   package C renames Interfaces.C;
   use type C.int;

   function Clock return C.double
     with Import, Convention => C, External_Name => "lua_ada_os_clock";
   function Execute (Command : System.Address; Error : access C.int)
                     return C.int
     with Import, Convention => C, External_Name => "lua_ada_os_execute";
   function Exit_Success return C.int
     with Import, Convention => C, External_Name => "lua_ada_os_exit_success";
   function Exit_Failure return C.int
     with Import, Convention => C, External_Name => "lua_ada_os_exit_failure";
   procedure Exit_Process (Code : C.int)
     with Import, Convention => C, No_Return,
       External_Name => "lua_ada_os_exit";
   --  Only the CLI or C-owned pump calls Exit_Process after Ada execution has
   --  returned. The interpreter reports a typed request to embedding hosts.

   procedure Decode_Status
     (Status : C.int; Code, Signaled : access C.int)
     with Import, Convention => C, External_Name => "lua_ada_os_status";
   --  POSIX wait-status interpretation is native mechanics. Windows keeps
   --  the returned process code unchanged, matching its actual system API.

   function Remove (Name : System.Address; Error : access C.int) return C.int
     with Import, Convention => C, External_Name => "lua_ada_os_remove";
   function Rename
     (Old_Name, New_Name : System.Address; Error : access C.int) return C.int
     with Import, Convention => C, External_Name => "lua_ada_os_rename";
   function Environment (Name : System.Address) return System.Address
     with Import, Convention => C, External_Name => "getenv";
   function Error_Text (Code : C.int) return System.Address
     with Import, Convention => C, External_Name => "strerror";
   function Text_Length (Text : System.Address) return C.size_t
     with Import, Convention => C, External_Name => "strlen";
   --  Returned environment/error pointers are synchronous borrows into libc
   --  storage. Copy them before running Lua or another modifying OS call.

   function Temporary_Name_Capacity return C.size_t
     with Import, Convention => C, External_Name => "lua_ada_os_tmpname_size";
   function Temporary_Name (Bytes : System.Address; Error : access C.int)
                            return C.int
     with Import, Convention => C, External_Name => "lua_ada_os_tmpname";
   --  Bytes has at least Temporary_Name_Capacity bytes. POSIX creates a real
   --  mkstemp path and closes its descriptor; native Windows uses tmpnam.

   type Broken_Down_Time is record
      Second, Minute, Hour : C.int := 0;
      Day : C.int := 0;
      Month : C.int := 0;
      Year : C.int := 0;
      Weekday : C.int := 0;
      Yearday : C.int := 0;
      Daylight : C.int := -1;
   end record with Convention => C;
   --  Public C tm fields are transferred by name, never by assuming tm's
   --  private platform layout. Month is zero-based, Year is relative to 1900,
   --  Weekday/Yearday are zero-based, and negative Daylight means unknown.

   function Time_Current (Valid : access C.int) return C.long_long
     with Import, Convention => C, External_Name => "lua_ada_os_time";
   function Time_Representable (Stamp : C.long_long) return C.int
     with Import, Convention => C, External_Name => "lua_ada_os_time_range";
   function Calendar_Time
     (Stamp : C.long_long; Universal : C.int;
      Result : access Broken_Down_Time) return C.int
     with Import, Convention => C, External_Name => "lua_ada_os_calendar";
   function Normalize_Time
     (Date : access Broken_Down_Time; Valid : access C.int)
      return C.long_long
     with Import, Convention => C, External_Name => "lua_ada_os_normalize";
   --  Normalize_Time always copies the native normalized fields back, even
   --  when mktime returns its failure sentinel. Ada publishes those field
   --  writes before reporting the corresponding Lua error.
   function Difference (Left, Right : C.long_long) return C.double
     with Import, Convention => C, External_Name => "lua_ada_os_difftime";
   function Format_Time
     (Bytes : System.Address; Capacity : C.size_t; Format : System.Address;
      Stamp : C.long_long; Universal : C.int) return C.size_t
     with Import, Convention => C, External_Name => "lua_ada_os_strftime";
   --  The Ada caller validates each conversion and supplies a bounded output
   --  buffer, preserving Lua's individual 250-byte strftime-item behavior.
   --  Native date conversion retains private timezone extensions for %z/%Z;
   --  the public tm carrier deliberately does not invent their layout.
end Lua.Platform_OS;
