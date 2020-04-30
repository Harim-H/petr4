module I = Info
open Core_kernel
open Env
open Types
open Value
module Info = I (* JNF: ugly hack *)
let (=) = Stdlib.(=)
let (<>) = Stdlib.(<>)

(*----------------------------------------------------------------------------*)
(* Declaration Evaluation *)
(*----------------------------------------------------------------------------*)

let rec eval_decl (env : EvalEnv.t) (ctrl : ctrl) (d : Declaration.t) : EvalEnv.t =
  match snd d with
  | Constant {
      annotations = _;
      typ = t;
      value = v;
      name = (_,n);
    } -> eval_const_decl env ctrl t v n
  | Instantiation {
      annotations = _;
      typ = typ;
      args = args;
      name = (_,n);
      init = None
    } -> eval_instantiation env ctrl typ args n
  | Instantiation { init = Some _; _ } ->
     failwith "evaluating instantiations with initializers is unimplemented"
  | Parser {
      annotations = _;
      name = (_,n);
      type_params = _;
      params = _;
      constructor_params = _;
      locals = _;
      states = _;
    } -> eval_parser_decl env n d
  | Control {
      annotations = _;
      name = (_,n);
      type_params = _;
      params = _;
      constructor_params = _;
      locals = _;
      apply = _;
    } -> eval_control_decl env n d
  | Function {
      return = _;
      name = (_,n);
      type_params = _;
      params = ps;
      body = b;
    } -> eval_fun_decl env n ps b d
  | ExternFunction {
      annotations = _;
      return = _;
      name = (_,n);
      type_params = _;
      params = ps;
    } -> eval_extern_fun env n ps d
  | Variable {
      annotations = _;
      typ = t;
      name = (_,n);
      init = v;
    } -> eval_var_decl env ctrl t n v |> fst
  | ValueSet {
      annotations = _;
      typ = t;
      size = s;
      name = (_,n);
    } -> eval_set_decl env ctrl t n s |> fst
  | Action {
      annotations = _;
      name = (_,n);
      params = ps;
      body = b;
    } -> eval_action_decl env n ps b d
  | Table {
      annotations = _;
      name = (_,n);
      properties = ps;
    } -> eval_table_decl env ctrl n d ps
  | Header {
      annotations = _;
      name = (_,n);
      fields = _;
    } -> eval_header_decl env n d
  | HeaderUnion {
      annotations = _;
      name = (_,n);
      fields = _;
    } -> eval_union_decl env n d
  | Struct {
      annotations = _;
      name = (_,n);
      fields = _;
    } -> eval_struct_decl env n d
  | Error {
      members = l;
    } -> eval_error_decl env l
  | MatchKind {
      members = _;
    } -> eval_matchkind_decl env d
  | Enum {
      annotations = _;
      name = (_,n);
      members = _;
    } -> eval_enum_decl env n d
  | SerializableEnum {
      annotations = _;
      typ = _;
      name = (_,n);
      members = _;
    } -> eval_senum_decl env n d
  | ExternObject {
      annotations = _;
      name = (_,n);
      type_params = tps;
      methods = ms;
    } -> eval_extern_obj env n ms d
  | TypeDef {
      annotations = _;
      name = (_,n);
      typ_or_decl = _;
    } -> eval_type_def env n d
  | NewType {
      annotations = _;
      name = (_,n);
      typ_or_decl = _;
    } -> eval_type_decl env n d
  | ControlType {
      annotations = _;
      name = (_,n);
      type_params = _;
      params = _;
    } -> eval_ctrltyp_decl env n d
  | ParserType {
      annotations = _;
      name = (_,n);
      type_params = _;
      params = _;
    } -> eval_prsrtyp_decl env n d
  | PackageType {
      annotations = _;
      name = (_,n);
      type_params = _;
      params = _;
    } -> eval_pkgtyp_decl env n d

and eval_const_decl (env : EvalEnv.t) (ctrl : ctrl) (typ : Type.t) (e : Expression.t)
    (name : string) : EvalEnv.t =
  let name_expr = (Info.dummy, Expression.Name(Info.dummy, name)) in
  let env' = EvalEnv.insert_typ name typ env in
  fst (eval_assign env' ctrl SContinue name_expr e)

and eval_instantiation (env:EvalEnv.t) (ctrl : ctrl) (typ : Type.t)
    (args : Argument.t list) (name : string) : EvalEnv.t =
  let (env', _,obj) = eval_nameless env ctrl typ args in
  EvalEnv.insert_val name obj env'

and eval_parser_decl (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_control_decl (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_fun_decl (env : EvalEnv.t) (name : string) (params : Parameter.t list)
    (body : Block.t) (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_val name (VFun{params;body}) env
  |> EvalEnv.insert_decl name decl

and eval_extern_fun (env : EvalEnv.t) (name : string)
    (params : Parameter.t list) (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_var_decl (env : EvalEnv.t) (ctrl : ctrl) (typ : Type.t) (name : string)
    (init : Expression.t option) : EvalEnv.t * signal =
  let env' = EvalEnv.insert_typ name typ env in
  match init with
  | None ->
    let env'' = EvalEnv.insert_val name (init_val_of_typ env' ctrl typ) env' in
    (env'', SContinue)
  | Some e ->
    let (env'', s, v) = eval_expression' env' ctrl SContinue e in
    match s with
    | SContinue -> (EvalEnv.insert_val name v env'', s)
    | SReject _ -> (env, s)
    | SReturn _ -> failwith "variable declaration should not return"
    | SExit -> failwith "variable declaration should not exit"

and eval_set_decl (env : EvalEnv.t) (ctrl : ctrl) (typ : Type.t) (name : string)
    (size : Expression.t) : EvalEnv.t * signal =
  let env' = EvalEnv.insert_typ name typ env in
  let (env'', s, size') = eval_expression' env' ctrl SContinue size in
  let size'' = assert_rawint size' in
  match s with
  | SContinue ->
    let ms = snd ctrl in
    if Bigint.(Bigint.of_int (List.length ms) > size'')
    then failwith "too many elements inserted to value set"
    else
    let vset = VSet (SValueSet{size=size';members=ms;sets=[]}) in
    let env''' = EvalEnv.insert_val name vset env'' in
    (env''', s)
  | SReject _ -> (env, s)
  | _ -> failwith "value set declaration should not return or exit"

and eval_action_decl (env : EvalEnv.t) (name : string) (params : Parameter.t list)
    (body : Block.t) (decl : Declaration.t) : EvalEnv.t  =
  EvalEnv.insert_val name (VAction{params; body}) env
  |> EvalEnv.insert_decl name decl

and eval_table_decl (env : EvalEnv.t) (ctrl : ctrl) (name : string)
    (decl : Declaration.t) (props : Table.property list) : EvalEnv.t =
  let props' = List.map props ~f:snd in
  let env' = EvalEnv.insert_decl name decl env in
  let ctrl_entries = fst ctrl in
  let pre_ks = List.filter props' ~f:is_key
               |> List.hd_exn
               |> assert_key
               |> List.map ~f:snd in
  let key = pre_ks |> List.map ~f:(fun k -> k.key) in
  let mks = pre_ks |> List.map ~f:(fun k -> snd k.match_kind) in
  let ((env'',s), ks) = List.fold_map key ~init:(env', SContinue)
      ~f:(fun (a, b) k ->

          let x,y,z = eval_expression' a ctrl b k in ((x,y),z)) in
  let f ((w,x,y),z) = ((w,x),(y,z)) in
  let sort_mks = check_lpm_count mks in
  let ws = List.map ks ~f:width_of_val in
  let ((env''',s'),entries) =
    match List.filter props' ~f:is_entries with
    | [] -> List.fold_map ctrl_entries ~init:(env'',s)
              ~f:(fun (a,b) c -> (set_of_matches a ctrl b c.matches ws, c.action) |> f)
    | l -> l
            |> List.hd_exn
            |> assert_entries
            |> List.map ~f:snd
            |> List.fold_map ~init:(env'',s)
              ~f:(fun (a,b) c -> (set_of_matches a ctrl b c.matches ws, c.action) |> f) in
  let actions = List.filter props' ~f:is_actionref
                |> List.hd_exn
                |> assert_actionref in
  let default = List.filter props' ~f:is_default
                |> default_of_defaults in
  let (final_entries, ks') = if List.equal String.equal mks ["lpm"] then (sort_lpm entries, ks)
    else if sort_mks then filter_lpm_prod env''' mks ks entries
    else (entries, ks) in
  let v = VTable { name = name;
                   keys = ks';
                   actions = actions;
                   default_action = default;
                   const_entries = final_entries; } in
  EvalEnv.insert_val name v env'''

and eval_header_decl (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_union_decl (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_struct_decl (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_error_decl (env : EvalEnv.t) (errs : P4String.t list) : EvalEnv.t =
  env

and eval_matchkind_decl (env : EvalEnv.t) (d : Declaration.t) : EvalEnv.t =
  env
  (* mems
  |> List.map ~f:snd
  |> List.map ~f:(fun a -> (a, VMatchKind))
  |> (fun a -> EvalEnv.insert_vals a env) *)

and eval_enum_decl (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_senum_decl (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) :EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_extern_obj (env : EvalEnv.t) (name : string)
    (methods : MethodPrototype.t list) (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_type_def (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_type_decl (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_ctrltyp_decl (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_prsrtyp_decl (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

and eval_pkgtyp_decl (env : EvalEnv.t) (name : string)
    (decl : Declaration.t) : EvalEnv.t =
  EvalEnv.insert_decl name decl env

(* -------------------------------------------------------------------------- *)
(* Table Declaration Evaluation *)
(* -------------------------------------------------------------------------- *)

and filter_lpm_prod (env : EvalEnv.t) (mks : string list) (ks : value list)
    (entries : (set * Table.action_ref) list)
    : (set * Table.action_ref) list * (value list) =
  let index = match List.findi mks ~f:(fun _ s -> String.equal s "lpm") with
    | None -> failwith "unreachable, should have lpm"
    | Some (i,_) -> i in
  let f = function
    | SProd l, a -> (List.nth_exn l index, a)
    | _ -> failwith "not lpm prod" in
  let entries =
    entries
    |> List.filter ~f:(fun (s,a) -> values_match_set ks s)
    |> List.map ~f:f in
  let ks' = [List.nth_exn ks index] in
  (sort_lpm entries, ks')

and check_lpm_count (mks : string list) : bool =
  let num_lpm =
    mks
    |> List.filter ~f:(fun s -> String.equal s "lpm")
    |> List.length in
  if num_lpm > 1
  then failwith "more than one lpm"
  else num_lpm = 1

and sort_lpm (entries : (set * Table.action_ref) list)
    : (set * Table.action_ref) list =
  let entries' = List.map entries ~f:(fun (x,y) -> lpm_set_of_set x, y) in
  let (entries'', uni) =
    match List.findi entries' ~f:(fun i (s,_) -> Poly.(s = SUniversal)) with
    | None -> (entries', None)
    | Some (i,_) ->
      let es = List.filteri entries' ~f:(fun ind _ -> ind < i) in
      let u = List.nth_exn entries' i in
      (es, Some u) in
  let compare (s1,_) (s2,_) =
    let (_,n1,_) = assert_lpm s1 in
    let (_,n2,_) = assert_lpm s2 in
    if Bigint.(n1 = n2) then 0
    else if Bigint.(n1 > n2) then -1
    else 1 in
  let sorted = List.sort entries'' ~compare:compare in
  match uni with
  | None -> sorted
  | Some u -> sorted @ [u]

and lpm_set_of_set (s : set) : set =
  match s with
  | SSingleton{w;v} ->
    let v' = bitwise_neg_of_bigint Bigint.zero w in
    SLpm{w=VBit{w;v};nbits=w;v=VBit{w;v=v'}}
  | SMask{v=v1;mask=v2} ->
    SLpm{w=v1;nbits=v2 |> bigint_of_val |> bits_of_lpmmask Bigint.zero false;v=v2}
  | SProd l -> List.map l ~f:lpm_set_of_set |> SProd
  | SUniversal
  | SLpm _ -> s
  | SRange _
  | SValueSet _ -> failwith "unreachable"

and bits_of_lpmmask (acc : Bigint.t) (b : bool) (v : Bigint.t) : Bigint.t =
  let two = Bigint.(one + one) in
  if Bigint.(v = zero)
  then acc
  else if Bigint.(v % two = zero)
  then if b then failwith "bad lpm mask"
        else bits_of_lpmmask acc b Bigint.(v / two)
  else bits_of_lpmmask Bigint.(acc + one) true Bigint.(v/two)

and default_of_defaults (p : Table.pre_property list) : Table.action_ref =
  let pre = match p with
    | [] ->
      Table.{ annotations = [];
              name = (Info.dummy,"NoAction");
              args = [] }
    | (Custom {value;_}) :: _ ->
      let (s,args) = assert_functioncall value in
      Table.{ annotations = [];
              name = (Info.dummy,s);
              args = args }
    | _ -> failwith "unreachable" in
  (Info.dummy,pre)

(*----------------------------------------------------------------------------*)
(* Functions to Calculate Initialization Values *)
(*----------------------------------------------------------------------------*)

and init_val_of_typ (env : EvalEnv.t) (ctrl : ctrl) (typ : Type.t) : value =
  match snd typ with
  | Bool                      -> VBool false
  | Error                     -> VError "NoError"
  | Integer                   -> VInteger Bigint.zero
  | IntType expr              -> init_val_of_int env ctrl expr
  | BitType expr              -> init_val_of_bit env ctrl expr
  | VarBit expr               -> init_val_of_varbit env ctrl expr
  | TopLevelType (_,n)        -> init_val_of_typname env ctrl n true
  | TypeName (_,n)            -> init_val_of_typname env ctrl n false
  | SpecializedType _         -> failwith "specialized init unimplemented"
  | HeaderStack{header; size} -> init_val_of_stack env ctrl header size
  | Tuple l                   -> init_val_of_tuple env ctrl typ l
  | String                    -> failwith "string init unimplemented"
  | Void                      -> VNull
  | DontCare                  -> VNull

and init_val_of_int (env : EvalEnv.t) (ctrl : ctrl)
    (expr : Expression.t) : value =
  match thrd3 (eval_expression' env ctrl SContinue expr) with
  | VInteger v
  | VBit{v;_}
  | VInt{v;_} -> VInt{w=v;v=Bigint.zero}
  | _ -> failwith "int width is not an int"

and init_val_of_bit (env : EvalEnv.t) (ctrl : ctrl)
    (expr : Expression.t) : value =
  match thrd3 (eval_expression' env ctrl SContinue expr) with
  | VInteger v
  | VBit{v;_}
  | VInt{v;_} -> VBit{w=v;v=Bigint.zero}
  | _ -> failwith "bit width is not an int"

and init_val_of_varbit (env : EvalEnv.t) (ctrl : ctrl)
    (expr: Expression.t) : value =
  match thrd3 (eval_expression' env ctrl SContinue expr) with
  | VInteger v
  | VBit{v;_}
  | VInt{v;_} -> VVarbit{max=v; w=Bigint.zero; v=Bigint.zero}
  | _ -> failwith "varbit width is not an int"

and init_val_of_typname (env : EvalEnv.t) (ctrl : ctrl) (tname : string) (is_toplevel: bool) : value =
  let find_decl = EvalEnv.(if is_toplevel then find_decl_toplevel else find_decl) in
  match snd (find_decl tname env) with
  | Struct {fields=fs;_}      -> init_val_of_struct env ctrl fs
  | Header {fields=fs;_}      -> init_val_of_header env ctrl fs
  | HeaderUnion {fields=fs;_} -> init_val_of_union env ctrl fs
  | _ -> failwith "decl init value unimplemented"

and init_val_of_stack env ctrl hdr size =
  let size' = size
              |> eval_expression' env ctrl SContinue
              |> thrd3
              |> bigint_of_val in
  let hdrs = size' |> Bigint.to_int_exn |> List.init ~f:string_of_int
             |> List.map ~f:(fun s -> init_val_of_typ env ctrl hdr) in
  VStack{headers=hdrs;size=size';next=Bigint.zero}

and init_val_of_tuple (env : EvalEnv.t) (ctrl : ctrl) (t : Type.t)
    (l : Type.t list) : value =
  VTuple (List.map l ~f:(init_val_of_typ env ctrl))

and init_val_of_struct env ctrl fields =
  VStruct {fields=List.map fields ~f:(init_binding_of_field env ctrl)}

and init_val_of_header (env : EvalEnv.t) (ctrl : ctrl)
    (fields : Declaration.field list) : value =
  VHeader {fields=List.map fields ~f:(init_binding_of_field env ctrl);is_valid=false}

and init_val_of_union (env : EvalEnv.t) (ctrl : ctrl)
    (fields : Declaration.field list) : value =
  let fields' = List.map fields ~f:(init_binding_of_field env ctrl) in
  let bs = List.map fields' ~f:(fun (a,b) -> (a,false)) in
  let v = fields' |> List.hd_exn |> snd in
  VUnion { valid_header=v; valid_fields=bs}

(*----------------------------------------------------------------------------*)
(* Statement Evaluation *)
(*----------------------------------------------------------------------------*)

and eval_statement (env :EvalEnv.t) (ctrl : ctrl) (sign : signal)
    (stm : Statement.t) : (EvalEnv.t * signal) =
  match snd stm with
  | MethodCall{func;type_args=ts;args} -> eval_method_call env ctrl sign func args ts
  | Assignment{lhs;rhs}                -> eval_assign env ctrl sign lhs rhs
  | DirectApplication{typ;args}        -> eval_app' env ctrl sign args typ
  | Conditional{cond;tru;fls}          -> eval_cond env ctrl sign cond tru fls
  | BlockStatement{block}              -> eval_block env ctrl sign block
  | Exit                               -> eval_exit env sign
  | EmptyStatement                     -> (env, sign)
  | Return{expr}                       -> eval_return env ctrl sign expr
  | Switch{expr;cases}                 -> eval_switch env ctrl sign expr cases
  | DeclarationStatement{decl}         -> eval_decl_stm env ctrl sign decl

and eval_method_call (env : EvalEnv.t) (ctrl : ctrl) (sign : signal)
    (func : Expression.t) (args : Argument.t list)
    (ts : Type.t list) : EvalEnv.t * signal =
  match sign with
  | SContinue -> let (e,s,_) = eval_funcall env ctrl func args ts in (e,s)
  | SReject _
  | SReturn _
  | SExit     -> (env, sign)

and eval_assign (env : EvalEnv.t) (ctrl : ctrl) (s : signal) (lhs : Expression.t)
    (rhs : Expression.t) : EvalEnv.t * signal =
  match s with
  | SContinue ->
    let (env', s', v) = eval_expression' env ctrl SContinue rhs in
    let lv = lvalue_of_expr lhs in
    begin match s' with
      | SReject _ -> (env', s')
      | SContinue -> eval_assign' env' ctrl lv v
      | _ -> failwith "unreachable" end
  | SReject _
  | SReturn _
  | SExit     -> (env, s)

and eval_app (env : EvalEnv.t) (ctrl : ctrl) (s : signal) (v : value)
  (args : Argument.t list) : EvalEnv.t * signal * value =
  match s with
  | SContinue ->
    begin match v with
      | VParser {pvs;pparams;plocals;states} ->
        let (env, s) = eval_parser env ctrl pparams args pvs plocals states in
        (env,s,VNull)
      | VControl {cvs;cparams;clocals;apply} ->
        let (env,s) = eval_control env ctrl cparams args cvs clocals apply in
        (env,s,VNull)
      | VTable {keys;const_entries;name;actions;default_action} ->
        eval_table env ctrl keys const_entries name actions default_action
      | _ -> failwith "apply not implemented on type" end
  | SReject _
  | SReturn _
  | SExit -> (env, s, VNull)

and eval_table (env : EvalEnv.t) (ctrl : ctrl) (key : value list)
    (entries : (set * Table.action_ref) list)
    (name : string) (actions : Table.action_ref list)
    (default : Table.action_ref) : EvalEnv.t * signal * value =
  let l = List.filter entries ~f:(fun (s,a) -> values_match_set key s) in
  let action = match l with
               | [] -> default
               | _ -> List.hd_exn l |> snd in
  let action_name = Table.((snd action).name |> snd) in
  let actionv = EvalEnv.find_val action_name env in
  let args = Table.((snd action).args) in
  match actionv with
  | VAction{params;body}  ->
    let (env',s,_) = eval_funcall' env ctrl params args body in
    let v = VStruct {fields=[
                          ("hit", VBool (not (List.is_empty l)));
                          ("action_run", VEnumField{typ_name=name;enum_name=action_name})
                         ]} in
    (env',s,v)
  | _ -> failwith "table expects an action"

  (* TODO: double check about scoping - actions before tables? *)

and eval_app' (env : EvalEnv.t) (ctrl : ctrl) (s : signal) (args : Argument.t list)
    (t : Type.t) : EvalEnv.t * signal =
  let (env', sign', v) = eval_nameless env ctrl t [] in
  let (env'', sign'',_) = eval_app env' ctrl sign' v args in
  (env'',sign'')

and eval_cond (env : EvalEnv.t) (ctrl : ctrl) (sign : signal) (cond : Expression.t)
    (tru : Statement.t) (fls : Statement.t option) : EvalEnv.t * signal =
  let eval_cond' env cond tru fls =
    let (env', s', v) = eval_expression' env ctrl SContinue cond in
    match s' with
    | SReject _ -> (env',s')
    | SContinue ->
      begin match v with
        | VBool true  -> eval_statement env' ctrl SContinue tru
        | VBool false ->
          begin match fls with
            | None -> (env, SContinue)
            | Some fls' -> eval_statement env' ctrl SContinue fls'  end
        | _ -> failwith "conditional guard must be a bool" end
    | _ -> failwith "unreachable" in
  match sign with
  | SContinue -> eval_cond' env cond tru fls
  | SReject _
  | SReturn _
  | SExit     -> (env, sign)

and eval_block (env : EvalEnv.t) (ctrl : ctrl) (sign :signal)
    (block : Block.t) : (EvalEnv.t * signal) =
  let block = snd block in
  let f (env,sign) stm =
    match sign with
    | SContinue -> eval_statement env ctrl sign stm
    | SReject _
    | SReturn _
    | SExit     -> (env, sign) in
  List.fold_left block.statements ~init:(env,sign) ~f:f

and eval_exit (env : EvalEnv.t) (sign : signal) : (EvalEnv.t * signal) =
    match sign with
    | SContinue -> (env, SExit)
    | SReturn v -> (env, SReturn v)
    | SExit -> (env, SExit)
    | SReject _ -> failwith "reject and exit in the same block"

and eval_return (env : EvalEnv.t) (ctrl : ctrl) (sign : signal)
    (expr : Expression.t option) : (EvalEnv.t * signal) =
  let (env',s',v) =
    match expr with
    | None   -> (env, SContinue, VNull)
    | Some e -> eval_expression' env ctrl SContinue e in
  match sign with
  | SReject _
  | SReturn _
  | SExit -> (env,sign)
  | SContinue -> begin match s' with
      | SContinue -> (env', SReturn v)
      | SReject _ -> (env', s')
      | SReturn _
      | SExit     -> failwith "unreachable" end

and eval_switch (env : EvalEnv.t) (ctrl : ctrl) (sign : signal) (expr : Expression.t)
    (cases : Statement.switch_case list) : EvalEnv.t * signal =
  let open Statement in
  let (env',s',v) = eval_expression' env ctrl SContinue expr in
  match sign with
  | SReject _
  | SReturn _
  | SExit -> (env, sign)
  | SContinue -> begin match s' with
    | SReject _ -> (env', s')
    | SContinue ->
      let s = assert_enum v |> snd in
      cases
      |> List.map ~f:snd
      |> List.group ~break:(fun x _ -> match x with Action _ -> true | _ -> false)
      |> List.filter ~f:(fun l -> List.exists l ~f:(label_matches_string s))
      |> List.hd_exn
      |> List.filter ~f:(function Action _ -> true | _ -> false)
      |> List.hd_exn
      |> (function Action{label;code} -> code | _ -> failwith "unreachable")
      |> eval_block env' ctrl SContinue
    | _ -> failwith "unreachable" end

and eval_decl_stm (env : EvalEnv.t) (ctrl : ctrl) (sign : signal)
    (decl : Declaration.t) : EvalEnv.t * signal =
  match sign with
  | SContinue -> (eval_decl env ctrl decl, SContinue)
  | SReject _
  | SReturn _
  | SExit     -> (env, sign)

(*----------------------------------------------------------------------------*)
(* Asssignment Evaluation *)
(*----------------------------------------------------------------------------*)

and eval_assign' (env : EvalEnv.t) (ctrl : ctrl) (lhs : lvalue)
    (rhs : value) : EvalEnv.t * signal =
  let lhs_typ = typ_of_lvalue env ctrl lhs in
  let rhs = 
    match rhs with
    | VTuple l -> implicit_cast_from_tuple env ctrl lhs rhs lhs_typ
    | VInteger n -> implicit_cast_from_rawint env ctrl rhs lhs_typ
    | _ -> rhs
  in
  match lhs with
  | LName n ->
     EvalEnv.insert_val n rhs env, SContinue
  | LTopName n ->
     EvalEnv.insert_val_toplevel n rhs env, SContinue
  | LMember{expr=lv;name=mname} ->
     let _, record = value_of_lvalue env ctrl lv in
     eval_assign' env ctrl lv (update_member record mname rhs)
  | LBitAccess{expr=lv;msb;lsb} ->
     let _, bits = value_of_lvalue env ctrl lv in
     let _, _, msb = eval_expression' env ctrl SContinue msb in
     let msb = bigint_of_val msb in
     let _, _, lsb = eval_expression' env ctrl SContinue lsb in
     let lsb = bigint_of_val lsb in
     eval_assign' env ctrl lv (update_slice bits msb lsb rhs)
  | LArrayAccess{expr=lv;idx} ->
     let _, arr = value_of_lvalue env ctrl lv in
     let _, _, idx = eval_expression' env ctrl SContinue idx in
     let idx = bigint_of_val idx in
     eval_assign' env ctrl lv (update_idx arr idx rhs)

and update_member (value : Value.value) (fname : string) (fvalue : value) : value =
  match value with
  | VStruct v ->
     VStruct {fields=update_field v.fields fname fvalue}
  | VHeader v ->
     VHeader{fields=update_field v.fields fname fvalue;
             is_valid=true}
  | VUnion v ->
     VUnion{valid_header=fvalue;valid_fields=set_only_valid v.valid_fields fname}
  | VStack{headers=hdrs;size=s;next=i} ->
     let idx = 
       match fname with
       | "next" -> i
       | "last" -> Bigint.(i - one)
       | _ -> failwith "BUG: VStack has no such member"
     in
     update_idx value idx fvalue
  | _ -> failwith "member access undefined"

and set_only_valid fields (fname: string) =
  List.map fields ~f:(fun (name, _) -> name, name = fname)

and update_field fields  field_name field_value =
  List.Assoc.remove fields ~equal:(=) field_name 

and update_nth l n x =
  let n = Bigint.to_int_exn n in
  let xs, ys = List.split_n l n in
  match ys with
  | y :: ys -> xs @ x :: ys
  | [] -> failwith "update_nth: out of bounds"

and update_idx arr idx value =
  match arr with
  | VStack{headers; size; next} ->
     if Bigint.(idx < zero || idx >= size)
     then failwith "out-of-bounds array access"
     else VStack { headers = update_nth headers idx value;
                   size = size;
                   next = next }
  | _ -> failwith "BUG: update_idx: expected a stack"

and update_slice bits_val msb lsb rhs_val =
  let open Bigint in
  let width =
    match bits_val with
    | VBit { w; _ } -> w
    | _ -> failwith "BUG:expected bit<> type"
  in
  let bits = bigint_of_val bits_val in
  let rhs_shifted = bigint_of_val rhs_val lsl to_int_exn lsb in
  let mask = lnot ((power_of_two (msb + one) - one)
                   lxor (power_of_two lsb - one))
  in
  let new_bits = (bits land mask) lxor rhs_shifted in
  VBit { w = width; v = new_bits }
     
(*----------------------------------------------------------------------------*)
(* Functions on L-Values*)
(*----------------------------------------------------------------------------*)

and lvalue_of_expr (expr : Expression.t) =
  match snd expr with
  | Name(_,n) -> LName n
  | TopLevel(_,n) -> LTopName n
  | ExpressionMember{expr=e; name=(_,n)} -> LMember{expr=lvalue_of_expr e;name=n}
  | BitStringAccess{bits;lo;hi} -> LBitAccess{expr=lvalue_of_expr bits;msb=lo;lsb=hi}
  | ArrayAccess{array;index} -> LArrayAccess{expr=lvalue_of_expr array;idx=index}
  | _ -> failwith "not an lvalue"

and value_of_lvalue (env : EvalEnv.t) (ctrl : ctrl)
    (lv : lvalue) : signal * value =
  match lv with
  | LName n                           -> (SContinue, EvalEnv.find_val n env)
  | LTopName n                        -> (SContinue, EvalEnv.find_val_toplevel n env)
  | LMember{expr=lv;name=n}           -> value_of_lmember env ctrl lv n
  | LBitAccess{expr=lv;msb=hi;lsb=lo} -> value_of_lbit env ctrl lv hi lo
  | LArrayAccess{expr=lv;idx}         -> value_of_larray env ctrl lv idx

and value_of_lmember (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (n : string) : signal * value =
  let (s,v) = value_of_lvalue env ctrl lv in
  let v' = match v with
    | VStruct{fields=l;_}
    | VHeader{fields=l;_}              -> List.Assoc.find_exn l n ~equal:String.equal
    | VUnion{valid_header=v;_}         -> v
    | VStack{headers=vs;size=s;next=i;_} -> value_of_stack_mem_lvalue n vs s i
    | _ -> failwith "no lvalue member" in
  match s with
  | SContinue -> (s,v')
  | SReject _ -> (s,VNull)
  | _ -> failwith "unreachable"

and value_of_lbit (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue) (hi : Expression.t)
    (lo : Expression.t) : signal * value =
  let (_,_,m) = eval_expression' env ctrl SContinue hi in
  let (_,_,l) = eval_expression' env ctrl SContinue lo in
  let (s,n) = value_of_lvalue env ctrl lv in
  let n' = bigint_of_val n in
  let m' = bigint_of_val m in
  let l' = bigint_of_val l in
  match s with
  | SContinue -> (s, VBit{w=Bigint.(m' - l' + one);v=bitstring_slice n' m' l'})
  | SReject _ -> (s, VNull)
  | _ -> failwith "unreachable"

and value_of_larray (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (idx : Expression.t) : signal * value =
  let (s,v) =  value_of_lvalue env ctrl lv in
  match s with
  | SContinue ->
    begin match v with
      | VStack{headers=vs;size=s;next=i} ->
        let idx' = eval_expression' env ctrl SContinue idx
                   |> thrd3
                   |> bigint_of_val in
        begin try (SContinue, List.nth_exn vs Bigint.(to_int_exn (idx' % s)))
          with Invalid_argument _ -> (SReject "StackOutOfBounds", VNull) end
      | _ -> failwith "array access is not a header stack" end
  | SReject _ -> (s,VNull)
  | _ -> failwith "unreachable"

and value_of_stack_mem_lvalue (name : string) (vs : value list)
    (size : Bigint.t) (next : Bigint.t) : value =
  match name with
  | "next" -> List.nth_exn vs Bigint.(to_int_exn (next % size))
  | _ -> failwith "not an lvalue"

and typ_of_lvalue (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue) : Type.t =
  match lv with
  | LName s                            -> EvalEnv.find_typ s env
  | LTopName s                         -> EvalEnv.find_typ_toplevel s env
  | LMember{expr=lv';name=s}           -> typ_of_lmember env ctrl lv' s
  | LBitAccess{expr=lv';msb=e1;lsb=e2} -> typ_of_lbit env ctrl lv' e1 e2
  | LArrayAccess{expr=lv';idx=e}       -> typ_of_larray env ctrl lv' e

and typ_of_lmember (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (s : string) : Type.t =
  let t = typ_of_lvalue env ctrl lv in
  match snd t with
  | HeaderStack{header;_} -> typ_of_stack_lmem env s header
  | TypeName(_,n) ->
    begin match snd (decl_of_typ env t) with
      | Header{fields=fs;_}      -> typ_of_struct_lmem env s fs
      | HeaderUnion{fields=fs;_} -> typ_of_struct_lmem env s fs
      | Struct{fields=fs;_}      -> typ_of_struct_lmem env s fs
      | _ -> failwith "lvalue type name member access not defined" end
  | _ -> failwith "type of lvalue member unimplemented"

and typ_of_struct_lmem (env : EvalEnv.t) (s : string)
    (fields : Declaration.field list) : Type.t =
  let fs = List.map fields ~f:(fun a -> (snd (snd a).name, a)) in
  let f = List.Assoc.find_exn fs ~equal:String.equal s in
  (snd f).typ

and typ_of_stack_lmem (env : EvalEnv.t) (s : string) (t : Type.t) : Type.t =
  let () =
    match s with
    | "next" -> ()
    | _ -> failwith "stack member not a lvalue" in
  t

and typ_of_lbit (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue) (e1 : Expression.t)
    (e2 : Expression.t) : Type.t =
  let (_,_,v1) = eval_expression' env ctrl SContinue e1 in
  let (_,_,v2) = eval_expression' env ctrl SContinue e2 in
  let n1 = bigint_of_val v1 in
  let n2 = bigint_of_val v2 in
  let n0 = Bigint.(n1 - n2 + one) in
  (Info.dummy, Type.BitType(Info.dummy, Expression.Int(Info.dummy,{value=n0;width_signed=None})))

and typ_of_larray (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue) (e : Expression.t) : Type.t =
  let t = typ_of_lvalue env ctrl lv in
  match snd t with
  | HeaderStack{header;_} -> header
  | _ -> failwith "array access on non-header stack"

(*----------------------------------------------------------------------------*)
(* Expression Evaluation *)
(*----------------------------------------------------------------------------*)

and eval_expression' (env : EvalEnv.t) (ctrl : ctrl) (s : signal)
    (exp : Expression.t) : EvalEnv.t * signal * value =
  match s with
  | SContinue ->
    begin match snd exp with
      | True                                 -> (env, s, VBool true)
      | False                                -> (env, s, VBool false)
      | Int(_,n)                             -> (env, s, eval_p4int n)
      | String (_,value)                     -> (env, s, VString value)
      | Name (_,name)                        -> eval_name env s name exp
      | TopLevel (_,name)                    -> (env, s, EvalEnv.find_val_toplevel name env)
      | ArrayAccess{array=a; index=i}        -> eval_array_access env ctrl a i
      | BitStringAccess({bits;lo;hi})        -> eval_bitstring_access env ctrl bits lo hi
      | List{values}                         -> eval_list env ctrl values
      | Record{entries}                      -> eval_struct env ctrl entries
      | UnaryOp{op;arg}                      -> eval_unary env ctrl op arg
      | BinaryOp{op; args=(l,r)}             -> eval_binop env ctrl op l r
      | Cast{typ;expr}                       -> eval_cast env ctrl typ expr
      | TypeMember{typ;name}                 -> eval_typ_mem env ctrl typ (snd name)
      | ErrorMember t                        -> (env, s, VError (snd t))
      | ExpressionMember{expr;name}          -> eval_expr_mem env ctrl expr name
      | Ternary{cond;tru;fls}                -> eval_ternary env ctrl cond tru fls
      | FunctionCall{func;type_args=ts;args} -> eval_funcall env ctrl func args ts
      | NamelessInstantiation{typ;args}      -> eval_nameless env ctrl typ args
      | Mask{expr;mask}                      -> eval_mask env ctrl expr mask
      | Range{lo;hi}                         -> eval_range env ctrl lo hi end
  | SReject _ -> (env, s, VNull)
  | SReturn _ -> failwith "expression should not return"
  | SExit -> failwith "expresion should not exit"

and eval_name (env : EvalEnv.t) (s : signal) (name : string)
    (exp : Expression.t) : EvalEnv.t * signal * value =
  if String.equal name "verify" then (env, s, VBuiltinFun {name;caller=lvalue_of_expr exp})
  else (env, s, EvalEnv.find_val name env)

and eval_p4int (n : P4Int.pre_t) : value =
  match n.width_signed with
  | None          -> VInteger n.value
  | Some(w,true)  -> VInt {w=Bigint.of_int w;v=n.value}
  | Some(w,false) -> VBit {w=Bigint.of_int w;v=n.value}

and eval_array_access (env : EvalEnv.t) (ctrl : ctrl) (a : Expression.t)
    (i : Expression.t) : EvalEnv.t * signal * value =
  let (env', s, a') = eval_expression' env ctrl SContinue a in
  let (env'', s', i') = eval_expression' env' ctrl SContinue i in
  let idx = bigint_of_val i' in
  let (hdrs,size,next) = assert_stack a' in
  let idx' = Bigint.(to_int_exn (idx % size)) in
  match (s,s') with
  | SContinue, SContinue -> (env'', SContinue, List.nth_exn hdrs idx')
  | SReject _,_ -> (env',s, VNull)
  | _,SReject _ -> (env'',s',VNull)
  | _ -> failwith "unreachable"

and eval_bitstring_access (env : EvalEnv.t) (ctrl : ctrl) (b : Expression.t)
    (m : Expression.t) (l : Expression.t) : EvalEnv.t * signal * value =
  let (env', s, m) = eval_expression' env ctrl SContinue m in
  let (env'', s', l) = eval_expression' env' ctrl SContinue l in
  let (env''', s'', b) = eval_expression' env'' ctrl SContinue b in
  let m' = bigint_of_val m in
  let l' = bigint_of_val l in
  let b' = bigint_of_val b in
  let w = Bigint.(m'-l' + one) in
  let n = bitstring_slice b' m' l' in
  match (s,s',s'') with
  | SContinue, SContinue, SContinue -> (env''', SContinue, VBit{w;v=n})
  | SReject _,_,_ -> (env',s,VNull)
  | _,SReject _,_ -> (env'', s',VNull)
  | _,_,SReject _ -> (env''', s'', VNull)
  | _ -> failwith "unreachable"

and eval_struct (env : EvalEnv.t) (ctrl : ctrl) 
  (entries : KeyValue.t list) : EvalEnv.t * signal * value = 
  failwith "unimplemented"

and eval_list (env : EvalEnv.t) (ctrl : ctrl)
    (values : Expression.t list) : EvalEnv.t * signal * value =
  let f (a,b) c =
    let (x,y,z) = eval_expression' a ctrl b c in
    ((x,y),z) in
  values
  |> List.fold_map ~f:f ~init:(env,SContinue)
  |> (fun ((e,s),l) -> (e, s, VTuple l))

and eval_unary (env : EvalEnv.t) (ctrl : ctrl) (op : Op.uni)
    (e : Expression.t) : EvalEnv.t * signal * value =
  let (env', s, v) = eval_expression' env ctrl SContinue e in
  match s with
  | SContinue ->
    let (env,v) = match snd op with
      | Not    -> eval_not env' v
      | BitNot -> eval_bitnot env' v
      | UMinus -> eval_uminus env' v in
    (env,s,v)
  | SReject _ -> (env',s,VNull)
  | _ -> failwith "unreachable"

and eval_binop (env : EvalEnv.t) (ctrl : ctrl) (op : Op.bin) (l : Expression.t)
    (r : Expression.t) : EvalEnv.t * signal * value =
  let (env',s,l) = eval_expression' env ctrl SContinue l in
  let (env'',s',r) = eval_expression' env' ctrl SContinue r in
  let v = match snd op with
    | Plus     -> eval_bplus l r
    | PlusSat  -> eval_bplus_sat l r
    | Minus    -> eval_bminus l r
    | MinusSat -> eval_bminus_sat l r
    | Mul      -> eval_bmult l r
    | Div      -> eval_bdiv l r
    | Mod      -> eval_bmod l r
    | Shl      -> eval_bshl l r
    | Shr      -> eval_bshr l r
    | Le       -> eval_ble l r
    | Ge       -> eval_bge l r
    | Lt       -> eval_blt l r
    | Gt       -> eval_bgt l r
    | Eq       -> eval_beq l r
    | NotEq    -> eval_bne l r
    | BitAnd   -> eval_bitwise_and l r
    | BitXor   -> eval_bitwise_xor l r
    | BitOr    -> eval_bitwise_or l r
    | PlusPlus -> eval_concat l r
    | And      -> eval_band l r
    | Or       -> eval_bor l r in
  match (s,s') with
  | SContinue, SContinue -> (env'', SContinue, v)
  | SReject _,_ -> (env',s,VNull)
  | _,SReject _ -> (env'',s',VNull)
  | _ -> failwith "unreachable"

and eval_cast (env : EvalEnv.t) (ctrl : ctrl) (typ : Type.t)
    (expr : Expression.t) : EvalEnv.t * signal * value =
  let (env', s, v) = eval_expression' env ctrl SContinue expr in
  let (env'',s',v') =
    match snd typ with
    | Bool -> (env', SContinue, bool_of_val v)
    | BitType e -> bit_of_val env' ctrl e v
    | IntType e -> int_of_val env' ctrl e v
    | TypeName (_,n) -> (env', s, v)
    | _ -> failwith "type cast unimplemented" in
  match (s,s') with
  | SContinue,SContinue -> (env'',s,v')
  | SReject _,_ -> (env',s,VNull)
  | _,SReject _ -> (env'',s',VNull)
  | _ -> failwith "unreachable"

and eval_typ_mem (env : EvalEnv.t) (ctrl : ctrl) (typ : Type.t)
    (name : string) : EvalEnv.t * signal * value =
  match snd (decl_of_typ env typ) with
  | Declaration.Enum {members=ms;name=(_,n);_} ->
    let mems = List.map ms ~f:snd in
    if List.mem mems name ~equal:String.equal
    then (env, SContinue, VEnumField{typ_name=n;enum_name=name})
    else raise (UnboundName name)
  | Declaration.SerializableEnum {members=ms;name=(_,n);typ;_ } ->
    let ms' = List.map ms ~f:(fun (a,b) -> (snd a, b)) in
    let expr = List.Assoc.find_exn ms' ~equal:String.equal name in
    let (env',s,v) = eval_expression' env ctrl SContinue expr in
    let v' = implicit_cast_from_rawint env' ctrl v typ in
    begin match s with
      | SContinue -> (env',s,VSenumField{typ_name=n;enum_name=name;v=v'})
      | SReject _ -> (env',s,VNull)
      | _ -> failwith "unreachable" end
  | _ -> failwith "typ mem undefined"

and eval_expr_mem (env : EvalEnv.t) (ctrl : ctrl) (expr : Expression.t)
    (name : P4String.t) : EvalEnv.t * signal * value =
  let (env', s, v) = eval_expression' env ctrl SContinue expr in
  match s with
  | SContinue ->
    begin match v with
      | VNull
      | VBool _
      | VInteger _
      | VBit _
      | VInt _
      | VVarbit _
      | VTuple _
      | VSet _
      | VString _
      | VError _
      | VFun _
      | VBuiltinFun _
      | VAction _
      | VEnumField _
      | VSenumField _
      | VPackage _                           -> failwith "expr member does not exist"
      | VStruct{fields=fs;_}                 -> eval_struct_mem env' (snd name) fs
      | VHeader{fields=fs;is_valid=vbit;_}   -> eval_header_mem env' (snd name) expr fs vbit
      | VUnion{valid_header=v;_}             -> (env', SContinue, v)
      | VStack{headers=hdrs;size=s;next=n;_} -> eval_stack_mem env' (snd name) expr hdrs s n
      | VRuntime v                           -> eval_runtime_mem env' (snd name) expr v
      | VParser _
      | VControl _                           -> (env', s, VBuiltinFun{name=snd name;caller=lvalue_of_expr expr})
      | VTable _                             -> (env', s, VBuiltinFun{name=snd name;caller=lvalue_of_expr expr}) end
  | SReject _ -> (env',s,VNull)
  | _ -> failwith "unreachable"

and eval_ternary (env : EvalEnv.t) (ctrl : ctrl) (c : Expression.t)
    (te : Expression.t) (fe : Expression.t) : EvalEnv.t * signal * value =
  let (env', s, c') = eval_expression' env ctrl SContinue c in
  match c' with
  | VBool(true)  -> (eval_expression' env' ctrl s te)
  | VBool(false) -> (eval_expression' env' ctrl s fe)
  | _ -> failwith "ternary guard must be a bool"

and eval_funcall (env : EvalEnv.t) (ctrl : ctrl) (func : Expression.t)
    (args : Argument.t list) (ts : Type.t list) : EvalEnv.t * signal * value =
  let (env', s, cl) = eval_expression' env ctrl SContinue func in
  match s with
  | SContinue ->
    begin match cl with
      | VAction{params; body}
      | VFun{params; body}            -> eval_funcall' env' ctrl params args body
      | VBuiltinFun{name=n;caller=lv} -> eval_builtin env ctrl n lv args ts
      | _ -> failwith "unreachable" end
  | SReject _ -> (env',s,VNull)
  | _ -> failwith "unreachable"

and eval_nameless (env : EvalEnv.t) (ctrl : ctrl) (typ : Type.t)
    (args : Argument.t list) : EvalEnv.t * signal * value =
  let (info ,decl) = decl_of_typ env typ in
  let (env',s,v) = match decl with
    | Control typ_decl ->
      let (env',s) = copyin env ctrl typ_decl.constructor_params args in
      let state = env' |> EvalEnv.get_val_firstlevel |> List.rev in
      let v' = VControl { cvs = state;
                          cparams = typ_decl.params;
                          clocals = typ_decl.locals;
                          apply = typ_decl.apply; } in
      (EvalEnv.pop_scope env',s,v')
    | Parser typ_decl ->
      let (env',s) = copyin env ctrl typ_decl.constructor_params args in
      let state = env' |> EvalEnv.get_val_firstlevel |> List.rev in
      let v' = VParser { pvs = state;
                         pparams = typ_decl.params;
                         plocals = typ_decl.locals;
                         states = typ_decl.states; } in
      (EvalEnv.pop_scope env',s,v')
    | PackageType pack_decl ->
      let (env',s) = copyin env ctrl pack_decl.params args in
      let state = env' |> EvalEnv.get_val_firstlevel |> List.rev in
      (EvalEnv.pop_scope env', s, VPackage{decl=(info, decl);args=state})
    | _ -> failwith "instantiation unimplemented" in
  match s with
  | SContinue -> (env',s,v)
  | SReject _ -> (env,s,VNull)
  | _ -> failwith "nameless should not return or exit"

and eval_mask (env : EvalEnv.t) (ctrl : ctrl) (e : Expression.t)
    (m : Expression.t) : EvalEnv.t * signal * value =
  let (env', s, v1)  = eval_expression' env ctrl SContinue e in
  let (env'', s', v2) = eval_expression' env' ctrl SContinue m in
  match (s,s') with
  | SContinue, SContinue -> (env'', s, VSet(SMask{v=v1;mask=v2}))
  | SReject _,_ -> (env',s,VNull)
  | _,SReject _ -> (env'',s',VNull)
  | _ -> failwith "unreachable"

and eval_range (env : EvalEnv.t) (ctrl : ctrl) (lo : Expression.t)
    (hi : Expression.t) : EvalEnv.t * signal * value =
  let (env', s, v1)  = eval_expression' env ctrl SContinue lo in
  let (env'', s', v2) = eval_expression' env' ctrl SContinue hi in
  match (s,s') with
  | SContinue, SContinue -> (env'', s, VSet(SRange{lo=v1;hi=v2}))
  | SReject _,_ -> (env',s,VNull)
  | _,SReject _ -> (env'',s',VNull)
  | _ -> failwith "unreachable"

(*----------------------------------------------------------------------------*)
(* Unary Operator Evaluation *)
(*----------------------------------------------------------------------------*)

and eval_not (env : EvalEnv.t) (v : value) : EvalEnv.t * value =
  match v with
  | VBool b -> (env, VBool (not b))
  | _ -> failwith "not operator can only be applied to bools"

and eval_bitnot (env : EvalEnv.t) (v : value) : EvalEnv.t * value =
  match v with
  | VBit{w;v=n} -> (env, VBit{w;v=bitwise_neg_of_bigint n w})
  | VInt{w;v=n} -> (env, VBit{w;v=((of_twos_complement n w
                                    |> bitwise_neg_of_bigint) w
                                    |> to_twos_complement) w})
  | _ -> failwith "bitwise complement on non-fixed width unsigned bitstring"

and bitwise_neg_of_bigint (n : Bigint.t) (w : Bigint.t) : Bigint.t =
  if Bigint.(w > zero) then
    let w' = power_of_two Bigint.(w-one) in
    let g = bitstring_slice n Bigint.(w - one) Bigint.(w - one) in
    if Bigint.(g = zero)
    then bitwise_neg_of_bigint Bigint.(n + w') Bigint.(w-one)
    else bitwise_neg_of_bigint Bigint.(n - w') Bigint.(w-one)
  else n

and eval_uminus (env : EvalEnv.t) (v : value) : EvalEnv.t * value =
  match v with
  | VBit{w;v=n}  -> Bigint.(env, VBit{w;v=(power_of_two w) - n})
  | VInt{w;v=n}  -> Bigint.(env, VInt{w;v=to_twos_complement (-n) w})
  | VInteger n -> (env, VInteger (Bigint.neg n))
  | _ -> failwith "unary minus on non-int type"

(*----------------------------------------------------------------------------*)
(* Binary Operator Evaluation *)
(*----------------------------------------------------------------------------*)

and eval_bplus (l : value) (r : value) : value =
  match (l,r) with
  | VBit{w;v=v1}, VBit{v=v2;_} -> VBit{w;v=of_twos_complement Bigint.(v1 + v2) w}
  | VInt{w;v=v1}, VInt{v=v2;_} -> VInt{w;v=to_twos_complement Bigint.(v1 + v2) w}
  | VBit{w;v=v1}, VInteger n   -> eval_bplus l (bit_of_rawint n w)
  | VInteger n,   VBit{w;v=v1} -> eval_bplus (bit_of_rawint n w) r
  | VInt{w;v=v1}, VInteger n   -> eval_bplus l (int_of_rawint n w)
  | VInteger n,   VInt{w;v=v1} -> eval_bplus (int_of_rawint n w) r
  | VInteger n1,  VInteger n2  -> VInteger Bigint.(n1 + n2)
  | _ -> failwith "binary plus operation only defined on ints"

and eval_bplus_sat (l : value) (r : value) : value =
  match (l,r) with
  | VBit{w;v=v1}, VBit{v=v2;_} -> unsigned_op_sat v1 v2 w Bigint.(+)
  | VInt{w;v=v1}, VInt{v=v2;_} -> signed_op_sat v1 v2 w Bigint.(+)
  | VBit{w;v=v1}, VInteger n   -> eval_bplus_sat l (bit_of_rawint n w)
  | VInteger n,   VBit{w;_}    -> eval_bplus_sat (bit_of_rawint n w) r
  | VInt{w;_},    VInteger n   -> eval_bplus_sat l (int_of_rawint n w)
  | VInteger n,   VInt{w;_}    -> eval_bplus_sat (int_of_rawint n w) r
  | _ -> failwith "binary sat plus operation only definted on fixed-width ints"

and eval_bminus (l : value) (r : value) : value =
  match (l,r) with
  | VBit{w;v=v1}, VBit{v=v2;_} -> VBit{w;v=of_twos_complement Bigint.(v1 - v2) w}
  | VInt{w;v=v1}, VInt{v=v2;_} -> VInt{w;v=to_twos_complement Bigint.(v1 - v2) w}
  | VBit{w;v=v1}, VInteger n   -> eval_bminus l (bit_of_rawint n w)
  | VInteger n,   VBit{w;v=v1} -> eval_bminus (bit_of_rawint n w) r
  | VInt{w;v=v1}, VInteger n   -> eval_bminus l (int_of_rawint n w)
  | VInteger n,   VInt{w;v=v1} -> eval_bminus (int_of_rawint n w) r
  | VInteger n1,  VInteger n2  -> VInteger Bigint.(n1 - n2)
  | _ -> failwith "binary plus operation only defined on ints"

and eval_bminus_sat (l : value) (r : value) : value =
  match (l,r) with
  | VBit{w;v=v1}, VBit{v=v2;_} -> unsigned_op_sat v1 v2 w Bigint.(-)
  | VInt{w;v=v1}, VInt{v=v2;_} -> signed_op_sat v1 v2 w Bigint.(-)
  | VBit{w;v=v1}, VInteger n   -> eval_bminus_sat l (bit_of_rawint n w)
  | VInteger n, VBit{w;_}      -> eval_bminus_sat (bit_of_rawint n w) r
  | VInt{w;_}, VInteger n      -> eval_bminus_sat l (int_of_rawint n w)
  | VInteger n, VInt{w;_}      -> eval_bminus_sat (int_of_rawint n w) r
  | _ -> failwith "binary sat plus operation only definted on fixed-width ints"

and eval_bmult (l : value) (r : value) : value =
  match (l,r) with
  | VBit{w;v=v1}, VBit{v=v2;_} -> VBit{w;v=of_twos_complement Bigint.(v1 * v2) w}
  | VInt{w;v=v1}, VInt{v=v2;_} -> VInt{w;v=to_twos_complement Bigint.(v1 * v2) w}
  | VBit{w;v=v1}, VInteger n   -> eval_bmult l (bit_of_rawint n w)
  | VInteger n,   VBit{w;v=v1} -> eval_bmult (bit_of_rawint n w) r
  | VInt{w;v=v1}, VInteger n   -> eval_bmult l (int_of_rawint n w)
  | VInteger n,   VInt{w;v=v1} -> eval_bmult (int_of_rawint n w) r
  | VInteger n1,  VInteger n2  -> VInteger Bigint.(n1 * n2)
  | _ -> failwith "binary mult operation only defined on ints"

and eval_bdiv (l : value) (r : value) : value =
  match (l,r) with
  | VInteger n1, VInteger n2 -> VInteger Bigint.(n1 / n2)
  | _ -> failwith "division only defined on raw ints"

and eval_bmod (l : value) (r : value) : value =
  match (l,r) with
  | VInteger n1, VInteger n2 -> VInteger Bigint.(n1 % n2)
  | _ -> failwith "mod only defined on raw ints"

and eval_bshl (l : value) (r : value) : value =
  match (l,r) with
  | VBit{w;v=v1}, VBit{v=v2;_}
  | VBit{w;v=v1}, VInteger v2 -> VBit{w;v=of_twos_complement (shift_bigint_left v1 v2) w}
  | VInt{w;v=v1}, VBit{v=v2;_}
  | VInt{w;v=v1}, VInteger v2 -> VInt{w;v=to_twos_complement (shift_bigint_left v1 v2) w}
  | VInteger v1, VInteger v2  -> VInteger(shift_bigint_left v1 v2)
  | _ -> failwith "shift left operator not defined for these types"

and eval_bshr (l : value) (r : value) : value =
  match (l,r) with
  | VBit{w;v=v1}, VBit{v=v2;_}
  | VBit{w;v=v1}, VInteger v2 -> VBit{w;v=of_twos_complement (shift_bigint_right v1 v2) w}
  | VInt{w;v=v1}, VBit{v=v2;_}
  | VInt{w;v=v1}, VInteger v2 -> VInt{w;v=to_twos_complement (shift_bigint_right v1 v2) w}
  | VInteger v1,  VInteger v2 -> VInteger(shift_bigint_right v1 v2)
  | _ -> failwith "shift right operator not defined for these types"

and eval_ble (l : value) (r : value) : value =
  match (l,r) with
  | VBit{v=v1;_}, VBit{v=v2;_}
  | VInteger v1, VInteger v2
  | VInt{v=v1;_}, VInt{v=v2;_} -> VBool Bigint.(v1 <= v2)
  | VInteger v1, VBit{w;v=v2}  -> eval_ble (bit_of_rawint v1 w) r
  | VBit{w;v=v1}, VInteger v2  -> eval_ble l (bit_of_rawint v2 w)
  | VInteger v1, VInt{w;v=v2}  -> eval_ble (int_of_rawint v1 w) r
  | VInt{w;v=v1}, VInteger v2  -> eval_ble l (int_of_rawint v2 w)
  | _ -> failwith "leq operator only defined on int types"

and eval_bge (l : value) (r : value) : value =
  match (l,r) with
  | VBit{v=v1;_}, VBit{v=v2;_}
  | VInteger v1,  VInteger v2
  | VInt{v=v1;_}, VInt{v=v2;_} -> VBool Bigint.(v1 >= v2)
  | VInteger v1,  VBit{w;v=v2} -> eval_bge (bit_of_rawint v1 w) r
  | VBit{w;v=v1}, VInteger v2  -> eval_bge l (bit_of_rawint v2 w)
  | VInteger v1,  VInt{w;v=v2} -> eval_bge (int_of_rawint v1 w) r
  | VInt{w;v=v1}, VInteger v2  -> eval_bge l (int_of_rawint v2 w)
  | _ -> failwith "geq operator only defined on int types"

and eval_blt (l : value) (r : value) : value =
  match (l,r) with
  | VBit{v=v1;_}, VBit{v=v2;_}
  | VInteger v1, VInteger v2
  | VInt{v=v1;_}, VInt{v=v2;_} -> VBool Bigint.(v1 < v2)
  | VInteger v1, VBit{w;v=v2}  -> eval_blt (bit_of_rawint v1 w) r
  | VBit{w;v=v1}, VInteger v2  -> eval_blt l (bit_of_rawint v2 w)
  | VInteger v1, VInt{w;v=v2}  -> eval_blt (int_of_rawint v1 w) r
  | VInt{w;v=v1}, VInteger v2  -> eval_blt l (int_of_rawint v2 w)
  | _ -> failwith "lt operator only defined on int types"

and eval_bgt (l : value) (r : value) : value =
  match (l,r) with
  | VBit{v=v1;_}, VBit{v=v2;_}
  | VInteger v1,  VInteger v2
  | VInt{v=v1;_}, VInt{v=v2;_} -> VBool Bigint.(v1 > v2)
  | VInteger v1,  VBit{w;v=v2} -> eval_bgt (bit_of_rawint v1 w) r
  | VBit{w;v=v1}, VInteger v2  -> eval_bgt l (bit_of_rawint v2 w)
  | VInteger v1,  VInt{w;v=v2} -> eval_bgt (int_of_rawint v1 w) r
  | VInt{w;v=v1}, VInteger v2  -> eval_bgt l (int_of_rawint v2 w)
  | _ -> failwith "gt operator only defined on int types"

and eval_beq (l : value) (r : value) : value =
  match (l,r) with
  | VError s1, VError s2
  | VEnumField{enum_name=s1;_},
    VEnumField{enum_name=s2;_}                -> VBool Poly.(s1 = s2)
  | VSenumField{v=v1;_},
    VSenumField{v=v2;_}                       -> eval_beq v1 v2
  | VBool b1, VBool b2                        -> VBool Poly.(b1 = b2)
  | VBit{v=n1;_}, VBit{v=n2;_}
  | VInteger n1, VInteger n2
  | VInt{v=n1;_}, VInt{v=n2;_}                -> VBool Bigint.(n1 = n2)
  | VVarbit{w=w1;v=n1;_},
    VVarbit{w=w2;v=n2;_}                      -> VBool(Bigint.(n1 = n2 && w1 = w2))
  | VBit{w;v=n1}, VInteger n2                 -> eval_beq l (bit_of_rawint n2 w)
  | VInteger n1, VBit{w;v=n2}                 -> eval_beq (bit_of_rawint n1 w) r
  | VInt{w;v=n1}, VInteger n2                 -> eval_beq l (int_of_rawint n2 w)
  | VInteger n1, VInt{w;v=n2}                 -> eval_beq (int_of_rawint n1 w) r
  | VStruct{fields=l1;_},
    VStruct{fields=l2;_}                      -> structs_equal l1 l2
  | VHeader{fields=l1;is_valid=b1;_},
    VHeader{fields=l2;is_valid=b2;_}          -> headers_equal l1 l2 b1 b2
  | VStack{headers=l1;_},
    VStack{headers=l2;_}                      -> stacks_equal l1 l2
  | VUnion{valid_header=v1;valid_fields=l1;_},
    VUnion{valid_header=v2;valid_fields=l2;_} -> unions_equal v1 v2 l1 l2
  | VTuple _, _ -> failwith "got tuple"
  | _ -> failwith "equality comparison undefined for given types"

and eval_bne (l : value) (r : value) : value =
  eval_beq l r |> assert_bool |> not |> VBool

and eval_bitwise_and (l : value) (r : value) : value =
  match (l,r) with
  | VBit{w;v=v1}, VBit{v=v2;_} -> VBit{w;v=Bigint.bit_and v1 v2}
  | VBit{w;v=v1}, VInteger n   -> eval_bitwise_and l (bit_of_rawint n w)
  | VInteger n, VBit{w;v=v2}   -> eval_bitwise_and (bit_of_rawint n w) r
  | VInt{w;v=v1}, VInt{v=v2;_} -> bitwise_op_of_signeds Bigint.bit_and v1 v2 w
  | VInt{w;v=v1}, VInteger n   -> eval_bitwise_and l (bit_of_rawint n w)
  | VInteger n, VInt{w;v=v2}   -> eval_bitwise_and (bit_of_rawint n w) r
  | _ -> failwith "bitwise and only defined on fixed width ints"

and eval_bitwise_xor (l : value) (r : value) : value =
  match (l,r) with
  | VBit{w;v=v1}, VBit{v=v2;_} -> VBit{w;v=Bigint.bit_xor v1 v2}
  | VBit{w;v=v1}, VInteger n   -> eval_bitwise_xor l (bit_of_rawint n w)
  | VInteger n,   VBit{w;v=v2} -> eval_bitwise_xor (bit_of_rawint n w) r
  | VInt{w;v=v1}, VInt{v=v2;_} -> bitwise_op_of_signeds Bigint.bit_xor v1 v2 w
  | VInt{w;v=v1}, VInteger n   -> eval_bitwise_xor l (bit_of_rawint n w)
  | VInteger n,   VInt{w;v=v2} -> eval_bitwise_xor (bit_of_rawint n w) r
  | _ -> failwith "bitwise xor only defined on fixed width ints"

and eval_bitwise_or (l : value) (r : value) : value =
  match (l,r) with
  | VBit{w;v=v1}, VBit{v=v2;_} -> VBit{w;v=Bigint.bit_or v1 v2}
  | VBit{w;v=v1}, VInteger n   -> eval_bitwise_or l (bit_of_rawint n w)
  | VInteger n, VBit{w;v=v2}   -> eval_bitwise_or (bit_of_rawint n w) r
  | VInt{w;v=v1}, VInt{v=v2;_} -> bitwise_op_of_signeds Bigint.bit_or v1 v2 w
  | VInt{w;v=v1}, VInteger n   -> eval_bitwise_or l (bit_of_rawint n w)
  | VInteger n, VInt{w;v=v2}   -> eval_bitwise_or (bit_of_rawint n w) r
  | _ -> failwith "bitwise or only defined on fixed width ints"

and eval_concat (l : value) (r : value) : value =
  match (l,r) with
  | VBit{w=w1;v=v1}, VBit{w=w2;v=v2} ->
    VBit{w=Bigint.(w1+w2);v=Bigint.(shift_bigint_left v1 w2 + v2)}
  | VBit{w;v},  VInteger n -> eval_concat l (bit_of_rawint n w)
  | VInteger n, VBit{w;v}  -> eval_concat (bit_of_rawint n w) r
  | _ -> failwith "concat operator only defined on unsigned ints"

and eval_band (l : value) (r : value) : value =
  match (l,r) with
  | VBool b1, VBool b2 -> VBool(b1 && b2)
  | _ -> failwith "and operator only defined on bools"

and eval_bor (l : value) (r : value) : value =
  match (l,r) with
  | VBool b1, VBool b2 -> VBool(b1 || b2)
  | _ -> failwith "or operator only defined on bools"

and bigint_max (n : Bigint.t) (m : Bigint.t) : Bigint.t =
  if Bigint.(n>m) then n else m

and bigint_min (n : Bigint.t) (m : Bigint.t) : Bigint.t =
  if Bigint.(n<m) then n else m

and unsigned_op_sat (l : Bigint.t) (r : Bigint.t) (w : Bigint.t)
    (op : Bigint.t -> Bigint.t -> Bigint.t) : value =
  let x = power_of_two w in
  let n = op l r in
  let n' =
    if Bigint.(n > zero)
    then bigint_min n Bigint.(x - one)
    else bigint_max n Bigint.zero in
  VBit{w;v=n'}

and signed_op_sat (l : Bigint.t) (r : Bigint.t) (w : Bigint.t)
    (op : Bigint.t -> Bigint.t -> Bigint.t) : value =
  let x = power_of_two Bigint.(w-one) in
  let n = op l r in
  let n' =
    if Bigint.(n > zero)
    then bigint_min n Bigint.(x - one)
    else bigint_max n Bigint.(-x) in
  VInt{w;v=n'}

and shift_bigint_left (v : Bigint.t) (o : Bigint.t) : Bigint.t =
  if Bigint.(o > zero)
  then shift_bigint_left Bigint.(v * (one + one)) Bigint.(o - one)
  else v

and shift_bigint_right (v : Bigint.t) (o : Bigint.t) : Bigint.t =
  if Bigint.(v = -one)
  then v
  else if Bigint.(o > zero)
  then shift_bigint_right Bigint.(v / (one + one)) Bigint.(o - one)
  else v

and bitwise_op_of_signeds (op : Bigint.t -> Bigint.t -> Bigint.t)
    (v1 : Bigint.t) (v2 : Bigint.t) (w : Bigint.t) : value =
  let v1' = of_twos_complement v1 w in
  let v2' = of_twos_complement v2 w in
  let n = op v1' v2' in
  VBit{w;v=to_twos_complement n w}

and structs_equal (l1 : (string * value) list)
    (l2 : (string * value) list) : value =
  let f (a : (string * value) list) (b : string * value) =
    if List.Assoc.mem a ~equal:String.equal (fst b)
    then a
    else b :: a in
  let l1' = List.fold_left l1 ~init:[] ~f:f in
  let l2' = List.fold_left l2 ~init:[] ~f:f in
  let g (a,b) =
    let h = (fun (x,y) -> String.equal x a && assert_bool (eval_beq y b)) in
    List.exists l2' ~f:h in
  let b = List.for_all l1' ~f:g in
  VBool b

and headers_equal (l1 : (string * value) list) (l2 : (string * value) list)
    (b1 : bool) (b2 : bool) : value =
  let a = (not b1 && not b2) in
  let b = (b1 && b2 && assert_bool (structs_equal l1 l2)) in
  VBool (a || b)

and stacks_equal (l1 : value list) (l2 : value list) : value =
  let f = (fun i a -> a |> eval_beq (List.nth_exn l2 i) |> assert_bool) in
  let b = List.for_alli l1 ~f:f in
  VBool b

and unions_equal (v1 : value) (v2 : value) (l1 : (string * bool) list)
    (l2 : (string * bool) list) : value =
  let f = fun (_,x) -> not x in
  let b1 = (List.for_all l1 ~f:f) && (List.for_all l2 ~f:f) in
  let l1' = List.map l1 ~f:(fun (x,y) -> (y,x)) in
  let l2' = List.map l2 ~f:(fun (x,y) -> (y,x)) in
  let b2 = Poly.(=) (List.Assoc.find l1' true ~equal:Poly.(=)) (List.Assoc.find l2' true ~equal:Poly.(=)) in
  let b3 = eval_beq v1 v2 |> assert_bool in
  VBool (b1 || (b2 && b3))

(*----------------------------------------------------------------------------*)
(* Type Casting Evaluation *)
(*----------------------------------------------------------------------------*)

and bool_of_val (v : value) : value =
  match v with
  | VBit{w;v=n} when Bigint.(w = one) -> VBool Bigint.(n = one)
  | _ -> failwith "cast to bool undefined"

and bit_of_val (env : EvalEnv.t) (ctrl : ctrl) (e : Expression.t)
    (v : value) : EvalEnv.t * signal * value =
  let (env', s, x) = eval_expression' env ctrl SContinue e in
  let w = bigint_of_val x in
  let v' = match v with
    | VInt{v=n;_}
    | VBit{v=n;_}
    | VInteger n -> bit_of_rawint n w
    | _ -> failwith "cast to bitstring undefined" in
  match s with
  | SContinue -> (env', s,v')
  | SReject _ -> (env',s,VNull)
  | _ -> failwith "unreachable"

and int_of_val (env : EvalEnv.t) (ctrl : ctrl) (e : Expression.t)
    (v : value) : EvalEnv.t * signal * value =
  let (env', s, x) = eval_expression' env ctrl SContinue e in
  let w = bigint_of_val x in
  let v' = match v with
    | VBit{v=n;_}
    | VInt{v=n;_}
    | VInteger n -> int_of_rawint n w
    | _ -> failwith "cast to bitstring undefined" in
  match s with
  | SContinue -> (env', s,v')
  | SReject _ -> (env',s,VNull)
  | _ -> failwith "unreachable"

and bit_of_rawint (n : Bigint.t) (w : Bigint.t) : value =
  VBit{w;v=of_twos_complement n w}

and int_of_rawint (n : Bigint.t) (w : Bigint.t) : value =
  VInt{w;v=to_twos_complement n w}

and of_twos_complement (n : Bigint.t) (w : Bigint.t) : Bigint.t =
  let w' = power_of_two w in
  if Bigint.(n >= w')
  then Bigint.(n % w')
  else if Bigint.(n < zero)
  then of_twos_complement Bigint.(n + w') w
  else n

and to_twos_complement (n : Bigint.t) (w : Bigint.t) : Bigint.t =
  let two = Bigint.(one + one) in
  let w' = power_of_two w in
  if Bigint.(n >= (w' / two))
  then to_twos_complement Bigint.(n-w') w
  else if Bigint.(n < -(w'/two))
  then to_twos_complement Bigint.(n+w') w
  else n

(*----------------------------------------------------------------------------*)
(* Membership Evaluation *)
(*----------------------------------------------------------------------------*)

and eval_struct_mem (env : EvalEnv.t) (name : string)
    (fs : (string * value) list) : EvalEnv.t * signal * value =
  (env, SContinue, List.Assoc.find_exn fs name ~equal:String.equal)

and eval_header_mem (env : EvalEnv.t) (fname : string) (e : Expression.t)
    (fs : (string * value) list) (valid : bool) : EvalEnv.t * signal * value =
  match fname with
  | "isValid"
  | "setValid"
  | "setInvalid" -> (env, SContinue, VBuiltinFun{name=fname;caller=lvalue_of_expr e})
  | _            -> (env, SContinue, List.Assoc.find_exn fs fname ~equal:String.equal)

and eval_stack_mem (env : EvalEnv.t) (fname : string) (e : Expression.t)
    (hdrs : value list) (size : Bigint.t)
    (next : Bigint.t) : EvalEnv.t * signal * value =
  match fname with
  | "size"       -> eval_stack_size env size
  | "next"       -> eval_stack_next env hdrs size next
  | "last"       -> eval_stack_last env hdrs size next
  | "lastIndex"  -> eval_stack_lastindex env next
  | "pop_front"
  | "push_front" -> eval_stack_builtin env fname e
  | _ -> failwith "stack member unimplemented"

and eval_runtime_mem (env : EvalEnv.t) (mname : string) (expr : Expression.t)
    (v : vruntime) : EvalEnv.t * signal * value =
  match v with
  | PacketIn p -> eval_packet_in_mem env mname expr p
  | PacketOut p -> eval_packet_out_mem env mname expr p

and eval_stack_size (env : EvalEnv.t)
    (size : Bigint.t) : EvalEnv.t * signal * value =
  let five = Bigint.(one + one + one + one + one) in
  let thirty_two = shift_bigint_left Bigint.one five in
  (env, SContinue, VBit{w=thirty_two;v=size})

and eval_stack_next (env : EvalEnv.t) (hdrs : value list) (size : Bigint.t)
    (next : Bigint.t) : EvalEnv.t * signal * value =
  let (env', s, hdr) =
    if Bigint.(next >= size)
    then (env, SReject "StackOutOfBounds", VNull)
    else (env, SContinue, List.nth_exn hdrs Bigint.(to_int_exn next)) in
  (env', s, hdr)

and eval_stack_last (env : EvalEnv.t) (hdrs : value list) (size : Bigint.t)
    (next : Bigint.t) : EvalEnv.t * signal *  value =
  let (env', s, hdr) =
    if Bigint.(next < one) || Bigint.(next > size)
    then (env, SReject "StackOutOfBounds", VNull)
    else (env, SContinue, List.nth_exn hdrs Bigint.(to_int_exn next)) in
  (env', s, hdr)

and eval_stack_lastindex (env : EvalEnv.t)
    (next : Bigint.t) : EvalEnv.t * signal * value =
  let five = Bigint.(one + one + one + one + one) in
  let thirty_two = shift_bigint_left Bigint.one five in
  (env, SContinue, VBit{w=thirty_two;v=Bigint.(next - one)})

and eval_stack_builtin (env : EvalEnv.t) (fname : string)
    (e : Expression.t) : EvalEnv.t * signal * value =
  (env, SContinue, VBuiltinFun{name=fname;caller=lvalue_of_expr e})

and eval_packet_in_mem (env : EvalEnv.t) (mname : string) (expr : Expression.t)
    (p : packet_in) : EvalEnv.t * signal * value =
  match mname with
  | "extract"   -> (env, SContinue, VBuiltinFun{name=mname;caller=lvalue_of_expr expr})
  | "length"    -> (env, SContinue, VBuiltinFun{name=mname;caller=lvalue_of_expr expr})
  | "lookahead" -> (env, SContinue, VBuiltinFun{name=mname;caller=lvalue_of_expr expr})
  | "advance"   -> (env, SContinue, VBuiltinFun{name=mname;caller=lvalue_of_expr expr})
  | _ -> failwith "packet member undefined"

and eval_packet_out_mem (env : EvalEnv.t) (mname : string) (expr : Expression.t)
    (p : packet_out) : EvalEnv.t * signal * value =
  match mname with
  | "emit" -> (env, SContinue, VBuiltinFun{name=mname;caller=lvalue_of_expr expr})
  | _ -> failwith "packet out member undefined"

(*----------------------------------------------------------------------------*)
(* Function and Method Call Evaluation *)
(*----------------------------------------------------------------------------*)

and eval_funcall' (env : EvalEnv.t) (ctrl : ctrl) (params : Parameter.t list)
    (args : Argument.t list) (body : Block.t) : EvalEnv.t * signal * value =
  let (fenv, s) = copyin env ctrl params args in
  let (fenv', sign) = eval_block fenv ctrl SContinue body in
  let final_env = copyout fenv' ctrl params args in
  match sign with
  | SReturn v -> (final_env, SContinue, v)
  | SReject _
  | SContinue
  | SExit     -> (final_env, sign, VNull)

and copyin (env : EvalEnv.t) (ctrl : ctrl) (params : Parameter.t list)
    (args : Argument.t list) : EvalEnv.t * signal =
  let fenv = EvalEnv.push_scope env in
  let ((fenv',s),arg_vals) =
    List.fold_mapi args ~f:(eval_nth_arg params ctrl) ~init:(fenv,SContinue) in
  let fenv' = List.fold2_exn params arg_vals ~init:fenv' ~f:insert_arg in
  match s with
  | SContinue -> (fenv',s)
  | SReject _ -> (fenv',s)
  | _ -> failwith " unreachable"

and copyout (fenv : EvalEnv.t) (ctrl : ctrl) (params : Parameter.t list)
    (args : Argument.t list) : EvalEnv.t =
  let env = EvalEnv.pop_scope fenv in
  List.fold2_exn params args ~init:env ~f:(copy_arg_out fenv ctrl)

and eval_nth_arg (params : Parameter.t list) (ctrl : ctrl) (i : int)
    ((env,sign) : EvalEnv.t * signal)
    (e : Argument.t) : (EvalEnv.t * signal) * (string * value) =
  let open Parameter in
  let open Argument in
  let p = snd (List.nth_exn params i) in
  let ((env',s,v), n) = match snd e with
    | Expression {value=expr} ->
      (eval_expression' env ctrl SContinue expr, snd p.variable)
    | KeyValue {value=expr;key=(_,n)} ->
      (eval_expression' env ctrl SContinue expr, n)
    | Missing ->
      (eval_expression' env ctrl SContinue (assert_some p.opt_value), snd p.variable) in
  match (sign,s) with
  | SContinue,SContinue -> ((env',s), (n,v))
  | SReject _, _ -> ((env,sign),(n,VNull))
  | _, SReject _ -> ((env',s),(n,VNull))
  | _ -> failwith "unreachable"

and insert_arg (e : EvalEnv.t) (p : Parameter.t) ((name,v) : string * value) : EvalEnv.t =
  let open Types.Direction in
  let v' = match v with
    | VHeader{fields=l;is_valid=b;_} -> VHeader{fields=l;is_valid=b}
    | VStruct{fields=l;_}            -> VStruct{fields=l}
    | _ -> v in
  let var = snd (snd p).variable in
  match (snd p).direction with
  | None
  | Some (_, InOut)
  | Some (_, In) ->
     let e = EvalEnv.insert_val_firstlevel var v' e in
     EvalEnv.insert_typ_firstlevel var (snd p).typ e
  | Some (_, Out) -> e

and copy_arg_out (fenv : EvalEnv.t) (ctrl : ctrl) (e : EvalEnv.t) (p : Parameter.t)
    (a : Argument.t) : EvalEnv.t =
  match (snd p).direction with
  | None ->
    begin match snd (snd p).typ with
      | TypeName(_,n)
      | TopLevelType(_,n) ->
        if is_extern_object (EvalEnv.find_decl_toplevel n e)
        then copy_arg_out_h fenv ctrl e p a
        else e
      | _ -> e end
  | Some x ->
    begin match snd x with
      | InOut
      | Out -> copy_arg_out_h fenv ctrl e p a
      | In -> e end

and copy_arg_out_h (fenv : EvalEnv.t) (ctrl : ctrl) (e : EvalEnv.t) (p : Parameter.t)
    (a : Argument.t) : EvalEnv.t =
  let open Argument in
  let v = EvalEnv.find_val (snd (snd p).variable) fenv in
  begin match snd a with
    | Expression {value=expr}
    | KeyValue {value=expr;_} -> fst (eval_assign' e ctrl (lvalue_of_expr expr) v)
    | Missing -> e end

(*----------------------------------------------------------------------------*)
(* Built-in Function Evaluation *)
(*----------------------------------------------------------------------------*)

and eval_builtin (env : EvalEnv.t) (ctrl : ctrl) (name : string) (lv : lvalue)
    (args : Argument.t list) (ts : Type.t list) : EvalEnv.t * signal * value =
  match name with
  | "isValid"    -> eval_isvalid env ctrl lv
  | "setValid"   -> eval_setbool env ctrl lv true
  | "setInvalid" -> eval_setbool env ctrl lv false
  | "pop_front"  -> eval_popfront env ctrl lv args
  | "push_front" -> eval_pushfront env ctrl lv args
  | (* TODO *) "extract"    -> eval_extract env ctrl lv args ts
  | (* TODO *) "emit"       -> eval_emit env ctrl lv args
  | (* TODO *) "length"     -> eval_length env ctrl lv
  | (* TODO *) "lookahead"  -> eval_lookahead env ctrl lv ts
  | (* TODO *) "advance"    -> eval_advance env ctrl lv args
  | "apply"      -> let (s,v) = value_of_lvalue env ctrl lv in
                    eval_app env ctrl s v args
  | (* TODO *) "verify"     -> eval_verify env ctrl args
  | _ -> failwith "builtin unimplemented"

and eval_isvalid (env : EvalEnv.t) (ctrl : ctrl)
    (lv : lvalue) : EvalEnv.t * signal * value =
  let (s,v) = value_of_lvalue env ctrl lv in
  match s with
  | SContinue ->
    begin match lv with
      | LName _
      | LTopName _
      | LBitAccess _
      | LArrayAccess _ ->
        begin match v with
          | VHeader{is_valid=b;_} -> (env, s, VBool b)
          | _ -> failwith "isvalid call is not a header" end
      | LMember{expr=lv';name=n} ->
        let (s',v') = value_of_lvalue env ctrl lv' in
        begin match s' with
          | SContinue ->
            begin match v' with
              | VUnion{valid_fields=l;_} ->
                (env, s', VBool (List.Assoc.find_exn l n ~equal:String.equal))
              | _ ->
                begin match v with
                  | VHeader{is_valid=b;_} -> (env, s', VBool b)
                  | _ -> failwith "isvalid call is not a header" end end
          | SReject _ -> (env, s', VNull)
          | _ -> failwith "unreachable" end end
  | SReject _ -> (env, s, VNull)
  | _ -> failwith "unreachable"

and eval_setbool (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (b : bool) : EvalEnv.t * signal * value =
  match lv with
  | LName n ->
    begin match EvalEnv.find_val n env with
      | VHeader{fields=fs;_} ->
        let env' = fst (eval_assign' env ctrl lv (VHeader{fields=fs;is_valid=b})) in
        (env', SContinue, VNull)
      | _ -> failwith "not a header" end
  | LTopName n ->
    begin match EvalEnv.find_val_toplevel n env with
      | VHeader{fields=fs;_} ->
        let env' = fst (eval_assign' env ctrl lv (VHeader{fields=fs;is_valid=b})) in
        (env', SContinue, VNull)
      | _ -> failwith "not a header" end
  | LMember{expr=lv';name=n2} ->
    let (s,v') = value_of_lvalue env ctrl lv' in
    begin match s with
      | SContinue ->
        begin match v' with
          | VUnion{valid_header=fs;valid_fields=vs} ->
            let vs' = List.map vs ~f:(fun (a,_) -> (a,if b then String.equal a n2 else b)) in
            let u = VUnion{valid_header=fs;valid_fields=vs'} in
            let env' = fst (eval_assign' env ctrl lv' u) in
            (env', SContinue, VNull)
          | VStruct{fields=fs} -> failwith "unimplemented"
          | _ -> failwith "not a union" end
      | SReject _ -> (env, s, VNull)
      | _ -> failwith "unreachable" end
  | LArrayAccess{expr=lv';idx=e} ->
    let (s,v') = value_of_lvalue env ctrl lv' in
    begin match s with
      | SContinue ->
        begin match v' with
          | VStack{headers=hdrs;size;next} ->
            let (env', s, i) = eval_expression' env ctrl SContinue e in
            let i' = bigint_of_val i in
            let (hdrs1, hdrs2) = List.split_n hdrs (Bigint.to_int_exn i') in
            let hdrs' = match hdrs2 with
              | VHeader{fields=vs;_} :: t ->
                hdrs1 @ (VHeader{fields=vs;is_valid=b} :: t)
              | _ -> failwith "not a header" in
            begin match s with
              | SContinue ->
                let s = VStack{headers=hdrs';size;next} in
                let env'' = fst (eval_assign' env' ctrl lv' s) in
                (env'', SContinue, VNull)
              | SReject _ -> (env', s, VNull)
              | _ -> failwith "unreachable" end
          | _ -> failwith "not a stack" end
      | SReject _ -> (env, s , VNull)
      | _ -> failwith "unreachable" end
  | LBitAccess _ -> failwith "not a header"

and eval_popfront (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (args : Argument.t list) : EvalEnv.t * signal * value =
  eval_push_pop env ctrl lv args false

and eval_pushfront (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (args : Argument.t list) : EvalEnv.t * signal * value =
  eval_push_pop env ctrl lv args true

and eval_extract (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (args : Argument.t list) (ts : Type.t list) : EvalEnv.t * signal * value =
  match args with
  | [(_,Argument.Expression{value})]
  | [(_,Argument.KeyValue{value;_})]-> eval_extract' env ctrl lv value Bigint.zero
  | [(_,Argument.Expression{value=e1}); (_,Argument.Expression{value=e2})]
  | [(_,Argument.KeyValue{value=e1;key=(_,"variableSizeHeader")});
     (_,Argument.KeyValue{value=e2;key=(_,"variableFieldSizeInBits")})]
  | [(_,Argument.KeyValue{value=e2;key=(_,"variableFieldSizeInBits")});
     (_,Argument.KeyValue{value=e1;key=(_,"variableSizeHeader")})] ->
    let (env', s, b') = eval_expression' env ctrl SContinue e2 in
    let n = bigint_of_val b' in
    begin match s with
      | SContinue -> eval_extract' env' ctrl lv e1 n
      | SReject _ -> (env',s,VNull)
      | _ -> failwith "unreachable" end
  | [(_,Argument.Missing)] ->
    let t = match ts with
      | [x] -> x
      | _ -> failwith "invalid type args for extract" in
    eval_advance' env ctrl lv (width_of_typ env ctrl t)
  | _ -> failwith "wrong number of args for extract"

and eval_emit (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (args : Argument.t list) : EvalEnv.t * signal * value =
  let args' = match args with
    | [a] -> List.map args ~f:snd
    | _ -> failwith "invalid emit args" in
  let expr = match args' with
    | [Argument.Expression{value}]
    | [Argument.KeyValue{value=value;_}] -> value
    | _ -> failwith "invalid emit args" in
  let lemit = lvalue_of_expr expr in
  let (env',s,_) = eval_expression' env ctrl SContinue expr in (* TODO  *)
  let (s',v) = lv |> value_of_lvalue env ctrl in
  let p = v |> assert_runtime |> assert_packet_out in
  let (env'', s'', p') = emit_lval env' ctrl p lemit in
  let env''' = fst (eval_assign' env'' ctrl lv (VRuntime(PacketOut p'))) in
  match s,s',s'' with
  | SContinue,SContinue,SContinue -> (env''', s, VNull)
  | SReject _,_,_ -> (env, s, VNull)
  | _,SReject _,_ -> (env',s',VNull)
  | _,_,SReject _ -> (env',s'',VNull)
  | _ -> failwith "unreachable"

and eval_length (env : EvalEnv.t) (ctrl : ctrl)
    (lv : lvalue) : EvalEnv.t * signal * value =
  let (s,v) = value_of_lvalue env ctrl lv in
  let p = v |> assert_runtime |> assert_packet_in in
  match s with
  | SContinue ->
    (env, s, VBit{w=Bigint.of_int 32;v=p |> Cstruct.len |> Bigint.of_int})
  | SReject _ -> (env, s, VNull)
  | _ -> failwith "unreachable"

and eval_lookahead (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (ts : Type.t list) : EvalEnv.t * signal * value =
  let t = match ts with
    | [t] -> t
    | _ -> failwith "invalid lookahead type args" in
  let w = width_of_typ env ctrl t in
  let (s,v) = lv |> value_of_lvalue env ctrl in
  match s with
  | SContinue ->
    let p = v |> assert_runtime |> assert_packet_in in
    let eight = Bigint.((one + one) * (one + one) * (one + one)) in
    begin try
        let (p',_) = Cstruct.split ~start:0 p Bigint.(to_int_exn (w/eight)) in
        let (_,n,_) = bytes_of_packet p' Bigint.(w/eight) in
        (env, SContinue, val_of_bigint env ctrl w n (init_val_of_typ env ctrl t) t)
      with Invalid_argument _ ->
        (env, SReject "PacketTooShort", VNull) end
  | SReject _ -> (env ,s,VNull)
  | _ -> failwith "unreachable"

and eval_advance (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (args : Argument.t list) : EvalEnv.t * signal * value =
  let args' = List.map args ~f:snd in
  let expr = match args' with
    | [Argument.Expression{value}]
    | [Argument.KeyValue{value;_}] -> value
    | _ -> failwith "invalid advance args" in
  let (env',s,v) = eval_expression' env ctrl SContinue expr in
  let n = v |> bigint_of_val in
  match s with
  | SContinue -> eval_advance' env' ctrl lv n
  | SReject _ -> (env, s, VNull)
  | _ -> failwith "unreachable"

and eval_advance' (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (n : Bigint.t) : EvalEnv.t * signal * value =
  let (s,v) = value_of_lvalue env ctrl lv in
  let p = v |> assert_runtime |> assert_packet_in in
  match s with
  | SContinue ->
    begin try
        let x = n |> Bigint.to_int_exn |> (/) 8 in
        let p' = Cstruct.split p x |> snd in
        let env' = fst (eval_assign' env ctrl lv (VRuntime(PacketIn p'))) in
        (env', SContinue, VNull)
      with Invalid_argument _ ->
        (env, SReject "PacketTooShort", VNull) end
  | SReject _ -> (env,s,VNull)
  | _ -> failwith "unreachable"

and eval_verify (env : EvalEnv.t) (ctrl : ctrl)
    (args : Argument.t list) : EvalEnv.t * signal * value =
  let exp_of_arg (arg : Argument.pre_t) =
    match arg with
    | Expression {value} -> value
    | _ -> failwith "arg is not an expression" in
  match args with
  | b :: err :: [] ->
    let (env', _, v) = eval_expression' env ctrl SContinue (snd b |> exp_of_arg) in
    begin match v with
    | VBool true -> (env', SContinue, VNull)
    | VBool false ->
      let (env'', _, v') = eval_expression' env' ctrl SContinue (snd err |> exp_of_arg) in
      begin match v' with
        | VError e -> (env'', SReject e, VNull)
        | _ -> failwith "verify expected error" end
    | _ -> failwith "verify expected bool"
    end
  | _ -> failwith "verify improper args"

and eval_push_pop (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (args : Argument.t list) (b : bool) : EvalEnv.t * signal * value =
  let (env',s, a) = eval_push_pop_args env ctrl args in
  let (s',v) = value_of_lvalue env ctrl lv in
  let (hdrs, size, next) =
    match v with
    | VStack{headers=hdrs;size;next} -> (hdrs,size,next)
    | _ -> failwith "push call not a header stack" in
  let x = if b then Bigint.(size - a) else a in
  let (hdrs1, hdrs2) = List.split_n hdrs Bigint.(to_int_exn x) in
  let t = typ_of_stack_mem env ctrl lv in
  let hdrs0 = List.init (Bigint.to_int_exn a) ~f:(fun x -> init_val_of_typ env ctrl t) in
  let hdrs' = if b then hdrs0 @ hdrs1 else hdrs2 @ hdrs0 in
  let y = if b then Bigint.(next + a) else Bigint.(next-a) in
  let v = VStack{headers=hdrs';size;next=y} in
  match s,s' with
  | SContinue, SContinue -> (fst (eval_assign' env ctrl lv v), s, VNull)
  | SReject _, _ -> (env',s,VNull)
  | _, SReject _ -> (env',s',VNull)
  | _ -> failwith "unreachble"

and eval_push_pop_args (env : EvalEnv.t) (ctrl : ctrl)
    (args : Argument.t list) : EvalEnv.t * signal * Bigint.t =
  let args' = List.map args ~f:snd in
  match args' with
  | [Argument.Expression{value}]
  | [Argument.KeyValue{value=value;_}] ->
    let (env', s, v) = eval_expression' env ctrl SContinue value in
    begin match s with
      | SContinue -> (env', s, bigint_of_val v)
      | SReject _ -> (env', s, Bigint.zero)
      | _ -> failwith "unreachable" end
  | _ -> failwith "invalid push or pop args"

and eval_extract' (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (expr : Expression.t) (w : Bigint.t) : EvalEnv.t * signal * value =
  let (env', s, v) = eval_expression' env ctrl SContinue expr in
  match s with
  | SContinue ->
    let lhdr = lvalue_of_expr expr in
    let t = typ_of_lvalue env' ctrl lhdr in
    let d = decl_of_typ env' t in
    let _ = assert_header v in
    let v' = init_val_of_typ env ctrl t in
    let (s,v) = lv |> value_of_lvalue env' ctrl in
    let p = v |> assert_runtime |> assert_packet_in in
    let eight = Bigint.((one + one) * (one + one) * (one + one)) in
    let nbytes = Bigint.(nbytes_of_hdr env' ctrl d + w / eight)in
    let (p',n,s') = bytes_of_packet p nbytes in
    begin match s with
      | SContinue ->
        begin match s' with
          | SReject _ -> (env',s',VNull)
          | SContinue ->
            let (fs,_) = assert_header v' in
            let (ns, vs) = List.unzip fs in
            let ((_,s),vs') =
              List.fold_map vs ~init:(Bigint.(nbytes * eight, n), SContinue) ~f:(extract_hdr_field w) in
            begin match s with
              | SReject _ -> (env',s,VNull)
              | SContinue ->
                let fs' = List.zip_exn ns vs' in
                let h = VHeader{fields=fs';is_valid=true} in
                let (env'',s') = eval_assign' env' ctrl lhdr h in
                begin match s' with
                  | SContinue ->
                    (fst (eval_assign' env'' ctrl lv (VRuntime(PacketIn p'))), s', VNull)
                  | SReject _ -> (env', s',VNull)
                  | _ -> failwith "unreachable" end
              | _ -> failwith "unreachable" end
          | _ -> failwith "unreachable" end
      | SReject _ -> (env', s, VNull)
      | _ -> failwith "unreachable" end
  | SReject _ -> (env',s,VNull)
  | _ -> failwith "unreachable"

and extract_hdr_field (nvarbits : Bigint.t) (x : (Bigint.t * Bigint.t) * signal)
    (v : value) : ((Bigint.t * Bigint.t) * signal) * value =
  let (n,s) = x in
  match s with
  | SContinue ->
    begin match v with
      | VBit{w;_} -> extract_bit n w
      | VInt{w;_} -> extract_int n w
      | VVarbit{max;_} -> extract_varbit nvarbits n max
      | _ -> failwith "invalid header field type" end
  | SReject _ -> ((n,s),VNull)
  | _ -> failwith "unreachable"

and extract_bit (n : Bigint.t * Bigint.t)
    (w : Bigint.t) : ((Bigint.t * Bigint.t) * signal) * value =
  let (nw,nv) = n in
  let x = bitstring_slice nv Bigint.(nw-one) Bigint.(nw-w) in
  let y = bitstring_slice nv Bigint.(nw-w-one) Bigint.zero in
  Bigint.(((nw-w, y), SContinue), VBit{w;v=x})

and extract_int (n : Bigint.t * Bigint.t)
    (w : Bigint.t) : ((Bigint.t * Bigint.t) * signal) * value =
  let (nw,nv) = n in
  let x = bitstring_slice nv Bigint.(nw-one) Bigint.(nw-w) in
  let y = bitstring_slice nv Bigint.(nw-w-one) Bigint.zero in
  Bigint.(((nw-w, y), SContinue), VInt{w;v=to_twos_complement x w})

and extract_varbit (nbits : Bigint.t) (n : Bigint.t * Bigint.t)
    (w : Bigint.t) : ((Bigint.t * Bigint.t) * signal) * value =
  let (nw,nv) = n in
  if Bigint.(nbits > w)
  then ((n,SReject "HeaderTooShort"),VNull)
  else
    let x = bitstring_slice nv Bigint.(nw-one) Bigint.(nw-nbits) in
    let y = bitstring_slice nv Bigint.(nw-nbits-one) Bigint.zero in
    Bigint.(((nw-nbits, y), SContinue), VVarbit{max=w;w=nbits;v=x})

and emit_lval (env : EvalEnv.t) (ctrl : ctrl) (p : packet_out)
    (lv : lvalue) : EvalEnv.t * signal * packet_out =
  let (s,v) = value_of_lvalue env ctrl lv in
  match s with
  | SContinue ->
    begin match v with
      | VStruct{fields=fs;_}                     -> emit_struct env ctrl p lv fs
      | VHeader{fields=fs;is_valid=b;_}          -> (env, s, emit_header env ctrl p lv fs b)
      | VUnion{valid_header=v;valid_fields=bs;_} -> emit_union env ctrl p lv v bs
      | VStack{headers=hs;_}                     -> emit_stack env ctrl p lv hs
      | _ -> failwith "emit undefined on type" end
  | SReject _ -> (env, s, p)
  | _ -> failwith "unreachable"

and emit_struct (env : EvalEnv.t) (ctrl : ctrl) (p : packet_out) (lv : lvalue)
    (fs :(string * value) list) : EvalEnv.t * signal * packet_out =
  let fs' = reset_fields env ctrl lv fs in
  let h (e,s,p) (n,v) =
    match s with
    | SContinue -> emit_lval e ctrl p (LMember{expr=lv;name=n})
    | SReject _ -> (e,s,p)
    | _ -> failwith "unreachable" in
  List.fold_left fs' ~init:(env, SContinue, p) ~f:h

and emit_header (env : EvalEnv.t) (ctrl : ctrl) (p : packet_out) (lv : lvalue)
    (fs : (string * value) list) (b : bool) : packet_out =
  if b
  then
    let fs' = reset_fields env ctrl lv fs in
    let fs'' = List.map fs' ~f:snd in
    let d = decl_of_typ env (typ_of_lvalue env ctrl lv) in
    let f n v =
      match v with
      | VBit{w;v} -> Bigint.(n * power_of_two w + v)
      | VInt{w;v} -> Bigint.(n * power_of_two w + (of_twos_complement v w))
      | VVarbit{w;v;_} -> Bigint.(n * power_of_two w + v)
      | _ -> failwith "invalid header field type" in
    let n = List.fold_left fs'' ~init:Bigint.zero ~f:f in
    let eight = Bigint.((one + one) * (one + one) * (one + one)) in
    let w = Bigint.(nbytes_of_hdr env ctrl d * eight) in
    let p1 = packet_of_bytes n w in
    let (p0,p2) = p in
    (Cstruct.append p0 p1,p2)
  else p

and emit_union (env : EvalEnv.t) (ctrl : ctrl) (p : packet_out) (lv : lvalue)
    (v : value) (vs : (string * bool) list) : EvalEnv.t * signal * packet_out =
  if List.exists vs ~f:snd
  then
    let vs' = List.map vs ~f:(fun (a,b) -> (b,a)) in
    let n = List.Assoc.find_exn vs' ~equal:Poly.(=) true in
    emit_lval env ctrl p (LMember{expr=lv;name=n})
  else (env, SContinue, p)

and emit_stack (env : EvalEnv.t) (ctrl : ctrl) (p : packet_out) (lv : lvalue)
    (hs : value list) : EvalEnv.t * signal * packet_out =
  let f (e,s,p,n) v =
    let lv' = (LArrayAccess{expr=lv;idx=(Info.dummy, Expression.Int(Info.dummy,
                                                            {value = n;
                                                             width_signed = None}))}) in
    let (e',s',p') = emit_lval env ctrl p lv' in
    match s with
    | SContinue -> (e',s',p', Bigint.(n + one))
    | SReject _ -> (e,s,p,Bigint.(n + one))
    | _ -> failwith "unreachable" in
  let (a,b,c,d) =  List.fold_left hs ~init:(env,SContinue,p,Bigint.zero) ~f:f in
  (a,b,c)

and width_of_typ (env : EvalEnv.t) (ctrl : ctrl) (t : Type.t) : Bigint.t =
  match snd t with
  | Bool -> Bigint.one
  | IntType e -> e |> eval_expression' env ctrl SContinue |> thrd3 |> bigint_of_val
  | BitType e -> e |> eval_expression' env ctrl SContinue |> thrd3 |> bigint_of_val
  | TopLevelType _
  | TypeName _ -> width_of_decl env ctrl (decl_of_typ env t)
  | HeaderStack{header=t';size=e} -> width_of_stack env ctrl t' e
  | Tuple l -> width_of_tuple env ctrl l
  | Void | DontCare -> Bigint.zero
  | Error | VarBit _ | Integer | String -> failwith "type does not a have a fixed width"
  | SpecializedType _ -> failwith "unimplemented"

and width_of_tuple (env : EvalEnv.t) (ctrl : ctrl)
    (l : Type.t list) : Bigint.t =
  let l' = List.map l ~f:(width_of_typ env ctrl) in
  List.fold_left l' ~init:Bigint.zero ~f:Bigint.(+)

and width_of_stack (env : EvalEnv.t) (ctrl : ctrl) (t : Type.t)
    (e : Expression.t) : Bigint.t =
  Bigint.(
    e
    |> eval_expression' env ctrl SContinue
    |> thrd3
    |> bigint_of_val
    |> ( * ) (width_of_typ env ctrl t))

and width_of_hdr (env : EvalEnv.t) (ctrl : ctrl)
    (fs : Declaration.field list) : Bigint.t =
  let ts = List.map fs ~f:(fun f -> (snd f).typ) in
  let ws = List.map ts ~f:(width_of_typ env ctrl) in
  List.fold_left ws ~init:Bigint.zero ~f:Bigint.(+)

and width_of_decl (env : EvalEnv.t) (ctrl : ctrl)
    (d : Declaration.t) : Bigint.t =
  match snd d with
  | Header{fields;_} -> width_of_hdr env ctrl fields
  | Struct{fields;_} -> width_of_hdr env ctrl fields
  | SerializableEnum{typ;_} -> width_of_typ env ctrl typ
  | TypeDef{typ_or_decl;_}
  | NewType{typ_or_decl;_} ->
    begin match typ_or_decl with
      | Left t -> width_of_typ env ctrl t
      | Right d -> width_of_decl env ctrl d end
  | _ -> failwith "decl does not have a fixed width"

and width_of_val (v : value) : Bigint.t =
  match v with
  | VBit {w;v} | VInt {w;v} -> w
  | VInteger _ -> failwith "width of VInteger"
  | _ -> failwith "unimplemented"

and val_of_bigint (env : EvalEnv.t) (ctrl : ctrl) (w : Bigint.t) (n : Bigint.t)
    (v : value) (t : Type.t) : value =
  match v with
  | VNull                                 -> VNull
  | VBool _                               -> VBool Bigint.(bitstring_slice n one zero = one)
  | VBit _                                -> VBit{w;v=n}
  | VInt _                                -> VInt{w;v=to_twos_complement n w}
  | VTuple l                              -> tuple_of_bigint env ctrl w n t l
  | VStruct{fields=fs;_}                  -> struct_of_bigint env ctrl w n t fs
  | VHeader{fields=fs;_}                  -> header_of_bigint env ctrl w n t fs
  | VStack{headers=vs;size=s;next=n;_}    -> stack_of_bigint env ctrl w n t vs s n
  | VSenumField{typ_name=a;enum_name=b;v} ->
    VSenumField{typ_name=a;enum_name=b;v=val_of_bigint env ctrl w n v t}
  | VInteger _
  | VVarbit _
  | VSet _
  | VString _
  | VError _
  | VFun _
  | VBuiltinFun _
  | VAction _
  | VUnion _
  | VEnumField _
  | VRuntime _
  | VParser _
  | VControl _
  | VPackage _
  | VTable _ -> failwith "value does not have a fixed width"

and tuple_of_bigint (env : EvalEnv.t) (ctrl : ctrl) (w : Bigint.t)
    (n : Bigint.t) (t : Type.t) (l : value list) : value =
  let f i (w,n) v =
    let t' = typ_of_tuple_field t i in
    let wv = width_of_typ env ctrl t' in
    let nv = bitstring_slice n Bigint.(w-one) Bigint.(w-wv) in
    let w' = Bigint.(w-wv) in
    let n' = bitstring_slice n Bigint.(w-wv-one) Bigint.zero in
    let v' = val_of_bigint env ctrl wv nv v t' in
    ((w',n'), v') in
  let l' = List.folding_mapi l ~init:(w,n) ~f:f in
  VTuple l'

and struct_of_bigint (env : EvalEnv.t) (ctrl : ctrl) (w : Bigint.t) (n : Bigint.t)
    (t : Type.t) (fs : (string * value) list) : value =
  let f (w,n) (s,v) =
    let t' = typ_of_struct_field env t s in
    let wv = width_of_typ env ctrl t' in
    let nv = bitstring_slice n Bigint.(w-one) Bigint.(w-wv) in
    let w' = Bigint.(w-wv) in
    let n' = bitstring_slice n Bigint.(w-wv-one) Bigint.zero in
    let v' = val_of_bigint env ctrl wv nv v t' in
    ((w',n'),(s,v')) in
  let fs' = List.folding_map fs ~init:(w,n) ~f:f in
  VStruct{fields=fs'}

and header_of_bigint (env : EvalEnv.t) (ctrl : ctrl) (w : Bigint.t)
    (n : Bigint.t) (t : Type.t) (fs : (string * value) list) : value =
  let f (w,n) (s,v) =
    let t' = typ_of_header_field env t s in
    let wv = width_of_typ env ctrl t' in
    let nv = bitstring_slice n Bigint.(w-one) Bigint.(w-wv) in
    let w' = Bigint.(w-wv) in
    let n' = bitstring_slice n Bigint.(w-wv-one) Bigint.zero in
    let v' = val_of_bigint env ctrl wv nv v t' in
    ((w',n'),(s,v')) in
  let fs' = List.folding_map fs ~init:(w,n) ~f:f in
  VHeader{fields=fs';is_valid=true}

and stack_of_bigint (env : EvalEnv.t) (ctrl : ctrl) (w : Bigint.t) (n : Bigint.t)
    (t : Type.t) (vs : value list) (size : Bigint.t) (next : Bigint.t) : value =
  let t' = match snd t with
    | HeaderStack{header;_} -> header
    | _ -> failwith "not a header stack" in
  let f (w,n) v =
    let wv = width_of_typ env ctrl t' in
    let nv = bitstring_slice n Bigint.(w-one) Bigint.(w-wv) in
    let w' = Bigint.(w-wv) in
    let n' = bitstring_slice n Bigint.(w-wv-one) Bigint.zero in
    let v' = val_of_bigint env ctrl wv nv v t' in
    ((w',n'),v') in
  let vs' = List.folding_map vs ~init:(w,n) ~f:f in
  VStack{headers=vs';size;next}

(*----------------------------------------------------------------------------*)
(* Parser Evaluation *)
(*----------------------------------------------------------------------------*)

and eval_parser (env : EvalEnv.t) (ctrl : ctrl) (params : Parameter.t list)
    (args : Argument.t list) (vs : (string * value) list)
    (locals : Declaration.t list) (states : Parser.state list) : EvalEnv.t * signal =
  let (penv, s) = copyin env ctrl params args in
  match s with
  | SContinue ->
    let f a (x,y) = EvalEnv.insert_val x y a in
    let penv' = List.fold_left vs ~init:penv ~f:f in
    let penv'' = List.fold_left locals ~init:penv' ~f:(fun e -> eval_decl e ctrl) in
    let states' = List.map states ~f:(fun s -> snd (snd s).name, s) in
    let start = List.Assoc.find_exn states' "start" ~equal:String.equal in
    let (penv''',final_state) = eval_state_machine penv'' ctrl states' start in
    (copyout penv''' ctrl params args, final_state)
  | SReject _ -> (EvalEnv.pop_scope penv, s)
  | _ -> failwith "unreachable"

and eval_state_machine (env : EvalEnv.t) (ctrl : ctrl)
    (states : (string * Parser.state) list)
    (state : Parser.state) : EvalEnv.t * signal =
  let (stms, transition) =
    match snd state with
    | {statements=stms; transition=t;_} -> (stms, t) in
  let stms' = (Info.dummy, Statement.BlockStatement
                 {block = (Info.dummy, {annotations = []; statements = stms})}) in
  let (env', sign) = eval_statement env ctrl SContinue stms' in
  match sign with
  | SContinue -> eval_transition env' ctrl states transition
  | SReject _ -> (env', sign)
  | SReturn _ -> failwith "return statements not permitted in parsers"
  | SExit -> failwith "exit statements not permitted in parsers"

and eval_transition (env : EvalEnv.t) (ctrl : ctrl)
    (states : (string * Parser.state) list)
    (transition : Parser.transition) : EvalEnv.t * signal =
  match snd transition with
  | Direct{next = (_, next)} -> eval_direct env ctrl states next
  | Select{exprs;cases} -> eval_select env ctrl states exprs cases

and eval_direct (env : EvalEnv.t) (ctrl : ctrl)
    (states : (string * Parser.state) list)
    (next : string) : EvalEnv.t * signal =
  match next with
  | "accept" -> (env, SContinue)
  | "reject" -> (env, SReject "NoError")
  | _ -> let state = List.Assoc.find_exn states next ~equal:String.equal in
        eval_state_machine env ctrl states state

and eval_select (env : EvalEnv.t) (ctrl : ctrl)
    (states : (string * Parser.state) list) (exprs : Expression.t list)
    (cases : Parser.case list) : EvalEnv.t * signal =
  let f (env,s) e =
    let (a,b,c) = eval_expression' env ctrl s e in
    ((a,b),c) in
  let ((env', s), vs) = List.fold_map exprs ~init:(env,SContinue) ~f:f in
  let ws = List.map vs ~f:width_of_val in
  match s with
  | SContinue ->
    let g (e,s) set =
      let (x,y,z) = set_of_case e ctrl s set ws in
      ((x,y),(z,x)) in
    let ((env'',s), ss) = List.fold_map cases ~init:(env', SContinue) ~f:g in
    let coerce_value_set s =
      match s with
      | SValueSet {size=si;members=ms;_},e ->
        let h (a,b) c =
          let (x,y,z) = set_of_matches a ctrl b c ws in
          ((x,y),z) in
        let ((e',_),ss) = List.fold_map ms ~init:(e,SContinue) ~f:h in
        (SValueSet {size=si;members=ms;sets=ss},e')
      | x -> x in
    let ss' = List.map ss ~f:coerce_value_set in
    let ms = List.map ss' ~f:(fun (x,y) -> (values_match_set vs x, y)) in
    let ms' = List.zip_exn ms cases
              |> List.map ~f:(fun ((b,env),c) -> (b,(env,c))) in
    let next = List.Assoc.find ms' true ~equal:Poly.(=) in
    begin match next with
      | None -> (env'', SReject "NotMatch")
      | Some (fenv,next) ->
        let next' = snd (snd next).next in
        eval_direct fenv ctrl states next' end
  | SReject _ -> (env', s)
  | _ -> failwith "unreachable"

and set_of_case (env : EvalEnv.t) (ctrl : ctrl) (s : signal)
    (case : Parser.case) (ws : Bigint.t list) : EvalEnv.t * signal * set =
  match s with
  | SContinue -> set_of_matches env ctrl s (snd case).matches ws
  | SReject _ -> (env,s,SUniversal)
  | _ -> failwith "unreachable"

and set_of_matches (env : EvalEnv.t) (ctrl : ctrl) (s : signal)
    (ms : Match.t list) (ws : Bigint.t list) : EvalEnv.t * signal * set =
  match ms,ws with
  | [],_ -> failwith "invalid set"
  | [m],[w] -> set_of_match env ctrl s m w
  | l,ws ->
    let f i (a,b) c =
      let (x,y,z) = set_of_match a ctrl b c (List.nth_exn ws i) in
      ((x,y),z) in
    let ((env',s),l') = List.fold_mapi l ~init:(env,SContinue) ~f:f in
    (env',s,SProd l')

and set_of_match (env : EvalEnv.t) (ctrl : ctrl) (s : signal)
    (m : Match.t) (w : Bigint.t) : EvalEnv.t * signal * set =
  match s with
  | SContinue ->
    begin match snd m with
      | Default
      | DontCare         -> (env, SContinue, SUniversal)
      | Expression{expr} ->
        let (env', s, v) = eval_expression' env ctrl SContinue expr in
        (env', s, assert_set v w) end
  | SReject _ -> (env, s, SUniversal)
  | _ -> failwith "unreachable"

and values_match_set (vs : value list) (s : set) : bool =
  match s with
  | SSingleton{w;v}     -> values_match_singleton vs v
  | SUniversal          -> true
  | SMask{v=v1;mask=v2} -> values_match_mask vs v1 v2
  | SRange{lo=v1;hi=v2} -> values_match_range vs v1 v2
  | SProd l             -> values_match_prod vs l
  | SLpm{w=v1;v=v2;_}   -> values_match_mask vs v1 v2
  | SValueSet {sets=ss;_}   -> values_match_value_set vs ss

and values_match_singleton (vs : value list) (n : Bigint.t) : bool =
  let v = assert_singleton vs in
  v |> bigint_of_val |> (Bigint.(=) n)

and values_match_mask (vs : value list) (v1 : value) (v2 : value) : bool =
  let two = Bigint.(one + one) in
  let v = assert_singleton vs in
  let (a,b,c) = assert_bit v, assert_bit v1, assert_bit v2 in
  let rec h (w0,b0) (w1,b1) (w2,b2) =
    if not (Bigint.(w0 = w1) && Bigint.(w1 = w2))
    then false
    else if Bigint.(w0 = zero)
    then true
    else if Bigint.(b2%two = zero) || Bigint.(b1%two = b0%two)
    then h Bigint.(w0-one, b0/two) Bigint.(w1-one, b1/two) Bigint.(w2-one, b2/two)
    else false in
  h a b c

and values_match_range (vs : value list) (v1 : value) (v2 : value) : bool =
  let v = assert_singleton vs in
  match (v, v1, v2) with
  | VBit{w=w0;v=b0}, VBit{w=w1;v=b1}, VBit{w=w2;v=b2}
  | VInt{w=w0;v=b0}, VInt{w=w1;v=b1}, VInt{w=w2;v=b2} ->
    Bigint.equal w0 w1 && Bigint.equal w1 w2 && Bigint.compare b1 b0 <= 0 && Bigint.compare b0 b2 <= 0
  | _ -> failwith "implicit casts unimplemented"

and values_match_prod (vs : value list) (l : set list) : bool =
  let bs = List.mapi l ~f:(fun i x -> values_match_set [List.nth_exn vs i] x) in
  List.for_all bs ~f:(fun b -> b)

and values_match_value_set (vs : value list) (l : set list) : bool =
  let bs = List.map l ~f:(values_match_set vs) in
  List.exists bs ~f:(fun b -> b)

(* -------------------------------------------------------------------------- *)
(* Control Evaluation *)
(* -------------------------------------------------------------------------- *)

and eval_control (env : EvalEnv.t) (ctrl : ctrl) (params : Parameter.t list)
    (args : Argument.t list) (vs : (string * value) list)
    (locals : Declaration.t list) (apply : Block.t) : EvalEnv.t * signal =
  let (cenv,_) = copyin env ctrl params args in
  let f a (x,y) = EvalEnv.insert_val x y a in
  let cenv' = List.fold_left vs ~init:cenv ~f:f in
  let cenv'' = List.fold_left locals ~init:cenv' ~f:(fun e -> eval_decl e ctrl) in
  let block = (Info.dummy, Statement.BlockStatement {block = apply}) in
  let (cenv''', sign) = eval_statement cenv'' ctrl SContinue block in
  match sign with
  | SContinue
  | SExit     -> (copyout cenv''' ctrl params args, sign)
  | SReject _ -> failwith "control should not reject"
  | SReturn _ -> failwith "control should not return"

(*----------------------------------------------------------------------------*)
(* Helper functions *)
(*----------------------------------------------------------------------------*)

and thrd3 (a,b,c) = c

and assert_singleton (vs : value list) : value =
  match vs with
  | [v] -> v
  | _ -> failwith "value list has more than one element"

and assert_some (x : 'a option) : 'a =
  match x with
  | None -> failwith "is none"
  | Some v -> v

and is_default (p : Table.pre_property) : bool =
  match p with
  | Custom {name=(_,"default_action");_} -> true
  | _ -> false

and assert_functioncall (e : Expression.t) : string * Argument.t list =
  match snd e with
  | FunctionCall {func;args;_} ->
    let f' = func |> assert_ename in (f',args)
  | _ -> failwith "expression not a function call"

and assert_ename (e : Expression.t) : string =
  match snd e with
  | Name (_,n) -> n
  | _ -> failwith "expression not a string"

and is_actionref (p : Table.pre_property) : bool =
  match p with
  | Actions _ -> true
  | _ -> false

and assert_actionref (p : Table.pre_property) : Table.action_ref list =
  match p with
  | Actions{actions} -> actions
  | _ -> failwith "not an action ref list"

and is_entries (p : Table.pre_property) : bool =
  match p with
  | Entries _ -> true
  | _ -> false

and assert_entries (p : Table.pre_property) : Table.entry list =
  match p with
  | Entries{entries=es} -> es
  | _ -> failwith "not an entries"

and is_key (p : Table.pre_property) : bool =
  match p with
  | Key _ -> true
  | _ -> false

and assert_key (p : Table.pre_property) : Table.key list =
  match p with
  | Key{keys=ks} -> ks
  | _ -> failwith "not a key"

and assert_typ (typ_or_decl : (Type.t, Declaration.t) Util.alternative) : Type.t =
  match typ_or_decl with
  | Left typ -> typ
  | Right decl -> failwith "not a typ"

and assert_typ_def (typ : Declaration.t) : (Type.t, Declaration.t) Util.alternative =
  match snd typ with
  | TypeDef {typ_or_decl;_} -> typ_or_decl
  | _ -> failwith "not a typedef"

and is_extern_object (d : Declaration.t) : bool =
  match snd d with
  | ExternObject _ -> true
  | _ -> false

and decl_of_typ (e : EvalEnv.t) (t : Type.t) : Declaration.t =
  match snd t with
  | TypeName (_,s)                 -> (EvalEnv.find_decl s e)
  | TopLevelType (_,s)             -> (EvalEnv.find_decl_toplevel s e)
  | _ -> (Info.dummy, Error{members = []}) (* TODO: find better solution *)

and init_binding_of_field env ctrl f : string * value =
  (snd (snd f).name, init_val_of_typ env ctrl (snd f).typ)

and bigint_of_val (v : value) : Bigint.t =
  match v with
  | VInt{v=n;_}
  | VBit{v=n;_}
  | VInteger n -> n
  | _ -> failwith "value not representable as bigint"

and power_of_two (w : Bigint.t) : Bigint.t =
  shift_bigint_left Bigint.one w

and bitstring_slice (n : Bigint.t) (m : Bigint.t) (l : Bigint.t) : Bigint.t =
  Bigint.(
    if l > zero
    then bitstring_slice (n/(one + one)) (m-one) (l-one)
    else n % (power_of_two (m + one)))

and typ_of_tuple_field (t : Type.t) (i : int) : Type.t =
  match snd t with
  | Tuple ts -> List.nth_exn ts i
  | _ -> failwith "not a tuple type"

and typ_of_struct_field (env : EvalEnv.t) (t : Type.t)
    (fname : string) : Type.t =
  let (_, d) = decl_of_typ env t in
  let fs = match d with
    | Struct h -> h.fields
    | _ -> failwith "not a struct" in
  match List.filter fs ~f:(fun a -> String.equal (snd (snd a).name) fname) with
  | h :: _ -> (snd h).typ
  | _ -> failwith "field name not found"

and typ_of_header_field (env : EvalEnv.t) (t : Type.t)
    (fname : string) : Type.t =
  let (_,d) = decl_of_typ env t in
  let fs = match d with
    | Header h -> h.fields
    | _ -> failwith "not a header" in
  match List.filter fs ~f:(fun a -> String.equal (snd (snd a).name) fname) with
  | h :: _ -> (snd h). typ
  | _ -> failwith "field name not found"

and typ_of_union_field (env : EvalEnv.t) (t : Type.t)
    (fname : string) : Type.t =
  let (_, d) = decl_of_typ env t in
  let fs = match d with
    | HeaderUnion u -> u.fields
    | _ -> failwith "not a union" in
  match List.filter fs ~f:(fun a -> String.equal (snd (snd a).name) fname) with
  | h :: _ -> (snd h).typ
  | _ -> failwith "field name not found"

and typ_of_stack_mem (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue) : Type.t =
  let t = typ_of_lvalue env ctrl lv in
  match snd t with
  | HeaderStack{header;_} -> header
  | _ -> failwith "not a header stack"

and struct_of_list (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue) (l : value list) : value =
  let t = typ_of_lvalue env ctrl lv in
  let d = decl_of_typ env t in
  let fs = match snd d with
    | Declaration.Struct s -> s.fields
    | _ -> failwith "not a struct" in
  let ns = List.map fs ~f:(fun x -> snd (snd x).name) in
  let ts = List.map fs ~f:(fun x -> (snd x).typ) in
  let l' = List.mapi l ~f:(fun i v -> implicit_cast_from_rawint env ctrl v (List.nth_exn ts i)) in
  let l'' = List.mapi l' ~f:(fun i v ->
                implicit_cast_from_tuple env ctrl
                                (LMember{expr=lv;name=List.nth_exn ns i}) v (List.nth_exn ts i)) in
  let l''' = List.mapi l'' ~f:(fun i v -> (List.nth_exn ns i, v)) in
  VStruct{fields=l'''}

and header_of_list (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue) (l : value list) : value =
  let t = typ_of_lvalue env ctrl lv in
  let d = decl_of_typ env t in
  let fs = match snd d with
    | Declaration.Header h -> h.fields
    | _ -> failwith "not a header" in
  let ns = List.map fs ~f:(fun x -> snd (snd x).name) in
  let ts = List.map fs ~f:(fun x -> (snd x).typ) in
  let l' = List.mapi l ~f:(fun i v -> implicit_cast_from_rawint env ctrl v (List.nth_exn ts i)) in
  let l'' = List.mapi l' ~f:(fun i v -> (List.nth_exn ns i, v)) in
  VHeader{fields=l'';is_valid=true}

and implicit_cast_from_rawint (env : EvalEnv.t) (ctrl : ctrl) (v : value)
    (t : Type.t) : value =
  match v with
  | VInteger n ->
    begin match snd t with
      | Type.IntType e ->
        e
        |> eval_expression' env ctrl SContinue
        |> thrd3
        |> bigint_of_val
        |> int_of_rawint n
      | Type.BitType e ->
        e
        |> eval_expression' env ctrl SContinue
        |> thrd3
        |> bigint_of_val
        |> bit_of_rawint n
      | Type.Bool -> failwith "is bool"
      | Type.TypeName (_,n) ->
        EvalEnv.find_decl n env
        |> assert_typ_def
        |> assert_typ
        |> implicit_cast_from_rawint env ctrl v
      | _ -> failwith "attempt to assign raw int to wrong type"
      end
  | _ -> v

and implicit_cast_from_tuple (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
     (v : value) (t : Type.t) : value =
  match v with
  | VTuple l ->
    begin match snd (decl_of_typ env t) with
      | Struct _ -> struct_of_list env ctrl lv l
      | Header _ -> header_of_list env ctrl lv l
      | _ -> VTuple l end
  | _ -> v

and nbytes_of_hdr (env : EvalEnv.t) (ctrl : ctrl)
    (d : Declaration.t) : Bigint.t =
  match snd d with
  | Header{fields = fs;_} ->
    let ts = List.map fs ~f:(fun f -> snd (snd f).typ) in
    let ls = List.map ts
        ~f:(function
            | Type.IntType e
            | Type.BitType e -> eval_expression' env ctrl SContinue e |> thrd3 |> bigint_of_val
            | Type.VarBit _ -> Bigint.zero
            | _ -> failwith "illegal header field type") in
    let n = List.fold_left ls ~init:Bigint.zero ~f:Bigint.(+) in
    let eight = Bigint.((one + one) * (one + one) * (one + one)) in
    Bigint.(n/eight)
  | _ -> failwith "not a header"

and bytes_of_packet (p : packet_in)
    (nbytes : Bigint.t) : packet_in * Bigint.t * signal =
  try
    let (c1,c2) = Cstruct.split p (Bigint.to_int_exn nbytes) in
    let s = Cstruct.to_string c1 in
    let chars = String.to_list s in
    let bytes = List.map chars ~f:Char.to_int in
    let bytes' = List.map bytes ~f:Bigint.of_int in
    let eight = Bigint.((one + one) * (one + one) * (one + one)) in
    let f a n = Bigint.(a * power_of_two eight + n) in
    let n = List.fold_left bytes' ~init:Bigint.zero ~f:f in
    (c2,n,SContinue)
  with Invalid_argument _ -> (p,Bigint.zero,SReject "PacketTooShort")

and packet_of_bytes (n : Bigint.t) (w : Bigint.t) : packet_in =
  let eight = Bigint.((one + one) * (one + one) * (one + one)) in
  let seven = Bigint.(eight - one) in
  let rec h acc n w =
    if Bigint.(w = zero) then acc else
      let lsbyte = bitstring_slice n seven Bigint.zero in
      let n' = bitstring_slice n Bigint.(w-one) eight in
      h (lsbyte :: acc) n' Bigint.(w-eight) in
  let bytes = h [] n w in
  let ints = List.map bytes ~f:Bigint.to_int_exn in
  let chars = List.map ints ~f:Char.of_int_exn in
  let s = String.of_char_list chars in
  Cstruct.of_string s

and reset_fields (env : EvalEnv.t) (ctrl : ctrl) (lv : lvalue)
    (fs : (string * value) list) : (string * value) list =
  let f l (n,v) =
    if List.Assoc.mem l ~equal:String.equal n
    then l
    else (n,v) :: l in
  let fs' = List.fold_left fs ~init:[] ~f:f in
  let init = init_val_of_typ env ctrl (typ_of_lvalue env ctrl lv) in
  let fs0 = match init with
    | VStruct{fields=fs;_}
    | VHeader{fields=fs;_} -> fs
    | _ -> failwith "not a struct or header" in
  let g (n,_) =
    (n, List.Assoc.find_exn fs' ~equal:String.equal n) in
  List.map fs0 ~f:g

and label_matches_string (s : string) (case : Statement.pre_switch_case) : bool =
  match case with
  | Action{label;_}
  | FallThrough{label} ->
    begin match snd label with
      | Default -> true
      | Name(_,n) -> String.equal s n end

(*----------------------------------------------------------------------------*)
(* Program Evaluation *)
(*----------------------------------------------------------------------------*)

let hex_of_nibble (i : int) : string =
  match i with
  | 0 -> "0"
  | 1 -> "1"
  | 2 -> "2"
  | 3 -> "3"
  | 4 -> "4"
  | 5 -> "5"
  | 6 -> "6"
  | 7 -> "7"
  | 8 -> "8"
  | 9 -> "9"
  | 10 -> "A"
  | 11 -> "B"
  | 12 -> "C"
  | 13 -> "D"
  | 14 -> "E"
  | 15 -> "F"
  | _ -> failwith "unreachable"

let hex_of_int (i : int) : string =
  hex_of_nibble (i/16) ^ hex_of_nibble (i%16) ^ " "

let hex_of_char (c : char) : string =
  c |> Char.to_int |> hex_of_int

let hex_of_string (s : string) : string =
  s
  |> String.to_list
  |> List.map ~f:hex_of_char
  |> List.fold_left ~init:"" ~f:(^)

let eval_main (env : EvalEnv.t) (ctrl : ctrl) (pkt : packet_in) : packet_in =
  let name =
    match env |> EvalEnv.find_val "main" |> assert_package |> fst |> snd with
    | Declaration.PackageType {name=(_,n);_} -> n
    | _ -> failwith "main is no a package" in
  match name with
  | "V1Switch"     -> Target.V1Model.eval_pipeline
                        env
                        ctrl
                        pkt
                        eval_app
                        eval_assign'
                        init_val_of_typ
  | "ebpfFilter"   -> Target.EbpfFilter.eval_pipeline
                        env
                        ctrl
                        pkt
                        eval_app
                        eval_assign'
                        init_val_of_typ
  | "EmptyPackage" -> pkt
  | _ -> failwith "architecture not supported"

let eval_expression env ctrl expr =
  let (a,b,c) = eval_expression' env ctrl SContinue expr in
  (a,c)

let eval_program (p : Types.program) (ctrl : ctrl) (pkt : packet_in): string =
  match p with Program l ->
    let env = List.fold_left l ~init:EvalEnv.empty_eval_env ~f:(fun e -> eval_decl e ctrl) in
    EvalEnv.print_env env;
    Format.printf "Done\n";
    let pkt' = eval_main env ctrl pkt in
    print_string "Resulting packet: ";
    pkt'
    |> Cstruct.to_string
    |> hex_of_string

let print_eval_program p ctrl pkt = eval_program p ctrl pkt |> print_endline
