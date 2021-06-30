Require Import Coq.Lists.List.
Require Import Coq.Classes.EquivDec.
Require Import Poulet4.FinType.
Require Poulet4.P4automata.Syntax.
Module P4A := Poulet4.P4automata.Syntax.
Require Import Poulet4.P4automata.PreBisimulationSyntax.
Require Poulet4.P4automata.WP.
Import ListNotations.

Section WeakestPreSymbolicLeap.
  Set Implicit Arguments.
  
  (* State identifiers. *)
  Variable (S1: Type).
  Context `{S1_eq_dec: EquivDec.EqDec S1 eq}.
  Context `{S1_finite: @Finite S1 _ S1_eq_dec}.

  Variable (S2: Type).
  Context `{S2_eq_dec: EquivDec.EqDec S2 eq}.
  Context `{S2_finite: @Finite S2 _ S2_eq_dec}.

  Definition S: Type := S1 + S2.

  (* Header identifiers. *)
  Variable (H: Type).
  Context `{H_eq_dec: EquivDec.EqDec H eq}.
  Context `{H_finite: @Finite H _ H_eq_dec}.

  Variable (a: P4A.t S H).

  Definition lpred c : Type :=
    nat * WP.pred S1 S2 H c.

  Definition jump_pred
             {c}
             (si: side)
             (s: state_template S)
             (candidate: S)
    : lpred c :=
    let st := a.(P4A.t_states) candidate in
    (P4A.size a candidate,
     WP.PredJump (WP.trans_cond si (P4A.st_trans st) s.(st_state)) candidate).

  Definition weaken_lpred {c} (size: nat) (p: lpred c) : lpred (BCSnoc c size) :=
    (fst p, WP.weaken_pred size (snd p)).

  Definition max_preds
             {c}
             (si: side)
             (candidates: list S)
             (s: state_template S)
    : list (lpred c) :=
    if s.(st_buf_len) == 0
    then List.map (jump_pred si s) candidates
    else [(s.(st_buf_len),
           WP.PredRead _ _ {| st_state := s.(st_state); st_buf_len := 0 |})].

  Definition modify_pred {c} (max: nat) (pred: lpred c) : lpred c :=
    (max, 
     match snd pred with
     | WP.PredJump phi s => WP.PredJump phi s
     | WP.PredRead _ _ s => WP.PredRead _ c {| st_state := s.(st_state);
                                               st_buf_len := fst pred - max |}
     end).

  Definition wp_lpred {c: bctx} (si: side) (b: bit_expr H c) (p: lpred c) (phi: store_rel H c) : store_rel H c :=
    let phi' := WP.sr_subst a phi (BEConcat (BEBuf _ _ si) b) (BEBuf _ _ si) in
    match snd p with
    | WP.PredRead _ _ s =>
      phi'
    | WP.PredJump cond s =>
      BRImpl cond (WP.wp_op a si (a.(P4A.t_states) s).(P4A.st_op) phi')
    end.

  Definition st_lpred {c} (p: lpred c) :=
    match snd p with
    | WP.PredRead _ _ s => s
    | WP.PredJump _ s => {| st_state := inl s; st_buf_len := P4A.size a s - fst p |}
    end.

  Definition wp_pred_pair
             (phi: conf_rel S H)
             (preds: lpred phi.(cr_ctx) * lpred phi.(cr_ctx))
    : list (conf_rel S H) :=
    let '(sl, sr) := preds in
    let size := Nat.min (fst sl) (fst sr) in
    let sl := weaken_lpred size (modify_pred size sl) in
    let sr := weaken_lpred size (modify_pred size sr) in
    let phi_rel := weaken_store_rel size phi.(cr_rel) in
    let b := (BEVar H (BVarTop phi.(cr_ctx) size)) in
    [{| cr_st := {| cs_st1 := st_lpred sl;
                    cs_st2 := st_lpred sr |};
        cr_rel := wp_lpred Left b sl (wp_lpred Right b sr phi_rel) |}].

  Definition wp (phi: conf_rel S H) : list (conf_rel S H) :=
    let cur_st_left  := phi.(cr_st).(cs_st1) in
    let cur_st_right := phi.(cr_st).(cs_st2) in
    let pred_pairs := list_prod (max_preds Left (List.map inl (enum S1)) cur_st_left)
                                (max_preds Right (List.map inr (enum S2)) cur_st_right) in
    List.concat (List.map (wp_pred_pair phi) pred_pairs).

End WeakestPreSymbolicLeap.

Hint Unfold jump_pred: wp.
Hint Unfold weaken_lpred: wp.
Hint Unfold max_preds: wp.
Hint Unfold modify_pred: wp.
Hint Unfold wp_lpred: wp.
Hint Unfold st_lpred: wp.
Hint Unfold wp_pred_pair: wp.
