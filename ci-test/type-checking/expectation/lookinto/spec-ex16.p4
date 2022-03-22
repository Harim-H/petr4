/petr4/ci-test/type-checking/testdata/p4_16_samples/spec-ex16.p4
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

parser Prs<T>(packet_in b, out T result);
control Map<T>(in T d);

package Switch<T>(Prs<T> prs, Map<T> map);

parser P(packet_in b, out bit<32> d) { state start { transition accept; } }
control Map1(in bit<32> d) { apply {} }
control Map2(in bit<8> d) { apply {} }

Switch(P(),
       Map1()) main;

Switch<bit<32>>(P(),
                Map1()) main1;
************************\n******** petr4 type checking result: ********\n************************\n
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
parser Prs<T3> (packet_in b, out T3 result);
control Map<T4> (in T4 d);
package Switch<T5> (Prs<T5> prs, Map<T5> map);
parser P(packet_in b, out bit<32> d) {
  state start {
    transition accept;
  }
}
control Map1(in bit<32> d) {
  apply { 
  }
}
control Map2(in bit<8> d) {
  apply { 
  }
}
Switch(P(), Map1()) main;
Switch<bit<32>>(P(), Map1()) main1;

************************\n******** p4c type checking result: ********\n************************\n
/petr4/ci-test/type-checking/testdata/p4_16_samples/spec-ex16.p4(32): [--Wwarn=unused] warning: main1: unused instance
                Map1()) main1;
                        ^^^^^
/petr4/ci-test/type-checking/testdata/p4_16_samples/spec-ex16.p4(24): [--Wwarn=uninitialized_out_param] warning: out parameter 'd' may be uninitialized when 'P' terminates
parser P(packet_in b, out bit<32> d) { state start { transition accept; } }
                                  ^
/petr4/ci-test/type-checking/testdata/p4_16_samples/spec-ex16.p4(24)
parser P(packet_in b, out bit<32> d) { state start { transition accept; } }
       ^
