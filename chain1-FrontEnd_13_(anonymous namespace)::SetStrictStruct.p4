error {
    NoError,
    PacketTooShort,
    NoMatch,
    StackOutOfBounds,
    HeaderTooShort,
    ParserTimeout,
    ParserInvalidArgument
}

extern packet_in {
    void extract<T>(out T hdr);
    void extract<T>(out T variableSizeHeader, in bit<32> variableFieldSizeInBits);
    T lookahead<T>();
    void advance(in bit<32> sizeInBits);
    bit<32> length();
}

extern packet_out {
    void emit<T>(in T hdr);
}

extern void verify(in bool check, in error toSignal);
@noWarn("unused") action NoAction() {
}
match_kind {
    exact,
    ternary,
    lpm
}

header Header {
    bit<32> data;
}

parser p1(packet_in p, out Header h) {
    bit<1> x;
    state start {
        transition select(x) {
            1w0: chain1;
            1w1: chain2;
        }
    }
    state chain1 {
        p.extract(h);
        transition next1;
    }
    state next1 {
        transition endchain;
    }
    state chain2 {
        p.extract(h);
        transition next2;
    }
    state next2 {
        transition endchain;
    }
    state endchain {
        transition accept;
    }
}

parser proto(packet_in p, out Header h);
package top(proto _p);
top(p1()) main;

