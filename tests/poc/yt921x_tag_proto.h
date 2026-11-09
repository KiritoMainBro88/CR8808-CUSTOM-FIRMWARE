/**
 * @file yt921x_tag_proto.h
 * @brief Motorcomm YT9215SC CPU Tagging & DSA tag_8021q NSS Compatibility Prototype Header
 * 
 * Project: CR8808-CUSTOM-FIRMWARE (Xiaomi CR8808 Ver.B / CR8818 / ap-mp03.3)
 * Target: Linux Kernel 6.18 / OpenWrt Mainline / Qualcomm NSS NPU Coexistence
 * 
 * Reference Sources:
 * - net/dsa/tag_yt921x.c (David Yang, upstream Linux commit ca4709843b7e / OpenWrt backport 967-02)
 * - drivers/net/dsa/yt921x.c (Motorcomm DSA driver / OpenWrt backport 967-03)
 * - zcop/immortalwrt (yt921x_8021q.c, tag_yt921x_8021q.c, yt921x_enhanced.c)
 * - kuncy7/openwrt-nss-edma (IPQ5018 NSS dwmac shim and low-memory profile)
 * 
 * CRITICAL ARCHITECTURAL DISCLAIMER:
 * Functions prefixed with 'nss_sim_' (e.g., nss_sim_classify_packet) are host-side
 * simulation/heuristic models created solely for architectural protocol flow testing.
 * They DO NOT represent actual Qualcomm NSS firmware parser microcode, DO NOT execute
 * on the NSS NPU, and DO NOT prove physical silicon behavior. Hardware compatibility
 * can only be verified on physical silicon during Phase P5.
 */

#ifndef YT921X_TAG_PROTO_H
#define YT921X_TAG_PROTO_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Standard Ethernet Constants */
#define ETH_ALEN                        6
#define ETH_HLEN                        14
#define ETH_DATA_LEN                    1500
#define ETH_FRAME_LEN                   1514
#define ETH_MIN_PAYLOAD                 46

/* EtherType Definitions */
#define ETH_P_IP                        0x0800
#define ETH_P_IPV6                      0x86dd
#define ETH_P_8021Q                     0x8100
#define ETH_P_8021AD                    0x88a8  /* IEEE 802.1ad Service Tag (QinQ) */
#define ETH_P_PPP_DISC                  0x8863  /* PPPoE Discovery */
#define ETH_P_PPP_SES                   0x8864  /* PPPoE Session */
#define ETH_P_PAUSE                     0x8808  /* Flow Control Pause */
#define ETH_P_YT921X                    0x9988  /* Hardware default Motorcomm CPU tag EtherType */

/* Motorcomm Switch Hardware Port Mapping (CR8818 Topology) */
#define YT921X_PORT_LAN1                0
#define YT921X_PORT_LAN2                1
#define YT921X_PORT_LAN3                2
#define YT921X_PORT_WAN                 3
#define YT921X_PORT_CPU2                4       /* Secondary CPU conduit (eth0 / gmac0 via Internal GE PHY) */
#define YT921X_PORT_CPU1                8       /* Primary CPU conduit (eth1 / gmac1 via Uniphy SerDes SGMII 1000M) */
#define YT921X_MAX_PORTS                9
#define YT921X_PORT_UNMAPPED            0xFF

/* Motorcomm 8-Byte CPU Tag Definitions (Bit-Accurate to Upstream net/dsa/tag_yt921x.c)
 * Wire Format:
 * +----+----+-------+-----+----+---------
 * | DA | SA | TagET | Tag | ET | Payload ...
 * +----+----+-------+-----+----+---------
 *   6    6      2      6    2       N
 *
 * TagET: 2 bytes: ETH_P_YT921X (0x9988)
 * Tag:   6 bytes:
 *   - Tag[1] (bytes 14-15): VLAN Tag field (0 on Tx)
 *   - Tag[2] (bytes 16-17): Rx Port / Metadata
 *       - bit 15:    PORT_EN (Must be 1 for valid Rx tag)
 *       - bits 14-11: RX_PORT (Port 0..8)
 *       - bits 10-0:  RX_CMD (Forwarding reason / action)
 *   - Tag[3] (bytes 18-19): Tx Port Mask
 *       - bit 15:    PORT_EN (Must be 1 for valid Tx tag)
 *       - bits 10-0:  TX_PORT Mask (BIT(port))
 * ET:    2 bytes: Original EtherType
 * Payload: starts at byte 22.
 */
#define YT921X_TAG_LEN                  8
#define YT921X_TAG_TPID_DEFAULT         0x9988

#define YT921X_TAG_PORT_EN              (1U << 15)
#define YT921X_TAG_RX_PORT_SHIFT        11
#define YT921X_TAG_RX_PORT_MASK         (0x0FU << YT921X_TAG_RX_PORT_SHIFT)  /* GENMASK(14, 11) */
#define YT921X_TAG_RX_CMD_MASK          0x07FFU                              /* GENMASK(10, 0) */
#define YT921X_TAG_TX_PORTS_MASK        0x07FFU                              /* GENMASK(10, 0) */

/* Forwarding Reason Codes (Rx from Switch to CPU) */
#define YT921X_RX_CMD_FORWARDED         0x080   /* Hardware already forwarded */
#define YT921X_RX_CMD_UNK_UCAST         0x0B2   /* Unknown unicast trap to CPU */
#define YT921X_RX_CMD_UNK_MCAST         0x0B4   /* Unknown multicast trap to CPU */

/* IEEE 802.1Q and VLAN Definitions */
#define VLAN_HLEN                       4
#define VLAN_VID_MASK                   0x0FFF
#define VLAN_PCP_SHIFT                  13
#define VLAN_PCP_MASK                   0xE000
#define VLAN_DEI_MASK                   0x1000
#define YT921X_8021Q_BASE_VID           100     /* Sub-interface VID base: port N -> VID 100 + N */

/* Return / Status Codes */
#define YT921X_OK                       0
#define YT921X_ERR_INVAL               -1       /* Invalid argument / NULL pointer */
#define YT921X_ERR_PORT                -2       /* Port out of bounds */
#define YT921X_ERR_SHORT               -3       /* Frame buffer truncated (< minimum header) */
#define YT921X_ERR_BAD_TPID            -4       /* TPID mismatch (expected 0x9988) */
#define YT921X_ERR_NO_PORT_EN          -5       /* PORT_EN bit 15 not set (malformed tag) */
#define YT921X_ERR_MTU                 -6       /* Frame payload exceeds MTU */

/* Dual-Conduit Routing Mode */
typedef enum {
    CONDUIT_PRIMARY_ETH1 = 0,   /* Port 8: SGMII 1000M / 2500M */
    CONDUIT_SECONDARY_ETH0 = 1  /* Port 4: Internal GE PHY */
} yt921x_conduit_id_t;

/* Tagging Architecture Protocol Selection */
typedef enum {
    TAG_PROTO_MOTORCOMM_PROPRIETARY = 0,    /* 8-Byte CPU Tag (TPID 0x9988) */
    TAG_PROTO_DSA_8021Q = 1,                /* IEEE 802.1Q Tag (TPID 0x8100) */
    TAG_PROTO_DUAL_CONDUIT_UNTAGGED = 2     /* Direct untagged WAN on Port 4 / eth0 */
} yt921x_tag_mode_t;

/* NSS NPU Parser Classification Simulation Status (HEURISTIC HOST-SIDE MODEL ONLY) */
typedef enum {
    NSS_CLASSIFY_PARSE_OK = 0,              /* Standard L2/L3 parsed successfully */
    NSS_CLASSIFY_UNRECOGNIZED_PROTO = 1,    /* Non-standard EtherType (e.g. 0x9988); falls back to CPU */
    NSS_CLASSIFY_VLAN_EXTRACTED = 2,        /* 802.1Q peeled and inner IP classified */
    NSS_CLASSIFY_FLOW_OFFLOADED = 3         /* ECM hardware flow table match established */
} nss_classify_status_t;

/* Frame Structure Representation */
typedef struct {
    uint8_t dmac[ETH_ALEN];
    uint8_t smac[ETH_ALEN];
    uint16_t ethertype;
    uint8_t payload[ETH_DATA_LEN];
    size_t payload_len;
} ether_frame_t;

/* Parsed Ingress Packet Metadata */
typedef struct {
    uint8_t source_port;
    uint16_t forward_cmd;
    uint16_t vlan_id;
    uint8_t vlan_pcp;
    bool vlan_dei;
    uint16_t inner_ethertype;
    bool is_tagged;
    yt921x_conduit_id_t conduit;
} rx_metadata_t;

/* API Declarations */

/**
 * Encapsulate an Ethernet frame with Motorcomm 8-byte CPU tag.
 * Egress direction: CPU -> Switch Port.
 * Returns YT921X_OK (0) on success, negative error code on failure.
 */
int yt921x_tag_xmit(const ether_frame_t *in_frame, uint8_t dest_port,
                    uint8_t *out_buf, size_t *out_len);

/**
 * Decapsulate and parse an incoming frame carrying Motorcomm 8-byte CPU tag.
 * Ingress direction: Switch Port -> CPU.
 * Returns YT921X_OK (0) on success, negative error code on failure.
 */
int yt921x_tag_rcv(const uint8_t *in_buf, size_t in_len,
                   ether_frame_t *out_frame, rx_metadata_t *meta);

/**
 * Encapsulate an Ethernet frame using DSA tag_8021q (Standard IEEE 802.1Q).
 * Egress direction: CPU -> Switch Port.
 * Returns YT921X_OK (0) on success, negative error code on failure.
 */
int yt921x_8021q_xmit(const ether_frame_t *in_frame, uint8_t dest_port,
                      uint8_t *out_buf, size_t *out_len);

/**
 * Decapsulate an incoming DSA tag_8021q Ethernet frame.
 * Ingress direction: Switch Port -> CPU.
 * Returns YT921X_OK (0) on success, negative error code on failure.
 */
int yt921x_8021q_rcv(const uint8_t *in_buf, size_t in_len,
                     ether_frame_t *out_frame, rx_metadata_t *meta);

/**
 * Dual-conduit demux decision:
 * Dispatches traffic based on destination port (WAN port 3 -> eth0, LAN ports 0..2 -> eth1).
 */
yt921x_conduit_id_t yt921x_select_conduit(uint8_t port);

/**
 * Simulate Qualcomm NSS NPU Parser classification on an incoming Ethernet packet buffer.
 * NOTE: THIS IS A HOST-SIDE ARCHITECTURAL SIMULATION MODEL ONLY.
 * It DOES NOT represent actual Qualcomm NSS firmware behavior on physical silicon.
 */
nss_classify_status_t nss_sim_classify_packet(const uint8_t *buf, size_t len,
                                              uint16_t *parsed_l3_proto,
                                              uint16_t *extracted_vid);

#ifdef __cplusplus
}
#endif

#endif /* YT921X_TAG_PROTO_H */
