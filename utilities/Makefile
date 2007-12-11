
CC=gcc
CFLAGS=-Wall -O6 -std=c99
all: bitcode_dump gzlparse
clean:
	rm -rf bitcode_dump.o bitcode_dump gzlparse.o gzlparse

bitcode_dump.o: bitcode_dump.c ../runtime/bc_read_stream.h
	$(CC) $(CFLAGS) -o bitcode_dump.o -c bitcode_dump.c -I../runtime

bitcode_dump: bitcode_dump.o ../runtime/bc_read_stream.o
	$(CC) -o bitcode_dump bitcode_dump.o ../runtime/bc_read_stream.o

gzlparse.o: gzlparse.c ../runtime/bc_read_stream.h ../runtime/interpreter.h
	$(CC) $(CFLAGS) -o gzlparse.o -c gzlparse.c -I../runtime

gzlparse: gzlparse.o ../runtime/libparse.a
	$(CC) -o gzlparse gzlparse.o ../runtime/libparse.a
