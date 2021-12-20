Set Warnings "-custom-entry-overridden".
Require Import Coq.Program.Basics.
Require Export Poulet4.P4cub.Syntax.AST.
Require Export Poulet4.P4Arith.
Require Export Poulet4.P4cub.Envn.
Require Export Poulet4.P4cub.BigStep.InstUtil.
Require Export Poulet4.P4cub.BigStep.BigStep.
Require Export Poulet4.P4cub.BigStep.Semantics.
Require Export Poulet4.P4cub.BigStep.Value.Value.
Require Export Poulet4.P4cub.Util.Result.
Require Import Poulet4.ToP4cub.
Import ToP4cub.
Require Import Coq.Arith.EqNat.
Require Import String.
Open Scope string_scope.

Require Import List.

Require Import Poulet4.P4cub.Util.StringUtil.
Require Import Poulet4.P4cub.Util.ListUtil.

Import Env.EnvNotations.

Import Result.
Import ResultNotations.
Import ToP4cub.

(** Compile to GCL *)
Module ST := Stmt.
Module CD := Control.
Module TD := TopDecl.
Module E := Expr.
Module F := F.

Section Inline.
Variable tags_t : Type.


Definition expenv : Type := Env.t string (E.e tags_t).

Definition get_exp (pa : paramarg (E.e tags_t) (E.e tags_t)) :=
  match pa with
  | PAInOut e => e
  | PAIn e => e
  | PAOut e => e
  | PADirLess e => e
  end.

Definition args_to_expenv (args : F.fs string (paramarg (E.e tags_t) (E.e tags_t))) : expenv :=
  F.fold (fun param arg env => Env.bind param (get_exp arg) env) args [].

Fixpoint subst_e (η : expenv) (e : E.e tags_t) : E.e tags_t :=
  match e with
  | E.EBool _ _ => e
  | E.EBit _ _ _ => e
  | E.EInt _ _ _ => e
  | E.EVar type x i =>
    match Env.find x η with
    | None => e
    | Some e' => e'
    end
  | E.ESlice e hi lo i =>
    E.ESlice (subst_e η e) hi lo i
  | E.ECast type arg i =>
    E.ECast type (subst_e η arg) i
  | E.EUop op type arg i =>
    E.EUop op type (subst_e η arg) i
  | E.EBop t op l r i =>
    E.EBop t op (subst_e η l) (subst_e η r) i
  | E.ETuple es i =>
    E.ETuple (List.map (subst_e η) es) i
  | E.EStruct fields i =>
    E.EStruct (F.map (subst_e η) fields) i
  | E.EHeader fields valid i =>
    E.EHeader (F.map (subst_e η) fields) (subst_e η valid) i
  | E.EExprMember mem expr_type arg i =>
    E.EExprMember mem expr_type (subst_e η arg) i
  | E.EError _ _ => e
  | E.EMatchKind _ _ => e
  | E.EHeaderStack fields headers ni i =>
    E.EHeaderStack fields (List.map (subst_e η) headers) ni i
  | E.EHeaderStackAccess fs stack idx i =>
    E.EHeaderStackAccess fs (subst_e η stack) idx i
  end.

Inductive t : Type :=
| ISkip (i : tags_t)                       (* skip, useful for
                                               small-step semantics *)
| IVardecl (type : E.t)
           (x : string) (i : tags_t)       (* Variable declaration. *)
| IAssign (type : E.t) (lhs rhs : E.e tags_t)
          (i : tags_t)                     (* assignment *)
| IConditional (guard_type : E.t)
               (guard : E.e tags_t)
               (tru_blk fls_blk : t) (i : tags_t) (* conditionals *)
| ISeq (s1 s2 : t) (i : tags_t)                   (* sequences *)
| IBlock (blk : t)                                (* blocks *)
| IReturnVoid (i : tags_t)                        (* void return statement *)
| IReturnFruit (t : E.t)
               (e : E.e tags_t)(i : tags_t)       (* fruitful return statement *)
| IExit (i : tags_t)                              (* exit statement *)
| IInvoke (x : string)
          (keys : list (E.t * E.e tags_t * E.matchkind))
          (actions : list (string * t))
          (i : tags_t)
| ISetValidity (hdr: E.e tags_t ) (val : bool) (i : tags_t) (*set the header indicated by hdr to valid (if val is true) or invalid (if val is false) *)
| IHeaderStackOp (hdr_stck_name : string) (typ : E.t) (op : ST.hsop) (size : positive) (i : tags_t)
| IExternMethodCall (extn : string) (method : string) (args : E.arrowE tags_t) (i : tags_t).

Definition rename_string (x : string) (params : list string) :=
  if fold_right (fun y => orb (String.eqb x y)) false params
  then "?" ++ x
  else x.

Fixpoint action_param_renamer_expr (params : list string) (e : E.e tags_t) : E.e tags_t :=
  match e with
  | E.EBool _ _ => e
  | E.EBit _ _ _ => e
  | E.EInt _ _ _ => e
  | E.EVar type x i =>
    E.EVar type (rename_string x params) i
  | E.ESlice e hi lo i =>
    E.ESlice (action_param_renamer_expr params e) hi lo i
  | E.ECast typ arg i =>
    E.ECast typ (action_param_renamer_expr params arg) i
  | E.EUop op typ arg i =>
    E.EUop op typ (action_param_renamer_expr params arg) i
  | E.EBop t op le re i =>
    let le' := action_param_renamer_expr params le in
    let re' := action_param_renamer_expr params re in
    E.EBop t op le re i
  | E.ETuple es i =>
    E.ETuple (List.map (action_param_renamer_expr params) es) i
  | E.EStruct fields i =>
    E.EStruct (F.map (action_param_renamer_expr params) fields) i
  | E.EHeader fields valid i =>
    E.EHeader (F.map (action_param_renamer_expr params) fields) (action_param_renamer_expr params valid) i
  | E.EExprMember mem expr_type arg i =>
    E.EExprMember mem expr_type (action_param_renamer_expr params arg) i
  | E.EError _ _ => e
  | E.EMatchKind _ _ => e
  | E.EHeaderStack fields headers ni i =>
    E.EHeaderStack fields (List.map (action_param_renamer_expr params) headers) ni i
  | E.EHeaderStackAccess fs stack idx i =>
    E.EHeaderStackAccess fs (action_param_renamer_expr params stack) idx i
  end.

Fixpoint action_param_renamer (params : list string) (c : t) : result (t * list string) :=
  match c with
  | ISkip _ => ok (c, params)
  | IVardecl type x i => ok (c, filter (negb ∘ (String.eqb x)) params)
  | IAssign t lhs rhs i =>
    let rhs' := action_param_renamer_expr params rhs in
    let lhs' := action_param_renamer_expr params lhs in
    ok (IAssign t lhs' rhs' i, params)
  | IConditional typ cond tru fls i =>
    let cond' := action_param_renamer_expr params cond in
    let* (tru', _) := action_param_renamer params tru in
    let+ (fls', _) := action_param_renamer params fls in
    (IConditional typ cond' tru' fls' i, params)
  | ISeq c1 c2 i =>
    let* (c1', params1) := action_param_renamer params c1 in
    let+ (c2', params2) := action_param_renamer params1 c2 in
    (ISeq c1' c2' i, params2)
  | IBlock blck =>
    let+ (blck', _) := action_param_renamer params blck in
    (blck', params)
  | IReturnVoid _ => ok (c, params)
  | IReturnFruit t e i =>
    let e' := action_param_renamer_expr params e in
    ok (IReturnFruit t e' i, params)
  | IExit _ => ok (c, params)
  | IInvoke _ _ _ _ =>
    error "Invocations should not occur within actions"
  | ISetValidity e v i =>
    let e' := action_param_renamer_expr params e in
    ok (ISetValidity e' v i, params)
  | IHeaderStackOp hdr_stck_name typ hsop size i =>
    ok (IHeaderStackOp (rename_string hdr_stck_name params) typ hsop size i, params)
  | IExternMethodCall extn method ar i =>
    let pargs := paramargs ar in
    let ret := rtrns ar in
    let pargs' := F.fold (fun p a rst =>
          let a' := paramarg_map (action_param_renamer_expr params) (action_param_renamer_expr params) a in
          (p, a') :: rst) [] pargs in
    let ar' := {| paramargs := pargs'; rtrns := ret |} in
    ok (IExternMethodCall extn method ar' i, params)
  end.

Fixpoint subst_t (η : expenv) (c : t) : (t * expenv) :=
  match c with
  | ISkip i => (ISkip i, η)
  | IVardecl type x i  =>
    (IVardecl type x i, Env.remove x η)
  | IAssign t lhs rhs i =>
    (IAssign t (subst_e η lhs) (subst_e η rhs) i , η)
  | IConditional guard_type guard tru_blk fls_blk i =>
    (IConditional guard_type
                  (subst_e η guard)
                  (fst (subst_t η tru_blk))
                  (fst (subst_t η fls_blk))
                  i, η)
  | ISeq s1 s2 i =>
    let (s1', η1) := subst_t η s1 in
    let (s2', η2) := subst_t η1 s2 in
    (ISeq s1' s2' i, η2)
  | IBlock blk =>
    (IBlock (fst (subst_t η blk)), η)
  | IReturnVoid _ => (c, η)
  | IReturnFruit t e i => (IReturnFruit t (subst_e η e) i,η)
  | IExit _ => (c,η)
  | IInvoke x keys actions i =>
    let keys' := List.map (fun '(t, m,k) => (t, subst_e η m, k)) keys in
    let actions' := List.map (fun '(s,a) => (s, fst(subst_t η a))) actions in
    (IInvoke x keys' actions' i, η)

  | IExternMethodCall extn method ar i =>
    let pas := paramargs ar in
    let returns := rtrns ar in
    let pas' := F.map (paramarg_map (subst_e η) (subst_e η)) pas in
    let ar' := {| paramargs := pas'; rtrns:=returns |} in
    (IExternMethodCall extn method ar' i, η)
  | ISetValidity e v i =>
    (ISetValidity (subst_e η e) v i, η)
  | IHeaderStackOp hdr_stck_name stck_el_typ hsop size i =>
    match Env.find hdr_stck_name η with
    | None => (c, η)
    | Some e' =>
      let stck_type := t_of_e e' in
      (ISeq (IAssign stck_type (E.EVar stck_type hdr_stck_name i) e' i) c i, η)
    end
  end.

Definition copy (args : E.args tags_t) : expenv :=
  F.fold (fun param arg η => match arg with
                             | PAIn e => Env.bind param e η
                             | PAInOut e => Env.bind param e η
                             | PAOut e => Env.bind param e η
                             | PADirLess e => Env.bind param e η
                             end)
         args (Env.empty String.string (E.e tags_t)).

Definition string_list_of_params (ps : E.params) : list string :=
  List.map fst ps.

Definition translate_pattern (discriminee : E.e tags_t) (pat : Parser.pat) (i : tags_t):=
  E.EBool true i.

Fixpoint elaborate_arg_expression (param : string) (arg : E.e tags_t) : F.fs string (E.e tags_t) :=
  let index := fun s idx => s ++ "[" ++ string_of_nat idx ++ "]" in
  let access := fun s f => s ++ "." ++ f in
  match arg with
  | E.EVar (E.TStruct fs) x tags =>
    List.fold_right (fun '(f, t) acc =>
     (access param f, (E.EVar t (access x f) tags)) :: acc) [] fs

  | E.EExprMember (E.TStruct fs) mem _ tags  =>
    let member_member := fun f t => E.EExprMember t f arg tags in
    List.fold_right (fun '(f, t) acc =>
     (access param f, member_member f t) :: acc) [] fs

  | E.EVar (E.TTuple ts) x tags =>
    ListUtil.fold_righti (fun idx t acc => (index param idx, (E.EVar t (index x idx) tags)) :: acc) [] ts

  | E.ETuple es _ =>
    ListUtil.fold_righti (fun i e acc =>
          let param_i := index param i in
          let es := elaborate_arg_expression param_i e in
          List.app es acc) [] es
  | _ => [(param, arg)]
  end.

Definition paramarg_map_union {A B : Type} (f : A -> F.fs string B) (pa : paramarg A A) : F.fs string (paramarg B B) :=
  match pa with
  | PAIn a => F.map PAIn (f a)
  | PAOut a => F.map PAOut (f a)
  | PAInOut a => F.map PAInOut (f a)
  | PADirLess a => F.map PADirLess (f a)
  end.

Definition elaborate_argument (parg : F.f string (paramarg (E.e tags_t) (E.e tags_t))) : F.fs string (paramarg (E.e tags_t) (E.e tags_t)) :=
  let '(param, arg) := parg in
  paramarg_map_union (elaborate_arg_expression param) arg.


Definition elaborate_arguments (args : F.fs string (paramarg (E.e tags_t) (E.e tags_t))) :  F.fs string (paramarg (E.e tags_t) (E.e tags_t)) :=
  List.concat (List.map elaborate_argument args).

Definition elaborate_arrowE (ar : E.arrowE tags_t) : E.arrowE tags_t :=
  {| paramargs := elaborate_arguments ar.(paramargs);
     rtrns := ar.(rtrns) |}.

Fixpoint inline
         (n : nat)
         (ctx : DeclCtx tags_t)
         (s : ST.s tags_t)
         {struct n} : result t :=
  match n with
  | 0 => error "Inliner ran out of gas"
  | S n0 =>
    match s with
    | ST.SSkip i =>
      ok (ISkip i)

    | ST.SVardecl x t_or_e i =>
      match t_or_e with
      | inl t =>  ok (IVardecl t x i)
      | inr e =>
        let t := t_of_e e in
        ok (ISeq (IVardecl t x i) (IAssign t (E.EVar t x i) e i) i)
      end
    | ST.SAssign lhs rhs i =>
      ok (IAssign (t_of_e rhs) lhs rhs i)

    | ST.SConditional guard tru_blk fls_blk i =>
      let* tru_blk' := inline n0 ctx tru_blk in
      let+ fls_blk' := inline n0 ctx fls_blk in
      IConditional (t_of_e guard) guard tru_blk' fls_blk' i

    | ST.SSeq s1 s2 i =>
      let* i1 := inline n0 ctx s1 in
      let+ i2 := inline n0 ctx s2 in
      ISeq i1 i2 i

    | ST.SBlock s =>
      let+ blk := inline n0 ctx s in
      IBlock blk

    | ST.SFunCall f _ ar i =>
      let args := paramargs ar in
      let ret := rtrns ar in
      match find_function _ ctx f with
        | Some (TD.TPFunction _ _ _ body i) =>
          (** TODO check copy-in/copy-out *)
          let+ rslt := inline n0 ctx body in
          let (s,_) := subst_t (args_to_expenv args) rslt in
          IBlock s
        | Some _ =>
          error "[ERROR] Got a nonfunction when `find`ing a function"
        | None =>
          let args := elaborate_arrowE {|paramargs:=args; rtrns:=ret|} in
          ok (IExternMethodCall "_" f args i)
      end

    | ST.SActCall a args i =>
      let*~ adecl := find_action tags_t ctx a else ("could not find action " ++ a ++ " in environment") in
      match adecl with
      | CD.CDAction _ _ body i =>
        (** TODO handle copy-in/copy-out *)
        let+ rslt := inline n0 ctx body in
        let η := args_to_expenv args in
        IBlock (fst (subst_t η rslt))
      | _ =>
        error "[ERROR] got a nonaction when `find`-ing a function"
      end

    | ST.SApply ci ext_args args i =>
      let*~ cinst := find_control tags_t ctx ci else "could not find controller instance " ++ ci ++ " in environment" in
      match cinst with
      | TD.TPInstantiate cname _ _ cargs i =>
        let*~ cdecl := find_control tags_t ctx cname else "could not find controller" in
        match cdecl with
        | TD.TPControl _ _ _ _ body apply_blk i =>
          (* Context is begin extended with body, but why can't I find the controls? *)
          let ctx' := of_cdecl tags_t ctx body in
          let+ rslt := inline n0 ctx' apply_blk in
          (** TODO check copy-in/copy-out *)
          let η := copy args in
          IBlock (fst (subst_t η rslt))
        | _ =>
          error "Expected a control decl, got something else"
        end
      | _ =>
         error "Expected a control instantiation, got something else"
      end

    | ST.SReturn None i =>
      ok (IReturnVoid i)

    | ST.SReturn (Some expr) i =>
      ok (IReturnFruit (t_of_e expr) expr i)

    | ST.SExit i =>
      ok (IExit i)

    | ST.SInvoke t i =>
      let*~ tdecl := find_table tags_t ctx t else "could not find table in environment" in
      match tdecl with
      | CD.CDTable _ tbl _ =>
        let keys := List.map (fun '(e,k) => (t_of_e e, e, k)) (Control.table_key tbl) in
        let actions := Control.table_actions tbl in
        let act_to_gcl := fun a =>
          let*~ act := find_action tags_t ctx a else "could not find action " ++ a ++ " in environment" in
          match act with
          | CD.CDAction _ params body _ =>
            let* s := inline n0 ctx body in
            let+ (s', _) := action_param_renamer (string_list_of_params params) s in
            s'
          | _ =>
            error "[ERROR] expecting action when `find`ing action, got something else"
          end
        in
        let* acts := rred (List.map act_to_gcl actions) in
        let+ named_acts := zip actions acts in
        IInvoke t keys named_acts i
      | _ =>
        error "[ERROR] expecting table when getting table, got something else"
      end

    | ST.SExternMethodCall ext method _ args i =>
      ok (IExternMethodCall ext method args i)

    | ST.SSetValidity e b i =>
      ok (ISetValidity e b i)
    (* | ST.PApply _ _ _ _ i => *)
      (* let*~ prsr := find_parser tags_t ctx pname else "could not find parser instance" in *)
      (* match pinst with *)
      (* | TD.TPParser _ cparams eparams params start states i => *)
      (*   inline_parser n0 ctx cparams eparams params start states i *)
      (* | _ => error "[ERROR] expecting parser when `find`ing parser. got something else" *)
      (* end *)
      (* ok (ISkip i) *)

    | ST.SHeaderStackOp s typ op n i =>
      ok (IHeaderStackOp s typ op n i)
  end
end.



Definition seq_tuple_elem_assign
           (tuple_name : string)
           (i : tags_t)
           (n : nat)
           (p : E.t * E.e tags_t)
           (acc : Inline.t) : Inline.t :=
  let (t, e) := p in
  let tuple_elem_name := tuple_name ++ "__tup__" ++ string_of_nat n in
  let lhs := E.EVar t tuple_elem_name i in
  Inline.ISeq (Inline.IAssign t lhs e i) acc i.

Fixpoint elim_tuple_assign (ltyp : E.t) (lhs rhs : E.e tags_t) (i : tags_t) : result Inline.t :=
  match lhs, rhs with
  | E.EVar (E.TTuple types) x i, E.ETuple es _ =>
    let+ te := zip types es in
    fold_lefti (seq_tuple_elem_assign x i) (Inline.ISkip i) te
  | _,_ => ok (Inline.IAssign ltyp lhs rhs i)
  end.

Definition res_snd { A B : Type } (p : A * result B ) : result (A * B) :=
  match p with
  | (_, Error _ s) => error s
  | (a, Ok _ b) => ok (a, b)
  end.

Definition elaborate_tuple_literal
           (param : string)
           (ctor : E.e tags_t -> paramarg (E.e tags_t) (E.e tags_t))
           (es : list (E.e tags_t))
           (args : F.fs string (paramarg (E.e tags_t) (E.e tags_t))) :=
  ListUtil.fold_righti (fun idx e acc =>
   let index := fun s =>  s ++ ".[" ++ string_of_nat idx ++ "]" in
   (index param, ctor e) :: acc) args es.

Fixpoint elim_tuple (c : Inline.t) : result t :=
  match c with
  | ISkip _ => ok c
  | IVardecl _ _ _ => ok c
  | IAssign type lhs rhs i =>
    elim_tuple_assign type lhs rhs i
  | IConditional typ g tru fls i =>
    let* tru' := elim_tuple tru in
    let+ fls' := elim_tuple fls in
    IConditional typ g tru' fls' i
  | ISeq c1 c2 i =>
    let* c1' := elim_tuple c1 in
    let+ c2' := elim_tuple c2 in
    ISeq c1' c2' i
  | IBlock blk =>
    let+ blk' := elim_tuple blk in
    IBlock blk'
  | IReturnVoid _ => ok c
  | IReturnFruit _ _ _ => ok c
  | IExit _ => ok c
  | IInvoke x keys actions i =>
    (** TODO do we need to eliminate tuples in keys??*)
    let+ actions := List.fold_right (fun '(name, act) acc =>
                     let* act := elim_tuple act in
                     let+ acc := acc in
                     (name, act) :: acc) (ok []) actions in
    IInvoke x keys actions i
  | IExternMethodCall extern method arrow tags =>
    let arrow := elaborate_arrowE arrow in
    ok (IExternMethodCall extern method arrow tags)
  | ISetValidity _ _ _ =>
    (** TODO do we need to eliminate tuples in valid sets? I think that'd be ill-typed *)
    ok c
  | IHeaderStackOp _ _ _ _ _ =>
    ok c
  end.

Fixpoint header_fields (tags : tags_t) (e : E.e tags_t) (fields : F.fs string E.t) : list (E.e tags_t * E.t)  :=
  (* TODO Type of ExprMember might need to be the header type *)
  F.fold (fun f typ acc => (E.EExprMember typ f e tags, typ) :: acc )
         fields
         [(E.EExprMember E.TBool "isValid" e tags, E.TBool)].

Fixpoint header_elaboration_assign tags (lhs rhs : E.e tags_t) (fields : F.fs string E.t) : result t:=
  let lhs_members := header_fields tags lhs fields in
  let rhs_members := header_fields tags rhs fields in
  let+ assigns := zip lhs_members rhs_members  in
  let f := fun '((lhs_mem, typ), (rhs_mem, _)) acc => ISeq (IAssign typ lhs_mem rhs_mem tags) acc tags in
  List.fold_right f (ISkip tags) assigns.


Fixpoint elaborate_headers (c : Inline.t) : result Inline.t :=
  match c with
  | ISkip _ => ok c
  | IVardecl type s i =>
    (** TODO elaborate header if type = THeader *)
    match type with
    (* | E.THeader fields => *)
    (*   let vars := header_fields i (E.EVar type s i) fields in *)
    (*   let elabd_hdr_decls := fold_left (fun acc '(var_str, var_typ) => ISeq (IVardecl var_typ var_str i) acc i) vars (ISkip i) in *)
    (*   ok elabd_hdr_decls *)
    | _ => ok c
    end
  | IAssign type lhs rhs i =>
    match type with
    | E.THeader fields =>
      header_elaboration_assign i lhs rhs fields
    (*   (** TODO : What other assignments to headers are legal? EHeader? EStruct? *) *)
    (*   match lhs, rhs with *)
    (*   | E.EVar _ l il, E.EVar _ r ir => *)
    (*     let lvars := header_fields l fields in *)
    (*     let rvars := header_fields r fields in *)
    (*     let+ lrvars := zip lvars rvars in *)
    (*     fold_right (fun '((lvar, ltyp),(rvar, rtyp)) acc => ISeq (IAssign ltyp (E.EVar ltyp lvar il) (E.EVar rtyp rvar ir) i) acc i) (ISkip i) lrvars *)
    (*   | E.EVar _ l il, E.EHeader explicit_fields valid i => *)
    (*     let lvars := header_fields l fields in *)
    (*     let assign_fields := fun '(lvar, ltyp) acc_res => *)
    (*          let* acc := acc_res in *)
    (*          let*~ rval := F.find_value (String.eqb lvar) explicit_fields else "couldn't find field in field list" in *)
    (*          ok (ISeq (IAssign ltyp (E.EVar ltyp lvar il) rval i) acc i) in *)
    (*    fold_right assign_fields *)
    (*               (ok (IAssign E.TBool (E.EVar E.TBool (l ++ ".is_valid") il) valid i)) *)
    (*               lvars *)
    (*   | E.ESlice _ _ _ _, _ => *)
    (*     error ("[elaborate_headers] Type Error. bitvector slice != header type") *)
    (*   | E.EVar _ x _ , _ => *)
    (*     error ("[elaborate_headers] Error assigning to [" ++ x ++ "] . Can only copy variables or header literals of type header.") *)
    (*   | E.EBool _ _, _ => *)
    (*     error ("[elaborate_headers] Type error, bool != header type") *)
    (*   | E.EBit _ _ _, _ => *)
    (*     error ("[elaborate_headers] Type error, bit<> != header type") *)
    (*   | E.EInt _ _ _, _ => *)
    (*     error ("[elaborate_headers] Type error, int<> != header type") *)
    (*   | E.ECast _ _ _, _ => *)
    (*     error ("[elaborate_headers] a cast is not an lvalue") *)
    (*   | E.EUop _ _ _ _, _ => *)
    (*     error ("[elaborate_headers] a unary op is not an lvalue") *)
    (*   | E.EBop _ _ _ _ _, _ => *)
    (*     error ("[elaborate_headers] a binary op is not an lvalue") *)
    (*   | E.ETuple _ _, _ => *)
    (*     error ("[elaborate_headers] a tuple is not an lvalue") *)
    (*   | E.EStruct _ _, _ => *)
    (*     error ("[elaborate_headers] Type Error:: struct type != header type ") *)
    (*   | E.EExprMember _ mem _ _, _ => *)
    (*     error ("[elaborate_headers] [FIXME] trying to elaborate header to an expresssion member lvalue " ++ mem) *)
    (*   | E.EError _ _, _ => *)
    (*     error ("[elaborate_headers] an error is not an lvalue ") *)
    (*   | E.EMatchKind _ _, _ => *)
    (*     error ("[elaborate_headers] a matchkind is not an lvalue ") *)
    (*   | E.EHeaderStack _ _ _ _ , _ => *)
    (*     error ("[elaborate_headers] a headerstack literal is not an lvalue ") *)
    (*   | E.EHeader _ _ _ , _ => *)
    (*     error ("[elaborate_headers] a header literal is not an lvalue ") *)
    (*   | E.EHeaderStackAccess _ _ _ _, _  => *)
    (*     error ("[elaborate_headers] [FIXME] need to translate a header stack access header-asignment ") *)
    (*   end *)
    | _ => ok c
  end
| IConditional guard_type guard tru fls i =>
  (** TODO: elaborate headers in guard? *)
  let* tru' := elaborate_headers tru in
  let+ fls' := elaborate_headers fls in
  IConditional guard_type guard tru' fls' i
| ISeq s1 s2 i =>
  let* s1' := elaborate_headers s1 in
  let+ s2' := elaborate_headers s2 in
  ISeq s1' s2' i

| IBlock b =>
  let+ b' := elaborate_headers b in
  IBlock b'
| IReturnVoid _ => ok c
| IReturnFruit _ _ _ => ok c
| IExit _ => ok c
| IInvoke x keys actions i =>
  let opt_actions := map_snd elaborate_headers actions in
  let+ actions' := rred (List.map res_snd opt_actions) in
  IInvoke x keys actions' i
| IExternMethodCall extern method arrow tags =>
  let arrow := elaborate_arrowE arrow in
  ok (IExternMethodCall extern method arrow tags)
| ISetValidity _ _ _ =>
  (* TODO Do we need to eliminate tuples in valid-sets? that seems ill-typed *)
  ok c
| IHeaderStackOp _ _ _ _ _ =>
  (* TODO Do we need to eliminate tuples in valid-sets? that seems ill-typed *)
  ok c
end.


Fixpoint ifold {A : Type} (n : nat) (f : nat -> A -> A) (init : A) :=
  match n with
  | O => init
  | S n' => f n (ifold n' f init)
  end.

Fixpoint elaborate_header_stacks (c : Inline.t) : result Inline.t :=
  match c with
  | ISkip _ => ok c
  | IVardecl type x i =>
    match type with
    | E.THeaderStack fields size =>
      ok (ifold (BinPos.Pos.to_nat size)
                (fun n acc => ISeq (IVardecl (E.THeader fields) (x ++ "[" ++ string_of_nat n ++ "]") i) acc i) (ISkip i))
    | _ => ok c
    end
  | IAssign type lhs rhs i =>
    match type with
    | E.THeaderStack fields size =>
      match lhs, rhs with
      | E.EVar ltyp lvar il, E.EVar rtyp rvar ir =>
        let iter := ifold (BinPos.Pos.to_nat size) in
        (* Should these be `HeaderStackAccess`es? *)
        let lvars := iter (fun n => cons (lvar ++ "[" ++ string_of_nat n ++ "]")) [] in
        let rvars := iter (fun n => cons (rvar ++ "[" ++ string_of_nat n ++ "]")) [] in
        let+ lrvars := zip lvars rvars in
        let htype := E.THeader fields in
        let mk := E.EVar htype in
        fold_right (fun '(lv, rv) acc => ISeq (IAssign htype (mk lv il) (mk lv ir) i) acc i) (ISkip i) lrvars
      | _, _ =>
        (* Don't know how to translate anything but variables *)
        error "Tried to elaborate a header stack assignment that wasn't variables"
      end
    | _ => ok c
    end
  | IConditional gtyp guard tru fls i =>
    (* TODO Eliminate header stack literals from expressions *)
    let* tru' := elaborate_header_stacks tru in
    let+ fls' := elaborate_header_stacks fls in
    IConditional gtyp guard tru' fls' i

  | ISeq c1 c2 i =>
    let* c1' := elaborate_header_stacks c1 in
    let+ c2' := elaborate_header_stacks c2 in
    ISeq c1' c2' i

  | IBlock c =>
    let+ c' := elaborate_header_stacks c in
    IBlock c'

  | IReturnVoid _ => ok c
  | IReturnFruit _ _ _ => ok c
  | IExit _ => ok c
  | IInvoke x keys actions i =>
    (* TODO: Do something with keys? *)
    let rec_act_call := fun '(nm, act) acc_opt =>
        let* acc := acc_opt in
        let+ act' := elaborate_header_stacks act in
        (nm, act') :: acc
    in
    let+ actions' := fold_right rec_act_call (ok []) actions in
    IInvoke x keys actions' i
  | IExternMethodCall extern method arrow tags =>
    let arrow := elaborate_arrowE arrow in
    ok (IExternMethodCall extern method arrow tags)
  | ISetValidity _ _ _ =>
    (* TODO Eliminate header stack literals from expressions *)
    ok c
  | IHeaderStackOp stck typ ST.HSPush n tags =>
    let seq := fun hidx lodx => ISeq hidx lodx tags in
    let indexed_stck := fun i => stck ++ "["++ string_of_nat i++"]" in
    let mk_ith_stack_copy :=
        fun i => IAssign typ
                         (E.EVar typ (indexed_stck i) tags)
                         (E.EVar typ (indexed_stck (i-1)) tags)
                         tags
    in
    ok (ifold (BinPos.Pos.to_nat n - 2) (fun i => seq (mk_ith_stack_copy (i+1)))
              (ISetValidity (E.EVar typ (indexed_stck 0) tags) true tags))
  | IHeaderStackOp stck typ ST.HSPop n tags =>
    let seq := fun hidx lodx => ISeq lodx hidx tags in
    let indexed_stck := fun i => stck ++ "["++ string_of_nat i++"]" in
    let mk_ith_stack_copy :=
        fun i => IAssign typ
                         (E.EVar typ (indexed_stck i) tags)
                         (E.EVar typ (indexed_stck (i+1)) tags)
                         tags
    in
    let n := BinPos.Pos.to_nat n in
    ok (ifold (n - 2) (fun i => seq (mk_ith_stack_copy i))
              (ISetValidity (E.EVar typ (indexed_stck (n-1)) tags) true tags))
  end.

Fixpoint struct_fields (s : string) (fields : F.fs string E.t) : list (string * E.t)  :=
  F.fold (fun f typ acc => (s ++ "__s__" ++ f, typ) :: acc ) fields [].

(** TODO: Compiler pass to elaborate structs *)
Fixpoint elaborate_structs (c : Inline.t) : result Inline.t :=
  match c with
  | ISkip _ => ok c
  | IVardecl type s i =>
    match type with
    | E.TStruct fields =>
      let vars := struct_fields s fields in
      let elabd_hdr_decls := fold_left (fun acc '(var_str, var_typ) => ISeq (IVardecl var_typ var_str i) acc i) vars (ISkip i) in
      ok elabd_hdr_decls
    | _ => ok c
    end
  | IAssign type lhs rhs i =>
    match type with
    | E.TStruct fields =>
      (** TODO : What other assignments to headers are legal? EHeader? EStruct? *)
      match lhs, rhs with
      | E.EVar _ l il, E.EVar _ r ir =>
        let lvars := struct_fields l fields in
        let rvars := struct_fields r fields in
        let+ lrvars := zip lvars rvars in
        fold_right (fun '((lvar, ltyp),(rvar, rtyp)) acc => ISeq (IAssign ltyp (E.EVar ltyp lvar il) (E.EVar rtyp rvar ir) i) acc i) (ISkip i) lrvars
      | E.EVar _ l il, E.EStruct explicit_fields i =>
        let lvars := struct_fields l fields in
        let assign_fields := fun '(lvar, ltyp) acc_opt =>
             let* acc := acc_opt in
             let*~ rval := F.find_value (String.eqb lvar) explicit_fields else "couldnt find field name in struct literal "in
             ok (ISeq (IAssign ltyp (E.EVar ltyp lvar il) rval i) acc i) in
        fold_right assign_fields
           (ok (ISkip i))
           lvars
      | _, _ =>
         error "Can only elaborate struct assignments of the form var := {var | struct literal}"
      end
    | _ => ok c
  end
  | IConditional guard_type guard tru fls i =>
    (** TODO: elaborate headers in guard? *)
    let* tru' := elaborate_headers tru in
    let+ fls' := elaborate_headers fls in
    IConditional guard_type guard tru' fls' i
  | ISeq s1 s2 i =>
    let* s1' := elaborate_headers s1 in
    let+ s2' := elaborate_headers s2 in
    ISeq s1' s2' i

  | IBlock b =>
    let+ b' := elaborate_headers b in
    IBlock b'
  | IReturnVoid _ => ok c
  | IReturnFruit _ _ _ => ok c
  | IExit _ => ok c
  | IInvoke x keys actions i =>
    let opt_actions := map_snd elaborate_structs actions in
    let+ actions' := rred (List.map res_snd opt_actions) in
    IInvoke x keys actions' i
  | IExternMethodCall extern method arrow tags =>
    let arrow := elaborate_arrowE arrow in
    ok (IExternMethodCall extern method arrow tags)
  | ISetValidity _ _ _ =>
    (* TODO Elaborate header stacks in expressions *)
    ok c
  | IHeaderStackOp _ _ _ _ _ =>
    ok c
end.
End Inline.
