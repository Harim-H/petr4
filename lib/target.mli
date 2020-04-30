open Value
open Env
open Types

type env = EvalEnv.t

type 'st assign = 
  ctrl -> env -> 'st -> lvalue -> value -> env * 'st * signal

type ('st1, 'st2) pre_extern =
  'st1 assign -> ctrl -> env -> 'st2 -> Type.t list -> value list ->
  env * 'st2 * signal * value

type 'st apply =
  ctrl -> env -> 'st -> signal -> value -> Argument.t list -> env * 'st * signal * value

type 'st init_typ = 
  ctrl -> env -> 'st -> string -> Type.t -> value

module State : sig
  type 'a t

  val empty : 'a t
  val insert : int -> 'a -> 'a t -> 'a t
  val find : int -> 'a t -> 'a
  val fresh_loc : unit -> int
end

module type Target = sig 

  type obj

  type state = obj State.t

  type 'st extern = ('st, state) pre_extern

  val externs : (string * state extern) list

  val eval_extern : state assign -> ctrl -> env -> state -> Type.t list ->
                    value list -> string -> env * state * signal * value

  val initialize_metadata : Bigint.t -> env -> env

  val check_pipeline : env -> unit 

  val eval_pipeline : ctrl -> env -> state -> pkt ->
  state apply -> 
  state assign -> 
  state init_typ -> state * env * pkt

end

module V1Model : Target

module EbpfFilter : Target