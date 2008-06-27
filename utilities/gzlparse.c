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
#include <assert.h>

void usage()
{
    printf("gzlparse: parse input text, given a compiled grammar\n");
    printf("Usage: gzlparse <grammar bitcode file> <input file>\n");
    printf("Input file can be '-' for stdin\n");
}

struct gzlparse_state
{
    DEFINE_DYNARRAY(first_child, bool);
};

void print_newline(struct gzlparse_state *user_state)
{
    if(user_state->first_child_len > 0)
    {
    printf("Foo: %d\n", *DYNARRAY_GET_TOP(user_state->first_child));
        if(*DYNARRAY_GET_TOP(user_state->first_child))
        {
            *DYNARRAY_GET_TOP(user_state->first_child) = false;
            fputs("\n", stdout);
        }
        else
        {
            fputs(",\n", stdout);
        }
    }
}

void print_indent(struct gzlparse_state *user_state)
{
    for(int i = 0; i < user_state->first_child_len; i++)
        fputs("  ", stdout);
}

void terminal_callback(struct parse_state *parse_state,
                       struct terminal *terminal)
{
    struct gzlparse_state *user_state = (struct gzlparse_state*)parse_state->user_data;
    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(parse_state->parse_stack);
    assert(frame->frame_type == FRAME_TYPE_RTN);
    struct rtn_frame *rtn_frame = &frame->f.rtn_frame;

    print_newline(user_state);
    print_indent(user_state);
    printf("{\"terminal\": \"%s\", \"slotname\": \"%s\", \"slotnum\": %d, \"offset\": %d, \"len\": %d}",
           terminal->name, rtn_frame->rtn_transition->slotname, rtn_frame->rtn_transition->slotnum,
           terminal->offset, terminal->len);
}

void start_rule_callback(struct parse_state *parse_state)
{
    struct gzlparse_state *user_state = (struct gzlparse_state*)parse_state->user_data;
    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(parse_state->parse_stack);
    assert(frame->frame_type == FRAME_TYPE_RTN);
    struct rtn_frame *rtn_frame = &frame->f.rtn_frame;

    print_newline(user_state);
    print_indent(user_state);
    printf("{\"rule\":\"%s\", \"start\": %d, ", rtn_frame->rtn->name, rtn_frame->start_offset);

    if(parse_state->parse_stack_len > 1)
    {
        frame--;
        struct rtn_frame *prev_rtn_frame = &frame->f.rtn_frame;
        printf("\"slotname\":\"%s\", \"slotnum\":%d, ",
               prev_rtn_frame->rtn_transition->slotname,
               prev_rtn_frame->rtn_transition->slotnum);
    }

    printf("\"children\": [\n");
    RESIZE_DYNARRAY(user_state->first_child, user_state->first_child_len+1);
    *DYNARRAY_GET_TOP(user_state->first_child) = true;
}

void end_rule_callback(struct parse_state *parse_state)
{
    struct gzlparse_state *user_state = (struct gzlparse_state*)parse_state->user_data;
    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(parse_state->parse_stack);
    assert(frame->frame_type == FRAME_TYPE_RTN);
    struct rtn_frame *rtn_frame = &frame->f.rtn_frame;

    RESIZE_DYNARRAY(user_state->first_child, user_state->first_child_len-1);
    print_newline(user_state);
    print_indent(user_state);
    printf("], \"len\": %d}", parse_state->offset - rtn_frame->start_offset);
}

int main(int argc, char *argv[])
{
    if(argc < 3)
    {
        usage();
        return 1;
    }

    /* Load the grammar file. */
    struct bc_read_stream *s = bc_rs_open_file(argv[1]);
    if(!s)
    {
        printf("Couldn't open bitcode file '%s'!\n\n", argv[1]);
        usage();
        return 1;
    }
    struct grammar *g = load_grammar(s);
    bc_rs_close_stream(s);

    /* Open the input file. */
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

    struct gzlparse_state user_state;
    INIT_DYNARRAY(user_state.first_child, 0, 16);
    struct parse_state state = {
        .user_data = &user_state
    };
    struct bound_grammar bg = {
        .grammar = g,
    };
    bool dump_json = false;
    if(dump_json) {
        bg.terminal_cb = terminal_callback;
        bg.start_rule_cb = start_rule_callback;
        bg.end_rule_cb = end_rule_callback;
    }
    init_parse_state(&state, &bg);

    char buf[4096];
    int total_read = 0;
    while(1) {
        int consumed_buf_len;
        int read = fread(buf, 1, sizeof(buf), file);
        enum parse_status status = parse(&state, buf, read, &consumed_buf_len, NULL);
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
