Require Export Poulet4.Semantics Poulet4.LightTyping.Utility
        Poulet4.Value Coq.micromega.Lia Poulet4.Utils
        Poulet4.Monads.Monad Poulet4.Monads.Option.

Lemma split_inj : forall (U V : Type) (uvs₁ uvs₂ : list (U * V)),
    split uvs₁ = split uvs₂ -> uvs₁ = uvs₂.
Proof.
  intros U V usv1;
    induction usv1 as [| [u1 v1] usv1 IHusv1];
    intros [| [u2 v2] usv2] H;
    simpl in *; auto.
  - destruct (split usv2) as [us2 vs2] eqn:H2; inversion H.
  - destruct (split usv1) as [us1 vs1] eqn:H1; inversion H.
  - specialize IHusv1 with usv2.
    destruct (split usv1) as [us1 vs1] eqn:H1;
      destruct (split usv2) as [us2 vs2] eqn:H2.
    inversion H; subst; f_equal; auto.
Qed.

Lemma map_pat_combine : forall (T U V W: Type) (f : T -> V) (g : U -> W) tus,
    map (fun '(t,u) => (f t, g u)) tus =
    combine (map f (map fst tus)) (map g (map snd tus)).
Proof.
  intros T U V W f g tus;
    induction tus as [| [t u] tus IHtus];
    simpl; f_equal; auto.
Qed.

(** Predicate that a
    [read_one_bit] relation
    is productive. *)
Definition read_one_bit_reads
           {U V : Type}
           (read_one_bit : U -> V -> Prop) : Prop :=
  forall u, exists v, read_one_bit u v.

(** Relation that a
    [read_one_bit] is an inverse
    with respect to [f]. *)
Definition read_one_bit_inverse
           {U V : Type}
           (read_one_bit : U -> V -> Prop) (f : V -> U -> Prop) : Prop :=
  forall u v, read_one_bit u v <-> f v u.

Section ValueTyping.
  Context {tags_t : Type}.

  Notation typ := (@P4Type tags_t).

  Section Val.
    Context {A : Type}.
    Notation V := (@ValueBase A).
    
    Inductive val_typ : V -> typ -> Prop :=
    | typ_null :
        val_typ ValBaseNull TypVoid
    | typ_bool : forall b,
        val_typ (ValBaseBool b) TypBool
    | typ_integer : forall v,
        val_typ (ValBaseInteger v) TypInteger
    | typ_bit : forall v,
        val_typ (ValBaseBit v) (TypBit (N.of_nat (length v)))
    | typ_int : forall v,
        val_typ (ValBaseInt v) (TypInt (N.of_nat (length v)))
    | typ_varbit : forall n v,
        length v <= N.to_nat n ->
        val_typ (ValBaseVarbit n v) (TypVarBit n)
    | typ_string : forall s,
        val_typ (ValBaseString s) TypString
    | typ_tuple : forall vs ts,
        Forall2 val_typ vs ts ->
        val_typ (ValBaseTuple vs) (TypTuple ts)
    | typ_error : forall err,
        val_typ (ValBaseError err) TypError
    | typ_matchkind : forall mk,
        val_typ (ValBaseMatchKind mk) TypMatchKind
    | typ_struct : forall vs ts,
        AList.all_values val_typ vs (P4String.clear_AList_tags ts) ->
        val_typ (ValBaseStruct vs) (TypStruct ts)
    | typ_header : forall b vs ts,
        AList.all_values val_typ vs (P4String.clear_AList_tags ts) ->
        val_typ (ValBaseHeader vs b) (TypHeader ts)
    | typ_union : forall vs ts,
        AList.all_values val_typ vs (P4String.clear_AList_tags ts) ->
        val_typ (ValBaseUnion vs) (TypHeaderUnion ts)
    | typ_stack : forall n vs ts,
        Forall (fun v => val_typ v (TypHeader ts)) vs ->
        val_typ (ValBaseStack vs n) (TypArray (TypHeader ts) (N.of_nat (length vs)))
    | typ_enumfield : forall ename member members,
        List.In member members ->
        val_typ
          (ValBaseEnumField (P4String.str ename) (P4String.str member))
          (TypEnum ename None members)
    | typ_senumfield : forall ename v t fields,
        val_typ v t ->
        val_typ
          (ValBaseSenumField (P4String.str ename) v)
          (TypEnum ename (Some t) fields).

    Section ValTypInd.
      Variable P : V -> typ -> Prop.

      Hypothesis HNull : P ValBaseNull TypVoid.
      Hypothesis HBool : forall b, P (ValBaseBool b) TypBool.
      Hypothesis HInteger : forall z, P (ValBaseInteger z) TypInteger.
      Hypothesis HBit : forall bits,
          P (ValBaseBit bits) (TypBit (N.of_nat (length bits))).
      Hypothesis HInt : forall bits,
          P (ValBaseInt bits) (TypInt (N.of_nat (length bits))).
      Hypothesis HVarbit : forall n bits,
          length bits <= N.to_nat n ->
          P (ValBaseVarbit n bits) (TypVarBit n).
      Hypothesis HString : forall s,
          P (ValBaseString s) TypString.
      Hypothesis HTuple : forall vs ts,
          Forall2 val_typ vs ts ->
          Forall2 P vs ts ->
          P (ValBaseTuple vs) (TypTuple ts).
      Hypothesis HError : forall err,
          P (ValBaseError err) TypError.
      Hypothesis HMatchkind : forall mk,
          P (ValBaseMatchKind mk) TypMatchKind.
      Hypothesis HStruct : forall vs ts,
          AList.all_values val_typ vs (P4String.clear_AList_tags ts) ->
          AList.all_values P vs (P4String.clear_AList_tags ts) ->
          P (ValBaseStruct vs) (TypStruct ts).
      Hypothesis HHeader : forall b vs ts,
          AList.all_values val_typ vs (P4String.clear_AList_tags ts) ->
          AList.all_values P vs (P4String.clear_AList_tags ts) ->
          P (ValBaseHeader vs b) (TypHeader ts).
      Hypothesis HUnion : forall vs ts,
          AList.all_values val_typ vs (P4String.clear_AList_tags ts) ->
          AList.all_values P vs (P4String.clear_AList_tags ts) ->
          P (ValBaseUnion vs) (TypHeaderUnion ts).
      Hypothesis HStack : forall n vs ts,
          Forall (fun v => val_typ v (TypHeader ts)) vs ->
          Forall (fun v => P v (TypHeader ts)) vs ->
          P (ValBaseStack vs n) (TypArray (TypHeader ts) (N.of_nat (length vs))).
      Hypothesis HEnum : forall ename member members,
          List.In member members ->
          P
            (ValBaseEnumField (P4String.str ename) (P4String.str member))
            (TypEnum ename None members).
      Hypothesis HSenum : forall ename v t fields,
          val_typ v t ->
          P v t ->
          P
            (ValBaseSenumField (P4String.str ename) v)
            (TypEnum ename (Some t) fields).

      Definition custom_val_typ_ind :
        forall (v : V) (t : typ), val_typ v t -> P v t :=
        fix vtind (v : V) (t : typ) (H : val_typ v t) : P v t :=
          let fix lind {vs : list V} {ts : list typ}
                  (H : Forall2 val_typ vs ts)
              : Forall2 P vs ts :=
              match H with
              | Forall2_nil _ => Forall2_nil _
              | Forall2_cons _ _ Hh Ht =>
                Forall2_cons _ _ (vtind _ _ Hh) (lind Ht)
              end in
          let fix alind
                  {vs : AList.AList String.string V _}
                  {ts : AList.AList String.string typ _}
                  (H : AList.all_values val_typ vs ts)
              : AList.all_values P vs ts :=
              match H with
              | Forall2_nil _ => Forall2_nil _
              | Forall2_cons _ _ (conj Hx Hh) Ht =>
                Forall2_cons _ _ (conj Hx (vtind _ _ Hh)) (alind Ht)
              end in
          let fix same_typ_ind {vs : list V} {t : typ}
                  (H : Forall (fun v => val_typ v t) vs)
              : Forall (fun v => P v t) vs :=
              match H with
              | Forall_nil _ => Forall_nil _
              | Forall_cons _ Hh Ht =>
                Forall_cons _ (vtind _ _ Hh) (same_typ_ind Ht)
              end in
          match H with
          | typ_null => HNull
          | typ_bool b => HBool b
          | typ_integer z => HInteger z
          | typ_bit bits => HBit bits
          | typ_int bits => HInt bits
          | typ_varbit _ _ H => HVarbit _ _ H
          | typ_string s => HString s
          | typ_tuple _ _ H => HTuple _ _ H (lind H)
          | typ_error err => HError err
          | typ_matchkind mk => HMatchkind mk
          | typ_struct _ _ H => HStruct _ _ H (alind H)
          | typ_header b _ _ H => HHeader b _ _ H (alind H)
          | typ_union _ _ H => HUnion _ _ H (alind H)
          | typ_stack n _ _ H => HStack n _ _ H (same_typ_ind H)
          | typ_enumfield x _ _ H => HEnum x _ _ H
          | typ_senumfield X _ _ ms Hv =>
            HSenum X _ _ ms Hv (vtind _ _ Hv)
          end.
    End ValTypInd.
  End Val.

  Section RelTyp.
    Context {A B : Type}.
    Notation VA := (@ValueBase A).
    Notation VB := (@ValueBase B).

    Local Hint Constructors val_typ : core.
    
    Section Map.
      Variable (f : A -> B).
      
      Lemma ValueBaseMap_preserves_type : forall v t,
          val_typ v t ->
          val_typ
            (ValueBaseMap f v) t.
      Proof.
        intros v t Hv;
          induction Hv using @custom_val_typ_ind;
          simpl in *; auto.
        - replace (length bits)
            with (length (map f bits))
            by (rewrite map_length; reflexivity); auto.
        - replace (length bits)
            with (length (map f bits))
            by (rewrite map_length; reflexivity); auto.
        - constructor; rewrite map_length; auto.
        - rewrite Forall2_map_l in H0; auto.
        - constructor.
          unfold AList.all_values in *.
          rewrite Forall2_conj in *;
            destruct H0 as [Hnames Hvts]; split.
          + clear Hvts.
            rewrite Forall2_map_both in *.
            rewrite map_fst_map, map_id.
            assumption.
          + clear Hnames.
            rewrite Forall2_map_both, map_snd_map,
            map_map, <- Forall2_map_both.
            assumption.
        - constructor.
          unfold AList.all_values in *.
          rewrite Forall2_conj in *;
            destruct H0 as [Hnames Hvts]; split.
          + clear Hvts.
            rewrite Forall2_map_both in *.
            rewrite map_fst_map, map_id.
            assumption.
          + clear Hnames.
            rewrite Forall2_map_both, map_snd_map,
            map_map, <- Forall2_map_both.
            assumption.
        - constructor.
          unfold AList.all_values in *.
          rewrite Forall2_conj in *;
            destruct H0 as [Hnames Hvts]; split.
          + clear Hvts.
            rewrite Forall2_map_both in *.
            rewrite map_fst_map, map_id.
            assumption.
          + clear Hnames.
            rewrite Forall2_map_both, map_snd_map,
            map_map, <- Forall2_map_both.
            assumption.
        - replace (length vs)
            with (length (map (ValueBaseMap f) vs))
            by (rewrite map_length; reflexivity).
          constructor.
          rewrite Forall_map.
          unfold Basics.compose.
          assumption.
      Qed.
    End Map.

    Section Rel.
      Variable (R : A -> B -> Prop).

      Local Hint Resolve Forall2_forall_impl_Forall2 : core.
      Local Hint Resolve Forall2_forall_specialize : core.
      Local Hint Resolve Forall2_impl : core.
      Local Hint Resolve in_combine_l : core.
      Local Hint Resolve nth_error_in_combine : core.
      Local Hint Resolve Forall2_length : core.
      
      Lemma exec_val_preserves_typ : forall va vb,
          exec_val R va vb ->
          forall t, val_typ va t -> val_typ vb t.
      Proof.
        intros va vb Hev.
        induction Hev using custom_exec_val_ind;
          intros t Hvat; inversion Hvat; clear Hvat; subst; eauto.
        - apply Forall2_length in H; rewrite H; auto.
        - apply Forall2_length in H; rewrite H; auto.
        - apply Forall2_length in H; rewrite H in H3; auto.
        - constructor.
          unfold AList.all_values in *.
          rewrite Forall2_conj in *.
          destruct H0 as [Habkeys Habtyps].
          destruct H2 as [Hakeys Hatyps].
          rewrite Forall2_map_both in *.
          pose proof Forall2_map_both
               _ _ _ _ (fun va vb => forall t, val_typ va t -> val_typ vb t)
               snd snd kvas kvbs as H';
            cbn in *; apply H' in Habtyps; clear H'.
          rewrite Forall2_eq in *; rewrite <- Habkeys.
          rewrite Forall2_map_both; split; eauto.
        - constructor.
          unfold AList.all_values in *.
          rewrite Forall2_conj in *.
          destruct H1 as [Habkeys Habtyps].
          destruct H5 as [Hakeys Hatyps].
          rewrite Forall2_map_both in *.
          pose proof Forall2_map_both
               _ _ _ _ (fun va vb => forall t, val_typ va t -> val_typ vb t)
               snd snd kvas kvbs as H';
            cbn in *; apply H' in Habtyps; clear H'.
          rewrite Forall2_eq in *; rewrite <- Habkeys.
          rewrite Forall2_map_both; split; eauto.
        - constructor.
          unfold AList.all_values in *.
          rewrite Forall2_conj in *.
          destruct H0 as [Habkeys Habtyps].
          destruct H2 as [Hakeys Hatyps].
          rewrite Forall2_map_both in *.
          pose proof Forall2_map_both
               _ _ _ _ (fun va vb => forall t, val_typ va t -> val_typ vb t)
               snd snd kvas kvbs as H';
            cbn in *; apply H' in Habtyps; clear H'.
          rewrite Forall2_eq in *; rewrite <- Habkeys.
          rewrite Forall2_map_both; split; eauto.
        - apply Forall2_length in H.
          apply Forall2_length in H0 as Hlen; rewrite Hlen; clear Hlen.
          constructor; try lia.
          apply Forall2_forall_specialize with (t := TypHeader ts) in H0.
          rewrite Forall_forall in *.
          rewrite Forall2_forall in H0.
          destruct H0 as [Hlen Hcomb].
          intros vb Hinvbs.
          apply In_nth_error in Hinvbs as Hnthvbs.
          destruct Hnthvbs as [n Hnthvbs].
          assert (Hnthvas: exists va, nth_error vas n = Some va).
          { apply ListUtil.nth_error_exists.
            rewrite Hlen, <- nth_error_Some, Hnthvbs; discriminate. }
          destruct Hnthvas as [va Hnthvas]. eauto 6.
      Qed.

      Local Hint Constructors exec_val : core.
      Hint Rewrite map_length : core.
      
      Lemma exec_val_exists :
        read_one_bit_reads R ->
        forall (va : VA), exists vb, exec_val R va vb.
      Proof.
        intros HR va.
        induction va using @custom_ValueBase_ind; eauto.
        - unfold read_one_bit_reads in HR.
          specialize HR with b. firstorder eauto.
        - unfold read_one_bit_reads in HR.
          assert (forall a, List.In a n -> exists b, R a b) by firstorder eauto.
          rewrite <- Forall_forall, Forall_exists_factor in H.
          firstorder eauto.
        - unfold read_one_bit_reads in HR.
          assert (forall a, List.In a z -> exists b, R a b) by firstorder eauto.
          rewrite <- Forall_forall, Forall_exists_factor in H.
          firstorder eauto.
        - unfold read_one_bit_reads in HR.
          assert (forall a, List.In a n -> exists b, R a b) by firstorder eauto.
          rewrite <- Forall_forall, Forall_exists_factor in H.
          firstorder eauto.
        - rewrite Forall_exists_factor in H.
          firstorder eauto.
        - rewrite Forall_snd, Forall_exists_factor in H.
          destruct H as [bs Hbs].
          exists (ValBaseStruct (combine (map fst vs) bs)).
          constructor. unfold AList.all_values.
          rewrite Forall2_conj.
          split; rewrite Forall2_map_both.
          + rewrite Forall2_eq.
            rewrite map_fst_combine;
              autorewrite with core; eauto.
          + rewrite Forall2_map_l in Hbs.
            rewrite map_snd_combine;
              autorewrite with core; eauto.
            apply Forall2_length in Hbs.
            autorewrite with core in *; assumption.
        - rewrite Forall_snd, Forall_exists_factor in H.
          destruct H as [bs Hbs].
          unfold read_one_bit_reads in HR.
          specialize HR with b; destruct HR as [bb HR].
          exists (ValBaseHeader (combine (map fst vs) bs) bb).
          constructor; auto. unfold AList.all_values.
          rewrite Forall2_conj.
          split; rewrite Forall2_map_both.
          + rewrite Forall2_eq.
            rewrite map_fst_combine;
              autorewrite with core; eauto.
          + rewrite Forall2_map_l in Hbs.
            rewrite map_snd_combine;
              autorewrite with core; eauto.
            apply Forall2_length in Hbs.
            autorewrite with core in *; assumption.
        - rewrite Forall_snd, Forall_exists_factor in H.
          destruct H as [bs Hbs].
          exists (ValBaseUnion (combine (map fst vs) bs)).
          constructor. unfold AList.all_values.
          rewrite Forall2_conj.
          split; rewrite Forall2_map_both.
          + rewrite Forall2_eq.
            rewrite map_fst_combine;
              autorewrite with core; eauto.
          + rewrite Forall2_map_l in Hbs.
            rewrite map_snd_combine;
              autorewrite with core; eauto.
            apply Forall2_length in Hbs.
            autorewrite with core in *; assumption.
        - rewrite Forall_exists_factor in H.
          firstorder eauto.
        - firstorder eauto.
      Qed.
    End Rel.
  End RelTyp.

  Section Uninit.
    Fixpoint normᵗ (t : typ) : typ :=
      match t with
      | TypBool
      | TypString
      | TypInteger
      | TypInt _
      | TypBit _
      | TypVarBit _
      | TypError
      | TypMatchKind
      | TypVoid
      | TypTypeName _
      | TypExtern _
      | TypTable _   => t
      | TypArray t n => TypArray (normᵗ t) n
      | TypList  ts
      | TypTuple ts  => TypTuple (map normᵗ ts)
      | TypRecord ts
      | TypStruct ts => TypStruct (map (fun '(x,t) => (x, normᵗ t)) ts)
      | TypSet    t  => TypSet (normᵗ t)
      | TypHeader ts => TypHeader (map (fun '(x,t) => (x, normᵗ t)) ts)
      | TypHeaderUnion ts => TypHeaderUnion (map (fun '(x,t) => (x, normᵗ t)) ts)
      | TypEnum X t ms    => TypEnum X (option_map normᵗ t) ms
      | TypNewType _ t    => normᵗ t
      | TypControl ct             => TypControl (normᶜ ct)
      | TypParser  ct             => TypParser  (normᶜ ct)
      | TypFunction ft            => TypFunction (normᶠ ft)
      | TypAction cs ds           => TypAction (map normᵖ cs) (map normᵖ ds)
      | TypPackage Xs ws ps       => TypPackage Xs ws (map normᵖ ps)
      | TypSpecializedType t ts   => TypSpecializedType (normᵗ t) (map normᵗ ts)
      | TypConstructor Xs ws ps t => TypConstructor Xs ws (map normᵖ ps) (normᵗ t)
      end
    with normᶜ (ct : ControlType) : ControlType :=
           match ct with
           | MkControlType Xs ps => MkControlType Xs (map normᵖ ps)
           end
    with normᶠ (ft : FunctionType) : FunctionType :=
           match ft with
           | MkFunctionType Xs ps k t
             => MkFunctionType Xs (map normᵖ ps) k (normᵗ t)
           end
    with normᵖ (p : P4Parameter) : P4Parameter :=
           match p with
           | MkParameter b d t a x => MkParameter b d (normᵗ t) a x
           end.

    Definition normᵗ_idem_def t := normᵗ (normᵗ t) = normᵗ t.
    Definition normᶜ_idem_def t := normᶜ (normᶜ t) = normᶜ t.
    Definition normᶠ_idem_def t := normᶠ (normᶠ t) = normᶠ t.
    Definition normᵖ_idem_def t := normᵖ (normᵖ t) = normᵖ t.

    Definition normᵗ_idem_ind :=
      my_P4Type_ind
        _ normᵗ_idem_def normᶜ_idem_def
        normᶠ_idem_def normᵖ_idem_def.

    Ltac list_idem :=
      intros ts Hts; f_equal;
      apply map_ext_Forall in Hts;
      rewrite map_map; auto; assumption.
    
    Ltac alist_idem :=
      intros xts Hxts; f_equal;
      pose proof Forall_map
           (fun t => normᵗ (normᵗ t) = normᵗ t) snd xts
        as H; unfold Basics.compose in H;
      rewrite <- H in Hxts; clear H;
      apply map_ext_Forall in Hxts;
      repeat rewrite map_pat_combine;
      repeat rewrite map_fst_combine;
      repeat rewrite map_snd_combine;
      repeat rewrite map_length; auto;
      repeat rewrite map_id; rewrite map_map;
      f_equal; auto; assumption.
    
    Lemma normᵗ_idem : forall t, normᵗ_idem_def t.
    Proof.
      apply normᵗ_idem_ind;
        unfold normᵗ_idem_def,normᶜ_idem_def,
        normᶠ_idem_def,normᵖ_idem_def; cbn in *;
          try (intros; f_equal; eauto; assumption);
          try list_idem; try alist_idem; eauto.
      - intros X [t |] ms H; inversion H; subst; cbn; do 2 f_equal; auto.
      - intros ds cs Hds Hcs.
        apply map_ext_Forall in Hds, Hcs.
        repeat rewrite map_map; f_equal; auto.
      - intros Xs ws ps H.
        apply map_ext_Forall in H.
        repeat rewrite map_map; f_equal; auto.
      - intros t ts Hts Ht.
        apply map_ext_Forall in Hts;
          rewrite map_map; f_equal; auto.
      - intros Xs ws ps t Hps Ht.
        apply map_ext_Forall in Hps;
          rewrite map_map; f_equal; auto.
      - intros Xs ps Hps;
          apply map_ext_Forall in Hps;
          rewrite map_map; f_equal; auto.
      - intros Xs ps k t Hps Ht;
          apply map_ext_Forall in Hps;
          rewrite map_map; f_equal; auto.
    Qed.
    
    Context {dummy : Inhabitant tags_t}.

    Definition uninit_sval_of_typ_norm_def t :=
      forall b, uninit_sval_of_typ b (normᵗ t) = uninit_sval_of_typ b t.

    Definition uninit_sval_of_typ_norm_ind :=
      my_P4Type_ind
        _ uninit_sval_of_typ_norm_def
        (fun _ => True) (fun _ => True) (fun _ => True).

    Ltac list_uninit_norm :=
      intros ts Hts b;
      rewrite Forall_forall in Hts;
      specialize Hts with (b:=b);
      rewrite <- Forall_forall in Hts;
      apply map_ext_Forall in Hts;
      do 2 f_equal; rewrite map_map; auto; assumption.

    Ltac alist_uninit_norm :=
      intros xts Hxts b;
      rewrite Forall_forall in Hxts;
      specialize Hxts with (b:=b);
      rewrite <- Forall_forall in Hxts;
      apply map_ext_Forall in Hxts;
      do 2 f_equal;
      rewrite <- map_map with
          (g := uninit_sval_of_typ b) (f := snd) in Hxts;
      rewrite <- map_map with
          (g := uninit_sval_of_typ b) (f := fun xt => normᵗ (snd xt)) in Hxts;
      rewrite <- map_map with
          (g := normᵗ) (f := snd) in Hxts;
      rewrite map_pat_combine, map_id;
      unfold option_ret, option_bind;
      induction xts as [| [[i x] t] xts IHxts];
      simpl in *; inversion Hxts; subst; f_equal; auto; assumption.
    
    Lemma uninit_sval_of_typ_norm : forall t,
        uninit_sval_of_typ_norm_def t.
    Proof.
      apply uninit_sval_of_typ_norm_ind;
        unfold uninit_sval_of_typ_norm_def; cbn;
          try (intros; f_equal; auto; assumption);
          try list_uninit_norm; try alist_uninit_norm; auto.
      - intros [iX X] [t |] [| [iM M] ms] H b;
          inversion H; subst; simpl in *; f_equal; eauto.
    Qed.
                                 
    Local Hint Constructors val_typ : core.

    Ltac some_inv :=
      match goal with
      | H: Some _ = Some _
        |- _ => inversion H; subst; clear H
      end.
    
    Lemma uninit_sval_of_typ_list_val_typ :
      forall b ts v,
        Forall is_expr_typ ts ->
        Forall
          (fun t => forall v,
               uninit_sval_of_typ b t = Some v -> val_typ v (normᵗ t))
          ts ->
        sequence (map (uninit_sval_of_typ b) ts) >>| ValBaseTuple = Some v ->
        val_typ v (TypTuple (map normᵗ ts)).
    Proof.
      intros b ts v Hts IHts Hob; cbn in *.
      unfold option_bind, option_ret in *.
      destruct (sequence (map (uninit_sval_of_typ b) ts))
        as [vs |] eqn:Hvs; cbn in *; try discriminate; some_inv.
      rewrite <- Forall2_sequence_iff,
      <- Forall2_map_l, Forall2_flip in Hvs.
      constructor.
      apply Forall2_impl
        with (R := fun v t => uninit_sval_of_typ b t = Some v)
             (Q := val_typ).
      - rewrite Forall2_forall;
          rewrite Forall_forall in IHts;
          split;
          [ rewrite map_length; eauto using Forall2_length
          | intros u v HIn Hun;
            apply in_combine_r in HIn;
            rewrite in_map_iff in HIn;
            destruct HIn as (t' & ? & Ht'); subst;
            pose proof uninit_sval_of_typ_norm as Husotn;
            unfold uninit_sval_of_typ_norm_def in Husotn;
            rewrite Husotn in Hun; clear Husotn; eauto ].
      - pose proof Forall2_map_l
             _ _ _ (fun vo v => vo = Some v) (@uninit_sval_of_typ tags_t b) as H';
          cbn in H'; rewrite Forall2_flip, H';
            rewrite Forall2_flip, H' in Hvs; clear H';
              rewrite map_map;
              pose proof uninit_sval_of_typ_norm as H';
              unfold uninit_sval_of_typ_norm_def in H';
              specialize H' with (b := b);
              rewrite map_ext with
                  (f := fun x => uninit_sval_of_typ b (normᵗ x))
                  (g := uninit_sval_of_typ b) by auto;
              assumption.
    Qed.
    Local Hint Resolve uninit_sval_of_typ_list_val_typ : core.

    Lemma uninit_sval_of_typ_alist_val_typ :
      forall b (xts : list (P4String.t tags_t * typ))
        (v : @ValueBase (option bool)),
        Forall (fun xt => is_expr_typ (snd xt)) xts ->
        Forall (fun xt => forall v,
                    uninit_sval_of_typ b (snd xt) = Some v ->
                    val_typ v (normᵗ (snd xt))) xts ->
        (sequence (map (fun '({| P4String.str := x |}, t) =>
                         uninit_sval_of_typ b t >>| pair x) xts)
                  >>| ValBaseStruct = Some v ->
         val_typ v (TypStruct (map (fun '(x,t) => (x, normᵗ t)) xts))) /\
        (sequence (map (fun '({| P4String.str := x |}, t) =>
                         uninit_sval_of_typ b t >>| pair x) xts)
                  >>| (fun xvs => ValBaseHeader xvs b) = Some v ->
         val_typ v (TypHeader (map (fun '(x,t) => (x, normᵗ t)) xts))) /\
        (sequence (map (fun '({| P4String.str := x |}, t) =>
                          uninit_sval_of_typ b t >>| pair x) xts)
                  >>| ValBaseUnion = Some v ->
         val_typ v (TypHeaderUnion (map (fun '(x,t) => (x, normᵗ t)) xts))).
    Proof.
      intros b xts v Hxts IHxts.
      repeat split; intro Hob;
        destruct
          (sequence
             (map
                (fun '({| P4String.str := x |}, t) =>
                   uninit_sval_of_typ b t >>| pair x)
                xts))
          as [xvs |] eqn:Hxvs; cbn in *;
          unfold option_bind, option_ret in *;
          try discriminate; some_inv;
            econstructor;
            unfold AList.all_values;
            rewrite <- Forall2_sequence_iff in Hxvs;
            rewrite Forall2_conj;
            rewrite Forall2_map_both with (f:=fst) (g:=fst);
            rewrite Forall2_map_both with (f:=snd) (g:=snd);
            rewrite Forall2_eq;
            unfold P4String.clear_AList_tags;
            do 2 rewrite map_fst_map;
            do 2 rewrite map_snd_map;
            repeat rewrite map_id;
            rewrite <- Forall2_map_l in Hxvs;
            clear Hxts;
            generalize dependent xvs;
            induction xts as [| [[i x] t] xts IHxts'];
            intros [| [y v] yvs] H; cbn in *;
              inversion H;
              inversion IHxts; subst; auto;
                specialize IHxts' with yvs;
                destruct (uninit_sval_of_typ b t) as [v' |] eqn:Hv;
                cbn in *; try discriminate; some_inv;
                  firstorder; f_equal; auto.
    Qed.
    Local Hint Resolve uninit_sval_of_typ_alist_val_typ : core.
    
    Local Hint Resolve Forall_repeat : core.

    Ltac width_solve :=
      match goal with
      | |- context [repeat ?o (N.to_nat ?w)]
        => assert (Hw : w = N.of_nat (length (repeat o (N.to_nat w))))
          by (rewrite repeat_length; lia);
          rewrite Hw at 2; auto
      end.
    Local Hint Extern 0 => width_solve : core.
    
    Lemma uninit_sval_of_typ_val_typ : forall t b v,
        is_expr_typ t ->
        uninit_sval_of_typ b t = Some v ->
        val_typ v (normᵗ t).
    Proof.
      intros t b v H; generalize dependent v.
      induction H using my_is_expr_typ_ind;
        intros v Huninit; cbn in *;
          try discriminate; try some_inv; eauto.
      - constructor; simpl; lia.
      - unfold option_bind, option_ret in *.
        destruct (uninit_sval_of_typ b (TypHeader ts))
          as [v' |] eqn:Hv';
          cbn in *; unfold option_bind, option_ret in *;
            rewrite Hv' in Huninit; try discriminate.
        apply IHis_expr_typ in Hv';
          clear IHis_expr_typ; some_inv.
        width_solve.
      - eapply uninit_sval_of_typ_alist_val_typ in H; firstorder eauto.
      - eapply uninit_sval_of_typ_alist_val_typ in H;
          cbn in *; unfold option_bind, option_ret in *; cbn in *;
            firstorder eauto.
      - eapply uninit_sval_of_typ_alist_val_typ in H; firstorder eauto.
      - eapply uninit_sval_of_typ_alist_val_typ in H; firstorder eauto.
      - destruct X as [iX X'] eqn:HX;
          destruct mems as [| [iM M] mems];
          cbn in *; try lia.
        destruct t as [t |];
          unfold option_map,option_bind, option_ret in *;
          inversion H1; revert HX; subst.
        + destruct (uninit_sval_of_typ b t)
            as [v' |] eqn:Hut; eauto;
            try discriminate; some_inv.
          intros HX.
          replace X' with (P4String.str X) at 1 by (subst; auto).
          rewrite <- HX; auto.
        + some_inv.
          intros HX.
          replace X' with (P4String.str X) at 1 by (subst; auto).
          rewrite <- HX. simpl.
          replace M with (P4String.str {| P4String.tags:=iM; P4String.str :=M |}) at 1
            by auto. intuition.
    Qed.
  End Uninit.
End ValueTyping.
