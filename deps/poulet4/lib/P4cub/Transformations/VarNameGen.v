Require Import Coq.Numbers.DecimalString.
Require Import Coq.Strings.String.

Open Scope string_scope.
Definition t : Type :=  nat.
Definition new_env : t := 
  0.
Definition new_var (env: t) : string * t :=
  ("_p_4_s_e_l_"++(NilZero.string_of_uint (Nat.to_uint env)),  env+1).
