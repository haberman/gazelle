
OBJS=bc_read_stream.o parse.o load_grammar.o

default: libparse.a

clean:
	rm -f libparse.a $(OBJS)

.PHONY: all clean

$(OBJS): include/gazelle/parse.h include/gazelle/bc_read_stream.h

$(OBJS): %.o: %.c include/gazelle/parse.h include/gazelle/bc_read_stream.h
	$(CC) $(CFLAGS) -Iinclude -o $@ -c $<

libparse.a: $(OBJS)
	$(AR) rcs libparse.a $(OBJS)
