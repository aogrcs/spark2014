package body Untangle is

   procedure Proc (R : in Exp_Seq_T; I: in Idx_T; Nf: out Opt_P_T) is
   begin
      Nf := Opt_P_T' (Flag  => True,
                      Idx   => I,
                      The_P => R.Points (I));
   end Proc;

end Untangle;
