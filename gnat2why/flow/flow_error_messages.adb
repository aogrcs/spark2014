------------------------------------------------------------------------------
--                                                                          --
--                            GNAT2WHY COMPONENTS                           --
--                                                                          --
--                  F L O W _ E R R O R _ M E S S A G E S                   --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                  Copyright (C) 2013-2015, Altran UK Limited              --
--                  Copyright (C) 2013-2015, AdaCore                        --
--                                                                          --
-- gnat2why is  free  software;  you can redistribute  it and/or  modify it --
-- under terms of the  GNU General Public License as published  by the Free --
-- Software  Foundation;  either version 3,  or (at your option)  any later --
-- version.  gnat2why is distributed  in the hope that  it will be  useful, --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of  MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public License  distributed with  gnat2why;  see file COPYING3. --
-- If not,  go to  http://www.gnu.org/licenses  for a complete  copy of the --
-- license.                                                                 --
--                                                                          --
------------------------------------------------------------------------------

with Ada.Strings;                use Ada.Strings;
with Ada.Strings.Unbounded;      use Ada.Strings.Unbounded;
with Assumption_Types;           use Assumption_Types;
with Atree;                      use Atree;
with Common_Containers;          use Common_Containers;
with Csets;                      use Csets;
with Einfo;                      use Einfo;
with Errout;                     use Errout;
with Erroutc;                    use Erroutc;
with Flow_Utility;               use Flow_Utility;
with Gnat2Why.Annotate;          use Gnat2Why.Annotate;
with Gnat2Why.Assumptions;       use Gnat2Why.Assumptions;
with Gnat2Why_Args;              use Gnat2Why_Args;
with GNATCOLL.Utils;             use GNATCOLL.Utils;
with GNAT;                       use GNAT;
with GNAT.String_Split;
with Namet;                      use Namet;
with Sinfo;                      use Sinfo;
with Sinput;                     use Sinput;
with SPARK_Util;                 use SPARK_Util;
with Stringt;                    use Stringt;

package body Flow_Error_Messages is

   Flow_Msgs_Set : Unbounded_String_Sets.Set;
   --  This set will contain flow related messages. It is used so as
   --  to not emit duplicate messages.

   function Msg_Kind_To_String (Kind : Msg_Kind) return String;
   --  Transform the msg kind into a string, for the JSON output.

   type Message_Id is new Integer;
   --  type used to identify a message issued by gnat2why

   function Compute_Message
     (Msg  : String;
      N    : Node_Id;
      F1   : Flow_Id := Null_Flow_Id;
      F2   : Flow_Id := Null_Flow_Id;
      F3   : Flow_Id := Null_Flow_Id)
      return String with
      Pre => (if Present (F2) then Present (F1)) and then
             (if Present (F3) then Present (F2));
   --  This function:
   --    * adds more precise location for generics and inlining
   --    * substitutes flow nodes

   function Compute_Sloc
     (N           : Node_Id;
      Place_First : Boolean := False)
      return Source_Ptr;
   --  function to compute a better sloc for reporting of results than the Ada
   --  Node. This takes into account generics.
   --  @param N the node for which we compute the sloc
   --  @param Place_First set this boolean to true to obtain placement at the
   --                     first sloc of the node, instead of the topmost node
   --  @return a sloc

   procedure Add_Json_Msg
     (Suppr       : String_Id;
      Tag         : String;
      Kind        : Msg_Kind;
      Slc         : Source_Ptr;
      Msg_List    : in out GNATCOLL.JSON.JSON_Array;
      E           : Entity_Id;
      Msg_Id      : Message_Id;
      Tracefile   : String := "";
      Cntexmp     : JSON_Value := GNATCOLL.JSON.Create_Object;
      VC_File     : String := "";
      How_Proved  : String := "";
      Stats       : JSON_Value := GNATCOLL.JSON.Create_Object;
      Editor_Cmd  : String := "");

   function Warning_Is_Suppressed
     (N   : Node_Id;
      Msg : String;
      F1  : Flow_Id := Null_Flow_Id;
      F2  : Flow_Id := Null_Flow_Id;
      F3  : Flow_Id := Null_Flow_Id)
     return String_Id;
   --  Check if the warning for the given node, message and flow id is
   --  suppressed. If the function returns No_String, the warning is not
   --  suppressed. If it returns Null_String_Id the warning is suppressed,
   --  but no reason has been given. Otherwise, the String_Id of the reason
   --  is provided.

   function Print_Regular_Msg
     (Msg  : String;
      Slc  : Source_Ptr;
      Kind : Msg_Kind;
      Continuation : Boolean := False) return Message_Id;
   --  Print a regular error, warning or info message using the frontend
   --  mechanism. Return an Id which can be used to identify this message.

   Flow_Msgs : GNATCOLL.JSON.JSON_Array;
   --  This will hold all of the emitted flow messages in JSON format.

   Proof_Msgs : GNATCOLL.JSON.JSON_Array;

   use type Ada.Containers.Count_Type;
   use type Flow_Graphs.Vertex_Id;
   use type Flow_Id_Sets.Set;

   function Escape (S : String) return String;
   --  Escape any special characters used in the error message (for
   --  example transforms "=>" into "='>" as > is a special insertion
   --  character. We also escape capital letters.

   function Substitute
     (S    : Unbounded_String;
      F    : Flow_Id;
      Flag : Source_Ptr)
      return Unbounded_String;
   --  Find the first '&' or '%' and substitute with the given flow id,
   --  with or without enclosing quotes respectively. Alternatively, '#'
   --  works like '&', but is followed by a line reference. Use '@' to
   --  substitute only with sloc of F.

   File_Counter : Natural := 0;
   Message_Id_Counter : Message_Id := 0;
   No_Message_Id : constant Message_Id := -1;

   ---------------------
   -- Compute_Message --
   ---------------------

   function Compute_Message
     (Msg  : String;
      N    : Node_Id;
      F1   : Flow_Id := Null_Flow_Id;
      F2   : Flow_Id := Null_Flow_Id;
      F3   : Flow_Id := Null_Flow_Id)
      return String is
      M : Unbounded_String := Null_Unbounded_String;
   begin
      Append (M, Msg);
      if Present (F1) then
         M := Substitute (M, F1, Sloc (N));
         if Present (F2) then
            M := Substitute (M, F2, Sloc (N));
            if Present (F3) then
               M := Substitute (M, F3, Sloc (N));
            end if;
         end if;
      end if;

      if Instantiation_Location (Sloc (N)) /= No_Location then

         --  If we are dealing with an instantiation of a generic we change
         --  the message to point at the implementation of the generic and we
         --  mention where the generic is instantiated.

         declare
            Tmp     : Source_Ptr := Sloc (First_Node (N));
            File    : Unbounded_String;
            Line    : Physical_Line_Number;
            Context : Unbounded_String;
         begin
            loop
               exit when Instantiation_Location (Tmp) = No_Location;
               if Comes_From_Inlined_Body (Tmp) then
                  Context := To_Unbounded_String (", in call inlined at ");
               else
                  Context := To_Unbounded_String (", in instantiation at ");
               end if;

               Tmp := Instantiation_Location (Tmp);
               File := To_Unbounded_String (File_Name (Tmp));
               Line := Get_Physical_Line_Number (Tmp);
               Append (M, To_String (Context) &
                         To_String (File) & ":" & Image (Integer (Line), 1));
            end loop;
         end;
      end if;
      return To_String (M);
   end Compute_Message;

   function Compute_Sloc
     (N           : Node_Id;
      Place_First : Boolean := False) return Source_Ptr
   is
      Slc : Source_Ptr;
   begin
      if Instantiation_Location (Sloc (N)) /= No_Location then
         --  If we are dealing with an instantiation of a generic we change
         --  the message to point at the implementation of the generic and we
         --  mention where the generic is instantiated.
         Slc := Original_Location (Sloc (N));

      elsif Place_First then
         Slc := First_Sloc (N);
      else
         Slc := Sloc (N);
      end if;
      return Slc;
   end Compute_Sloc;

   --------------------
   -- Error_Msg_Flow --
   --------------------

   procedure Error_Msg_Flow
     (E            : Entity_Id;
      Msg          : String;
      Kind         : Msg_Kind;
      N            : Node_Id;
      Suppressed   : out Boolean;
      F1           : Flow_Id       := Null_Flow_Id;
      F2           : Flow_Id       := Null_Flow_Id;
      F3           : Flow_Id       := Null_Flow_Id;
      Tag          : Flow_Tag_Kind := Empty_Tag;
      SRM_Ref      : String        := "";
      Tracefile    : String        := "";
      Continuation : Boolean := False)
   is
      Msg2    : constant String :=
        (if SRM_Ref'Length > 0 then Msg & " (SPARK RM " & SRM_Ref & ")"
         else Msg);
      Msg3    : constant String := Compute_Message (Msg2, N, F1, F2, F3);
      Suppr   : String_Id := No_String;
      Slc     : constant Source_Ptr := Compute_Sloc (N);
      Msg_Id  : Message_Id := No_Message_Id;
      Unb_Msg : constant Unbounded_String :=
        To_Unbounded_String (Msg3 &
                             Source_Ptr'Image (Slc) &
                             Msg_Kind_To_String (Kind));

      function Is_Specified_Line return Boolean;
      --  Returns True if command line argument "--limit-line" was not
      --  given, or if the message currently being processed is to
      --  be emitted on the line specified by the "--limit-line"
      --  argument.

      -----------------------
      -- Is_Specified_Line --
      -----------------------

      function Is_Specified_Line return Boolean is
         Loc  : constant Source_Ptr :=
           Translate_Location (Sloc (N));
         File : constant String := File_Name (Loc);
         Line : constant Physical_Line_Number :=
           Get_Physical_Line_Number (Loc);
      begin
         return Gnat2Why_Args.Limit_Line = Null_Unbounded_String
           or else File & ":" & Image (Integer (Line), 1) =
                     To_String (Gnat2Why_Args.Limit_Line);
      end Is_Specified_Line;

   --  Start of processing for Error_Msg_Flow

   begin
      --  If the message we are about to emit has already been emitted
      --  in the past then do nothing.

      if Flow_Msgs_Set.Contains (Unb_Msg) then
         Suppressed := True;
      else
         Flow_Msgs_Set.Insert (Unb_Msg);

         case Kind is
            when Warning_Kind =>
               Suppr := Warning_Is_Suppressed (N, Msg3, F1, F2, F3);
               Suppressed := Suppr /= No_String;

            when Info_Kind =>
               Suppressed := Report_Mode = GPR_Fail;

            when Check_Kind =>
               declare
                  Is_Annot : Boolean;
                  Info     : Annotated_Range;
               begin
                  Check_Is_Annotated (N, Msg3, True, Is_Annot, Info);
                  if Is_Annot then
                     Suppr := Info.Reason;
                  end if;
               end;
               Suppressed := Suppr /= No_String;

            when Error_Kind =>
               --  Set the error flag if we have an error message. Note
               --  that warnings do not count as errors here, they should
               --  not prevent us going to proof. The errout mechanism
               --  already deals with the warnings-as-errors handling for
               --  the whole unit.
               Suppressed       := False;
               Found_Flow_Error := True;
         end case;

         --  Print the message except when it's suppressed.
         --  Additionally, if command line argument "--limit-line" was
         --  given, only issue the warning if it is to be emitted on
         --  the specified line (errors are emitted anyway).

         if not Suppressed and then Is_Specified_Line then
            Msg_Id := Print_Regular_Msg (Msg3, Slc, Kind, Continuation);
         end if;

         Add_Json_Msg
           (Suppr     => Suppr,
            Tag       => Flow_Tag_Kind'Image (Tag),
            Kind      => Kind,
            Slc       => Slc,
            Msg_List  => Flow_Msgs,
            E         => E,
            Tracefile => Tracefile,
            Msg_Id    => Msg_Id);
      end if;
   end Error_Msg_Flow;

   procedure Error_Msg_Flow
     (FA           : in out Flow_Analysis_Graphs;
      Msg          : String;
      Kind         : Msg_Kind;
      N            : Node_Id;
      F1           : Flow_Id               := Null_Flow_Id;
      F2           : Flow_Id               := Null_Flow_Id;
      F3           : Flow_Id               := Null_Flow_Id;
      Tag          : Flow_Tag_Kind         := Empty_Tag;
      SRM_Ref      : String                := "";
      Tracefile    : String                := "";
      Vertex       : Flow_Graphs.Vertex_Id := Flow_Graphs.Null_Vertex;
      Continuation : Boolean               := False)
   is
      E       : Entity_Id;
      Img     : constant String := Natural'Image
        (FA.CFG.Vertex_To_Natural (Vertex));
      Tmp     : constant String :=
        (if Gnat2Why_Args.Flow_Advanced_Debug and then
           Vertex /= Flow_Graphs.Null_Vertex
         then Msg & " <" & Img (2 .. Img'Last) & ">"
         else Msg);
      Suppressed : Boolean;
   begin
      case FA.Kind is
         when Kind_Subprogram |
              Kind_Package    |
              Kind_Task       |
              Kind_Entry      =>
            E := FA.Analyzed_Entity;
         when Kind_Package_Body =>
            E := Spec_Entity (FA.Analyzed_Entity);
      end case;

      Error_Msg_Flow (E            => E,
                      Msg          => Tmp,
                      Kind         => Kind,
                      N            => N,
                      Suppressed   => Suppressed,
                      F1           => F1,
                      F2           => F2,
                      F3           => F3,
                      Tag          => Tag,
                      SRM_Ref      => SRM_Ref,
                      Tracefile    => Tracefile,
                      Continuation => Continuation);

      --  Set the No_Errors_Or_Warnings flag to False for this
      --  entity if we are dealing with anything but a suppressed
      --  warning.

      if not Suppressed then
         FA.No_Errors_Or_Warnings := False;
      end if;
   end Error_Msg_Flow;

   ---------------------
   -- Error_Msg_Proof --
   ---------------------

   procedure Error_Msg_Proof
     (N           : Node_Id;
      Msg         : String;
      Is_Proved   : Boolean;
      Tag         : VC_Kind;
      Tracefile   : String;
      Cntexmp     : JSON_Value := Create_Object;
      VC_File     : String;
      Editor_Cmd  : String;
      E           : Entity_Id;
      How_Proved  : String;
      Stats       : JSON_Value := Create_Object;
      Place_First : Boolean)
   is
      function Do_Pretty_Cntexmp (Cntexmp : JSON_Value) return JSON_Value;
      --  Pretty print model element names in Cntexmp.
      --  Note that no deep copy of Cntexmp is made and thus both input
      --  counterexample (Cntexmp) and returned counterexample will contain
      --  pretty printed model element names.

      -----------------------
      -- Do_Pretty_Cntexmp --
      -----------------------

      function Do_Pretty_Cntexmp (Cntexmp : JSON_Value) return JSON_Value
      is
         procedure Do_Pretty_File (File : String; File_Cntexmp : JSON_Value);
         --  Pretty prints model element names in counterexample file.
         procedure Do_Pretty_Line (Line : String; Line_Cntexmp : JSON_Value);
         --  Pretty prints model element names in counterexample line.

         --------------------
         -- Do_Pretty_File --
         --------------------

         procedure Do_Pretty_File (File : String; File_Cntexmp : JSON_Value)
         is
            pragma Unreferenced (File);
         begin
            Map_JSON_Object (File_Cntexmp, Do_Pretty_Line'Access);
         end Do_Pretty_File;

         --------------------
         -- Do_Pretty_Line --
         --------------------

         procedure Do_Pretty_Line (Line : String; Line_Cntexmp : JSON_Value)
         is
            function Get_Pretty_Name
              (Name : String; Kind : String) return String;
            --  Get pretty printed model element name.

            ---------------------
            -- Get_Pretty_Name --
            ---------------------

            function Get_Pretty_Name
              (Name : String; Kind : String) return String
            is
               Name_Parts : String_Split.Slice_Set;
            begin

               --  Name either error message or of the form
               --  "Entity_Id"{".Entity_Id"}*

               if Kind = "error_message" then
                  return Name;
               end if;

               --  Split Name into sequence of Entity_Id and build the pretty
               --  model element name using these

               String_Split.Create (S => Name_Parts,
                       From => Name,
                       Separators => ".",
                       Mode => String_Split.Single);

               declare
                  First_Entity : constant Entity_Id :=
                    Entity_Id'Value (String_Split.Slice (Name_Parts, 1));
                  Name_Pretty : Unbounded_String :=
                    To_Unbounded_String (Source_Name (First_Entity));
               begin

                  --  Process the first Entity_Id, which corresponds to a
                  --  variable. Possibly append attributes 'Old or 'Result
                  --  after its name

                  if Kind = "old" and then
                    Out_Present (Parent (First_Entity))
                  then
                     Name_Pretty := Name_Pretty & "'Old";
                  elsif Kind = "result" then
                     Name_Pretty := Name_Pretty & "'Result";
                  end if;

                  --  Process other Entity_Ids, which correspond to record
                  --  fields

                  for I in 2 .. String_Split.Slice_Count (Name_Parts) loop
                     declare
                        Entity : constant Entity_Id :=
                          Entity_Id'Value (String_Split.Slice (Name_Parts, I));
                     begin
                        Name_Pretty :=
                          Name_Pretty & "." & Source_Name (Entity);
                     end;
                  end loop;

                  return To_String (Name_Pretty);

               end;
            end Get_Pretty_Name;

            pragma Unreferenced (Line);
            Line_Cntexmp_Arr : constant JSON_Array := Get (Line_Cntexmp);
         begin
            --  Change model element names to pretty printed names in all model
            --  elements in counterexample line.
            for I in Integer range 1 .. Length (Line_Cntexmp_Arr) loop
               declare
                  Cntexmp_Element : constant JSON_Value :=
                    Get (Line_Cntexmp_Arr, I);
                  Name  : constant String := Get (Cntexmp_Element, "name");
                  Kind  : constant String := Get (Cntexmp_Element, "kind");
               begin
                  Set_Field (Cntexmp_Element,
                             "name",
                             Create (Get_Pretty_Name (Name, Kind)));
               end;
            end loop;
         end Do_Pretty_Line;
      begin
         Map_JSON_Object (Cntexmp, Do_Pretty_File'Access);

         return Cntexmp;
      end Do_Pretty_Cntexmp;

      function Get_Cntexmp_One_Liner
        (Cntexmp : JSON_Value; VC_Loc : Source_Ptr) return String;
      --  Get the part of the counterexample corresponding to the location of
      --  the construct that triggers VC.

      ---------------------------
      -- Get_Cntexmp_One_Liner --
      ---------------------------
      function Get_Cntexmp_One_Liner
        (Cntexmp : JSON_Value; VC_Loc : Source_Ptr) return String
      is
         function Get_Cntexmp_Line_Str
           (Cntexmp_Line : JSON_Array) return String;

         --------------------------
         -- Get_Cntexmp_Line_Str --
         --------------------------

         function Get_Cntexmp_Line_Str
           (Cntexmp_Line : JSON_Array) return String
         is
            Cntexmp_Line_Str : Unbounded_String := To_Unbounded_String ("");
            procedure Add_Cntexmp_Element
              (Add_Cntexmp_Element : JSON_Value);

            -------------------------
            -- Add_Cntexmp_Element --
            -------------------------

            procedure Add_Cntexmp_Element
              (Add_Cntexmp_Element : JSON_Value)
            is
               Name  : constant String := Get (Add_Cntexmp_Element, "name");
               Value : constant JSON_Value :=
                 Get (Add_Cntexmp_Element, "value");
               Kind  : constant String := Get (Add_Cntexmp_Element, "kind");
               Element : constant String := Name &
               (if Kind = "error_message" then "" else " = " & Get (Value));
            begin
               Cntexmp_Line_Str :=
                 (if Cntexmp_Line_Str = "" then To_Unbounded_String (Element)
                  else Cntexmp_Line_Str & " and " &
                    To_Unbounded_String (Element));
            end Add_Cntexmp_Element;

         begin
            for I in Integer range 1 .. Length (Cntexmp_Line) loop
               Add_Cntexmp_Element (Get (Cntexmp_Line, I));
            end loop;

            return To_String (Cntexmp_Line_Str);
         end Get_Cntexmp_Line_Str;

         File  : constant String :=
              File_Name (VC_Loc);
         Line  : constant Integer :=
           Integer (Get_Logical_Line_Number (VC_Loc));
         Line_Str : constant String :=
           To_String (Trim (To_Unbounded_String (Integer'Image (Line)), Both));
         Cntexmp_File : constant JSON_Value :=
           (if Has_Field (Cntexmp, File) then Get (Cntexmp, File)
            else Create_Object);
         Cntexmp_Line : constant JSON_Array :=
           (if Has_Field (Cntexmp_File, Line_Str) then
                 Get (Get (Cntexmp_File, Line_Str))
            else Empty_Array);
         Cntexmp_Line_Str : constant String :=
           Get_Cntexmp_Line_Str (Cntexmp_Line);
      begin
            return (if Cntexmp_Line_Str = "" then
                       "error: cannot get location of the check"
                    else Cntexmp_Line_Str);
      end Get_Cntexmp_One_Liner;

      Msg2     : constant String :=
        Compute_Message (Msg, N);
      Pretty_Cntexmp  : constant JSON_Value := Do_Pretty_Cntexmp (Cntexmp);
      Slc      : constant Source_Ptr := Compute_Sloc (N, Place_First);
      Msg3     : constant String :=
        (if Is_Empty (Cntexmp) then Msg2
         else Msg2 &
         ", counterexample: " & Get_Cntexmp_One_Liner (Pretty_Cntexmp, Slc));
      Kind     : constant Msg_Kind :=
        (if Is_Proved then Info_Kind else Medium_Check_Kind);
      Suppr    : String_Id := No_String;
      Msg_Id   : Message_Id := No_Message_Id;
      Is_Annot : Boolean;
      Info     : Annotated_Range;

   begin

      --  The call to Check_Is_Annotated needs to happen on all paths, even
      --  though we only need the info in the Check_Kind path. The reason is
      --  that also in the Info_Kind case, we want to know whether the check
      --  corresponds to a pragma Annotate.

      Check_Is_Annotated (N, Msg, Kind in Check_Kind, Is_Annot, Info);

      case Kind is
         when Check_Kind =>
            if Is_Annot then
               Suppr := Info.Reason;
            else
               Msg_Id := Print_Regular_Msg (Msg3, Slc, Kind);
            end if;
         when Info_Kind =>
            if Report_Mode /= GPR_Fail then
               Msg_Id := Print_Regular_Msg (Msg3, Slc, Kind);
            end if;
         when Error_Kind | Warning_Kind =>
            --  cannot happen
            null;
      end case;

      Add_Json_Msg
        (Suppr       => Suppr,
         Tag         => VC_Kind'Image (Tag),
         Kind        => Kind,
         Slc         => Slc,
         Msg_List    => Proof_Msgs,
         Msg_Id      => Msg_Id,
         E           => E,
         Tracefile   => Tracefile,
         Cntexmp     => Pretty_Cntexmp,
         VC_File     => VC_File,
         How_Proved  => How_Proved,
         Stats       => Stats,
         Editor_Cmd  => Editor_Cmd);

   end Error_Msg_Proof;

   ------------
   -- Escape --
   ------------

   function Escape (S : String) return String is
      R : Unbounded_String := Null_Unbounded_String;
   begin
      for Index in S'Range loop
         if S (Index) in '%' | '$' | '{' | '*' | '&' | '#' |
                         '}' | '@' | '^' | '>' | '!' | '?' |
                         '<' | '`' | ''' | '\' | '|'
           or else Is_Upper_Case_Letter (S (Index))
         then
            Append (R, "'");
         end if;

         Append (R, S (Index));
      end loop;

      return To_String (R);
   end Escape;

   ----------------------
   -- Fresh_Trace_File --
   ----------------------

   function Fresh_Trace_File return String is
      Result : constant String :=
        Unit_Name & "__flow__" & Image (File_Counter, 1) & ".trace";
   begin
      File_Counter := File_Counter + 1;
      return Result;
   end Fresh_Trace_File;

   -------------------
   -- Get_Flow_JSON --
   -------------------

   function Get_Flow_JSON return JSON_Array is (Flow_Msgs);

   --------------------
   -- Get_Proof_JSON --
   --------------------

   function Get_Proof_JSON return JSON_Array is (Proof_Msgs);

   ------------------------
   -- Msg_Kind_To_String --
   ------------------------

   function Msg_Kind_To_String (Kind : Msg_Kind) return String is
   begin
      case Kind is
         when Error_Kind =>
            return "error";
         when Warning_Kind =>
            return "warning";
         when Info_Kind =>
            return "info";
         when High_Check_Kind =>
            return "high";
         when Medium_Check_Kind =>
            return "medium";
         when Low_Check_Kind =>
            return "low";
      end case;
   end Msg_Kind_To_String;

   ------------------
   -- Add_Json_Msg --
   ------------------

   procedure Add_Json_Msg
     (Suppr       : String_Id;
      Tag         : String;
      Kind        : Msg_Kind;
      Slc         : Source_Ptr;
      Msg_List    : in out GNATCOLL.JSON.JSON_Array;
      E           : Entity_Id;
      Msg_Id      : Message_Id;
      Tracefile   : String := "";
      Cntexmp     : JSON_Value := GNATCOLL.JSON.Create_Object;
      VC_File     : String := "";
      How_Proved  : String := "";
      Stats       : JSON_Value := GNATCOLL.JSON.Create_Object;
      Editor_Cmd  : String := "")
   is
      Value : constant JSON_Value := Create_Object;
      File  : constant String     := File_Name (Slc);
      Line  : constant Integer    := Integer (Get_Logical_Line_Number (Slc));
      Col   : constant Integer    := Integer (Get_Column_Number (Slc));
   begin

      Set_Field (Value, "file", File);
      Set_Field (Value, "line", Line);
      Set_Field (Value, "col", Col);

      if Suppr /= No_String then
         declare
            Len           : constant Natural :=
              Natural (String_Length (Suppr));
            Reason_String : String (1 .. Len);
         begin
            String_To_Name_Buffer (Suppr);
            Reason_String := Name_Buffer (1 .. Len);
            Set_Field (Value, "suppressed", Reason_String);
         end;
      end if;

      Set_Field (Value, "rule", Tag);
      Set_Field (Value, "severity", Msg_Kind_To_String (Kind));
      Set_Field (Value, "entity", To_JSON (Entity_To_Subp (E)));

      if Tracefile /= "" then
         Set_Field (Value, "tracefile", Tracefile);
      end if;

      if not Is_Empty (Cntexmp) then
         Set_Field (Value, "cntexmp", Cntexmp);
      end if;

      if VC_File /= "" then
         Set_Field (Value, "vc_file", VC_File);
      end if;

      if Editor_Cmd /= "" then
         Set_Field (Value, "editor_cmd", Editor_Cmd);
      end if;

      if Msg_Id /= No_Message_Id then
         Set_Field (Value, "msg_id", Integer (Msg_Id));
      end if;

      if How_Proved /= "" then
         Set_Field (Value, "how_proved", How_Proved);
      end if;

      if not Is_Empty (Stats) then
         Set_Field (Value, "stats", Stats);
      end if;

      Append (Msg_List, Value);
   end Add_Json_Msg;

   -----------------------
   -- Print_Regular_Msg --
   -----------------------

   function Print_Regular_Msg
     (Msg  : String;
      Slc  : Source_Ptr;
      Kind : Msg_Kind;
      Continuation : Boolean := False)
      return Message_Id
   is
      Id         : constant Message_Id := Message_Id_Counter;
      Prefix     : constant String :=
        (if Continuation then "\" else "") &
        (case Kind is
            when Info_Kind         => "info: ?",
            when Low_Check_Kind    => "low: ",
            when Medium_Check_Kind => "medium: ",
            when High_Check_Kind   => "high: ",
            when Warning_Kind      => "?",
            when Error_Kind        => "");
      Actual_Msg : constant String :=
        Prefix & Escape (Msg) & "!!" &
        (if Ide_Mode
         then "'['#" & Image (Integer (Id), 1) & "']"
         else "");
   begin
      Message_Id_Counter := Message_Id_Counter + 1;
      Error_Msg (Actual_Msg, Slc);
      return Id;
   end Print_Regular_Msg;

   ----------------
   -- Substitute --
   ----------------

   function Substitute
     (S    : Unbounded_String;
      F    : Flow_Id;
      Flag : Source_Ptr)
      return Unbounded_String
   is
      R      : Unbounded_String := Null_Unbounded_String;
      Do_Sub : Boolean          := True;
      Quote  : Boolean;

      procedure Append_Quote;
      --  Append a quote on R if Quote is True

      ------------------
      -- Append_Quote --
      ------------------

      procedure Append_Quote is
      begin
         if Quote then
            Append (R, """");
         end if;
      end Append_Quote;

   begin
      for Index in Positive range 1 .. Length (S) loop
         if Do_Sub then
            case Element (S, Index) is
            when '&' | '#' | '%' =>
               Quote := Element (S, Index) in '&' | '#';

               case F.Kind is
               when Null_Value =>
                  raise Program_Error;

               when Synthetic_Null_Export =>
                  Append_Quote;
                  Append (R, "null");

               when Direct_Mapping | Record_Field =>
                  if Is_Private_Part (F) then
                     Append (R, "private part of ");
                     Append_Quote;
                     Append (R, Flow_Id_To_String
                               (F'Update (Facet => Normal_Part)));
                  elsif Is_Extension (F) then
                     Append (R, "extension of ");
                     Append_Quote;
                     Append (R, Flow_Id_To_String
                               (F'Update (Facet => Normal_Part)));
                  elsif Is_Bound (F) then
                     Append (R, "bounds of ");
                     Append_Quote;
                     Append (R, Flow_Id_To_String
                               (F'Update (Facet => Normal_Part)));
                  elsif Nkind (Get_Direct_Mapping_Id (F)) in N_Entity
                    and then Ekind (Get_Direct_Mapping_Id (F)) = E_Constant
                  then
                     Append (R, "constant with");
                     if not Has_Variable_Input (F) then
                        Append (R, "out");
                     end if;
                     Append (R, " variable input ");
                     Append_Quote;
                     Append (R, Flow_Id_To_String (F));
                  elsif Is_Constituent (F) then
                     Append_Quote;
                     Append (R, Flow_Id_To_String (F));
                     Append_Quote;
                     Append (R, " constituent of ");
                     Append_Quote;
                     declare
                        Encaps_State : constant Node_Id :=
                          Encapsulating_State (Get_Direct_Mapping_Id (F));
                        Encaps_Scope : constant Node_Id :=
                          Scope (Encaps_State);
                     begin
                        --  If scopes of the abstract state and its constituent
                        --  differ then prefix the name of the abstract state
                        --  with its immediate scope.
                        if Encaps_Scope /= Scope (Get_Direct_Mapping_Id (F))
                        then
                           Get_Name_String (Chars (Encaps_Scope));
                           Adjust_Name_Case (Sloc (Encaps_Scope));

                           Append (R, Name_Buffer (1 .. Name_Len) & ".");
                        end if;

                        Get_Name_String (Chars (Encaps_State));
                        Adjust_Name_Case (Sloc (Encaps_State));

                        Append (R, Name_Buffer (1 .. Name_Len));
                     end;
                  else
                     Append_Quote;
                     Append (R, Flow_Id_To_String (F));
                  end if;

               when Magic_String =>
                  --  ??? we may want to use __gnat_decode() here instead
                  Append_Quote;
                  declare
                     F_Name_String : constant String := To_String (F.Name);
                  begin
                     if F_Name_String = "__HEAP" then
                        Append (R, "the heap");
                     else
                        declare
                           Index : Positive := F_Name_String'First;
                        begin
                           --  Replace __ with . in the magic string.
                           while Index <= F_Name_String'Last loop
                              case F_Name_String (Index) is
                              when '_' =>
                                 if Index < F_Name_String'Last and then
                                   F_Name_String (Index + 1) = '_'
                                 then
                                    Append (R, ".");
                                    Index := Index + 2;
                                 else
                                    Append (R, '_');
                                    Index := Index + 1;
                                 end if;

                              when others =>
                                 Append (R, F_Name_String (Index));
                                 Index := Index + 1;
                              end case;
                           end loop;
                        end;
                     end if;
                  end;
               end case;

               Append_Quote;

               if Element (S, Index) = '#' then
                  case F.Kind is
                  when Direct_Mapping | Record_Field =>
                     declare
                        N : constant Node_Id := Get_Direct_Mapping_Id (F);
                     begin
                        Msglen := 0;
                        Set_Msg_Insertion_Line_Number (Sloc (N), Flag);
                        Append (R, " ");
                        Append (R, Msg_Buffer (1 .. Msglen));
                     end;
                  when others =>
                     --  Can't really add source information for stuff that
                     --  doesn't come from the tree.
                     null;
                  end case;
               end if;

               Do_Sub := False;

            when '@' =>
               declare
                  N : constant Node_Id := Get_Direct_Mapping_Id (F);
               begin
                  Msglen := 0;
                  Set_Msg_Insertion_Line_Number (Sloc (N), Flag);
                  Append (R, Msg_Buffer (1 .. Msglen));
               end;

            when others =>
               Append (R, Element (S, Index));
            end case;
         else
            Append (R, Element (S, Index));
         end if;
      end loop;

      return R;
   end Substitute;

   ---------------------------
   -- Warning_Is_Suppressed --
   ---------------------------

   function Warning_Is_Suppressed
     (N   : Node_Id;
      Msg : String;
      F1  : Flow_Id := Null_Flow_Id;
      F2  : Flow_Id := Null_Flow_Id;
      F3  : Flow_Id := Null_Flow_Id)
     return String_Id is

      function Warning_Disabled_For_Entity return Boolean;
      --  Returns True if either of N, F1, F2 correspond to an entity that
      --  Has_Warnings_Off.

      ---------------------------------
      -- Warning_Disabled_For_Entity --
      ---------------------------------

      function Warning_Disabled_For_Entity return Boolean is

         function Is_Entity_And_Has_Warnings_Off
           (N : Node_Or_Entity_Id) return Boolean
         is
           ((Nkind (N) in N_Has_Entity
               and then Present (Entity (N))
               and then Has_Warnings_Off (Entity (N)))
               or else
            (Nkind (N) in N_Entity
               and then Has_Warnings_Off (N)));
         --  Returns True if N is an entity and Has_Warnings_Off (N)

      begin
         if Is_Entity_And_Has_Warnings_Off (N) then
            return True;
         end if;

         if Present (F1)
           and then F1.Kind in Direct_Mapping | Record_Field
           and then Is_Entity_And_Has_Warnings_Off (Get_Direct_Mapping_Id (F1))
         then
            return True;
         end if;

         if Present (F2)
           and then F2.Kind in Direct_Mapping | Record_Field
           and then Is_Entity_And_Has_Warnings_Off (Get_Direct_Mapping_Id (F2))
         then
            return True;
         end if;

         if Present (F3)
           and then F3.Kind in Direct_Mapping | Record_Field
           and then Is_Entity_And_Has_Warnings_Off (Get_Direct_Mapping_Id (F3))
         then
            return True;
         end if;

         return False;
      end Warning_Disabled_For_Entity;

      Suppr_Reason : String_Id := Warnings_Suppressed (Sloc (N));

   begin
      if Suppr_Reason = No_String then
         Suppr_Reason :=
           Warning_Specifically_Suppressed
             (Loc => Sloc (N),
              Msg => Msg'Unrestricted_Access);

         if Suppr_Reason = No_String
           and then Warning_Disabled_For_Entity
         then
            Suppr_Reason := Null_String_Id;
         end if;
      end if;
      return Suppr_Reason;
   end Warning_Is_Suppressed;

end Flow_Error_Messages;
