with AUnit.Assertions; use AUnit.Assertions;
with Lua.Diagnostic_Text; use Lua.Diagnostic_Text;
with Lua.Storage;
with Test_Support;

package body Lua.Diagnostic_Text_Tests is
   use type Lua.Storage.Byte_Count;
   Long_Source : constant String (1 .. 1_024) := [others => 'x'];
   Longer_Source : constant String (1 .. 2_048) := [others => 'y'];
   procedure Empty_Value;
   procedure Inline_Refusal;
   procedure Long_Ownership;
   procedure Shared_Copy;
   procedure Replace_Alias;
   procedure Self_Assignment;
   procedure Refused_Replacement;
   procedure Inline_Releases_Long;
   procedure Query_Clear;
   procedure Query_Replace;
   procedure Query_Exception;
   procedure Query_Aliased_Replacement;
   procedure Query_Inline_Clear;
   procedure Counted_Bytes;
   procedure No_Blocks (Memory : Lua.Storage.Owner);

   procedure No_Blocks (Memory : Lua.Storage.Owner) is
   begin
      Assert (Lua.Storage.Statistics (Memory).Live_Blocks = 0,
              "diagnostic retained selected storage");
   end No_Blocks;

   procedure Empty_Value is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
   begin
      --  Default construction, repeated clearing and empty inspection need
      --  no selected storage or independently initialized allocator handle.
      Assert (Length (Item) = 0 and then To_String (Item) = "", "empty text");
      Clear (Item);
      Clear (Item);
      No_Blocks (Memory);
   end Empty_Value;

   procedure Inline_Refusal is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
   begin
      --  Emergency publication remains usable under permanent refusal and
      --  must not even attempt provider growth, rather than catch its error.
      Lua.Storage.Set_Failure_Countdown (Memory, 0);
      Set_Value (Item, Lua.Storage.Reference (Memory), "not enough memory");
      Assert (To_String (Item) = "not enough memory", "inline message");
      Assert (Lua.Storage.Statistics (Memory).Growth_Attempts = 0,
              "inline diagnostic attempted allocation");
      Clear (Item);
      No_Blocks (Memory);
   end Inline_Refusal;

   procedure Long_Ownership is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
   begin
      --  One long message has one selected block, including its metadata;
      --  clearing returns that actual block and does not retain a cache.
      Set_Value (Item, Lua.Storage.Reference (Memory), Long_Source);
      Assert (Lua.Storage.Statistics (Memory).Live_Blocks = 1 and then
                Lua.Storage.Statistics (Memory).Payload_Bytes >=
                  Long_Source'Length,
              "long diagnostic bypassed its selected owner");
      Assert (Length (Item) = Long_Source'Length and then
                To_String (Item) = Long_Source, "long diagnostic bytes");
      Clear (Item);
      No_Blocks (Memory);
   end Long_Ownership;

   procedure Shared_Copy is
      Memory : aliased Lua.Storage.Owner;
      First, Second : Text;
      Before : Lua.Storage.Byte_Count;
   begin
      --  Copying saved failure state shares immutable storage even when any
      --  growth would refuse. Releasing its source cannot invalidate it.
      Set_Value (First, Lua.Storage.Reference (Memory), Long_Source);
      Before := Lua.Storage.Statistics (Memory).Growth_Attempts;
      Lua.Storage.Set_Failure_Countdown (Memory, 0);
      Second := First;
      Clear (First);
      Assert (To_String (Second) = Long_Source, "copied diagnostic lifetime");
      Assert (Lua.Storage.Statistics (Memory).Growth_Attempts = Before,
              "diagnostic copy attempted growth");
      Clear (Second);
      No_Blocks (Memory);
   end Shared_Copy;

   procedure Replace_Alias is
      Memory : aliased Lua.Storage.Owner;
      First, Second : Text;
   begin
      --  Replacing one handle leaves its former immutable alias intact.
      Set_Value (First, Lua.Storage.Reference (Memory), Long_Source);
      Second := First;
      Set_Value (First, Lua.Storage.Reference (Memory), Longer_Source);
      Assert (To_String (First) = Longer_Source and then
                To_String (Second) = Long_Source, "shared text was mutated");
      Assert (Lua.Storage.Statistics (Memory).Live_Blocks = 2,
              "replacement ownership extent");
      Clear (Second);
      Clear (First);
      No_Blocks (Memory);
   end Replace_Alias;

   procedure Self_Assignment is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
      Before : Lua.Storage.Byte_Count;
      function Identity (Value : Text) return Text;
      function Identity (Value : Text) return Text is (Value);
   begin
      --  The source may alias the assignment target. Controlled temporary
      --  lifetime must retain it across target finalization without growth.
      Set_Value (Item, Lua.Storage.Reference (Memory), Long_Source);
      Before := Lua.Storage.Statistics (Memory).Growth_Attempts;
      Lua.Storage.Set_Failure_Countdown (Memory, 0);
      Item := Identity (Item);
      Assert (To_String (Item) = Long_Source and then
                Lua.Storage.Statistics (Memory).Growth_Attempts = Before,
              "aliased diagnostic assignment");
      Clear (Item);
      No_Blocks (Memory);
   end Self_Assignment;

   procedure Refused_Replacement is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
      Refused : Boolean := False;
   begin
      --  Failure before publication must leave the old payload and ownership
      --  valid. Its final release must still work under the active refusal.
      Set_Value (Item, Lua.Storage.Reference (Memory), Long_Source);
      Lua.Storage.Set_Failure_Countdown (Memory, 0);
      begin
         Set_Value (Item, Lua.Storage.Reference (Memory), Longer_Source);
      exception
         when Lua.Storage.Allocation_Error => Refused := True;
      end;
      Assert (Refused and then To_String (Item) = Long_Source and then
                Lua.Storage.Statistics (Memory).Live_Blocks = 1,
              "refused diagnostic replacement changed old ownership");
      Clear (Item);
      No_Blocks (Memory);
   end Refused_Replacement;

   procedure Inline_Releases_Long is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
      Before : Lua.Storage.Byte_Count;
   begin
      --  A memory error can replace a long prior diagnostic without growth.
      Set_Value (Item, Lua.Storage.Reference (Memory), Long_Source);
      Before := Lua.Storage.Statistics (Memory).Growth_Attempts;
      Lua.Storage.Set_Failure_Countdown (Memory, 0);
      Set_Value (Item, Lua.Storage.Reference (Memory), "not enough memory");
      Assert (To_String (Item) = "not enough memory" and then
                Lua.Storage.Statistics (Memory).Growth_Attempts = Before,
              "emergency replacement attempted growth");
      No_Blocks (Memory);
   end Inline_Releases_Long;

   procedure Query_Clear is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
      procedure Inspect (Bytes : String);
      procedure Inspect (Bytes : String) is
      begin
         Clear (Item);
         Assert (Bytes = Long_Source and then
                   Lua.Storage.Statistics (Memory).Live_Blocks = 1,
                 "cleared handle invalidated borrowed bytes");
      end Inspect;
   begin
      --  Snapshot retention protects a borrowed view through alias mutation.
      Set_Value (Item, Lua.Storage.Reference (Memory), Long_Source);
      Query (Item, Inspect'Access);
      Assert (Length (Item) = 0, "query did not clear original handle");
      No_Blocks (Memory);
   end Query_Clear;

   procedure Query_Replace is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
      procedure Inspect (Bytes : String);
      procedure Inspect (Bytes : String) is
      begin
         Set_Value (Item, Lua.Storage.Reference (Memory), Longer_Source);
         Assert (Bytes = Long_Source and then
                   Lua.Storage.Statistics (Memory).Live_Blocks = 2,
                 "replacement invalidated immutable borrowed bytes");
      end Inspect;
   begin
      --  Old and replacement ownership overlap only while the view is live.
      Set_Value (Item, Lua.Storage.Reference (Memory), Long_Source);
      Query (Item, Inspect'Access);
      Assert (To_String (Item) = Longer_Source and then
                Lua.Storage.Statistics (Memory).Live_Blocks = 1,
              "query snapshot survived beyond callback");
      Clear (Item);
      No_Blocks (Memory);
   end Query_Replace;

   procedure Query_Exception is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
      Expected : exception;
      Seen : Boolean := False;
      procedure Inspect (Bytes : String);
      procedure Inspect (Bytes : String) is
      begin
         Clear (Item);
         Assert (Bytes = Long_Source, "exception query bytes");
         raise Expected;
      end Inspect;
   begin
      --  Exceptional callback unwinding releases the final retained snapshot.
      Set_Value (Item, Lua.Storage.Reference (Memory), Long_Source);
      begin
         Query (Item, Inspect'Access);
      exception
         when Expected => Seen := True;
      end;
      Assert (Seen, "query swallowed callback exception");
      No_Blocks (Memory);
   end Query_Exception;

   procedure Query_Aliased_Replacement is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
      procedure Inspect (Bytes : String);
      procedure Inspect (Bytes : String) is
      begin
         Set_Value (Item, Lua.Storage.Reference (Memory), Bytes);
         Assert (Bytes = Long_Source, "aliased input invalidated during set");
      end Inspect;
   begin
      --  Set_Value may receive the very payload it replaces. The original
      --  immutable view must survive until the complete new copy is owned.
      Set_Value (Item, Lua.Storage.Reference (Memory), Long_Source);
      Query (Item, Inspect'Access);
      Assert (To_String (Item) = Long_Source and then
                Lua.Storage.Statistics (Memory).Live_Blocks = 1,
              "aliased replacement ownership");
      Clear (Item);
      No_Blocks (Memory);
   end Query_Aliased_Replacement;

   procedure Query_Inline_Clear is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
      procedure Inspect (Bytes : String);
      procedure Inspect (Bytes : String) is
      begin
         Clear (Item);
         Assert (Bytes = "inline", "cleared inline view changed");
      end Inspect;
   begin
      --  The inline representation also needs an independent bounded snapshot
      --  when a callback releases or replaces its original handle.
      Set_Value (Item, Lua.Storage.Reference (Memory), "inline");
      Query (Item, Inspect'Access);
      Assert (Length (Item) = 0, "inline query did not clear original");
      No_Blocks (Memory);
   end Query_Inline_Clear;

   procedure Counted_Bytes is
      Memory : aliased Lua.Storage.Owner;
      Item : Text;
      Source : String (1 .. 128) := [others => 'a'];
   begin
      --  Diagnostics preserve counted bytes rather than silently applying
      --  C-string truncation. C-specific formatting belongs at its consumer.
      Source (1) := Character'Val (0);
      Source (96) := Character'Val (0);
      Source (97) := Character'Val (0);
      Source (128) := Character'Val (0);
      for Count in 96 .. 97 loop
         Item := To_Text (Lua.Storage.Reference (Memory), Source (1 .. Count));
         Assert (Length (Item) = Count and then
                   To_String (Item) = Source (1 .. Count),
                 "diagnostic NUL truncated boundary bytes");
         Assert (Lua.Storage.Statistics (Memory).Live_Blocks =
                   (if Count = 96 then 0 else 1),
                 "inline/heap diagnostic boundary ownership");
         Clear (Item);
      end loop;
      No_Blocks (Memory);
   end Counted_Bytes;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "diagnostic text: empty value",
                        Empty_Value'Access);
      Test_Support.Add (Suite, "diagnostic text: inline permanent refusal",
                        Inline_Refusal'Access);
      Test_Support.Add (Suite, "diagnostic text: selected long ownership",
                        Long_Ownership'Access);
      Test_Support.Add (Suite, "diagnostic text: copy under refusal",
                        Shared_Copy'Access);
      Test_Support.Add (Suite, "diagnostic text: immutable alias replacement",
                        Replace_Alias'Access);
      Test_Support.Add (Suite, "diagnostic text: self assignment",
                        Self_Assignment'Access);
      Test_Support.Add (Suite, "diagnostic text: atomic refused replacement",
                        Refused_Replacement'Access);
      Test_Support.Add (Suite, "diagnostic text: inline releases long",
                        Inline_Releases_Long'Access);
      Test_Support.Add (Suite, "diagnostic text: query clears original",
                        Query_Clear'Access);
      Test_Support.Add (Suite, "diagnostic text: query replaces original",
                        Query_Replace'Access);
      Test_Support.Add (Suite, "diagnostic text: query exception cleanup",
                        Query_Exception'Access);
      Test_Support.Add (Suite, "diagnostic text: aliased borrowed replacement",
                        Query_Aliased_Replacement'Access);
      Test_Support.Add (Suite, "diagnostic text: inline query clear",
                        Query_Inline_Clear'Access);
      Test_Support.Add (Suite, "diagnostic text: counted binary bytes",
                        Counted_Bytes'Access);
   end Register;
end Lua.Diagnostic_Text_Tests;
