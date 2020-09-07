(* Copyright 2019-present Cornell University
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not
 * use this file except in compliance with the License. You may obtain a copy
 * of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations
 * under the License.
 *)

type i_record =
  { filename :string;
    line_start: int;
    line_end: int option;
    col_start: int;
    col_end: int } [@@deriving sexp,yojson,show]

type t =
  | I of
      int * i_record
  | M of int * string
[@@deriving sexp,show,yojson]

val update_identifier : t -> int -> t
val identifier_of_info : t -> int

val dummy : t

val merge : t -> t -> t

val follows : t -> t -> bool

val to_string : t -> string

val header_union_info : t
