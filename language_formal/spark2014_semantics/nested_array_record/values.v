Require Export language.
Require Export util.

(** * Return values/states *)
(** Statement and expressions evaluation returns one of the following results:
    - normal result;
    - run time errors, which are required to be detected at run time,
      for example, overflow check and division by zero check;
    - unterminated state caused by infinite loop (only for functional semantics);
    - abnormal state, which includes compile time errors
      (for example, type checks failure and undefined variables), 
      bounded errors and erroneous execution. 
      In the future, the abnormal state can be refined into these 
      more precise categories (1.1.5);
*)

Inductive Return (A:Type): Type :=
    | Normal: A -> Return A
    | Run_Time_Error: Return A
    | Unterminated: Return A
    | Abnormal: Return A.

(* TODO: add stuff in error states *)
Arguments Normal [A] a.
Arguments Run_Time_Error {A}.
Arguments Unterminated {A}.
Arguments Abnormal {A}.


(** * Value Types *) 

(** the range of 32-bit (singed/unsigned) integer type: 
    - modulus : 2^32 ;
    - half_modulus : 2^31 ;
    - max_unsigned : 2^32 -1 ;
    - max_signed : 2^31 - 1 ;
    - min_signed : -2^31 ;
*)
Definition wordsize: nat := 32.
Definition modulus : Z := two_power_nat wordsize.
Definition half_modulus : Z := Z.div modulus 2.
Definition max_unsigned : Z := Z.sub modulus 1.
Definition max_signed : Z := Z.sub half_modulus 1.
Definition min_signed : Z := Z.opp half_modulus.


(** Type of basic values*)

(** TODO: now we only model the 32-bit singed integer for SPARK 
    program, where Coq integer (Z) is used to represent this integer  
    value with a range bound between min_signed and max_signed. 
    This integer range constraint is enforced when we define the
    semantics for the language;
*)
Inductive basic_value : Type :=
    | Int (n : Z)
    | Bool (b : bool).

Inductive value : Type :=
    | BasicV (v: basic_value)
    | AggregateV (v: aggregate_value)

with aggregate_value : Type :=
    | ArrayV (a: list value)
    | RecordV (r: list (idnum*value)).

(** Type of stored values in the store.
TODO: rename into value_stored, for uniformity with type_stored. *)
Inductive value_stored: Type := 
    | Value (v:value)
    | Procedure (pb: procedure_declaration)
    | TypeDef (typ: type)
    | Undefined.

(** Expression evaluation returns one of the following results:
    - normal values;
    - run time errors, which are required to be detected at run time,
      for example, overflow check and division by zero check;
    - abnormal values, which includes compile time errors
      (for example, type checks failure and undefined variables), 
      bounded errors and erroneous execution. In the future, 
      if it's necessary, we would refine the abnormal value into 
      these more precise categories (1.1.5);
*)



(** * Value Operations *)
Module Val.

(*
Notation "n == m" := (Zeq_bool n m) (at level 70, no associativity).
Notation "n != m" := (Zneq_bool n m) (at level 70, no associativity).
Notation "n > m" := (Z.gtb m n) (at level 70, no associativity).
Notation "n >= m" := (Z.geb m n) (at level 70, no associativity).
Notation "n < m" := (Z.ltb n m) (at level 70, no associativity).
Notation "n <= m" := (Z.leb n m) (at level 70, no associativity).
*)

(** ** Arithmetic operations *)

Definition unary_add (v: basic_value): Return basic_value := 
    match v with
    | Int v1' => Normal v
    | _ => Abnormal
    end.

Definition add (v1 v2: basic_value): Return basic_value := 
    match v1, v2 with
    | Int v1', Int v2' => 
        Normal (Int (v1' + v2'))
    | _, _ => Abnormal
    end.

Definition sub (v1 v2: basic_value): Return basic_value := 
    match v1, v2 with
    | Int v1', Int v2' => Normal (Int (v1' - v2'))
    | _, _ => Abnormal
    end.

Definition mul (v1 v2: basic_value): Return basic_value :=
    match v1, v2 with
    | Int v1', Int v2' => Normal (Int (v1' * v2'))
    | _, _ => Abnormal
    end.


(** map Ada operators to corresponding Coq operators:
    - div -> Z.quot
    - rem -> Z.rem
    - mod -> Z.modulo

      (Note: Ada "mod" has the following formula in Why:    
       - if y > 0 then EuclideanDivision.mod x y else EuclideanDivision.mod x y + y)
*)

Definition div (v1 v2: basic_value): Return basic_value := 
    match v1, v2 with
    | Int v1', Int v2' => Normal (Int (Z.quot v1' v2'))
    | _, _ => Abnormal
    end.

Definition rem (v1 v2: basic_value): Return basic_value := 
    match v1, v2 with
    | Int v1', Int v2' => Normal (Int (Z.rem v1' v2'))
    | _, _ => Abnormal
    end.

(* the keyword "mod" cannot redefined here, so we use "mod'" *)
Definition mod' (v1 v2: basic_value): Return basic_value := 
    match v1, v2 with
    | Int v1', Int v2' => Normal (Int (Z.modulo v1' v2'))
    | _, _ => Abnormal
    end.

(** ** Logic operations  *)
Definition and (v1 v2: basic_value): Return basic_value :=
    match v1, v2 with
    | Bool v1', Bool v2' => Normal (Bool (andb v1' v2'))
    | _, _ => Abnormal
    end.

Definition or (v1 v2: basic_value): Return basic_value :=
    match v1, v2 with
    | Bool v1', Bool v2' => Normal (Bool (orb v1' v2'))
    | _, _ => Abnormal
    end.

(** ** Relational operations *)
Definition eq (v1 v2: basic_value): Return basic_value :=
    match v1, v2 with
    | Int v1', Int v2' => Normal (Bool (Zeq_bool v1' v2'))
    | _, _ => Abnormal
    end.

Definition ne (v1 v2: basic_value): Return basic_value :=
    match v1, v2 with
    | Int v1', Int v2' => Normal (Bool (Zneq_bool v1' v2'))
    | _, _ => Abnormal
    end.

Definition gt (v1 v2: basic_value): Return basic_value :=
    match v1, v2 with
    | Int v1', Int v2' => Normal (Bool (Zgt_bool v1' v2'))
    | _, _ => Abnormal
    end.

Definition ge (v1 v2: basic_value): Return basic_value :=
    match v1, v2 with
    | Int v1', Int v2' => Normal (Bool (Zge_bool v1' v2'))
    | _, _ => Abnormal
    end.

Definition lt (v1 v2: basic_value): Return basic_value :=
    match v1, v2 with
    | Int v1', Int v2' => Normal (Bool (Zlt_bool v1' v2'))
    | _, _ => Abnormal
    end.

Definition le (v1 v2: basic_value): Return basic_value :=
    match v1, v2 with
    | Int v1', Int v2' => Normal (Bool (Zle_bool v1' v2'))
    | _, _ => Abnormal
    end.

(** ** Unary operations *)
Definition not (v: basic_value): Return basic_value :=
    match v with
    | Bool v' => Normal (Bool (negb v'))
    | _ => Abnormal
    end.
End Val. 

 
