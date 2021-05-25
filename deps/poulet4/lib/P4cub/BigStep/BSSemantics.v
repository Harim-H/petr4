Set Warnings "-custom-entry-overridden".
Require Import Coq.ZArith.BinInt.
Require Export BSUtil.
Require Export Value.
Require Export Poulet4.P4cub.Envn.
Require Import BSPacket.

(** * Big-Step Evaluation *)

(** Notation entries. *)
Declare Custom Entry p4evalsignal.

(** Expression evaluation. *)
Reserved Notation "⟨ envn , e ⟩ ⇓ v"
         (at level 40, e custom p4expr, v custom p4value).

(** L-value evaluation. *)
Reserved Notation "⧠ e ⇓ lv"
         (at level 40, e custom p4expr, lv custom p4lvalue).

(** Parser-expression evaluation. *)
Reserved Notation "⦑ envn , e ⦒ ⇓ st"
         (at level 40, e custom p4prsrexpr, st custom p4prsrstate).

(** Statement evaluation. *)
Reserved Notation "⟪ pkt1 , cp , tenv , aenv , fenv , ienv , ϵ1 , s ⟫ ⤋ ⟪ ϵ2 , sig , pkt2 ⟫"
         (at level 40, s custom p4stmt,
          ϵ2 custom p4env, sig custom p4evalsignal).

(** Control-declaration evaluation. *)
Reserved Notation "⦉ ts1 , aa1 , fns , ins1 , ϵ1 , d ⦊ ⟱  ⦉ aa2 , ts2 ⦊"
         (at level 40, d custom p4ctrldecl, ts2 custom p4env, ts1 custom p4env).

(** Top-declaration evaluation. *)
Reserved Notation "⦇ cs1 , fns1 , ins1 , ϵ1 , d ⦈ ⟱  ⦇ ins2 , fns2 , cs2 ⦈"
         (at level 40, d custom p4topdecl).

(** Parser-state-machine evaluation. *)
Reserved Notation  "'Δ`' ( pkt1 , cs1 , tenv , aenv , fenv , ienv , ϵ1 , strt , states , curr ) ⇝ ⟨ ϵ2 , final , pkt2 ⟩"
         (at level 40, strt custom p4prsrstateblock,
          curr custom p4prsrstate,
          ϵ2 custom p4env,
          final custom p4prsrstate).

(** Parser-state-block evaluation. *)
Reserved Notation "'Δ' ( pkt1 , cs1 , tenv , aenv , fenv , ienv , ϵ1 , currb ) ⇝ ⟨ ϵ2 , next , pkt2 ⟩"
         (at level 40, currb custom p4prsrstateblock,
          ϵ2 custom p4env,
          next custom p4prsrstate).

Module Step.
  Export Env.EnvNotations.
  Import P.P4cubNotations.
  Import V.ValueNotations.
  Import V.LValueNotations.

  (** Statement signals. *)
  Inductive signal : Type :=
  | SIG_Cont                  (* continue *)
  | SIG_Exit                  (* exit *)
  | SIG_Rtrn (v : option V.v) (* return *)
  | SIG_Rjct                  (* reject *).

  Notation "x"
    := x (in custom p4evalsignal at level 0, x constr at level 0).
  Notation "'C'" := SIG_Cont (in custom p4evalsignal at level 0).
  Notation "'X'" := SIG_Exit (in custom p4evalsignal at level 0).
  Notation "'R' 'of' v ?"
    := (SIG_Rtrn v) (in custom p4evalsignal at level 0).
  Notation "'Void'" := (SIG_Rtrn None) (in custom p4evalsignal at level 0).
  Notation "'Fruit' v" := (SIG_Rtrn (Some v)) (in custom p4evalsignal at level 0).

  (** Evidence that control-flow
      is interrupted by an exit or return statement. *)
  Inductive interrupt : signal -> Prop :=
  | interrupt_exit : interrupt SIG_Exit
  | interrupt_rtrn (vo : option V.v) : interrupt (SIG_Rtrn vo)
  | interrupt_rjct : interrupt SIG_Rjct.
  (**[]*)

  Export ExprUtil.
  Export EnvUtil.

  (** Expression big-step semantics. *)
  Inductive expr_big_step {tags_t : Type} (ϵ : epsilon) : E.e tags_t -> V.v -> Prop :=
  (* Literals. *)
  | ebs_bool (b : bool) (i : tags_t) :
      ⟨ ϵ, BOOL b @ i ⟩ ⇓ VBOOL b
  | ebs_bit (w : positive) (n : Z) (i : tags_t) :
      ⟨ ϵ, w W n @ i ⟩ ⇓ w VW n
  | ebs_int (w : positive) (z : Z) (i : tags_t) :
      ⟨ ϵ, w S z @ i ⟩ ⇓ w VS z
  | ebs_var (x : string) (τ : E.t) (i : tags_t) (v : V.v) :
      ϵ x = Some v ->
      ⟨ ϵ, Var x:τ @ i ⟩ ⇓ v
  | ebs_slice (e : E.e tags_t) (τ : E.t) (hi lo : positive)
              (i : tags_t) (v' v : V.v) :
      eval_slice hi lo v = Some v' ->
      ⟨ ϵ, e ⟩ ⇓ v ->
      ⟨ ϵ, Slice e:τ [hi:lo] @ i ⟩ ⇓ v'
  | ebs_cast (τ : E.t) (e : E.e tags_t) (i : tags_t) (v v' : V.v) :
      eval_cast τ v = Some v' ->
      ⟨ ϵ, e ⟩ ⇓ v ->
      ⟨ ϵ, Cast e:τ @ i ⟩ ⇓ v'
  | ebs_error (err : option string) (i : tags_t) :
      ⟨ ϵ, Error err @ i ⟩ ⇓ ERROR err
  | ebs_matchkind (mk : E.matchkind) (i : tags_t) :
      ⟨ ϵ, Matchkind mk @ i ⟩ ⇓ MATCHKIND mk
  (* Unary Operations. *)
  | ebs_uop (op : E.uop) (τ : E.t) (e : E.e tags_t) (i : tags_t) (v v' : V.v) :
      eval_uop op v = Some v' ->
      ⟨ ϵ, e ⟩ ⇓ v ->
      ⟨ ϵ, UOP op e:τ @ i ⟩ ⇓ v'
  (* Binary Operations. *)
  | ebs_bop (op : E.bop) (τ1 τ2 : E.t) (e1 e2 : E.e tags_t)
            (i : tags_t) (v v1 v2 : V.v) :
      eval_bop op v1 v2 = Some v ->
      ⟨ ϵ, e1 ⟩ ⇓ v1 ->
      ⟨ ϵ, e2 ⟩ ⇓ v2 ->
      ⟨ ϵ, BOP e1:τ1 op e2:τ2 @ i ⟩ ⇓ v
  (* Structs *)
  | ebs_mem (e : E.e tags_t) (x : string) (τ : E.t)
            (i : tags_t) (v v' : V.v) :
      eval_member x v = Some v' ->
      ⟨ ϵ, e ⟩ ⇓ v ->
      ⟨ ϵ, Mem e:τ dot x @ i ⟩ ⇓ v'
  | ebs_tuple (es : list (E.e tags_t)) (i : tags_t)
              (vs : list (V.v)) :
      Forall2 (fun e v => ⟨ ϵ, e ⟩ ⇓ v) es vs ->
      ⟨ ϵ, tup es @ i ⟩ ⇓ TUPLE vs
  | ebs_rec_lit (efs : F.fs string (E.t * E.e tags_t))
                (i : tags_t) (vfs : F.fs string V.v) :
      F.relfs
        (fun te v =>
           let e := snd te in ⟨ ϵ, e ⟩ ⇓ v) efs vfs ->
      ⟨ ϵ, rec { efs } @ i ⟩ ⇓ REC { vfs }
  | ebs_hdr_lit (efs : F.fs string (E.t * E.e tags_t))
                (e : E.e tags_t) (i : tags_t) (b : bool)
                (vfs : F.fs string V.v) :
      F.relfs
        (fun te v =>
           let e := snd te in ⟨ ϵ, e ⟩ ⇓ v) efs vfs ->
      ⟨ ϵ, e ⟩ ⇓ VBOOL b ->
      ⟨ ϵ, hdr { efs } valid:=e @ i ⟩ ⇓ HDR { vfs } VALID:=b
  | ebs_hdr_stack (ts : F.fs string (E.t))
                  (hs : list (E.e tags_t))
                  (n : positive) (ni : Z) (i : tags_t)
                  (vss : list (bool * F.fs string (V.v))) :
      Forall2
        (fun e bvs =>
           let b := fst bvs in
           let vs := snd bvs in
           ⟨ ϵ, e ⟩ ⇓ HDR { vs } VALID:=b)
        hs vss ->
      ⟨ ϵ, Stack hs:ts[n] nextIndex:=ni @ i ⟩ ⇓ STACK vss:ts [n] NEXT:=ni
  | ebs_access (e : E.e tags_t) (i : tags_t)
               (n : positive) (index ni : Z)
               (ts : F.fs string (E.t))
               (vss : list (bool * F.fs string (V.v)))
               (b : bool) (vs : F.fs string (V.v)) :
      nth_error vss (Z.to_nat index) = Some (b,vs) ->
      ⟨ ϵ, e ⟩ ⇓ STACK vss:ts [n] NEXT:=ni ->
      ⟨ ϵ, Access e[index] @ i ⟩ ⇓ HDR { vs } VALID:=b
  where "⟨ ϵ , e ⟩ ⇓ v" := (expr_big_step ϵ e v).
  (**[]*)

  (** A custom induction principle for
      the expression big-step relation. *)
  Section ExprEvalInduction.
    Variable (tags_t: Type).

    Variable P : epsilon -> E.e tags_t -> V.v -> Prop.

    Hypothesis HBool : forall ϵ b i, P ϵ <{ BOOL b @ i }> ~{ VBOOL b }~.

    Hypothesis HBit : forall ϵ w n i, P ϵ <{ w W n @ i }> ~{ w VW n }~.

    Hypothesis HInt : forall ϵ w z i, P ϵ <{ w S z @ i }> ~{ w VS z }~.

    Hypothesis HVar : forall ϵ x τ i v,
        ϵ x = Some v ->
        P ϵ <{ Var x:τ @ i }> v.
    (**[]*)

    Hypothesis HSlice : forall ϵ e τ hi lo i v v',
        eval_slice hi lo v = Some v' ->
        ⟨ ϵ, e ⟩ ⇓ v ->
        P ϵ e v ->
        P ϵ <{ Slice e:τ [hi:lo] @ i }> v'.
    (**[]*)

    Hypothesis HCast : forall ϵ τ e i v v',
        eval_cast τ v = Some v' ->
        ⟨ ϵ, e ⟩ ⇓ v ->
        P ϵ e v ->
        P ϵ <{ Cast e:τ @ i }> v'.
    (**[]*)

    Hypothesis HError : forall ϵ err i, P ϵ <{ Error err @ i }> ~{ ERROR err }~.

    Hypothesis HMatchkind : forall ϵ mk i,
        P ϵ <{ Matchkind mk @ i }> ~{ MATCHKIND mk }~.
    (**[]*)

    Hypothesis HUop : forall ϵ op τ e i v v',
        eval_uop op v = Some v' ->
        ⟨ ϵ, e ⟩ ⇓ v ->
        P ϵ e v ->
        P ϵ <{ UOP op e:τ @ i }> v'.

    Hypothesis HBop : forall ϵ op τ1 τ2 e1 e2 i v v1 v2,
        eval_bop op v1 v2 = Some v ->
        ⟨ ϵ, e1 ⟩ ⇓ v1 ->
        P ϵ e1 v1 ->
        ⟨ ϵ, e2 ⟩ ⇓ v2 ->
        P ϵ e2 v2 ->
        P ϵ <{ BOP e1:τ1 op e2:τ2 @ i }> v.
    (**[]*)

    Hypothesis HMem : forall ϵ e x τ i v v',
        eval_member x v = Some v' ->
        ⟨ ϵ, e ⟩ ⇓ v ->
        P ϵ e v ->
        P ϵ <{ Mem e:τ dot x @ i }> v'.
    (**[]*)

    Hypothesis HTuple : forall ϵ es i vs,
        Forall2 (fun e v => ⟨ ϵ, e ⟩ ⇓ v) es vs ->
        Forall2 (P ϵ) es vs ->
        P ϵ <{ tup es @ i }> ~{ TUPLE vs }~.
    (**[]*)

    Hypothesis HRecLit : forall ϵ efs i vfs,
        F.relfs
          (fun te v =>
             let e := snd te in ⟨ ϵ, e ⟩ ⇓ v) efs vfs ->
        F.relfs (fun te v => let e := snd te in P ϵ e v) efs vfs ->
        P ϵ <{ rec { efs } @ i }> ~{ REC { vfs } }~.
    (**[]*)

    Hypothesis HHdrLit : forall ϵ efs e i b vfs,
        F.relfs
          (fun te v =>
             let e := snd te in ⟨ ϵ, e ⟩ ⇓ v) efs vfs ->
        F.relfs (fun te v => let e := snd te in P ϵ e v) efs vfs ->
        ⟨ ϵ, e ⟩ ⇓ VBOOL b ->
        P ϵ e ~{ VBOOL b }~ ->
        P ϵ <{ hdr { efs } valid:=e @ i }> ~{ HDR { vfs } VALID:=b }~.
    (**[]*)

    Hypothesis HHdrStack : forall ϵ ts hs n ni i vss,
        Forall2
          (fun e bvs =>
             let b := fst bvs in
             let vs := snd bvs in
             ⟨ ϵ, e ⟩ ⇓ HDR { vs } VALID:=b)
          hs vss ->
        Forall2
          (fun e bvs =>
             let b := fst bvs in
             let vs := snd bvs in
             P ϵ e ~{ HDR { vs } VALID:=b}~ )
          hs vss ->
        P ϵ <{ Stack hs:ts[n] nextIndex:=ni @ i }> ~{ STACK vss:ts[n] NEXT:=ni }~.
    (**[]*)

    Hypothesis HAccess : forall ϵ e i n index ni ts vss b vs,
        nth_error vss (Z.to_nat index) = Some (b,vs) ->
        ⟨ ϵ, e ⟩ ⇓ STACK vss:ts[n] NEXT:=ni ->
        P ϵ e ~{ STACK vss:ts[n] NEXT:=ni }~ ->
        P ϵ <{ Access e[index] @ i }> ~{ HDR { vs } VALID:=b }~.
    (**[]*)

    (** Custom induction principle for
        the expression big-step relation.
        [Do induction ?H using custom_expr_big_step_ind]. *)
    Definition custom_expr_big_step_ind :
      forall (ϵ : epsilon) (e : E.e tags_t)
        (v : V.v) (Hy : ⟨ ϵ, e ⟩ ⇓ v), P ϵ e v :=
      fix ebsind ϵ e v Hy :=
        let fix lind
                {es : list (E.e tags_t)}
                {vs : list (V.v)}
                (HR : Forall2 (fun e v => ⟨ ϵ, e ⟩ ⇓ v) es vs)
            : Forall2 (P ϵ) es vs :=
            match HR with
            | Forall2_nil _ => Forall2_nil _
            | Forall2_cons _ _ Hh Ht
              => Forall2_cons _ _ (ebsind _ _ _ Hh) (lind Ht)
            end in
        let fix fsind
                {efs : F.fs string (E.t * E.e tags_t)}
                {vfs : F.fs string (V.v)}
                (HRs : F.relfs
                         (fun te v =>
                            let e := snd te in
                            ⟨ ϵ , e ⟩ ⇓ v) efs vfs)
                : F.relfs
                    (fun te v => let e := snd te in P ϵ e v)
                    efs vfs :=
                match HRs with
                | Forall2_nil _ => Forall2_nil _
                | Forall2_cons _ _ (conj Hx Hhd) Htl
                  => Forall2_cons _ _ (conj Hx (ebsind _ _ _ Hhd)) (fsind Htl)
                end in
        let fix ffind
                {es : list (E.e tags_t)}
                {vss : list (bool * F.fs string (V.v))}
                (HRs : Forall2
                         (fun e bvs =>
                            let b := fst bvs in
                            let vs := snd bvs in
                            ⟨ ϵ, e ⟩ ⇓ HDR { vs } VALID:=b)
                         es vss)
            : Forall2
                (fun e bvs =>
                   let b := fst bvs in
                   let vs := snd bvs in
                   P ϵ e ~{ HDR { vs } VALID:=b}~ )
                es vss :=
            match HRs with
            | Forall2_nil _ => Forall2_nil _
            | Forall2_cons _ _ Hhead Htail
              => Forall2_cons _ _ (ebsind _ _ _ Hhead) (ffind Htail)
            end in
        match Hy with
        | ebs_bool _ b i => HBool ϵ b i
        | ebs_bit _ w n i => HBit ϵ w n i
        | ebs_int _ w z i => HInt ϵ w z i
        | ebs_var _ _ τ i _ Hx => HVar _ _ τ i _ Hx
        | ebs_slice _ _ _ _ _ i _ _ Hv He
          => HSlice _ _ _ _ _ i _ _ Hv He (ebsind _ _ _ He)
        | ebs_cast _ _ _ i _ _ Hv He
          => HCast _ _ _ i _ _ Hv He (ebsind _ _ _ He)
        | ebs_error _ err i => HError _ err i
        | ebs_matchkind _ mk i => HMatchkind _ mk i
        | ebs_uop _ _ _ _ i _ _ Hv He
          => HUop _ _ _ _ i _ _ Hv He (ebsind _ _ _ He)
        | ebs_bop _ _ _ _ _ _ i _ _ _ Hv He1 He2
          => HBop _ _ _ _ _ _ i _ _ _ Hv He1 (ebsind _ _ _ He1) He2 (ebsind _ _ _ He2)
        | ebs_mem _ _ _ _ i _ _ Heval He
          => HMem _ _ _ _ i _ _ Heval He (ebsind _ _ _ He)
        | ebs_tuple _ _ i _ HR => HTuple _ _ i _ HR (lind HR)
        | ebs_rec_lit _ _ i _ HR => HRecLit _ _ i _ HR (fsind HR)
        | ebs_hdr_lit _ _ _ i _ _ HR He
          => HHdrLit _ _ _ i _ _ HR (fsind HR) He (ebsind _ _ _ He)
        | ebs_hdr_stack _ _ _ n ni i _ HR
          => HHdrStack _ _ _ n ni i _ HR (ffind HR)
        | ebs_access _ _ i n index ni ts _ _ _ Hnth He
          => HAccess _ _ i n index ni ts _ _ _ Hnth He (ebsind _ _ _ He)
        end.
    (**[]*)

  End ExprEvalInduction.

  Inductive lvalue_big_step {tags_t : Type} : E.e tags_t -> V.lv -> Prop :=
  | lvbs_var (x : string) (τ : E.t) (i : tags_t) :
      ⧠ Var x:τ @ i ⇓ VAR x
  | lvbs_member (e : E.e tags_t) (x : string)
                (τ : E.t) (i : tags_t) (lv : V.lv) :
      ⧠ e ⇓ lv ->
      ⧠ Mem e:τ dot x @ i ⇓ lv DOT x
  | lvbs_access (e : E.e tags_t) (i : tags_t)
                      (lv : V.lv) (n : Z) :
      let w := 32%positive in
      ⧠ e ⇓ lv ->
      ⧠ Access e[n] @ i ⇓ lv[n]
  where "⧠ e ⇓ lv" := (lvalue_big_step e lv).
  (**[]*)

  (** Parser-expression evaluation. *)
  Inductive parser_expr_big_step
            {tags_t} (ϵ : epsilon) : PR.e tags_t -> PR.state -> Prop :=
  | pebs_goto (st : PR.state) (i : tags_t) :
      ⦑ ϵ, goto st @ i ⦒ ⇓ st
  | pebs_select (e : E.e tags_t) (def : PR.e tags_t)
                (cases : F.fs PR.pat (PR.e tags_t))
                (i : tags_t) (v : V.v) (st_def : PR.state)
                (vcases : F.fs PR.pat PR.state) :
      ⟨ ϵ, e ⟩ ⇓ v ->
      Forall2
        (fun pe ps =>
           let p := fst pe in
           let p' := fst ps in
           let e := snd pe in
           let s := snd ps in
           p = p' /\ ⦑ ϵ, e ⦒ ⇓ s)
        cases vcases ->
      ⦑ ϵ, def ⦒ ⇓ st_def ->
      let st := match F.find_value (fun p => V.ValueUtil.match_pattern p v) vcases with
                | None => st_def
                | Some st => st
                end in
      ⦑ ϵ, select e { cases } default:=def @ i ⦒ ⇓ st
  where "⦑ envn , e ⦒ ⇓ st"
          := (parser_expr_big_step envn e st).
  (**[]*)

  Section ParserExprInduction.
    Variable tags_t : Type.
    Variable P : epsilon -> PR.e tags_t -> PR.state -> Prop.

    Hypothesis HGoto : forall ϵ st i,
      P ϵ p{ goto st @ i }p st.

    Hypothesis HSelect : forall ϵ e def cases i v
                           st_def vcases,
      ⟨ ϵ, e ⟩ ⇓ v ->
      Forall2
        (fun pe ps =>
           let p := fst pe in
           let p' := fst ps in
           let e := snd pe in
           let s := snd ps in
           p = p' /\ ⦑ ϵ, e ⦒ ⇓ s)
        cases vcases ->
      Forall2 (fun pe ps =>
                 let e := snd pe in
                 let s := snd ps in
                 P ϵ e s) cases vcases ->
      ⦑ ϵ, def ⦒ ⇓ st_def ->
      P ϵ def st_def ->
      let st := match F.find_value (fun p => V.ValueUtil.match_pattern p v) vcases with
                | None => st_def
                | Some st => st
                end in
      P ϵ p{ select e { cases } default:=def @ i }p st.

    Definition custom_parser_expr_big_step_ind :
      forall (ϵ : epsilon) (e : PR.e tags_t) (st : PR.state),
        ⦑ ϵ, e ⦒ ⇓ st -> P ϵ e st :=
      fix pebsind ϵ e st H :=
        let fix cases_ind
                {cases : F.fs PR.pat (PR.e tags_t)}
                {vcases : F.fs PR.pat PR.state}
                (Hcases :
                   Forall2
                     (fun pe ps =>
                        let p := fst pe in
                        let p' := fst ps in
                        let e := snd pe in
                        let s := snd ps in
                        p = p' /\ ⦑ ϵ, e ⦒ ⇓ s)
                     cases vcases)
            : Forall2
                (fun pe ps =>
                   let e := snd pe in
                   let s := snd ps in
                   P ϵ e s) cases vcases :=
            match Hcases with
            | Forall2_nil _ => Forall2_nil _
            | Forall2_cons _ _ (conj _ Hcase) Htail
              => Forall2_cons _ _ (pebsind _ _ _ Hcase) (cases_ind Htail)
            end in
        match H with
        | pebs_goto _ st i => HGoto _ st i
        | pebs_select _ _ _ _ i _ _ _ He Hcases Hdef
          => HSelect _ _ _ _ i _ _ _ He
                    Hcases (cases_ind Hcases)
                    Hdef (pebsind _ _ _ Hdef)
        end.
    (**[]*)
  End ParserExprInduction.

  Definition get_state_block {tags_t : Type}
             (strt : PR.state_block tags_t)
             (states : F.fs string (PR.state_block tags_t))
             (curr : PR.state) : option (PR.state_block tags_t) :=
    match curr with
    | ={ start }= => Some strt
    | ={ δ x }=  => F.get x states
    | _ => None end.

  (** Statement big-step semantics. *)
  Inductive stmt_big_step
            {tags_t : Type} (pkt : Paquet.t)
            (cp : ctrl) (ts : tenv) (aa : aenv)
            (fs : fenv) (ins : ienv) (ϵ : epsilon) :
    ST.s tags_t -> epsilon -> signal -> Paquet.t -> Prop :=
  | sbs_skip (i : tags_t) :
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, skip @ i ⟫ ⤋ ⟪ ϵ, C, pkt ⟫
  | sbs_seq_cont (s1 s2 : ST.s tags_t) (i : tags_t)
                 (ϵ' ϵ'' : epsilon) (sig : signal) (pkt' pkt'' : Paquet.t) :
      ⟪ pkt, cp,  ts, aa, fs, ins, ϵ,  s1 ⟫ ⤋ ⟪ ϵ',  C, pkt' ⟫ ->
      ⟪ pkt', cp, ts, aa, fs, ins, ϵ', s2 ⟫ ⤋ ⟪ ϵ'', sig, pkt'' ⟫ ->
      ⟪ pkt,  cp, ts, aa, fs, ins, ϵ,  s1 ; s2 @ i ⟫ ⤋ ⟪ ϵ'', sig, pkt'' ⟫
  | sbs_seq_interrupt (s1 s2 : ST.s tags_t) (i : tags_t)
                      (ϵ' : epsilon) (sig : signal) (pkt' : Paquet.t) :
      interrupt sig ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, s1 ⟫ ⤋ ⟪ ϵ', sig, pkt' ⟫ ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, s1 ; s2 @ i ⟫ ⤋ ⟪ ϵ', sig, pkt' ⟫
  | sbs_block_cont (s : ST.s tags_t) (ϵ' : epsilon) (pkt' : Paquet.t) :
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, s ⟫ ⤋ ⟪ ϵ', C, pkt' ⟫ ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, b{ s }b ⟫ ⤋ ⟪ ϵ ≪ ϵ', C, pkt' ⟫
  | sbs_block_interrupt (s : ST.s tags_t) (ϵ' : epsilon)
                        (sig : signal) (pkt' : Paquet.t) :
      interrupt sig ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, s ⟫ ⤋ ⟪ ϵ', sig, pkt' ⟫ ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, b{ s }b ⟫ ⤋ ⟪ ϵ ≪ ϵ', sig, pkt' ⟫
  | sbs_vardecl (τ : E.t) (x : string)
                (i : tags_t) (v : V.v) :
      V.vdefault τ = v ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, var x : τ @ i ⟫ ⤋ ⟪ x ↦ v ;; ϵ, C, pkt ⟫
  | sbs_assign (τ : E.t) (e1 e2 : E.e tags_t) (i : tags_t)
               (lv : V.lv) (v : V.v) (ϵ' : epsilon) :
      lv_update lv v ϵ = ϵ' ->
      ⧠ e1 ⇓ lv ->
      ⟨ ϵ, e2 ⟩ ⇓ v ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, asgn e1 := e2 : τ @ i ⟫ ⤋ ⟪ ϵ', C, pkt ⟫
  | sbs_exit (i : tags_t) :
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, exit @ i ⟫ ⤋ ⟪ ϵ, X, pkt ⟫
  | sbs_retvoid (i : tags_t) :
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, returns @ i ⟫ ⤋ ⟪ ϵ, Void, pkt ⟫
  | sbs_retfruit (τ : E.t) (e : E.e tags_t)
                 (i : tags_t) (v : V.v) :
      ⟨ ϵ, e ⟩ ⇓ v ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, return e:τ @ i ⟫ ⤋ ⟪ ϵ, Fruit v, pkt ⟫
  | sbs_cond_true (guard : E.e tags_t)
                  (tru fls : ST.s tags_t) (i : tags_t)
                  (ϵ' : epsilon) (sig : signal) :
      ⟨ ϵ, guard ⟩ ⇓ TRUE ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, tru ⟫ ⤋ ⟪ ϵ', sig, pkt ⟫ ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, if guard:Bool then tru else fls @ i ⟫
        ⤋ ⟪ ϵ', sig, pkt ⟫
  | sbs_cond_false (guard : E.e tags_t)
                   (tru fls : ST.s tags_t) (i : tags_t)
                   (ϵ' : epsilon) (sig : signal) :
      ⟨ ϵ, guard ⟩ ⇓ FALSE ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, fls ⟫ ⤋ ⟪ ϵ', sig, pkt ⟫ ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, if guard:Bool then tru else fls @ i ⟫
        ⤋ ⟪ ϵ', sig, pkt ⟫
  | sbs_action_call (args : E.args tags_t)
                    (argsv : V.argsv)
                    (a : string) (i : tags_t)
                    (body : ST.s tags_t) (aclosure : aenv)
                    (fclosure : fenv) (ains : ienv)
                    (closure ϵ' ϵ'' ϵ''' : epsilon) :
      (* Looking up action. *)
      alookup aa a = Some (ADecl closure fclosure ains aclosure body) ->
      (* Argument evaluation. *)
      F.relfs
        (P.rel_paramarg
           (fun '(_,e) v  => ⟨ ϵ, e ⟩ ⇓ v)
           (fun '(_,e) lv => ⧠ e ⇓ lv))
        args argsv ->
      (* Copy-in. *)
      copy_in argsv ϵ closure = ϵ' ->
      (* Action evaluation *)
      ⟪ pkt, cp, ts, aclosure, fclosure, ains, ϵ', body ⟫ ⤋ ⟪ ϵ'', Void, pkt ⟫ ->
      (* Copy-out *)
      copy_out argsv ϵ'' ϵ = ϵ''' ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, calling a with args @ i ⟫ ⤋ ⟪ ϵ''', C, pkt ⟫
  | sbs_void_call (args : E.args tags_t)
                  (argsv : V.argsv)
                  (f : string) (i : tags_t)
                  (body : ST.s tags_t) (fclosure : fenv) (fins : ienv)
                  (closure ϵ' ϵ'' ϵ''' : epsilon) :
      (* Looking up function. *)
      lookup fs f = Some (FDecl closure fclosure fins body) ->
      (* Argument evaluation. *)
      F.relfs
        (P.rel_paramarg
           (fun '(_,e) v  => ⟨ ϵ, e ⟩ ⇓ v)
           (fun '(_,e) lv => ⧠ e ⇓ lv))
        args argsv ->
      (* Copy-in. *)
      copy_in argsv ϵ closure = ϵ' ->
      (* Function evaluation *)
      ⟪ pkt, cp, ts, aa, fclosure, fins, ϵ', body ⟫ ⤋ ⟪ ϵ'', Void, pkt ⟫ ->
      (* Copy-out *)
      copy_out argsv ϵ'' ϵ = ϵ''' ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, call f with args @ i ⟫ ⤋ ⟪ ϵ''', C, pkt ⟫
  | sbs_fruit_call (args : E.args tags_t)
                   (argsv : V.argsv)
                   (f : string) (τ : E.t)
                   (e : E.e tags_t) (i : tags_t)
                   (v : V.v) (lv : V.lv)
                   (body : ST.s tags_t) (fclosure : fenv) (fins : ienv)
                   (closure ϵ' ϵ'' ϵ''' ϵ'''' : epsilon) :
      (* Looking up function. *)
      lookup fs f = Some (FDecl closure fclosure fins body) ->
      (* Argument evaluation. *)
      F.relfs
        (P.rel_paramarg
           (fun '(_,e) v => ⟨ ϵ, e ⟩ ⇓ v)
           (fun '(_,e) lv => ⧠ e ⇓ lv))
        args argsv ->
      (* Copy-in. *)
      copy_in argsv ϵ closure = ϵ' ->
      (* Lvalue Evaluation. *)
      ⧠ e ⇓ lv ->
      (* Function evaluation. *)
      ⟪ pkt, cp, ts, aa, fclosure, fins, ϵ', body ⟫ ⤋ ⟪ ϵ'', Fruit v, pkt ⟫ ->
      (* Copy-out. *)
      copy_out argsv ϵ'' ϵ = ϵ''' ->
      (* Assignment to lvalue. *)
      lv_update lv v ϵ''' = ϵ'''' ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ,
        let e:τ := call f with args @ i ⟫ ⤋ ⟪ ϵ'''', C, pkt ⟫
  | sbs_ctrl_apply (args : E.args tags_t)
                   (argsv : V.argsv)
                   (x : string) (i : tags_t)
                   (body : ST.s tags_t) (fclosure : fenv) (iins : ienv)
                   (tblclosure : tenv) (aclosure : aenv)
                   (closure ϵ' ϵ'' ϵ''' : epsilon) (pkt' : Paquet.t) :
      (* Instance lookup. *)
      ilookup ins x = Some (CInst closure fclosure iins tblclosure aclosure body) ->
      (* Argument evaluation. *)
      F.relfs
        (P.rel_paramarg
           (fun '(_,e) v => ⟨ ϵ, e ⟩ ⇓ v)
           (fun '(_,e) lv => ⧠ e ⇓ lv))
        args argsv ->
      (* Copy-in. *)
      copy_in argsv ϵ closure = ϵ' ->
      (* Apply block evaluation. *)
      ⟪ pkt, cp, tblclosure, aclosure, fclosure, iins, ϵ', body ⟫ ⤋ ⟪ ϵ'', Void, pkt' ⟫ ->
      (* Copy-out. *)
      copy_out argsv ϵ'' ϵ = ϵ''' ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, apply x with args @ i ⟫ ⤋ ⟪ ϵ''', C, pkt' ⟫
  | sbs_prsr_accept_apply (args : E.args tags_t)
                          (argsv : V.argsv)
                          (x : string) (i : tags_t)
                          (strt : PR.state_block tags_t)
                          (states : F.fs string (PR.state_block tags_t))
                          (fclosure : fenv) (iins : ienv)
                          (closure ϵ' ϵ'' ϵ''' : epsilon) (pkt' : Paquet.t) :
      (* Instance lookup *)
      ilookup ins x = Some (PInst closure fclosure iins strt states) ->
      (* Argument evaluation *)
      F.relfs
        (P.rel_paramarg
           (fun '(_,e) v => ⟨ ϵ, e ⟩ ⇓ v)
           (fun '(_,e) lv => ⧠ e ⇓ lv))
        args argsv ->
      (* Copy-in *)
      copy_in argsv ϵ closure = ϵ' ->
      (* state machine evaluation *)
      Δ` (pkt, cp, ts, aa, fs, ins, ϵ', strt, states, ={start}=)
       ⇝ ⟨ϵ'', ={accept}=, pkt'⟩ ->
      (* copy-out *)
      copy_out argsv ϵ'' ϵ = ϵ''' ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, apply x with args @ i ⟫ ⤋ ⟪ ϵ''', C, pkt' ⟫
  | sbs_prsr_reject_apply (args : E.args tags_t)
                          (argsv : V.argsv)
                          (x : string) (i : tags_t)
                          (strt : PR.state_block tags_t)
                          (states : F.fs string (PR.state_block tags_t))
                          (fclosure : fenv) (iins : ienv)
                          (closure ϵ' ϵ'' ϵ''' : epsilon) (pkt' : Paquet.t) :
      (* Instance lookup *)
      ilookup ins x = Some (PInst closure fclosure iins strt states) ->
      (* Argument evaluation *)
      F.relfs
        (P.rel_paramarg
           (fun '(_,e) v => ⟨ ϵ, e ⟩ ⇓ v)
           (fun '(_,e) lv => ⧠ e ⇓ lv))
        args argsv ->
      (* Copy-in *)
      copy_in argsv ϵ closure = ϵ' ->
      (* state machine evaluation *)
      Δ` (pkt, cp, ts, aa, fs, ins, ϵ', strt, states, ={start}=) ⇝ ⟨ϵ'', reject, pkt'⟩ ->
      (* copy-out *)
      copy_out argsv ϵ'' ϵ = ϵ''' ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, apply x with args @ i ⟫ ⤋ ⟪ ϵ''', SIG_Rjct, pkt' ⟫
  | sbs_invoke (x : string) (i : tags_t)
               (es : entries)
               (ky : list (E.t * E.e tags_t * E.matchkind))
               (acts : list (string))
               (vky : list (V.v * E.matchkind))
               (a : string) (args : E.args tags_t)
               (ϵ' : epsilon)
               (sig : signal) :
      cp x = Some es ->
      ts x = Some (CD.Table ky acts) ->
      Forall2 (fun '(_,k,_) '(v,_) => ⟨ ϵ, k ⟩ ⇓ v) ky vky ->
      (* Black box, need extra assumption for soundness *)
      es vky acts = (a,args) ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, calling a with args @ i ⟫ ⤋ ⟪ ϵ', sig, pkt ⟫ ->
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, invoke x @ i ⟫ ⤋ ⟪ ϵ', sig, pkt ⟫
  where "⟪ pkt1 , cp , ts , aa , fs , ins , ϵ , s ⟫ ⤋ ⟪ ϵ' , sig , pkt2 ⟫"
          := (stmt_big_step pkt1 cp ts aa fs ins ϵ s ϵ' sig pkt2)

  with bigstep_state_machine
         {tags_t : Type} (pkt : Paquet.t)
         (cp : ctrl) (ts : tenv) (aa : aenv) (fs : fenv)
         (ins : ienv) (ϵ : epsilon) :
         PR.state_block tags_t -> (F.fs string (PR.state_block tags_t)) ->
         PR.state -> epsilon -> PR.state -> Paquet.t -> Prop :=
  | bsm_accept (strt : PR.state_block tags_t)
               (states : F.fs string (PR.state_block tags_t))
               (curr : PR.state) (currb : PR.state_block tags_t)
               (ϵ' : epsilon) (pkt' : Paquet.t) :
      get_state_block strt states curr = Some currb ->
      Δ (pkt, cp, ts, aa, fs, ins, ϵ, currb) ⇝ ⟨ϵ', accept, pkt'⟩ ->
      Δ` (pkt, cp, ts, aa, fs, ins, ϵ, strt, states, curr) ⇝ ⟨ϵ', accept, pkt'⟩
  | bsm_reject (strt : PR.state_block tags_t)
               (states : F.fs string (PR.state_block tags_t))
               (curr : PR.state) (currb : PR.state_block tags_t)
               (ϵ' : epsilon) (pkt' : Paquet.t) :
      get_state_block strt states curr = Some currb ->
      Δ (pkt, cp, ts, aa, fs, ins, ϵ, currb) ⇝ ⟨ϵ', reject, pkt'⟩ ->
      Δ` (pkt, cp, ts, aa, fs, ins, ϵ, strt, states, curr) ⇝ ⟨ϵ', reject, pkt'⟩
  | bsm_continue (strt : PR.state_block tags_t)
                 (states : F.fs string (PR.state_block tags_t))
                 (curr : PR.state) (currb : PR.state_block tags_t)
                 (next : PR.state) (final : PR.state)
                 (ϵ' ϵ'' : epsilon) (pkt' pkt'' : Paquet.t) :
      get_state_block strt states curr = Some currb ->
      Δ (pkt, cp, ts, aa, fs, ins, ϵ, currb) ⇝ ⟨ϵ', next, pkt'⟩ ->
      Δ` (pkt', cp, ts, aa, fs, ins, ϵ', strt, states, next) ⇝ ⟨ϵ'', final, pkt''⟩ ->
      Δ` (pkt, cp, ts, aa, fs, ins, ϵ, strt, states, curr) ⇝ ⟨ ϵ'', final, pkt''⟩
  where  "'Δ`' ( pkt1 , cs1 , tenv , aenv , fenv , ienv , ϵ1 , strt , states , curr ) ⇝ ⟨ ϵ2 , final , pkt2 ⟩"
           := (bigstep_state_machine
                 pkt1 cs1 tenv aenv fenv ienv ϵ1 strt states curr ϵ2 final pkt2)

  with bigstep_state_block
         {tags_t : Type} (pkt : Paquet.t)
         (cp : ctrl) (ts : tenv) (aa : aenv) (fs : fenv)
         (ins : ienv) (ϵ : epsilon) :
         PR.state_block tags_t -> epsilon -> PR.state -> Paquet.t -> Prop :=
  | bsb_reject (s : ST.s tags_t) (e : PR.e tags_t)
               (ϵ' : epsilon) (pkt' : Paquet.t) :
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, s ⟫ ⤋ ⟪ ϵ', SIG_Rjct, pkt' ⟫ ->
      Δ (pkt, cp, ts, aa, fs, ins, ϵ, &{ state{s} transition e }&) ⇝ ⟨ϵ', reject, pkt'⟩
  | bsb_cont (s : ST.s tags_t) (e : PR.e tags_t)
             (st : PR.state) (ϵ' : epsilon) (pkt' : Paquet.t) :
      ⟪ pkt, cp, ts, aa, fs, ins, ϵ, s ⟫ ⤋ ⟪ ϵ', C, pkt' ⟫ ->
      ⦑ ϵ', e ⦒ ⇓ st ->
      Δ (pkt, cp, ts, aa, fs, ins, ϵ, &{ state{s} transition e }&) ⇝ ⟨ϵ', st, pkt'⟩
  where "'Δ' ( pkt1 , cs1 , tenv , aenv , fenv , ienv , ϵ1 , currb ) ⇝ ⟨ ϵ2 , next , pkt2 ⟩"
  := (bigstep_state_block pkt1 cs1 tenv aenv fenv ienv ϵ1 currb ϵ2 next pkt2).


  (** Control declaration big-step semantics. *)
  Inductive ctrldecl_big_step
            {tags_t : Type} (tbls : tenv) (aa : aenv)
            (fns : fenv) (ins : ienv) (ϵ : epsilon)
    : CD.d tags_t -> aenv -> tenv -> Prop :=
  | cdbs_action (a : string) (params : E.params)
                (body : ST.s tags_t) (i : tags_t) :
      let aa' := aupdate aa a (ADecl ϵ fns ins aa body) in
      ⦉ tbls, aa, fns, ins, ϵ, action a (params) {body} @ i ⦊
        ⟱  ⦉ aa', tbls ⦊
  | cdbs_table (t : string)
               (kys : list
                        (E.t * E.e tags_t * E.matchkind))
               (actns : list (string))
               (i : tags_t) :
      let tbl := CD.Table kys actns in
      ⦉ tbls, aa, fns, ins, ϵ, table t key:=kys actions:=actns @ i ⦊
        ⟱  ⦉ aa, t ↦ tbl;; tbls ⦊
  | cdbs_seq (d1 d2 : CD.d tags_t) (i : tags_t)
             (aa' aa'' : aenv) (tbls' tbls'' : tenv) :
      ⦉ tbls,  aa,  fns, ins, ϵ, d1 ⦊ ⟱  ⦉ aa',  tbls'  ⦊ ->
      ⦉ tbls', aa', fns, ins, ϵ, d2 ⦊ ⟱  ⦉ aa'', tbls'' ⦊ ->
      ⦉ tbls,  aa,  fns, ins, ϵ, d1 ;c; d2 @ i ⦊
        ⟱  ⦉ aa'', tbls'' ⦊
  where "⦉ ts1 , aa1 , fns , ins1 , ϵ1 , d ⦊ ⟱  ⦉ aa2 , ts2 ⦊"
          := (ctrldecl_big_step ts1 aa1 fns ins1 ϵ1 d aa2 ts2).
  (**[]*)

  Module TP := P.TopDecl.
  
  (** Top-level declaration big-step semantics. *)
  Inductive topdecl_big_step
            {tags_t : Type} (cs : cenv)
            (fns : fenv) (ins : ienv) (ϵ : epsilon)
    : TP.d tags_t -> ienv -> fenv -> cenv -> Prop :=
  | dbs_instantiate (c : string) (x : string)
                    (cargs : E.constructor_args tags_t)
                    (vargs : F.fs string (either (V.v) inst)) (i : tags_t)
                    (ctrlclosure : cenv) (fclosure : fenv)
                    (iclosure ins' : ienv)
                    (body : CD.d tags_t) (applyblk : ST.s tags_t)
                    (closure ϵ' ϵ'' : epsilon) (tbls : tenv) (aa : aenv) :
      clookup cs c = Some (CDecl ctrlclosure closure fclosure iclosure body applyblk) ->
      F.relfs
        (fun carg v =>
           match carg,v with
           | E.CAExpr e, Left v => ⟨ ϵ, e ⟩ ⇓ v
           | E.CAName c, Right cinst => ilookup ins c = Some cinst
           | _, _ => False
           end) cargs vargs ->
      F.fold (fun x v '(ϵ,ins) =>
                match v with
                | Left v => (!{ x ↦ v;; ϵ }!, ins)
                | Right cinst => (ϵ, iupdate ins x cinst)
                end) vargs (closure,iclosure) = (ϵ',ins') ->
      let ae := AEnv !{ ∅ }! in
      ⦉ ∅, ae, fclosure, ins', ϵ', body ⦊ ⟱  ⦉ aa, tbls ⦊ ->
      let ins'' := iupdate ins x (CInst ϵ'' fclosure ins' tbls aa applyblk) in
      ⦇ cs, fns, ins, ϵ, Instance x of c(cargs) @ i ⦈ ⟱  ⦇ ins'', fns, cs ⦈
  | tpbs_control (c : string) (cparams : E.constructor_params)
                 (params : E.params) (body : CD.d tags_t)
                 (apply_blk : ST.s tags_t) (i : tags_t) (cs' : @cenv tags_t) :
      let cs' := cupdate cs c (CDecl cs ϵ fns ins body apply_blk) in
      ⦇ cs, fns, ins, ϵ,
        control c (cparams)(params) apply { apply_blk } where { body } @ i ⦈
        ⟱  ⦇ ins, fns, cs' ⦈
  | tpbs_fruit_function (f : string) (params : E.params)
                        (τ : E.t) (body : ST.s tags_t) (i : tags_t) :
      let fns' := update fns f (FDecl ϵ fns ins body) in
      ⦇ cs, fns, ins, ϵ, fn f (params) -> τ { body } @ i ⦈
        ⟱  ⦇ ins, fns', cs ⦈
  | tpbs_void_function (f : string) (params : E.params)
                       (body : ST.s tags_t) (i : tags_t) :
      let fns' := update fns f (FDecl ϵ fns ins body) in
      ⦇ cs, fns, ins, ϵ, void f (params) { body } @ i ⦈
        ⟱  ⦇ ins, fns', cs ⦈
  | tpbs_seq (d1 d2 : TP.d tags_t) (i : tags_t)
             (ins' ins'' : ienv) (fns' fns'' : fenv) (cs' cs'' : cenv) :
      ⦇ cs,  fns,  ins,  ϵ, d1 ⦈ ⟱  ⦇ ins',  fns',  cs'  ⦈ ->
      ⦇ cs', fns', ins', ϵ, d2 ⦈ ⟱  ⦇ ins'', fns'', cs'' ⦈ ->
      ⦇ cs,  fns,  ins,  ϵ, d1 ;%; d2 @ i ⦈ ⟱  ⦇ ins'', fns'', cs'' ⦈
  where "⦇ cs1 , fns1 , ins1 , ϵ1 , d ⦈ ⟱  ⦇ ins2 , fns2 , cs2 ⦈"
          := (topdecl_big_step cs1 fns1 ins1 ϵ1 d ins2 fns2 cs2).
  (**[]*)
End Step.
