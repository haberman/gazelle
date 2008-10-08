/*********************************************************************

  Gazelle: a system for building fast, reusable parsers

  gzlparse.c

  This is a command-line utility for parsing using Gazelle.  It is
  very minimal at the moment, but the intention is for it to grow
  into a very rich and useful utility for doing all sorts of things.

  Copyright (c) 2007-2008 Joshua Haberman.  See LICENSE for details.

*********************************************************************/

#include "interpreter.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

void usage()
{
    fprintf(stderr, "gzlparse -- A command-line tool for parsing input text.\n");
    fprintf(stderr, "Gazelle %s  %s.\n", GAZELLE_VERSION, GAZELLE_WEBPAGE);
    fprintf(stderr, "\n");
    fprintf(stderr, "Usage: gzlparse [OPTIONS] GRAMMAR.gzc INFILE\n");
    fprintf(stderr, "Input file can be '-' for stdin.\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "  --dump-json    Dump a parse tree in JSON as text is parsed.\n");
    fprintf(stderr, "  --dump-total   When parsing finishes, print the number of bytes parsed.\n");
    fprintf(stderr, "  --help         You're looking at it.\n");
    fprintf(stderr, "\n");
}

struct gzlparse_state
{
    DEFINE_DYNARRAY(first_child, bool);
};

char *get_json_escaped_string(char *str)
{
    // The longest possible escaped string of this length has every character
    // escaped and a quote on each end, plus a NULL.
    char *return_str = malloc(strlen(str)*2 + 3);
    char *source = str;
    char *dest = return_str;
    *dest++ = '"';
    while(*source)
    {
        if(*source == '"' || *source == '\\')
        {
            // Escape backslashes and double quotes.
            *dest++ = '\\';
            *dest++ = *source++;
        }
        else if(*source < 32)
        {
            // Escape control characters.
            sprintf(dest, "\\u%04x", *source++);
            dest += 6;
        }
        else
            *dest++ = *source++;
    }
    *dest++ = '"';
    *dest++ = '\0';
    return return_str;
}

void print_newline(struct gzlparse_state *user_state, bool suppress_comma)
{
    if(user_state->first_child_len > 0 || suppress_comma == true)
    {
        if(*DYNARRAY_GET_TOP(user_state->first_child) || suppress_comma)
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

    print_newline(user_state, false);
    print_indent(user_state);

    char *terminal_name = get_json_escaped_string(terminal->name);
    char *slotname = get_json_escaped_string(rtn_frame->rtn_transition->slotname);
    printf("{\"terminal\": %s, \"slotname\": %s, \"slotnum\": %d, \"offset\": %d, \"len\": %d}",
           terminal_name, slotname, rtn_frame->rtn_transition->slotnum,
           terminal->offset, terminal->len);
    free(terminal_name);
    free(slotname);
}

void start_rule_callback(struct parse_state *parse_state)
{
    struct gzlparse_state *user_state = (struct gzlparse_state*)parse_state->user_data;
    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(parse_state->parse_stack);
    assert(frame->frame_type == FRAME_TYPE_RTN);
    struct rtn_frame *rtn_frame = &frame->f.rtn_frame;

    print_newline(user_state, false);
    print_indent(user_state);
    char *rule = get_json_escaped_string(rtn_frame->rtn->name);
    printf("{\"rule\":%s, \"start\": %d, ", rule, frame->start_offset);
    free(rule);

    if(parse_state->parse_stack_len > 1)
    {
        frame--;
        struct rtn_frame *prev_rtn_frame = &frame->f.rtn_frame;
        char *slotname = get_json_escaped_string(prev_rtn_frame->rtn_transition->slotname);
        printf("\"slotname\":%s, \"slotnum\":%d, ",
               slotname, prev_rtn_frame->rtn_transition->slotnum);
    }

    printf("\"children\": [");
    RESIZE_DYNARRAY(user_state->first_child, user_state->first_child_len+1);
    *DYNARRAY_GET_TOP(user_state->first_child) = true;
}

void end_rule_callback(struct parse_state *parse_state)
{
    struct gzlparse_state *user_state = (struct gzlparse_state*)parse_state->user_data;
    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(parse_state->parse_stack);
    assert(frame->frame_type == FRAME_TYPE_RTN);

    RESIZE_DYNARRAY(user_state->first_child, user_state->first_child_len-1);
    print_newline(user_state, true);
    print_indent(user_state);
    printf("], \"len\": %d}", parse_state->offset - frame->start_offset);
}

int main(int argc, char *argv[])
{
    if(strcmp(argv[1], "--help") == 0)
    {
        usage();
        exit(0);
    }

    if(argc < 3)
    {
        fprintf(stderr, "Not enough arguments.\n");
        usage();
        return 1;
    }

    int arg_offset = 1;
    bool dump_json = false;
    bool dump_total = false;
    while(arg_offset < argc && argv[arg_offset][0] == '-')
    {
        if(strcmp(argv[arg_offset], "--dump-json") == 0)
            dump_json = true;
        else if(strcmp(argv[arg_offset], "--dump-total") == 0)
            dump_total = true;
        else
        {
            fprintf(stderr, "Unrecognized option '%s'.\n", argv[arg_offset]);
            usage();
            exit(1);
        }
        arg_offset++;
    }

    /* Load the grammar file. */
    if(arg_offset+1 >= argc)
    {
        fprintf(stderr, "Must specify grammar file and input file.\n");
        usage();
        return 1;
    }
    struct bc_read_stream *s = bc_rs_open_file(argv[arg_offset++]);
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
    if(strcmp(argv[arg_offset], "-") == 0)
    {
        file = stdin;
    }
    else
    {
        file = fopen(argv[arg_offset], "r");
        if(!file)
        {
            printf("Couldn't open file '%s' for reading: %s\n\n", argv[2], strerror(errno));
            usage();
            return 1;
        }
    }

    struct gzlparse_state user_state;
    INIT_DYNARRAY(user_state.first_child, 1, 16);
    struct parse_state state = {
        .user_data = &user_state
    };
    struct bound_grammar bg = {
        .grammar = g,
    };
    if(dump_json) {
        bg.terminal_cb = terminal_callback;
        bg.start_rule_cb = start_rule_callback;
        bg.end_rule_cb = end_rule_callback;
        fputs("{\"parse_tree\":", stdout);
    }
    init_parse_state(&state, &bg);

    char buf[4096];
    int total_read = 0;
    while(1) {
        int consumed_buf_len;
        bool eof_ok;
        int read = fread(buf, 1, sizeof(buf), file);
        enum parse_status status = parse(&state, buf, read, &consumed_buf_len, &eof_ok);
        total_read += consumed_buf_len;

        if(read == 0)
        {
            if(eof_ok)
                finish_parse(&state);
            else
            {
                printf("\n");
                fprintf(stderr, "Premature end-of-file.\n");
                dump_json = false;
            }

            break;
        }
        else if(status == PARSE_STATUS_EOF)
        {
            break;
        }
    }

    if(dump_json)
        fputs("\n}\n", stdout);

    if(dump_total)
        fprintf(stderr, "%d bytes parsed.\n", total_read);

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
