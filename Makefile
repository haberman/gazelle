
CFLAGS=-Wall -g -O6 -std=c99
SUBDIRS=runtime lang_ext utilities
TARGETS=all clean doc

.PHONY: $(TARGETS)
all: lua_path
	@for dir in $(SUBDIRS) ; do make -w -C $$dir $@; done

doc: docs/manual.html

clean:
	rm -f lua_path *.dot *.png docs/manual.html docs/*.png
	@for dir in $(SUBDIRS) ; do make -w -C $$dir $@; done

lua_path: Makefile
	echo -n "export LUA_PATH=`pwd`/compiler/?.lua\\;`pwd`/sketches/?.lua" > lua_path
	echo "\\;`pwd`/tests/?.lua" >> lua_path
	echo export LUA_CPATH=`pwd`/lang_ext/lua/?.so >> lua_path

png:
	for x in *.dot; do echo $$x; dot -Tpng -o `basename $$x .dot`.png $$x; done

doc: docs/manual.html
docs: docs/manual.html

docs/manual.html: docs/manual.txt docs/manual.conf docs/gzl-rtn-graph Makefile
	asciidoc -a toc -a toclevels=3 -a icons -a iconsdir=. docs/manual.txt

icons:
	cp /usr/share/asciidoc/icons/*.png docs

test:
	for test in tests/test*.lua; do lua $$test; done
