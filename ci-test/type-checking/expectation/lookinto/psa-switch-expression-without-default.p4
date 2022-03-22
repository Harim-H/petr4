/petr4/ci-test/type-checking/testdata/p4_16_samples/psa-switch-expression-without-default.p4
\n
#include <core.p4>
#include <psa.p4>

struct EMPTY { };

typedef bit<48>  EthernetAddress;

struct user_meta_t {
    bit<16> data;
    bit<16> data1;
}

header ethernet_t {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
    bit<80> newfield;
}

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<3>  res;
    bit<3>  ecn;
    bit<6>  ctrl;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

struct headers_t {
    ethernet_t ethernet;
    ipv4_t           ipv4;
    tcp_t            tcp;
}

parser MyIP(
    packet_in buffer,
    out headers_t hdr,
    inout user_meta_t b,
    in psa_ingress_parser_input_metadata_t c,
    in EMPTY d,
    in EMPTY e) {

    state start {
        buffer.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            0x0800 &&& 0x0F00 : parse_ipv4;
            16w0x0d00 : parse_tcp;
            default : accept;
        }
    }
    state parse_ipv4 {
        buffer.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            8w4 .. 8w7: parse_tcp;
            default: accept;
        }
    }
    state parse_tcp {
        buffer.extract(hdr.tcp);
        transition accept;
    }
}

parser MyEP(
    packet_in buffer,
    out EMPTY a,
    inout EMPTY b,
    in psa_egress_parser_input_metadata_t c,
    in EMPTY d,
    in EMPTY e,
    in EMPTY f) {
    state start {
        transition accept;
    }
}

control MyIC(
    inout headers_t hdr,
    inout user_meta_t b,
    in psa_ingress_input_metadata_t c,
    inout psa_ingress_output_metadata_t d) {
    bit<16> tmp = 16;
    action a1(bit<48> param) { hdr.ethernet.dstAddr = param; }
    action a2(bit<16> param) { hdr.ethernet.etherType = param; }
    table tbl {
        key = {
            hdr.ethernet.srcAddr : exact;
            b.data : lpm;
        }
        actions = { NoAction; a1; a2; }
    }

    table foo {
        actions = { NoAction; }
    }

    table bar {
        actions = { NoAction; }
    }

    apply {
        switch (tmp) {
            16:
            32: { tmp = 1; }
             64: { tmp = 2; }
            92:
        }
        switch (tbl.apply().action_run) {
            a1: {  if (tmp == 1) foo.apply(); }
            a2: { bar.apply(); }
        }
    }
}

control MyEC(
    inout EMPTY a,
    inout EMPTY b,
    in psa_egress_input_metadata_t c,
    inout psa_egress_output_metadata_t d) {
    apply { }
}

control MyID(
    packet_out buffer,
    out EMPTY a,
    out EMPTY b,
    out EMPTY c,
    inout headers_t hdr,
    in user_meta_t e,
    in psa_ingress_output_metadata_t f) {
    apply {
        buffer.emit(hdr.ethernet);
    }
}

control MyED(
    packet_out buffer,
    out EMPTY a,
    out EMPTY b,
    inout EMPTY c,
    in EMPTY d,
    in psa_egress_output_metadata_t e,
    in psa_egress_deparser_input_metadata_t f) {
    apply { }
}

IngressPipeline(MyIP(), MyIC(), MyID()) ip;
EgressPipeline(MyEP(), MyEC(), MyED()) ep;

PSA_Switch(
    ip,
    PacketReplicationEngine(),
    ep,
    BufferingQueueingEngine()) main;
************************\n******** petr4 type checking result: ********\n************************\n
/petr4/ci-test/type-checking/testdata/p4_16_samples/psa-switch-expression-without-default.p4:2:10: fatal error: psa.p4: No such file or directory
    2 | #include <psa.p4>
      |          ^~~~~~~~
compilation terminated.
error {
  NoError, PacketTooShort, NoMatch, StackOutOfBounds, HeaderTooShort,
  ParserTimeout, ParserInvalidArgument
}
extern packet_in {
  void extract<T>(out T hdr);
  void extract<T0>(out T0 variableSizeHeader,
                   in bit<32> variableFieldSizeInBits);
  T1 lookahead<T1>();
  void advance(in bit<32> sizeInBits);
  bit<32> length();
}

extern packet_out {
  void emit<T2>(in T2 hdr);
}

extern void verify(in bool check, in error toSignal);
@noWarn("unused")
action NoAction() { 
}
match_kind {
  exact, ternary, lpm
}

************************\n******** p4c type checking result: ********\n************************\n
/petr4/ci-test/type-checking/testdata/p4_16_samples/psa-switch-expression-without-default.p4(126): [--Wwarn=missing] warning: SwitchCase: fallthrough with no statement
            92:
            ^^
/usr/local/share/p4c/p4include/bmv2/psa.p4(546): [--Wwarn=unused] warning: 'W' is unused
extern Counter<W, S> {
               ^
/usr/local/share/p4c/p4include/bmv2/psa.p4(575): [--Wwarn=unused] warning: 'W' is unused
extern DirectCounter<W> {
                     ^
/petr4/ci-test/type-checking/testdata/p4_16_samples/psa-switch-expression-without-default.p4(122): [--Wwarn=mismatch] warning: 16w16: constant expression in switch
        switch (tmp) {
                ^^^
