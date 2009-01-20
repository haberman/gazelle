/*********************************************************************

  Gazelle: a system for building fast, reusable parsers

  gzlparse.c

  This is a command-line utility for parsing using Gazelle.  It is
  very minimal at the moment, but the intention is for it to grow
  into a very rich and useful utility for doing all sorts of things.

  Copyright (c) 2007-2008 Joshua Haberman.  See LICENSE for details.

*********************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <assert.h>

#include <gazelle/parse.h>

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

char *get_json_escaped_string(char *str, size_t size)
{
    // The longest possible escaped string of this length has every character
    // escaped and a quote on each end, plus a NULL.
    if(size == 0) size = strlen(str);  /* wait for NULL-termination */
    char *return_str = malloc(size*6 + 3);
    char *source = str;
    char *dest = return_str;
    *dest++ = '"';
    while((source-str) < size)
    {
        if(*source == '"' || *source == '\\')
        {
            // Escape backslashes and double quotes.
            *dest++ = '\\';
            *dest++ = *source++;
        }
        else if(*source < 32)
        {
            if(*source == '\n')
            {
              sprintf(dest, "\\n");
              dest += 2;
            }
            else if(*source == '\t')
            {
              sprintf(dest, "\\t");
              dest += 2;
            }
            else if(*source == '\r')
            {
              sprintf(dest, "\\r");
              dest += 2;
            }
            else
            {
              // Escape control characters.
              sprintf(dest, "\\u%04x", *source);
              dest += 6;
            }
            source++;
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
    if(user_state->first_child_len > 0 || suppress_comma)
    {
        if(user_state->first_child_len > 0 &&
           (*DYNARRAY_GET_TOP(user_state->first_child) || suppress_comma))
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

void terminal_callback(struct gzl_parse_state *parse_state,
                       struct gzl_terminal *terminal)
{
    struct gzl_buffer *buffer = (struct gzl_buffer*)parse_state->user_data;
    struct gzlparse_state *user_state = (struct gzlparse_state*)buffer->user_data;
    struct gzl_parse_stack_frame *frame = DYNARRAY_GET_TOP(parse_state->parse_stack);
    assert(frame->frame_type == GZL_FRAME_TYPE_RTN);
    struct gzl_rtn_frame *rtn_frame = &frame->f.rtn_frame;

    print_newline(user_state, false);
    print_indent(user_state);

    char *terminal_name = get_json_escaped_string(terminal->name, 0);
    int start = terminal->offset.byte - buffer->buf_offset;
    assert(start >= 0);
    assert(start+terminal->len <= buffer->buf_len);
    char *terminal_text = get_json_escaped_string(buffer->buf+
                                                  (terminal->offset.byte - buffer->buf_offset),
                                                  terminal->len);
    char *slotname = get_json_escaped_string(rtn_frame->rtn_transition->slotname, 0);
    printf("{\"terminal\": %s, \"slotname\": %s, \"slotnum\": %d, \"byte_offset\": %zu, "
           "\"line\": %zu, \"column\": %zu, \"len\": %zu, \"text\": %s}",
           terminal_name, slotname, rtn_frame->rtn_transition->slotnum,
           terminal->offset.byte, terminal->offset.line, terminal->offset.column,
           terminal->len, terminal_text);
    free(terminal_name);
    free(terminal_text);
    free(slotname);
}

void start_rule_callback(struct gzl_parse_state *parse_state)
{
    struct gzl_buffer *buffer = (struct gzl_buffer*)parse_state->user_data;
    struct gzlparse_state *user_state = (struct gzlparse_state*)buffer->user_data;
    struct gzl_parse_stack_frame *frame = DYNARRAY_GET_TOP(parse_state->parse_stack);
    assert(frame->frame_type == GZL_FRAME_TYPE_RTN);
    struct gzl_rtn_frame *rtn_frame = &frame->f.rtn_frame;

    print_newline(user_state, false);
    print_indent(user_state);
    char *rule = get_json_escaped_string(rtn_frame->rtn->name, 0);
    printf("{\"rule\":%s, \"start\": %zu, \"line\": %zu, \"column\": %zu, ",
           rule, frame->start_offset.byte,
           frame->start_offset.line, frame->start_offset.column);
    free(rule);

    if(parse_state->parse_stack_len > 1)
    {
        frame--;
        struct gzl_rtn_frame *prev_rtn_frame = &frame->f.rtn_frame;
        char *slotname = get_json_escaped_string(prev_rtn_frame->rtn_transition->slotname, 0);
        printf("\"slotname\":%s, \"slotnum\":%d, ",
               slotname, prev_rtn_frame->rtn_transition->slotnum);
        free(slotname);
    }

    printf("\"children\": [");
    RESIZE_DYNARRAY(user_state->first_child, user_state->first_child_len+1);
    *DYNARRAY_GET_TOP(user_state->first_child) = true;
}

void error_char_callback(struct gzl_parse_state *parse_state, int ch)
{
    fprintf(stderr, "gzlparse: unexpected character '%c' (0x%02x) at "
                    "line %zu, column %zu (byte offset %zu), aborting.\n",
                    ch, ch, parse_state->offset.line, parse_state->offset.column,
                    parse_state->offset.byte);
}

void error_terminal_callback(struct gzl_parse_state *parse_state, struct gzl_terminal *terminal)
{
    struct gzl_buffer *buffer = (struct gzl_buffer*)parse_state->user_data;
    struct gzlparse_state *user_state = (struct gzlparse_state*)buffer->user_data;
    fprintf(stderr, "gzlparse: unexpected terminal '%s' at line %zu, column %zu "
                    "(byte offset %zu), aborting.\n",
                    terminal->name, terminal->offset.line, terminal->offset.column,
                    terminal->offset.byte);
    char *terminal_text = get_json_escaped_string(buffer->buf+
                                                  (terminal->offset.byte - buffer->buf_offset),
                                                  terminal->len);
    fprintf(stderr, "gzlparse: terminal text is: %s.\n", terminal_text);
    free(terminal_text);
}

void end_rule_callback(struct gzl_parse_state *parse_state)
{
    struct gzl_buffer *buffer = (struct gzl_buffer*)parse_state->user_data;
    struct gzlparse_state *user_state = (struct gzlparse_state*)buffer->user_data;
    struct gzl_parse_stack_frame *frame = DYNARRAY_GET_TOP(parse_state->parse_stack);
    assert(frame->frame_type == GZL_FRAME_TYPE_RTN);

    RESIZE_DYNARRAY(user_state->first_child, user_state->first_child_len-1);
    print_newline(user_state, true);
    print_indent(user_state);
    printf("], \"len\": %zu}", parse_state->offset.byte - frame->start_offset.byte);
}

int main(int argc, char *argv[])
{
    if(argc > 1 && strcmp(argv[1], "--help") == 0)
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
    struct gzl_grammar *g = gzl_load_grammar(s);
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
    user_state.first_child[0] = true;

    struct gzl_parse_state *state = gzl_alloc_parse_state();
    struct gzl_bound_grammar bg = {
        .grammar = g,
        .error_char_cb = error_char_callback,
        .error_terminal_cb = error_terminal_callback,
    };
    if(dump_json) {
        bg.terminal_cb = terminal_callback;
        bg.start_rule_cb = start_rule_callback;
        bg.end_rule_cb = end_rule_callback;
        fputs("{\"parse_tree\":", stdout);
    }
    gzl_init_parse_state(state, &bg);
    enum gzl_status status = gzl_parse_file(state, file, &user_state, 50 * 1024);

    switch(status)
    {
        case GZL_STATUS_OK:
        case GZL_STATUS_HARD_EOF:
        {
            if(dump_json)
                fputs("\n}\n", stdout);

            if(dump_total)
            {
                fprintf(stderr, "gzlparse: %zu bytes parsed", state->offset.byte);
                if(status == GZL_STATUS_HARD_EOF)
                    fprintf(stderr, "(hit grammar EOF before file EOF)");
                fprintf(stderr, ".\n");
            }
            break;
        }

        case GZL_STATUS_ERROR:
            fprintf(stderr, "gzlparse: parse error, aborting.\n");

        case GZL_STATUS_CANCELLED:
            /* TODO: when we support length caps. */
            break;

        case GZL_STATUS_RESOURCE_LIMIT_EXCEEDED:
            /* TODO: more informative message about what limit was exceeded. */
            fprintf(stderr, "gzlparse: resource limit exceeded.\n");
            break;

        case GZL_STATUS_IO_ERROR:
            perror("gzlparse");
            break;

        case GZL_STATUS_PREMATURE_EOF_ERROR:
            fprintf(stderr, "gzlparse: premature eof.\n");
            break;
    }

    gzl_free_parse_state(state);
    gzl_free_grammar(g);
    FREE_DYNARRAY(user_state.first_child);
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
