with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Formats;
with Lua.Engine.Format_Drivers;
with Lua.Engine.Patterns;
with Lua.Engine.Pattern_Drivers;
with Lua.Engine.Strings;
with Lua.Numbers;
with Test_Support;

package body Lua.String_Helper_Tests is
   use type Integer_Value;
   use type Real_Value;
   procedure Free_Frame is new Ada.Unchecked_Deallocation
     (Frame, Frame_Access);

   generic
      with procedure Action (State : in out World);
   procedure Fixture;

   procedure Fixture is
      State : World;
   begin
      --  Each case owns a fresh heap. Finalization also runs after assertion
      --  failures, so a failed case cannot contaminate its successor.
      Initialize (State, (others => <>));
      begin
         Action (State);
      exception
         when others =>
            Finalize (State);
            raise;
      end;
      Finalize (State);
   end Fixture;

   procedure Captured_Backreference (State : in out World);
   procedure Balanced_Nesting (State : in out World);
   procedure Frontier_Boundaries (State : in out World);
   procedure Capture_Rollback (State : in out World);
   procedure Binary_Classes (State : in out World);
   procedure Position_Captures (State : in out World);
   procedure Malformed_Pattern (State : in out World);
   procedure Pattern_Budget (State : in out World);
   procedure Empty_Plain_Search (State : in out World);
   procedure Negative_Substring (State : in out World);
   procedure Huge_Empty_Repetition (State : in out World);
   procedure Decimal_Rounding (State : in out World);
   procedure Hexadecimal_Rounding (State : in out World);
   procedure Unsigned_Formatting (State : in out World);
   procedure Binary_Quoting (State : in out World);
   procedure Invalid_Format_Flags (State : in out World);
   procedure Precision_Digit_Limit (State : in out World);
   procedure Binary_String_Formatting (State : in out World);
   procedure Empty_Match_Progression (State : in out World);
   procedure Iterator_Persistence (State : in out World);
   procedure Formatting_Callback (State : in out World);
   procedure Replacement_Roots (State : in out World);
   procedure Quoting_Budget (State : in out World);
   procedure Iterator_Copy_Budget (State : in out World);
   procedure Replacement_Copy_Budget (State : in out World);
   procedure Backreference_Comparison_Budget (State : in out World);
   procedure MacOS_Subnormal_Formatting (State : in out World);
   procedure MacOS_Hexadecimal_Modifiers (State : in out World);
   procedure Linux_Subnormal_Formatting (State : in out World);

   procedure Captured_Backreference (State : in out World) is
      Found : Patterns.Match_Result;
      Captures : Values.Vector := Owned_Values (State);
   begin
      --  The second occurrence must equal the captured bytes, rather than
      --  merely matching the same character class independently.
      Found := Patterns.Find (State, "go go stop", "(%a+)%s+%1");
      Captures := Patterns.Capture_Values (State, "go go stop", Found);
      Assert (Found.Found and then Found.After = 5, "backreference span");
      Assert (Captures (1).Reference.Bytes = "go", "capture payload");
   end Captured_Backreference;

   procedure Balanced_Nesting (State : in out World) is
      Found : Patterns.Match_Result;
   begin
      --  Balanced matching counts nested pairs and consumes the matching
      --  close, protecting the transition back to ordinary pattern scanning.
      Found := Patterns.Find (State, "x(a(b)c)y", "%b()");
      Assert (Found.Found and then Found.First = 1 and then Found.After = 8,
              "balanced pair span");
   end Balanced_Nesting;

   procedure Frontier_Boundaries (State : in out World) is
      Found : Patterns.Match_Result;
   begin
      --  Virtual NUL bytes participate at both subject boundaries. A word
      --  frontier therefore finds a complete word at the very end of input.
      Found := Patterns.Find (State, "12 abc", "%f[%a]%a+%f[%A]");
      Assert (Found.Found and then Found.First = 3 and then Found.After = 6,
              "frontier at end of input");
   end Frontier_Boundaries;

   procedure Capture_Rollback (State : in out World) is
      Found : Patterns.Match_Result;
      Captures : Values.Vector := Owned_Values (State);
   begin
      --  Greedy expansion initially consumes too much. Failed alternatives
      --  must restore capture boundaries before trying the successful split.
      Found := Patterns.Find (State, "aaaab", "(a*)ab");
      Captures := Patterns.Capture_Values (State, "aaaab", Found);
      Assert (Captures (1).Reference.Bytes = "aaa", "greedy rollback");
   end Capture_Rollback;

   procedure Binary_Classes (State : in out World) is
      Text : constant String := "a" & Character'Val (0) & Character'Val (255);
      Found : Patterns.Match_Result;
   begin
      --  Byte strings retain embedded zero and high bytes. %z consumes zero;
      --  the following negated ASCII class consumes the high byte unchanged.
      Found := Patterns.Find (State, Text, "%z[^%a]");
      Assert (Found.Found and then Found.First = 1 and then Found.After = 3,
              "binary pattern payload");
   end Binary_Classes;

   procedure Position_Captures (State : in out World) is
      Found : Patterns.Match_Result;
      Captures : Values.Vector := Owned_Values (State);
   begin
      --  Empty parentheses yield one-based positions, not empty strings.
      --  The last position may legitimately be one byte beyond the subject.
      Found := Patterns.Find (State, "abc", "()abc()");
      Captures := Patterns.Capture_Values (State, "abc", Found);
      Assert (Captures (1).Integer_Data = 1, "initial position capture");
      Assert (Captures (2).Integer_Data = 4, "terminal position capture");
   end Position_Captures;

   procedure Malformed_Pattern (State : in out World) is
      Found : Patterns.Match_Result;
   begin
      --  A missing set delimiter is a catchable language error. It must not
      --  read beyond the pattern and become an Ada bounds exception.
      begin
         Found := Patterns.Find (State, "abc", "[abc");
         Assert (not Found.Found, "malformed set unexpectedly matched");
         Assert (False, "missing set delimiter accepted");
      exception
         when Language_Error => null;
      end;
   end Malformed_Pattern;

   procedure Pattern_Budget (State : in out World) is
      Found : Patterns.Match_Result;
   begin
      --  Backtracking is native work, but still consumes the execution
      --  budget. A deliberately tiny allowance must stop an expensive miss.
      State.Bounds.Instructions := 20;
      begin
         Found := Patterns.Find (State, "aaaaaaaaaaaa", "a*a*a*b");
         Assert (not Found.Found, "unexpected expensive match");
         Assert (False, "pattern bypassed instruction budget");
      exception
         when Language_Error =>
            Assert ((State.Current.Failure_Class = Host_Abort),
              "budget failure category");
      end;
   end Pattern_Budget;

   procedure Empty_Plain_Search (State : in out World) is
      Args, Result : Values.Vector := Owned_Values (State);
   begin
      --  Searching after the last byte is legal. Nonempty plain text misses,
      --  while the empty pattern denotes the terminal zero-width match.
      Args.Append (New_String (State, "abc"));
      Args.Append (New_String (State, "x"));
      Args.Append (Value'(Integer_Kind, 4));
      Result := Strings.Run (State, "find", Args);
      Assert (Result (1).Kind = Nil_Kind, "terminal nonempty search");
      Args.Replace_Element (2, New_String (State, ""));
      Result := Strings.Run (State, "find", Args);
      Assert (Result (1).Integer_Data = 4, "terminal empty start");
      Assert (Result (2).Integer_Data = 3, "terminal empty end");
   end Empty_Plain_Search;

   procedure Negative_Substring (State : in out World) is
      Args, Result : Values.Vector := Owned_Values (State);
   begin
      --  Negative positions count from the end without negating mininteger.
      --  Extreme negative bounds clip at the start instead of overflowing.
      Args.Append (New_String (State, "abcde"));
      Args.Append (Value'(Integer_Kind, Integer_Value'First));
      Args.Append (Value'(Integer_Kind, -2));
      Result := Strings.Run (State, "sub", Args);
      Assert (Result (1).Reference.Bytes = "abcd", "clipped substring");
   end Negative_Substring;

   procedure Huge_Empty_Repetition (State : in out World) is
      Args, Result : Values.Vector := Owned_Values (State);
   begin
      --  The mathematical output is empty even with maxinteger repetitions.
      --  This must finish immediately, with no gigantic loop or allocation.
      Args.Append (New_String (State, ""));
      Args.Append (Value'(Integer_Kind, Integer_Value'Last));
      Result := Strings.Run (State, "rep", Args);
      Assert (Result (1).Reference.Bytes = "", "empty repetition result");
   end Huge_Empty_Repetition;

   procedure Decimal_Rounding (State : in out World) is
   begin
      --  Exactly representable halves exercise nearest-even decimal rounding
      --  independently of the current Ada or C stream formatting defaults.
      Assert (Formats.Render (State, "%.0f", (Real_Kind, 2.5)) = "2",
              "even lower decimal tie");
      Assert (Formats.Render (State, "%.0f", (Real_Kind, 3.5)) = "4",
              "even upper decimal tie");
   end Decimal_Rounding;

   procedure Hexadecimal_Rounding (State : in out World) is
   begin
      --  At zero precision, tie parity includes the leading hexadecimal
      --  digit. Ignoring it incorrectly rounds 1.5 down to 1.
      begin
         Assert (Formats.Render (State, "%.0a", (Real_Kind, 1.5)) = "0x2p+0",
                 "hexadecimal leading digit tie");
      exception
         when Language_Error =>
            --  The pinned Windows configuration deliberately uses Lua's
            --  C89 hex formatter, which rejects every modifier.
            Assert (State.Current.Failure_Text =
              "modifiers for format '%a'/'%A' not implemented",
              "documented C89 hex format boundary");
      end;
      Assert (Formats.Render (State, "%a", (Real_Kind, -0.0)) = "-0x0p+0",
              "negative zero sign bit");
   end Hexadecimal_Rounding;

   procedure Unsigned_Formatting (State : in out World) is
   begin
      --  Unsigned formatting reinterprets all 64 bits rather than narrowing
      --  a negative integer or attempting an absolute value of mininteger.
      Assert (Formats.Render (State, "%u", (Integer_Kind, -1)) =
        "18446744073709551615", "unsigned decimal representation");
      Assert (Formats.Render (State, "%#x", (Integer_Kind, -1)) =
        "0xffffffffffffffff", "unsigned alternate hexadecimal");
   end Unsigned_Formatting;

   procedure Binary_Quoting (State : in out World) is
      Item : constant Value := New_String (State, Character'Val (0) & "9");
   begin
      --  A following digit requires a three-digit escape, otherwise loading
      --  the quoted text would merge it into the escape's decimal value.
      Assert (Formats.Render (State, "%q", Item) = '"' & "\0009" & '"',
              "unambiguous binary quoting");
   end Binary_Quoting;

   procedure Invalid_Format_Flags (State : in out World) is
      Result : Unbounded_String;
   begin
      --  Lua forbids numeric flags on strings even where printf accepts them.
      --  This protects argument checking from host formatting extensions.
      begin
         Result := To_Unbounded_String (Formats.Render
           (State, "%+s", New_String (State, "abc")));
         Assert (Length (Result) = 0, "invalid format produced text");
         Assert (False, "numeric string flag accepted");
      exception
         when Language_Error => null;
      end;
   end Invalid_Format_Flags;

   procedure Precision_Digit_Limit (State : in out World) is
      Result : Unbounded_String;
   begin
      --  The precision field accepts two digits, irrespective of their value.
      --  Three zero digits cannot evade the bound by keeping its value zero.
      begin
         Result := To_Unbounded_String (Formats.Render
           (State, "%.000d", (Integer_Kind, 1)));
         Assert (Length (Result) = 0, "overlong precision produced text");
         Assert (False, "three precision digits accepted");
      exception
         when Language_Error => null;
      end;
   end Precision_Digit_Limit;

   procedure Binary_String_Formatting (State : in out World) is
      Text : constant String := "a" & Character'Val (0) & "b";
      Item : constant Value := New_String (State, Text);
      Result : Unbounded_String;
   begin
      --  Plain %s is binary-safe. Adding any modifier selects Lua's checked
      --  C-style string formatting path, which rejects embedded zero bytes.
      Assert (Formats.Render (State, "%s", Item) = Text,
              "plain string formatting retains zero bytes");
      begin
         Result := To_Unbounded_String (Formats.Render (State, "%1s", Item));
         Assert (Length (Result) = 0, "binary modified string produced text");
         Assert (False, "modified binary string accepted");
      exception
         when Language_Error => null;
      end;
   end Binary_String_Formatting;

   procedure Empty_Match_Progression (State : in out World) is
      Activation : Frame_Access :=
        New_Frame (State);
      Result : Native_Action;
   begin
      --  The native continuation emits each byte between empty matches once.
      --  Three substitutions for two bytes also exercises the EOF match.
      Activation.Native_Name := To_Unbounded_String ("gsub");
      Activation.Native_Arguments.Append (New_String (State, "ab"));
      Activation.Native_Arguments.Append (New_String (State, ""));
      Activation.Native_Arguments.Append (New_String (State, "-"));
      loop
         Result := Pattern_Drivers.Advance (State, Activation);
         exit when Result.Kind = Finished;
         Assert (Result.Kind = Continue_Step, "unexpected string callback");
      end loop;
      Assert (Result.Results (1).Reference.Bytes = "-a-b-",
              "empty matches progress");
      Assert (Result.Results (2).Integer_Data = 3, "empty replacement count");
      Free_Frame (Activation);
   exception
      when others =>
         Free_Frame (Activation);
         raise;
   end Empty_Match_Progression;

   procedure Iterator_Persistence (State : in out World) is
      Creation : Frame_Access := New_Frame (State);
      Invocation : Frame_Access :=
        New_Frame (State);
      Created, Result : Native_Action;
   begin
      --  Each invocation has its own frame. Position state belongs to the
      --  native closure, so fresh frames advance the same iterator correctly.
      Creation.Native_Name := To_Unbounded_String ("gmatch");
      Creation.Native_Arguments.Append (New_String (State, "a b"));
      Creation.Native_Arguments.Append (New_String (State, "%a+"));
      Created := Pattern_Drivers.Advance (State, Creation);
      Invocation.Native_Name := To_Unbounded_String ("gmatch.iterator");
      Invocation.Native_Self := Created.Results (1).Reference;
      Result := Pattern_Drivers.Advance (State, Invocation);
      Assert (Result.Results (1).Reference.Bytes = "a", "first iterator item");
      Result := Pattern_Drivers.Advance (State, Invocation);
      Assert (Result.Results (1).Reference.Bytes = "b",
              "second iterator item");
      Result := Pattern_Drivers.Advance (State, Invocation);
      Assert (Result.Results.Is_Empty, "iterator exhaustion");
      Free_Frame (Creation);
      Free_Frame (Invocation);
   exception
      when others =>
         Free_Frame (Creation);
         Free_Frame (Invocation);
         raise;
   end Iterator_Persistence;

   procedure Formatting_Callback (State : in out World) is
      Activation : Frame_Access :=
        New_Frame (State);
      Result : Native_Action;
   begin
      --  Formatting must suspend before %s, request ordinary tostring, and
      --  resume into the following conversion without repeating that call.
      Activation.Native_Arguments.Append (New_String (State, "[%s] %d"));
      Activation.Native_Arguments.Append (New_Table (State));
      Activation.Native_Arguments.Append (Value'(Integer_Kind, 7));
      Result := Format_Drivers.Advance (State, Activation);
      Assert (Result.Kind = Invoke, "format requests tostring");
      Assert (Result.Function_Value.Reference.Native_Name = "base.tostring",
              "format uses normal tostring handler");
      Activation.Native_Results.Append (New_String (State, "value"));
      loop
         Result := Format_Drivers.Advance (State, Activation);
         exit when Result.Kind = Finished;
         Assert (Result.Kind = Continue_Step, "format repeated callback");
      end loop;
      Assert (Result.Results (1).Reference.Bytes = "[value] 7",
              "format resumed with callback result");
      Free_Frame (Activation);
   exception
      when others =>
         Free_Frame (Activation);
         raise;
   end Formatting_Callback;

   procedure Replacement_Roots (State : in out World) is
      Activation : Frame_Access :=
        New_Frame (State);
      Result : Native_Action;
   begin
      --  A Lua replacement can trigger collection before returning. Keep the
      --  whole match, captures, original arguments, and pending result rooted
      --  in the activation; neither helper locals nor action packets own them.
      Activation.Is_Native := True;
      Activation.Native_Name := To_Unbounded_String ("gsub");
      Activation.Native_Arguments.Append (New_String (State, "ab"));
      Activation.Native_Arguments.Append (New_String (State, "(a)"));
      Activation.Native_Arguments.Append (New_Native (State, "identity"));
      State.Current.Stack.Append (Activation);
      Result := Pattern_Drivers.Advance (State, Activation);
      Assert (Result.Kind = Invoke, "replacement requests callback");
      Activation.Native_Results.Append (New_String (State, "X"));
      Collect (State);
      Assert (Activation.Native_Captures (2).Reference.Bytes = "a",
              "whole match survives collection");
      loop
         Result := Pattern_Drivers.Advance (State, Activation);
         exit when Result.Kind = Finished;
         Assert (Result.Kind = Continue_Step, "unexpected second callback");
      end loop;
      Assert (Result.Results (1).Reference.Bytes = "Xb",
              "replacement result survives collection");
      State.Current.Stack.Clear;
      Free_Frame (Activation);
   exception
      when others =>
         State.Current.Stack.Clear;
         Free_Frame (Activation);
         raise;
   end Replacement_Roots;

   procedure Quoting_Budget (State : in out World) is
      Item : constant Value := New_String (State, String'(1 .. 64 => 'a'));
      Result : Unbounded_String;
   begin
      --  A short format may inspect a long argument. Native quoting must
      --  consume the byte budget even when none of those bytes need escaping.
      State.Bounds.Instructions := 16;
      begin
         Result := To_Unbounded_String (Formats.Render (State, "%q", Item));
         Assert (Length (Result) = 0, "unbudgeted quote produced text");
         Assert (False, "quote scan bypassed instruction budget");
      exception
         when Language_Error =>
            Assert ((State.Current.Failure_Class = Host_Abort),
              "quote resource diagnostic");
      end;
   end Quoting_Budget;

   procedure Iterator_Copy_Budget (State : in out World) is
      Creation : Frame_Access := New_Frame (State);
      Invocation : Frame_Access :=
        New_Frame (State);
      Created, Result : Native_Action;
   begin
      --  Each resumed iterator copies the retained subject before matching.
      --  A tiny remaining budget must reject that copy before advancing the
      --  iterator, rather than granting a free large copy for every match.
      Creation.Native_Name := To_Unbounded_String ("gmatch");
      Creation.Native_Arguments.Append
        (New_String (State, String'(1 .. 64 => 'a')));
      Creation.Native_Arguments.Append (New_String (State, "."));
      Created := Pattern_Drivers.Advance (State, Creation);
      Invocation.Native_Name := To_Unbounded_String ("gmatch.iterator");
      Invocation.Native_Self := Created.Results (1).Reference;
      State.Steps := 0;
      State.Bounds.Instructions := 16;
      begin
         Result := Pattern_Drivers.Advance (State, Invocation);
         Assert (Result.Results.Is_Empty, "unbudgeted iterator produced text");
         Assert (False, "iterator copy bypassed instruction budget");
      exception
         when Language_Error =>
            Assert ((State.Current.Failure_Class = Host_Abort),
              "iterator copy resource diagnostic");
            Assert (Invocation.Native_Self.Captures
              (3).Cell_Value.Integer_Data = 0,
                    "iterator position unchanged by failed copy");
      end;
      Free_Frame (Creation);
      Free_Frame (Invocation);
   exception
      when others =>
         Free_Frame (Creation);
         Free_Frame (Invocation);
         raise;
   end Iterator_Copy_Budget;

   procedure Replacement_Copy_Budget (State : in out World) is
      Activation : Frame_Access :=
        New_Frame (State);
      Result : Native_Action;
   begin
      --  A replacement step also obtains a whole-subject view. Account for
      --  that work before scanning or changing continuation progress state.
      Activation.Native_Name := To_Unbounded_String ("gsub");
      Activation.Native_Arguments.Append
        (New_String (State, String'(1 .. 64 => 'a')));
      Activation.Native_Arguments.Append (New_String (State, "."));
      Activation.Native_Arguments.Append (New_String (State, "-"));
      State.Bounds.Instructions := 16;
      begin
         Result := Pattern_Drivers.Advance (State, Activation);
         Assert (Result.Results.Is_Empty, "unbudgeted replacement output");
         Assert (False, "replacement copy bypassed instruction budget");
      exception
         when Language_Error =>
            Assert ((State.Current.Failure_Class = Host_Abort),
              "replacement copy resource diagnostic");
            Assert (Activation.Native_Stage = 0,
                    "replacement state unchanged by failed copy");
      end;
      Free_Frame (Activation);
   exception
      when others =>
         Free_Frame (Activation);
         raise;
   end Replacement_Copy_Budget;

   procedure Backreference_Comparison_Budget (State : in out World) is
      Subject : constant String := String'(1 .. 64 => 'a') & 'b';
      Found : Patterns.Match_Result;
   begin
      --  A greedy capture repeatedly shrinks and compares long equal prefixes
      --  before its anchored suffix fails. Counting only matcher transitions
      --  would finish under budget while leaving byte comparisons unbounded.
      State.Bounds.Instructions := 500;
      begin
         Found := Patterns.Find (State, Subject, "^(a*)%1$");
         Assert (not Found.Found, "unexpected anchored backreference match");
         Assert (False, "backreference comparisons bypassed native budget");
      exception
         when Language_Error =>
            Assert ((State.Current.Failure_Class = Host_Abort),
              "backreference resource diagnostic");
      end;
   end Backreference_Comparison_Budget;

   procedure MacOS_Subnormal_Formatting (State : in out World) is
      Smallest : constant Value := (Real_Kind, Real_Value'Succ (0.0));
   begin
      --  Inject macOS policy on every host. Darwin normalizes subnormals for
      --  both %a and %q, so the leading hexadecimal digit must be nonzero.
      Assert (Formats.Render
        (State, "%a",
         (Real_Kind, Lua.Numbers.Read ("1e-308").Real_Item),
         Host => "macos") =
          "0x1.cc359e067a348p-1024", "macOS subnormal hexadecimal");
      Assert (Formats.Render (State, "%q", Smallest, Host => "macos") =
        "0x1p-1074", "macOS smallest quoted subnormal");
   end MacOS_Subnormal_Formatting;

   procedure MacOS_Hexadecimal_Modifiers (State : in out World) is
   begin
      --  Normalizing like Windows does not imply C89's modifier restriction.
      --  macOS must still honor precision after normalization and rounding.
      Assert (Formats.Render
        (State, "%.3a",
         (Real_Kind, Lua.Numbers.Read ("1e-308").Real_Item),
         Host => "macos") =
          "0x1.cc3p-1024", "macOS subnormal precision");
      Assert (Formats.Render
        (State, "%.0a", (Real_Kind, 1.5), Host => "macos") = "0x2p+0",
        "macOS hexadecimal modifiers remain available");
   end MacOS_Hexadecimal_Modifiers;

   procedure Linux_Subnormal_Formatting (State : in out World) is
      Smallest : constant Value := (Real_Kind, Real_Value'Succ (0.0));
   begin
      --  Linux's minimum-normal exponent spelling remains a distinct policy.
      --  A fix for macOS must not silently normalize glibc-compatible output.
      Assert (Formats.Render
        (State, "%a",
         (Real_Kind, Lua.Numbers.Read ("1e-308").Real_Item),
         Host => "linux") =
          "0x0.730d67819e8d2p-1022", "Linux subnormal hexadecimal");
      Assert (Formats.Render (State, "%q", Smallest, Host => "linux") =
        "0x0.0000000000001p-1022", "Linux smallest quoted subnormal");
   end Linux_Subnormal_Formatting;

   procedure Backreference_Case is new Fixture (Captured_Backreference);
   procedure Balance_Case is new Fixture (Balanced_Nesting);
   procedure Frontier_Case is new Fixture (Frontier_Boundaries);
   procedure Rollback_Case is new Fixture (Capture_Rollback);
   procedure Binary_Case is new Fixture (Binary_Classes);
   procedure Position_Case is new Fixture (Position_Captures);
   procedure Malformed_Case is new Fixture (Malformed_Pattern);
   procedure Budget_Case is new Fixture (Pattern_Budget);
   procedure Search_Case is new Fixture (Empty_Plain_Search);
   procedure Substring_Case is new Fixture (Negative_Substring);
   procedure Repetition_Case is new Fixture (Huge_Empty_Repetition);
   procedure Decimal_Case is new Fixture (Decimal_Rounding);
   procedure Hexadecimal_Case is new Fixture (Hexadecimal_Rounding);
   procedure Unsigned_Case is new Fixture (Unsigned_Formatting);
   procedure Quoting_Case is new Fixture (Binary_Quoting);
   procedure Flags_Case is new Fixture (Invalid_Format_Flags);
   procedure Precision_Case is new Fixture (Precision_Digit_Limit);
   procedure Binary_Format_Case is new Fixture (Binary_String_Formatting);
   procedure Empty_Case is new Fixture (Empty_Match_Progression);
   procedure Iterator_Case is new Fixture (Iterator_Persistence);
   procedure Format_Callback_Case is new Fixture (Formatting_Callback);
   procedure Replacement_Roots_Case is new Fixture (Replacement_Roots);
   procedure Quoting_Budget_Case is new Fixture (Quoting_Budget);
   procedure Iterator_Budget_Case is new Fixture (Iterator_Copy_Budget);
   procedure Replacement_Budget_Case is new Fixture (Replacement_Copy_Budget);
   procedure Backreference_Budget_Case is new Fixture
     (Backreference_Comparison_Budget);
   procedure MacOS_Subnormal_Case is new Fixture
     (MacOS_Subnormal_Formatting);
   procedure MacOS_Modifiers_Case is new Fixture
     (MacOS_Hexadecimal_Modifiers);
   procedure Linux_Subnormal_Case is new Fixture
     (Linux_Subnormal_Formatting);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "string: backreference", Backreference_Case'Access);
      Test_Support.Add
        (Suite, "string: balanced nesting", Balance_Case'Access);
      Test_Support.Add
        (Suite, "string: frontier boundary", Frontier_Case'Access);
      Test_Support.Add
        (Suite, "string: capture rollback", Rollback_Case'Access);
      Test_Support.Add (Suite, "string: binary classes", Binary_Case'Access);
      Test_Support.Add
        (Suite, "string: position captures", Position_Case'Access);
      Test_Support.Add (Suite, "string: malformed set", Malformed_Case'Access);
      Test_Support.Add (Suite, "string: native budget", Budget_Case'Access);
      Test_Support.Add (Suite, "string: terminal search", Search_Case'Access);
      Test_Support.Add
        (Suite, "string: negative substring", Substring_Case'Access);
      Test_Support.Add
        (Suite, "string: empty repetition", Repetition_Case'Access);
      Test_Support.Add
        (Suite, "string: decimal rounding", Decimal_Case'Access);
      Test_Support.Add
        (Suite, "string: hex rounding", Hexadecimal_Case'Access);
      Test_Support.Add
        (Suite, "string: unsigned format", Unsigned_Case'Access);
      Test_Support.Add (Suite, "string: binary quoting", Quoting_Case'Access);
      Test_Support.Add (Suite, "string: invalid flags", Flags_Case'Access);
      Test_Support.Add
        (Suite, "string: precision digit limit", Precision_Case'Access);
      Test_Support.Add
        (Suite, "string: binary string format", Binary_Format_Case'Access);
      Test_Support.Add (Suite, "string: empty progression", Empty_Case'Access);
      Test_Support.Add (Suite, "string: iterator state", Iterator_Case'Access);
      Test_Support.Add
        (Suite, "string: formatting callback", Format_Callback_Case'Access);
      Test_Support.Add
        (Suite, "string: replacement roots", Replacement_Roots_Case'Access);
      Test_Support.Add
        (Suite, "string: quote byte budget", Quoting_Budget_Case'Access);
      Test_Support.Add
        (Suite, "string: iterator copy budget", Iterator_Budget_Case'Access);
      Test_Support.Add
        (Suite, "string: replacement copy budget",
         Replacement_Budget_Case'Access);
      Test_Support.Add
        (Suite, "string: backreference comparison budget",
         Backreference_Budget_Case'Access);
      Test_Support.Add
        (Suite, "string: macOS subnormal formatting",
         MacOS_Subnormal_Case'Access);
      Test_Support.Add
        (Suite, "string: macOS hexadecimal modifiers",
         MacOS_Modifiers_Case'Access);
      Test_Support.Add
        (Suite, "string: Linux subnormal formatting",
         Linux_Subnormal_Case'Access);
   end Register;
end Lua.String_Helper_Tests;
