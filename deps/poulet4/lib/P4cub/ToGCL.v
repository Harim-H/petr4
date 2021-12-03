Require Import Coq.Program.Basics.
Require Export Poulet4.P4cub.Syntax.AST.
Require Export Poulet4.P4Arith.
Require Export Poulet4.P4cub.Envn.
Require Export Poulet4.P4cub.BigStep.InstUtil.
Require Export Poulet4.P4cub.BigStep.BigStep.
Require Export Poulet4.P4cub.BigStep.Semantics.
Require Export Poulet4.P4cub.BigStep.Value.Value.
Require Export Poulet4.P4cub.Util.Result.
Require Import Coq.Arith.EqNat.
Require Import String.
Open Scope string_scope.

Require Import Poulet4.P4cub.Inline.
Require Import Poulet4.ToP4cub.

Import Env.EnvNotations.

Import Result.
Import ResultNotations.

Import Poulet4.P4cub.Util.ListUtil.
Import Poulet4.P4cub.Util.StringUtil.

Require Import Poulet4.P4cub.GCL.


(** Compile to GCL *)
Module ST := Stmt.
Module CD := Control.
Module E := Expr.
Module F := F.
Module BV := GCL.BitVec.


Section ToGCL.
  Variable tags_t : Type.

  Record ctx : Type :=
    mkCtx { stack : list nat; (* The current block stack *)
            used : list nat;  (* indices that have already been used *)
            locals : list string; (* variables in the current scope *)
            may_have_exited: bool;
            may_have_returned: bool;
          }.
  (* TODO make sure that you check the variables are unique. fresh name generator based on variables that are in scope *)

  Definition initial :=
    {| stack := [0];
       used := [];
       locals := [];
       may_have_exited  := false;
       may_have_returned := false;
    |}.

  Definition incr (c : ctx) : ctx :=
    let new_idx := S(list_max (c.(stack) ++ c.(used))) in
    {| stack := new_idx :: c.(stack);
       used := c.(used);
       locals := [];
       may_have_exited := c.(may_have_exited);
       may_have_returned := false;
    |}.

  Definition current (c : ctx) : result nat :=
    match c.(stack) with
    | [] => error "Tried to get context counter from empty context"
    | idx :: _ => ok idx
    end.

  Definition decr (old_ctx : ctx) (new_ctx : ctx)  : result ctx :=
    match new_ctx.(stack) with
    | [] => error "Tried decrement empty counter"
    | idx :: idxs =>
      let ctx' := {| stack := idxs;
                     used := idx :: new_ctx.(stack);
                     locals := old_ctx.(locals);
                     may_have_exited := old_ctx.(may_have_exited) || new_ctx.(may_have_exited);
                     may_have_returned := old_ctx.(may_have_returned);
                  |} in
      ok ctx'
    end.

  Definition update_exit (c : ctx) (b : bool) :=
    {| stack := c.(stack);
       used := c.(used);
       locals := c.(locals);
       may_have_exited := b;
       may_have_returned := c.(may_have_returned)
    |}.

  Definition join (tctx fctx : ctx) : result ctx :=
    if list_eq Nat.eqb tctx.(stack) fctx.(stack)
    then ok {| stack := tctx.(stack);
               used := tctx.(used) ++ fctx.(used);
               locals := intersect_string_list tctx.(locals) fctx.(locals);
               may_have_exited := tctx.(may_have_exited) || fctx.(may_have_exited);
               may_have_returned := tctx.(may_have_returned) || fctx.(may_have_returned)
            |}
    else error "Tried to join two contexts with different context counters".

  Definition retvar_name (c : ctx) : string :=
    fold_right (fun idx acc => acc ++ (string_of_nat idx)) "return" c.(stack).

  Definition retvar (c : ctx) (i : tags_t) : E.e tags_t :=
    E.EVar E.TBool (retvar_name c) i.

  Definition add_to_scope (c : ctx) (v : string) :=
    {| stack := c.(stack);
       used := c.(used);
       locals := v :: c.(locals);
       may_have_exited := c.(may_have_exited);
       may_have_returned := c.(may_have_returned);
    |}.

  Definition is_local (c : ctx) (v : string) : bool :=
    string_member v (c.(locals)).

  Definition scope_name (v : string) (idx : nat) : string :=
    v ++ "__$__" ++ string_of_nat idx.


  Definition relabel_for_scope (c : ctx) (v : string) : string :=
    if is_local c v
    then match current c with
         | Error _ _ => v
         | Ok _ idx => scope_name v idx
         end
    else v.

  Definition target := @GCL.t tags_t string (BV.t tags_t) (Form.t tags_t).

  Definition extern : Type := Env.t string target.
  (* TODO :: Think about calling out to external functions for an interpreter*)
  Definition model : Type := Env.t string extern.
  Definition find (m : model) (e f : string) : result (GCL.t tags_t) :=
    let*~ ext := Env.find e m else "couldn't find extern " ++ e ++ " in model" in
    let*~ fn := Env.find f ext else "couldn't find field " ++ f ++ " in extern" in
    ok fn.
  Definition empty : model := Env.empty string extern.
  Definition pipeline : Type := list E.t -> E.constructor_args tags_t -> result (ST.s tags_t).

  Section Instr.

    Variable instr : (string -> tags_t -> list (nat * BitVec.t tags_t * E.matchkind) -> list (string * target) -> result target).

    Definition pos := GCL.pos.
    Fixpoint scopify (ctx : ctx) (e : E.e tags_t) : E.e tags_t :=
      match e with
      | E.EBool _ _ => e
      | E.EBit _ _ _ => e
      | E.EInt _ _ _ => e
      | E.EVar typ x i =>
        let x' := relabel_for_scope ctx x in
        E.EVar typ x' i
      | E.ESlice e hi lo i =>
        E.ESlice (scopify ctx e) hi lo i
      | E.ECast type arg i =>
        E.ECast type (scopify ctx arg) i
      | E.EUop op type arg i =>
        E.EUop op type (scopify ctx arg) i
      | E.EBop typ op lhs rhs i =>
        E.EBop typ op (scopify ctx lhs) (scopify ctx rhs) i
      | E.ETuple es i =>
        E.ETuple (List.map (scopify ctx) es) i
      | E.EStruct fields i =>
        E.EStruct (F.map (scopify ctx) fields) i
      | E.EHeader fields valid i =>
        E.EHeader (F.map (scopify ctx) fields) (scopify ctx valid) i
      | E.EExprMember mem expr_type arg i =>
        E.EExprMember mem expr_type (scopify ctx arg) i
      | E.EError _ _ => e
      | E.EMatchKind _ _ => e
      | E.EHeaderStack fields headers next_index i =>
        E.EHeaderStack fields (List.map (scopify ctx) headers) next_index i
      | E.EHeaderStackAccess fs stack index i =>
        E.EHeaderStackAccess fs (scopify ctx stack) index i
      end.
    (**[]*)

    Definition iteb (guard : Form.t tags_t) (tru fls : target) (i : tags_t) : target :=
      GCL.GChoice _ (GCL.GSeq _ (GCL.GAssume _ guard) tru) (GCL.GSeq _ (GCL.GAssume _ (Form.LNot _ guard i)) fls).

    Definition seq (i : tags_t) (res1 res2 : (target * ctx)) : target * ctx :=
      let (g1, ctx1) := res1 in
      let (g2, ctx2) := res2 in
      let g2' :=
          if may_have_returned ctx1
          then (iteb (GCL.is_true _ (retvar_name ctx1) i) (GCL.GSkip _ i) g2 i)
          else g2 in
      let g2'' :=
          if may_have_exited ctx1
          then (iteb (GCL.exit _ i) (GCL.GSkip _ i) g2 i)
          else g2' in
      (GCL.GSeq _ g1 g2'', ctx2).

    Definition string_of_z (x : Z) :=
      if BinInt.Z.ltb x (Z0)
      then "-" ++ string_of_nat (BinInt.Z.abs_nat x)
      else string_of_nat (BinInt.Z.abs_nat x).

    Fixpoint to_lvalue (e : E.e tags_t) : result string :=
      match e with
      | E.EBool _ _ => error "Boolean Literals are not lvalues"
      | E.EBit _ _ _ => error "BitVector Literals are not lvalues"
      | E.EInt _ _ _ => error "Integer literals are not lvalues"
      | E.EVar t x i => ok x
      | E.ESlice e hi lo pos =>
        (* TODO :: Allow assignment to slices *)
        error "[FIXME] Slices are not l-values "
      | E.ECast _ _ _ => error "Casts are not l-values"
      | E.EUop _ _ _ _ => error "Unary Operations are not l-values"
      | E.EBop _ _ _ _ _ => error "Binary Operations are not l-values"
      | E.ETuple _ _ => error "Explicit Tuples are not l-values"
      | E.EStruct _ _ => error "Explicit Structs are not l-values"
      | E.EHeader _ _ _ => error "Explicit Headers are not l-values"
      | E.EExprMember expr_type mem arg i =>
        let+ lv := to_lvalue arg in
        lv ++ "." ++ mem
      | E.EError _ _ => error "errors are not l-values"
      | E.EMatchKind _ _ => error "Match Kinds are not l-values"
      | E.EHeaderStack _ _ _ _ => error "Header Stacks are not l-values"
      | E.EHeaderStackAccess _ stack index i =>
        let+ lv := to_lvalue stack in
        (** TODO How to handle negative indices? **)
        lv ++ "["++ (string_of_z index) ++ "]"
      end.

    Definition width_of_type (x:string) (t : E.t) : result nat :=
      match t with
      | E.TBool => ok 1
      | E.TBit w => ok (BinNat.N.to_nat w)
      | E.TInt w => ok (BinPos.Pos.to_nat w)
      | E.TVar tx => error ("Cannot get the width of a typ variable " ++ tx ++ " for var " ++ x)
      | E.TError => error ("Cannot get the width of an ErrorType for var " ++ x)
      | E.TMatchKind => error ("Cannot get the width of a Match Kind Type for var" ++ x)
      | E.TTuple types => error ("Cannot get the width of a Tuple Type for var" ++ x)
      | E.TStruct fields => error ("Cannot get the width of a Struct Type for var " ++ x)
      | E.THeader fields => error ("Cannot get the width of a Header Type for var" ++ x)
      | E.THeaderStack fields size => error ("Cannot get the width of a header stack type for var" ++ x)
      end.

    Definition get_header_of_stack (stack : E.e tags_t) : result E.t :=
      match stack with
      | E.EHeaderStack fields headers next_index i =>
        ok (E.THeader fields)
      | _ => error "Tried to get the base header of something other than a header stack."
      end.

    Fixpoint to_header_string (e : (E.e tags_t)) : result string :=
      match e with
      | E.EBool _ _ => error "A Boolean is not a header"
      | E.EBit _ _ _ => error "A bitvector literal is not a header"
      | E.EInt _ _ _ => error "An integer literal is not a header"
      | E.EVar t x i =>
        match t with
        | E.THeader _ => ok x
        | _ => error "Got variable, but the header itself was no good"
        end
      | E.ESlice _ _ _ _ => error "A Slice is not a header"
      | E.ECast _ _ _ => error "A Cast is not a header"
      | E.EUop _ _ _ _ => error "No unary operation is a header"
      | E.EBop _ _ _ _ _ => error "No binary operation is a header"
      | E.ETuple _ _ => error "A Tuple is not a header"
      | E.EStruct _ _ => error "Structs are not headers"
      | E.EHeader _ _ _ =>
        error "Header literals should not be keys"
      | E.EExprMember expr_type mem arg i =>
        let+ str := to_header_string arg in
        str ++ "." ++ mem
      | E.EError _ _ => error "errors are not header strings"
      | E.EMatchKind _ _ => error "MatchKinds are not header strings"
      | E.EHeaderStack _ _ _ _ =>
        error "Header stacks are not headers"
      | E.EHeaderStackAccess _ stack index i =>
        error "Header stack accesses as table keys should have been factored out in an earlier stage."
      end.

    Definition lookup_member_from_fields mem fields : result E.t :=
      match F.find_value (String.eqb mem) fields with
      | None => error ("cannot find " ++ mem ++ "in type")
      | Some t => ok t
      end.

    Definition lookup_member_type_from_type (mem : string) (typ : E.t) : result E.t :=
      match typ with
      | E.TStruct fields =>
        lookup_member_from_fields mem fields
      | E.THeader fields =>
        lookup_member_from_fields mem fields
      | E.TVar v =>
        error ("Error :: Type variable " ++ v ++ "  should've been removed")
      | _ =>
        error "don't know how to extract member from type that has no members"
      end.

    Fixpoint to_rvalue (e : (E.e tags_t)) : result (BV.t tags_t) :=
      match e with
      | E.EBool b i =>
        if b
        then ok (BV.bit _ 1 1 i)
        else ok (BV.bit _ 0 1 i)
      | E.EBit w v i =>
        ok (BV.bit _  (BinInt.Z.to_nat v) (BinNat.N.to_nat w) i)
      | E.EInt _ _ _ =>
        (** TODO Figure out how to handle ints *)
        error "[FIXME] Cannot translate signed ints to bivectors"
      | E.EVar t x i =>
        let+ w := width_of_type x t in
        BV.BVVar _ x w i

      | E.ESlice e hi lo i =>
        let+ rv_e := to_rvalue e in
        BV.UnOp _ (BV.BVSlice (BinPos.Pos.to_nat hi) (BinPos.Pos.to_nat lo)) rv_e i
      | E.ECast type arg i =>
        let* rvalue_arg := to_rvalue arg in
        let cast := fun w => ok (BV.UnOp _ (BV.BVCast w) rvalue_arg i) in
        match type with
        | E.TBool => cast 1
        | E.TBit w => cast (BinNat.N.to_nat w)
        | E.TInt w => error "[FIXME] Signed Integers are unimplemented "
        | _ =>
          error "Illegal cast, should've been caught by the type-checker"
        end
      | E.EUop type op arg i =>
        match op with
        | E.Not =>
          let+ rv_arg := to_rvalue arg in
          BV.UnOp _ BV.BVNeg rv_arg i
        | E.BitNot =>
          let+ rv_arg := to_rvalue arg in
          BV.UnOp _ BV.BVNeg rv_arg i
        | E.UMinus => error "[FIXME] Subtraction is unimplemented"
        | E.IsValid =>
          let+ header := to_header_string arg in
          let hvld := header ++ ".is_valid" in
          BV.BVVar _ hvld 1 i
        | E.SetValid => (* TODO @Rudy isn't this a command? *)
          error "SetValid as an expression is deprecated"
        | E.SetInValid =>
          error "SetInValid as an expression is deprecated"
        | E.NextIndex =>
          error "[FIXME] NextIndex for Header Stacks is unimplemented"
        | E.Size =>
          error "[FIXME] Size for Header Stacks is unimplmented"
        end
      | E.EBop typ op lhs rhs i =>
        let* l := to_rvalue lhs in
        let* r := to_rvalue rhs in
        let bin := fun o => ok (BV.BinOp _ o l r i) in
        let* signed :=
           match typ with
           | E.TBit _ => ok false
           | E.TInt _ => ok true
           | _ => error "Typeerror: exected (un)singed bitvec for binar expression"
           end
        in
        match op with
        | E.Plus => bin (BV.BVPlus false signed)
        | E.PlusSat => bin (BV.BVPlus true signed)
        | E.Minus => bin (BV.BVMinus false signed)
        | E.MinusSat => bin (BV.BVMinus true signed)
        | E.Times => bin (BV.BVTimes signed)
        | E.Shl => bin (BV.BVShl signed)
        | E.Shr => bin (BV.BVShr signed)
        | E.Le => error "Typeerror: (<=) is a boolean, expected BV expression"
        | E.Ge => error "Typeerror: (>=) is a boolean, expected BV expression"
        | E.Lt => error "Typeerror: (<) is a boolean, expected BV expression"
        | E.Gt => error "Typeerror: (>) is a boolean, expected BV expression"
        | E.Eq => error "Typeerror: (=) is a boolean, expected BV expression"
        | E.NotEq => error "Typeerror: (!=) is a boolean, expected BV expression"
        | E.BitAnd => bin BV.BVAnd
        | E.BitXor => bin BV.BVXor
        | E.BitOr => bin BV.BVOr
        | E.PlusPlus => bin BV.BVConcat
        | E.And => error "Typeerror: (&&) is a boolean, expected BV expression"
        | E.Or => error "Typeerror: (||) is a boolean, expected BV expression"
        end
      | E.ETuple _ _ =>
        error "Tuples in the rvalue position should have been factored out by previous passes"
      | E.EStruct _ _ =>
        error "Structs in the rvalue position should have been factored out by previous passes"
      | E.EHeader _ _ _ =>
        error "Header in the rvalue positon should have been factored out by previous passes"
      | E.EExprMember ret_type mem arg i =>
        let* w := width_of_type mem ret_type in
        let+ lv := to_lvalue arg in
        BV.BVVar _  (lv ++ "." ++ mem) w i
      | E.EError _ _ => error "errors are not rvalues."
      | E.EMatchKind _ _ => error "MatchKinds are not rvalues"
      | E.EHeaderStack _ _ _ _ =>
        error "Header stacks in the rvalue position should have been factored out by previous passes"
      | E.EHeaderStackAccess _ stack index i =>
        error "Header stack accesses in the rvalue position should have been factored out by previous passes."
      end.

    Fixpoint to_form (e : (E.e tags_t)) : result (Form.t tags_t) :=
      match e with
      | E.EBool b i => ok (Form.LBool _ b i)
      | E.EBit _ _ _ =>
        error "Typeerror: Bitvector literals are not booleans (perhaps you want to insert a cast?)"
      | E.EInt _ _ _ =>
        error "Typeerror: Signed Ints are not booleans (perhaps you want to insert a cast?)"
      | E.EVar t x i =>
        match t with
        | E.TBool => ok (Form.LVar _ x i)
        | _ =>
          error "Typeerror: Expected a Boolean form, got something else (perhaps you want to insert a cast?)"
        end

      | E.ESlice e hi lo i =>
        error "Typeerror: BitVector Slices are not booleans (perhaps you want to insert a cast?)"

      | E.ECast type arg i =>
        let* rvalue_arg := to_rvalue arg in
        let cast := fun w => ok (GCL.isone _ (BV.UnOp _ (BV.BVCast w) rvalue_arg i) i) in
        match type with
        | E.TBool => cast 1
        | E.TBit w => cast (BinNat.N.to_nat w)
        | E.TInt w => error "[FIXME] Handle Signed Integers"
        | _ =>
          error "Invalid Cast"
        end
      | E.EUop type op arg i =>
        let* rv_arg := to_rvalue arg in
        match op with
        | E.Not => ok (GCL.isone _ (BV.UnOp _ BV.BVNeg rv_arg i) i)
        | E.BitNot => error "Bitvector operations (!) are not booleans (perhaps you want to insert a cast?)"
        | E.UMinus => error "Saturating arithmetic (-) is not boolean (perhaps you want to insert a cast?)"
        | E.IsValid =>
          let+ header := to_lvalue arg in
          let hvld := header ++ ".is_valid" in
          GCL.isone _ (BV.BVVar _ hvld 1 i) i
        | E.SetValid =>
          error "SetValid is deprecated as an expression"
        | E.SetInValid =>
          error "SetInValid is deprecated as an expression"
        | E.NextIndex =>
          error "[FIXME] Next Index for stacks is unimplemented"
        | E.Size =>
          error "[FIXME] Size for stacks is unimplemented"
        end
      | E.EBop typ op lhs rhs i =>
        let signed := match typ with
                      | E.TBit _ => ok false
                      | E.TInt _ => ok true
                      | _ => error "Typerror:: expected (signed) bitvector as argument binary operator"
                      end in
        let lbin := fun o_res => let* l := to_form lhs in
                                 let* r := to_form rhs in
                                 let+ o := o_res in
                                 Form.LBop _ o l r i in
        let cbin := fun o_res => let* l := to_rvalue lhs in
                                 let* r := to_rvalue rhs in
                                 let+ o := o_res in
                                 Form.LComp _ o l r i in
        match op with
        | E.Plus => error "Typeerror: (+) is not a boolean operator"
        | E.PlusSat => error "Typeerror: (|+|) is not a boolean operator"
        | E.Minus => error "Typeerror: (-) is not a boolean operator"
        | E.MinusSat => error "Typeerror: (|-|) is not a boolean operator"
        | E.Times => error "Typerror: (*) is not a boolean operator"
        | E.Shl => error "Typerror: (<<) is not a boolean operator"
        | E.Shr => error "TYperror: (>>) is not a boolean operator"
        | E.Le => cbin (Form.LLe |=> signed)
        | E.Ge => cbin (Form.LGe |=> signed)
        | E.Lt => cbin (Form.LLt |=> signed)
        | E.Gt => cbin (Form.LGt |=> signed)
        | E.Eq => cbin (ok Form.LEq)
        | E.NotEq => cbin (ok Form.LNeq)
        | E.BitAnd => error "Typeerror: (&) is not a boolean operator"
        | E.BitXor => error "Typeerror: (^) is not a boolean operator"
        | E.BitOr => error "Typeerror: (|) is not a boolean operator"
        | E.PlusPlus => error "Typeerror: (++) is not a boolean operator"
        | E.And => lbin (ok Form.LAnd)
        | E.Or => lbin (ok Form.LOr)
        end
      | E.ETuple _ _ =>
        error "Tuples are not formulae"
      | E.EStruct _ _ =>
        error "Structs are not formulae"
      | E.EHeader _ _ _ =>
        error "Headers are not formulae"
      | E.EExprMember expr_type mem arg i =>
        let* lv := to_lvalue arg in
        let~ w := (width_of_type mem expr_type) over ("failed getting type of " ++ mem) in
        ok (GCL.isone _ (BV.BVVar _ lv w i) i)
      | E.EError _ _ =>
        error "errors are not formulae"
      | E.EMatchKind _ _ =>
        error "Matchkinds are not formulae"
      | E.EHeaderStack _ _ _ _ =>
        error "HeaderStacks are not formulae"
      | E.EHeaderStackAccess _ stack index i =>
        error "Headers (from header stack accesses) are not formulae"
      end.

    Definition cond (guard_type : E.t) (guard : E.e tags_t) (i : tags_t) (tres fres : (target * ctx)) : result (target * ctx) :=
      let (tg, tctx) := tres in
      let (fg, fctx) := fres in
      let* ctx := join tctx fctx in
      let* phi := to_form guard in
      ok (iteb phi tg fg i, ctx).

    Fixpoint inline_to_gcl (c : ctx) (arch : model) (s : Inline.t tags_t) : result (target * ctx) :=
      match s with
      | Inline.ISkip _ i =>
        ok (GCL.GSkip _ i, c)

      | Inline.IVardecl _ typ x i =>
        ok (GCL.GSkip _ i, add_to_scope c x)

      | Inline.IAssign _ type lhs rhs i =>
        let* lhs' := to_lvalue (scopify c lhs) in
        let+ rhs' := to_rvalue (scopify c rhs) in
        let e := GCL.GAssign _ type lhs' rhs' i in
        (e, c)

      | Inline.IConditional _ guard_type guard tru_blk fls_blk i =>
        let* tru_blk' := inline_to_gcl c arch tru_blk in
        let* fls_blk' := inline_to_gcl c arch fls_blk in
        cond guard_type (scopify c guard) i tru_blk' fls_blk'

      | Inline.ISeq _ s1 s2 i =>
        let* g1 := inline_to_gcl c arch s1 in
        let+ g2 := inline_to_gcl (snd g1) arch s2 in
        seq i g1 g2

      | Inline.IBlock _ s =>
        let* (gcl, c') := inline_to_gcl (incr c) arch s in
        let+ c'' := decr c c' in
        (gcl, c'')

      | Inline.IReturnVoid _ i =>
        let g_asn := @GCL.GAssign _ string (BV.t _) (Form.t _) in
        ok (g_asn (E.TBit (BinNat.N.of_nat 1)) (retvar_name c) (BV.bit _ 1 1 i) i, c)

      | Inline.IReturnFruit _ typ expr i =>
        (** TODO create var for return type & save it *)
        ok (GCL.GAssign _ (E.TBit (BinNat.N.of_nat 1)) (retvar_name c) (BV.bit _ 1 1 i) i, c)

      | Inline.IExit _ i =>
        ok (GCL.GAssign _ (E.TBit (BinNat.N.of_nat 1)) "exit" (BV.bit _ 1 1 i) i, update_exit c true)

      | Inline.IInvoke _ tbl keys actions i =>
        let* actions' := union_map_snd (fst >>=> inline_to_gcl c arch) actions in
        let* keys' := rred (map (fun '(t,e,mk) =>
                                   let* w := width_of_type (tbl ++ " key") t in
                                   let+ e' := to_rvalue e in
                                   (w, e', mk)) keys) in
        let+ g := instr tbl i keys' actions' in
        (g, c)

      | Inline.IExternMethodCall _  ext method args i =>
        (** TODO handle copy-in/copy-out) *)
        let+ g := find arch ext method in
        (g, c)
      | Inline.ISetValidity _ e v i =>
        let+ header := to_lvalue e in
        let hvld := header ++ ".is_valid" in
        let vld_bit := if v then 1 else 0 in
        (GCL.GAssign _ (E.TBit (BinNat.N.of_nat 1)) hvld (BV.BitVec _ vld_bit (Some 1) i) i, c)
      end.

    Definition p4cub_statement_to_gcl (gas : nat)
               (ctx : ToP4cub.DeclCtx tags_t)
               (arch : model) (s : ST.s tags_t) : result target :=
      let* inline_stmt := Inline.inline _ gas ctx s in
      let* no_tup := Inline.elim_tuple _ inline_stmt in
      let* no_stk := Inline.elaborate_header_stacks _ no_tup in
      let* no_hdr := Inline.elaborate_headers _ no_stk in
      let* no_structs := Inline.elaborate_structs _ no_hdr in
      let+ (gcl,_) := inline_to_gcl initial arch no_structs in
      gcl.

    (* use externs to specify inter-pipeline behavior.*)
    Definition get_main ctx (pipe : pipeline) : result (ST.s tags_t) :=
      match find_package tags_t ctx "main" with
      | Some (TD.TPInstantiate cname _ type_args args i) =>
        pipe type_args args
      | _ =>
        error "expected package, got sth else"
      end
    .

    Definition p4cub_to_gcl (gas : nat) (ext : model) (pipe : pipeline) (ctx : ToP4cub.DeclCtx tags_t) : result target :=
      let* stmt := get_main ctx pipe in
      p4cub_statement_to_gcl gas ctx ext stmt.

  End Instr.
End ToGCL.
