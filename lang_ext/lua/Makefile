
CFLAGS=-Wall -g -O6 -std=c99
EXTS=bc_read_stream.so gazelle.so

default: $(EXTS)

all: default

clean:
	rm -f $(EXTS) bc_read_stream.o gazelle.o

.PHONY: all clean default

bc_read_stream.o: bc_read_stream.c ../../runtime/include/gazelle/bc_read_stream.h
	gcc $(CFLAGS) -o bc_read_stream.o -c bc_read_stream.c -I../../runtime/include -I/usr/include/lua5.1

gazelle.o: gazelle.c ../../runtime/include/gazelle/bc_read_stream.h ../../runtime/include/gazelle/parse.h
	gcc $(CFLAGS) -o gazelle.o -c gazelle.c -I../../runtime/include -I/usr/include/lua5.1

ifeq ($(shell uname), Darwin)

bc_read_stream.so: ../../runtime/bc_read_stream.o bc_read_stream.o
	gcc -o bc_read_stream.so -undefined dynamic_lookup -bundle bc_read_stream.o ../../runtime/bc_read_stream.o

gazelle.so: ../../runtime/parse.o ../../runtime/bc_read_stream.o ../../runtime/load_grammar.o gazelle.o
	gcc -o gazelle.so -undefined dynamic_lookup -bundle gazelle.o ../../runtime/bc_read_stream.o ../../runtime/parse.o ../../runtime/load_grammar.o

else

bc_read_stream.so: ../../runtime/bc_read_stream.o bc_read_stream.o
	gcc -o bc_read_stream.so -shared bc_read_stream.o ../../runtime/bc_read_stream.o

gazelle.so: ../../runtime/bc_read_stream.o ../../runtime/load_grammar.o gazelle.o
	gcc -o gazelle.so -shared gazelle.o ../../runtime/bc_read_stream.o ../../runtime/load_grammar.o

endif
