with Interfaces.C;
with System;

private package Lua.Platform_Streams is
   --  Opaque host stdio mechanics only. The caller validates Lua options and
   --  owns the lifetime. These bindings never execute Lua or retain byte
   --  views.
   package C renames Interfaces.C;
   type Handle is new System.Address with Convention => C;
   No_Stream : constant Handle := Handle (System.Null_Address);
   type Standard_Stream is (Standard_Input, Standard_Output, Standard_Error)
     with Convention => C;
   for Standard_Stream use
     (Standard_Input => 0, Standard_Output => 1, Standard_Error => 2);
   type Seek_Origin is (From_Start, From_Current, From_End)
     with Convention => C;
   for Seek_Origin use (From_Start => 0, From_Current => 1, From_End => 2);
   type Buffer_Mode is (Unbuffered, Fully_Buffered, Line_Buffered)
     with Convention => C;
   for Buffer_Mode use
     (Unbuffered => 0, Fully_Buffered => 1, Line_Buffered => 2);

   function Standard (Which : Standard_Stream) return Handle
     with Import, Convention => C, External_Name => "lua_ada_stream_standard";
   function Open
     (Name, Mode : System.Address; Error : access C.int) return Handle
     with Import, Convention => C, External_Name => "lua_ada_stream_open";
   function Temporary (Error : access C.int) return Handle
     with Import, Convention => C, External_Name => "lua_ada_stream_temporary";
   function Open_Pipe
     (Command, Mode : System.Address; Error : access C.int) return Handle
     with Import, Convention => C, External_Name => "lua_ada_stream_pipe";
   --  Name/mode/command are borrowed NUL-terminated host strings. Native FILE
   --  ownership transfers only on a nonnull return; Error is captured before
   --  returning to any allocating Ada operation.

   function Close (File : Handle; Error : access C.int) return C.int
     with Import, Convention => C, External_Name => "lua_ada_stream_close";
   function Close_Pipe (File : Handle; Error : access C.int) return C.int
     with Import, Convention => C, External_Name => "lua_ada_stream_pclose";
   --  Ordinary close returns native success/failure; pipe close retains the
   --  native wait status for platform-aware Lua result adjustment.

   procedure Begin_Read (File : Handle)
     with Import, Convention => C,
          External_Name => "lua_ada_stream_begin_read";
   function Read
     (File : Handle; Bytes : System.Address; Count : C.size_t;
      Error : access C.int) return C.size_t
     with Import, Convention => C, External_Name => "lua_ada_stream_read";
   function Get_Byte (File : Handle; Error : access C.int) return C.int
     with Import, Convention => C, External_Name => "lua_ada_stream_get";
   procedure Unread_Byte (File : Handle; Byte : C.int)
     with Import, Convention => C, External_Name => "lua_ada_stream_unget";
   function Is_End (File : Handle) return C.int
     with Import, Convention => C, External_Name => "lua_ada_stream_eof";
   function Has_Error (File : Handle) return C.int
     with Import, Convention => C, External_Name => "lua_ada_stream_error";
   function End_Marker return C.int
     with Import, Convention => C,
          External_Name => "lua_ada_stream_end_marker";
   --  Begin_Read clears flags once per Lua operation. A zero-sized Read does
   --  not inspect Bytes. Get/Unread permit one-byte lookahead, including EOF's
   --  ordinary no-op unread. Retain Error before allocator/GC safe points.

   function Write
     (File : Handle; Bytes : System.Address; Count : C.size_t;
      Error : access C.int) return C.size_t
     with Import, Convention => C, External_Name => "lua_ada_stream_write";
   function Flush (File : Handle; Error : access C.int) return C.int
     with Import, Convention => C, External_Name => "lua_ada_stream_flush";
   function Set_Buffering
     (File : Handle; Mode : Buffer_Mode; Size : C.size_t;
      Error : access C.int) return C.int
     with Import, Convention => C, External_Name => "lua_ada_stream_buffer";
   --  Buffer storage belongs to libc, matching setvbuf(NULL,...); no caller
   --  pointer survives. Native short writes preserve their actual byte count.

   function Offset_Bits return C.int
     with Import, Convention => C, External_Name => "lua_ada_stream_seek_bits";
   function Seek
     (File : Handle; Offset : C.long_long; Origin : Seek_Origin;
      Error : access C.int) return C.int
     with Import, Convention => C, External_Name => "lua_ada_stream_seek";
   function Position (File : Handle) return C.long_long
     with Import, Convention => C, External_Name => "lua_ada_stream_position";
   function Pointer_Text
     (File : Handle; Bytes : System.Address; Capacity : C.size_t)
      return C.size_t
     with Import, Convention => C,
       External_Name => "lua_ada_stream_pointer_text";
   --  Native %p spelling for the public FILE pointer. Bytes is a synchronous
   --  writable range; callers provide enough space for a pointer token.
   --  Validate offset against Offset_Bits before seeking. This deliberately
   --  follows pinned POSIX off_t / native MinGW C-long configuration rather
   --  than silently granting MSVC's unrelated 64-bit extension on MinGW.
end Lua.Platform_Streams;
