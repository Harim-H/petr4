Require Import Coq.PArith.BinPosDef.
Require Import Coq.PArith.BinPos.
Require Import Coq.NArith.BinNatDef.
Require Import Coq.ZArith.BinIntDef.
Require Import Coq.NArith.BinNat.
Require Import Coq.ZArith.BinInt.
Require Import Coq.micromega.Lia.

Require Import P4cub.SmallStep.
Import IsValue.
Import Step.
Import Typecheck.
Module P := P4cub.AST.P4cub.
Module E := P.Expr.

Import P.P4cubNotations.
Import E.TypeEquivalence.

Import F.FieldTactics.

Ltac invert_value :=
  match goal with
  | H: value _ |- _ => inv H
  end.

Ltac invert_expr_check :=
  match goal with
  | H: ⟦ _, _ ⟧ ⊢ _ ∈ _ |- _ => inv H
  end.

Ltac invert_canonical := invert_value; invert_expr_check.

Ltac crush_canonical := intros; invert_canonical; eauto.

Section Lemmas.

  Variable errs : errors.

  Variable Γ : gamma.

  Section CanonicalForms.
    Context {tags_t : Type}.

    Variable v : E.e tags_t.

    Hypothesis Hv : value v.

    Lemma canonical_forms_bool :
      ⟦ errs, Γ ⟧ ⊢ v ∈ Bool -> exists b i, v = <{ BOOL b @ i }>.
    Proof. crush_canonical. Qed.

    Lemma canonical_forms_bit : forall w,
        ⟦ errs, Γ ⟧ ⊢ v ∈ bit<w> -> exists n i, v = <{ w W n @ i }>.
    Proof. crush_canonical. Qed.

    Lemma canonical_forms_int : forall w,
        ⟦ errs, Γ ⟧ ⊢ v ∈ int<w> -> exists z i, v = <{ w S z @ i }>.
    Proof. crush_canonical. Qed.

    Lemma canonical_forms_tuple : forall ts,
        ⟦ errs, Γ ⟧ ⊢ v ∈ tuple ts -> exists es i, v = <{ tup es @ i }>.
    Proof. crush_canonical. Qed.

    Lemma canonical_forms_record : forall ts,
        ⟦ errs, Γ ⟧ ⊢ v ∈ rec { ts } -> exists fs i, v = <{ rec { fs } @ i }>.
    Proof. crush_canonical. Qed.

    Lemma canonical_forms_header : forall ts,
        ⟦ errs, Γ ⟧ ⊢ v ∈ hdr { ts } -> exists fs b i, v = <{ hdr { fs } valid:=b @ i }>.
    Proof. crush_canonical. Qed.

    Lemma canonical_forms_error :
      ⟦ errs, Γ ⟧ ⊢ v ∈ error -> exists err i, v = <{ Error err @ i }>.
    Proof. crush_canonical. Qed.

    Lemma canonical_forms_matchkind :
      ⟦ errs, Γ ⟧ ⊢ v ∈ matchkind -> exists mk i, v = <{ Matchkind mk @ i }>.
    Proof. crush_canonical. Qed.

    Lemma canonical_forms_headerstack : forall ts n,
        ⟦ errs, Γ ⟧ ⊢ v ∈ stack ts[n] ->
        exists hs ni, v = <{ Stack hs:ts[n] nextIndex:= ni }>.
    Proof. crush_canonical. Qed.
  End CanonicalForms.
End Lemmas.

Ltac assert_canonical_forms :=
  match goal with
  | Hv: value ?v, Ht: ⟦ _, _ ⟧ ⊢ ?v ∈ Bool |- _
    => pose proof canonical_forms_bool _ _ _ Hv Ht as [? [? ?]]; inv Hv; inv Ht
  | Hv: value ?v, Ht: ⟦ _, _ ⟧ ⊢ ?v ∈ bit<_> |- _
    => pose proof canonical_forms_bit _ _ _ Hv _ Ht as [? [? ?]]; inv Hv; inv Ht
  | Hv: value ?v, Ht: ⟦ _, _ ⟧ ⊢ ?v ∈ int<_> |- _
    => pose proof canonical_forms_int _ _ _ Hv _ Ht as [? [? ?]]; inv Hv; inv Ht
  | Hv: value ?v, Ht: ⟦ _, _ ⟧ ⊢ ?v ∈ tuple _ |- _
    => pose proof canonical_forms_tuple _ _ _ Hv _ Ht as [? [? ?]]; inv Hv; inv Ht
  | Hv: value ?v, Ht: ⟦ _, _ ⟧ ⊢ ?v ∈ rec { _ } |- _
    => pose proof canonical_forms_record _ _ _ Hv _ Ht as [? [? ?]]; inv Hv; inv Ht
  | Hv: value ?v, Ht: ⟦ _, _ ⟧ ⊢ ?v ∈ hdr { _ } |- _
    => pose proof canonical_forms_header _ _ _ Hv _ Ht as [? [? [? ?]]]; inv Hv; inv Ht
  | Hv: value ?v, Ht: ⟦ _, _ ⟧ ⊢ ?v ∈ error |- _
    => pose proof canonical_forms_error _ _ _ Hv Ht as [? [? ?]]; inv Hv; inv Ht
  | Hv: value ?v, Ht: ⟦ _, _ ⟧ ⊢ ?v ∈ matchkind |- _
    => pose proof canonical_forms_matchkind _ _ _ Hv Ht as [? [? ?]]; inv Hv; inv Ht
  | Hv: value ?v, Ht: ⟦ _, _ ⟧ ⊢ ?v ∈ stack _[_] |- _
    => pose proof canonical_forms_headerstack _ _ _ Hv _ _ Ht as [? [? ?]]; inv Hv; inv Ht
  end; subst; try discriminate.
(**[]*)

Section Theorems.
  Variable Γ : gamma.

  Context {tags_t : Type}.

  Variable ϵ : @eenv tags_t.

  (** Epsilon is a subset of Gamma. *)
  Definition envs_subset : Prop :=
    forall (x : string) (τ : E.t),
      Γ x = Some τ -> exists v, ϵ x = Some v.
  (**[]*)

  Variable errs : errors.

  (** Epsilon's values type's agree with Gamma. *)
  Definition envs_type : Prop :=
    forall (x : string) (τ : E.t) (v : E.e tags_t),
      Γ x = Some τ -> ϵ x = Some v -> ⟦ errs , Γ ⟧ ⊢ v ∈ τ.
  (**[]*)

  Definition envs_sound : Prop := envs_type /\ envs_subset.

  Section Preservation.
    Hypothesis Henvs_type : envs_type.

    Theorem expr_small_step_preservation : forall e e' τ,
        ℵ ϵ ** e -->  e' -> ⟦ errs, Γ ⟧ ⊢ e ∈ τ -> ⟦ errs, Γ ⟧ ⊢ e' ∈ τ.
    Proof.
      Hint Resolve eval_cast_types : core.
      Hint Resolve BitArith.return_bound_bound : core.
      Hint Resolve BitArith.neg_bound : core.
      Hint Resolve BitArith.plus_mod_bound : core.
      Hint Resolve IntArith.return_bound_bound : core.
      Hint Resolve eval_hdr_op_types : core.
      Hint Resolve eval_stk_op_types : core.
      Hint Resolve eval_uop_types : core.
      Hint Resolve eval_bop_types : core.
      Hint Resolve eval_cast_types : core.
      Hint Resolve eval_member_types : core.
      Hint Rewrite Forall_app : core.
      Hint Rewrite app_length : core.
      Hint Resolve Forall2_app : core.
      Hint Constructors check_expr : core.
      Hint Constructors PT.proper_nesting : core.
      unfold envs_type in Henvs_type; intros;
      generalize dependent τ;
      match goal with
      | H: ℵ ϵ ** _ -->  _ |- _ => induction H; intros
      end;
      try match goal with
          | H: ⟦ errs, Γ ⟧ ⊢ _ ∈ _ |- _ => inv H
          end; unravel in *;
      repeat assert_canonical_forms; eauto.
      - inv H4. assert_canonical_forms. inv H1.
        unravel in *. inv H0. eauto.
      - inv H3.
        assert (⟦ errs, Γ ⟧ ⊢ Stack x:ts[size0] nextIndex:=x0 ∈ stack ts[size0]) by auto.
        inv H; unravel in *; eauto.
      - inv H3; unravel in *. eapply Forall_nth_error in H12; eauto.
      - subst es; subst es'.
        apply Forall2_app_inv_l in H5 as [? [? [? [? ?]]]];
        inv_Forall2_cons; eauto.
      - subst fs; subst fs'.
        apply Forall2_app_inv_l in H5 as [? [? [? [? ?]]]];
        inv_Forall2_cons; relf_destruct; intuition; subst.
        constructor. apply Forall2_app; auto.
        repeat constructor; auto.
      - inv H3. subst fs; subst fs'.
        apply Forall2_app_inv_l in H8 as [? [? [? [? ?]]]];
        inv_Forall2_cons; relf_destruct; intuition; subst.
        inv H6; try match goal with
                    | H: PT.base_type {{ hdr { _ } }} |- _ => inv H
                    end.
        constructor; eauto.
        apply Forall2_app; auto.
        repeat constructor; auto.
      - subst hs; subst hs'; constructor;
        autorewrite with core in *; intuition;
        try inv_Forall_cons; eauto.
    Qed.
  End Preservation.

  Section Progress.
    Hypothesis Henvs_sound : envs_sound.

    Ltac progress_simpl :=
      match goal with
      | H: value _ \/ (exists _, ℵ ϵ ** _ -->  _)
        |- _ => destruct H as [? | ?]
      | H: exists _, ℵ ϵ ** _ -->  _ |- _ => destruct H as [? ?]
      | |- _ => assert_canonical_forms
      | IH: (?P -> ?Q -> value _ \/ exists _, ℵ ϵ ** _ -->  _),
            HP: ?P, HQ: ?Q |- _ => pose proof IH HP HQ as [? | ?]; clear IH
      end.
    (**[]*)

    Theorem expr_small_step_progress : forall e τ,
        ⟦ errs, Γ ⟧ ⊢ e ∈ τ -> value e \/ exists e', ℵ ϵ ** e -->  e'.
    Proof.
      Hint Constructors value : core.
      Hint Constructors expr_step : core.
      Hint Resolve eval_cast_exists : core.
      Hint Resolve eval_uop_exists : core.
      Hint Resolve eval_bop_exists : core.
      Hint Resolve eval_stk_op_exists : core.
      Hint Resolve eval_member_exists : core.
      Hint Resolve expr_small_step_preservation : core.
      destruct Henvs_sound as [Henvs_type Henvs_subset];
      clear Henvs_sound; unfold envs_type, envs_subset in *; intros.
      match goal with
      | H: ⟦ errs, Γ ⟧ ⊢ _ ∈ _
        |- _ => induction H using custom_check_expr_ind
      end;
      try match goal with
          | |- value ?e \/ _ =>
            assert (value e); [ repeat constructor; eassumption
                          | left; assumption ]
          end;
      repeat progress_simpl; eauto.
      - right; apply Henvs_subset in H as [? ?]; eauto.
      - pose proof eval_cast_exists _ _ _ _ _ H1 H H0 as [? ?]; eauto.
      - pose proof eval_uop_exists _ _ _ _ _ H H1 H0 as [? ?]; eauto.
      - pose proof eval_bop_exists _ _ _ _ _ _ i _ _ H H3 H2 H0 H1 as [? ?]; eauto.
      - pose proof eval_member_exists _ _ _ _ _ _ _ H2 H0 H H1 as [? ?]; eauto.
      - induction H; repeat inv_Forall2_cons;
        repeat progress_simpl; eauto; intuition.
        + inv H3; eauto.
        + destruct H3 as [? ?]. inv H2.
          subst es; subst es'.
          repeat rewrite app_comm_cons in *. eauto.
        + rewrite <- (app_nil_l (x :: l)). eauto.
        + rewrite <- (app_nil_l (x :: l)). eauto.
      - induction H; repeat invert_cons_cons_relate;
        repeat progress_simpl; intuition.
        + left. repeat constructor.
        + inv H4. left. repeat constructor; unravel; eauto.
        + destruct H4 as [? ?]. inv H2.
          subst fs; subst fs'.
          repeat rewrite app_comm_cons in *. right.
          exists (E.ERecord (((s0, p) :: prefix) ++ (x0, (τ, e')) :: suffix) i).
          repeat constructor; unravel; eauto.
        + destruct p as [t e]; simpl in *. unfold F.f.
          rewrite <- (app_nil_l ((s, (t, e)) :: l)).
          right. exists (E.ERecord ([] ++ (s, (t, x)) :: l) i).
          repeat constructor; unravel; eauto.
        + destruct p as [t e]; simpl in *. unfold F.f.
          rewrite <- (app_nil_l ((s, (t, e)) :: l)).
          right. exists (E.ERecord ([] ++ (s, (t, x)) :: l) i).
          repeat constructor; unravel; eauto.
      - inv H5. clear H. rename H0 into H; rename H1 into H0.
        induction H; repeat invert_cons_cons_relate;
        repeat progress_simpl; intuition.
        + left. repeat constructor.
        + inv H4. left. repeat constructor; unravel; eauto.
        + destruct H4 as [? ?]. inv H2.
          * subst fs; subst fs'.
            repeat rewrite app_comm_cons in *. right.
            exists (E.EHeader
                 (((s0, p) :: prefix) ++ (x2, (τ, e')) :: suffix)
               <{ BOOL x @ x0 }> i).
            repeat constructor; unravel; eauto.
          * inv H9.
        + destruct p as [t e]; simpl in *. unfold F.f.
          rewrite <- (app_nil_l ((s, (t, e)) :: l)). right.
          exists (E.EHeader ([] ++ (s, (t, x1)) :: l) <{ BOOL x @ x0 }> i).
          repeat constructor; unravel; eauto.
        + destruct p as [t e]; simpl in *. unfold F.f.
          rewrite <- (app_nil_l ((s, (t, e)) :: l)). right.
          exists (E.EHeader ([] ++ (s, (t, x1)) :: l) <{ BOOL x @ x0 }> i).
          repeat constructor; unravel; eauto.
      - inv H5. assert_canonical_forms. inv H0.
        right. exists (eval_hdr_op op x x2 x3 x1). eauto.
      - clear H H0 H1 H2.
        (* generalize dependent ni; generalize dependent n. *)
        induction H3; intros; repeat inv_Forall_cons; eauto;
        intuition; try assert_canonical_forms.
        + inv H7. assert_canonical_forms. inv H0; inv H2; eauto.
        + inv H7. assert_canonical_forms. inv H0.
          destruct H2 as [v Hv]. inv Hv. subst hs; subst hs'.
          repeat rewrite app_comm_cons in *; eauto 6.
        + destruct H0 as [v Hv]. rewrite <- (app_nil_l (x :: l)); eauto.
        + destruct H0 as [v Hv]. rewrite <- (app_nil_l (x :: l)); eauto.
      - inv H4. assert (Hidx : N.to_nat idx < length x) by lia.
        pose proof nth_error_exists _ _ Hidx as [v ?]. eauto.
      - inv H4.
        pose proof eval_stk_op_exists
             _ _ i op _ _ _ _ H6 H7 H8 H9 H10 as [? ?]; eauto.
    Qed.
  End Progress.
End Theorems.
