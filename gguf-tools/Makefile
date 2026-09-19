ifneq ($(shell uname -s),Darwin)
$(error sf-q3-8flash tools build on macOS only)
endif

CC ?= cc
NATIVE_CPU_FLAG ?= -mcpu=native
CFLAGS ?= -O3 -Wall -Wextra -std=c11 $(NATIVE_CPU_FLAG)
CPPFLAGS ?= -D_GNU_SOURCE
QUANTS_SHARED := libds4quants.dylib

.PHONY: all clean quants-shared quality-score
all: quants-shared

quants-shared: $(QUANTS_SHARED)

$(QUANTS_SHARED): quants.c quants.h
	$(CC) $(CFLAGS) $(CPPFLAGS) -dynamiclib -fPIC -o $@ quants.c -lm -pthread

quality-score:
	$(MAKE) -C .. gguf-tools/quality-testing/score_official

clean:
	rm -f $(QUANTS_SHARED) quality-testing/score_official
