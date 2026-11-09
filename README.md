# CR8808-CUSTOM-FIRMWARE

**Project type:** Custom router firmware engineering  
**Target product:** Xiaomi CR8808 Ver.B  
**Initial version:** `0.1.0-dev.2`  
**Current phase:** `P0 – Initiation / P1 – Discovery`  
**Flash status:** **NO-GO**

Đây là repository tích hợp firmware có quản lý yêu cầu, kiến trúc, upstream, patch, kiểm thử và phát hành. Mục tiêu là tạo một nền tảng có thể bảo trì lâu dài cho đúng phần cứng CR8808 Ver.B, không phải chỉ build một image chạy được.

## 1. Mục tiêu sản phẩm

- Xác minh đúng phần cứng CR8808 Ver.B trước khi chọn target.
- Duy trì các chức năng người dùng đang sử dụng trên Xiaomi RA82 v1.4.31; mọi khác biệt phải được liệt kê.
- Giữ Wi-Fi 5 GHz HE160/160 MHz.
- Ethernet, WAN, VLAN, switch và Wi-Fi phải hoạt động đúng trên thiết bị thật.
- Nghiên cứu Qualcomm NSS offload và chỉ tích hợp khi chứng minh được tính tương thích, hiệu quả và độ ổn định.
- Chuyển WireGuard từ Go sang BoringTun Rust; mục tiêu cuối cùng là Rust-only sau khi nghiệm thu, không giữ Go làm dịch vụ thường trực.
- Tối ưu sâu RAM, CPU, IRQ/SoftIRQ, networking, QoS/SQM, Wi-Fi và VPN dựa trên baseline và benchmark.
- Có quy trình cập nhật upstream, build tái lập, regression test và rollback.

## 2. Quy tắc không thể vi phạm

1. Không flash, sysupgrade, ghi MTD/NAND, bootloader, NVRAM, bootconfig hoặc partition table trong P0/P1.
2. Không reboot, restart service hoặc thay đổi cấu hình router trong P0/P1.
3. Không làm gián đoạn LAN/Internet mà PC đang dùng để truy cập AI.
4. Không sửa, reset, xóa hoặc đổi tên `D:\vibecode\test_wifi`.
5. Repository sản phẩm duy nhất là `D:\vibecode\CR8808-CUSTOM-FIRMWARE`.
6. Không coi dual-boot/A-B là bảo đảm chống brick.
7. Không tuyên bố tương thích 100%, NSS hoạt động, hoặc feature parity nếu chưa có bằng chứng.
8. Không merge nguyên repo upstream một cách mù quáng.
9. Không tự ý xóa Go WireGuard trước khi Rust được nghiệm thu và có rollback đã kiểm chứng.
10. Không thực hiện hành động router-side có tác động nếu chưa có phê duyệt rõ ràng cho đúng hành động đó.

## 3. Bắt đầu

1. Đọc `AGENTS.md`.
2. Đọc `GEMINI.md`.
3. Đọc toàn bộ `docs/`.
4. Đọc `PROJECT_STATUS.md` và `TASKS.md`.
5. Chỉ thực hiện task đang ở trạng thái `READY`.

## 4. Cấu trúc repository

```text
CR8808-CUSTOM-FIRMWARE/
├── AGENTS.md
├── GEMINI.md
├── README.md
├── PROJECT_STATUS.md
├── TASKS.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CHANGELOG.md
├── docs/
│   ├── 00_PROJECT_CHARTER.md
│   ├── 01_USER_REQUIREMENTS.md
│   ├── 02_DEVICE_BASELINE.md
│   ├── 03_SYSTEM_ARCHITECTURE.md
│   ├── 04_SOURCE_GOVERNANCE.md
│   ├── 05_RISK_REGISTER.md
│   ├── 06_TEST_STRATEGY.md
│   ├── 07_RELEASE_AND_RECOVERY.md
│   ├── 08_FEATURE_PARITY.md
│   ├── 09_WIREGUARD_RUST_PLAN.md
│   ├── 10_AI_HANDOFF_PROTOCOL.md
│   ├── adr/
│   └── templates/
├── agents/
│   └── roles/
├── prompts/
├── manifests/
├── patches/
├── config/
├── scripts/
├── tests/
├── reports/
├── artifacts/
└── upstream/
```

## 5. Mô hình phân nhánh & Quản trị Git

Dự án duy trì kho mã nguồn chính thức tại:
`https://github.com/KiritoMainBro88/CR8808-CUSTOM-FIRMWARE`

- **`main`**: Nhánh phiên bản ổn định, đã qua kiểm định nghiêm ngặt và nghiệm thu. Không commit trực tiếp vào `main`.
- **`develop`**: Nhánh tích hợp chính. Mọi tài liệu discovery, patch phần cứng và tính năng mới được tích hợp tại đây trước khi phát hành.
- **`feature/<tên>`**: Nhánh phát triển tính năng độc lập.
- **`research/<tên>`**: Nhánh nghiên cứu upstream và benchmark.
- **Nguyên tắc tích hợp Upstream**: Khi các nguồn upstream (`kuncy7`, `zcop`, `openwrt`) có cập nhật mới, không merge đè toàn bộ source. Đánh giá commit, cherry-pick có kiểm soát, chạy regression test và ghi nhận xuất xứ rõ ràng trong `manifests/sources.lock.yaml`.

## 6. Current project truth

- Physical product name `Xiaomi CR8808 Ver.B`: owner-confirmed.
- `CR8818`, `ap-mp03.3`, IPQ5018, YT9215S/SC, QCN6102, NAND model, kernel and RA82 build details are prior audit claims until re-read from the device or verified against authoritative source.
- No upstream commit is pinned.
- No final base distribution has been selected.
- No firmware has been built by this repository.
- No router-side action has been authorized or performed by this repository.
- Current status is **discovery only**.
