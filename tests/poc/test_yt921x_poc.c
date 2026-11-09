/**
 * @file test_yt921x_poc.c
 * @brief Unit Test Suite for Motorcomm YT9215SC CPU Tagging & NSS Compatibility Prototype
 * 
 * Project: CR8808-CUSTOM-FIRMWARE (Xiaomi CR8808 Ver.B / CR8818)
 */

#include "yt921x_tag_proto.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#define COLOR_GREEN "\033[32m"
#define COLOR_RED   "\033[31m"
#define COLOR_YELLOW "\033[33m"
#define COLOR_RESET "\033[0m"

static int g_tests_passed = 0;
static int g_tests_failed = 0;

#define TEST_ASSERT(cond, msg) do { \
    if (cond) { \
        printf("  [PASS] %s\n", msg); \
        g_tests_passed++; \
    } else { \
        printf("  " COLOR_RED "[FAIL] %s" COLOR_RESET " (Line %d)\n", msg, __LINE__); \
        g_tests_failed++; \
    } \
} while(0)

/* Test 1: Motorcomm 8-byte CPU tag transmission and reception */
static void test_motorcomm_8byte_tag(void)
{
    printf("\n=== Test 1: Motorcomm 8-Byte Proprietary CPU Tag (TPID 0x9988) ===\n");

    ether_frame_t frame_in;
    memset(&frame_in, 0, sizeof(frame_in));
    memcpy(frame_in.dmac, "\x00\x11\x22\x33\x44\x55", ETH_ALEN);
    memcpy(frame_in.smac, "\xaa\xbb\xcc\xdd\xee\xff", ETH_ALEN);
    frame_in.ethertype = ETH_P_IP;
    const char *payload_text = "CR8818 IPv4 UDP Test Packet on LAN1";
    frame_in.payload_len = strlen(payload_text);
    memcpy(frame_in.payload, payload_text, frame_in.payload_len);

    uint8_t wire_buf[2048];
    size_t wire_len = 0;

    /* Transmit on LAN1 (Port 0) */
    int rc = yt921x_tag_xmit(&frame_in, YT921X_PORT_LAN1, wire_buf, &wire_len);
    TEST_ASSERT(rc == 0, "yt921x_tag_xmit() returns 0 for Port 0");
    TEST_ASSERT(wire_len == (12 + YT921X_TAG_LEN + 2 + frame_in.payload_len), "Encapsulated length matches 8-byte tag format");

    /* Validate wire bytes */
    uint16_t tag_tpid = ((uint16_t)wire_buf[12] << 8) | wire_buf[13];
    TEST_ASSERT(tag_tpid == 0x9988, "Byte 12-13 is strictly TPID 0x9988 (ETH_P_YT921X)");

    uint16_t tx_mask = ((uint16_t)wire_buf[18] << 8) | wire_buf[19];
    TEST_ASSERT(tx_mask == (YT921X_TAG_PORT_EN | (1U << YT921X_PORT_LAN1)), "Tx port bitmask has PORT_EN and BIT(0)");

    /* Simulate switch RX: construct Rx tag from Port 3 (WAN) */
    uint8_t rx_wire[2048];
    size_t rx_len = wire_len;
    memcpy(rx_wire, wire_buf, wire_len);
    /* Set Rx Port 3 and FORWARDED command in byte 16-17 */
    uint16_t rx_info = (YT921X_PORT_WAN << YT921X_TAG_RX_PORT_SHIFT) | YT921X_RX_CMD_FORWARDED;
    rx_wire[16] = (uint8_t)((rx_info >> 8) & 0xFF);
    rx_wire[17] = (uint8_t)(rx_info & 0xFF);

    ether_frame_t frame_out;
    rx_metadata_t meta;
    memset(&frame_out, 0, sizeof(frame_out));
    memset(&meta, 0, sizeof(meta));

    rc = yt921x_tag_rcv(rx_wire, rx_len, &frame_out, &meta);
    TEST_ASSERT(rc == 0, "yt921x_tag_rcv() decodes successfully");
    TEST_ASSERT(meta.source_port == YT921X_PORT_WAN, "Metadata source port decoded as 3 (WAN)");
    TEST_ASSERT(meta.forward_cmd == YT921X_RX_CMD_FORWARDED, "Metadata command decoded as FORWARDED");
    TEST_ASSERT(frame_out.ethertype == ETH_P_IP, "Original EtherType extracted as 0x0800 (IPv4)");
    TEST_ASSERT(frame_out.payload_len == frame_in.payload_len, "Decapsulated payload length matches");
    TEST_ASSERT(memcmp(frame_out.payload, frame_in.payload, frame_in.payload_len) == 0, "Payload contents intact");
}

/* Test 2: NSS Parser Simulation on Motorcomm Tag */
static void test_nss_simulation_motorcomm_collision(void)
{
    printf("\n=== Test 2: Qualcomm NSS Firmware Parser Simulation on Motorcomm Tag ===\n");

    ether_frame_t frame_in;
    memset(&frame_in, 0, sizeof(frame_in));
    frame_in.ethertype = ETH_P_IP;
    frame_in.payload_len = 64;

    uint8_t wire_buf[2048];
    size_t wire_len = 0;
    yt921x_tag_xmit(&frame_in, YT921X_PORT_LAN2, wire_buf, &wire_len);

    uint16_t l3_proto = 0;
    uint16_t vid = 0;
    nss_classify_status_t status = nss_sim_classify_packet(wire_buf, wire_len, &l3_proto, &vid);

    TEST_ASSERT(status == NSS_CLASSIFY_UNRECOGNIZED_PROTO,
                "NSS silicon parser rejects 0x9988 tag as UNRECOGNIZED_PROTO");
    TEST_ASSERT(l3_proto == 0, "L3 header extraction fails due to 8-byte tag offset mismatch");
    printf("  " COLOR_YELLOW "-> Verified: Frame with 0x9988 cannot be accelerated by NSS firmware directly." COLOR_RESET "\n");
}

/* Test 3: DSA tag_8021q Transmission and Reception */
static void test_dsa_tag_8021q(void)
{
    printf("\n=== Test 3: DSA tag_8021q Adapter (Standard IEEE 802.1Q TPID 0x8100) ===\n");

    ether_frame_t frame_in;
    memset(&frame_in, 0, sizeof(frame_in));
    memcpy(frame_in.dmac, "\x00\xaa\xbb\xcc\xdd\xee", ETH_ALEN);
    memcpy(frame_in.smac, "\x11\x22\x33\x44\x55\x66", ETH_ALEN);
    frame_in.ethertype = ETH_P_IP;
    const char *payload_text = "CR8818 tag_8021q VLAN-encapsulated packet";
    frame_in.payload_len = strlen(payload_text);
    memcpy(frame_in.payload, payload_text, frame_in.payload_len);

    uint8_t wire_buf[2048];
    size_t wire_len = 0;

    /* Transmit targeting LAN3 (Port 2) -> Should be VID 102 */
    int rc = yt921x_8021q_xmit(&frame_in, YT921X_PORT_LAN3, wire_buf, &wire_len);
    TEST_ASSERT(rc == 0, "yt921x_8021q_xmit() succeeds for Port 2");
    TEST_ASSERT(wire_len == (12 + VLAN_HLEN + 2 + frame_in.payload_len), "Frame length matches 802.1Q tagged frame (12B MAC + 4B VLAN + 2B Proto + Payload)");

    uint16_t tpid = ((uint16_t)wire_buf[12] << 8) | wire_buf[13];
    TEST_ASSERT(tpid == ETH_P_8021Q, "Byte 12-13 is standard 802.1Q TPID 0x8100");

    uint16_t tci = ((uint16_t)wire_buf[14] << 8) | wire_buf[15];
    uint16_t vid = tci & VLAN_VID_MASK;
    TEST_ASSERT(vid == (YT921X_8021Q_BASE_VID + YT921X_PORT_LAN3), "VLAN ID encodes switch port: VID = 100 + 2 = 102");

    ether_frame_t frame_out;
    rx_metadata_t meta;
    memset(&frame_out, 0, sizeof(frame_out));
    memset(&meta, 0, sizeof(meta));

    rc = yt921x_8021q_rcv(wire_buf, wire_len, &frame_out, &meta);
    TEST_ASSERT(rc == 0, "yt921x_8021q_rcv() decapsulates successfully");
    TEST_ASSERT(meta.source_port == YT921X_PORT_LAN3, "Source port decoded from VID as 2 (LAN3)");
    TEST_ASSERT(frame_out.ethertype == ETH_P_IP, "Inner EtherType preserved as 0x0800 (IPv4)");
    TEST_ASSERT(frame_out.payload_len == frame_in.payload_len, "Payload size preserved");
    TEST_ASSERT(memcmp(frame_out.payload, frame_in.payload, frame_in.payload_len) == 0, "Payload content preserved");
}

/* Test 4: NSS Parser Simulation on tag_8021q */
static void test_nss_simulation_tag_8021q_success(void)
{
    printf("\n=== Test 4: Qualcomm NSS Firmware Parser Simulation on tag_8021q Frame ===\n");

    ether_frame_t frame_in;
    memset(&frame_in, 0, sizeof(frame_in));
    frame_in.ethertype = ETH_P_IP;
    frame_in.payload_len = 128;

    uint8_t wire_buf[2048];
    size_t wire_len = 0;
    yt921x_8021q_xmit(&frame_in, YT921X_PORT_LAN1, wire_buf, &wire_len);

    uint16_t l3_proto = 0;
    uint16_t vid = 0;
    nss_classify_status_t status = nss_sim_classify_packet(wire_buf, wire_len, &l3_proto, &vid);

    TEST_ASSERT(status == NSS_CLASSIFY_VLAN_EXTRACTED,
                "NSS silicon parser natively extracts 802.1Q VLAN tag");
    TEST_ASSERT(vid == 100, "VLAN ID 100 extracted for sub-interface mapping");
    TEST_ASSERT(l3_proto == ETH_P_IP, "L3 protocol correctly identified as 0x0800 (IPv4)");
    printf("  " COLOR_GREEN "-> Confirmed: tag_8021q solves NSS packet classification collision!" COLOR_RESET "\n");
}

/* Test 5: Dual-Conduit Demux Verification */
static void test_dual_conduit_demux(void)
{
    printf("\n=== Test 5: Dual-Conduit Topology Routing Verification ===\n");

    yt921x_conduit_id_t conduit_wan = yt921x_select_conduit(YT921X_PORT_WAN);
    TEST_ASSERT(conduit_wan == CONDUIT_SECONDARY_ETH0,
                "Physical WAN (Port 3) maps to Secondary Conduit eth0 (Port 4 via Internal GE PHY)");

    yt921x_conduit_id_t conduit_lan1 = yt921x_select_conduit(YT921X_PORT_LAN1);
    yt921x_conduit_id_t conduit_lan2 = yt921x_select_conduit(YT921X_PORT_LAN2);
    yt921x_conduit_id_t conduit_lan3 = yt921x_select_conduit(YT921X_PORT_LAN3);

    TEST_ASSERT(conduit_lan1 == CONDUIT_PRIMARY_ETH1, "LAN1 (Port 0) maps to Primary Conduit eth1 (Port 8 via SGMII 1000M)");
    TEST_ASSERT(conduit_lan2 == CONDUIT_PRIMARY_ETH1, "LAN2 (Port 1) maps to Primary Conduit eth1 (Port 8 via SGMII 1000M)");
    TEST_ASSERT(conduit_lan3 == CONDUIT_PRIMARY_ETH1, "LAN3 (Port 2) maps to Primary Conduit eth1 (Port 8 via SGMII 1000M)");

    /* Verify untagged WAN packet on eth0 directly enters NSS parser */
    ether_frame_t wan_frame;
    memset(&wan_frame, 0, sizeof(wan_frame));
    wan_frame.ethertype = ETH_P_IP;
    wan_frame.payload_len = 64;

    uint8_t untagged_buf[1514];
    memcpy(untagged_buf, wan_frame.dmac, ETH_ALEN);
    memcpy(untagged_buf + ETH_ALEN, wan_frame.smac, ETH_ALEN);
    untagged_buf[12] = 0x08;
    untagged_buf[13] = 0x00;
    memcpy(untagged_buf + 14, wan_frame.payload, wan_frame.payload_len);
    size_t untagged_len = 14 + wan_frame.payload_len;

    uint16_t l3_proto = 0;
    uint16_t vid = 0;
    nss_classify_status_t status = nss_sim_classify_packet(untagged_buf, untagged_len, &l3_proto, &vid);
    TEST_ASSERT(status == NSS_CLASSIFY_PARSE_OK, "Untagged WAN frame on eth0 parses cleanly with zero CPU tag overhead");
    TEST_ASSERT(l3_proto == ETH_P_IP, "WAN L3 proto identified as IPv4");
}

int main(void)
{
    printf("====================================================================\n");
    printf("CR8818 NSS + Motorcomm YT9215SC PoC Verification Suite (M2 Milestone)\n");
    printf("Target: Xiaomi CR8808 Ver.B / IPQ5018 / Kernel 6.18 / NSS 12.5\n");
    printf("====================================================================\n");

    test_motorcomm_8byte_tag();
    test_nss_simulation_motorcomm_collision();
    test_dsa_tag_8021q();
    test_nss_simulation_tag_8021q_success();
    test_dual_conduit_demux();

    printf("\n====================================================================\n");
    printf("Test Results: %d Passed, %d Failed\n", g_tests_passed, g_tests_failed);
    printf("====================================================================\n");

    return (g_tests_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}
