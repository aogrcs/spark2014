-- This specification is a implementation of a ASM (Abstract Stata Machine)
-- " An ASM is an entity which has well defined states plus a set of operation
-- which cause state transitions

package ASM_Stack with SPARK_Mode is

   function Is_Empty return Boolean;
   function Is_Full return Boolean;
   procedure Clear;
   procedure Push(X : in Integer);
   function Pop return Integer;

end ASM_Stack;
