with Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Frontend_Text;
with Lua.Lexer_Core;
with Lua.Lexers;
with Lua.Storage; use Lua.Storage;
with Lua.Syntax;
with Lua.Syntax_Trees;
with System;
with Test_Support;

package body Lua.Frontend_Storage_Tests is
   use type Byte_Count;
   use type Lua.Lexers.Scan_Status;
   use type Lua.Lexers.Token_Kind;
   use type Lua.Syntax.Check_Status;
   use type System.Address;
   package Trees renames Lua.Syntax_Trees;
   package Core renames Lua.Lexer_Core;
   package Texts renames Lua.Frontend_Text;
   use type Trees.Node_Id;

   procedure Arena_References_Survive_Growth;
   procedure Arena_Query_Borrows_Storage;
   procedure Arena_Refusal_Preserves_Published_Text;
   procedure Scanner_Borrows_Shifted_Source;
   procedure Scanner_Comment_Does_Not_Copy_Body;
   procedure Scanner_Decoded_Text_Uses_Owner;
   procedure Parser_Uses_Selected_Owner;
   procedure Parser_Refusal_Releases_Temporaries;
   procedure Parser_Reuses_Unit;
   procedure Parser_Bindings_Compare_Bytes;
   procedure Public_Tokens_Outlive_Scanner;
   procedure Reverse_Owned_Children;
   procedure Configured_Global_Keyword;
   procedure Parser_Temporary_Loop_Lists;

   procedure Arena_References_Survive_Growth is
      Memory : Owner;
      Arena : Texts.Arena;
      First, Shifted : Texts.Text_Ref;
      Bytes : constant String (8 .. 10) := "a" & Character'Val (0) & "b";
   begin
      --  Retain an early reference, then force several reallocations. Stored
      --  offsets must still select its exact binary bytes after each move.
      Arena.Set_Owner (Reference (Memory));
      First := Arena.Store (Bytes);
      for Index in 1 .. 4_096 loop
         Shifted := Arena.Store ("another token");
      end loop;
      Assert (Arena.Text (First) = Bytes, "arena retained binary text");
      Assert (Arena.Text (Shifted) = "another token", "arena latest text");
      Assert (Statistics (Memory).Growth_Attempts < 20,
              "arena growth remained amortized");
   end Arena_References_Survive_Growth;

   procedure Arena_Query_Borrows_Storage is
      Memory : Owner;
      Arena : Texts.Arena;
      Item : Texts.Text_Ref;
      First_Address : System.Address := System.Null_Address;
      Rejected : Boolean := False;
      procedure Inspect (Bytes : String);
      procedure Inspect (Bytes : String) is
      begin
         Assert (Bytes = "actual", "borrowed arena text");
         if First_Address = System.Null_Address then
            First_Address := Bytes (Bytes'First)'Address;
         else
            Assert (Bytes (Bytes'First)'Address = First_Address,
                    "query retained actual arena address");
         end if;
         begin
            Item := Arena.Store ("mutation");
         exception
            when Program_Error => Rejected := True;
         end;
      end Inspect;
   begin
      --  The no-copy consumer can retain a pointer only for the callback.
      --  Reentrant mutation must be rejected before invalidating that view.
      Arena.Set_Owner (Reference (Memory));
      Item := Arena.Store ("actual");
      Arena.Query (Item, Inspect'Access);
      Arena.Query (Item, Inspect'Access);
      Assert (Rejected and Arena.Text (Item) = "actual",
              "arena borrow prevented relocation");
   end Arena_Query_Borrows_Storage;

   procedure Arena_Refusal_Preserves_Published_Text is
      Memory : Owner;
      Arena : Texts.Arena;
      Item : Texts.Text_Ref;
      Failed : Boolean := False;
   begin
      --  Refuse growth after a valid token has been retained. Failed append
      --  must preserve the previous reference and balanced owner accounting.
      Arena.Set_Owner (Reference (Memory));
      Item := Arena.Store ("retained");
      Set_Failure_Countdown (Memory, 0);
      begin
         declare
            Unexpected : constant Texts.Text_Ref :=
              Arena.Store (String'(1 .. 1_024 => 'x'));
         begin
            Assert (Unexpected.Length = 1_024, "unexpected append length");
         end;
      exception
         when Allocation_Error => Failed := True;
      end;
      Assert (Failed and Arena.Text (Item) = "retained",
              "failed arena growth preserved text reference");
      Assert (Refusal_Pending (Memory), "arena refusal classified");
   end Arena_Refusal_Preserves_Published_Text;

   procedure Scanner_Borrows_Shifted_Source is
      Memory : Owner;
      Arena : Texts.Arena;
      Reader : Core.Scanner_State;
      Input : String (31 .. 37) := "abc 123";
      Step : Core.Scan_Result;
   begin
      --  The core borrows its argument rather than retaining a source copy.
      --  Change an unscanned byte between calls and use unusual Ada bounds.
      Arena.Set_Owner (Reference (Memory));
      Step := Core.Next (Input, Reader, Arena);
      Assert (Step.Item.Kind = Lua.Lexers.Identifier and
              Arena.Text (Step.Item.Text) = "abc", "shifted first token");
      Input (35) := '4';
      Step := Core.Next (Input, Reader, Arena);
      Assert (Step.Item.Kind = Lua.Lexers.Integer_Literal and
              Arena.Text (Step.Item.Text) = "423", "borrowed next token");
      Assert (Step.Item.Location.Offset = 5, "relative source location");
   end Scanner_Borrows_Shifted_Source;

   procedure Scanner_Comment_Does_Not_Copy_Body is
      Memory : Owner;
      Arena : Texts.Arena;
      Reader : Core.Scanner_State;
      Input : constant String := "--[[" &
        String'(1 .. 65_536 => 'x') & "]]local";
      Step : Core.Scan_Result;
   begin
      --  A long comment changes scanner position but owns no token payload.
      --  This ceiling permits the following keyword, never a comment copy.
      Arena.Set_Owner (Reference (Memory));
      Set_Ceiling (Memory, 4_096);
      Step := Core.Next (Input, Reader, Arena);
      Assert (Step.Status = Lua.Lexers.Success and
              Step.Item.Kind = Lua.Lexers.Local_Word,
              "large comment skipped under small managed ceiling");
      Assert (Statistics (Memory).Payload_Bytes < 1_024,
              "comment body did not allocate retained or scratch bytes");
   end Scanner_Comment_Does_Not_Copy_Body;

   procedure Scanner_Decoded_Text_Uses_Owner is
      Memory : Owner;
      Arena : Texts.Arena;
      Reader : Core.Scanner_State;
      Step : Core.Scan_Result;
   begin
      --  Escapes decode into managed scratch and then the unit's arena. The
      --  scratch is gone on return; embedded NUL and UTF-8 bytes remain exact.
      Arena.Set_Owner (Reference (Memory));
      Step := Core.Next ("'\x41\000\u{80}'", Reader, Arena);
      Assert (Step.Item.Kind = Lua.Lexers.String_Literal and
              Arena.Text (Step.Item.Text) =
                "A" & Character'Val (0) & Character'Val (16#C2#) &
                  Character'Val (16#80#), "owned decoded token bytes");
      Assert (Statistics (Memory).Live_Blocks = 1,
              "decoded scratch released before scanner return");
   end Scanner_Decoded_Text_Uses_Owner;

   procedure Parser_Uses_Selected_Owner is
      Memory : Owner;
   begin
      --  Nodes, child lists, bindings, captures and token payloads must all
      --  be attributable to the supplied universe and released with the unit.
      declare
         Unit : Trees.Compilation_Unit;
      begin
         Trees.Parse (Unit,
           "local value='owned'; return function() return value end",
           "owned", (others => <>), Reference (Memory));
         Assert (Unit.Result.Status = Lua.Syntax.Success,
                 "owned parser accepted captured binding");
         Assert (Unit.Tree.Owner_Of = Reference (Memory) and
                 Unit.Names.Owner_Of = Reference (Memory),
                 "syntax storage selected supplied owner");
         Assert (Statistics (Memory).Live_Blocks > 3,
                 "syntax nodes and payloads are managed");
      end;
      Assert (Statistics (Memory).Live_Blocks = 0,
              "compilation unit finalized all managed storage");
   end Parser_Uses_Selected_Owner;

   procedure Parser_Refusal_Releases_Temporaries is
      Memory : Owner;
      Failed : Boolean := False;
   begin
      --  Exhaust growth midway through construction. The runtime must see an
      --  allocator failure, rather than a syntax rejection, and partial ASTs
      --  must not survive after their compilation unit leaves scope.
      Set_Failure_Countdown (Memory, 3);
      begin
         declare
            Unit : Trees.Compilation_Unit;
         begin
            Trees.Parse (Unit, "local first,second=1,2; return first+second",
                         "refusal", (others => <>), Reference (Memory));
            Assert (Unit.Result.Status = Lua.Syntax.Success,
                    "refused parse unexpectedly returned");
         end;
      exception
         when Allocation_Error | Program_Error => Failed := True;
      end;
      Assert (Failed and Refusal_Pending (Memory),
              "frontend retained allocator failure classification");
      Assert (Statistics (Memory).Live_Blocks = 0,
              "refused frontend finalized its partial arena");
      Clear_Failures (Memory);
      Acknowledge_Refusal (Memory);
      declare
         Unit : Trees.Compilation_Unit;
      begin
         Trees.Parse (Unit, "return 1", "recovery", (others => <>),
                      Reference (Memory));
         Assert (Unit.Result.Status = Lua.Syntax.Success,
                 "same allocator usable after frontend refusal");
      end;
   end Parser_Refusal_Releases_Temporaries;

   procedure Parser_Reuses_Unit is
      Memory : Owner;
      Unit : Trees.Compilation_Unit;
   begin
      --  Reusing a unit with the same allocator must reset source refs and
      --  resolution state after both success and a controlled syntax failure.
      Trees.Parse (Unit, "local x=1; return x", "first", (others => <>),
                   Reference (Memory));
      Trees.Parse (Unit, "local =", "bad", (others => <>),
                   Reference (Memory));
      Assert (Unit.Result.Status = Lua.Syntax.Syntax_Error,
              "reused unit reported syntax failure");
      Trees.Parse (Unit, "return 'last'", "last", (others => <>),
                   Reference (Memory));
      Assert (Unit.Result.Status = Lua.Syntax.Success and
              Trees.Text (Unit, Unit.Result.Error.Source) = "last",
              "reused unit reset source and parser state");
   end Parser_Reuses_Unit;

   procedure Parser_Bindings_Compare_Bytes is
      Unit : Trees.Compilation_Unit;
   begin
      --  Separate occurrences have different arena offsets. Resolution and
      --  goto matching must compare their bytes rather than reference records.
      Trees.Parse (Unit,
        "local count<const> = 1; ::again:: do local other=count end; " &
        "goto again", "binding bytes", (others => <>));
      Assert (Unit.Result.Status = Lua.Syntax.Success,
              "names and labels resolved by byte content");
      Trees.Parse (Unit, "local value<const> =1; value=2", "const bytes",
                   (others => <>));
      Assert (Unit.Result.Status = Lua.Syntax.Syntax_Error,
              "separate reference still resolves const binding");
   end Parser_Bindings_Compare_Bytes;

   procedure Public_Tokens_Outlive_Scanner is
      Saved : Lua.Lexers.Scan_Result;
   begin
      --  The existing host API remains independently owned. Destroying its
      --  scanner/default arena cannot invalidate a returned decoded string.
      declare
         Reader : Lua.Lexers.Scanner := Lua.Lexers.Open ("'retained'");
      begin
         Saved := Lua.Lexers.Next (Reader);
      end;
      Assert (Saved.Status = Lua.Lexers.Success and
              Ada.Strings.Unbounded.To_String
                (Saved.Tokens.First_Element.Text) = "retained",
              "host token retained independent source bytes");
   end Public_Tokens_Outlive_Scanner;

   procedure Reverse_Owned_Children is
      Memory : Owner;
      Children : Trees.Node_Lists.Vector;
      Expected : Trees.Node_Id := 3;
   begin
      --  Scope resolution scans active declarations and terminal labels in
      --  reverse. The managed container must retain that iterable behavior.
      Children.Set_Owner (Reference (Memory));
      Children.Append (1);
      Children.Append (2);
      Children.Append (3);
      for Child of reverse Children loop
         Assert (Child = Expected, "reverse managed child ordering");
         Expected := Expected - 1;
      end loop;
      Assert (Expected = 0, "reverse iterator visited every element");
   end Reverse_Owned_Children;

   procedure Configured_Global_Keyword is
      Memory : Owner;
      Arena : Texts.Arena;
      Reader : Core.Scanner_State :=
        (Compatible_Global => False, others => <>);
      Step : Core.Scan_Result;
      Unit : Trees.Compilation_Unit;
   begin
      --  The ordinary API keeps pinned contextual globals. The configured
      --  frontend can reserve that keyword for the C test build without a
      --  second scanner or a post-tokenization spelling rewrite.
      Arena.Set_Owner (Reference (Memory));
      Step := Core.Next ("global", Reader, Arena);
      Assert (Step.Item.Kind = Lua.Lexers.Global_Word,
              "configured scanner reserved global");
      Trees.Parse (Unit, "global named=1; return named", "reserved",
                   (others => <>), Compatible_Global => False);
      Assert (Unit.Result.Status = Lua.Syntax.Success,
              "reserved declaration accepted");
      Trees.Parse (Unit, "local global=1", "reserved identifier",
                   (others => <>), Compatible_Global => False);
      Assert (Unit.Result.Status = Lua.Syntax.Syntax_Error,
              "reserved keyword rejected as local name");
   end Configured_Global_Keyword;

   procedure Parser_Temporary_Loop_Lists is
      Memory : Owner;
   begin
      --  Both loop forms gather their declaration list before publishing a
      --  node. That temporary list needs an owner too, not just stored nodes.
      --  Keep the two related forms in this focused ownership regression.
      for Numeric in Boolean loop
         declare
            Unit : Trees.Compilation_Unit;
         begin
            Trees.Parse
              (Unit,
               (if Numeric then "for i=1,3 do local x=i end"
                else "for key,value in next,t do local x=value end"),
               "loop owner", (others => <>), Reference (Memory));
            Assert (Unit.Result.Status = Lua.Syntax.Success,
                    "temporary loop declaration list is owned");
         end;
         Assert (Statistics (Memory).Live_Blocks = 0,
                 "temporary loop syntax storage released");
      end loop;
   end Parser_Temporary_Loop_Lists;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "owned frontend: stable arena references",
                        Arena_References_Survive_Growth'Access);
      Test_Support.Add (Suite, "owned frontend: borrowed arena text",
                        Arena_Query_Borrows_Storage'Access);
      Test_Support.Add (Suite, "owned frontend: arena refusal atomicity",
                        Arena_Refusal_Preserves_Published_Text'Access);
      Test_Support.Add (Suite, "owned frontend: shifted borrowed source",
                        Scanner_Borrows_Shifted_Source'Access);
      Test_Support.Add (Suite, "owned frontend: discarded comment body",
                        Scanner_Comment_Does_Not_Copy_Body'Access);
      Test_Support.Add (Suite, "owned frontend: owned decoded token",
                        Scanner_Decoded_Text_Uses_Owner'Access);
      Test_Support.Add (Suite, "owned frontend: selected syntax allocator",
                        Parser_Uses_Selected_Owner'Access);
      Test_Support.Add (Suite, "owned frontend: partial refusal cleanup",
                        Parser_Refusal_Releases_Temporaries'Access);
      Test_Support.Add (Suite, "owned frontend: repeated compilation unit",
                        Parser_Reuses_Unit'Access);
      Test_Support.Add (Suite, "owned frontend: name content resolution",
                        Parser_Bindings_Compare_Bytes'Access);
      Test_Support.Add (Suite, "owned frontend: independent public tokens",
                        Public_Tokens_Outlive_Scanner'Access);
      Test_Support.Add (Suite, "owned frontend: reverse declaration walk",
                        Reverse_Owned_Children'Access);
      Test_Support.Add (Suite, "owned frontend: configured global keyword",
                        Configured_Global_Keyword'Access);
      Test_Support.Add (Suite, "owned frontend: temporary loop lists",
                        Parser_Temporary_Loop_Lists'Access);
   end Register;
end Lua.Frontend_Storage_Tests;
