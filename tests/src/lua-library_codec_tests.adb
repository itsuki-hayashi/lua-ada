with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Packing;
with Lua.Engine.Unicode;
with Test_Support;

package body Lua.Library_Codec_Tests is
   use type Integer_Value;
   use type Real_Value;
   procedure Integer_Endianness;
   procedure Wide_Sign_Extension;
   procedure Virtual_Size;
   procedure Semantic_Size_Overflow;
   procedure Alignment_Padding;
   procedure Negative_Zero;
   procedure Invalid_UTF8_Position;
   procedure Extended_UTF8;
   procedure Offset_Two_Results;
   procedure Offset_Continuation_Error;
   procedure Empty_Encoding;
   procedure Iterator_Exhaustion;
   procedure Single_Precision_Rounding;
   procedure Single_Precision_Subnormal;
   procedure Offset_ASCII_Boundary;
   procedure Overlong_Encoding;
   procedure Native_Work_Quota;
   procedure Iterator_Subject_Copy_Quota;
   procedure With_State (Action : access procedure (State : in out World));

   procedure With_State (Action : access procedure (State : in out World)) is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Action (State);
      exception
         when others =>
            Finalize (State);
            raise;
      end;
      Finalize (State);
   end With_State;

   procedure Integer_Endianness is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  Explicit endian changes apply independently to adjacent fields.
         Args.Append (New_String (State, ">i2 <i2"));
         Args.Append (Value'(Integer_Kind, 10));
         Args.Append (Value'(Integer_Kind, 20));
         Result := Packing.Run (State, "pack", Args);
         Assert (Result (1).Reference.Bytes =
           Character'Val (0) & Character'Val (10) &
           Character'Val (20) & Character'Val (0), "mixed endian bytes");
      end Check;
   begin
      With_State (Check'Access);
   end Integer_Endianness;

   procedure Wide_Sign_Extension is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Packed, Result : Values.Vector;
      begin
         --  A 16-byte integer extends the 64-bit sign and decodes without
         --  narrowing or overflowing an Ada machine integer.
         Args.Append (New_String (State, ">i16"));
         Args.Append (Value'(Integer_Kind, -1));
         Packed := Packing.Run (State, "pack", Args);
         Assert (Packed (1).Reference.Bytes =
           String'(1 .. 16 => Character'Val (255)), "wide negative bytes");
         Args.Replace_Element (2, Packed (1));
         Result := Packing.Run (State, "unpack", Args);
         Assert (Result (1).Integer_Data = -1, "wide negative value");
         Assert (Result (2).Integer_Data = 17, "unpack next position");
      end Check;
   begin
      With_State (Check'Access);
   end Wide_Sign_Extension;

   procedure Virtual_Size is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  packsize is mathematical. A size near maxinteger is valid even
         --  when it far exceeds Natural and the string allocation quota.
         Args.Append (New_String (State, "c" & Ada.Strings.Fixed.Trim
           (Integer_Value'(Integer_Value'Last - 9)'Image, Ada.Strings.Both)));
         Result := Packing.Run (State, "packsize", Args);
         Assert (Result (1).Integer_Data = Integer_Value'Last - 9,
                 "virtual size is not an allocation");
      end Check;
   begin
      With_State (Check'Access);
   end Virtual_Size;

   procedure Semantic_Size_Overflow is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  Invalid total-size arithmetic must raise a catchable language
         --  error before any attempt to allocate the enormous final field.
         Args.Append (New_String (State, "xxxxxxxxxxc" &
           Ada.Strings.Fixed.Trim
             (Integer_Value'(Integer_Value'Last - 9)'Image,
              Ada.Strings.Both)));
         Args.Append (New_String (State, ""));
         begin
            Result := Packing.Run (State, "pack", Args);
            Assert (Result.Is_Empty and then False, "overflow must fail");
         exception
            when Language_Error =>
               Assert (not (State.Current.Failure_Class = Host_Abort),
                       "semantic overflow is catchable");
               Assert (Ada.Strings.Fixed.Index
                 (To_String (State.Current.Failure_Text), "too long") /= 0,
                       "overflow explains the format result");
         end;
      end Check;
   begin
      With_State (Check'Access);
   end Semantic_Size_Overflow;

   procedure Alignment_Padding is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  X requests only alignment from its next option; it consumes no
         --  input argument and contributes no data bytes for that option.
         Args.Append (New_String (State, "!8 xXi8"));
         Result := Packing.Run (State, "packsize", Args);
         Assert (Result (1).Integer_Data = 8, "explicit alignment padding");
      end Check;
   begin
      With_State (Check'Access);
   end Alignment_Padding;

   procedure Negative_Zero is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  Floating packing retains the IEEE sign of zero, unlike an
         --  integer-oriented numerical conversion through zero.
         Args.Append (New_String (State, ">f"));
         Args.Append (Value'(Real_Kind, -0.0));
         Result := Packing.Run (State, "pack", Args);
         Assert (Result (1).Reference.Bytes =
           Character'Val (128) & String'(1 .. 3 => Character'Val (0)),
                 "binary32 negative zero sign");
      end Check;
   begin
      With_State (Check'Access);
   end Negative_Zero;

   procedure Invalid_UTF8_Position is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  len returns nil plus the failing byte position rather than
         --  throwing a language error for an invalid input sequence.
         Args.Append (New_String (State, "abc" & Character'Val (255)));
         Result := Unicode.Run (State, "len", Args);
         Assert (Result (1).Kind = Nil_Kind, "invalid UTF-8 length is nil");
         Assert (Result (2).Integer_Data = 4, "failing byte is one-based");
      end Check;
   begin
      With_State (Check'Access);
   end Invalid_UTF8_Position;

   procedure Extended_UTF8 is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Encoded, Result : Values.Vector;
      begin
         --  Lua's lax mode accepts the full extended 31-bit encoding; the
         --  same bytes are rejected by strict Unicode scalar decoding.
         Args.Append (Value'(Integer_Kind, 16#7FFF_FFFF#));
         Encoded := Unicode.Run (State, "char", Args);
         Args.Clear;
         Args.Append (Encoded (1));
         Args.Append (Value'(Integer_Kind, 1));
         Args.Append (Value'(Integer_Kind, 1));
         Args.Append (Value'(Boolean_Kind, True));
         Result := Unicode.Run (State, "codepoint", Args);
         Assert (Result (1).Integer_Data = 16#7FFF_FFFF#,
                 "extended scalar preserved");
         Args.Clear;
         Args.Append (Encoded (1));
         Result := Unicode.Run (State, "len", Args);
         Assert (Result (1).Kind = Nil_Kind, "strict limit rejects extension");
      end Check;
   begin
      With_State (Check'Access);
   end Extended_UTF8;

   procedure Offset_Two_Results is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  Lua 5.5 returns both ends of the selected character, even when
         --  the initial position lies within its continuation bytes.
         Args.Append (New_String (State, Character'Val (16#C2#) &
                                 Character'Val (16#A0#)));
         Args.Append (Value'(Integer_Kind, 0));
         Args.Append (Value'(Integer_Kind, 2));
         Result := Unicode.Run (State, "offset", Args);
         Assert (Result (1).Integer_Data = 1, "character starts at lead byte");
         Assert (Result (2).Integer_Data = 2,
                 "character ends at continuation");
      end Check;
   begin
      With_State (Check'Access);
   end Offset_Two_Results;

   procedure Offset_Continuation_Error is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  Nonzero offsets cannot start within a continuation sequence.
         Args.Append (New_String (State, Character'Val (16#C2#) &
                                 Character'Val (16#A0#)));
         Args.Append (Value'(Integer_Kind, 1));
         Args.Append (Value'(Integer_Kind, 2));
         begin
            Result := Unicode.Run (State, "offset", Args);
            Assert (Result.Is_Empty and then False,
                    "continuation start must fail");
         exception
            when Language_Error =>
               Assert (not (State.Current.Failure_Class = Host_Abort),
                 "ordinary invalid position");
         end;
      end Check;
   begin
      With_State (Check'Access);
   end Offset_Continuation_Error;

   procedure Empty_Encoding is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  An empty codepoint list produces a real empty byte string.
         Result := Unicode.Run (State, "char", Args);
         Assert (Result (1).Kind = String_Kind, "empty result type");
         Assert (Result (1).Reference.Bytes = "", "empty encoded payload");
      end Check;
   begin
      With_State (Check'Access);
   end Empty_Encoding;

   procedure Iterator_Exhaustion is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  A negative iterator control is interpreted as an exhausted
         --  unsigned position, not narrowed to an Ada index.
         Args.Append (New_String (State, "abc"));
         Args.Append (Value'(Integer_Kind, Integer_Value'First));
         Result := Unicode.Run (State, "step", Args);
         Assert (Result.Is_Empty, "negative control ends iteration");
      end Check;
   begin
      With_State (Check'Access);
   end Iterator_Exhaustion;

   procedure Single_Precision_Rounding is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  Halfway binary64 inputs distinguish ties-to-even from truncation
         --  and ties-away rounding during binary32 packing.
         Args.Append (New_String (State, ">f"));
         Args.Append (Value'(Real_Kind, 1.0 + 2.0 ** (-24)));
         Result := Packing.Run (State, "pack", Args);
         Assert (Result (1).Reference.Bytes =
           Character'Val (16#3F#) & Character'Val (16#80#) &
           String'(1 .. 2 => Character'Val (0)), "even lower significand");
         Args.Replace_Element
           (2, Value'(Real_Kind, 1.0 + 3.0 * 2.0 ** (-24)));
         Result := Packing.Run (State, "pack", Args);
         Assert (Result (1).Reference.Bytes =
           Character'Val (16#3F#) & Character'Val (16#80#) &
           Character'Val (0) & Character'Val (2), "even upper significand");
      end Check;
   begin
      With_State (Check'Access);
   end Single_Precision_Rounding;

   procedure Single_Precision_Subnormal is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Packed, Result : Values.Vector;
      begin
         --  The smallest binary32 subnormal survives both explicit encoding
         --  and decoding without entering a constrained Ada float subtype.
         Args.Append (New_String (State, ">f"));
         Args.Append (Value'(Real_Kind, 2.0 ** (-149)));
         Packed := Packing.Run (State, "pack", Args);
         Assert (Packed (1).Reference.Bytes =
           String'(1 .. 3 => Character'Val (0)) & Character'Val (1),
                 "smallest binary32 subnormal bytes");
         Args.Replace_Element (2, Packed (1));
         Result := Packing.Run (State, "unpack", Args);
         Assert (Result (1).Real_Data = 2.0 ** (-149),
                 "smallest binary32 subnormal value");
      end Check;
   begin
      With_State (Check'Access);
   end Single_Precision_Subnormal;

   procedure Offset_ASCII_Boundary is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  offset is a byte-boundary operation, not a validating decoder.
         --  An ASCII byte ends at itself even before an orphan continuation.
         Args.Append (New_String (State, "a" & Character'Val (16#80#)));
         Args.Append (Value'(Integer_Kind, 1));
         Result := Unicode.Run (State, "offset", Args);
         Assert (Result (1).Integer_Data = 1, "ASCII starting byte");
         Assert (Result (2).Integer_Data = 1, "ASCII ending byte");
      end Check;
   begin
      With_State (Check'Access);
   end Offset_ASCII_Boundary;

   procedure Overlong_Encoding is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  Lax mode extends the scalar range; it never permits an overlong
         --  representation. C0 80 must fail even with the lax flag enabled.
         Args.Append (New_String (State, Character'Val (16#C0#) &
                                 Character'Val (16#80#)));
         Args.Append (Value'(Integer_Kind, 1));
         Args.Append (Value'(Integer_Kind, -1));
         Args.Append (Value'(Boolean_Kind, True));
         Result := Unicode.Run (State, "len", Args);
         Assert (Result (1).Kind = Nil_Kind, "overlong lax input rejected");
         Assert (Result (2).Integer_Data = 1, "overlong failure position");
      end Check;
   begin
      With_State (Check'Access);
   end Overlong_Encoding;

   procedure Native_Work_Quota is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  Bulk fixed-string padding consumes the same shared work budget
         --  as VM instructions. A native helper cannot bypass exhaustion.
         Args.Append (New_String (State, "c20"));
         Args.Append (New_String (State, ""));
         State.Bounds.Instructions := 10;
         State.Steps := 0;
         begin
            Result := Packing.Run (State, "pack", Args);
            Assert (Result.Is_Empty and then False,
                    "native padding must consume work budget");
         exception
            when Language_Error =>
               Assert ((State.Current.Failure_Class = Host_Abort),
                 "native quota is resource failure");
         end;
      end Check;
   begin
      With_State (Check'Access);
   end Native_Work_Quota;

   procedure Iterator_Subject_Copy_Quota is
      procedure Check (State : in out World);
      procedure Check (State : in out World) is
         Args, Result : Values.Vector;
      begin
         --  Each iterator step currently materializes the whole retained
         --  subject before decoding one character. A budget which permits one
         --  64-byte copy but not two must therefore stop the second step.
         --  This protects against quadratic copying hidden behind apparently
         --  constant-cost native calls and keeps exhaustion structured.
         Args.Append (New_String (State, String'(1 .. 64 => 'a')));
         Args.Append (Value'(Integer_Kind, 0));
         State.Bounds.Instructions := 80;
         State.Steps := 0;
         Result := Unicode.Run (State, "step", Args);
         Assert (Result (1).Integer_Data = 1, "first iterator position");
         Assert (Result (2).Integer_Data = Character'Pos ('a'),
                 "first decoded codepoint");
         Assert (State.Steps = 65, "subject copy plus decoded byte charged");
         Args.Replace_Element (2, Result (1));
         begin
            Result := Unicode.Run (State, "step", Args);
            Assert (Result.Is_Empty and then False,
                    "repeated subject copy must exhaust shared budget");
         exception
            when Language_Error =>
               Assert ((State.Current.Failure_Class = Host_Abort),
                       "iterator copy quota is resource failure");
               Assert (State.Steps = 65,
                       "second copy fails before materialization");
         end;
      end Check;
   begin
      With_State (Check'Access);
   end Iterator_Subject_Copy_Quota;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "codec: integer endianness", Integer_Endianness'Access);
      Test_Support.Add
        (Suite, "codec: wide sign extension", Wide_Sign_Extension'Access);
      Test_Support.Add (Suite, "codec: virtual size", Virtual_Size'Access);
      Test_Support.Add
        (Suite, "codec: semantic size overflow",
         Semantic_Size_Overflow'Access);
      Test_Support.Add
        (Suite, "codec: alignment padding", Alignment_Padding'Access);
      Test_Support.Add (Suite, "codec: negative zero", Negative_Zero'Access);
      Test_Support.Add
        (Suite, "codec: invalid UTF-8 position", Invalid_UTF8_Position'Access);
      Test_Support.Add
        (Suite, "codec: extended UTF-8", Extended_UTF8'Access);
      Test_Support.Add
        (Suite, "codec: offset two results", Offset_Two_Results'Access);
      Test_Support.Add
        (Suite, "codec: continuation error", Offset_Continuation_Error'Access);
      Test_Support.Add (Suite, "codec: empty encoding", Empty_Encoding'Access);
      Test_Support.Add
        (Suite, "codec: iterator exhaustion", Iterator_Exhaustion'Access);
      Test_Support.Add
        (Suite, "codec: binary32 rounding", Single_Precision_Rounding'Access);
      Test_Support.Add
        (Suite, "codec: binary32 subnormal",
         Single_Precision_Subnormal'Access);
      Test_Support.Add
        (Suite, "codec: ASCII offset boundary", Offset_ASCII_Boundary'Access);
      Test_Support.Add
        (Suite, "codec: overlong UTF-8", Overlong_Encoding'Access);
      Test_Support.Add
        (Suite, "codec: native work quota", Native_Work_Quota'Access);
      Test_Support.Add
        (Suite, "codec: iterator subject copy quota",
         Iterator_Subject_Copy_Quota'Access);
   end Register;
end Lua.Library_Codec_Tests;
