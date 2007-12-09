
#include "bc_read_stream.h"

#include <stdio.h>
#include <string.h>

void check_error(struct bc_read_stream *s)
{
    if(bc_rs_get_error(s))
    {
        int err = bc_rs_get_error(s);
        fprintf(stderr, "There were stream errors!\n");
        if(err & BITCODE_ERR_VALUE_TOO_LARGE)
            fprintf(stderr, "  Value too large.\n");
        if(err & BITCODE_ERR_NO_SUCH_VALUE)
            fprintf(stderr, "  No such value.\n");
        if(err & BITCODE_ERR_IO)
            fprintf(stderr, "  IO error.\n");
        if(err & BITCODE_ERR_CORRUPT_INPUT)
            fprintf(stderr, "  Corrupt input.\n");
        if(err & BITCODE_ERR_INTERNAL)
            fprintf(stderr, "  Internal error.\n");
    }
}

void usage()
{
    printf("bitcode_dump: dumps all of the records in a bitcode file\n");
    printf("Usage: bitcode_dump <bitcode file>\n");
}

int main(int argc, char *argv[0])
{
    int nesting = 0;

    if(argc < 2 || strcmp(argv[1], "--help") == 0)
    {
        usage();
        return 1;
    }

    struct bc_read_stream *s = bc_rs_open_file(argv[1]);
    if(!s)
    {
        printf("Failed to open bitcode file %s\n", argv[1]);
        return 1;
    }

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == DataRecord)
        {
            for(int i = 0; i < nesting; i++)
                printf("  ");

            printf("%u: ", ri.id);
            for(int i = 0; i < bc_rs_get_record_size(s); i++)
                printf("%llu ", bc_rs_read_64(s, i));
            printf("\n");
        }
        else if(ri.record_type == StartBlock)
        {
            for(int i = 0; i < nesting; i++)
                printf("  ");
            printf("-- (id=%u)\n", ri.id);
            nesting++;
        }
        else if(ri.record_type == EndBlock)
        {
            nesting--;
        }
        else if(ri.record_type == Eof)
        {
            bc_rs_close_stream(s);
            return 0;
        }
        else if(ri.record_type == Err)
        {
            fprintf(stderr, "Hit an error.  :(\n");
            check_error(s);
            return 1;
        }
        check_error(s);
    }
}

