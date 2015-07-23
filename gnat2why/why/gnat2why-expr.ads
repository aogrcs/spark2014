------------------------------------------------------------------------------
--                                                                          --
--                            GNAT2WHY COMPONENTS                           --
--                                                                          --
--                        G N A T 2 W H Y - E X P R                         --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
--                       Copyright (C) 2010-2015, AdaCore                   --
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
-- gnat2why is maintained by AdaCore (http://www.adacore.com)               --
--                                                                          --
------------------------------------------------------------------------------

with Ada.Containers.Hashed_Maps;

with Atree;             use Atree;
with Flow_Types;        use Flow_Types;
with Sem_Eval;          use Sem_Eval;
with Sinfo;             use Sinfo;
with Types;             use Types;

with SPARK_Util;        use SPARK_Util;

with Why.Gen.Terms;     use Why.Gen.Terms;

with Why.Types;         use Why.Types;
with Why.Ids;           use Why.Ids;
with Why.Inter;         use Why.Inter;
with Why.Sinfo;         use Why.Sinfo;

with Common_Containers; use Common_Containers;

with Gnat2Why.Util;     use Gnat2Why.Util;

package Gnat2Why.Expr is

   function Assignment_Of_Obj_Decl (N : Node_Id) return W_Prog_Id;
   --  Generate an assignment from an object declaration

   function Assume_Dynamic_Property
     (Expr          : W_Expr_Id;
      Ty            : Entity_Id;
      Only_Var      : Boolean := True;
      Initialized   : Boolean := True;
      Top_Predicate : Boolean := True;
      Use_Pred      : Boolean := True) return W_Prog_Id;
   --  Generate an assumption that N is a value of its type.
   --  If Only_Var is true, then don't assume properties of constant parts
   --  of the object, such as the bounds of an array.

   function Check_Scalar_Range
     (Params : Transformation_Params;
      N      : Entity_Id;
      Base   : Entity_Id) return W_Prog_Id
     with Pre => (if No (Base) then Is_OK_Static_Range (Get_Range (N)));
   --  Generate checks for the bounds of a range as well as a
   --  range check that the range_constraint is compatible with the subtype.
   --  Returns the empty program if both Base and N have a static
   --  range_constraint.
   --  @param Params transformation parameters
   --  @param N calling Get_Range on N should get the range to check.
   --  @param Base type against which N's bounds should be checked if any.
   --  @return a program that checks that no error can appear while computing
   --  N's bounds and that they are in Base's range.

   function Check_Subtype_Indication
     (Params   : Transformation_Params;
      N        : Node_Id;
      Sub_Type : Entity_Id) return W_Prog_Id;
   --  Generate checks for bounds of the range_constraint in Sub_Typ as well as
   --  a range check that the range_constraint in Sub_Typ is compatible with
   --  the subtype. Returns the empty program if N is not a scalar subtype,
   --  or is a scalar subtype with a static range_constraint.

   function Compute_Default_Init
     (Expr           : W_Expr_Id;
      Ty             : Entity_Id;
      Params         : Transformation_Params := Body_Params;
      Skip_Last_Cond : W_Term_Id := False_Term;
      Use_Pred       : Boolean := True) return W_Pred_Id;
   --  @param Expr Expression for which we want the default initialization
   --  @param Ty The type of the expression Expr
   --  @param Params Transformation parameters
   --  @param Skip_Last_Cond Do not assume the top-level
   --         Default_Initial_Condition of Ty if any.
   --  @param Use_Pred Use the precomputed predicate for Ty's dynamic property
   --  @result The dynamic property of type Ty over Expr

   function Compute_Dynamic_Predicate
     (Expr     : W_Expr_Id;
      Ty       : Entity_Id;
      Params   : Transformation_Params := Body_Params;
      Use_Pred : Boolean := True) return W_Pred_Id;
   --  @param Expr Why3 expression on which to express the dynamic predicate
   --  @param Ty type with the dynamic property
   --  @param Params transformation parameters
   --  @param Use_Pred True iff the named predicate should be used
   --  @result Why3 predicate expressing the dynamic predicate of type [Ty]
   --     over [Expr].

   function Compute_Dynamic_Property
     (Expr          : W_Expr_Id;
      Ty            : Entity_Id;
      Initialized   : W_Term_Id := True_Term;
      Only_Var      : W_Term_Id := True_Term;
      Top_Predicate : W_Term_Id := True_Term;
      Params        : Transformation_Params := Body_Params;
      Use_Pred      : Boolean := True) return W_Pred_Id;
   --  @param Expr Expression for which we want the dynamic property
   --  @param Ty The type of the expression Expr
   --  @param Only_Var Only assume property over variable parts of Expr
   --  @param Initialized Assume that Expr is initialized
   --  @param Skip_Predicate whether the type predicate is considered
   --  @param Params Transformation parameters
   --  @param Use_Pred Use the precomputed predicate for Ty's dynamic property
   --  @result The dynamic property of type Ty over Expr.

   function Get_Container_In_Iterator_Specification
     (N : Node_Id) return Node_Id;

   function Get_Pure_Logic_Term_If_Possible
     (File          : Why_Section;
      Expr          : Node_Id;
      Expected_Type : W_Type_Id) return W_Term_Id;
   --  If Expr can be translated into a pure logic term (without dereference),
   --  return this term. Otherwise, return Why_Empty.

   function Insert_Predicate_Check
     (Ada_Node : Node_Id;
      Check_Ty : Entity_Id;
      W_Expr   : W_Prog_Id) return W_Prog_Id;
   --  @param Ada_Node node to which the check is attached
   --  @param Check_Ty type whose predicate needs to be checked
   --  @param W_Expr Why3 expression on which to check the predicate
   --  @result Why3 program that performs the check and returns [W_Expr]

   function New_Op_Expr
     (Op          : N_Op;
      Left        : W_Expr_Id := Why_Empty;
      Right       : W_Expr_Id;
      Left_Type   : Entity_Id := Empty;
      Right_Type  : Entity_Id;
      Return_Type : Entity_Id;
      Domain      : EW_Domain;
      Ada_Node    : Node_Id := Empty) return W_Expr_Id;
   --  Generates Left Op Right depending on the value of Op and the Ada types
   --  Return_Type, Left_Type, and Right_Type

   function Range_Expr
     (N           : Node_Id;
      T           : W_Expr_Id;
      Domain      : EW_Domain;
      Params      : Transformation_Params;
      T_Type      : W_Type_OId := Why_Empty) return W_Expr_Id;
   --  Given an N_Range node N and a Why expr T, create an expression
   --  low <= T <= high
   --  where "low" and "high" are the lower and higher bounds of N.
   --  T_Type is the base type in which the comparisons take
   --  place (e.g. int, real). If it is not set, it is deduced from
   --  the bounds' type.

   function Transform_Attribute_Old
     (Expr   : Node_Id;
      Domain : EW_Domain;
      Params : Transformation_Params) return W_Expr_Id;
   --  Translate Expr'Old into Why

   function Transform_Declarations_Block (L : List_Id; Core : W_Prog_Id)
      return W_Prog_Id;
   --  Translate the Declarations block of Block statement or subprogram to a
   --  sequence of Why expressions; dynamic type declarations are translated
   --  to assert/assume statements, object declarations to assignment
   --  statements

   function Transform_Declarations_For_Body (L : List_Id) return W_Prog_Id;
   --  Transform the declarations in the list, but excluding the leading
   --  declarations with a Related_Expression wich is a parameter enity.

   function Transform_Declarations_For_Params (L : List_Id) return W_Prog_Id;
   --  Transform the declarations in the list, only the first declarations
   --  with a Related_Expression wich is a parameter enity.

   function Transform_Discrete_Choices
     (Choices      : List_Id;
      Choice_Type  : Entity_Id;
      Matched_Expr : W_Expr_Id;
      Cond_Domain  : EW_Domain;
      Params       : Transformation_Params) return W_Expr_Id;
      --  Return the guard that corresponds to a branch. In programs, also
      --  generate a check that dynamic choices are in the subtype Choice_Type.

   function Transform_Expr
     (Expr          : Node_Id;
      Expected_Type : W_Type_Id;
      Domain        : EW_Domain;
      Params        : Transformation_Params) return W_Expr_Id;
   --  Compute an expression in Why having the expected type for the given Ada
   --  expression node. The formal "Domain" decides if we return a predicate,
   --  term or program. If Ref_Allowed is True, then references are allowed,
   --  for example in the context of a program (whether the domain is EW_Prog
   --  for program text or EW_Pred/EW_Term for contract). If Ref_Allowed is
   --  False, then references are not allowed, for example in the context of an
   --  axiom or a logic function definition.

   function Transform_Expr
     (Expr        : Node_Id;
      Domain      : EW_Domain;
      Params      : Transformation_Params) return W_Expr_Id;
   --  Same as above, but derive the Expected_Type from the Ada Expr

   function Transform_Expr_With_Actions
     (Expr          : Node_Id;
      Actions       : List_Id;
      Expected_Type : W_Type_Id;
      Domain        : EW_Domain;
      Params        : Transformation_Params) return W_Expr_Id;
   --  Same as Transform_Expr, but takes into account the declarations of
   --  constants in Actions, to create a suitable variable map for translating
   --  Expr.

   function Transform_Expr_With_Actions
     (Expr          : Node_Id;
      Actions       : List_Id;
      Domain        : EW_Domain;
      Params        : Transformation_Params) return W_Expr_Id;
   --  Same as above, but derive the Expected_Type from the Ada Expr

   function Transform_Identifier
     (Params   : Transformation_Params;
      Expr     : Node_Id;
      Ent      : Entity_Id;
      Domain   : EW_Domain;
      Selector : Selection_Kind := Why.Inter.Standard) return W_Expr_Id;
   --  Transform an Ada identifier to a Why item (take care of enumeration
   --  literals, boolean values etc)
   --
   --  This also deals with volatility, so that an object with a Async_Writers
   --  is suitably havoc'd before being read.

   function Transform_Pragma
     (Prag  : Node_Id;
      Force : Boolean) return W_Prog_Id
   with
     Pre => Nkind (Prag) = N_Pragma;
   --  Returns the Why program for pragma.
   --  @param Prag The pragma to translate into Why3.
   --  @param Force True to force the translation of the pragma, for those
   --     pragmas normally translated elsewhere like preconditions and
   --     postconditions.
   --  @return The translated pragma into Why3.

   procedure Transform_Pragma_Check
     (Stmt    :     Node_Id;
      Force   :     Boolean;
      Runtime : out W_Prog_Id;
      Pred    : out W_Pred_Id);
   --  Translates a pragma Check into Why3.
   --  @param Stmt The pragma Check to translate.
   --  @param Force True to force the translation of the pragma, even for those
   --     pragmas normally translated elsewhere like preconditions and
   --     postconditions.
   --  @param Runtime On exit, Why3 program for checking absence of run-time
   --     errors in the pragma.
   --  @param Pred On exit, Why3 proposition corresponding to the pragma.

   function Transform_Pragma_Check
     (Prag  : Node_Id;
      Force : Boolean) return W_Prog_Id;
   --  Returns the Why program for pragma Check. As most assertion pragmas
   --  (like Assert or Assume) are internally rewritten by semantic analysis
   --  into pragma Check, this is where these are translated.
   --  @param Prag The pragma Check to translate into Why3.
   --  @param Force True to force the translation of the pragma, even for those
   --     pragmas normally translated elsewhere like preconditions and
   --     postconditions.
   --  @return The translated pragma into Why3.

   function Transform_Statements_And_Declarations
     (Stmts_And_Decls : Node_Lists.List) return W_Prog_Id;
   function Transform_Statements_And_Declarations
     (Stmts_And_Decls : List_Id) return W_Prog_Id;
   --  Transforms a list of statements and declarations into a Why expression.
   --  An empty list is transformed into the void expression.

   function Transform_Statement_Or_Declaration_In_List
     (Stmt_Or_Decl : Node_Id;
      Prev_Prog    : W_Prog_Id) return W_Prog_Id;
   --  Transform the next statement or declaration Cur, inside a list of
   --  statements and declarations. Prev_Prog is the transformation of the
   --  previous statements and declarations in the list. This allows treating
   --  the case where Cur is a pragma Assert_And_Cut.

   procedure Variables_In_Default_Init
     (Ty        : Entity_Id;
      Variables : in out Flow_Id_Sets.Set);
   --  @param Ty a type
   --  @param Variables used in the expression for Ty's default initialization

   procedure Variables_In_Dynamic_Predicate
     (Ty        : Entity_Id;
      Variables : in out Flow_Id_Sets.Set);
   --  @param Ty a type with a predicate
   --  @param Variables used in the expression for Ty's predicate

   procedure Variables_In_Dynamic_Property
     (Ty        : Entity_Id;
      Variables : in out Flow_Id_Sets.Set);
   --  @param Ty a type
   --  @param Variables used in the expression for Ty's dynamic invariant

   ----------------------------------------
   -- Attributes Old, Loop_Entry, Result --
   ----------------------------------------

   --  Expressions X'Old and F'Result are normally expanded into references to
   --  saved values of variables by the frontend, but this expansion does not
   --  apply to the original postcondition. It is this postcondition which
   --  is translated by gnat2why into a program to detect possible run-time
   --  errors, therefore a special mechanism is needed to deal with expressions
   --  X'Old and F'Result.

   Result_Name : W_Identifier_Id := Why_Empty;
   --  Name to use for occurrences of F'Result in the postcondition. It should
   --  be equal to Why_Empty when we are not generating code for detecting
   --  run-time errors in the postcondition.

   package Ada_To_Why_Ident is new Ada.Containers.Hashed_Maps
     (Key_Type        => Node_Id,
      Element_Type    => W_Identifier_Id,
      Hash            => Node_Hash,
      Equivalent_Keys => "=",
      "="             => "=");

   package Loop_Entry_Nodes is new Ada.Containers.Hashed_Maps
     (Key_Type        => Node_Id,
      Element_Type    => Ada_To_Why_Ident.Map,
      Hash            => Node_Hash,
      Equivalent_Keys => "=",
      "="             => Ada_To_Why_Ident."=");

   function Bind_From_Mapping_In_Expr
     (Params                 : Transformation_Params;
      Map                    : Ada_To_Why_Ident.Map;
      Expr                   : W_Prog_Id;
      Guard_Map              : Ada_To_Why_Ident.Map :=
        Ada_To_Why_Ident.Empty_Map;
      Others_Guard_Ident     : W_Identifier_Id := Why_Empty;
      Do_Runtime_Error_Check : Boolean := True;
      Bind_Value_Of_Old      : Boolean := False) return W_Prog_Id;
   --  Bind names from Map to their corresponding values, obtained by
   --  transforming the expression node associated to the name in Map, in
   --  Expr. Do_Runtime_Error_Check is True if the returned Why program
   --  should check for absence of run-time errors in the expressions bound.
   --  Bind_Value_Of_Old is True when binding the value of references to Old in
   --  postcondition and contract-cases, as a special treatment is requested to
   --  only check absence of run-time error when the corresponding guard of a
   --  contract-case is enabled. Guard_Map and Others_Guard_Ident are used to
   --  retrieve the identifier for the corresponding guard in that case.

   function Name_For_Loop_Entry
     (Expr    : Node_Id;
      Loop_Id : Node_Id) return W_Identifier_Id;
   --  Returns the identifier to use for a Expr'Loop_Entry(Loop_Id)

   function Map_For_Loop_Entry (Loop_Id : Node_Id) return Ada_To_Why_Ident.Map;
   --  Returns the map of identifiers to use for Loop_Entry attribute
   --  references applying to loop Loop_Id.

   function Map_For_Old return Ada_To_Why_Ident.Map;
   --  Returns the map of identifiers to use for Old attribute references in
   --  the current subprogram.

   procedure Reset_Map_For_Old;
   --  Empty the map of identifiers to use for Old attribute references

   function Name_For_Old (N : Node_Id) return W_Identifier_Id;
   --  During the generation of code for detecting run-time errors in the
   --  postcondition, return the name to use for occurrences of N'Old.

   --  Register a node that appears with attribute 'Old; return a fresh
   --  Name_Id for this Node. This function is intended to be called by the
   --  code that translates expressions to Why (Gnat2why.Expr), which itself
   --  is called by Transform_Subprogram. For each call to this
   --  function, a declaration at the beginning of the Why program is
   --  generated.

   function Name_For_Result return W_Identifier_Id;
   --  During the generation of code for detecting run-time errors in the
   --  postcondition of F, return the name to use for occurrences of F'Result.

private
   --  Mapping of all expressions whose 'Old attribute is used in the current
   --  postcondition to the translation of the corresponding
   --  expression in Why. Until 'Old is forbidden in the body, this is also
   --  used to translate occurrences of 'Old that are left by the frontend (for
   --  example, inside quantified expressions that are only preanalyzed).
   --
   --  The mapping is cleared before generating Why code for VC generation for
   --  the body and postcondition, filled during the translation, and used
   --  afterwards to generate the necessary copy instructions.

   Old_Map        : Ada_To_Why_Ident.Map;
   Loop_Entry_Map : Loop_Entry_Nodes.Map;

   function Map_For_Loop_Entry
     (Loop_Id : Node_Id) return Ada_To_Why_Ident.Map
   is
     (if Loop_Entry_Map.Contains (Loop_Id) then
        Loop_Entry_Map.Element (Loop_Id)
      else
        Ada_To_Why_Ident.Empty_Map);

   function Map_For_Old return Ada_To_Why_Ident.Map is (Old_Map);

end Gnat2Why.Expr;
