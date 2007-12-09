
CFLAGS=-Wall -g -O6 -std=c99
EXTS=bc_read_stream.so

all: $(EXTS)

clean:
	rm -f $(EXTS) bc_read_stream.o

.PHONY: all clean

bc_read_stream.o: bc_read_stream.c ../../runtime/bc_read_stream.h
	gcc $(CFLAGS) -o bc_read_stream.o -c bc_read_stream.c -I../../runtime

# OS X specific for now
bc_read_stream.so: ../../runtime/bc_read_stream.o bc_read_stream.o
	gcc -o bc_read_stream.so -undefined dynamic_lookup -bundle bc_read_stream.o ../../runtime/bc_read_stream.o
