#include  "test.h"

/*
 * This file implements the following C extern function:
 *
 * bool verify_ipv4_checksum(in IPv4_h iphdr)
 *
 */


/**
 * This function implements method to verify IP checksum.
 * @param iphdr Structure representing IP header. The IP header is generated by the P4 compiler and defined in test.h.
 * @return True if checksum is correct.
 */
static inline u8 verify_ipv4_checksum(const struct IPv4_h iphdr)
{
    u8 correct = 0;
    u32 checksum = bpf_htons(((u16) iphdr.version << 12) | ((u16) iphdr.ihl << 8) | (u16) iphdr.diffserv);
    checksum += bpf_htons(iphdr.totalLen);
    checksum += bpf_htons(iphdr.identification);
    checksum += bpf_htons(((u16) iphdr.flags << 13) | iphdr.fragOffset);
    checksum += bpf_htons(((u16) iphdr.ttl << 8) | (u16) iphdr.protocol);
    checksum += bpf_htons(iphdr.hdrChecksum);
    u32 srcAddr = bpf_ntohl(iphdr.srcAddr);
    u32 dstAddr = bpf_ntohl(iphdr.dstAddr);
    checksum += (srcAddr >> 16) + (u16) srcAddr;
    checksum += (dstAddr >> 16) + (u16) dstAddr;

    u16 res = bpf_ntohs(~((checksum & 0xFFFF) + (checksum >> 16)));

    if (res == 0)
        correct = 1;
    return correct;
}


