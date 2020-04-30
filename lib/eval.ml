module I = Info
open Core_kernel
open Env
open Types
open Value
open Target
module Info = I (* JNF: ugly hack *)

type env = EvalEnv.t

module type Interpreter = sig
  
  type state
  
  val empty_state : state

  val eval : ctrl -> env -> state -> pkt -> Bigint.t -> state * env * pkt

  val eval_decl : ctrl -> env -> state -> Declaration.t -> (env * state)

  val eval_statement : ctrl -> env -> state -> Statement.t -> (env * state)

  val eval_expression : ctrl -> env -> state  -> Expression.t -> (env * state * value)

  val eval_app : ctrl -> env -> state -> signal -> value -> Argument.t list -> env * state * signal * value

  val eval_assign' : ctrl -> env -> state -> lvalue -> value -> env * state * signal

  val init_val_of_typ : ctrl -> env -> state -> string -> Type.t -> value

end

module MakeInterpreter (T : Target) = struct 

  type state = T.state

  let empty_state = State.empty

  (*----------------------------------------------------------------------------*)
  (* Declaration Evaluation *)
  (*----------------------------------------------------------------------------*)

  let rec eval_decl (ctrl : ctrl) (env : env) (st : state) 
      (d : Declaration.t) : env * state =
    match snd d with
    | Constant {
        annotations = _;
        typ = t;
        value = v;
        name = (_,n);
      } -> eval_const_decl ctrl env st t v n
    | Instantiation {
        annotations = _;
        typ = typ;
        args = args;
        name = (_,n);
        init = None
      } -> eval_instantiation ctrl env st typ args n
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
      } -> (eval_parser_decl env n d, st)
    | Control {
        annotations = _;
        name = (_,n);
        type_params = _;
        params = _;
        constructor_params = _;
        locals = _;
        apply = _;
      } -> (eval_control_decl env n d, st)
    | Function {
        return = _;
        name = (_,n);
        type_params = _;
        params = ps;
        body = b;
      } -> (eval_fun_decl env n ps b d, st)
    | ExternFunction {
        annotations = _;
        return = _;
        name = (_,n);
        type_params = _;
        params = ps;
      } -> (eval_extern_fun env n ps d, st)
    | Variable {
        annotations = _;
        typ = t;
        name = (_,n);
        init = v;
      } -> let (a,b,_) = eval_var_decl ctrl env st t n v in (a,b)
    | ValueSet {
        annotations = _;
        typ = t;
        size = s;
        name = (_,n);
      } -> let (a,b,_) = eval_set_decl ctrl env st t n s in (a,b)
    | Action {
        annotations = _;
        name = (_,n);
        params = ps;
        body = b;
      } -> (eval_action_decl env n ps b d, st)
    | Table {
        annotations = _;
        name = (_,n);
        properties = ps;
      } -> (eval_table_decl ctrl env st n d ps)
    | Header {
        annotations = _;
        name = (_,n);
        fields = _;
      } -> (eval_header_decl env n d, st)
    | HeaderUnion {
        annotations = _;
        name = (_,n);
        fields = _;
      } -> (eval_union_decl env n d, st)
    | Struct {
        annotations = _;
        name = (_,n);
        fields = _;
      } -> (eval_struct_decl env n d, st)
    | Error {
        members = l;
      } -> (eval_error_decl env l, st)
    | MatchKind {
        members = _;
      } -> (eval_matchkind_decl env d, st)
    | Enum {
        annotations = _;
        name = (_,n);
        members = _;
      } -> (eval_enum_decl env n d, st)
    | SerializableEnum {
        annotations = _;
        typ = _;
        name = (_,n);
        members = _;
      } -> (eval_senum_decl env n d, st)
    | ExternObject {
        annotations = _;
        name = (_,n);
        type_params = tps;
        methods = ms;
      } -> (eval_extern_obj env n ms d, st)
    | TypeDef {
        annotations = _;
        name = (_,n);
        typ_or_decl = _;
      } -> (eval_type_def env n d, st)
    | NewType {
        annotations = _;
        name = (_,n);
        typ_or_decl = _;
      } -> (eval_type_decl env n d, st)
    | ControlType {
        annotations = _;
        name = (_,n);
        type_params = _;
        params = _;
      } -> (eval_ctrltyp_decl env n d, st)
    | ParserType {
        annotations = _;
        name = (_,n);
        type_params = _;
        params = _;
      } -> (eval_prsrtyp_decl env n d, st)
    | PackageType {
        annotations = _;
        name = (_,n);
        type_params = _;
        params = _;
      } -> (eval_pkgtyp_decl env n d, st)

  and eval_const_decl (ctrl : ctrl) (env : env) (st : state) (typ : Type.t) (e : Expression.t)
      (name : string) : env * state =
    let name_expr = (Info.dummy, Expression.Name(Info.dummy, name)) in
    let env' = EvalEnv.insert_typ name typ env in
    let (e,s,_) = eval_assign ctrl env' st SContinue name_expr e in (e,s)

  and eval_instantiation (ctrl : ctrl) (env : env) (st : state) (typ : Type.t)
      (args : Argument.t list) (name : string) : env * state =
    let (env',st',_,obj) = eval_nameless ctrl env st typ args in
    (EvalEnv.insert_val name obj env', st')

  and eval_parser_decl (env : env) (name : string)
      (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_control_decl (env : env) (name : string)
      (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_fun_decl (env : env) (name : string) (params : Parameter.t list)
      (body : Block.t) (decl : Declaration.t) : env =
    EvalEnv.insert_val name (VFun{params;body}) env
    |> EvalEnv.insert_decl name decl

  and eval_extern_fun (env : env) (name : string)
      (params : Parameter.t list) (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_var_decl (ctrl : ctrl) (env : env) (st : state) (typ : Type.t) (name : string)
      (init : Expression.t option) : env * state * signal =
    let name_expr = (Info.dummy, Expression.Name(Info.dummy, name)) in
    print_endline ("initializing variable " ^ name);
    let env' = EvalEnv.insert_typ name typ env in
    match init with
    | None ->
      let env'' =
        EvalEnv.insert_val name (init_val_of_typ ctrl env' st name typ) env' in
      (env'', st, SContinue)
    | Some e ->
      let (_, _, _, v) = eval_expr ctrl env st SContinue e in
      begin match v with
      | VBit {w;_} -> print_string "variable init width is: "; print_endline (Bigint.to_string w)
      | _ -> () end;
      eval_assign ctrl env' st SContinue name_expr e

  and eval_set_decl (ctrl : ctrl) (env : env) (st : state) (typ : Type.t) (name : string)
      (size : Expression.t) : env * state * signal =
    let env' = EvalEnv.insert_typ name typ env in
    let (env'', st', s, size') = eval_expr ctrl env' st SContinue size in
    let size'' = assert_rawint size' in
    match s with
    | SContinue ->
      let ms = snd ctrl in
      if Bigint.(Bigint.of_int (List.length ms) > size'')
      then failwith "too many elements inserted to value set"
      else
      let vset = VSet (SValueSet{size=size';members=ms;sets=[]}) in
      let env''' = EvalEnv.insert_val name vset env'' in
      (env''', st', s)
    | SReject _ -> (env, st', s)
    | _ -> failwith "value set declaration should not return or exit"

  and eval_action_decl (env : env) (name : string) (params : Parameter.t list)
      (body : Block.t) (decl : Declaration.t) : env  =
    EvalEnv.insert_val name (VAction{params; body}) env
    |> EvalEnv.insert_decl name decl

  and eval_table_decl (ctrl : ctrl) (env : env) (st : state) (name : string)
      (decl : Declaration.t) (props : Table.property list) : env * state =
    let props' = List.map props ~f:snd in
    let env' = EvalEnv.insert_decl name decl env in
    let ctrl_entries = fst ctrl in
    let pre_ks = List.filter props' ~f:is_key
                |> List.hd_exn
                |> assert_key
                |> List.map ~f:snd in
    let key = pre_ks |> List.map ~f:(fun k -> k.key) in
    let mks = pre_ks |> List.map ~f:(fun k -> snd k.match_kind) in
    let ((env'',st',s), ks) = List.fold_map key ~init:(env', st, SContinue)
        ~f:(fun (a, b, c) k ->

            let w,x,y,z = eval_expr ctrl a b c k in ((w,x,y),z)) in
    let f ((v,w,x,y),z) = ((v,w,x),(y,z)) in
    let sort_mks = check_lpm_count mks in
    let ws = List.map ks ~f:width_of_val in
    let ((env''',st'',s'),entries) =
      match List.filter props' ~f:is_entries with
      | [] -> List.fold_map ctrl_entries ~init:(env'',st',s)
                ~f:(fun (a,b,c) d -> (set_of_matches ctrl a b c d.matches ws, d.action) |> f)
      | l -> l
              |> List.hd_exn
              |> assert_entries
              |> List.map ~f:snd
              |> List.fold_map ~init:(env'',st',s)
                ~f:(fun (a,b,c) d -> (set_of_matches ctrl a b c d.matches ws, d.action) |> f) in
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
    (EvalEnv.insert_val name v env''', st')

  and eval_header_decl (env : env) (name : string)
      (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_union_decl (env : env) (name : string)
      (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_struct_decl (env : env) (name : string)
      (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_error_decl (env : env) (errs : P4String.t list) : env =
    env

  and eval_matchkind_decl (env : env) (d : Declaration.t) : env =
    env 
    (* mems
    |> List.map ~f:snd
    |> List.map ~f:(fun a -> (a, VMatchKind))
    |> (fun a -> EvalEnv.insert_vals a env) *)

  and eval_enum_decl (env : env) (name : string)
      (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_senum_decl (env : env) (name : string)
      (decl : Declaration.t) :env =
    EvalEnv.insert_decl name decl env

  and eval_extern_obj (env : env) (name : string)
      (methods : MethodPrototype.t list) (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_type_def (env : env) (name : string)
      (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_type_decl (env : env) (name : string)
      (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_ctrltyp_decl (env : env) (name : string)
      (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_prsrtyp_decl (env : env) (name : string)
      (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  and eval_pkgtyp_decl (env : env) (name : string)
      (decl : Declaration.t) : env =
    EvalEnv.insert_decl name decl env

  (* -------------------------------------------------------------------------- *)
  (* Table Declaration Evaluation *)
  (* -------------------------------------------------------------------------- *)

  and filter_lpm_prod (env : env) (mks : string list) (ks : value list)
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

  and init_val_of_typ (ctrl : ctrl) (env : env) (st : state) (name : string) (typ : Type.t) : value =
    match snd typ with
    | Bool                      -> VBool false
    | Error                     -> VError "NoError"
    | Integer                   -> VInteger Bigint.zero
    | IntType expr              -> init_val_of_int ctrl env st expr
    | BitType expr              -> init_val_of_bit ctrl env st expr
    | VarBit expr               -> init_val_of_varbit ctrl env st expr
    | TopLevelType (_,n)        -> init_val_of_typname ctrl env st n name true
    | TypeName (_,n)            -> init_val_of_typname ctrl env st n name false
    | SpecializedType _         -> failwith "specialized init unimplemented"
    | HeaderStack{header; size} -> init_val_of_stack ctrl env st name header size
    | Tuple l                   -> init_val_of_tuple ctrl env st typ l
    | String                    -> failwith "string init unimplemented"
    | Void                      -> VNull
    | DontCare                  -> VNull

  and init_val_of_int (ctrl : ctrl) (env : env) (st : state)
      (expr : Expression.t) : value =
    let (_,_,_,v) = eval_expr ctrl env st SContinue expr in
    match v with
    | VInteger v
    | VBit{v;_}
    | VInt{v;_} -> VInt{w=v;v=Bigint.zero}
    | _ -> failwith "int width is not an int"

  and init_val_of_bit (ctrl : ctrl) (env : env) (st : state)
      (expr : Expression.t) : value =
    match fourth4 (eval_expr ctrl env st SContinue expr) with
    | VInteger v
    | VBit{v;_}
    | VInt{v;_} -> VBit{w=v;v=Bigint.zero}
    | _ -> failwith "bit width is not an int"

  and init_val_of_varbit (ctrl : ctrl) (env : env) (st : state)
      (expr: Expression.t) : value =
    match fourth4 (eval_expr ctrl env st SContinue expr) with
    | VInteger v
    | VBit{v;_}
    | VInt{v;_} -> VVarbit{max=v; w=Bigint.zero; v=Bigint.zero}
    | _ -> failwith "varbit width is not an int"

  and init_val_of_typname (ctrl : ctrl) (env : env) (st : state) (tname : string) 
      (vname : string) (b : bool) : value =
    let f = EvalEnv.(if b then find_decl_toplevel else find_decl) in
    match snd (f tname env) with
    | Struct {fields=fs;_}      -> init_val_of_struct ctrl env st vname tname fs
    | Header {fields=fs;_}      -> init_val_of_header ctrl env st vname tname fs
    | HeaderUnion {fields=fs;_} -> init_val_of_union ctrl env st vname fs
    | _ -> failwith "decl init value unimplemented"

  and init_val_of_stack (ctrl : ctrl) (env: env) (st : state) (name : string)
      (hdr : Type.t) (size : Expression.t) : value =
    let size' = size 
                |> eval_expr ctrl env st SContinue 
                |> fourth4 
                |> bigint_of_val in
    let hdrs = size' |> Bigint.to_int_exn |> List.init ~f:string_of_int
              |> List.map ~f:(fun s -> init_val_of_typ ctrl env st s hdr) in
    VStack{name;headers=hdrs;size=size';next=Bigint.zero}

  and init_val_of_tuple (ctrl : ctrl) (env : env) (st : state)   (t : Type.t)
      (l : Type.t list) : value =
    VTuple (List.map l ~f:(init_val_of_typ ctrl env st ""))

  and init_val_of_struct (ctrl : ctrl) (env : env) (st : state)  (name : string)
      (tname : string) (fs : Declaration.field list) : value =
    VStruct {
      name = name;
      typ_name = tname;
      fields = List.map fs ~f:(init_binding_of_field ctrl env st)
    }

  and init_val_of_header (ctrl : ctrl) (env : env) (st : state)  (name : string)
      (tname : string) (fs : Declaration.field list) : value =
    VHeader {
      name = name; 
      typ_name = tname;
      fields = List.map fs ~f:(init_binding_of_field ctrl env st);
      is_valid = false;
    }

  and init_val_of_union (ctrl : ctrl) (env : env) (st : state)   (name : string)
      (fs : Declaration.field list) : value =
    let fs' = List.map fs ~f:(init_binding_of_field ctrl env st) in
    let bs = List.map fs' ~f:(fun (a,b) -> (a,false)) in
    let v = fs' |> List.hd_exn |> snd in
    VUnion {name; valid_header=v; valid_fields=bs}

  (*----------------------------------------------------------------------------*)
  (* Statement Evaluation *)
  (*----------------------------------------------------------------------------*)

  and eval_stmt (ctrl : ctrl) (env : env) (st : state) (sign : signal)
      (stm : Statement.t) : (env * state * signal) =
    match snd stm with
    | MethodCall{func;type_args=ts;args} -> eval_method_call ctrl env st sign func args ts
    | Assignment{lhs;rhs}                -> eval_assign ctrl env st sign lhs rhs
    | DirectApplication{typ;args}        -> eval_app' ctrl env st sign args typ
    | Conditional{cond;tru;fls}          -> eval_cond ctrl env st sign cond tru fls
    | BlockStatement{block}              -> eval_block ctrl env st sign block
    | Exit                               -> eval_exit env st sign
    | EmptyStatement                     -> (env, st, sign)
    | Return{expr}                       -> eval_return ctrl env st sign expr
    | Switch{expr;cases}                 -> eval_switch ctrl env st sign expr cases
    | DeclarationStatement{decl}         -> eval_decl_stm ctrl env st sign decl

  and eval_method_call (ctrl : ctrl) (env : env) (st : state) (sign : signal)
      (func : Expression.t) (args : Argument.t list)
      (ts : Type.t list) : env * state * signal =
    match sign with
    | SContinue -> let (e,s,i,_) = eval_funcall ctrl env st func args ts in (e,s,i)
    | SReject _
    | SReturn _
    | SExit     -> (env, st, sign)

  and eval_assign (ctrl : ctrl) (env : env) (st : state) (s : signal) (lhs : Expression.t)
      (rhs : Expression.t) : env * state * signal =
    match s with
    | SContinue ->
      let (env', st', s', v) = eval_expr ctrl env st SContinue rhs in
      let lv = lvalue_of_expr lhs in
      begin match s' with
        | SReject _ -> (env', st', s')
        | SContinue -> let (env, st'', s'') = eval_assign' ctrl env' st' lv v in (env, st'', s'')
        | _ -> failwith "unreachable" end
    | SReject _
    | SReturn _
    | SExit     -> (env, st, s)

  and eval_app (ctrl : ctrl) (env : env) (st : state) (s : signal) (v : value)
    (args : Argument.t list) : env * state * signal * value =
    match s with
    | SContinue ->
      begin match v with
        | VParser {pvs;pparams;plocals;states} ->
          let (env, s, st') = eval_parser ctrl env st pparams args pvs plocals states in
          (env,s, st', VNull)
        | VControl {cvs;cparams;clocals;apply} ->
          let (env,st,s) = eval_control ctrl env st cparams args cvs clocals apply in
          (env,st,s,VNull)
        | VTable {keys;const_entries;name;actions;default_action} ->
          eval_table ctrl env st keys const_entries name actions default_action
        | _ -> failwith "apply not implemented on type" end
    | SReject _
    | SReturn _
    | SExit -> (env, st, s, VNull)

  and eval_table (ctrl : ctrl) (env : env) (st : state) (key : value list)
      (entries : (set * Table.action_ref) list)
      (name : string) (actions : Table.action_ref list)
      (default : Table.action_ref) : env * state * signal * value =
    let l = List.filter entries ~f:(fun (s,a) -> values_match_set key s) in
    let action = match l with
                | [] -> default
                | _ -> List.hd_exn l |> snd in
    let action_name = Table.((snd action).name |> snd) in
    let actionv = EvalEnv.find_val action_name env in
    let args = Table.((snd action).args) in
    match actionv with
    | VAction{params;body}  ->
      let (env',st',s,_) = eval_funcall' ctrl env st params args body in
      let v = VStruct {name=""; typ_name="apply_result"; fields=[
                            ("hit", VBool (not (List.is_empty l)));
                            ("action_run", VEnumField{typ_name=name;enum_name=action_name})
                          ]} in
      (env',st',s,v)
    | _ -> failwith "table expects an action"

    (* TODO: double check about scoping - actions before tables? *)

  and eval_app' (ctrl : ctrl) (env : env) (st : state) (s : signal) (args : Argument.t list)
      (t : Type.t) : env * state * signal =
    let (env', st', sign', v) = eval_nameless ctrl env st t [] in
    let (env'', st'', sign'', _) = eval_app ctrl env' st' sign' v args in
    (env'', st'', sign'')

  and eval_cond (ctrl : ctrl) (env : env) (st : state) (sign : signal) (cond : Expression.t)
      (tru : Statement.t) (fls : Statement.t option) : env * state * signal =
    let eval_cond' env cond tru fls =
      let (env', st', s', v) = eval_expr ctrl env st SContinue cond in
      match s' with
      | SReject _ -> (env', st', s')
      | SContinue ->
        begin match v with
          | VBool true  -> eval_stmt ctrl env' st' SContinue tru
          | VBool false ->
            begin match fls with
              | None -> (env, st, SContinue)
              | Some fls' -> eval_stmt ctrl env' st' SContinue fls'  end
          | _ -> failwith "conditional guard must be a bool" end
      | _ -> failwith "unreachable" in
    match sign with
    | SContinue -> eval_cond' env cond tru fls
    | SReject _
    | SReturn _
    | SExit     -> (env, st, sign)

  and eval_block (ctrl : ctrl) (env : env) (st : state) (sign :signal) 
      (block : Block.t) : (env * state * signal) =
    let block = snd block in
    let f (env,st,sign) stm =
      match sign with
      | SContinue -> eval_stmt ctrl env st sign stm
      | SReject _
      | SReturn _
      | SExit     -> (env, st, sign) in
    List.fold_left block.statements ~init:(env,st,sign) ~f:f

  and eval_exit (env : env) (st : state) (sign : signal) : (env * state * signal) =
      match sign with 
      | SContinue -> (env, st, SExit)
      | SReturn v -> (env, st, SReturn v) 
      | SExit -> (env, st, SExit)
      | SReject _ -> failwith "reject and exit in the same block"

  and eval_return (ctrl : ctrl) (env : env) (st : state) (sign : signal)
      (expr : Expression.t option) : (env * state * signal) =
    let (env', st', s', v) =
      match expr with
      | None   -> (env, st, SContinue, VNull)
      | Some e -> eval_expr ctrl env st SContinue e in
    match sign with
    | SReject _
    | SReturn _
    | SExit -> (env,st,sign)
    | SContinue -> begin match s' with
        | SContinue -> (env', st', SReturn v)
        | SReject _ -> (env', st', s')
        | SReturn _
        | SExit     -> failwith "unreachable" end

  and eval_switch (ctrl : ctrl) (env : env) (st : state) (sign : signal) (expr : Expression.t)
      (cases : Statement.switch_case list) : env * state * signal = 
    let open Statement in 
    let (env',st',s',v) = eval_expr ctrl env st SContinue expr in 
    match sign with 
    | SReject _
    | SReturn _ 
    | SExit -> (env, st, sign)
    | SContinue -> begin match s' with 
      | SReject _ -> (env', st', s') 
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
        |> eval_block ctrl env' st' SContinue
      | _ -> failwith "unreachable" end

  and eval_decl_stm (ctrl : ctrl) (env : env) (st : state) (sign : signal)
      (decl : Declaration.t) : env * state * signal =
    match sign with
    | SReject _
    | SReturn _
    | SExit     -> (env, st, sign)
    | SContinue -> 
      let (env', st') = eval_decl ctrl env st decl in 
      (env', st', SContinue)

  (*----------------------------------------------------------------------------*)
  (* Asssignment Evaluation *)
  (*----------------------------------------------------------------------------*)

  and eval_assign' (ctrl : ctrl) (env : env) (st : state) (lhs : lvalue)
      (rhs : value) : env * state * signal =
    match lhs with
    | LName n -> 
      let (a,b) = assign_name ctrl env st n lhs rhs EvalEnv.insert_val in
      (a,b,SContinue)
    | LTopName n -> 
      let (a,b) = assign_name ctrl env st n lhs rhs EvalEnv.insert_val_toplevel in 
      (a,b,SContinue)
    | LMember{expr=lv;name=mname}     -> assign_member ctrl env st lv mname rhs
    | LBitAccess{expr=lv;msb=m;lsb=l} -> assign_bitaccess ctrl env st lv m l rhs
    | LArrayAccess{expr=lv;idx=e}     -> assign_arrayaccess ctrl env st lv e rhs

  and assign_name (ctrl : ctrl) (env : env) (st : state) (name : string) (lhs : lvalue)
      (rhs : value) (f : string -> value -> env -> env) : env * state =
    let t = EvalEnv.find_typ name env in
    match rhs with
    | VTuple l -> 
      (f name (implicit_cast_from_tuple ctrl env st lhs name rhs t) env, st)
    | VStruct{name=n;typ_name;fields} -> 
      (f name (VStruct{name=n;typ_name;fields}) env, st)
    | VHeader{name=n;typ_name;fields;is_valid} -> 
      (f name (VHeader{name=n;typ_name;fields;is_valid}) env, st)
    | VUnion{name=n;valid_header;valid_fields} -> 
      (f name (VUnion{name=n;valid_header;valid_fields}) env, st)
    | VStack{name=n;headers;size;next} -> 
      (f name (VStack{name=n;headers;size;next}) env, st)
    | VInteger n -> 
      (f name (implicit_cast_from_rawint ctrl env st rhs t) env, st)
    | _ -> (f name rhs env, st)

  and assign_member (ctrl : ctrl) (env : env) (st : state) (lv : lvalue) (mname : string)
      (rhs : value) : env * state * signal =
    let (s,v) = value_of_lvalue ctrl env st lv in
    match s with
    | SContinue ->
      begin match v with
        | VStruct{name=n;typ_name;fields=l} -> 
          assign_struct_mem ctrl env st lv rhs mname n typ_name l
        | VHeader{name=n;typ_name;fields=l;is_valid=b} -> 
          assign_header_mem ctrl env st lv rhs mname n typ_name l b
        | VUnion{name=n;valid_header=vs;valid_fields=bs} -> 
          assign_union_mem ctrl env st lv rhs mname n bs
        | VStack{name=n;headers=hdrs;size=s;next=i} ->
          assign_stack_mem ctrl env st lv rhs n mname hdrs s i
        | _ -> failwith "member access undefined" end
    | SReject _ -> (env, st, s)
    | _ -> failwith "unreachable"

  and assign_bitaccess (ctrl : ctrl) (env : env) (st : state) (lv : lvalue)
      (msb : Expression.t) (lsb : Expression.t)
      (rhs : value) : env * state * signal =
    let (env', st', s, msb') = eval_expr ctrl env st SContinue msb in
    let (env'', st'', s', lsb') = eval_expr ctrl env' st' SContinue lsb in
    match (s,s') with
    | SContinue, SContinue ->
      let lsb'' = bigint_of_val lsb' in
      let msb'' = bigint_of_val msb' in
      let w = Bigint.(msb'' - lsb'' + one) in
      print_string "during assign msb is: "; print_endline (Bigint.to_string msb'');
      print_string "during assign lsb is: "; print_endline (Bigint.to_string lsb'');
      print_string "during assign w is: "; print_endline (Bigint.to_string w);
      let (s,v) = value_of_lvalue ctrl env st lv in
      begin match s with
        | SContinue ->
          let n = bigint_of_val v in
          let nw = width_of_val v in 
          let rhs' = bit_of_rawint (bigint_of_val rhs) w |> bigint_of_val in
          let n0 = bitstring_slice n msb'' lsb'' in
          let diff = Bigint.(n0 - rhs') in
          let diff' = Bigint.(diff * (power_of_two lsb'')) in
          let final = Bigint.(n - diff') in
          eval_assign' ctrl env'' st'' lv (VBit{w=nw;v=final})
        | SReject _ -> (env'',st'',s)
        | _ -> failwith "unreachable" end
    | SReject _, _ -> (env',st',s)
    | _, SReject _ -> (env'',st'',s')
    | _ -> failwith "unreachable"

  and assign_arrayaccess (ctrl : ctrl) (env : env) (st : state) (lv : lvalue)
      (e : Expression.t) (rhs : value) : env * state * signal =
    let (s,v) = value_of_lvalue ctrl env st lv in
    let (env', st', s', i) = eval_expr ctrl env st SContinue e in
    let i' = bigint_of_val i in
    let t = match snd (typ_of_lvalue ctrl env st' lv) with
      | HeaderStack{header;_} -> header
      | _ -> failwith "not a stack" in
    let x = LArrayAccess{expr=lv;idx=e} in
    let rhs' = implicit_cast_from_tuple ctrl env st x (string_of_int (Bigint.to_int_exn i')) rhs t in
    match s,s' with
    | SContinue,SContinue ->
      begin match v with
        | VStack{name=n;headers=hdrs;size;next} ->
          let (hdrs1, hdrs2) = List.split_n hdrs Bigint.(to_int_exn i') in
          begin match hdrs2 with
            | _ :: t ->
              let hdrs' = hdrs1 @ (rhs' :: t) in
              let rhs'' = VStack{name=n;headers=hdrs';size;next} in
              eval_assign' ctrl env' st' lv rhs''
            | [] -> (env', st', SReject "StackOutOfBounds") end
        | _ -> failwith "array access is not a header stack" end
    | SReject _,_ -> (env, st, s)
    | _,SReject _ -> (env', st', s')
    | _ -> failwith "unreachable"


  and assign_struct_mem (ctrl : ctrl) (env : env) (st : state) (lhs : lvalue)
      (rhs : value) (fname : string) (sname : string) (tname : string)
      (l : (string * value) list) : env * state * signal =
    let t = typ_of_struct_field env (typ_of_lvalue ctrl env st lhs) fname in
    let rhs' = implicit_cast_from_rawint ctrl env st rhs t in
    let rhs'' = implicit_cast_from_tuple ctrl env st (LMember{expr=lhs;name=fname}) fname rhs' t in
    eval_assign' ctrl env st lhs (VStruct{name=sname;typ_name=tname;fields=(fname, rhs'') :: l})

  and assign_header_mem (ctrl : ctrl) (env : env) (st : state) (lhs : lvalue)
      (rhs : value) (fname : string) (hname : string) (tname : string) (l : (string * value) list)
      (b : bool) : env * state * signal =
    let t = typ_of_header_field env (typ_of_lvalue ctrl env st lhs) fname in
    let rhs' = implicit_cast_from_rawint ctrl env st rhs t in
    eval_assign' ctrl env st lhs (VHeader{name=hname;typ_name=tname;fields=(fname,rhs') :: l;is_valid=b})

  and assign_union_mem (ctrl : ctrl) (env : env) (st : state) (lhs : lvalue)
      (rhs : value) (fname : string) (uname : string)
      (vbs : (string * bool) list) : env * state * signal =
    let t = typ_of_union_field env (typ_of_lvalue ctrl env st lhs) fname in
    let rhs' = implicit_cast_from_tuple ctrl env st (LMember{expr=lhs;name=fname}) fname rhs t in
    let vbs' = List.map vbs ~f:(fun (s,_) -> (s, String.equal s fname)) in
    eval_assign' ctrl env st lhs (VUnion{name=uname; valid_header=rhs'; valid_fields=vbs'})

  and assign_stack_mem (ctrl : ctrl) (env : env) (st : state) (lhs : lvalue)
      (rhs : value) (sname : string) (mname : string) (hdrs : value list) 
      (size : Bigint.t) (next : Bigint.t) : env * state * signal =
    let () =
      match mname with
      | "next" -> ()
      | _ -> failwith "stack mem not an lvalue" in
    if Bigint.compare next size >= 0
    then (env, st, SReject "StackOutOfBounds")
    else
      let t = typ_of_stack_mem ctrl env st lhs in
      let rhs' = implicit_cast_from_tuple ctrl env st (LMember{expr=lhs;name=mname}) mname rhs t in
      let (hdrs1, hdrs2) = List.split_n hdrs Bigint.(to_int_exn next) in
      let hdrs' =
        match hdrs2 with
        | _ :: t -> hdrs1 @ (rhs' :: t)
        | [] -> failwith "header stack is empty" in
      eval_assign' ctrl env st lhs (VStack{name=sname;headers=hdrs';size;next})

  (*----------------------------------------------------------------------------*)
  (* Functions on L-Values*)
  (*----------------------------------------------------------------------------*)

  and lvalue_of_expr (expr : Expression.t) =
    match snd expr with
    | Name(_,n) -> LName n
    | TopLevel(_,n) -> LTopName n
    | ExpressionMember{expr=e; name=(_,n)} -> LMember{expr=lvalue_of_expr e;name=n}
    | BitStringAccess{bits;lo;hi} -> LBitAccess{expr=lvalue_of_expr bits;msb=hi;lsb=lo}
    | ArrayAccess{array;index} -> LArrayAccess{expr=lvalue_of_expr array;idx=index}
    | _ -> failwith "not an lvalue"

  and value_of_lvalue (ctrl : ctrl) (env : env) (st : state)
      (lv : lvalue) : signal * value =
    match lv with
    | LName n                           -> (SContinue, EvalEnv.find_val n env)
    | LTopName n                        -> (SContinue, EvalEnv.find_val_toplevel n env)
    | LMember{expr=lv;name=n}           -> value_of_lmember ctrl env st lv n
    | LBitAccess{expr=lv;msb=hi;lsb=lo} -> value_of_lbit ctrl env st lv hi lo
    | LArrayAccess{expr=lv;idx}         -> value_of_larray ctrl env st lv idx

  and value_of_lmember (ctrl : ctrl) (env : env) (st : state) (lv : lvalue)
      (n : string) : signal * value =
    let (s,v) = value_of_lvalue ctrl env st lv in
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

  and value_of_lbit (ctrl : ctrl) (env : env) (st : state) (lv : lvalue) (hi : Expression.t)
      (lo : Expression.t) : signal * value =
    let (_,_,_,m) = eval_expr ctrl env st SContinue hi in
    let (_,_,_,l) = eval_expr ctrl env st SContinue lo in
    let (s,n) = value_of_lvalue ctrl env st lv in
    let n' = bigint_of_val n in
    let m' = bigint_of_val m in
    let l' = bigint_of_val l in
    match s with
    | SContinue -> (s, VBit{w=Bigint.(m' - l' + one);v=bitstring_slice n' m' l'})
    | SReject _ -> (s, VNull)
    | _ -> failwith "unreachable"

  and value_of_larray (ctrl : ctrl) (env : env) (st : state) (lv : lvalue)
      (idx : Expression.t) : signal * value =
    let (s,v) =  value_of_lvalue ctrl env st lv in
    match s with
    | SContinue ->
      begin match v with
        | VStack{name=n;headers=vs;size=s;next=i} ->
          let idx' = eval_expr ctrl env st SContinue idx 
                    |> fourth4 
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

  and typ_of_lvalue (ctrl : ctrl) (env : env) (st : state) (lv : lvalue) : Type.t =
    match lv with
    | LName s                            -> EvalEnv.find_typ s env
    | LTopName s                         -> EvalEnv.find_typ_toplevel s env
    | LMember{expr=lv';name=s}           -> typ_of_lmember ctrl env st lv' s
    | LBitAccess{expr=lv';msb=e1;lsb=e2} -> typ_of_lbit ctrl env st lv' e1 e2
    | LArrayAccess{expr=lv';idx=e}       -> typ_of_larray ctrl env st lv' e

  and typ_of_lmember (ctrl : ctrl) (env : env) (st : state) (lv : lvalue)
      (s : string) : Type.t =
    let t = typ_of_lvalue ctrl env st lv in
    match snd t with
    | HeaderStack{header;_} -> typ_of_stack_lmem env st s header
    | TypeName(_,n) ->
      begin match snd (decl_of_typ env t) with
        | Header{fields=fs;_}      -> typ_of_struct_lmem env st s fs
        | HeaderUnion{fields=fs;_} -> typ_of_struct_lmem env st s fs
        | Struct{fields=fs;_}      -> typ_of_struct_lmem env st s fs
        | _ -> failwith "lvalue type name member access not defined" end
    | _ -> failwith "type of lvalue member unimplemented"

  and typ_of_struct_lmem (env : env) (st : state) (s : string)
      (fields : Declaration.field list) : Type.t =
    let fs = List.map fields ~f:(fun a -> (snd (snd a).name, a)) in
    let f = List.Assoc.find_exn fs ~equal:String.equal s in
    (snd f).typ

  and typ_of_stack_lmem (env : env) (st : state) (s : string) (t : Type.t) : Type.t =
    let () =
      match s with
      | "next" -> ()
      | _ -> failwith "stack member not a lvalue" in
    t

  and typ_of_lbit (ctrl : ctrl) (env : env) (st : state) (lv : lvalue) (e1 : Expression.t)
      (e2 : Expression.t) : Type.t =
    let (_,_,_,v1) = eval_expr ctrl env st SContinue e1 in
    let (_,_,_,v2) = eval_expr ctrl env st SContinue e2 in
    let n1 = bigint_of_val v1 in
    let n2 = bigint_of_val v2 in
    let n0 = Bigint.(n1 - n2 + one) in
    (Info.dummy, Type.BitType(Info.dummy, Expression.Int(Info.dummy,{value=n0;width_signed=None})))

  and typ_of_larray (ctrl : ctrl) (env : env) (st : state) (lv : lvalue) (e : Expression.t) : Type.t =
    let t = typ_of_lvalue ctrl env st lv in
    match snd t with
    | HeaderStack{header;_} -> header
    | _ -> failwith "array access on non-header stack"

  (*----------------------------------------------------------------------------*)
  (* Expression Evaluation *)
  (*----------------------------------------------------------------------------*)

  and eval_expr (ctrl : ctrl) (env : env) (st : state) (s : signal)
      (exp : Expression.t) : env * state * signal * value =
    match s with
    | SContinue ->
      begin match snd exp with
        | True                                 -> (env, st, s, VBool true)
        | False                                -> (env, st, s, VBool false)
        | Int(_,n)                             -> (env, st, s, eval_p4int n)
        | String (_,value)                     -> (env, st, s, VString value)
        | Name (_,name)                        -> eval_name ctrl env st s name exp
        | TopLevel (_,name)                    -> (env, st, s, EvalEnv.find_val_toplevel name env)
        | ArrayAccess{array=a; index=i}        -> eval_array_access ctrl env st a i
        | BitStringAccess({bits;lo;hi})        -> eval_bitstring_access ctrl env st bits hi lo
        | Record _                             -> failwith "TODO"
        | List{values}                         -> eval_list ctrl env st values
        | UnaryOp{op;arg}                      -> eval_unary ctrl env st op arg
        | BinaryOp{op; args=(l,r)}             -> eval_binop ctrl env st op l r
        | Cast{typ;expr}                       -> eval_cast ctrl env st typ expr
        | TypeMember{typ;name}                 -> eval_typ_mem ctrl env st typ (snd name)
        | ErrorMember t                        -> (env, st, s, VError (snd t))
        | ExpressionMember{expr;name}          -> eval_expr_mem ctrl env st expr name
        | Ternary{cond;tru;fls}                -> eval_ternary ctrl env st cond tru fls
        | FunctionCall{func;type_args=ts;args} -> eval_funcall ctrl env st func args ts
        | NamelessInstantiation{typ;args}      -> eval_nameless ctrl env st typ args
        | Mask{expr;mask}                      -> eval_mask ctrl env st expr mask
        | Range{lo;hi}                         -> eval_range ctrl env st lo hi end
    | SReject _ -> (env, st, s, VNull)
    | SReturn _ -> failwith "expression should not return"
    | SExit -> failwith "expresion should not exit"

  and eval_name (ctrl : ctrl) (env : env) (st : state) (s : signal) (name : string)
      (exp : Expression.t) : env * state * signal * value =
    if String.equal name "verify" then (env, st, s, VExternFun {name;caller = None})
    else (env, st, s, EvalEnv.find_val name env)

  and eval_p4int (n : P4Int.pre_t) : value =
    match n.width_signed with
    | None          -> VInteger n.value
    | Some(w,true)  -> VInt {w=Bigint.of_int w;v=n.value}
    | Some(w,false) -> VBit {w=Bigint.of_int w;v=n.value}

  and eval_array_access (ctrl : ctrl) (env : env) (st : state) (a : Expression.t)
      (i : Expression.t) : env * state * signal * value =
    let (env', st', s, a') = eval_expr ctrl env st SContinue a in
    let (env'', st'', s', i') = eval_expr ctrl env' st' SContinue i in
    let idx = bigint_of_val i' in
    let (name,hdrs,size,next) = assert_stack a' in
    let idx' = Bigint.(to_int_exn (idx % size)) in
    match (s,s') with
    | SContinue, SContinue -> (env'', st'', SContinue, List.nth_exn hdrs idx')
    | SReject _,_ -> (env',st',s, VNull)
    | _,SReject _ -> (env'',st'',s',VNull)
    | _ -> failwith "unreachable"

  and eval_bitstring_access (ctrl : ctrl) (env : env) (st : state) (b : Expression.t)
      (m : Expression.t) (l : Expression.t) : env * state * signal * value =
    let (env', st', s, m) = eval_expr ctrl env st SContinue m in
    let (env'', st'', s', l) = eval_expr ctrl env' st' SContinue l in
    let (env''', st''', s'', b) = eval_expr ctrl env'' st'' SContinue b in
    let m' = bigint_of_val m in
    let l' = bigint_of_val l in
    let b' = bigint_of_val b in
    let w = Bigint.(m'-l' + one) in
    let n = bitstring_slice b' m' l' in
    match (s,s',s'') with
    | SContinue, SContinue, SContinue -> (env''', st''', SContinue, VBit{w;v=n})
    | SReject _,_,_ -> (env',st',s,VNull)
    | _,SReject _,_ -> (env'', st'', s',VNull)
    | _,_,SReject _ -> (env''', st''', s'', VNull)
    | _ -> failwith "unreachable"

  and eval_list (ctrl : ctrl) (env : env) (st : state) 
      (values : Expression.t list) : env * state * signal * value =
    let f (a,b,c) d =
      let (w,x,y,z) = eval_expr ctrl a b c d in
      ((w,x,y),z) in
    values
    |> List.fold_map ~f:f ~init:(env,st,SContinue)
    |> (fun ((e,st,s),l) -> (e, st, s, VTuple l))

  and eval_unary (ctrl : ctrl) (env : env) (st : state) (op : Op.uni)
      (e : Expression.t) : env * state * signal * value =
    let (env', st', s, v) = eval_expr ctrl env st SContinue e in
    match s with
    | SContinue ->
      let (env,v) = match snd op with
        | Not    -> eval_not env' v
        | BitNot -> eval_bitnot env' v
        | UMinus -> eval_uminus env' v in
      (env,st', s,v)
    | SReject _ -> (env',st',s,VNull)
    | _ -> failwith "unreachable"

  and eval_binop (ctrl : ctrl) (env : env) (st : state) (op : Op.bin) (l : Expression.t)
      (r : Expression.t) : env * state * signal * value =
    let (env',st',s,l) = eval_expr ctrl env st SContinue l in
    let (env'',st'',s',r) = eval_expr ctrl env' st' SContinue r in
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
    | SContinue, SContinue -> (env'', st'', SContinue, v)
    | SReject _,_ -> (env',st',s,VNull)
    | _,SReject _ -> (env'',st'',s',VNull)
    | _ -> failwith "unreachable"

  and eval_cast (ctrl : ctrl) (env : env) (st : state) (typ : Type.t)
      (expr : Expression.t) : env * state * signal * value =
    let (env', st', s, v) = eval_expr ctrl env st SContinue expr in
    let (env'',st'', s',v') =
      match snd typ with
      | Bool -> (env', st',SContinue, bool_of_val v)
      | BitType e -> bit_of_val ctrl env' st e v
      | IntType e -> int_of_val ctrl env' st e v
      | TypeName (_,n) -> (env', st', s, v)
      | _ -> failwith "type cast unimplemented" in
    match (s,s') with
    | SContinue,SContinue -> (env'',st'',s,v')
    | SReject _,_ -> (env',st',s,VNull)
    | _,SReject _ -> (env'',st'',s',VNull)
    | _ -> failwith "unreachable"

  and eval_typ_mem (ctrl : ctrl) (env : env) (st : state) (typ : Type.t)
      (name : string) : env * state * signal * value =
    match snd (decl_of_typ env typ) with
    | Declaration.Enum {members=ms;name=(_,n);_} ->
      let mems = List.map ms ~f:snd in
      if List.mem mems name ~equal:String.equal
      then (env, st, SContinue, VEnumField{typ_name=n;enum_name=name})
      else raise (UnboundName name)
    | Declaration.SerializableEnum {members=ms;name=(_,n);typ;_ } ->
      let ms' = List.map ms ~f:(fun (a,b) -> (snd a, b)) in
      let expr = List.Assoc.find_exn ms' ~equal:String.equal name in
      let (env',st',s,v) = eval_expr ctrl env st SContinue expr in
      let v' = implicit_cast_from_rawint ctrl env' st v typ in
      begin match s with
        | SContinue -> (env',st',s,VSenumField{typ_name=n;enum_name=name;v=v'})
        | SReject _ -> (env',st',s,VNull)
        | _ -> failwith "unreachable" end
    | _ -> failwith "typ mem undefined"

  and eval_expr_mem (ctrl : ctrl) (env : env) (st : state) (expr : Expression.t)
      (name : P4String.t) : env * state * signal * value =
    let (env', st', s, v) = eval_expr ctrl env st SContinue expr in
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
        | VExternFun _
        | VPackage _                           -> failwith "expr member does not exist"
        | VStruct{fields=fs;_}                 -> eval_struct_mem env' st' (snd name) fs
        | VHeader{fields=fs;is_valid=vbit;_}   -> eval_header_mem env' st' (snd name) expr fs vbit
        | VUnion{valid_header=v;_}             -> (env', st', SContinue, v)
        | VStack{headers=hdrs;size=s;next=n;_} -> eval_stack_mem env' st' (snd name) expr hdrs s n
        | VRuntime {loc;typ_name}              -> eval_runtime_mem env' st' (snd name) expr loc typ_name
        | VParser _
        | VControl _                           -> (env', st', s, VBuiltinFun{name=snd name;caller=lvalue_of_expr expr})
        | VTable _                             -> (env', st', s, VBuiltinFun{name=snd name;caller=lvalue_of_expr expr}) end
    | SReject _ -> (env',st',s,VNull)
    | _ -> failwith "unreachable"

  and eval_ternary (ctrl : ctrl) (env : env) (st : state) (c : Expression.t)
      (te : Expression.t) (fe : Expression.t) : env * state * signal * value =
    let (env', st', s, c') = eval_expr ctrl env st SContinue c in
    match c' with
    | VBool(true)  -> (eval_expr ctrl env' st' s te)
    | VBool(false) -> (eval_expr ctrl env' st' s fe)
    | _ -> failwith "ternary guard must be a bool"

  and eval_funcall (ctrl : ctrl) (env : env) (st : state) (func : Expression.t)
      (args : Argument.t list) (ts : Type.t list) : env * state * signal * value =
    let (env', st', s, cl) = eval_expr ctrl env st SContinue func in
    match s with
    | SContinue ->
      begin match cl with
        | VAction{params; body}
        | VFun{params; body}            -> eval_funcall' ctrl env' st' params args body
        | VBuiltinFun{name=n;caller=lv} -> eval_builtin ctrl env' st' n lv args ts
        | VExternFun{name=n;caller=v}   -> eval_extern_call ctrl env' st' n v args ts
        | _ -> failwith "unreachable" end
    | SReject _ -> (env',st',s,VNull)
    | _ -> failwith "unreachable"

  and eval_nameless (ctrl : ctrl) (env : env) (st : state) (typ : Type.t)
      (args : Argument.t list) : env * state * signal * value =
    let (info ,decl) = decl_of_typ env typ in
    let (env',st',s,v) = match decl with
      | Control typ_decl ->
        let (env',st',s) = copyin ctrl env st typ_decl.constructor_params args in
        let state = env' |> EvalEnv.get_val_firstlevel |> List.rev in
        let v' = VControl { cvs = state;
                            cparams = typ_decl.params;
                            clocals = typ_decl.locals;
                            apply = typ_decl.apply; } in
        (EvalEnv.pop_scope env',st',s,v')
      | Parser typ_decl ->
        let (env',st',s) = copyin ctrl env st typ_decl.constructor_params args in
        let state = env' |> EvalEnv.get_val_firstlevel |> List.rev in
        let v' = VParser { pvs = state;
                          pparams = typ_decl.params;
                          plocals = typ_decl.locals;
                          states = typ_decl.states; } in
        (EvalEnv.pop_scope env',st',s,v')
      | PackageType pack_decl ->
        let (env',st',s) = copyin ctrl env st pack_decl.params args in
        let state = env' |> EvalEnv.get_val_firstlevel |> List.rev in
        (EvalEnv.pop_scope env', st', s, VPackage{decl=(info, decl);args=state})
      | _ -> failwith "instantiation unimplemented" in
    match s with
    | SContinue -> (env',st',s,v)
    | SReject _ -> (env,st',s,VNull)
    | _ -> failwith "nameless should not return or exit"

  and eval_mask (ctrl : ctrl) (env : env) (st : state) (e : Expression.t)
      (m : Expression.t) : env * state * signal * value =
    let (env', st', s, v1)  = eval_expr ctrl env st SContinue e in
    let (env'', st'', s', v2) = eval_expr ctrl env' st SContinue m in
    match (s,s') with
    | SContinue, SContinue -> (env'', st'', s, VSet(SMask{v=v1;mask=v2}))
    | SReject _,_ -> (env',st',s,VNull)
    | _,SReject _ -> (env'',st'',s',VNull)
    | _ -> failwith "unreachable"

  and eval_range (ctrl : ctrl) (env : env) (st : state) (lo : Expression.t)
      (hi : Expression.t) : env * state * signal * value =
    let (env', st',s, v1)  = eval_expr ctrl env st SContinue lo in
    let (env'', st'',s', v2) = eval_expr ctrl env' st SContinue hi in
    match (s,s') with
    | SContinue, SContinue -> (env'', st'', s, VSet(SRange{lo=v1;hi=v2}))
    | SReject _,_ -> (env',st',s,VNull)
    | _,SReject _ -> (env'',st'',s',VNull)
    | _ -> failwith "unreachable"

  (*----------------------------------------------------------------------------*)
  (* Unary Operator Evaluation *)
  (*----------------------------------------------------------------------------*)

  and eval_not (env : env) (v : value) : env * value =
    match v with
    | VBool b -> (env, VBool (not b))
    | _ -> failwith "not operator can only be applied to bools"

  and eval_bitnot (env : env) (v : value) : env * value =
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

  and eval_uminus (env : env) (v : value) : env * value =
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

  and bit_of_val (ctrl : ctrl) (env : env) (st : state) (e : Expression.t)
      (v : value) : env * state * signal * value =
    let (env', st', s, x) = eval_expr ctrl env st SContinue e in
    let w = bigint_of_val x in
    let v' = match v with
      | VInt{v=n;_}
      | VBit{v=n;_}
      | VInteger n -> bit_of_rawint n w
      | _ -> failwith "cast to bitstring undefined" in
    match s with
    | SContinue -> (env', st', s,v')
    | SReject _ -> (env', st', s,VNull)
    | _ -> failwith "unreachable"

  and int_of_val (ctrl : ctrl) (env : env) (st : state) (e : Expression.t)
      (v : value) : env * state * signal * value =
    let (env', st', s, x) = eval_expr ctrl env st SContinue e in
    let w = bigint_of_val x in
    let v' = match v with
      | VBit{v=n;_}
      | VInt{v=n;_}
      | VInteger n -> int_of_rawint n w
      | _ -> failwith "cast to bitstring undefined" in
    match s with
    | SContinue -> (env', st', s,v')
    | SReject _ -> (env', st', s,VNull)
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

  and eval_struct_mem (env : env) (st : state) (name : string)
      (fs : (string * value) list) : env * state * signal * value =
    (env, st, SContinue, List.Assoc.find_exn fs name ~equal:String.equal)

  and eval_header_mem (env : env) (st : state) (fname : string) (e : Expression.t)
      (fs : (string * value) list) (valid : bool) : env * state * signal * value =
    match fname with
    | "isValid"
    | "setValid"
    | "setInvalid" -> (env, st, SContinue, VBuiltinFun{name=fname;caller=lvalue_of_expr e})
    | _            -> (env, st, SContinue, List.Assoc.find_exn fs fname ~equal:String.equal)

  and eval_stack_mem (env : env) (st : state) (fname : string) (e : Expression.t)
      (hdrs : value list) (size : Bigint.t)
      (next : Bigint.t) : env * state * signal * value =
    match fname with
    | "size"       -> eval_stack_size env st size
    | "next"       -> eval_stack_next env st hdrs size next
    | "last"       -> eval_stack_last env st hdrs size next
    | "lastIndex"  -> eval_stack_lastindex env st next
    | "pop_front"
    | "push_front" -> eval_stack_builtin env st fname e
    | _ -> failwith "stack member unimplemented"

  and eval_runtime_mem (env : env) (st : state) (mname : string) (expr : Expression.t)
      (loc : int) (typ_name : string) : env * state * signal * value =
    env, st, SContinue, VExternFun {caller = Some (loc, typ_name); name = mname }

  and eval_stack_size (env : env) (st : state) 
      (size : Bigint.t) : env * state * signal * value =
    let five = Bigint.(one + one + one + one + one) in
    let thirty_two = shift_bigint_left Bigint.one five in
    (env, st, SContinue, VBit{w=thirty_two;v=size})

  and eval_stack_next (env : env) (st : state) (hdrs : value list) (size : Bigint.t)
      (next : Bigint.t) : env * state * signal * value =
    let (env', st', s, hdr) =
      if Bigint.(next >= size)
      then (env, st, SReject "StackOutOfBounds", VNull)
      else (env, st, SContinue, List.nth_exn hdrs Bigint.(to_int_exn next)) in
    (env', st', s, hdr)

  and eval_stack_last (env : env) (st : state) (hdrs : value list) (size : Bigint.t)
      (next : Bigint.t) : env * state * signal *  value =
    let (env', st', s, hdr) =
      if Bigint.(next < one) || Bigint.(next > size)
      then (env, st, SReject "StackOutOfBounds", VNull)
      else (env, st, SContinue, List.nth_exn hdrs Bigint.(to_int_exn next)) in
    (env', st', s, hdr)

  and eval_stack_lastindex (env : env) (st : state) 
      (next : Bigint.t) : env * state * signal * value =
    let five = Bigint.(one + one + one + one + one) in
    let thirty_two = shift_bigint_left Bigint.one five in
    (env, st, SContinue, VBit{w=thirty_two;v=Bigint.(next - one)})

  and eval_stack_builtin (env : env) (st : state) (fname : string)
      (e : Expression.t) : env * state * signal * value =
    (env, st, SContinue, VBuiltinFun{name=fname;caller=lvalue_of_expr e})

  (*----------------------------------------------------------------------------*)
  (* Function and Method Call Evaluation *)
  (*----------------------------------------------------------------------------*)

  and eval_extern_call (ctrl : ctrl) (env : env) (st : state) (name : string)
      (v : (loc * string) option) (args : Argument.t list)
      (ts : Type.t list) : env * state * signal * value =
    print_endline "got to emit";
    let params = 
      match v with 
      | Some (_, t) -> 
        EvalEnv.find_decl t env
        |> assert_extern_obj
        |> List.map ~f:params_of_prototype
        |> List.map ~f:(fun ((_, n), ps) -> (n,ps))
        |> fun x -> List.Assoc.find_exn x name ~equal:String.equal
      | None -> EvalEnv.find_decl name env |> assert_extern_function in
    let (fenv, st', signal) = copyin ctrl env st params args in
    let env' = EvalEnv.pop_scope fenv in
    match signal with
    | SExit -> env', st', SExit, VNull
    | SReject s -> env', st', SReject s, VNull
    | SReturn _ | SContinue -> 
    let vs = EvalEnv.get_val_firstlevel fenv |> List.map ~f:snd in
    let vs' = match v with
      | Some (loc, t) -> VRuntime {loc = loc; typ_name = t} :: vs
      | None -> vs in
    let vs' = match vs' with
      | _ :: VNull :: [] -> []
      | _ -> vs' in
    let (fenv', st'', s, v) = T.eval_extern eval_assign' ctrl fenv st' ts vs' name in
    let env'' = copyout ctrl fenv' st params args in
    env'', st'', s, v

  and assert_extern_obj (d : Declaration.t) : MethodPrototype.t list =
    match snd d with 
    | ExternObject x -> x.methods
    | _ -> failwith "expected extern object"

  and params_of_prototype (p : MethodPrototype.t) : P4String.t * Parameter.t list =
    match snd p with
    | AbstractMethod x -> (x.name, x.params)
    | Method x -> (x.name, x.params)
    | Constructor x -> (x.name, x.params)
    (* | _ -> failwith "expected abstract method" *)

  and assert_extern_function (d : Declaration.t) : Parameter.t list =
    match snd d with
    | ExternFunction x -> x.params
    | _ -> failwith "expected extern function"

  and eval_funcall' (ctrl : ctrl) (env : env) (st : state) (params : Parameter.t list)
      (args : Argument.t list) (body : Block.t) : env * state * signal * value =
    let (fenv, st', s) = copyin ctrl env st params args in
    let (fenv', st'', sign) = eval_block ctrl fenv st SContinue body in
    let final_env = copyout ctrl fenv' st'' params args in
    match sign with
    | SReturn v -> 
      begin match v with 
      | VBit {w;_} -> print_string "on return width is: " ; print_endline (Bigint.to_string w)
      | _ -> () end; (final_env, st'', SContinue, v)
    | SReject _
    | SContinue
    | SExit     -> (final_env, st'', sign, VNull)

  and copyin (ctrl : ctrl) (env : env) (st : state) (params : Parameter.t list)
      (args : Argument.t list) : env * state * signal =
    let fenv = EvalEnv.push_scope env in
    let ((fenv',st',s),arg_vals) = 
      List.fold_mapi args ~f:(eval_nth_arg ctrl st params) ~init:(fenv,st,SContinue) in
    let fenv' = List.fold2_exn params arg_vals ~init:fenv' ~f:insert_arg in
    match s with
    | SContinue -> (fenv',st',s)
    | SReject _ -> (fenv',st',s)
    | _ -> failwith " unreachable"

  and copyout (ctrl : ctrl) (fenv : env) (st : state) (params : Parameter.t list)
      (args : Argument.t list) : env =
    let env = EvalEnv.pop_scope fenv in
    List.fold2_exn params args ~init:env ~f:(copy_arg_out ctrl fenv st)
    
  and eval_nth_arg (ctrl : ctrl) (st : state) (params : Parameter.t list)  (i : int) 
      ((env,st,sign) : env * state * signal)
      (e : Argument.t) : (env * state * signal) * (string * value) =
    let open Parameter in 
    let open Argument in
    let p = snd (List.nth_exn params i) in
    let ((env',st',s,v), n) = match snd e with
      | Expression {value=expr} ->
        (eval_expr ctrl env st SContinue expr, snd p.variable)
      | KeyValue {value=expr;key=(_,n)} ->
        (eval_expr ctrl env st SContinue expr, n)
      | Missing ->
        match p.opt_value with
        | Some v -> (eval_expr ctrl env st SContinue v, snd p.variable)
        | None -> (env, st, SContinue, VNull), snd p.variable in
    match (sign,s) with
    | SContinue,SContinue -> ((env',st',s), (n,v))
    | SReject _, _ -> ((env,st,sign),(n,VNull))
    | _, SReject _ -> ((env',st',s),(n,VNull))
    | _ -> failwith "unreachable"
    
  and insert_arg (e : env) (p : Parameter.t) ((name,v) : string * value) : env =
    let v' = match v with
      | VHeader{fields=l;typ_name;is_valid=b;_} -> VHeader{name;typ_name;fields=l;is_valid=b}
      | VStruct{fields=l;typ_name;_}            -> VStruct{name;typ_name;fields=l}
      | _ -> v in
    let var = snd (snd p).variable in
    let f = EvalEnv.insert_val_firstlevel in
    let g = EvalEnv.insert_typ_firstlevel in
    match (snd p).direction with
    | None -> e |> f var v' |> g var (snd p).typ
    | Some x -> 
      begin match snd x with
        | InOut
        | In -> e |> f var v' |> g var (snd p).typ
        | Out -> e end

  and copy_arg_out (ctrl : ctrl) (fenv : env) (st : state) (e : env) (p : Parameter.t)
      (a : Argument.t) : env =
    match (snd p).direction with
    | None ->
      begin match snd (snd p).typ with 
        | TypeName(_,n) 
        | TopLevelType(_,n) -> 
          if is_extern_object (EvalEnv.find_decl_toplevel n e)
          then copy_arg_out_h ctrl fenv st e p a
          else e
        | _ -> e end
    | Some x -> 
      begin match snd x with
        | InOut
        | Out -> copy_arg_out_h ctrl fenv st e p a
        | In -> e end

  and copy_arg_out_h (ctrl : ctrl) (fenv : env) (st : state) (e : env) (p : Parameter.t)
      (a : Argument.t) : env = 
    let open Argument in 
    let v = EvalEnv.find_val (snd (snd p).variable) fenv in
    begin match snd a with
      | Expression {value=expr}
      | KeyValue {value=expr;_} -> 
        let (e,_,_) = (eval_assign' ctrl e st (lvalue_of_expr expr) v) in e
      | Missing -> e end

  (*----------------------------------------------------------------------------*)
  (* Built-in Function Evaluation *)
  (*----------------------------------------------------------------------------*)

  and eval_builtin (ctrl : ctrl) (env : env) (st : state) (name : string) (lv : lvalue)
      (args : Argument.t list) (ts : Type.t list) : env * state * signal * value =
    match name with
    | "isValid"    -> eval_isvalid ctrl env st lv
    | "setValid"   -> eval_setbool ctrl env st lv true
    | "setInvalid" -> eval_setbool ctrl env st lv false
    | "pop_front"  -> eval_popfront ctrl env st lv args
    | "push_front" -> eval_pushfront ctrl env st lv args
    | "apply"      -> let (s,v) = value_of_lvalue ctrl env st lv in 
                      eval_app ctrl env st s v args
    | _ -> failwith "builtin unimplemented"

  and eval_isvalid (ctrl : ctrl) (env : env) (st : state) 
      (lv : lvalue) : env * state * signal * value =
    let (s,v) = value_of_lvalue ctrl env st lv in
    match s with
    | SContinue ->
      begin match lv with
        | LName _
        | LTopName _
        | LBitAccess _
        | LArrayAccess _ ->
          begin match v with
            | VHeader{is_valid=b;_} -> (env, st, s, VBool b)
            | _ -> failwith "isvalid call is not a header" end
        | LMember{expr=lv';name=n} ->
          let (s',v') = value_of_lvalue ctrl env st lv' in
          begin match s' with
            | SContinue ->
              begin match v' with
                | VUnion{valid_fields=l;_} ->
                  (env, st, s', VBool (List.Assoc.find_exn l n ~equal:String.equal))
                | _ ->
                  begin match v with
                    | VHeader{is_valid=b;_} -> (env, st, s', VBool b)
                    | _ -> failwith "isvalid call is not a header" end end
            | SReject _ -> (env, st, s', VNull)
            | _ -> failwith "unreachable" end end
    | SReject _ -> (env, st, s, VNull)
    | _ -> failwith "unreachable"

  and eval_setbool (ctrl : ctrl) (env : env) (st : state) (lv : lvalue)
      (b : bool) : env * state * signal * value =
    match lv with
    | LName n ->
      begin match EvalEnv.find_val n env with
        | VHeader{name=n';typ_name;fields=fs;_} ->
          let (env', st', _) = eval_assign' ctrl env st lv (VHeader{name=n';typ_name;fields=fs;is_valid=b}) in
          (env', st', SContinue, VNull)
        | _ -> failwith "not a header" end
    | LTopName n ->
      begin match EvalEnv.find_val_toplevel n env with
        | VHeader{name=n';typ_name;fields=fs;_} ->
          let (env', st', _) = eval_assign' ctrl env st lv (VHeader{name=n';typ_name;fields=fs;is_valid=b}) in
          (env', st, SContinue, VNull)
        | _ -> failwith "not a header" end
    | LMember{expr=lv';name=n2} ->
      let (s,v') = value_of_lvalue ctrl env st lv' in
      begin match s with
        | SContinue ->
          begin match v' with
            | VUnion{name=n1;valid_header=fs;valid_fields=vs} ->
              let vs' = List.map vs ~f:(fun (a,_) -> (a,if b then String.equal a n2 else b)) in
              let u = VUnion{name=n1;valid_header=fs;valid_fields=vs'} in
              let (env',st',_) = eval_assign' ctrl env st lv' u in
              (env', st', SContinue, VNull)
            | VStruct{name=n1;typ_name;fields=fs} -> failwith "unimplemented"
            | _ -> failwith "not a union" end
        | SReject _ -> (env, st, s, VNull)
        | _ -> failwith "unreachable" end
    | LArrayAccess{expr=lv';idx=e} ->
      let (s,v') = value_of_lvalue ctrl env st lv' in
      begin match s with
        | SContinue ->
          begin match v' with
            | VStack{name=n1;headers=hdrs;size;next} ->
              let (env', st', s, i) = eval_expr ctrl env st SContinue e in
              let i' = bigint_of_val i in
              let (hdrs1, hdrs2) = List.split_n hdrs (Bigint.to_int_exn i') in
              let hdrs' = match hdrs2 with
                | VHeader{name=n2;typ_name;fields=vs;_} :: t -> 
                  hdrs1 @ (VHeader{name=n2;typ_name;fields=vs;is_valid=b} :: t)
                | _ -> failwith "not a header" in
              begin match s with
                | SContinue ->
                  let s = VStack{name=n1;headers=hdrs';size;next} in
                  let (env'', st'',_) = eval_assign' ctrl env' st' lv' s in
                  (env'', st'', SContinue, VNull)
                | SReject _ -> (env', st', s, VNull)
                | _ -> failwith "unreachable" end
            | _ -> failwith "not a stack" end
        | SReject _ -> (env, st, s , VNull)
        | _ -> failwith "unreachable" end
    | LBitAccess _ -> failwith "not a header"

  and eval_popfront (ctrl : ctrl) (env : env) (st : state) (lv : lvalue)
      (args : Argument.t list) : env * state * signal * value =
    eval_push_pop ctrl env st lv args false

  and eval_pushfront (ctrl : ctrl) (env : env) (st : state) (lv : lvalue)
      (args : Argument.t list) : env * state * signal * value =
    eval_push_pop ctrl env st lv args true

  and eval_push_pop (ctrl : ctrl) (env : env) (st : state) (lv : lvalue)
      (args : Argument.t list) (b : bool) : env * state * signal * value =
    let (env', st', s, a) = eval_push_pop_args ctrl env st args in
    let (s',v) = value_of_lvalue ctrl env st lv in
    let (n, hdrs, size, next) =
      match v with
      | VStack{name=n;headers=hdrs;size;next} -> (n,hdrs,size,next)
      | _ -> failwith "push call not a header stack" in
    let x = if b then Bigint.(size - a) else a in
    let (hdrs1, hdrs2) = List.split_n hdrs Bigint.(to_int_exn x) in
    let t = typ_of_stack_mem ctrl env st lv in
    let hdrs0 = List.init (Bigint.to_int_exn a) ~f:(fun x -> init_val_of_typ ctrl env st (string_of_int x) t) in
    let hdrs' = if b then hdrs0 @ hdrs1 else hdrs2 @ hdrs0 in
    let y = if b then Bigint.(next + a) else Bigint.(next-a) in
    let v = VStack{name=n;headers=hdrs';size;next=y} in
    match s,s' with
    | SContinue, SContinue -> 
      let (e,st,_) = eval_assign' ctrl env st' lv v in (e,st, s, VNull)
    | SReject _, _ -> (env',st',s,VNull)
    | _, SReject _ -> (env',st',s',VNull)
    | _ -> failwith "unreachble"

  and eval_push_pop_args (ctrl : ctrl) (env : env) (st : state) 
      (args : Argument.t list) : env * state * signal * Bigint.t =
    let args' = List.map args ~f:snd in
    match args' with
    | [Argument.Expression{value}]
    | [Argument.KeyValue{value=value;_}] ->
      let (env', st', s, v) = eval_expr ctrl env st SContinue value in
      begin match s with
        | SContinue -> (env', st', s, bigint_of_val v)
        | SReject _ -> (env', st', s, Bigint.zero)
        | _ -> failwith "unreachable" end
    | _ -> failwith "invalid push or pop args"

  and width_of_typ (ctrl : ctrl) (env : env) (st : state) (t : Type.t) : Bigint.t =
    match snd t with
    | Bool -> Bigint.one
    | IntType e -> e |> eval_expr ctrl env st SContinue |> fourth4 |> bigint_of_val
    | BitType e -> e |> eval_expr ctrl env st SContinue |> fourth4 |> bigint_of_val
    | TopLevelType _
    | TypeName _ -> width_of_decl ctrl env st (decl_of_typ env t)
    | HeaderStack{header=t';size=e} -> width_of_stack ctrl env st t' e
    | Tuple l -> width_of_tuple ctrl env st l
    | Void | DontCare -> Bigint.zero
    | Error | VarBit _ | Integer | String -> failwith "type does not a have a fixed width"
    | SpecializedType _ -> failwith "unimplemented"

  and width_of_tuple (ctrl : ctrl) (env : env) (st : state)
      (l : Type.t list) : Bigint.t =
    let l' = List.map l ~f:(width_of_typ ctrl env st) in
    List.fold_left l' ~init:Bigint.zero ~f:Bigint.(+)

  and width_of_stack (ctrl : ctrl) (env : env) (st : state) (t : Type.t)
      (e : Expression.t) : Bigint.t =
    Bigint.(
      e
      |> eval_expr ctrl env st SContinue
      |> fourth4
      |> bigint_of_val
      |> ( * ) (width_of_typ ctrl env st t))

  and width_of_hdr (ctrl : ctrl) (env : env) (st : state) 
      (fs : Declaration.field list) : Bigint.t =
    let ts = List.map fs ~f:(fun f -> (snd f).typ) in
    let ws = List.map ts ~f:(width_of_typ ctrl env st) in
    List.fold_left ws ~init:Bigint.zero ~f:Bigint.(+)

  and width_of_decl (ctrl : ctrl) (env : env) (st : state) 
      (d : Declaration.t) : Bigint.t =
    match snd d with
    | Header{fields;_} -> width_of_hdr ctrl env st fields
    | Struct{fields;_} -> width_of_hdr ctrl env st fields
    | SerializableEnum{typ;_} -> width_of_typ ctrl env st typ
    | TypeDef{typ_or_decl;_}
    | NewType{typ_or_decl;_} ->
      begin match typ_or_decl with
        | Left t -> width_of_typ ctrl env st t
        | Right d -> width_of_decl ctrl env st d end
    | _ -> failwith "decl does not have a fixed width"

  and width_of_val (v : value) : Bigint.t =
    match v with
    | VBit {w;v} | VInt {w;v} -> w
    | VInteger _ -> failwith "width of VInteger"
    | _ -> failwith "unimplemented"

  (*----------------------------------------------------------------------------*)
  (* Parser Evaluation *)
  (*----------------------------------------------------------------------------*)

  and eval_parser (ctrl : ctrl) (env : env) (st : state) (params : Parameter.t list)
      (args : Argument.t list) (vs : (string * value) list)
      (locals : Declaration.t list) (states : Parser.state list) : env * state * signal =
    let (penv, st', s) = copyin ctrl env st params args in
    match s with
    | SContinue ->
      let f a (x,y) = EvalEnv.insert_val x y a in
      let penv' = List.fold_left vs ~init:penv ~f:f in
      let (penv'', st'') = List.fold_left locals ~init:(penv',st') ~f:(fun (e,s) -> eval_decl ctrl e s) in
      let states' = List.map states ~f:(fun s -> snd (snd s).name, s) in
      let start = List.Assoc.find_exn states' "start" ~equal:String.equal in
      let (penv''', st''', final_state) = eval_state_machine ctrl penv'' st'' states' start in
      (copyout ctrl penv''' st''' params args, st''', final_state)
    | SReject _ -> (EvalEnv.pop_scope penv, st, s)
    | _ -> failwith "unreachable"

  and eval_state_machine (ctrl : ctrl) (env : env) (st : state)
      (states : (string * Parser.state) list)
      (state : Parser.state) : env * state * signal =
    let (stms, transition) =
      match snd state with
      | {statements=stms; transition=t;_} -> (stms, t) in
    let stms' = (Info.dummy, Statement.BlockStatement
                  {block = (Info.dummy, {annotations = []; statements = stms})}) in
    let (env', st', sign) = eval_stmt ctrl env st SContinue stms' in
    match sign with
    | SContinue -> eval_transition ctrl env' st' states transition
    | SReject _ -> (env', st', sign)
    | SReturn _ -> failwith "return statements not permitted in parsers"
    | SExit -> failwith "exit statements not permitted in parsers"

  and eval_transition (ctrl : ctrl) (env : env) (st : state) 
      (states : (string * Parser.state) list)
      (transition : Parser.transition) : env * state * signal =
    match snd transition with
    | Direct{next = (_, next)} -> eval_direct ctrl env st states next
    | Select{exprs;cases} -> eval_select ctrl env st states exprs cases

  and eval_direct (ctrl : ctrl) (env : env) (st : state)
      (states : (string * Parser.state) list) 
      (next : string) : env * state * signal =
    match next with
    | "accept" -> (env, st, SContinue)
    | "reject" -> (env, st, SReject "NoError")
    | _ -> let state = List.Assoc.find_exn states next ~equal:String.equal in
          eval_state_machine ctrl env st states state

  and eval_select (ctrl : ctrl) (env : env) (st : state)
      (states : (string * Parser.state) list) (exprs : Expression.t list)
      (cases : Parser.case list) : env * state * signal =
    let f (env,st,s) e =
      let (a,b,c,d) = eval_expr ctrl env st s e in
      ((a,b,c),d) in
    let ((env', st', s), vs) = List.fold_map exprs ~init:(env,st,SContinue) ~f:f in
    let ws = List.map vs ~f:width_of_val in
    match s with
    | SContinue ->
      let g (e,st,s) set =
        let (w,x,y,z) = set_of_case ctrl e st s set ws in
        ((w,x,y),(z,w,x)) in
      let ((env'',st'', s), ss) = List.fold_map cases ~init:(env', st', SContinue) ~f:g in
      let coerce_value_set s =
        match s with
        | SValueSet {size=si;members=ms;_},e,st ->
          let h (a,b,c) d =
            let (w,x,y,z) = set_of_matches ctrl a b c d ws in
            ((w,x,y),z) in
          let ((e',st',_),ss) = List.fold_map ms ~init:(e,st,SContinue) ~f:h in
          (SValueSet {size=si;members=ms;sets=ss},e',st')
        | x -> x in
      let ss' = List.map ss ~f:coerce_value_set in
      let ms = List.map ss' ~f:(fun (x,y,z) -> (values_match_set vs x, y,z)) in
      let ms' = List.zip_exn ms cases
                |> List.map ~f:(fun ((b,env,st),c) -> (b,(env,st,c))) in
      let next = List.Assoc.find ms' true ~equal:Poly.(=) in
      begin match next with
        | None -> (env'', st', SReject "NotMatch")
        | Some (fenv,st,next) ->
          let next' = snd (snd next).next in
          eval_direct ctrl fenv st states next' end
    | SReject _ -> (env',st', s)
    | _ -> failwith "unreachable"

  and set_of_case (ctrl : ctrl) (env : env) (st : state) (s : signal)
      (case : Parser.case) (ws : Bigint.t list) : env * state * signal * set =
    match s with
    | SContinue -> set_of_matches ctrl env st s (snd case).matches ws
    | SReject _ -> (env,st,s,SUniversal)
    | _ -> failwith "unreachable"

  and set_of_matches (ctrl : ctrl) (env : env) (st : state) (s : signal)
      (ms : Match.t list) (ws : Bigint.t list) : env * state * signal * set =
    match ms,ws with
    | [],_ -> failwith "invalid set"
    | [m],[w] -> set_of_match ctrl env st s m w
    | l,ws ->
      let f i (a,b,c) d =
        let (w,x,y,z) = set_of_match ctrl a b c d (List.nth_exn ws i) in
        ((w,x,y),z) in
      let ((env',st',s),l') = List.fold_mapi l ~init:(env,st,SContinue) ~f:f in
      (env',st',s,SProd l')

  and set_of_match (ctrl : ctrl) (env : env) (st : state) (s : signal)
      (m : Match.t) (w : Bigint.t) : env * state * signal * set =
    match s with
    | SContinue ->
      begin match snd m with
        | Default
        | DontCare         -> (env, st, SContinue, SUniversal)
        | Expression{expr} ->
          let (env', st', s, v) = eval_expr ctrl env st SContinue expr in
          (env', st', s, assert_set v w) end
    | SReject _ -> (env, st, s, SUniversal)
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

  and eval_control (ctrl : ctrl) (env : env) (st : state) (params : Parameter.t list)
      (args : Argument.t list) (vs : (string * value) list)
      (locals : Declaration.t list) (apply : Block.t) : env * state * signal =
    let (cenv,st',_) = copyin ctrl env st params args in
    let f a (x,y) = EvalEnv.insert_val x y a in
    let cenv' = List.fold_left vs ~init:cenv ~f:f in
    let (cenv'',st'') = List.fold_left locals ~init:(cenv',st') ~f:(fun (e,st) s -> eval_decl ctrl e st s) in
    let block = (Info.dummy, Statement.BlockStatement {block = apply}) in
    let (cenv''', st''', sign) = eval_stmt ctrl cenv'' st'' SContinue block in
    match sign with
    | SContinue
    | SExit     -> (copyout ctrl cenv''' st''' params args, st''', sign)
    | SReject _ -> failwith "control should not reject"
    | SReturn _ -> failwith "control should not return"

  (*----------------------------------------------------------------------------*)
  (* Helper functions *)
  (*----------------------------------------------------------------------------*)

  and fourth4 (a,b,c,d) = d

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

  and decl_of_typ (e : env) (t : Type.t) : Declaration.t =
    match snd t with
    | TypeName (_,s)                 -> (EvalEnv.find_decl s e)
    | TopLevelType (_,s)             -> (EvalEnv.find_decl_toplevel s e)
    | _ -> (Info.dummy, Error{members = []}) (* TODO: find better solution *)

  and init_binding_of_field (ctrl : ctrl) (env : env) (st : state)
      (f : Declaration.field) : string * value =
    let n = snd (snd f).name in
    (n, init_val_of_typ ctrl env st n (snd f).typ)

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
      print_endline "bitstring slice";
      if l > zero
      then bitstring_slice (n/(one + one)) (m-one) (l-one)
      else n % (power_of_two (m + one)))

  and typ_of_tuple_field (t : Type.t) (i : int) : Type.t =
    match snd t with
    | Tuple ts -> List.nth_exn ts i
    | _ -> failwith "not a tuple type"

  and typ_of_struct_field (env : env) (t : Type.t)
      (fname : string) : Type.t =
    let (_, d) = decl_of_typ env t in
    let fs = match d with
      | Struct h -> h.fields
      | _ -> failwith "not a struct" in
    match List.filter fs ~f:(fun a -> String.equal (snd (snd a).name) fname) with
    | h :: _ -> (snd h).typ
    | _ -> failwith "field name not found"

  and typ_of_header_field (env : env) (t : Type.t)
      (fname : string) : Type.t =
    let (_,d) = decl_of_typ env t in
    let fs = match d with
      | Header h -> h.fields
      | _ -> failwith "not a header" in
    match List.filter fs ~f:(fun a -> String.equal (snd (snd a).name) fname) with
    | h :: _ -> (snd h). typ
    | _ -> failwith "field name not found"

  and typ_of_union_field (env : env) (t : Type.t)
      (fname : string) : Type.t =
    let (_, d) = decl_of_typ env t in
    let fs = match d with
      | HeaderUnion u -> u.fields
      | _ -> failwith "not a union" in
    match List.filter fs ~f:(fun a -> String.equal (snd (snd a).name) fname) with
    | h :: _ -> (snd h).typ
    | _ -> failwith "field name not found"

  and typ_of_stack_mem (ctrl : ctrl) (env : env) (st : state) (lv : lvalue) : Type.t =
    let t = typ_of_lvalue ctrl env st lv in
    match snd t with
    | HeaderStack{header;_} -> header
    | _ -> failwith "not a header stack"

  and struct_of_list (ctrl : ctrl) (env : env) (st : state) (lv : lvalue) (name : string)
      (l : value list) : value =
    let t = typ_of_lvalue ctrl env st lv in
    let d = decl_of_typ env t in
    let (tname, fs) = match snd d with
      | Declaration.Struct s -> (snd s.name), s.fields
      | _ -> failwith "not a struct" in
    let ns = List.map fs ~f:(fun x -> snd (snd x).name) in
    let ts = List.map fs ~f:(fun x -> (snd x).typ) in
    let l' = List.mapi l ~f:(fun i v -> implicit_cast_from_rawint ctrl env st v (List.nth_exn ts i)) in
    let l'' = List.mapi l' ~f:(fun i v -> implicit_cast_from_tuple ctrl env st
                                  (LMember{expr=lv;name=List.nth_exn ns i}) (List.nth_exn ns i)
                                  v (List.nth_exn ts i)) in
    let l''' = List.mapi l'' ~f:(fun i v -> (List.nth_exn ns i, v)) in
    VStruct{name;typ_name=tname;fields=l'''}

  and header_of_list (ctrl : ctrl) (env : env) (st : state) (lv : lvalue) (name : string)
      (l : value list) : value =
    let t = typ_of_lvalue ctrl env st lv in
    let d = decl_of_typ env t in
    let (tname, fs) = match snd d with
      | Declaration.Header h -> (snd h.name), h.fields
      | _ -> failwith "not a header" in
    let ns = List.map fs ~f:(fun x -> snd (snd x).name) in
    let ts = List.map fs ~f:(fun x -> (snd x).typ) in
    let l' = List.mapi l ~f:(fun i v -> implicit_cast_from_rawint ctrl env st v (List.nth_exn ts i)) in
    let l'' = List.mapi l' ~f:(fun i v -> (List.nth_exn ns i, v)) in
    VHeader{name;typ_name=tname;fields=l'';is_valid=true}

  and implicit_cast_from_rawint (ctrl : ctrl) (env : env) (st : state) (v : value)
      (t : Type.t) : value =
    match v with
    | VInteger n ->
      begin match snd t with
        | Type.IntType e ->
          e
          |> eval_expr ctrl env st SContinue
          |> fourth4
          |> bigint_of_val
          |> int_of_rawint n
        | Type.BitType e ->
          e
          |> eval_expr ctrl env st SContinue
          |> fourth4
          |> bigint_of_val
          |> bit_of_rawint n
        | Type.Bool -> failwith "is bool"
        | Type.TypeName (_,n) ->
          EvalEnv.find_decl n env
          |> assert_typ_def
          |> assert_typ
          |> implicit_cast_from_rawint ctrl env st v
        | _ -> v
        end
    | _ -> v

  and implicit_cast_from_tuple (ctrl : ctrl) (env : env) (st : state) (lv : lvalue) 
      (n : string) (v : value) (t : Type.t) : value =
    match v with
    | VTuple l ->
      begin match snd (decl_of_typ env t) with
        | Struct _ -> struct_of_list ctrl env st lv n l
        | Header _ -> header_of_list ctrl env st lv n l
        | _ -> VTuple l end
    | _ -> v

  and label_matches_string (s : string) (case : Statement.pre_switch_case) : bool =
    match case with
    | Action{label;_}
    | FallThrough{label} ->
      begin match snd label with
        | Default -> true
        | Name(_,n) -> String.equal s n end

  and eval_statement ctrl env st s = 
    let (a,b,_) = eval_stmt ctrl env st SContinue s in (a,b)

  and eval_expression ctrl env st expr = 
    let (a,b,_,c) = eval_expr ctrl env st SContinue expr in (a,b,c)

  and eval (ctrl : ctrl) (env : env) (st : state) (pkt : pkt)
      (in_port : Bigint.t) : state * env * pkt =
    let env' = T.initialize_metadata in_port env in 
    T.eval_pipeline ctrl env' st pkt eval_app eval_assign' init_val_of_typ

end

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

module V1Interpreter = MakeInterpreter(Target.V1Model)

(* module EbpfInterpreter = MakeInterpreter(Target.EbpfFilter) *)

let eval_main (env : env) (ctrl : ctrl) (pkt : pkt)
    (in_port : Bigint.t) : pkt * Bigint.t =
  let name =
    match env |> EvalEnv.find_val "main" |> assert_package |> fst |> snd with
    | Declaration.PackageType {name=(_,n);_} -> n
    | _ -> failwith "main is not a package" in
  match name with
  | "V1Switch"     ->
    let (_, env', pkt) = V1Interpreter.eval ctrl env V1Interpreter.empty_state pkt in_port in
    begin match EvalEnv.find_val "std_meta" env' with
    | VStruct {fields;_} -> 
      pkt, 
      List.Assoc.find_exn fields "egress_port" ~equal:String.equal
      |> assert_bit
      |> snd
    | _ -> failwith "TODO" end
  (* | "ebpfFilter"   -> EbpfInterpreter.eval ctrl env EbpfInterpreter.empty_state pkt |> snd *)
  | "EmptyPackage" -> pkt, Bigint.zero
  | _ -> failwith "architecture not supported"

let assert_main_pkg (d : Declaration.t) : string = 
  match snd d with 
  | Instantiation {typ;name;_} ->
    if String.(<>) (snd name) "main" then failwith "package declaration is not main"
    else begin match snd typ with
      | TypeName (_,n) -> n
      | _ -> failwith "main instantiation not a typename" end
  | _ -> failwith "main not an instantiation"

let eval_prog (p : Types.program) (ctrl : ctrl) (pkt : pkt)
    (in_port : Bigint.t) : (string * Bigint.t) option =
  match p with Program l ->
    let name = List.rev l |> List.hd_exn |> assert_main_pkg in
    let eval_decl = match name with 
      | "V1Switch"     -> V1Interpreter.eval_decl
      | "ebpfFilter"   -> failwith "unimplemented" (* TODO: resolve return type of eval_prog *)
      | "EmptyPackage" -> failwith "unimplemented" (* (fun (e:env) s d -> e) *)
      | _ -> failwith "architecture not supported" in
    let (env,st) = 
      List.fold_left l 
        ~init:(EvalEnv.empty_eval_env, V1Interpreter.empty_state)
        ~f:(fun (e,s) -> eval_decl ctrl e s) 
    in
    EvalEnv.print_env env;
    Format.printf "Done\n";
    let pkt', port = eval_main env ctrl pkt in_port in
    print_string "Resulting packet: ";
    Some begin
    pkt'
    |> Cstruct.to_string
    |> hex_of_string, port end

let print_eval_program p ctrl pkt in_port =
  match eval_prog p ctrl pkt in_port with
  | Some (pkt, _) -> pkt |> print_endline
  | None -> ()
