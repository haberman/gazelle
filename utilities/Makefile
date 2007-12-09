
CC=gcc
CFLAGS=-Wall -O6 -std=c99
all: bitcode_dump
clean:
	rm -rf bitcode_dump.o bitcode_dump

bitcode_dump.o: bitcode_dump.c ../runtime/bc_read_stream.h
	$(CC) $(CFLAGS) -o bitcode_dump.o -c bitcode_dump.c -I../runtime

bitcode_dump: bitcode_dump.o ../runtime/bc_read_stream.o
	$(CC) -o bitcode_dump bitcode_dump.o ../runtime/bc_read_stream.o
