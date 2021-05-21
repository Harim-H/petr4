Set Warnings "-custom-entry-overridden".
Require Export Poulet4.P4cub.Static.Check.
Require Import Poulet4.P4Arith.
Require Import Poulet4.P4cub.BigStep.Value.
Require Import Coq.Bool.Bool.
Require Import Coq.ZArith.BinInt.
Require Import Coq.Arith.Compare_dec.
Require Import Coq.micromega.Lia.

Module P := P4cub.
Module E := P.Expr.
Module F := P.F.
Module ST := P.Stmt.
Module CD := P.Control.ControlDecl.
Module V := Val.
Import V.ValueNotations.
Import V.LValueNotations.

Module ExprUtil.
  Import P.P4cubNotations.
  Import V.ValueEquality.
  
  (** Bit-slicing. *)
  Definition eval_slice (hi lo : positive) (v : V.v) : option V.v :=
    match v with
    | ~{ _ VW z }~
    | ~{ _ VS z }~
      => let w' := (hi - lo + 1)%positive in
        Some $ V.VBit w' $
             BitArith.mod_bound w' $
             BitArith.bitstring_slice z hi lo
    | _ => None
    end.
  (**[]*)

  (** Unary Operations. *)
  Definition eval_uop (op : E.uop) (v : V.v) : option V.v :=
    match op, v with
    | _{ ! }_, ~{ VBOOL b }~ => Some $ V.VBool  $ negb b
    | _{ ~ }_, ~{ w VW n }~  => Some $ V.VBit w $ BitArith.bit_not w n
    | _{ ~ }_, ~{ w VS n }~  => Some $ V.VInt w $ IntArith.bit_not w n
    | _{ - }_, ~{ w VW z }~  => Some $ V.VBit w $ BitArith.neg w z
    | _{ - }_, ~{ w VS z }~  => Some $ V.VInt w $ IntArith.neg w z
    | _{ isValid }_, ~{ HDR { _ } VALID:=b }~ => Some ~{ VBOOL b }~
    | _{ setValid }_, ~{ HDR { vs } VALID:=_ }~
      => Some ~{ HDR { vs } VALID:=true }~
    | _{ setInValid }_, ~{ HDR { vs } VALID:=_ }~
      => Some ~{ HDR { vs } VALID:=false }~
    | _{ Size }_, ~{ STACK _:_[n] NEXT:=_ }~ => Some $ V.VBit 32%positive $ Zpos n
    | _{ Next }_, ~{ STACK hs:_[_] NEXT:=ni }~
      => bvs <<| nth_error hs $ Z.to_nat ni ;;
        match bvs with
        | (b,vs) => ~{ HDR { vs } VALID:=b }~
        end
    | _{ Push n }_, ~{ STACK hs:ts[size] NEXT:=ni }~
      => let nnat := Pos.to_nat n in
        let sizenat := Pos.to_nat size in
        if lt_dec nnat sizenat then
          let new_hdrs := repeat (false, F.map V.vdefault ts) nnat in
          let remains := firstn (sizenat - nnat) hs in
          let new_nextIndex := Z.min (ni + Z.pos n) (Z.pos size - 1)%Z in
          Some $ V.VHeaderStack ts (new_hdrs ++ remains) size new_nextIndex
        else
          let new_hdrs := repeat (false, F.map V.vdefault ts) sizenat in
          Some $ V.VHeaderStack ts new_hdrs size ((Z.pos size) - 1)%Z
    | _{ Pop n }_, ~{ STACK hs:ts[size] NEXT:=ni }~
      => let nnat := Pos.to_nat n in
        let sizenat := Pos.to_nat size in
        if lt_dec nnat sizenat then
          let new_hdrs := repeat (false, F.map V.vdefault ts) nnat in
          let remains := skipn nnat hs in
          Some $
               V.VHeaderStack ts (remains ++ new_hdrs) size $
               Z.max 0%Z (ni - Zpos n)%Z
        else
          let new_hdrs := repeat (false, F.map V.vdefault ts) sizenat in
          Some $ V.VHeaderStack ts new_hdrs size 0%Z
    | _, _ => None
    end.
  (**[]*)
  
  (** Binary operations. *)
  Definition eval_bop (op : E.bop) (v1 v2 : V.v) : option V.v :=
    match op, v1, v2 with
    | +{ + }+, ~{ w VW n1 }~, ~{ _ VW n2 }~
      => Some $ V.VBit w $ BitArith.plus_mod w n1 n2
    | +{ + }+, ~{ w VS z1 }~, ~{ _ VS z2 }~
      => Some $ V.VInt w $ IntArith.plus_mod w z1 z2
    | +{ |+| }+, ~{ w VW n1 }~, ~{ _ VW n2 }~
      => Some $ V.VBit w $ BitArith.plus_sat w n1 n2
    | +{ |+| }+,  ~{ w VS z1 }~, ~{ _ VS z2 }~
      => Some $ V.VInt w $ IntArith.plus_sat w z1 z2
    | +{ - }+, ~{ w VW n1 }~, ~{ _ VW n2 }~
      => Some $ V.VBit w $ BitArith.minus_mod w n1 n2
    | +{ - }+, ~{ w VS z1 }~, ~{ _ VS z2 }~
      => Some $ V.VInt w $ IntArith.minus_mod w z1 z2
    | +{ |-| }+, ~{ w VW n1 }~, ~{ _ VW n2 }~
      => Some $ V.VBit w $ BitArith.minus_sat w n1 n2
    | +{ |-| }+, ~{ w VS z1 }~, ~{ _ VS z2 }~
      => Some $ V.VInt w $ IntArith.minus_sat w z1 z2
    | +{ × }+, ~{ w VW n1 }~, ~{ _ VW n2 }~
      => Some $ V.VBit w $ BitArith.mult_mod w n1 n2
    | +{ × }+, ~{ w VS z1 }~, ~{ _ VS z2 }~
      => Some $ V.VInt w $ IntArith.mult_mod w z1 z2
    | +{ << }+, ~{ w VW n1 }~, ~{ _ VW n2 }~
      => Some $ V.VBit w $ BitArith.shift_left w n1 n2
    | +{ << }+, ~{ w VS z1 }~, ~{ _ VW z2 }~
      => Some $ V.VInt w $ IntArith.shift_left w z1 z2
    | +{ >> }+, ~{ w VW n1 }~, ~{ _ VW n2 }~
      => Some $ V.VBit w $ BitArith.shift_right w n1 n2
    | +{ >> }+, ~{ w VS z1 }~, ~{ _ VW z2 }~
      => Some $ V.VInt w $ IntArith.shift_right w z1 z2
    | +{ & }+, ~{ w VW n1 }~, ~{ _ VW n2 }~
      => Some $ V.VBit w $ BitArith.bit_and w n1 n2
    | +{ & }+, ~{ w VS z1 }~, ~{ _ VS z2 }~
      => Some $ V.VInt w $ IntArith.bit_and w z1 z2
    | +{ ^ }+, ~{ w VW n1 }~, ~{ _ VW n2 }~
      => Some $ V.VBit w $ BitArith.bit_xor w n1 n2
    | +{ ^ }+, ~{ w VS z1 }~, ~{ _ VS z2 }~
      => Some $ V.VInt w $ IntArith.bit_xor w z1 z2
    | +{ | }+, ~{ w VW n1 }~, ~{ _ VW n2 }~
      => Some $ V.VBit w $ BitArith.bit_or w n1 n2
    | +{ | }+, ~{ w VS z1 }~, ~{ _ VS z2 }~
      => Some $ V.VInt w $ IntArith.bit_or w z1 z2
    | +{ <= }+, ~{ w VW n1 }~, ~{ _ VW n2 }~ => Some $ V.VBool (n1 <=? n2)%Z
    | +{ <= }+, ~{ w VS z1 }~, ~{ _ VS z2 }~ => Some $ V.VBool (z1 <=? z2)%Z
    | +{ < }+, ~{ w VW n1 }~, ~{ _ VW n2 }~ => Some $ V.VBool (n1 <? n2)%Z
    | +{ < }+, ~{ w VS z1 }~, ~{ _ VS z2 }~ => Some $ V.VBool (z1 <? z2)%Z
    | +{ >= }+, ~{ w VW n1 }~, ~{ _ VW n2 }~ => Some $ V.VBool (n2 <=? n1)%Z
    | +{ >= }+, ~{ w VS z1 }~, ~{ _ VS z2 }~ => Some $ V.VBool (z2 <=? z1)%Z
    | +{ > }+, ~{ w VW n1 }~, ~{ _ VW n2 }~ => Some $ V.VBool (n2 <? n1)%Z
    | +{ > }+, ~{ w VS z1 }~, ~{ _ VS z2 }~ => Some $ V.VBool (z2 <? z1)%Z
    | +{ && }+, ~{ VBOOL b1 }~, ~{ VBOOL b2 }~ => Some $ V.VBool (b1 && b2)
    | +{ || }+, ~{ VBOOL b1 }~, ~{ VBOOL b2 }~ => Some $ V.VBool (b1 || b2)
    | +{ == }+, _, _ => Some $ V.VBool $ eqbv v1 v2
    | +{ != }+, _, _ => Some $ V.VBool $ negb $ eqbv v1 v2
    | +{ ++ }+, ~{ w1 VW n1 }~, ~{ w2 VW n2 }~
    | +{ ++ }+, ~{ w1 VW n1 }~, ~{ w2 VS n2 }~
      => Some $ V.VBit (w1 + w2)%positive $ BitArith.concat w1 w2 n1 n2
    | +{ ++ }+, ~{ w1 VS n1 }~, ~{ w2 VS n2 }~
    | +{ ++ }+, ~{ w1 VS n1 }~, ~{ w2 VW n2 }~
      => Some $ V.VInt (w1 + w2)%positive $ IntArith.concat w1 w2 n1 n2
    | _, _, _ => None
    end.
  (**[]*)
  
  Definition eval_cast
             (target : E.t) (v : V.v) : option V.v :=
    match target, v with
    | {{ bit<xH> }}, ~{ TRUE }~         => Some (V.VBit 1%positive 1%N)
    | {{ bit<xH> }}, ~{ FALSE }~        => Some (V.VBit 1%positive 0%N)
    | {{ Bool }}, V.VBit 1%positive 1%N => Some ~{ TRUE }~
    | {{ Bool }}, V.VBit 1%positive 0%N => Some ~{ FALSE }~
    | {{ bit<w> }}, ~{ _ VS z }~ => let n := BitArith.mod_bound w z in
                                   Some ~{ w VW n }~
    | {{ int<w> }}, ~{ _ VW n }~ => let z := IntArith.mod_bound w n in
                                   Some ~{ w VS z }~
    | {{ bit<w> }}, ~{ _ VW n }~ => let n := BitArith.mod_bound w n in
                                   Some ~{ w VW n }~
    | {{ int<w> }}, ~{ _ VS z }~ => let z := IntArith.mod_bound w z in
                                   Some ~{ w VS z }~
    | {{ rec { fs } }}, ~{ TUPLE vs }~
      => Some $ V.VRecord $ combine (F.keys fs) vs
    | {{ hdr { fs } }}, ~{ TUPLE vs }~
      => Some $ V.VHeader (combine (F.keys fs) vs) true
    | _, _ => None
    end.
  (**[]*)
  
  Definition eval_member (x : string) (v : V.v) : option V.v :=
    match v with
    | ~{ REC { vs } }~
    | ~{ HDR { vs } VALID:=_ }~ => F.get x vs
    | _ => None
    end.
  (**[]*)
  
  Section Lemmas.
    Import Typecheck.
    Import V.ValueTyping.
    Import P4ArithTactics.
    Import E.ProperType.
    
    Section HelpersType.
      Local Hint Constructors type_value : core.
      
      Lemma eval_member_types : forall errs x v v' ts τ τ',
          eval_member x v = Some v' ->
          member_type ts τ ->
          F.get x ts = Some τ' ->
          ∇ errs ⊢ v ∈ τ ->
          ∇ errs ⊢ v' ∈ τ'.
      Proof.
        intros errs x v v' ts τ τ' Heval Hmem Hget Ht;
          inv Hmem; inv Ht; unravel in *.
        - eapply F.relfs_get_r in H1 as [? ?]; eauto.
          intuition. rewrite Heval in H0; inv H0; eauto.
        - eapply F.relfs_get_r in H2 as [? ?]; eauto.
          intuition. rewrite Heval in H1; inv H1; eauto.
      Qed.
      
      Local Hint Extern 0 => bit_bounded : core.
      Local Hint Extern 0 => int_bounded : core.
      
      Lemma eval_slice_types : forall errs v v' τ hi lo w,
          eval_slice hi lo v = Some v' ->
          (lo <= hi < w)%positive ->
          numeric_width w τ ->
          ∇ errs ⊢ v ∈ τ ->
          let w' := (hi - lo + 1)%positive in
          ∇ errs ⊢ v' ∈ bit<w'>.
      Proof.
        intros errs v v' τ hi lo w Heval Hw Hnum Hv w'; subst w'.
        inv Hnum; inv Hv; unravel in *; inv Heval; auto 2.
      Qed.
      
      Lemma eval_bop_type : forall errs op τ1 τ2 τ v1 v2 v,
          bop_type op τ1 τ2 τ -> eval_bop op v1 v2 = Some v ->
          ∇ errs ⊢ v1 ∈ τ1 -> ∇ errs ⊢ v2 ∈ τ2 -> ∇ errs ⊢ v ∈ τ.
      Proof.
        intros errs op τ1 τ2 τ v1 v2 v Hbop Heval Ht1 Ht2; inv Hbop;
          repeat match goal with
                 | H: Some _ = Some _ |- _ => inv H; constructor; auto 2
                 | H: numeric _ |- _ => inv H
                 | H: numeric_width _ _ |- _ => inv H
                 | |- _ => inv Ht1; inv Ht2; unravel in *
                 | |- BitArith.bound _ _ => unfold_bit_operation; auto 2
                 | |- IntArith.bound _ _ => unfold_int_operation; auto 2
                 end; auto 2.
      Qed.
      
      Local Hint Resolve proper_inside_header_nesting : core.
      
      Lemma eval_cast_types : forall errs v v' τ τ',
          proper_cast τ τ' -> eval_cast τ' v = Some v' ->
          ∇ errs ⊢ v ∈ τ -> ∇ errs ⊢ v' ∈ τ'.
      Proof.
        intros errs v v' τ τ' Hpc Heval Ht; inv Hpc; inv Ht;
          unravel in *; try match goal with
                            | H: Some _ = Some _ |- _ => inv H
                            end; auto 2.
        - destruct b; inv Heval; constructor; cbv; auto 2.
        - destruct n; inv Heval; auto 1; destruct p; inv H0; auto 1.
        - destruct w; inv Heval; auto 2.
        - destruct w2; inv Heval; auto 2.
        - constructor. generalize dependent fs.
          induction vs as [| v vs IHvs]; intros [| [x τ] fs] H;
            inv H; unravel; constructor; unfold F.relf in *;
              unravel; try apply IHvs; auto 2.
        - constructor; unfold F.values,F.value in *.
          + apply pn_header; rewrite F.predfs_data_map; auto 1.
          + clear H0. generalize dependent fs.
            induction vs as [| v vs IHvs];
              intros [| [x τ] fs] H; inv H; constructor;
                try split; unravel; try apply IHvs; auto 2.
      Qed.
      
      Local Hint Constructors proper_nesting : core.
      Hint Rewrite repeat_length.
      Hint Rewrite app_length.
      Hint Rewrite firstn_length.
      Hint Rewrite skipn_length.
      Hint Rewrite Forall_app.
      Hint Rewrite @F.map_snd.
      Hint Rewrite @map_compose.
      Hint Rewrite (@Forall2_map_l E.t).
      Hint Rewrite (@Forall2_Forall E.t).
      Hint Rewrite @F.predfs_data_map.
      Hint Rewrite @F.relfs_split_map_iff.
      Hint Rewrite @F.map_fst.
      Local Hint Resolve Forall_impl : core.
      Local Hint Resolve vdefault_types : core.
      Local Hint Resolve Forall_firstn : core.
      Local Hint Resolve Forall_skipn : core.
      
      Lemma eval_uop_types : forall errs op τ τ' v v',
          uop_type op τ τ' -> eval_uop op v = Some v' ->
          ∇ errs ⊢ v ∈ τ -> ∇ errs ⊢ v' ∈ τ'.
      Proof.
        intros errs op τ τ' v v' Huop Heval Ht;
          inv Huop; inv Ht; unravel in *; inv Heval; auto 2;
            invert_proper_nesting;
            repeat match goal with
                   | H: Some _ = Some _ |- _ => inv H
                   | H: (if ?b then _ else _) = _ |- _ => destruct b as [? | ?]
                   end; try constructor; try (destruct n; lia); auto 2;
              autorewrite with core; try split; auto 2;
                try (apply repeat_Forall; simpl; constructor; auto 2;
                     autorewrite with core in *; split; [intuition | eauto 5]).
        - destruct (nth_error hs (Z.to_nat ni))
            as [[b vs] |] eqn:equack; inv H0; constructor; auto 2;
            apply (Forall_nth_error _ hs (Z.to_nat ni) (b, vs)) in H6; inv H6; auto 1.
      Qed.
    End HelpersType.
    
    Section HelpersExist.
      Lemma eval_slice_exists : forall errs v τ hi lo w,
        (lo <= hi < w)%positive ->
        numeric_width w τ ->
        ∇ errs ⊢ v ∈ τ ->
        exists v', eval_slice hi lo v = Some v'.
      Proof.
        intros errs v τ hi lo w Hw Hnum Hv;
          inv Hnum; inv Hv; unravel; eauto 2.
      Qed.
      
      Lemma eval_bop_exists : forall errs op τ1 τ2 τ v1 v2,
          bop_type op τ1 τ2 τ ->
          ∇ errs ⊢ v1 ∈ τ1 -> ∇ errs ⊢ v2 ∈ τ2 ->
          exists v, eval_bop op v1 v2 = Some v.
      Proof.
        intros errs op τ1 τ2 τ v1 v2 Hbop Ht1 Ht2; inv Hbop;
          repeat inv_numeric; inv Ht1; inv Ht2; unravel; eauto 2;
            try inv_numeric_width.
      Qed.
      
      Lemma eval_cast_exists : forall errs τ τ' v,
          proper_cast τ τ' -> ∇ errs ⊢ v ∈ τ -> exists v', eval_cast τ' v = Some v'.
      Proof.
        intros errs τ τ' v Hpc Ht; inv Hpc; inv Ht; unravel; eauto 2.
        - destruct b; eauto 2.
        - destruct n; eauto 2; destruct p; eauto 2;
            try (cbv in *; destruct H1; try destruct p; discriminate).
        - destruct w; eauto 2.
        - destruct w2; eauto 2.
      Qed.
      
      Lemma eval_uop_exist : forall errs op τ τ' v,
          uop_type op τ τ' -> ∇ errs ⊢ v ∈ τ -> exists v', eval_uop op v = Some v'.
      Proof.
        intros errs op τ τ' v Huop Ht; inv Huop; inv Ht;
          unravel; repeat inv_numeric; eauto 2;
            try (destruct (lt_dec (Pos.to_nat p) (Pos.to_nat n)) as [? | ?]; eauto 2).
        - assert (Hnith : (Z.to_nat ni < length hs)%nat) by lia;
            pose proof nth_error_exists _ _ Hnith as [[b vs] Hexists];
            rewrite Hexists; eauto 2.
      Qed.
      
      Lemma eval_member_exists : forall errs x v ts τ τ',
          member_type ts τ ->
          F.get x ts = Some τ' ->
          ∇ errs ⊢ v ∈ τ ->
          exists v', eval_member x v = Some v'.
      Proof.
        intros errs x v ts τ τ' Hmem Hget Ht;
          inv Hmem; inv Ht; unravel.
        - eapply F.relfs_get_r in H1 as [? ?]; eauto 2;
            intuition; eauto 2.
        - eapply F.relfs_get_r in H2 as [? ?]; eauto 2;
            intuition; eauto 2.
      Qed.
    End HelpersExist.
  End Lemmas.
End ExprUtil.

Module EnvUtil.
  Import Env.EnvNotations.

  (** Variable to Value mappings. *)
  Definition epsilon : Type := Env.t string V.v.

  (** Lookup an lvalue. *)
  Fixpoint lv_lookup (ϵ : epsilon) (lv : V.lv) : option V.v :=
    match lv with
    | l{ VAR x }l => ϵ x
    | l{ lv DOT x }l =>
      (* TODO: use monadic bind. *)
      match lv_lookup ϵ lv with
      | None => None
      | Some ~{ REC { fs } }~
      | Some ~{ HDR { fs } VALID:=_ }~ => F.get x fs
      | Some _ => None
      end
    | l{ lv[n] }l =>
      match lv_lookup ϵ lv with
      | None => None
      | Some ~{ STACK vss:_[_] NEXT:=_ }~ =>
        match nth_error vss (Z.to_nat n) with
        | None => None
        | Some (b,vs) => Some ~{ HDR { vs } VALID:=b }~
        end
      | Some _ => None
      end
    end.
  (**[]*)

  (** Updating an lvalue in an environment. *)
  Fixpoint lv_update (lv : V.lv) (v : V.v) (ϵ : epsilon) : epsilon :=
    match lv with
    | l{ VAR x }l    => !{ x ↦ v ;; ϵ }!
    | l{ lv DOT x }l =>
      match lv_lookup ϵ lv with
      | Some ~{ REC { vs } }~ => lv_update lv (V.VRecord (F.update x v vs)) ϵ
      | Some ~{ HDR { vs } VALID:=b }~ =>
        lv_update lv (V.VHeader (F.update x v vs) b) ϵ
      | Some _ | None => ϵ
      end
    | l{ lv[n] }l =>
      match v, lv_lookup ϵ lv with
      | ~{ HDR { vs } VALID:=b }~ ,
        Some ~{ STACK vss:ts[size] NEXT:=ni }~ =>
        let vss := nth_update (Z.to_nat n) (b,vs) vss in
        lv_update lv ~{ STACK vss:ts[size] NEXT:=ni }~ ϵ
      | _, Some _ | _, None => ϵ
      end
    end.
  (**[]*)

  (** Create a new environment
      from a closure environment where
      values of [In] args are substituted
      into the function parameters. *)
  Definition copy_in
             (argsv : V.argsv)
             (ϵcall : epsilon) : epsilon -> epsilon :=
    F.fold (fun x arg ϵ =>
              match arg with
              | P.PAIn v     => !{ x ↦ v ;; ϵ }!
              | P.PAInOut lv => match lv_lookup ϵcall lv with
                               | None   => ϵ
                               | Some v => !{ x ↦ v ;; ϵ }!
                               end
              | P.PAOut _    => ϵ
              end) argsv.
  (**[]*)
  
  (** Update call-site environment with
      out variables from function call evaluation. *)
  Definition copy_out
             (argsv : V.argsv)
             (ϵf : epsilon) : epsilon -> epsilon :=
    F.fold (fun x arg ϵ =>
              match arg with
              | P.PAIn _ => ϵ
              | P.PAOut lv
              | P.PAInOut lv =>
                match ϵf x with
                | None   => ϵ
                | Some v => lv_update lv v ϵ
                end
              end) argsv.
  (**[]*)

  Section InstEnv.
    Context {tags_t : Type}.

    (** Table environment. *)
    Definition tenv : Type := Env.t string (CD.table tags_t).

    (** Function declarations and closures. *)
    Inductive fdecl : Type :=
    | FDecl (closure : epsilon) (fs : fenv) (ins : ienv) (body : ST.s tags_t)
    with fenv : Type :=
    | FEnv (fs : Env.t string fdecl)
    (** Action declarations and closures *)
    with adecl : Type :=
    | ADecl (closure : epsilon) (fs : fenv) (ins : ienv) (aa : aenv) (body : ST.s tags_t)
    with aenv : Type :=
    | AEnv (aa : Env.t string adecl)
    (** Instances and Environment. *)
    with inst : Type :=
    | CInst (closure : epsilon) (fs : fenv) (ins : ienv)
            (tbls : tenv) (aa : aenv)
            (apply_blk : ST.s tags_t)  (* control instance *)
    | PInst (closure : epsilon) (fs : fenv) (ins : ienv)
            (strt : PR.state_block tags_t)
            (states : F.fs string (PR.state_block tags_t))
    | EInst (* TODO: extern object instance *)
    with ienv : Type :=
    | IEnv (ins : Env.t string inst).
    (**[]*)

    (** Function lookup. *)
    Definition lookup '(FEnv fs : fenv) : string -> option fdecl := fs.

    (** Bind a function declaration to an environment. *)
    Definition update '(FEnv fs : fenv) (x : string) (d : fdecl) : fenv :=
      FEnv !{ x ↦ d ;; fs }!.
    (**[]*)

    (** Instance lookup. *)
    Definition ilookup '(IEnv fs : ienv) : string -> option inst := fs.

    (** Bind an instance to an environment. *)
    Definition iupdate '(IEnv fs : ienv) (x : string) (d : inst) : ienv :=
      IEnv !{ x ↦ d ;; fs }!.
    (**[]*)

    (** Action lookup. *)
    Definition alookup '(AEnv aa : aenv) : string -> option adecl := aa.

    (** Bind a function declaration to an environment. *)
    Definition aupdate '(AEnv aa : aenv) (x : string) (d : adecl) : aenv :=
      AEnv !{ x ↦ d ;; aa }!.
    (**[]*)

    (** Control plane table entries,
        essentially mapping tables to an action call. *)
    Definition entries : Type :=
      list (V.v * E.matchkind) ->
      list string ->
      string * E.args tags_t.
    (**[]*)

    (** Control plane tables. *)
    Definition ctrl : Type := Env.t string entries.

    (** Control declarations and closures. *)
    Inductive cdecl : Type :=
    | CDecl (cs : cenv) (closure : epsilon) (fs : fenv) (ins : ienv)
            (body : CD.d tags_t) (apply_block : ST.s tags_t)
    with cenv : Type :=
    | CEnv (cs : Env.t string cdecl).
    (**[]*)

    (** Control lookup. *)
    Definition clookup '(CEnv cs : cenv) : string -> option cdecl := cs.

    (** Bind an instance to an environment. *)
    Definition cupdate '(CEnv cs : cenv) (x : string) (d : cdecl) : cenv :=
      CEnv !{ x ↦ d ;; cs }!.
    (**[]*)
  End InstEnv.
End EnvUtil.
