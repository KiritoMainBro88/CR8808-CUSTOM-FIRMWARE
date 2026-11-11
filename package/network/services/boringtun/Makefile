# SPDX-License-Identifier: BSD-3-Clause
#
# OpenWrt Package Makefile for Cloudflare BoringTun (Rust WireGuard Userspace Daemon)
# Project: CR8808-CUSTOM-FIRMWARE (Xiaomi CR8808 Ver.B / IPQ5018)

include $(TOPDIR)/rules.mk

PKG_NAME:=boringtun
PKG_VERSION:=0.7.1
PKG_RELEASE:=1

PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=LICENSE.md
PKG_MAINTAINER:=Gemini Engineering Team

include $(INCLUDE_DIR)/package.mk

define Package/boringtun
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Cloudflare BoringTun Userspace WireGuard Daemon (Rust AArch64 Static)
  DEPENDS:=+kmod-tun +wireguard-tools
  URL:=https://github.com/cloudflare/boringtun
endef

define Package/boringtun/description
  BoringTun is an implementation of the WireGuard protocol designed for
  portability and speed, written in Rust. It serves as the primary
  WireGuard userspace daemon for CR8818, replacing wireguard-go.
  Cross-compiled statically for ARM64 Cortex-A53 with Issue #498 in-place patch.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/boringtun/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/boringtun-cli-aarch64 $(1)/usr/bin/boringtun
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/boringtun.init $(1)/etc/init.d/boringtun
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/boringtun.config $(1)/etc/config/boringtun
	$(INSTALL_DIR) $(1)/lib/netifd/proto
	$(INSTALL_BIN) ./files/wireguard_boringtun.sh $(1)/lib/netifd/proto/wireguard_boringtun.sh
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/boringtun_watchdog $(1)/usr/bin/boringtun_watchdog
endef

$(eval $(call BuildPackage,boringtun))
