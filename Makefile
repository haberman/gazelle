
DOT=dot
CFLAGS=-Wall -g -std=c99
all: runtime/bc_read_stream.o bc_lua.so runtime/bc_test libparse.a test

clean:
	rm -rf runtime/*.o runtime/bc_test bc_lua.so *.dot *.png libparse.a

runtime/bc_read_stream.o: runtime/bc_read_stream.c runtime/bc_read_stream.h
	gcc $(CFLAGS) -o runtime/bc_read_stream.o -c runtime/bc_read_stream.c -Iruntime

runtime/bc_lua.o: runtime/bc_lua.c runtime/bc_read_stream.h
	gcc $(CFLAGS) -o runtime/bc_lua.o -c runtime/bc_lua.c -Iruntime

runtime/bc_test.o: runtime/bc_test.c runtime/bc_read_stream.h
	gcc $(CFLAGS) -o runtime/bc_test.o -c runtime/bc_test.c -Iruntime

runtime/interpreter.o: runtime/interpreter.c runtime/bc_read_stream.h runtime/interpreter.h
	gcc $(CFLAGS) -o runtime/interpreter.o -c runtime/interpreter.c -Iruntime

runtime/load_grammar.o: runtime/load_grammar.c runtime/bc_read_stream.h runtime/interpreter.h
	gcc $(CFLAGS) -o runtime/load_grammar.o -c runtime/load_grammar.c -Iruntime

runtime/bc_test: runtime/bc_test.o runtime/bc_read_stream.o
	gcc -o runtime/bc_test runtime/bc_test.o runtime/bc_read_stream.o

libparse.a: runtime/interpreter.o runtime/load_grammar.o runtime/bc_read_stream.o
	ar rcs libparse.a runtime/interpreter.o runtime/load_grammar.o runtime/bc_read_stream.o

test: libparse.a test.c
	gcc $(CFLAGS) -o test test.c -lparse -Iruntime -L.

bc_lua.so: runtime/bc_lua.o runtime/bc_read_stream.o
	gcc $(CFLAGS) -o bc_lua.so -bundle runtime/bc_lua.o runtime/bc_read_stream.o -llua

png:
	for x in *.dot; do echo $$x; $(DOT) -Tpng -o `basename -s .dot $$x`.png $$x; done
