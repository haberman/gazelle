
export CC=gcc
export AR=ar
export CFLAGS=-Wall -g -O6 -std=c99
SUBDIRS=runtime lang_ext utilities
ALLSUBDIRS=$(SUBDIRS) docs
TARGETS=all clean docs doc default

.PHONY: $(TARGETS)

default: lua_path
	@for dir in $(SUBDIRS) ; do $(MAKE) -w -C $$dir $@; done

all: lua_path doc
	@for dir in $(ALLSUBDIRS) ; do $(MAKE) -w -C $$dir $@; done

doc: docs
docs:
	@$(MAKE) -w -C docs

clean:
	rm -f lua_path *.dot *.png docs/manual.html docs/*.png
	@for dir in $(ALLSUBDIRS) ; do make -w -C $$dir $@; done

lua_path: Makefile
	echo "export LUA_PATH=`pwd`/compiler/?.lua\\;`pwd`/sketches/?.lua\\;`pwd`/tests/?.lua" > lua_path
	echo export LUA_CPATH=`pwd`/lang_ext/lua/?.so >> lua_path

test:
	for test in tests/test*.lua; do lua $$test; done
