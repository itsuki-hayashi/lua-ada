with Ada.Containers;
with Ada.Unchecked_Deallocation;

package body Lua.Prototypes is
   use type Interfaces.Unsigned_64;
   use type Ada.Containers.Count_Type;
   use type Lua.Storage.Owner_Access;
   use type System.Address;

   procedure Free is new Ada.Unchecked_Deallocation
     (Prototype, Prototype_Access);
   function Hash (Text : String) return Interfaces.Unsigned_64;
   function Equal_Text (Self : Program; Id : String_Id; Text : String)
                        return Boolean;
   procedure Grow_Strings (Self : in out Program);
   procedure Rehash (Self : in out Program);

   procedure Set_Owner
     (Self : in out Program; Memory : not null Lua.Storage.Owner_Access)
   is
   begin
      if Self.Memory = Memory then
         return;
      elsif Self.Memory /= null then
         raise Program_Error with "canonical program already has an owner";
      end if;
      Self.Memory := Memory;
      Self.Nodes.Set_Owner (Memory);
      Self.Texts.Set_Owner (Memory);
      Self.Buckets.Set_Owner (Memory);
   end Set_Owner;

   function Owner_Of (Self : Program) return Lua.Storage.Owner_Access is
     (Self.Memory);

   function New_Prototype (Self : in out Program) return Prototype_Access is
      Item : Prototype_Access;
   begin
      if Self.Memory = null then
         raise Program_Error with "canonical program requires an owner";
      end if;
      if Self.Nodes.Length = Ada.Containers.Count_Type (Natural'Last) then
         raise Lua.Storage.Allocation_Error;
      end if;
      --  Reserve the registry slot first: once the typed node exists, its
      --  nonallocating publication cannot fail and leave it unregistered.
      Self.Nodes.Reserve_Capacity (Self.Nodes.Length + 1);
      Item := new (Lua.Storage.Handle (Self.Memory.all)) Prototype;
      Item.Code.Set_Owner (Self.Memory);
      Item.Constants.Set_Owner (Self.Memory);
      Item.Upvalues.Set_Owner (Self.Memory);
      Item.Children.Set_Owner (Self.Memory);
      Item.Lines.Set_Owner (Self.Memory);
      Item.Absolute_Lines.Set_Owner (Self.Memory);
      Item.Locals.Set_Owner (Self.Memory);
      Item.Owner_Token := Self'Address;
      Item.Node_Index := Natural (Self.Nodes.Length) + 1;
      Self.Nodes.Append (Item);
      return Item;
   end New_Prototype;

   function Owns (Self : Program; Item : Prototype_Access) return Boolean is
     (Item /= null and then Item.Owner_Token = Self'Address and then
      Item.Node_Index in 1 .. Natural (Self.Nodes.Length) and then
      Self.Nodes (Item.Node_Index) = Item);

   procedure Set_Root (Self : in out Program; Item : Prototype_Access) is
   begin
      if not Owns (Self, Item) then
         raise Program_Error with "canonical root belongs to another program";
      end if;
      Self.Main := Item;
   end Set_Root;

   function Root (Self : Program) return Prototype_Access is (Self.Main);
   function Prototype_Count (Self : Program) return Natural is
     (Natural (Self.Nodes.Length));
   function Prototype_At
     (Self : Program; Index : Positive) return Prototype_Access is
     (Self.Nodes (Index));
   function String_Count (Self : Program) return Natural is
     (Natural (Self.Texts.Length));

   function Hash (Text : String) return Interfaces.Unsigned_64 is
      Result : Interfaces.Unsigned_64 := 16#CBF2_9CE4_8422_2325#;
   begin
      for Item of Text loop
         Result := (Result xor Interfaces.Unsigned_64
           (Character'Pos (Item))) * 16#100_0000_01B3#;
      end loop;
      return Result;
   end Hash;

   function Equal_Text (Self : Program; Id : String_Id; Text : String)
                        return Boolean
   is
      Offset : Natural := 0;
   begin
      if Self.Texts (Positive (Id)).Bytes.Length /= Text'Length then
         return False;
      end if;
      for Item of Text loop
         Offset := Offset + 1;
         if Self.Texts (Positive (Id)).Bytes.Element (Offset) /= Item then
            return False;
         end if;
      end loop;
      return True;
   end Equal_Text;

   procedure Rehash (Self : in out Program) is
      Bucket : Positive;
      procedure Set_Link (Item : in out String_Entry);
      procedure Set_Link (Item : in out String_Entry) is
      begin
         Item.Next := Self.Buckets (Bucket);
      end Set_Link;
   begin
      for Index in Self.Buckets.First_Index .. Self.Buckets.Last_Index loop
         Self.Buckets.Replace_Element (Index, No_String);
      end loop;
      for Index in Self.Texts.First_Index .. Self.Texts.Last_Index loop
         Bucket := Natural (Self.Texts (Index).Hash mod
           Interfaces.Unsigned_64 (Self.Buckets.Length)) + 1;
         --  Updating a link must not copy an accumulated owned byte buffer.
         Self.Texts.Update_Element (Index, Set_Link'Access);
         Self.Buckets.Replace_Element (Bucket, String_Id (Index));
      end loop;
   end Rehash;

   procedure Grow_Strings (Self : in out Program) is
      Size : constant Natural := Natural (Self.Buckets.Length);
      Desired : Natural;
   begin
      if Size /= 0 and then Natural (Self.Texts.Length) < Size / 2 then
         return;
      elsif Size > Natural'Last / 2 then
         raise Lua.Storage.Allocation_Error;
      end if;
      Desired := Natural'Max (8, Size * 2);
      Self.Buckets.Set_Length (Ada.Containers.Count_Type (Desired));
      Rehash (Self);
   end Grow_Strings;

   function Intern (Self : in out Program; Text : String) return String_Id is
      Code : constant Interfaces.Unsigned_64 := Hash (Text);
      Cursor : String_Id := No_String;
      Bucket : Positive;
   begin
      if Self.Memory = null then
         raise Program_Error with "canonical strings require an owner";
      end if;
      if not Self.Buckets.Is_Empty then
         Bucket := Natural (Code mod
           Interfaces.Unsigned_64 (Self.Buckets.Length)) + 1;
         Cursor := Self.Buckets (Bucket);
         while Cursor /= No_String loop
            if Self.Texts (Positive (Cursor)).Hash = Code and then
              Equal_Text (Self, Cursor, Text)
            then
               return Cursor;
            end if;
            Cursor := Self.Texts (Positive (Cursor)).Next;
         end loop;
      end if;
      if Self.Texts.Length = Ada.Containers.Count_Type (Natural'Last) then
         raise Lua.Storage.Allocation_Error;
      end if;
      Grow_Strings (Self);
      Bucket := Natural (Code mod
        Interfaces.Unsigned_64 (Self.Buckets.Length)) + 1;
      declare
         Fresh : String_Entry;
      begin
         Fresh.Bytes.Set_Owner (Self.Memory);
         --  Public debug metadata borrows frozen program strings directly.
         --  Even an empty debug name needs real stable NUL storage; reserve
         --  it while constructing the graph, never during a read-only query.
         Fresh.Bytes.Reserve_Capacity (1);
         Fresh.Bytes.Set_Value (Text);
         Fresh.Hash := Code;
         Fresh.Next := Self.Buckets (Bucket);
         Self.Texts.Append (Fresh);
      end;
      Cursor := String_Id (Self.Texts.Last_Index);
      Self.Buckets.Replace_Element (Bucket, Cursor);
      return Cursor;
   end Intern;

   function String_Length (Self : Program; Id : String_Id) return Natural is
     (Self.Texts (Positive (Id)).Bytes.Length);
   function String_Address
     (Self : Program; Id : String_Id) return System.Address is
     (Self.Texts (Positive (Id)).Bytes.Address);
   function String_Element
     (Self : Program; Id : String_Id; Index : Positive) return Character is
     (Self.Texts (Positive (Id)).Bytes.Element (Index));

   procedure Query_String
     (Self : in out Program; Id : String_Id;
      Process : not null access procedure (Text : String))
   is
      procedure Query (Item : in out String_Entry);
      procedure Query (Item : in out String_Entry) is
      begin
         Item.Bytes.Query (Process);
      end Query;
   begin
      Self.Texts.Update_Element (Positive (Id), Query'Access);
   end Query_String;

   procedure Close (Self : in out Program) is
   begin
      Self.Main := null;
      for Item of Self.Nodes loop
         declare
            Owned : Prototype_Access := Item;
         begin
            Free (Owned);
         end;
      end loop;
      --  Clear alone retains capacity and would leave buffers borrowing the
      --  owner after Close. Empty assignment destroys every capacity block.
      Self.Nodes := Node_Lists.Empty_Vector;
      Self.Texts := String_Lists.Empty_Vector;
      Self.Buckets := Index_Lists.Empty_Vector;
      Self.Memory := null;
   end Close;

   procedure Move (Target, Source : in out Program) is
   begin
      if Target'Address = Source'Address then
         return;
      end if;
      Close (Target);
      --  Vector moves transfer ownership-bearing buffers rather than cloning
      --  controlled strings or nodes. All remaining work is nonallocating;
      --  allocation refusal cannot interrupt the identity transition.
      Node_Lists.Move (Target.Nodes, Source.Nodes);
      String_Lists.Move (Target.Texts, Source.Texts);
      Index_Lists.Move (Target.Buckets, Source.Buckets);
      Target.Memory := Source.Memory;
      Target.Main := Source.Main;
      Source.Memory := null;
      Source.Main := null;
      for Item of Target.Nodes loop
         Item.Owner_Token := Target'Address;
      end loop;
   end Move;

   overriding procedure Finalize (Self : in out Program) is
   begin
      Close (Self);
   end Finalize;
end Lua.Prototypes;
