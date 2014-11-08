DESTDIR ?=
PREFIX ?= /usr
BINDIR := $(DESTDIR)$(PREFIX)/bin
LIBDIR := $(DESTDIR)$(PREFIX)/lib
INCDIR := $(DESTDIR)$(PREFIX)/include

IMGDIR := /usr/share/asciidoc/images

CFLAGS += -std=c99
CPPFLAGS := -Iruntime/include
ifeq ($(shell uname), Darwin)
  CPPFLAGS += -I/usr/include/lua5.1
  LDFLAGS := -L/usr/local/lib -llua -undefined dynamic_lookup
else
  CFLAGS += $(strip $(shell pkg-config --silence-errors --cflags lua || pkg-config --cflags lua5.1))
  LDFLAGS := $(strip $(shell pkg-config --silence-errors --libs lua || pkg-config --libs lua5.1))
endif
ADFLAGS := -a toc -a toclevels=3 -a icons -a iconsdir=.

export LUA_PATH := $(CURDIR)/compiler/?.lua;$(CURDIR)/sketches/?.lua;$(CURDIR)/tests/?.lua
export LUA_CPATH := $(CURDIR)/lang_ext/lua/?.so

RTSRC := $(wildcard runtime/*.c)
RTOBJ := $(RTSRC:.c=.o)
EXTSRC := $(wildcard lang_ext/lua/*.c)
EXTOBJ := $(EXTSRC:.c=.o)
LUASRC := $(wildcard compiler/*.lua) $(wildcard compiler/bootstrap/*.lua)
SRC := $(RTSRC) $(EXTSRC) $(wildcard utilities/*.c)
OBJ := $(SRC:.c=.o)
DEP := $(SRC:.c=.d)
UTIL := utilities/bitcode_dump utilities/srlua utilities/srlua-glue
PROG := gzlc utilities/gzlparse
LUALIB := lang_ext/lua/bc_read_stream.so lang_ext/lua/gazelle.so
LIB := $(LUALIB) runtime/libgazelle.a
INC := $(wildcard runtime/include/gazelle/*.h)
IMG := $(foreach img,$(wildcard $(IMGDIR)/*.png),docs/images/$(notdir $(img)))

.PHONY: all clean doc install test

%.d: %.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -MM -MT $(patsubst %.c,%.o,$<) -o $@ $^

%.so: %.o
	$(CC) $(LDFLAGS) -shared -o $@ $^

all: $(UTIL) $(LIB) $(PROG)

ifneq ($(filter-out clean doc test,$(MAKECMDGOALS)),)
  -include $(DEP)
endif

$(RTOBJ) $(EXTOBJ): CFLAGS += -fPIC

lang_ext/lua/bc_read_stream.so: lang_ext/lua/bc_read_stream.o \
                                runtime/bc_read_stream.o

lang_ext/lua/gazelle.so: lang_ext/lua/gazelle.o \
                         runtime/load_grammar.o \
                         runtime/parse.o

runtime/libgazelle.a(%.o): %.o
	$(AR) cr $@ $^

runtime/libgazelle.a: runtime/libgazelle.a($(RTOBJ))
	ranlib $@

utilities/bitcode_dump: utilities/bitcode_dump.o $(RTOBJ)

utilities/gzlparse: utilities/gzlparse.o $(RTOBJ)

gzlc: utilities/luac.lua utilities/srlua utilities/srlua-glue \
      compiler/gzlc | $(LUASRC) sketches/pp.lua sketches/dump_to_html.lua
	lua utilities/luac.lua compiler/gzlc -L $|
	./utilities/srlua-glue ./utilities/srlua luac.out $@
	chmod a+x gzlc

docs/images:
	mkdir -p docs/images

docs/images/%.png: /usr/share/asciidoc/images/%.png docs/images
	cp $(filter-out docs/images, $^) $@

docs/manual.html: docs/gzl-rtn-graph docs/manual.conf docs/manual.txt
	(cd docs; asciidoc -o manual.html manual.txt)

doc: $(IMG) docs/images docs/manual.html

test:
	lua tests/run_tests.lua

install: gzlc utilities/gzlparse runtime/libgazelle.a $(INC)
	install -d -o root -g root $(BINDIR)
	install -m 0755 -o root -g root gzlc $(BINDIR)
	install -m 0755 -o root -g root utilities/gzlparse $(BINDIR)
	install -d -o root -g root $(LIBDIR)
	install -m 0644 -o root -g root runtime/libgazelle.a $(LIBDIR)
	install -d $(INCDIR)/gazelle
	install -m 0644 -o root -g root $(INC) $(INCDIR)/gazelle

clean:
	$(RM) $(OBJ)
	$(RM) $(DEP)
	$(RM) $(PROG)
	$(RM) $(UTIL)
	$(RM) $(LIB)
	$(RM) luac.out
	$(RM) -r docs/images
	$(RM) docs/manual.html
	$(RM) docs/*.dot docs/*.png
