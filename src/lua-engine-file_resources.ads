with Interfaces.C;
with Lua.Engine.Foreign;
with Lua.Platform_Streams;

package Lua.Engine.File_Resources is
   package Streams renames Lua.Platform_Streams;
   type File_Kind is (Regular_File, Pipe_File, Borrowed_File);

   type Stream_Header is record
      File : Streams.Handle := Streams.No_Stream;
      Closer : Foreign.C_Function := null;
   end record with Convention => C;
   --  Exact public luaL_Stream payload: the native FILE pointer and a real
   --  callable lua_CFunction. Allocation/finalization metadata lives outside
   --  these C-visible bytes; no C private userdata layout is reproduced.

   type Header_Access is access all Stream_Header;
   function Header (Item : Value) return Header_Access;
   --  Borrow the payload until Item ceases to be traced. The caller first
   --  validates the actual FILE* metatable; undersized userdata is rejected
   --  defensively instead of borrowing memory beyond the supplied payload.

   function Is_File (State : World; Item : Value) return Boolean;
   --  Compare the actual registry FILE* metatable without allocating. This
   --  also accepts correctly formed file userdata made through the C API.

   function New_Closed
     (State : in out World; Kind : File_Kind) return Value;
   --  Allocate/root a closed prefile and its first-party host metadata before
   --  fopen/popen/tmpfile can create an external resource. Construction has
   --  no native side effects; it is safe to fail under allocator refusal.

   procedure Prepare
     (Item : Value; Closer : not null Foreign.C_Function);
   --  Install the actual newfile primitive before fopen/tmpfile/mode checks.
   --  A failed native open retains that handler with a null FILE, matching
   --  C's observable prefile state; the ordinary __gc path ignores null FILEs.

   procedure Publish
     (Item : Value; File : Streams.Handle;
      Closer : not null Foreign.C_Function);
   --  Publish an already-open native stream without allocating. New_Closed
   --  owns Item; its metatable and any result packet must already be rooted.

   function Take_Closer (Item : Value) return Foreign.C_Function;
   --  Save the actual handler and clear closef before invocation, exactly as
   --  aux_close does. This operation neither calls Lua nor closes the FILE.

   procedure Close_Native
     (Item : Value; Kind : File_Kind;
      Primitive : not null Foreign.C_Function;
      Status, Error : out Interfaces.C.int);
   --  Execute a known first-party primitive in the current logical native
   --  frame. Ordinary/pipe status comes from libc. Borrowed standard streams
   --  are never closed: restore their real primitive and return Status=-1,
   --  Error=0 so the Lua layer supplies its prescribed explanatory message.
   --  This routine does not allocate, execute Lua, or create a debug frame.
end Lua.Engine.File_Resources;
