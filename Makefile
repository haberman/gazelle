
CFLAGS=-Wall -g -O6 -std=c99
SUBDIRS=runtime lang_ext utilities
TARGETS=all clean

.PHONY: $(TARGETS)
all: lua_path
	@for dir in $(SUBDIRS) ; do make -w -C $$dir $@; done

clean:
	rm -f lua_path
	@for dir in $(SUBDIRS) ; do make -w -C $$dir $@; done

lua_path: Makefile
	echo "export LUA_PATH=`pwd`/compiler/?.lua\\;`pwd`/sketches/?.lua" > lua_path
	echo export LUA_CPATH=`pwd`/lang_ext/lua/?.so >> lua_path
