
DOT=dot
CFLAGS=-Wall -g -std=c99
all: runtime/bc_read_stream.o bc_lua.so runtime/bc_test runtime/recs-collate

clean:
	rm -rf runtime/*.o runtime/bc_test bc_lua.so *.dot *.png

runtime/bc_read_stream.o: runtime/bc_read_stream.c runtime/bc_read_stream.h
	gcc $(CFLAGS) -o runtime/bc_read_stream.o -c runtime/bc_read_stream.c -Iruntime

runtime/bc_lua.o: runtime/bc_lua.c runtime/bc_read_stream.h
	gcc $(CFLAGS) -o runtime/bc_lua.o -c runtime/bc_lua.c -Iruntime

runtime/bc_test.o: runtime/bc_test.c runtime/bc_read_stream.h
	gcc $(CFLAGS) -o runtime/bc_test.o -c runtime/bc_test.c -Iruntime

runtime/interpreter.o: runtime/interpreter.c runtime/bc_read_stream.h
	gcc $(CFLAGS) -o runtime/interpreter.o -c runtime/interpreter.c -Iruntime

runtime/recs-collate.o: runtime/recs-collate.c runtime/bc_read_stream.h
	gcc $(CFLAGS) -o runtime/recs-collate.o -c runtime/recs-collate.c -Iruntime

runtime/bc_test: runtime/bc_test.o runtime/bc_read_stream.o
	gcc -o runtime/bc_test runtime/bc_test.o runtime/bc_read_stream.o

runtime/recs-collate: runtime/interpreter.o runtime/bc_read_stream.o runtime/recs-collate.o
	gcc -o runtime/recs-collate runtime/recs-collate.o runtime/interpreter.o runtime/bc_read_stream.o

bc_lua.so: runtime/bc_lua.o runtime/bc_read_stream.o
	gcc -std=c99 -O6 -o bc_lua.so -bundle runtime/bc_lua.o runtime/bc_read_stream.o -llua

png:
	for x in *.dot; do echo $$x; $(DOT) -Tpng -o `basename -s .dot $$x`.png $$x; done
