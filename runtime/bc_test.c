
#include "bc_read_stream.h"

#include <stdio.h>

int main()
{
    int nesting = 0;

    struct bc_read_stream *s = bc_rs_open_file("/tmp/test.bc");
    if(!s)
    {
        printf("Failed to open bitcode file!\n");
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
            printf("Hit EOF.  Bye.\n");
            bc_rs_close_stream(s);
            return 0;
        }
        else if(ri.record_type == Err)
        {
            printf("Hit an error.  :(\n");
            return 1;
        }

        if(bc_rs_get_error(s))
        {
            int err = bc_rs_get_error(s);
            printf("There were stream errors!\n");
            if(err & BITCODE_ERR_VALUE_TOO_LARGE)
                printf("  Value too large.\n");
            if(err & BITCODE_ERR_NO_SUCH_VALUE)
                printf("  No such value.\n");
            if(err & BITCODE_ERR_IO)
                printf("  IO error.\n");
            if(err & BITCODE_ERR_CORRUPT_INPUT)
                printf("  Corrupt input.\n");
            if(err & BITCODE_ERR_INTERNAL)
                printf("  Internal error.\n");
            return 1;
        }
    }
}

