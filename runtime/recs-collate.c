
#include <stdio.h>
#include "interpreter.h"

int main()
{
    struct bc_read_stream *s = bc_rs_open_file("/tmp/test.bc");
    if(!s)
    {
        printf("Couldn't open bitcode file /tmp/test.bc!\n");
    }

    struct grammar *g = load_grammar(s);
}
