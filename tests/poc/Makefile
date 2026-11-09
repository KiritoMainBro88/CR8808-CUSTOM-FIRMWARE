# Makefile for Motorcomm YT9215SC + NSS Compatibility PoC
CC ?= gcc
CFLAGS ?= -Wall -Wextra -Werror -O2 -std=c99

TARGET = test_yt921x_poc
SRCS = test_yt921x_poc.c yt921x_tag_proto.c
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

%.o: %.c yt921x_tag_proto.h
	$(CC) $(CFLAGS) -c $< -o $@

test: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(OBJS) $(TARGET) $(TARGET).exe

.PHONY: all test clean
