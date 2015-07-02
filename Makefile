MODULE = hotkey
PREFIX ?= ~/.hammerspoon/hs/_asm
LUA_INCLUDES ?= $(shell hs -c 'hs.processInfo.resourcePath')/lua

OBJCFILE = internal.m
LUAFILE  = init.lua
SOFILE  := $(OBJCFILE:.m=.so)
DEBUG_CFLAGS ?= -g
DOC_FILE = hs._asm.$(MODULE).json

CC=cc
EXTRA_CFLAGS ?= -fobjc-arc -I ${LUA_INCLUDES}
CFLAGS  += $(DEBUG_CFLAGS) -Wall -Wextra $(EXTRA_CFLAGS)
LDFLAGS += -dynamiclib -undefined dynamic_lookup $(EXTRA_LDFLAGS)

ifeq ($(wildcard $(CURDIR)/$(OBJCFILE)),)

### Lua Only

DOC_SOURCES = $(LUAFILE)

all: verify

install: install-lua

else

### Lua and Objective-C live together in perfect harmony

DOC_SOURCES = $(LUAFILE) $(OBJCFILE)

all: verify $(SOFILE)

$(SOFILE): $(OBJCFILE)
	$(CC) $(OBJCFILE) $(CFLAGS) $(LDFLAGS) -o $@

install: install-objc install-lua

endif

### Common

verify: $(LUAFILE)
	luac-5.3 -p $(LUAFILE) && echo "Passed" || echo "Failed"

install-objc: $(SOFILE)
	mkdir -p $(PREFIX)/$(MODULE)
	install -m 0644 $(SOFILE) $(PREFIX)/$(MODULE)

install-lua: $(LUAFILE)
	mkdir -p $(PREFIX)/$(MODULE)
	install -m 0644 $(LUAFILE) $(PREFIX)/$(MODULE)

docs: $(DOC_FILE)

$(DOC_FILE): $(DOC_SOURCES)
	find . -type f \( -name '*.lua' -o -name '*.m' \) -not -name 'template.*' -not -path './_*' -exec cat {} + | __doc_tools/gencomments | __doc_tools/genjson > $@

install-docs: docs
	mkdir -p $(PREFIX)/$(MODULE)
	install -m 0644 $(DOC_FILE) $(PREFIX)/$(MODULE)

clean:
	rm -v -rf $(SOFILE) *.dSYM $(DOC_FILE)

uninstall:
	rm -v -f $(PREFIX)/$(MODULE)/$(LUAFILE)
	rm -v -f $(PREFIX)/$(MODULE)/$(DOC_FILE)
	rm -v -f $(PREFIX)/$(MODULE)/$(SOFILE)
	rmdir -p $(PREFIX)/$(MODULE) ; exit 0

.PHONY: all clean uninstall verify docs install install-objc install-lua install-docs
