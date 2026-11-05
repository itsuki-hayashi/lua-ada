with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Simple_Test_Cases;

package body Test_Support is
   --  A small adapter keeps mechanical fixture plumbing out of the tests.
   --  AUnit still sees a separate object/result for every registered action.
   type Action_Case is new AUnit.Simple_Test_Cases.Test_Case with record
      Title  : Unbounded_String;
      Action : Test_Action;
   end record;

   overriding function Name (Item : Action_Case) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Action_Case);

   overriding function Name (Item : Action_Case) return AUnit.Message_String is
     (AUnit.Format (To_String (Item.Title)));

   overriding procedure Run_Test (Item : in out Action_Case) is
   begin
      Item.Action.all;
   end Run_Test;

   procedure Add
     (Suite : AUnit.Test_Suites.Access_Test_Suite;
      Title : String; Action : Test_Action)
   is
      Item : constant AUnit.Simple_Test_Cases.Test_Case_Access :=
        new Action_Case;
   begin
      --  Store independent state rather than a pointer into a registration
      --  loop. The action's library-level lifetime covers the whole run.
      Action_Case (Item.all).Title := To_Unbounded_String (Title);
      Action_Case (Item.all).Action := Action;
      Suite.Add_Test (Item);
   end Add;
end Test_Support;
