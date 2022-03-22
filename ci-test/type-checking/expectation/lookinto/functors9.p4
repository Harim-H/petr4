/petr4/ci-test/type-checking/testdata/p4_16_samples/functors9.p4
\n
/*
Copyright 2013-present Barefoot Networks, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

#include <core.p4>

extern e<T> {
    e();
    T get();
}

parser p1<T>(in T a) {
    e<T>() ei;
    state start {
        T w = ei.get();
        transition accept;
    }
}

parser simple(in bit<2> a);

package m(simple n);

m(p1<bit<2>>()) main;
************************\n******** petr4 type checking result: ********\n************************\n
Uncaught exception:
  
  Petr4.Prog.Env.UnboundName("T")

Raised at Petr4__Prog.Env.raise_unbound in file "lib/prog.ml", line 1455, characters 4-32
Called from Petr4__Checker.is_some_type in file "lib/checker.ml", line 64, characters 13-47
Called from Petr4__Checker.validate_param in file "lib/checker.ml", line 1367, characters 5-22
Called from Petr4__Checker.type_param' in file "lib/checker.ml", line 1380, characters 2-43
Called from Base__List.count_map in file "src/list.ml", line 387, characters 13-17
Called from Base__List.map in file "src/list.ml" (inlined), line 418, characters 15-31
Called from Petr4__Checker.type_params' in file "lib/checker.ml", line 1401, characters 4-66
Called from Petr4__Checker.type_params in file "lib/checker.ml" (inlined), line 1408, characters 6-34
Called from Petr4__Checker.open_parser_scope in file "lib/checker.ml", line 3042, characters 21-57
Called from Petr4__Checker.type_parser in file "lib/checker.ml", line 3057, characters 4-72
Called from Petr4__Checker.type_declarations.f in file "lib/checker.ml", line 4118, characters 26-55
Called from Stdlib__list.fold_left in file "list.ml", line 121, characters 24-34
Called from Base__List0.fold in file "src/list0.ml" (inlined), line 21, characters 22-52
Called from Petr4__Checker.type_declarations in file "lib/checker.ml", line 4121, characters 19-58
Called from Petr4__Checker.check_program in file "lib/checker.ml", line 4128, characters 18-78
Called from Petr4__Common.Make_parse.check_file' in file "lib/common.ml", line 95, characters 17-51
Called from Petr4__Common.Make_parse.check_file in file "lib/common.ml", line 108, characters 10-50
Called from Main.check_command.(fun) in file "bin/main.ml", line 70, characters 14-65
Called from Core_kernel__Command.For_unix.run.(fun) in file "src/command.ml", line 2453, characters 8-238
Called from Base__Exn.handle_uncaught_aux in file "src/exn.ml", line 111, characters 6-10
************************\n******** p4c type checking result: ********\n************************\n
