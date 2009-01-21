
# Change these if necessary.
export CC=gcc
export AR=ar
export CFLAGS=-Wall -g -O6 -std=c99
export LUA_INCLUDE=-I/usr/include/lua5.1
export LUA_LINK=-L/usr/local/lib -llua

SUBDIRS=runtime lang_ext utilities
ALLSUBDIRS=$(SUBDIRS) docs
TARGETS=all clean docs doc default
PREFIX=/usr/local

.PHONY: $(TARGETS)

default: lua_path gzlc
	@for dir in $(SUBDIRS) ; do $(MAKE) -w -C $$dir $@ || break ; done

runtime:
	$(MAKE) -w -C runtime

utilities: runtime
	$(MAKE) -w -C utilities

all: lua_path doc
	@for dir in $(ALLSUBDIRS) ; do $(MAKE) -w -C $$dir $@ || break ; done

doc: docs
docs:
	@$(MAKE) -w -C docs

clean:
	rm -f lua_path *.dot *.png docs/manual.html docs/*.png gzlc gzlc.out
	@for dir in $(ALLSUBDIRS) ; do make -w -C $$dir $@; done

lua_path: Makefile
	echo "export LUA_PATH=`pwd`/compiler/?.lua\\;`pwd`/sketches/?.lua\\;`pwd`/tests/?.lua" > lua_path
	echo export LUA_CPATH=`pwd`/lang_ext/lua/?.so >> lua_path

gzlc: utilities
	lua utilities/luac.lua compiler/gzlc -L compiler/*.lua compiler/bootstrap/*.lua sketches/pp.lua
	./utilities/srlua-glue ./utilities/srlua luac.out gzlc
	chmod a+x gzlc

install: gzlc runtime/libgazelle.a
	mkdir -p $(PREFIX)/bin
	cp gzlc $(PREFIX)/bin
	cp utilities/gzlparse $(PREFIX)/bin
	mkdir -p $(PREFIX)/include
	cp -R runtime/include/gazelle $(PREFIX)/include

test:
	for test in tests/test*.lua; do lua $$test; done
