/petr4/ci-test/type-checking/testdata/p4_16_samples/bit0-bmv2.p4
\n
#include <core.p4>

header ethernet_t {
    bit<48> dst_addr;
    bit<48> src_addr;
    bit<16> eth_type;
}

header H {
    bit<0> a;
    bit<1> b;
    bit<0> c;
}

struct Headers {
    ethernet_t eth_hdr;
    H          h;
}

parser p(packet_in pkt, out Headers hdr) {
    state start {
        transition parse_hdrs;
    }
    state parse_hdrs {
        pkt.extract(hdr.eth_hdr);
        pkt.extract(hdr.h);
        transition accept;
    }
}

control ingress(inout Headers h) {

    apply {
        bit<0> tmp = 1;
        h.h.a = tmp;
        h.h.b = (bit<1>) h.h.a;
        h.h.c = h.h.a + (bit<0>) h.h.b;
    }
}

parser Parser(packet_in b, out Headers hdr);
control Ingress(inout Headers hdr);
package top(Parser p, Ingress ig);
top(p(), ingress()) main;
************************\n******** petr4 type checking result: ********\n************************\n
Uncaught exception:
  
  ("expected positive integer"
   (info
    (I
     (filename
      /petr4/ci-test/type-checking/testdata/p4_16_samples/bit0-bmv2.p4)
     (line_start 10) (line_end ()) (col_start 4) (col_end 10))))

Raised at Base__Error.raise in file "src/error.ml" (inlined), line 8, characters 14-30
Called from Base__Error.raise_s in file "src/error.ml", line 9, characters 19-40
Called from Petr4__Checker.translate_type' in file "lib/checker.ml", line 1087, characters 37-73
Called from Petr4__Checker.translate_type in file "lib/checker.ml" (inlined), line 1114, characters 6-36
Called from Petr4__Checker.type_field in file "lib/checker.ml", line 3697, characters 30-63
Called from Base__List.count_map in file "src/list.ml", line 394, characters 13-17
Called from Base__List.map in file "src/list.ml" (inlined), line 418, characters 15-31
Called from Petr4__Checker.type_header in file "lib/checker.ml", line 3687, characters 48-83
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
/petr4/ci-test/type-checking/testdata/p4_16_samples/bit0-bmv2.p4(34): [--Wwarn=mismatch] warning: 1: value does not fit in 0 bits
        bit<0> tmp = 1;
                     ^
