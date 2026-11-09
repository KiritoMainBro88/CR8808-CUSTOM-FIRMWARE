#!/bin/bash
set -e

mkdir -p /root/dts_validation/include/dt-bindings/arm
mkdir -p /root/dts_validation/include/dt-bindings/clock
mkdir -p /root/dts_validation/include/dt-bindings/reset
mkdir -p /root/dts_validation/include/dt-bindings/interrupt-controller
mkdir -p /root/dts_validation/include/dt-bindings/gpio
mkdir -p /root/dts_validation/include/dt-bindings/input
mkdir -p /root/dts_validation/include/dt-bindings/leds

BASE="https://raw.githubusercontent.com/torvalds/linux/v6.18"
curl -sL "$BASE/arch/arm64/boot/dts/qcom/ipq5018.dtsi" -o /root/dts_validation/ipq5018.dtsi
curl -sL "$BASE/include/dt-bindings/interrupt-controller/arm-gic.h" -o /root/dts_validation/include/dt-bindings/interrupt-controller/arm-gic.h
curl -sL "$BASE/include/dt-bindings/interrupt-controller/irq.h" -o /root/dts_validation/include/dt-bindings/interrupt-controller/irq.h
curl -sL "$BASE/include/dt-bindings/clock/qcom,gcc-ipq5018.h" -o /root/dts_validation/include/dt-bindings/clock/qcom,gcc-ipq5018.h
curl -sL "$BASE/include/dt-bindings/reset/qcom,gcc-ipq5018.h" -o /root/dts_validation/include/dt-bindings/reset/qcom,gcc-ipq5018.h
curl -sL "$BASE/include/dt-bindings/gpio/gpio.h" -o /root/dts_validation/include/dt-bindings/gpio/gpio.h
curl -sL "$BASE/include/dt-bindings/input/input.h" -o /root/dts_validation/include/dt-bindings/input/input.h
curl -sL "$BASE/include/dt-bindings/leds/common.h" -o /root/dts_validation/include/dt-bindings/leds/common.h

echo "Base DTS files downloaded successfully."
ls -lh /root/dts_validation
