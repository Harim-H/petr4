#include <core.p4>

header ethernet_t {
    bit<48> dst_addr;
    bit<48> src_addr;
    bit<16> eth_type;
}

struct Headers {
    ethernet_t eth_hdr;
}

extern bit<16> call_extern(ethernet_t val);
parser p(packet_in pkt, out Headers hdr) {
    state start {
        pkt.extract<ethernet_t>(hdr.eth_hdr);
        transition accept;
    }
}

control ingress(inout Headers h) {
    @hidden action gauntlet_extern_arguments_2l28() {
        h.eth_hdr.eth_type = call_extern((ethernet_t){dst_addr = 48w1,src_addr = 48w2,eth_type = 16w1});
    }
    @hidden table tbl_gauntlet_extern_arguments_2l28 {
        actions = {
            gauntlet_extern_arguments_2l28();
        }
        const default_action = gauntlet_extern_arguments_2l28();
    }
    apply {
        tbl_gauntlet_extern_arguments_2l28.apply();
    }
}

parser Parser(packet_in b, out Headers hdr);
control Ingress(inout Headers hdr);
package top(Parser p, Ingress ig);
top(p(), ingress()) main;

