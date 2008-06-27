/*********************************************************************

  Gazelle: a system for building fast, reusable parsers

  gzlparse.c

  This is a command-line utility for parsing using Gazelle.  It is
  very minimal at the moment, but the intention is for it to grow
  into a very rich and useful utility for doing all sorts of things.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

*********************************************************************/

#include "interpreter.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

void usage()
{
    printf("gzlparse: parse input text, given a compiled grammar\n");
    printf("Usage: gzlparse <grammar bitcode file> <input file>\n");
    printf("Input file can be '-' for stdin\n");
}

int main(int argc, char *argv[])
{
    if(argc < 3)
    {
        usage();
        return 1;
    }

    struct bc_read_stream *s = bc_rs_open_file(argv[1]);
    if(!s)
    {
        printf("Couldn't open bitcode file '%s'!\n\n", argv[1]);
        usage();
        return 1;
    }

    struct grammar *g = load_grammar(s);

    bc_rs_close_stream(s);

    FILE *file;
    if(strcmp(argv[2], "-") == 0)
    {
        file = stdin;
    }
    else
    {
        file = fopen(argv[2], "r");
        if(!file)
        {
            printf("Couldn't open file '%s' for reading: %s\n\n", argv[2], strerror(errno));
            usage();
            return 1;
        }
    }

    struct parse_state state;
    init_parse_state(&state, g);

    char buf[4096];
    int total_read = 0;
    while(1) {
        int consumed_buf_len;
        int read = fread(buf, 1, sizeof(buf), file);
        enum parse_status status = parse(g, &state, buf, read, &consumed_buf_len, NULL);
        total_read += consumed_buf_len;

        if(status == PARSE_STATUS_EOF || read == 0)
            break;
    }

    free_parse_state(&state);
    free_grammar(g);
    fclose(file);
}

/*
 * Local Variables:
 * c-file-style: "bsd"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:et:sts=4:sw=4
 */
