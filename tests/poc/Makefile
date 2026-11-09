# Makefile for Motorcomm YT9215SC + NSS Compatibility PoC
CC ?= gcc
CROSS_COMPILE ?= aarch64-linux-gnu-
CFLAGS ?= -Wall -Wextra -Werror -O2 -std=c99

TARGET = test_yt921x_poc
TARGET_ARM64 = test_yt921x_poc_arm64
SRCS = test_yt921x_poc.c yt921x_tag_proto.c
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

%.o: %.c yt921x_tag_proto.h
	$(CC) $(CFLAGS) -c $< -o $@

arm64: $(SRCS) yt921x_tag_proto.h
	$(CROSS_COMPILE)gcc $(CFLAGS) -o $(TARGET_ARM64) $(SRCS)

test: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(OBJS) $(TARGET) $(TARGET).exe $(TARGET_ARM64) test_yt921x_poc_linux

.PHONY: all arm64 test clean
