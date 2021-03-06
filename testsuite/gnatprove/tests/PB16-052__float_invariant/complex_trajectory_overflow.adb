with Interfaces; use Interfaces;

package body Complex_Trajectory_Overflow
  with SPARK_Mode
is
   procedure Compute_Distance (N         : Frame;
                               Factor    :        Ratio_T;
                               Drag      :        Drag_T;
                               Speed     : in out Float64;
                               Distance  : in out Float64;
                               Average   :    out Float64)
   is
      Old_Speed : constant Float64 := Speed;
      Delta_Speed : constant Float64 := Drag + Factor * G * Frame_Length;
      function T (N : Integer) return Float64 is (Float64 (N)) with Ghost;
      N_Bv : constant Unsigned_16 := Unsigned_16(N) with Ghost;
   begin
      Speed := Speed + Delta_Speed;

      --  Bound all quantities involved with constants

      pragma Assert (Delta_Speed in -Bound .. Bound);
      pragma Assert (In_Bounds (High_Bound(N)));
      pragma Assert (In_Bounds (Low_Bound(N)));

      --  Intermediate assertions to bound New_Speed

      pragma Assert (Float64(N_Bv) * Bound + Bound = (Float64(N_Bv) + 1.0) * Bound);
      pragma Assert (Float64(N) * Bound + Bound = (Float64(N) + 1.0) * Bound);
      pragma Assert (Float64(N) * (-Bound) - Bound = (Float64(N) + 1.0) * (-Bound));

      --  Relate the property on Float64(N) + 1.0 to the same property on Float64(N+1)

      pragma Assert (T(1) = 1.0);
      pragma Assert (Float64(N) + 1.0 = Float64(N + 1));

      pragma Assert (Speed >= Float64 (N) * (-Bound) - Bound);
      pragma Assert (Speed >= Float64 (N + 1) * (-Bound));
      pragma Assert (Speed <= Float64 (N) * Bound + Bound);
      pragma Assert (Speed <= Float64 (N + 1) * Bound);

      --  Relate the bounds to the postcondition

      pragma Assert (Speed >= Low_Bound (N + 1));
      pragma Assert (Speed <= High_Bound (N + 1));
      pragma Assert (Invariant (N + 1, Speed));

      Average := (Old_Speed + Speed) / 2.0;
      Distance := Distance + (Average * Frame_Length);
   end Compute_Distance;

end Complex_Trajectory_Overflow;
