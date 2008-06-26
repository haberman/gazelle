
CC=gcc
AR=ar
CFLAGS=-Wall -g -O0 -std=c99
OBJS=bc_read_stream.o interpreter.o load_grammar.o

all: libparse.a

clean:
	rm -f libparse.a $(OBJS)

.PHONY: all clean

$(OBJS): interpreter.h bc_read_stream.h

$(OBJS): %.o: %.c interpreter.h bc_read_stream.h
	$(CC) $(CFLAGS) -o $@ -c $<

libparse.a: $(OBJS)
	$(AR) rcs libparse.a $(OBJS)
