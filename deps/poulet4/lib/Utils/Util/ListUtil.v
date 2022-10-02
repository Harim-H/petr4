From Poulet4 Require Export Utils.Util.FunUtil Utils.Util.StringUtil Monads.Result.
From Coq Require Export Lists.List micromega.Lia.
Export ListNotations.
Require Import Coq.Strings.String.
Require VST.zlist.sublist.

(** * List Tactics *)

Ltac inv_Forall_cons :=
  match goal with
  | H: Forall _ (_ :: _) |- _ => inv H
  end.
(**[]*)

Ltac ind_list_Forall :=
  match goal with
  | H: Forall _ ?l
    |- _ => induction l; try inv_Forall_cons
  end.
(**[]*)

Ltac inv_Forall2_cons :=
  match goal with
  | H: Forall2 _ _ (_ :: _) |- _ => inv H
  | H: Forall2 _ (_ :: _) _ |- _ => inv H
  end.
(**[]*)

(** * Helper Functions *)

(** Update position [n] of list [l],
    or return [l] if [n] is too large. *)
Fixpoint nth_update {A : Type} (n : nat) (a : A) (l : list A) : list A :=
  match n, l with
  | O, _::t   => a::t
  | S n, h::t => h :: nth_update n a t
  | O, []
  | S _, []  => []
  end.
(**[]*)

(** [filter_opt l] is the sublist of [l] containing only elements which are 
    [Some e] *)
Definition filter_opt {A : Type} : list (option A) -> list A :=
  List.fold_right (fun x acc =>
    match x with
    | Some x => x :: acc
    | None => acc
    end) [].

(** Same as [filter_map], but monadic *)
Definition filter_map_monad {A B : Type} {m : Type -> Type} {M : Monad m} (f : A -> m (option B)) (l : list A) : m (list B) :=
  sequence (List.map f l) >>| filter_opt.

(** * Helper Lemmas *)

Lemma nth_error_exists : forall {A:Type} (l : list A) n,
    n < List.length l -> exists a, nth_error l n = Some a.
Proof.
  intros A l; induction l as [| h t IHt];
    intros [] Hnl; unravel in *; try lia.
  - exists h; reflexivity.
  - apply IHt; lia.
Qed.

Lemma Forall_until_eq : forall {A : Type} (P : A -> Prop) prf1 prf2 a1 a2 suf1 suf2,
    Forall P prf1 -> Forall P prf2 -> ~ P a1 -> ~ P a2 ->
    prf1 ++ a1 :: suf1 = prf2 ++ a2 :: suf2 ->
    prf1 = prf2 /\ a1 = a2 /\ suf1 = suf2.
Proof.
  intros A P prf1;
  induction prf1 as [| hp1 tp1 IHtp1 ];
  intros [| hp2 tp2 ] a1 a2 suf1 suf2 Hp1 Hp2 Ha1 Ha2 Heq;
  repeat inv_Forall_cons; simpl in *; inv Heq;
  try contradiction; try auto 3.
  apply IHtp1 in H5; intuition; subst; reflexivity.
Qed.

Lemma map_compose : forall {A B C : Type} (f : A -> B) (g : B -> C) l,
    map (g ∘ f) l = map g (map f l).
Proof.
  intros; induction l; unravel in *; auto.
  rewrite IHl; reflexivity.
Qed.

Lemma split_map : forall {A B : Type} (l : list (A * B)),
    split l = (map fst l, map snd l).
Proof.
  induction l as [| [a b] l IHl]; unravel; auto.
  destruct (split l) as [la lb] eqn:eqsplit.
  inv IHl; reflexivity.
Qed.

Lemma Forall_nth_error : forall {A : Type} (P : A -> Prop) l n a,
    Forall P l -> nth_error l n = Some a -> P a.
Proof.
  intros A P l n a HPl Hnth.
  eapply Forall_forall in HPl; eauto.
  eapply nth_error_In; eauto.
Qed.

Lemma In_repeat : forall {A : Type} (a : A) n,
    0 < n -> In a (repeat a n).
Proof.
  intros A a [|] H; try lia; unravel; intuition.
Qed.

Lemma Forall_repeat : forall {A : Type} (P : A -> Prop) n a,
    0 < n -> Forall P (repeat a n) -> P a.
Proof.
  intros A P n a Hn H.
  eapply Forall_forall in H; eauto.
  apply In_repeat; auto.
Qed.

Lemma repeat_Forall : forall {A : Type} (P : A -> Prop) n a,
    P a -> Forall P (repeat a n).
Proof.
  intros A P n a H.
  induction n as [| n IHn]; unravel; constructor; auto.
Qed.

Lemma Forall_firstn : forall {A : Type} (P : A -> Prop) n l,
    Forall P l -> Forall P (firstn n l).
Proof.
  intros A P n l H. rewrite <- firstn_skipn with (n := n) in H.
  apply Forall_app in H. intuition.
Qed.

Lemma Forall_skipn : forall {A : Type} (P : A -> Prop) n l,
    Forall P l -> Forall P (skipn n l).
Proof.
  intros A P n l H. rewrite <- firstn_skipn with (n := n) in H.
  apply Forall_app in H. intuition.
Qed.

Lemma Forall2_length : forall {A B : Type} (R : A -> B -> Prop) l1 l2,
    Forall2 R l1 l2 -> List.length l1 = List.length l2.
Proof. intros A B R l1 l2 H; induction H; unravel; auto. Qed.

Lemma Forall2_duh : forall {A B : Type} (P : A -> B -> Prop),
    (forall a b, P a b) ->
    forall la lb, List.length la = List.length lb -> Forall2 P la lb.
Proof.
  induction la; destruct lb; intros;
  unravel in *; try discriminate; constructor; auto.
Qed.

Lemma Forall2_map_l : forall {A B C : Type} (f : A -> B) (R : B -> C -> Prop) la lc,
    Forall2 R (map f la) lc <-> Forall2 (R ∘ f) la lc.
Proof.
  induction la as [| a la IHal]; intros [| c lc];
  unravel in *; split; intros; intuition; inv_Forall2_cons;
  constructor; try apply IHal; auto.
Qed.

Lemma Forall2_Forall : forall {A : Type} (R : A -> A -> Prop) l,
    Forall2 R l l <-> Forall (fun a => R a a) l.
Proof.
  induction l; split; intros;
  try inv_Forall_cons;  try inv_Forall2_cons; intuition.
Qed.

Lemma Forall2_rev : forall {A B: Type} (R : A -> B -> Prop) l1 l2,
    Forall2 R l1 l2 -> Forall2 R (rev l1) (rev l2).
Proof.
  intros. induction H; simpl; auto. apply Forall2_app; auto.
Qed.

Lemma Forall_duh : forall {A : Type} (P : A -> Prop),
    (forall a, P a) -> forall l, Forall P l.
Proof.
  induction l; constructor; auto.
Qed.

Lemma Forall_exists_prefix_only_or_all : forall {A : Type} (P : A -> Prop) (l : list A),
    (forall a, P a \/ ~ P a) ->
    Forall P l \/ exists a prefix suffix,
        l = prefix ++ a :: suffix /\ Forall P prefix /\ ~ P a.
Proof.
  intros A P l HP;
  induction l as [| h t [IHt | [a [prf [suf [Heq [Hprf Ha]]]]]]];
  intuition; subst.
  - destruct (HP h) as [? | ?]; intuition.
    right. exists h; exists []; exists t; intuition.
  - right. destruct (HP h) as [? | ?].
    + exists a; exists (h :: prf); exists suf; intuition.
    + exists h; exists []; exists (prf ++ a :: suf); intuition.
Qed.

Section FoldLeftProp.
  Context {A B : Type}.
  Variable (R : A -> B -> B -> Prop).

  Inductive FoldLeft : list A -> B -> B -> Prop :=
  | FoldLeft_nil (b: B) :
      FoldLeft [] b b
  | FoldLeft_cons (a: A) (l: list A) (b b' b'': B) :
      R a b b' ->
      FoldLeft l b' b'' ->
      FoldLeft (a :: l) b b''.
  (**[]*)
End FoldLeftProp.

Import String.

Definition opt_snd { A B : Type } (p : A * option B ) : option (A * B) :=
  match p with
  | (_, None) => None
  | (a, Some b) => Some (a,b)
  end.

Fixpoint string_member (x : string) (l1 : list string) : bool :=
  match l1 with
  | [] => false
  | y::ys =>
    if String.eqb x y
    then true
    else string_member x ys
  end.

Fixpoint list_eq {A : Type} (eq : A -> A -> bool) (s1 s2 : list A) : bool  :=
  match s1,s2 with
  | [], [] => true
  | _, [] => false
  | [], _ => false
  | x::xs, y::ys => andb (eq x y) (list_eq eq xs ys)
  end.

Import Result ResultNotations.

Fixpoint zip {A B : Type} (xs : list A) (ys : list B) : result string (list (A * B)) :=
  match xs, ys with
  | [],[] => ok []
  | [], _ => error "First zipped list was shorter than the second"%string
  | _, [] => error "First zipped list was longer than the second"%string
  | x::xs, y::ys =>
    let+ xys := zip xs ys in
    cons (x,y) xys
  end.

Fixpoint ith { A : Type } (xs : list A) (i : nat) : result string A :=
  match xs with
  | [] => error ("ListAccessFailure: list had " ++ StringUtil.string_of_nat i ++ " too few elements")%string
  | x::xs =>
    match i with
    | O => ok x
    | S i =>  ith xs i
    end
  end.

Definition fold_righti {A B : Type} (f : nat -> A -> B -> B) (init : B) (xs : list A) : B :=
  snd (List.fold_right (fun a '(i, b) => (i + 1, f i a b )) (0, init) xs).

Definition fold_lefti { A B : Type } (f : nat -> A -> B -> B) (init : B) (lst : list A) : B :=
  snd (fold_left (fun '(n, b) a => (S n, f n a b)) lst (O, init)).

Definition findi { A : Type } (select : A -> bool) (l : list A) : option nat :=
  fold_lefti (fun i a found_at_n =>
                match found_at_n with
                | Some _ => found_at_n
                | None => if select a
                          then Some i
                          else None
                end
             ) None l.

Definition union_map_snd {Err A B C : Type} (f : B -> result Err C) (xs : list (A * B)) : result Err (list (A * C)) :=
  rred (List.map (snd_res_map f) xs).

Definition map_snd {A B C : Type} (f : B -> C) (ps : list (A * B)) : list (A * C) :=
  List.map (fun '(a, b) => (a, f b)) ps.

Fixpoint intersect_string_list_aux (xs ys acc : list string) : list string :=
  match xs with
  | [] => acc
  | x::xs =>
    if string_member x ys
    then intersect_string_list_aux xs ys (x::acc)
    else intersect_string_list_aux xs ys acc
  end.

Definition intersect_string_list (xs ys : list string) : list string :=
  rev' (intersect_string_list_aux xs ys []).

(* This wrapper prevents A = Inhabitant A definitional equalities from
   throwing off typeclass inference. *)
Definition Znth_default {A : Type} (x : A) (n : BinInt.Z) (l : list A) : A :=
  @VST.zlist.sublist.Znth A x n l.
