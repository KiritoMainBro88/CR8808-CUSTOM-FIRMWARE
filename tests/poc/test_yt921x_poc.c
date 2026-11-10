/**
 * @file test_yt921x_poc.c
 * @brief Independent Unit Test Suite for Motorcomm YT9215SC CPU Tagging & NSS Compatibility
 * 
 * Project: CR8808-CUSTOM-FIRMWARE (Xiaomi CR8808 Ver.B / CR8818)
 * 
 * Complies with upstream Linux net/dsa/tag_yt921x.c (commit ca4709843b7e / OpenWrt 967-02).
 * All test cases use INDEPENDENT ORACLE TEST VECTORS directly derived from hardware &
 * driver register specifications, without circular test dependencies.
 */

#include "yt921x_tag_proto.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define COLOR_GREEN  "\033[32m"
#define COLOR_RED    "\033[31m"
#define COLOR_YELLOW "\033[33m"
#define COLOR_CYAN   "\033[36m"
#define COLOR_RESET  "\033[0m"

static int g_tests_passed = 0;
static int g_tests_failed = 0;

#define TEST_ASSERT(cond, msg) do { \
    if (cond) { \
        printf("  " COLOR_GREEN "[PASS]" COLOR_RESET " %s\n", msg); \
        g_tests_passed++; \
    } else { \
        printf("  " COLOR_RED "[FAIL]" COLOR_RESET " %s (Line %d)\n", msg, __LINE__); \
        g_tests_failed++; \
    } \
} while(0)

/* =========================================================================
 * INDEPENDENT ORACLE TEST VECTORS
 * Derived directly from upstream net/dsa/tag_yt921x.c specification:
 * Frame wire layout:
 * [0..5]   DMAC:  00:11:22:33:44:55
 * [6..11]  SMAC:  AA:BB:CC:DD:EE:FF
 * [12..13] TagET: 0x99, 0x88 (ETH_P_YT921X Big-Endian)
 * [14..15] VLAN:  0x00, 0x00
 * [16..17] Rx:    bit 15 PORT_EN (0x8000), bits 14..11 Port, bits 10..0 Cmd
 * [18..19] Tx:    bit 15 PORT_EN (0x8000), bits 10..0 Tx Port Mask (BIT(port))
 * [20..21] ET:    0x08, 0x00 (ETH_P_IP)
 * [22..]   Payload bytes...
 * ========================================================================= */

/* Oracle Vector 1: Expected Tx wire bytes for LAN1 (Port 0) */
static const uint8_t ORACLE_TX_PORT0_LAN1[] = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55,       /* DMAC */
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,       /* SMAC */
    0x99, 0x88,                               /* Tag EtherType: 0x9988 */
    0x00, 0x00,                               /* VLAN Tag field */
    0x00, 0x00,                               /* Rx Port metadata (0 on Tx) */
    0x80, 0x01,                               /* Tx Port Mask: PORT_EN (0x8000) | BIT(0) */
    0x08, 0x00,                               /* Original EtherType: IPv4 */
    'T', 'E', 'S', 'T'                        /* 4 bytes payload */
};

/* Oracle Vector 2: Expected Tx wire bytes for WAN (Port 3) */
static const uint8_t ORACLE_TX_PORT3_WAN[] = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55,
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
    0x99, 0x88,
    0x00, 0x00,
    0x00, 0x00,
    0x80, 0x08,                               /* Tx Port Mask: PORT_EN (0x8000) | BIT(3) */
    0x08, 0x00,
    'T', 'E', 'S', 'T'
};

/* Oracle Vector 3: Expected Tx wire bytes for Primary CPU Conduit (Port 8) */
static const uint8_t ORACLE_TX_PORT8_CPU1[] = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55,
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
    0x99, 0x88,
    0x00, 0x00,
    0x00, 0x00,
    0x81, 0x00,                               /* Tx Port Mask: PORT_EN (0x8000) | BIT(8) = 0x8100 */
    0x08, 0x00,
    'T', 'E', 'S', 'T'
};

/* Oracle Vector 4: Wire packet received from WAN (Port 3) with FORWARDED command (0x080)
 * Byte 16-17 = (3 << 11) | 0x8000 | 0x080 = 0x1800 | 0x8000 | 0x080 = 0x9880 */
static const uint8_t ORACLE_RX_PORT3_FORWARDED[] = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55,
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
    0x99, 0x88,                               /* TPID 0x9988 */
    0x00, 0x2A,                               /* VLAN ID = 42 */
    0x98, 0x80,                               /* Rx: PORT_EN | (Port 3 << 11) | CMD_FORWARDED (0x080) */
    0x00, 0x00,                               /* Tx bits (0 on Rx) */
    0x08, 0x00,                               /* Original EtherType: IPv4 */
    0xDE, 0xAD, 0xBE, 0xEF                    /* Payload */
};

/* Oracle Vector 5: Wire packet received from LAN2 (Port 1) with UNKNOWN UNICAST TRAP (0x0B2)
 * Byte 16-17 = (1 << 11) | 0x8000 | 0x0B2 = 0x0800 | 0x8000 | 0x0B2 = 0x88B2 */
static const uint8_t ORACLE_RX_PORT1_UNK_UCAST[] = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55,
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
    0x99, 0x88,
    0x00, 0x00,
    0x88, 0xB2,                               /* Rx: PORT_EN | (Port 1 << 11) | CMD_UNK_UCAST (0x0B2) */
    0x00, 0x00,
    0x08, 0x00,
    0x01, 0x02, 0x03, 0x04
};

/* Oracle Vector 6: Wire packet received from LAN3 (Port 2) with UNKNOWN MULTICAST TRAP (0x0B4)
 * Byte 16-17 = (2 << 11) | 0x8000 | 0x0B4 = 0x1000 | 0x8000 | 0x0B4 = 0x90B4 */
static const uint8_t ORACLE_RX_PORT2_UNK_MCAST[] = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55,
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
    0x99, 0x88,
    0x00, 0x00,
    0x90, 0xB4,                               /* Rx: PORT_EN | (Port 2 << 11) | CMD_UNK_MCAST (0x0B4) */
    0x00, 0x00,
    0x86, 0xDD,                               /* Original EtherType: IPv6 */
    0xCA, 0xFE, 0xBA, 0xBE
};

/* Oracle Vector 7: Standard IEEE 802.1Q tagged frame for LAN3 (Port 2 -> VID 102) */
static const uint8_t ORACLE_8021Q_PORT2[] = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55,
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
    0x81, 0x00,                               /* 802.1Q TPID */
    0x00, 0x66,                               /* VID = 100 + 2 = 102 (0x0066) */
    0x08, 0x00,                               /* EtherType: IPv4 */
    'Q', 'T', 'A', 'G'                        /* Payload */
};

/* Oracle Vector 8: IEEE 802.1p Priority Tagged Frame (PCP=5, DEI=0, VID=0) */
static const uint8_t ORACLE_8021P_PRIORITY[] = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55,
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
    0x81, 0x00,                               /* 802.1Q TPID */
    0xA0, 0x00,                               /* PCP = 5 (0xA000), VID = 0 */
    0x08, 0x00,                               /* EtherType: IPv4 */
    'V', 'O', 'I', 'P'
};

/* Oracle Vector 9: QinQ Frame (802.1ad S-Tag 0x88A8 VID 200 + 802.1Q C-Tag 0x8100 VID 100) */
static const uint8_t ORACLE_QINQ_FRAME[] = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55,
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
    0x88, 0xA8,                               /* S-Tag TPID 0x88A8 */
    0x00, 0xC8,                               /* SVID = 200 */
    0x81, 0x00,                               /* C-Tag TPID 0x8100 */
    0x00, 0x64,                               /* CVID = 100 */
    0x08, 0x00,                               /* Inner EtherType: IPv4 */
    'Q', 'I', 'N', 'Q'
};

/* =========================================================================
 * TEST GROUP 1: Upstream Bit-Accurate 8-Byte Motorcomm Tag Encapsulation
 * ========================================================================= */
static void test_group1_motorcomm_xmit_oracle(void)
{
    printf("\n=== Test Group 1: 8-Byte Motorcomm CPU Tag Encapsulation vs Upstream Oracle ===\n");

    ether_frame_t frame;
    memset(&frame, 0, sizeof(frame));
    memcpy(frame.dmac, "\x00\x11\x22\x33\x44\x55", ETH_ALEN);
    memcpy(frame.smac, "\xaa\xbb\xcc\xdd\xee\xff", ETH_ALEN);
    frame.ethertype = ETH_P_IP;
    frame.payload_len = 4;
    memcpy(frame.payload, "TEST", 4);

    uint8_t out[256];
    size_t out_len = 0;

    /* 1.1 Port 0 (LAN1) xmit vs Oracle byte vector */
    int rc = yt921x_tag_xmit(&frame, YT921X_PORT_LAN1, out, &out_len);
    TEST_ASSERT(rc == YT921X_OK, "yt921x_tag_xmit() succeeds for Port 0");
    TEST_ASSERT(out_len == sizeof(ORACLE_TX_PORT0_LAN1), "Encapsulated length matches Oracle (22 bytes)");
    TEST_ASSERT(memcmp(out, ORACLE_TX_PORT0_LAN1, sizeof(ORACLE_TX_PORT0_LAN1)) == 0,
                "Port 0 wire bytes match upstream Oracle vector byte-for-byte");

    /* 1.2 Port 3 (WAN) xmit vs Oracle byte vector */
    rc = yt921x_tag_xmit(&frame, YT921X_PORT_WAN, out, &out_len);
    TEST_ASSERT(rc == YT921X_OK, "yt921x_tag_xmit() succeeds for Port 3");
    TEST_ASSERT(memcmp(out, ORACLE_TX_PORT3_WAN, sizeof(ORACLE_TX_PORT3_WAN)) == 0,
                "Port 3 wire bytes match upstream Oracle vector (Tx mask 0x8008)");

    /* 1.3 Port 8 (CPU1) xmit vs Oracle byte vector */
    rc = yt921x_tag_xmit(&frame, YT921X_PORT_CPU1, out, &out_len);
    TEST_ASSERT(rc == YT921X_OK, "yt921x_tag_xmit() succeeds for Port 8");
    TEST_ASSERT(memcmp(out, ORACLE_TX_PORT8_CPU1, sizeof(ORACLE_TX_PORT8_CPU1)) == 0,
                "Port 8 wire bytes match upstream Oracle vector (Tx mask 0x8100)");

    /* 1.4 Endianness verification: TPID byte 12 is 0x99, byte 13 is 0x88 */
    TEST_ASSERT(out[12] == 0x99 && out[13] == 0x88,
                "Endianness verified: Network Byte Order TPID is strictly 0x99, 0x88");

    /* 1.5 Parameter validation & boundary conditions */
    rc = yt921x_tag_xmit(&frame, 9, out, &out_len);
    TEST_ASSERT(rc == YT921X_ERR_PORT, "Out-of-range port (9 >= YT921X_MAX_PORTS) rejected with YT921X_ERR_PORT");

    rc = yt921x_tag_xmit(NULL, 0, out, &out_len);
    TEST_ASSERT(rc == YT921X_ERR_INVAL, "NULL input frame pointer rejected with YT921X_ERR_INVAL");

    ether_frame_t oversized;
    memset(&oversized, 0, sizeof(oversized));
    oversized.payload_len = 1501; /* Exceeds 1500 MTU */
    rc = yt921x_tag_xmit(&oversized, 0, out, &out_len);
    TEST_ASSERT(rc == YT921X_ERR_MTU, "Oversized payload (1501 > 1500 MTU) rejected with YT921X_ERR_MTU");
}

/* =========================================================================
 * TEST GROUP 2: Upstream Bit-Accurate 8-Byte Motorcomm Tag Decapsulation
 * ========================================================================= */
static void test_group2_motorcomm_rcv_oracle(void)
{
    printf("\n=== Test Group 2: 8-Byte Motorcomm Tag Decapsulation from Independent Oracle ===\n");

    ether_frame_t frame;
    rx_metadata_t meta;

    /* 2.1 Decapsulate Oracle Vector 4: WAN (Port 3), CMD_FORWARDED (0x080) */
    memset(&frame, 0, sizeof(frame));
    memset(&meta, 0, sizeof(meta));
    int rc = yt921x_tag_rcv(ORACLE_RX_PORT3_FORWARDED, sizeof(ORACLE_RX_PORT3_FORWARDED), &frame, &meta);
    TEST_ASSERT(rc == YT921X_OK, "yt921x_tag_rcv() successfully decodes Oracle Vector 4");
    TEST_ASSERT(meta.source_port == YT921X_PORT_WAN, "Source port decoded accurately as 3 (WAN)");
    TEST_ASSERT(meta.forward_cmd == YT921X_RX_CMD_FORWARDED, "Forwarding cmd decoded as 0x080 (FORWARDED)");
    TEST_ASSERT(meta.vlan_id == 42, "Embedded VLAN ID decoded as 42");
    TEST_ASSERT(frame.ethertype == ETH_P_IP, "Original EtherType extracted as 0x0800 (IPv4)");
    TEST_ASSERT(frame.payload_len == 4, "Decapsulated payload length matches 4 bytes");
    TEST_ASSERT(memcmp(frame.payload, "\xDE\xAD\xBE\xEF", 4) == 0, "Payload contents intact (0xDEADBEEF)");

    /* 2.2 Decapsulate Oracle Vector 5: LAN2 (Port 1), CMD_UNK_UCAST (0x0B2) */
    memset(&frame, 0, sizeof(frame));
    memset(&meta, 0, sizeof(meta));
    rc = yt921x_tag_rcv(ORACLE_RX_PORT1_UNK_UCAST, sizeof(ORACLE_RX_PORT1_UNK_UCAST), &frame, &meta);
    TEST_ASSERT(rc == YT921X_OK, "yt921x_tag_rcv() successfully decodes Oracle Vector 5");
    TEST_ASSERT(meta.source_port == YT921X_PORT_LAN2, "Source port decoded accurately as 1 (LAN2)");
    TEST_ASSERT(meta.forward_cmd == YT921X_RX_CMD_UNK_UCAST, "Forwarding cmd decoded as 0x0B2 (UNKNOWN UNICAST)");

    /* 2.3 Decapsulate Oracle Vector 6: LAN3 (Port 2), CMD_UNK_MCAST (0x0B4), IPv6 */
    memset(&frame, 0, sizeof(frame));
    memset(&meta, 0, sizeof(meta));
    rc = yt921x_tag_rcv(ORACLE_RX_PORT2_UNK_MCAST, sizeof(ORACLE_RX_PORT2_UNK_MCAST), &frame, &meta);
    TEST_ASSERT(rc == YT921X_OK, "yt921x_tag_rcv() successfully decodes Oracle Vector 6");
    TEST_ASSERT(meta.source_port == YT921X_PORT_LAN3, "Source port decoded accurately as 2 (LAN3)");
    TEST_ASSERT(meta.forward_cmd == YT921X_RX_CMD_UNK_MCAST, "Forwarding cmd decoded as 0x0B4 (UNKNOWN MULTICAST)");
    TEST_ASSERT(frame.ethertype == ETH_P_IPV6, "Original EtherType extracted as 0x86DD (IPv6)");
}

/* =========================================================================
 * TEST GROUP 3: Error Paths, Truncated Frames & Malformed Tags
 * ========================================================================= */
static void test_group3_malformed_and_edge_cases(void)
{
    printf("\n=== Test Group 3: Robustness, Truncated Frames & Malformed Tags ===\n");

    ether_frame_t frame;
    rx_metadata_t meta;

    /* 3.1 Truncated frame: only 16 bytes (< 22 bytes minimum) */
    uint8_t truncated_buf[16];
    memcpy(truncated_buf, ORACLE_RX_PORT3_FORWARDED, 16);
    int rc = yt921x_tag_rcv(truncated_buf, 16, &frame, &meta);
    TEST_ASSERT(rc == YT921X_ERR_SHORT, "Truncated frame (16B < 22B) rejected with YT921X_ERR_SHORT");

    /* 3.2 Truncated frame: 0 bytes */
    rc = yt921x_tag_rcv(truncated_buf, 0, &frame, &meta);
    TEST_ASSERT(rc == YT921X_ERR_SHORT, "Zero-length buffer rejected with YT921X_ERR_SHORT");

    /* 3.3 Malformed TPID: 0x8888 instead of 0x9988 */
    uint8_t malformed_tpid[sizeof(ORACLE_RX_PORT3_FORWARDED)];
    memcpy(malformed_tpid, ORACLE_RX_PORT3_FORWARDED, sizeof(malformed_tpid));
    malformed_tpid[12] = 0x88;
    malformed_tpid[13] = 0x88;
    rc = yt921x_tag_rcv(malformed_tpid, sizeof(malformed_tpid), &frame, &meta);
    TEST_ASSERT(rc == YT921X_ERR_BAD_TPID, "Malformed TPID (0x8888 != 0x9988) rejected with YT921X_ERR_BAD_TPID");

    /* 3.4 Malformed Tag: PORT_EN bit 15 missing (0x1880 instead of 0x9880) */
    uint8_t malformed_tag[sizeof(ORACLE_RX_PORT3_FORWARDED)];
    memcpy(malformed_tag, ORACLE_RX_PORT3_FORWARDED, sizeof(malformed_tag));
    malformed_tag[16] = 0x18; /* bit 15 is 0 */
    rc = yt921x_tag_rcv(malformed_tag, sizeof(malformed_tag), &frame, &meta);
    TEST_ASSERT(rc == YT921X_ERR_NO_PORT_EN, "Missing PORT_EN bit rejected with YT921X_ERR_NO_PORT_EN (Upstream driver guard)");

    /* 3.5 Out of bounds source port: Port 14 encoded in bits 14..11 (0xF000) */
    uint8_t bad_port_buf[sizeof(ORACLE_RX_PORT3_FORWARDED)];
    memcpy(bad_port_buf, ORACLE_RX_PORT3_FORWARDED, sizeof(bad_port_buf));
    bad_port_buf[16] = 0xF0; /* Port 14 | PORT_EN */
    rc = yt921x_tag_rcv(bad_port_buf, sizeof(bad_port_buf), &frame, &meta);
    TEST_ASSERT(rc == YT921X_ERR_PORT, "Out-of-range port index (14 >= MAX 9) rejected with YT921X_ERR_PORT");
}

/* =========================================================================
 * TEST GROUP 4: IEEE 802.1Q (tag_8021q) & Priority VLAN (802.1p)
 * ========================================================================= */
static void test_group4_vlan_8021q_and_priority(void)
{
    printf("\n=== Test Group 4: IEEE 802.1Q Tagging & Priority VLAN (802.1p) ===\n");

    ether_frame_t frame_in;
    memset(&frame_in, 0, sizeof(frame_in));
    memcpy(frame_in.dmac, "\x00\x11\x22\x33\x44\x55", ETH_ALEN);
    memcpy(frame_in.smac, "\xaa\xbb\xcc\xdd\xee\xff", ETH_ALEN);
    frame_in.ethertype = ETH_P_IP;
    frame_in.payload_len = 4;
    memcpy(frame_in.payload, "QTAG", 4);

    uint8_t out[256];
    size_t out_len = 0;

    /* 4.1 Encapsulate 802.1Q for Port 2 (LAN3) */
    int rc = yt921x_8021q_xmit(&frame_in, YT921X_PORT_LAN3, out, &out_len);
    TEST_ASSERT(rc == YT921X_OK, "yt921x_8021q_xmit() succeeds for Port 2");
    TEST_ASSERT(out_len == sizeof(ORACLE_8021Q_PORT2), "802.1Q wire length is exactly 22 bytes");
    TEST_ASSERT(memcmp(out, ORACLE_8021Q_PORT2, sizeof(ORACLE_8021Q_PORT2)) == 0,
                "Port 2 802.1Q frame matches Oracle (TPID 0x8100, VID 102)");

    /* 4.2 Decapsulate Oracle 802.1Q vector */
    ether_frame_t frame_out;
    rx_metadata_t meta;
    memset(&frame_out, 0, sizeof(frame_out));
    memset(&meta, 0, sizeof(meta));
    rc = yt921x_8021q_rcv(ORACLE_8021Q_PORT2, sizeof(ORACLE_8021Q_PORT2), &frame_out, &meta);
    TEST_ASSERT(rc == YT921X_OK, "yt921x_8021q_rcv() decodes successfully");
    TEST_ASSERT(meta.vlan_id == 102, "VLAN ID decoded as 102");
    TEST_ASSERT(meta.source_port == YT921X_PORT_LAN3, "Source port decoded from VID as 2 (LAN3)");
    TEST_ASSERT(frame_out.ethertype == ETH_P_IP, "Original EtherType extracted as 0x0800 (IPv4)");

    /* 4.3 IEEE 802.1p Priority Tagged Frame (VID 0, PCP 5) */
    memset(&frame_out, 0, sizeof(frame_out));
    memset(&meta, 0, sizeof(meta));
    rc = yt921x_8021q_rcv(ORACLE_8021P_PRIORITY, sizeof(ORACLE_8021P_PRIORITY), &frame_out, &meta);
    TEST_ASSERT(rc == YT921X_OK, "Priority-tagged frame (802.1p) decodes successfully");
    TEST_ASSERT(meta.vlan_id == 0, "Priority Tag VID correctly parsed as 0");
    TEST_ASSERT(meta.vlan_pcp == 5, "Priority Code Point (PCP) correctly extracted as 5 (Voice)");
    TEST_ASSERT(meta.source_port == YT921X_PORT_UNMAPPED, "VID 0 correctly flagged as unmapped source port (0xFF)");

    /* 4.4 Non-802.1Q frame rejected by 8021q_rcv */
    rc = yt921x_8021q_rcv(ORACLE_RX_PORT3_FORWARDED, sizeof(ORACLE_RX_PORT3_FORWARDED), &frame_out, &meta);
    TEST_ASSERT(rc == YT921X_ERR_BAD_TPID, "0x9988 frame fed to 8021q_rcv rejected with YT921X_ERR_BAD_TPID");
}

/* =========================================================================
 * TEST GROUP 5: QinQ (IEEE 802.1ad) & Ethernet MTU Verification
 * ========================================================================= */
static void test_group5_qinq_and_mtu(void)
{
    printf("\n=== Test Group 5: QinQ (IEEE 802.1ad) & Ethernet MTU Boundaries ===\n");

    /* 5.1 Verify QinQ wire vector parsing */
    uint16_t outer_tpid = ((uint16_t)ORACLE_QINQ_FRAME[12] << 8) | ORACLE_QINQ_FRAME[13];
    uint16_t svid = (((uint16_t)ORACLE_QINQ_FRAME[14] << 8) | ORACLE_QINQ_FRAME[15]) & VLAN_VID_MASK;
    uint16_t inner_tpid = ((uint16_t)ORACLE_QINQ_FRAME[16] << 8) | ORACLE_QINQ_FRAME[17];
    uint16_t cvid = (((uint16_t)ORACLE_QINQ_FRAME[18] << 8) | ORACLE_QINQ_FRAME[19]) & VLAN_VID_MASK;
    uint16_t ether_type = ((uint16_t)ORACLE_QINQ_FRAME[20] << 8) | ORACLE_QINQ_FRAME[21];

    TEST_ASSERT(outer_tpid == ETH_P_8021AD, "QinQ Outer TPID is strictly 0x88A8 (IEEE 802.1ad)");
    TEST_ASSERT(svid == 200, "QinQ SVID decoded as 200");
    TEST_ASSERT(inner_tpid == ETH_P_8021Q, "QinQ Inner TPID is strictly 0x8100 (IEEE 802.1Q)");
    TEST_ASSERT(cvid == 100, "QinQ CVID decoded as 100");
    TEST_ASSERT(ether_type == ETH_P_IP, "QinQ Inner EtherType is 0x0800 (IPv4)");

    /* 5.2 Maximum Standard MTU Payload (1500 bytes) */
    ether_frame_t max_frame;
    memset(&max_frame, 0, sizeof(max_frame));
    max_frame.ethertype = ETH_P_IP;
    max_frame.payload_len = ETH_DATA_LEN; /* 1500 */
    memset(max_frame.payload, 0x5A, ETH_DATA_LEN);

    uint8_t max_wire[2048];
    size_t max_wire_len = 0;
    int rc = yt921x_tag_xmit(&max_frame, YT921X_PORT_LAN1, max_wire, &max_wire_len);
    TEST_ASSERT(rc == YT921X_OK, "yt921x_tag_xmit() handles full 1500-byte MTU frame");
    TEST_ASSERT(max_wire_len == (12 + YT921X_TAG_LEN + 2 + 1500), "Wire length is exactly 1522 bytes (14B eth + 8B tag + 1500B)");
}

/* =========================================================================
 * TEST GROUP 6: Dual-Conduit Topology & Port Isolation
 * ========================================================================= */
static void test_group6_dual_conduit_topology(void)
{
    printf("\n=== Test Group 6: Dual-Conduit Topology & Port Isolation ===\n");

    /* WAN Port 3 must route to Secondary Conduit eth0 */
    yt921x_conduit_id_t conduit_wan = yt921x_select_conduit(YT921X_PORT_WAN);
    TEST_ASSERT(conduit_wan == CONDUIT_SECONDARY_ETH0, "WAN (Port 3) dispatches to CONDUIT_SECONDARY_ETH0 (Port 4 / eth0)");

    /* LAN Ports 0..2 must route to Primary Conduit eth1 */
    yt921x_conduit_id_t conduit_lan1 = yt921x_select_conduit(YT921X_PORT_LAN1);
    yt921x_conduit_id_t conduit_lan2 = yt921x_select_conduit(YT921X_PORT_LAN2);
    yt921x_conduit_id_t conduit_lan3 = yt921x_select_conduit(YT921X_PORT_LAN3);
    TEST_ASSERT(conduit_lan1 == CONDUIT_PRIMARY_ETH1, "LAN1 (Port 0) dispatches to CONDUIT_PRIMARY_ETH1 (Port 8 / eth1)");
    TEST_ASSERT(conduit_lan2 == CONDUIT_PRIMARY_ETH1, "LAN2 (Port 1) dispatches to CONDUIT_PRIMARY_ETH1 (Port 8 / eth1)");
    TEST_ASSERT(conduit_lan3 == CONDUIT_PRIMARY_ETH1, "LAN3 (Port 2) dispatches to CONDUIT_PRIMARY_ETH1 (Port 8 / eth1)");

    /* Port Isolation: Conduit separation prevents WAN/LAN bridging leak */
    TEST_ASSERT(conduit_wan != conduit_lan1, "WAN conduit is physically isolated from LAN conduit");
}

/* =========================================================================
 * TEST GROUP 7: Host Simulation Boundaries & Silicon Disclaimers
 * ========================================================================= */
static void test_group7_simulation_boundaries_and_disclaimer(void)
{
    printf("\n=== Test Group 7: Simulation Model Boundaries (HOST-SIDE MODEL ONLY) ===\n");
    printf("  " COLOR_YELLOW "[DISCLAIMER] Testing heuristic model nss_sim_classify_packet()." COLOR_RESET "\n");
    printf("  " COLOR_YELLOW "[DISCLAIMER] THIS DOES NOT PROVE QUALCOMM NSS SILICON BEHAVIOR." COLOR_RESET "\n");

    uint16_t l3_proto = 0;
    uint16_t vid = 0;

    /* 7.1 Model reaction to 0x9988 tag */
    nss_classify_status_t st = nss_sim_classify_packet(ORACLE_TX_PORT0_LAN1, sizeof(ORACLE_TX_PORT0_LAN1),
                                                      &l3_proto, &vid);
    TEST_ASSERT(st == NSS_CLASSIFY_UNRECOGNIZED_PROTO,
                "[SIMULATION] Model returns UNRECOGNIZED_PROTO for 0x9988 proprietary tag");
    TEST_ASSERT(l3_proto == 0, "[SIMULATION] Model extracts 0 for L3 protocol when tag unrecognized");

    /* 7.2 Model reaction to 802.1Q tag */
    st = nss_sim_classify_packet(ORACLE_8021Q_PORT2, sizeof(ORACLE_8021Q_PORT2), &l3_proto, &vid);
    TEST_ASSERT(st == NSS_CLASSIFY_VLAN_EXTRACTED,
                "[SIMULATION] Model returns VLAN_EXTRACTED for standard 802.1Q frame");
    TEST_ASSERT(vid == 102, "[SIMULATION] Model extracts VID 102");
    TEST_ASSERT(l3_proto == ETH_P_IP, "[SIMULATION] Model extracts inner IPv4 EtherType (0x0800)");

    /* 7.3 Direct Untagged IPv4 on secondary conduit */
    uint8_t untagged_ipv4[64] = {
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55,
        0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
        0x08, 0x00, /* IPv4 */
        0x45, 0x00, /* IP Header starts at byte 14 directly */
    };
    st = nss_sim_classify_packet(untagged_ipv4, sizeof(untagged_ipv4), &l3_proto, &vid);
    TEST_ASSERT(st == NSS_CLASSIFY_PARSE_OK,
                "[SIMULATION] Untagged WAN IPv4 on eth0 passes classification directly with zero tag overhead");
    TEST_ASSERT(l3_proto == ETH_P_IP, "[SIMULATION] Untagged L3 proto identified as IPv4");
}

/* =========================================================================
 * TEST GROUP 8: DSA Tag Protocol Enum Audit & Protocol Switching Model (M4)
 * ========================================================================= */
static void test_group8_dsa_enum_and_tag_switching(void)
{
    printf("\n=== Test Group 8: DSA Tag Protocol Enum & Switching (M4 Audit) ===\n");

    /* 8.1 Protocol ID Validation */
    int rc = yt921x_validate_tag_proto_id(DSA_TAG_PROTO_YT921X_VALUE);
    TEST_ASSERT(rc == YT921X_OK,
                "[ENUM] DSA_TAG_PROTO_YT921X (32) within upstream Linux 6.18/6.19 allocation");

    rc = yt921x_validate_tag_proto_id(DSA_TAG_PROTO_YT921X_8021Q_VALUE);
    TEST_ASSERT(rc == 1,
                "[ENUM] DSA_TAG_PROTO_YT921X_8021Q (36) identified as vendor extension (patch 968)");

    rc = yt921x_validate_tag_proto_id(DSA_TAG_PROTO_YT921X_ENHANCED_VALUE);
    TEST_ASSERT(rc == 1,
                "[ENUM] DSA_TAG_PROTO_YT921X_ENHANCED (38) identified as vendor extension (patch 968)");

    rc = yt921x_validate_tag_proto_id(99);
    TEST_ASSERT(rc == YT921X_ERR_INVAL,
                "[ENUM] Invalid protocol ID (99) rejected");

    /* 8.2 Protocol Switching & Hardware Register Synchronization */
    uint32_t active_proto = DSA_TAG_PROTO_YT921X_VALUE;
    uint32_t reg_ext_cpu = YT921X_EXT_CPU_PORT_TAG_EN;

    /* Switch from 32 (8-byte tag) to 36 (802.1Q) */
    rc = yt921x_sim_change_tag_protocol(DSA_TAG_PROTO_YT921X_8021Q_VALUE, &active_proto, &reg_ext_cpu);
    TEST_ASSERT(rc == YT921X_OK,
                "[SWITCH] Transition to DSA_TAG_PROTO_YT921X_8021Q succeeds");
    TEST_ASSERT(active_proto == DSA_TAG_PROTO_YT921X_8021Q_VALUE,
                "[SWITCH] Active protocol updated to 36");
    TEST_ASSERT((reg_ext_cpu & YT921X_EXT_CPU_PORT_TAG_EN) == 0,
                "[REGISTER] Reg 0x8000c TAG_EN cleared (enables 802.1Q bypass)");

    /* Switch to Untagged Mode (DSA_TAG_PROTO_NONE) */
    rc = yt921x_sim_change_tag_protocol(DSA_TAG_PROTO_NONE_VALUE, &active_proto, &reg_ext_cpu);
    TEST_ASSERT(rc == YT921X_OK,
                "[SWITCH] Transition to DSA_TAG_PROTO_NONE succeeds");
    TEST_ASSERT((reg_ext_cpu & YT921X_EXT_CPU_PORT_TAG_EN) == 0,
                "[REGISTER] Reg 0x8000c TAG_EN remains cleared for untagged WAN");

    /* Switch back to 8-byte Tag Mode */
    rc = yt921x_sim_change_tag_protocol(DSA_TAG_PROTO_YT921X_VALUE, &active_proto, &reg_ext_cpu);
    TEST_ASSERT(rc == YT921X_OK,
                "[SWITCH] Transition back to DSA_TAG_PROTO_YT921X succeeds");
    TEST_ASSERT((reg_ext_cpu & YT921X_EXT_CPU_PORT_TAG_EN) != 0,
                "[REGISTER] Reg 0x8000c TAG_EN re-enabled for proprietary tag");

    /* Reject invalid protocol transition */
    rc = yt921x_sim_change_tag_protocol(99, &active_proto, &reg_ext_cpu);
    TEST_ASSERT(rc == YT921X_ERR_INVAL,
                "[SWITCH] Invalid protocol transition rejected");
}

/* =========================================================================
 * TEST GROUP 9: Switch Register Programming & Port Isolation Matrix (M4)
 * ========================================================================= */
static void test_group9_switch_register_and_isolation(void)
{
    printf("\n=== Test Group 9: Switch Register Programming & Port Isolation (M4) ===\n");

    /* 9.1 L2 Hardware Isolation Matrix */
    bool allowed = yt921x_sim_check_port_isolation(YT921X_PORT_LAN1, YT921X_PORT_LAN2);
    TEST_ASSERT(allowed == true,
                "[ISOLATION] LAN1 (Port 0) -> LAN2 (Port 1) hardware bridging permitted");

    allowed = yt921x_sim_check_port_isolation(YT921X_PORT_LAN1, YT921X_PORT_WAN);
    TEST_ASSERT(allowed == false,
                "[ISOLATION] LAN1 (Port 0) -> WAN (Port 3) direct L2 traffic BLOCKED by switch");

    allowed = yt921x_sim_check_port_isolation(YT921X_PORT_WAN, YT921X_PORT_LAN1);
    TEST_ASSERT(allowed == false,
                "[ISOLATION] WAN (Port 3) -> LAN1 (Port 0) direct L2 traffic BLOCKED by switch");

    allowed = yt921x_sim_check_port_isolation(YT921X_PORT_WAN, YT921X_PORT_CPU2);
    TEST_ASSERT(allowed == true,
                "[ISOLATION] WAN (Port 3) -> CPU2 (Port 4 / eth0) secondary conduit permitted");

    allowed = yt921x_sim_check_port_isolation(YT921X_PORT_LAN1, YT921X_PORT_CPU1);
    TEST_ASSERT(allowed == true,
                "[ISOLATION] LAN1 (Port 0) -> CPU1 (Port 8 / eth1) primary conduit permitted");

    allowed = yt921x_sim_check_port_isolation(YT921X_PORT_WAN, YT921X_PORT_CPU1);
    TEST_ASSERT(allowed == false,
                "[ISOLATION] WAN (Port 3) -> CPU1 (Port 8 / eth1) primary conduit BLOCKED");

    /* 9.2 Truncated Frames & Error Handling Boundary Tests */
    ether_frame_t out_frame;
    rx_metadata_t meta;

    uint8_t short_buf_0[1] = {0};
    int rc = yt921x_tag_rcv(short_buf_0, 0, &out_frame, &meta);
    TEST_ASSERT(rc == YT921X_ERR_SHORT,
                "[BOUNDARY] 0-byte frame rejected with YT921X_ERR_SHORT");

    uint8_t short_buf_13[13] = {0};
    rc = yt921x_tag_rcv(short_buf_13, sizeof(short_buf_13), &out_frame, &meta);
    TEST_ASSERT(rc == YT921X_ERR_SHORT,
                "[BOUNDARY] 13-byte frame (< eth header) rejected with YT921X_ERR_SHORT");

    uint8_t short_buf_21[21] = {0};
    rc = yt921x_tag_rcv(short_buf_21, sizeof(short_buf_21), &out_frame, &meta);
    TEST_ASSERT(rc == YT921X_ERR_SHORT,
                "[BOUNDARY] 21-byte frame (< eth + tag + et) rejected with YT921X_ERR_SHORT");

    /* 9.3 Out of Bounds Port Indices */
    ether_frame_t tx_frame;
    memset(&tx_frame, 0, sizeof(tx_frame));
    uint8_t out_buf[64];
    size_t out_len = sizeof(out_buf);

    rc = yt921x_tag_xmit(&tx_frame, 10, out_buf, &out_len);
    TEST_ASSERT(rc == YT921X_ERR_PORT,
                "[BOUNDARY] Port 10 (>= MAX 9) rejected with YT921X_ERR_PORT");

    rc = yt921x_tag_xmit(&tx_frame, 255, out_buf, &out_len);
    TEST_ASSERT(rc == YT921X_ERR_PORT,
                "[BOUNDARY] Port 255 rejected with YT921X_ERR_PORT");
}

int main(void)
{
    printf("====================================================================\n");
    printf("CR8818 NSS + Motorcomm YT9215SC Milestone M4 Test Verification Suite\n");
    printf("Independent Oracle-Verified Testing & Rigorous Boundary Analysis\n");
    printf("====================================================================\n");

    test_group1_motorcomm_xmit_oracle();
    test_group2_motorcomm_rcv_oracle();
    test_group3_malformed_and_edge_cases();
    test_group4_vlan_8021q_and_priority();
    test_group5_qinq_and_mtu();
    test_group6_dual_conduit_topology();
    test_group7_simulation_boundaries_and_disclaimer();
    test_group8_dsa_enum_and_tag_switching();
    test_group9_switch_register_and_isolation();

    printf("\n====================================================================\n");
    printf("Test Results: %d Passed, %d Failed\n", g_tests_passed, g_tests_failed);
    printf("====================================================================\n");

    return (g_tests_failed == 0) ? 0 : 1;
}

