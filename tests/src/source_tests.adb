with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sources; use Lua.Sources;
with Test_Support;

package body Source_Tests is
   BOM : constant String := Character'Val (16#EF#) &
     Character'Val (16#BB#) & Character'Val (16#BF#);
   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);
   procedure Empty;
   procedure Empty_Zero_Bound;
   procedure Raw_Bytes;
   procedure Leading_BOM;
   procedure Partial_BOM;
   procedure Interpreter_Line;
   procedure CRLF_Preserved;
   procedure Lone_CR_Ignored;
   procedure Interior_CR_With_CRLF;
   procedure No_Final_Newline;
   procedure BOM_Interpreter_Line;
   procedure Nonleading_Hash;
   procedure Shifted_Bounds;
   procedure Upper_Index_Bound;
   procedure Inspection_Empty_Bounds;
   procedure Inspection_Composition;
   procedure Inspection_Raw_Prefixes;
   procedure Inspection_Upper_Bounds;
   procedure Binary_Interpreter_Line;
   procedure Binary_BOM_CRLF;
   procedure Binary_LFCR_Not_Skipped;

   procedure Empty is
      --  An empty file has no first byte. It must stay empty rather than
      --  failing a constrained index conversion or creating a newline.
   begin
      Assert (File_Preamble ("") = "", "empty source changed");
   end Empty;

   procedure Empty_Zero_Bound is
      Source : constant String (0 .. -1) := "";
   begin
      --  Null String bounds need not lie in Positive. This specifically
      --  protects the pre-index empty fast path required by Ada callers.
      Assert (File_Preamble (Source)'Length = 0, "null bounds rejected");
   end Empty_Zero_Bound;

   procedure Raw_Bytes is
      Source : constant String := "return '" & Character'Val (0) &
        Character'Val (255) & "'" & CR & LF;
   begin
      --  Only the recognized preamble is transformed. Literal NUL, high
      --  bytes, and the body's original line endings must remain exact.
      Assert (File_Preamble (Source) = Source, "body bytes changed");
   end Raw_Bytes;

   procedure Leading_BOM is
      --  Strip exactly one complete initial UTF-8 marker. A second marker
      --  belongs to the source and must be diagnosed by the lexer later.
   begin
      Assert (File_Preamble (BOM & "return 1") = "return 1", "BOM kept");
      Assert (File_Preamble (BOM & BOM) = BOM, "second BOM stripped");
      Assert (File_Preamble (BOM) = "", "BOM-only file not empty");
   end Leading_BOM;

   procedure Partial_BOM is
      Source : constant String := BOM (1 .. 2);
   begin
      --  A truncated prefix is not a marker. Preserve it for the lexical
      --  diagnostic instead of silently accepting malformed input bytes.
      Assert (File_Preamble (Source) = Source, "partial BOM discarded");
   end Partial_BOM;

   procedure Interpreter_Line is
      --  Blank the line's bytes rather than deleting its newline. This
      --  keeps the subsequent return on line two for frontend diagnostics.
   begin
      Assert (File_Preamble ("#!/bin/lua" & LF & "return 1") =
              "          " & LF & "return 1", "interpreter line changed");
   end Interpreter_Line;

   procedure CRLF_Preserved is
      --  Both bytes of a CRLF remain present; the lexer owns newline
      --  normalization, so loader policy must not perform it a second time.
   begin
      Assert (File_Preamble ("#lua" & CR & LF & "x") =
              "    " & CR & LF & "x", "CRLF normalized by loader");
   end CRLF_Preserved;

   procedure Lone_CR_Ignored is
   begin
      --  Pinned skipcomment ends only at LF. The lone CR belongs to the
      --  ignored interpreter line and cannot expose following Lua tokens.
      Assert (File_Preamble ("#lua" & CR & "x" & LF & "return 1") =
                "      " & LF & "return 1",
              "lone CR exposed interpreter-line bytes as Lua code");
   end Lone_CR_Ignored;

   procedure Interior_CR_With_CRLF is
   begin
      --  Ignore an interior lone CR while preserving the terminal CRLF
      --  bytes promised by the existing pure source preparation interface.
      Assert (File_Preamble ("#a" & CR & "x" & CR & LF & "return 1") =
                "    " & CR & LF & "return 1",
              "interior CR or terminal CRLF prepared incorrectly");
   end Interior_CR_With_CRLF;

   procedure No_Final_Newline is
      --  A file consisting only of an interpreter line produces spaces
      --  without inventing a newline or inspecting past its final byte.
   begin
      Assert (File_Preamble ("#lua") = "    ", "line end invented");
   end No_Final_Newline;

   procedure BOM_Interpreter_Line is
      --  Interpreter recognition begins after the optional BOM. Both
      --  policies compose while retaining all bytes of the real Lua body.
   begin
      Assert (File_Preamble (BOM & "#lua" & LF & "x") =
              "    " & LF & "x", "BOM interpreter composition");
   end BOM_Interpreter_Line;

   procedure Nonleading_Hash is
      Source : constant String := " #lua" & LF & "#body";
   begin
      --  A leading space disables interpreter recognition. Hash tokens
      --  elsewhere belong to ordinary Lua source and are never stripped.
      Assert (File_Preamble (Source) = Source, "nonleading hash blanked");
   end Nonleading_Hash;

   procedure Shifted_Bounds is
      Source : constant String (17 .. 24) := "#lua" & LF & "x=1";
   begin
      --  Ada slices may start above one; policy offsets must be relative
      --  to Source'First, never absolute indices into an assumed buffer.
      Assert (File_Preamble (Source) = "    " & LF & "x=1",
              "shifted source bounds rejected");
   end Shifted_Bounds;

   procedure Upper_Index_Bound is
      Hash : constant String (Positive'Last .. Positive'Last) := "#";
      Marker : constant String (Positive'Last - 2 .. Positive'Last) := BOM;
   begin
      --  Advancing past the final index would overflow even a tiny source.
      --  The scan and BOM-only fast path avoid computing that sentinel.
      Assert (File_Preamble (Hash) = " ", "final-index scan overflow");
      Assert (File_Preamble (Marker) = "", "final-index BOM overflow");
   end Upper_Index_Bound;

   procedure Inspection_Empty_Bounds is
      Source : constant String (0 .. -1) := "";
      Info : constant File_Preamble_Info := Inspect_File_Preamble (Source);
   begin
      --  Inspection is usable before any allocation. An empty input with
      --  non-Positive bounds must produce no transformation or index access.
      Assert (Info.Skipped_Bytes = 0 and Info.Blanked_Bytes = 0,
              "empty inspection counts");
   end Inspection_Empty_Bounds;

   procedure Inspection_Composition is
      Source : constant String (17 .. 28) := BOM & "#lua" & CR & LF & "x=1";
      Info : constant File_Preamble_Info := Inspect_File_Preamble (Source);
   begin
      --  Counts are relative bytes: a BOM followed by a shebang with CRLF
      --  preserves both newline bytes and does not depend on the lower bound.
      Assert (Info.Skipped_Bytes = 3 and Info.Blanked_Bytes = 4,
              "relative composite preamble counts");
      Assert (File_Preamble (Source) = "    " & CR & LF & "x=1",
              "copying wrapper shares inspection policy");
   end Inspection_Composition;

   procedure Inspection_Raw_Prefixes is
      Partial : constant File_Preamble_Info :=
        Inspect_File_Preamble (BOM (1 .. 2));
      Nonleading : constant File_Preamble_Info :=
        Inspect_File_Preamble (" #lua");
   begin
      --  These similar-looking prefixes are source bytes, not preambles.
      --  Neither inspection nor its managed consumer may silently strip them.
      Assert (Partial.Skipped_Bytes = 0 and Partial.Blanked_Bytes = 0,
              "partial marker not recognized");
      Assert (Nonleading.Skipped_Bytes = 0 and Nonleading.Blanked_Bytes = 0,
              "nonleading hash not recognized");
   end Inspection_Raw_Prefixes;

   procedure Inspection_Upper_Bounds is
      Hash : constant String (Positive'Last .. Positive'Last) := "#";
      Marker : constant String (Positive'Last - 2 .. Positive'Last) := BOM;
      Hash_Info : constant File_Preamble_Info := Inspect_File_Preamble (Hash);
      BOM_Info : constant File_Preamble_Info := Inspect_File_Preamble (Marker);
   begin
      --  Even a tiny source can end at Integer'Last. Relative loops must not
      --  compute an overflowing index one past the byte being inspected.
      Assert (Hash_Info.Blanked_Bytes = 1, "upper-bound hash inspection");
      Assert (BOM_Info.Skipped_Bytes = 3 and BOM_Info.Blanked_Bytes = 0,
              "upper-bound BOM-only inspection");
   end Inspection_Upper_Bounds;

   procedure Binary_Interpreter_Line is
      Bytes : constant String := Character'Val (27) & "Lua" &
        Character'Val (0) & Character'Val (255);
   begin
      --  A native chunk must start at its signature for absolute alignment.
      --  Remove the interpreter line and LF rather than inserting whitespace.
      Assert (File_Preamble ("#lua" & LF & Bytes) = Bytes,
              "binary interpreter prefix retained alignment bytes");
   end Binary_Interpreter_Line;

   procedure Binary_BOM_CRLF is
      Bytes : constant String := Character'Val (27) & "Lua" &
        Character'Val (0);
      Info : constant File_Preamble_Info :=
        Inspect_File_Preamble (BOM & "#lua" & CR & LF & Bytes);
   begin
      --  Compose BOM removal with the binary reopen's LF-based line skip.
      --  Every byte after the signature, including NUL, remains unchanged.
      Assert (Info.Skipped_Bytes = 9 and then Info.Blanked_Bytes = 0,
              "binary preamble inspection");
      Assert (File_Preamble (BOM & "#lua" & CR & LF & Bytes) = Bytes,
              "binary BOM/CRLF composition");
   end Binary_BOM_CRLF;

   procedure Binary_LFCR_Not_Skipped is
      Bytes : constant String := Character'Val (27) & "Lua";
   begin
      --  Pinned skipcomment consumes through LF. A CR after that byte is the
      --  first text input; a later signature must not be promoted to binary.
      Assert (File_Preamble ("#lua" & LF & CR & Bytes) =
                "    " & LF & CR & Bytes,
              "nonleading binary signature incorrectly promoted");
   end Binary_LFCR_Not_Skipped;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin      Test_Support.Add (Suite, "source binary interpreter prefix",
                        Binary_Interpreter_Line'Access);
      Test_Support.Add (Suite, "source binary BOM/CRLF prefix",
                        Binary_BOM_CRLF'Access);
      Test_Support.Add (Suite, "source binary LFCR boundary",
                        Binary_LFCR_Not_Skipped'Access);

      Test_Support.Add (Suite, "source empty", Empty'Access);
      Test_Support.Add (Suite, "source null zero bounds",
                        Empty_Zero_Bound'Access);
      Test_Support.Add (Suite, "source raw bytes", Raw_Bytes'Access);
      Test_Support.Add (Suite, "source leading BOM", Leading_BOM'Access);
      Test_Support.Add (Suite, "source partial BOM", Partial_BOM'Access);
      Test_Support.Add (Suite, "source interpreter line",
                        Interpreter_Line'Access);
      Test_Support.Add (Suite, "source CRLF preservation",
                        CRLF_Preserved'Access);
      Test_Support.Add (Suite, "source interpreter lone CR ignored",
                        Lone_CR_Ignored'Access);
      Test_Support.Add (Suite, "source interior CR and terminal CRLF",
                        Interior_CR_With_CRLF'Access);
      Test_Support.Add (Suite, "source no final newline",
                        No_Final_Newline'Access);
      Test_Support.Add (Suite, "source BOM interpreter composition",
                        BOM_Interpreter_Line'Access);
      Test_Support.Add (Suite, "source nonleading hash",
                        Nonleading_Hash'Access);
      Test_Support.Add (Suite, "source shifted bounds", Shifted_Bounds'Access);
      Test_Support.Add (Suite, "source upper index bound",
                        Upper_Index_Bound'Access);
      Test_Support.Add (Suite, "source inspect empty bounds",
                        Inspection_Empty_Bounds'Access);
      Test_Support.Add (Suite, "source inspect composition",
                        Inspection_Composition'Access);
      Test_Support.Add (Suite, "source inspect raw prefixes",
                        Inspection_Raw_Prefixes'Access);
      Test_Support.Add (Suite, "source inspect upper bounds",
                        Inspection_Upper_Bounds'Access);
   end Register;
end Source_Tests;
