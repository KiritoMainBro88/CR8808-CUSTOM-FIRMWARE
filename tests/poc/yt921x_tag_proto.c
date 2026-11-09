/**
 * @file yt921x_tag_proto.c
 * @brief Implementation of Motorcomm YT9215SC CPU Tagging & DSA tag_8021q NSS Prototype
 * 
 * Project: CR8808-CUSTOM-FIRMWARE (Xiaomi CR8808 Ver.B / CR8818)
 */

#include "yt921x_tag_proto.h"
#include <string.h>

/* Portable Big-Endian Helpers */
static inline uint16_t get_be16(const uint8_t *p) {
    return (uint16_t)((((uint16_t)p[0]) << 8) | ((uint16_t)p[1]));
}

static inline void put_be16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)((v >> 8) & 0xFF);
    p[1] = (uint8_t)(v & 0xFF);
}

int yt921x_tag_xmit(const ether_frame_t *in_frame, uint8_t dest_port,
                    uint8_t *out_buf, size_t *out_len)
{
    if (!in_frame || !out_buf || !out_len) return -1;
    if (dest_port >= YT921X_MAX_PORTS) return -2;

    size_t needed_len = 12 + YT921X_TAG_LEN + 2 + in_frame->payload_len;
    *out_len = needed_len;

    /* 1. Copy DMAC and SMAC (12 bytes) */
    memcpy(out_buf, in_frame->dmac, ETH_ALEN);
    memcpy(out_buf + ETH_ALEN, in_frame->smac, ETH_ALEN);

    /* 2. Write 8-byte Motorcomm CPU Tag */
    /* Byte 0-1: Tag EtherType (0x9988) */
    put_be16(out_buf + 12, YT921X_TAG_TPID_DEFAULT);
    /* Byte 2-3: VLAN field (0) */
    put_be16(out_buf + 14, 0x0000);
    /* Byte 4-5: Rx metadata (0 on Tx) */
    put_be16(out_buf + 16, 0x0000);
    /* Byte 6-7: Tx port bitmask: PORT_EN | BIT(dest_port) */
    uint16_t tx_mask = YT921X_TAG_PORT_EN | (1U << dest_port);
    put_be16(out_buf + 18, tx_mask);

    /* 3. Original EtherType (2 bytes) */
    put_be16(out_buf + 20, in_frame->ethertype);

    /* 4. Payload */
    if (in_frame->payload_len > 0) {
        memcpy(out_buf + 22, in_frame->payload, in_frame->payload_len);
    }

    return 0;
}

int yt921x_tag_rcv(const uint8_t *in_buf, size_t in_len,
                   ether_frame_t *out_frame, rx_metadata_t *meta)
{
    if (!in_buf || !out_frame || !meta) return -1;
    if (in_len < 12 + YT921X_TAG_LEN + 2) return -2;

    /* Verify Tag TPID */
    uint16_t tag_tpid = get_be16(in_buf + 12);
    if (tag_tpid != YT921X_TAG_TPID_DEFAULT) {
        return -3; /* Not a Motorcomm tagged frame */
    }

    /* Extract MACs */
    memcpy(out_frame->dmac, in_buf, ETH_ALEN);
    memcpy(out_frame->smac, in_buf + ETH_ALEN, ETH_ALEN);

    /* Parse Tag Body */
    uint16_t rx_info = get_be16(in_buf + 16);
    meta->source_port = (uint8_t)((rx_info & YT921X_TAG_RX_PORT_MASK) >> YT921X_TAG_RX_PORT_SHIFT);
    meta->forward_cmd = rx_info & YT921X_TAG_RX_CMD_MASK;
    meta->is_tagged = true;
    meta->vlan_id = get_be16(in_buf + 14);

    /* Original EtherType */
    out_frame->ethertype = get_be16(in_buf + 20);
    meta->inner_ethertype = out_frame->ethertype;

    /* Extract Payload */
    size_t payload_len = in_len - (12 + YT921X_TAG_LEN + 2);
    if (payload_len > sizeof(out_frame->payload)) {
        payload_len = sizeof(out_frame->payload);
    }
    memcpy(out_frame->payload, in_buf + 22, payload_len);
    out_frame->payload_len = payload_len;

    return 0;
}

int yt921x_8021q_xmit(const ether_frame_t *in_frame, uint8_t dest_port,
                      uint8_t *out_buf, size_t *out_len)
{
    if (!in_frame || !out_buf || !out_len) return -1;
    if (dest_port >= YT921X_MAX_PORTS) return -2;

    /* 12 (MACs) + 4 (VLAN TPID+TCI) + 2 (EtherType) + payload */
    size_t needed_len = 12 + VLAN_HLEN + 2 + in_frame->payload_len;
    *out_len = needed_len;

    /* 1. Copy DMAC and SMAC (12 bytes) */
    memcpy(out_buf, in_frame->dmac, ETH_ALEN);
    memcpy(out_buf + ETH_ALEN, in_frame->smac, ETH_ALEN);

    /* 2. Write standard 802.1Q Tag (4 bytes) */
    /* TPID = 0x8100 */
    put_be16(out_buf + 12, ETH_P_8021Q);
    /* TCI = PRIO(0) | CFI(0) | VID (Base + dest_port) */
    uint16_t vid = (uint16_t)(YT921X_8021Q_BASE_VID + dest_port);
    put_be16(out_buf + 14, vid & VLAN_VID_MASK);

    /* 3. Original EtherType (2 bytes) */
    put_be16(out_buf + 16, in_frame->ethertype);

    /* 4. Payload */
    if (in_frame->payload_len > 0) {
        memcpy(out_buf + 18, in_frame->payload, in_frame->payload_len);
    }

    return 0;
}

int yt921x_8021q_rcv(const uint8_t *in_buf, size_t in_len,
                     ether_frame_t *out_frame, rx_metadata_t *meta)
{
    if (!in_buf || !out_frame || !meta) return -1;
    if (in_len < 12 + VLAN_HLEN + 2) return -2;

    /* Verify 802.1Q TPID */
    uint16_t tpid = get_be16(in_buf + 12);
    if (tpid != ETH_P_8021Q) {
        return -3; /* Not an 802.1Q frame */
    }

    /* Extract MACs */
    memcpy(out_frame->dmac, in_buf, ETH_ALEN);
    memcpy(out_frame->smac, in_buf + ETH_ALEN, ETH_ALEN);

    /* Parse TCI / VID */
    uint16_t tci = get_be16(in_buf + 14);
    uint16_t vid = tci & VLAN_VID_MASK;
    meta->vlan_id = vid;
    meta->is_tagged = true;

    /* Map VID back to switch port */
    if (vid >= YT921X_8021Q_BASE_VID && vid < (YT921X_8021Q_BASE_VID + YT921X_MAX_PORTS)) {
        meta->source_port = (uint8_t)(vid - YT921X_8021Q_BASE_VID);
    } else {
        meta->source_port = 0xFF; /* Unknown / External VLAN */
    }

    /* Original EtherType */
    out_frame->ethertype = get_be16(in_buf + 16);
    meta->inner_ethertype = out_frame->ethertype;

    /* Extract Payload */
    size_t payload_len = in_len - (12 + VLAN_HLEN + 2);
    if (payload_len > sizeof(out_frame->payload)) {
        payload_len = sizeof(out_frame->payload);
    }
    memcpy(out_frame->payload, in_buf + 18, payload_len);
    out_frame->payload_len = payload_len;

    return 0;
}

yt921x_conduit_id_t yt921x_select_conduit(uint8_t port)
{
    /* CR8818 Dual-Conduit Mapping:
     * Port 3 (External WAN) -> Routed directly to Port 4 (cpu2 / eth0) untagged.
     * Ports 0, 1, 2 (LAN)   -> Routed to Port 8 (cpu1 / eth1) via SGMII 1000M.
     */
    if (port == YT921X_PORT_WAN) {
        return CONDUIT_SECONDARY_ETH0;
    }
    return CONDUIT_PRIMARY_ETH1;
}

nss_classify_status_t nss_sim_classify_packet(const uint8_t *buf, size_t len,
                                              uint16_t *parsed_l3_proto,
                                              uint16_t *extracted_vid)
{
    if (!buf || len < 14) return NSS_CLASSIFY_UNRECOGNIZED_PROTO;

    uint16_t ethertype = get_be16(buf + 12);

    /* 1. Proprietary Motorcomm Tag (0x9988) */
    if (ethertype == ETH_P_YT921X) {
        /* NSS firmware parser does NOT recognize 0x9988 as an L2/L3 protocol.
         * Fails HW classification; punts frame to host CPU slow-path or drops.
         */
        if (parsed_l3_proto) *parsed_l3_proto = 0;
        if (extracted_vid) *extracted_vid = 0;
        return NSS_CLASSIFY_UNRECOGNIZED_PROTO;
    }

    /* 2. Standard IEEE 802.1Q Tag (0x8100) */
    if (ethertype == ETH_P_8021Q) {
        if (len < 18) return NSS_CLASSIFY_UNRECOGNIZED_PROTO;
        uint16_t tci = get_be16(buf + 14);
        uint16_t vid = tci & VLAN_VID_MASK;
        uint16_t inner_proto = get_be16(buf + 16);

        if (extracted_vid) *extracted_vid = vid;
        if (parsed_l3_proto) *parsed_l3_proto = inner_proto;

        if (inner_proto == ETH_P_IP || inner_proto == ETH_P_IPV6) {
            return NSS_CLASSIFY_VLAN_EXTRACTED;
        }
        return NSS_CLASSIFY_PARSE_OK;
    }

    /* 3. Direct Untagged IPv4 / IPv6 */
    if (ethertype == ETH_P_IP || ethertype == ETH_P_IPV6) {
        if (extracted_vid) *extracted_vid = 0;
        if (parsed_l3_proto) *parsed_l3_proto = ethertype;
        return NSS_CLASSIFY_PARSE_OK;
    }

    return NSS_CLASSIFY_UNRECOGNIZED_PROTO;
}
