/petr4/ci-test/type-checking/testdata/p4_16_samples/bfd_offload.p4
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


extern BFD_Offload {
    BFD_Offload(bit<16> size);

    // State manipulation
    void setTx(in bit<16> index, in bit<8> data);
    bit<8> getTx(in bit<16> index);

    abstract void on_rx( in bit<16> index );
    abstract bool on_tx( in bit<16> index );
}

BFD_Offload(32768) bfd_session_liveness_tracker = {
    void on_rx( in bit<16> index ) {
        this.setTx(index, 0);
    }
    bool on_tx( in bit<16> index ) {
        bit<8> c = this.getTx(index) + 1;
        if (c >= 4) {
            return true;
        } else {
            this.setTx(index, c);
            return false;
        }
    }
};

control for_rx_bfd_packets() {
    apply {
        bit<16> index;
        bfd_session_liveness_tracker.on_rx( index );
    }
}
control for_tx_bfd_packets() {
    apply {
        bit<16> index;
        bfd_session_liveness_tracker.on_tx( index );
    }
}
************************\n******** petr4 type checking result: ********\n************************\n
Uncaught exception:
  
  (Failure "initializer block in instantiation unsupported")

Raised at Stdlib.failwith in file "stdlib.ml", line 29, characters 17-33
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
/petr4/ci-test/type-checking/testdata/p4_16_samples/bfd_offload.p4(29): [--Wwarn=unused] warning: bfd_session_liveness_tracker: unused instance
BFD_Offload(32768) bfd_session_liveness_tracker = {
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
[--Wwarn=missing] warning: Program does not contain a `main' module
