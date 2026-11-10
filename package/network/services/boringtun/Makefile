# SPDX-License-Identifier: BSD-3-Clause
#
# OpenWrt Package Makefile for Cloudflare BoringTun (Rust WireGuard Userspace Daemon)
# Project: CR8808-CUSTOM-FIRMWARE (Xiaomi CR8808 Ver.B / IPQ5018)

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/rust-values.mk

PKG_NAME:=boringtun
PKG_VERSION:=0.7.1
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/cloudflare/boringtun/archive/refs/tags/boringtun-cli-$(PKG_VERSION).tar.gz?
PKG_HASH:=0bfce9717e898533036c853e3433308770d9cd0a5f54b10e9d90f149947e355c
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-boringtun-cli-$(PKG_VERSION)

PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=LICENSE.md
PKG_MAINTAINER:=Gemini Engineering Team

PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/rust-package.mk

define Package/boringtun
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Cloudflare BoringTun Userspace WireGuard Daemon (Rust)
  DEPENDS:=$(RUST_ARCH_DEPENDS) +kmod-tun +wireguard-tools
  URL:=https://github.com/cloudflare/boringtun
endef

define Package/boringtun/description
  BoringTun is an implementation of the WireGuard protocol designed for
  portability and speed, written in Rust. It serves as the primary
  WireGuard userspace daemon for CR8818, replacing wireguard-go.
endef

# Build the boringtun-cli binary with Cortex-A53 vectorization and musl static runtime
CARGO_PKG_BUILD_DIR:=boringtun-cli
CARGO_BUILD_FLAGS += --package boringtun-cli

CARGO_PKG_VARS += \
	RUSTFLAGS="-C target-cpu=cortex-a53 -C panic=abort -C codegen-units=1 -C target-feature=+crt-static"

define Package/boringtun/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/boringtun-cli $(1)/usr/bin/boringtun
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/boringtun.init $(1)/etc/init.d/boringtun
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/boringtun.config $(1)/etc/config/boringtun
	$(INSTALL_DIR) $(1)/lib/netifd/proto
	$(INSTALL_BIN) ./files/wireguard_boringtun.sh $(1)/lib/netifd/proto/wireguard_boringtun.sh
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/boringtun_watchdog $(1)/usr/bin/boringtun_watchdog
endef

$(eval $(call RustBinPackage,boringtun))
$(eval $(call BuildPackage,boringtun))
