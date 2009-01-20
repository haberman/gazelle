
OBJS=bc_read_stream.o parse.o load_grammar.o

default: libgazelle.a

clean:
	rm -f libgazelle.a $(OBJS)

.PHONY: all clean

$(OBJS): include/gazelle/parse.h include/gazelle/bc_read_stream.h

$(OBJS): %.o: %.c include/gazelle/parse.h include/gazelle/bc_read_stream.h
	$(CC) $(CFLAGS) -Iinclude -o $@ -c $<

libgazelle.a: $(OBJS)
	$(AR) rcs libgazelle.a $(OBJS)
