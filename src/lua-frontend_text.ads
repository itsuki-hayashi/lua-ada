with Lua.Storage.Buffers;

private package Lua.Frontend_Text is
   --  One arena owns decoded token text and parser names. References contain
   --  offsets rather than pointers, so geometric growth cannot invalidate
   --  nodes, lookahead tokens or bindings retained by the compilation unit.
   type Text_Ref is record
      First : Positive := 1;
      Length : Natural := 0;
   end record;
   Empty_Text : constant Text_Ref := (1, 0);
   type Arena is tagged limited private;
   procedure Set_Owner
     (Self : in out Arena; Memory : not null Lua.Storage.Owner_Access);
   function Owner_Of (Self : Arena) return Lua.Storage.Owner_Access;
   procedure Clear (Self : in out Arena);
   function Store (Self : in out Arena; Text : String) return Text_Ref;
   function Store
     (Self : in out Arena; Text : in out Lua.Storage.Buffers.Buffer)
      return Text_Ref;
   --  Append once through the chosen allocator. Empty text needs no storage.
   function Text (Self : Arena; Item : Text_Ref) return String;
   --  Materialize a host String. Runtime consumers should prefer Query.
   procedure Query
     (Self : in out Arena; Item : Text_Ref;
      Process : not null access procedure (Text : String));
   --  The borrowed view lives only during Process; no mutation of this arena
   --  is allowed until the callback returns, including exceptional returns.
   function Equal (Self : Arena; Left, Right : Text_Ref) return Boolean;
   function Equal (Self : Arena; Left : Text_Ref; Right : String)
                  return Boolean;
   function Element
     (Self : Arena; Item : Text_Ref; Index : Positive) return Character;

private
   type Arena is tagged limited record
      Data : Lua.Storage.Buffers.Buffer;
   end record;
end Lua.Frontend_Text;
