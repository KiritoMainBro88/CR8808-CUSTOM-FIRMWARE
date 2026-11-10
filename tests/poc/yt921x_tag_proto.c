/**
 * @file yt921x_tag_proto.c
 * @brief Implementation of Motorcomm YT9215SC CPU Tagging & DSA tag_8021q NSS Prototype
 * 
 * Project: CR8808-CUSTOM-FIRMWARE (Xiaomi CR8808 Ver.B / CR8818)
 * 
 * Complies with upstream Linux net/dsa/tag_yt921x.c (commit ca4709843b7e / OpenWrt 967-02)
 */

#include "yt921x_tag_proto.h"
#include <string.h>

/* Portable Big-Endian Network Byte Order Helpers */
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
    if (!in_frame || !out_buf || !out_len) return YT921X_ERR_INVAL;
    if (dest_port >= YT921X_MAX_PORTS) return YT921X_ERR_PORT;
    if (in_frame->payload_len > ETH_DATA_LEN) return YT921X_ERR_MTU;

    size_t needed_len = 12 + YT921X_TAG_LEN + 2 + in_frame->payload_len;
    *out_len = needed_len;

    /* 1. Copy DMAC and SMAC (12 bytes) */
    memcpy(out_buf, in_frame->dmac, ETH_ALEN);
    memcpy(out_buf + ETH_ALEN, in_frame->smac, ETH_ALEN);

    /* 2. Write 8-byte Motorcomm Extended CPU Tag (Upstream tag_yt921x format) */
    /* TagET (bytes 12-13): TPID default 0x9988 */
    put_be16(out_buf + 12, YT921X_TAG_TPID_DEFAULT);

    /* Tag[1] (bytes 14-15): VLAN Tag field (0x0000 on TX) */
    put_be16(out_buf + 14, 0x0000);

    /* Tag[2] (bytes 16-17): Rx Port metadata (0x0000 on TX) */
    put_be16(out_buf + 16, 0x0000);

    /* Tag[3] (bytes 18-19): Tx Port Mask: PORT_EN (bit 15) | BIT(dest_port) */
    uint16_t tx_mask = YT921X_TAG_PORT_EN | (uint16_t)(1U << dest_port);
    put_be16(out_buf + 18, tx_mask);

    /* 3. Encapsulated Original EtherType (bytes 20-21) */
    put_be16(out_buf + 20, in_frame->ethertype);

    /* 4. Payload (starts at byte 22) */
    if (in_frame->payload_len > 0) {
        memcpy(out_buf + 22, in_frame->payload, in_frame->payload_len);
    }

    return YT921X_OK;
}

int yt921x_tag_rcv(const uint8_t *in_buf, size_t in_len,
                   ether_frame_t *out_frame, rx_metadata_t *meta)
{
    if (!in_buf || !out_frame || !meta) return YT921X_ERR_INVAL;

    /* Minimum length required: 12 (MACs) + 8 (Tag) + 2 (EtherType) = 22 bytes */
    if (in_len < 12 + YT921X_TAG_LEN + 2) return YT921X_ERR_SHORT;

    /* Verify Tag TPID (Byte 12-13) */
    uint16_t tag_tpid = get_be16(in_buf + 12);
    if (tag_tpid != YT921X_TAG_TPID_DEFAULT) {
        return YT921X_ERR_BAD_TPID;
    }

    /* Extract MACs */
    memcpy(out_frame->dmac, in_buf, ETH_ALEN);
    memcpy(out_frame->smac, in_buf + ETH_ALEN, ETH_ALEN);

    /* Parse Tag Body */
    /* Tag[1] (bytes 14-15): VLAN */
    meta->vlan_id = get_be16(in_buf + 14);

    /* Tag[2] (bytes 16-17): Rx Info */
    uint16_t rx_info = get_be16(in_buf + 16);

    /* Check PORT_EN (bit 15) - upstream tag_yt921x requires this */
    if ((rx_info & YT921X_TAG_PORT_EN) == 0) {
        return YT921X_ERR_NO_PORT_EN;
    }

    uint8_t port = (uint8_t)((rx_info & YT921X_TAG_RX_PORT_MASK) >> YT921X_TAG_RX_PORT_SHIFT);
    if (port >= YT921X_MAX_PORTS) {
        return YT921X_ERR_PORT;
    }
    meta->source_port = port;
    meta->forward_cmd = rx_info & YT921X_TAG_RX_CMD_MASK;
    meta->is_tagged = true;

    /* Original EtherType (bytes 20-21) */
    out_frame->ethertype = get_be16(in_buf + 20);
    meta->inner_ethertype = out_frame->ethertype;

    /* Extract Payload */
    size_t payload_len = in_len - (12 + YT921X_TAG_LEN + 2);
    if (payload_len > sizeof(out_frame->payload)) {
        payload_len = sizeof(out_frame->payload);
    }
    memcpy(out_frame->payload, in_buf + 22, payload_len);
    out_frame->payload_len = payload_len;

    return YT921X_OK;
}

int yt921x_8021q_xmit(const ether_frame_t *in_frame, uint8_t dest_port,
                      uint8_t *out_buf, size_t *out_len)
{
    if (!in_frame || !out_buf || !out_len) return YT921X_ERR_INVAL;
    if (dest_port >= YT921X_MAX_PORTS) return YT921X_ERR_PORT;
    if (in_frame->payload_len > ETH_DATA_LEN) return YT921X_ERR_MTU;

    /* 12 (MACs) + 4 (VLAN TPID+TCI) + 2 (EtherType) + payload */
    size_t needed_len = 12 + VLAN_HLEN + 2 + in_frame->payload_len;
    *out_len = needed_len;

    /* 1. Copy DMAC and SMAC (12 bytes) */
    memcpy(out_buf, in_frame->dmac, ETH_ALEN);
    memcpy(out_buf + ETH_ALEN, in_frame->smac, ETH_ALEN);

    /* 2. Write standard 802.1Q Tag (4 bytes) */
    put_be16(out_buf + 12, ETH_P_8021Q);
    uint16_t vid = (uint16_t)(YT921X_8021Q_BASE_VID + dest_port);
    put_be16(out_buf + 14, vid & VLAN_VID_MASK);

    /* 3. Original EtherType (2 bytes) */
    put_be16(out_buf + 16, in_frame->ethertype);

    /* 4. Payload */
    if (in_frame->payload_len > 0) {
        memcpy(out_buf + 18, in_frame->payload, in_frame->payload_len);
    }

    return YT921X_OK;
}

int yt921x_8021q_rcv(const uint8_t *in_buf, size_t in_len,
                     ether_frame_t *out_frame, rx_metadata_t *meta)
{
    if (!in_buf || !out_frame || !meta) return YT921X_ERR_INVAL;
    if (in_len < 12 + VLAN_HLEN + 2) return YT921X_ERR_SHORT;

    /* Verify 802.1Q TPID */
    uint16_t tpid = get_be16(in_buf + 12);
    if (tpid != ETH_P_8021Q) {
        return YT921X_ERR_BAD_TPID;
    }

    /* Extract MACs */
    memcpy(out_frame->dmac, in_buf, ETH_ALEN);
    memcpy(out_frame->smac, in_buf + ETH_ALEN, ETH_ALEN);

    /* Parse TCI / VID / PCP / DEI */
    uint16_t tci = get_be16(in_buf + 14);
    uint16_t vid = tci & VLAN_VID_MASK;
    meta->vlan_id = vid;
    meta->vlan_pcp = (uint8_t)((tci & VLAN_PCP_MASK) >> VLAN_PCP_SHIFT);
    meta->vlan_dei = (tci & VLAN_DEI_MASK) != 0;
    meta->is_tagged = true;

    /* Map VID back to switch port */
    if (vid >= YT921X_8021Q_BASE_VID && vid < (YT921X_8021Q_BASE_VID + YT921X_MAX_PORTS)) {
        meta->source_port = (uint8_t)(vid - YT921X_8021Q_BASE_VID);
    } else {
        meta->source_port = YT921X_PORT_UNMAPPED; /* Priority Tag (VID 0) or External Customer VID */
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

    return YT921X_OK;
}

yt921x_conduit_id_t yt921x_select_conduit(uint8_t port)
{
    /* CR8818 Dual-Conduit Mapping:
     * Port 3 (External WAN) -> Routed directly to Port 4 (cpu2 / eth0) untagged.
     * Ports 0, 1, 2 (LAN)   -> Routed to Port 8 (cpu1 / eth1) via SGMII 1000M / 2500M.
     */
    if (port == YT921X_PORT_WAN) {
        return CONDUIT_SECONDARY_ETH0;
    }
    return CONDUIT_PRIMARY_ETH1;
}

/**
 * =========================================================================
 * HEURISTIC HOST-SIDE SIMULATION MODEL ONLY
 * =========================================================================
 * The following function models the theoretical behavior of an L2 parser:
 * - Recognizes IEEE standard EtherTypes (IPv4, IPv6, 802.1Q).
 * - Rejects non-standard proprietary EtherTypes (such as 0x9988).
 * 
 * WARNING: THIS IS A CPU MODEL FOR TESTING ARCHITECTURAL HYPOTHESES ONLY.
 * IT DOES NOT EXECUTE QUALCOMM NSS FIRMWARE MICROCODE.
 * IT DOES NOT PROVE WHETHER REAL QUALCOMM NSS SILICON ACCEPTS OR REJECTS 0x9988.
 */
nss_classify_status_t nss_sim_classify_packet(const uint8_t *buf, size_t len,
                                              uint16_t *parsed_l3_proto,
                                              uint16_t *extracted_vid)
{
    if (!buf || len < 14) {
        if (parsed_l3_proto) *parsed_l3_proto = 0;
        if (extracted_vid) *extracted_vid = 0;
        return NSS_CLASSIFY_UNRECOGNIZED_PROTO;
    }

    uint16_t ethertype = get_be16(buf + 12);

    /* 1. Proprietary Motorcomm Tag (0x9988) */
    if (ethertype == ETH_P_YT921X) {
        /* Heuristic model: NSS firmware expected to fail classification on 0x9988 */
        if (parsed_l3_proto) *parsed_l3_proto = 0;
        if (extracted_vid) *extracted_vid = 0;
        return NSS_CLASSIFY_UNRECOGNIZED_PROTO;
    }

    /* 2. Standard IEEE 802.1Q Tag (0x8100) */
    if (ethertype == ETH_P_8021Q) {
        if (len < 18) {
            if (parsed_l3_proto) *parsed_l3_proto = 0;
            if (extracted_vid) *extracted_vid = 0;
            return NSS_CLASSIFY_UNRECOGNIZED_PROTO;
        }
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

    if (parsed_l3_proto) *parsed_l3_proto = ethertype;
    if (extracted_vid) *extracted_vid = 0;
    return NSS_CLASSIFY_UNRECOGNIZED_PROTO;
}

int yt921x_validate_tag_proto_id(uint32_t proto_id)
{
    /* Upstream Linux 6.18 allocation boundary is 0..32 */
    if (proto_id <= 32) {
        return YT921X_OK;
    }
    /* zcop out-of-tree vendor allocation range (patch 968) */
    if (proto_id >= 36 && proto_id <= 38) {
        return 1; /* Valid vendor extension, unallocated in upstream mainline */
    }
    return YT921X_ERR_INVAL;
}

int yt921x_sim_change_tag_protocol(uint32_t new_proto, uint32_t *active_proto, uint32_t *reg_ext_cpu)
{
    if (!active_proto || !reg_ext_cpu) {
        return YT921X_ERR_INVAL;
    }

    if (new_proto == DSA_TAG_PROTO_YT921X_VALUE) {
        /* Proprietary 8-byte tag mode: hardware MUST enable CPU port tag */
        *active_proto = new_proto;
        *reg_ext_cpu |= YT921X_EXT_CPU_PORT_TAG_EN;
        return YT921X_OK;
    }

    if (new_proto == DSA_TAG_PROTO_YT921X_8021Q_VALUE ||
        new_proto == DSA_TAG_PROTO_NONE_VALUE) {
        /* 802.1Q or untagged mode: hardware CPU port tag enforcement must be CLEARED */
        *active_proto = new_proto;
        *reg_ext_cpu &= ~YT921X_EXT_CPU_PORT_TAG_EN;
        return YT921X_OK;
    }

    return YT921X_ERR_INVAL;
}

bool yt921x_sim_check_port_isolation(uint8_t src_port, uint8_t dst_port)
{
    /* Validation of bounds */
    if (src_port >= YT921X_MAX_PORTS || dst_port >= YT921X_MAX_PORTS) {
        return false;
    }
    if (src_port == dst_port) {
        return false; /* No hairpin unless explicit */
    }

    /* LAN ports: 0, 1, 2 */
    bool src_is_lan = (src_port <= YT921X_PORT_LAN3);
    bool dst_is_lan = (dst_port <= YT921X_PORT_LAN3);
    bool src_is_wan = (src_port == YT921X_PORT_WAN);
    bool dst_is_wan = (dst_port == YT921X_PORT_WAN);

    /* Hardware Isolation Policy: LAN <-> WAN direct L2 forwarding is strictly FORBIDDEN */
    if ((src_is_lan && dst_is_wan) || (src_is_wan && dst_is_lan)) {
        return false;
    }

    /* CPU Conduit Access */
    if (src_is_lan && dst_port == YT921X_PORT_CPU1) return true;  /* LAN to eth1 */
    if (src_is_wan && dst_port == YT921X_PORT_CPU2) return true;  /* WAN to eth0 */
    if (src_port == YT921X_PORT_CPU1 && dst_is_lan) return true;  /* eth1 to LAN */
    if (src_port == YT921X_PORT_CPU2 && dst_is_wan) return true;  /* eth0 to WAN */

    /* LAN to LAN bridging within switch */
    if (src_is_lan && dst_is_lan) return true;

    return false;
}

