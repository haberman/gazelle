
#include "bc_read_stream.h"

#define OP_ENCODING_FIXED 1
#define OP_ENCODING_VBR   2
#define OP_ENCODING_ARRAY 3
#define OP_ENCODING_CHAR6 4

#define ABBREV_ID_END_BLOCK       0
#define ABBREV_ID_ENTER_SUBBLOCK  1
#define ABBREV_ID_DEFINE_ABBREV   2
#define ABBREV_ID_UNABBREV_RECORD 3

#define STDBLOCK_BLOCKINFO 0

#define BLOCKINFO_BLOCK_SETBID 1

#define ALLOC_INITIAL_ARRAY(ptr, size, len) \
    

#define RESIZE_ARRAY_IF_NECESSARY(ptr, size, desired_size) \
    if(size < desired_size) \
    { \
        size *= 2; \
        ptr = realloc(ptr, size*sizeof(*ptr)); \
    }

#include <stdio.h>
#include <stdlib.h>

struct blockinfo {
    uint32_t block_id;
    int num_abbreviations;
    int size_abbreviations;
    struct blockinfo_abbrev {
        int num_operands;
        struct abbrev_operand *operands;
    } *abbreviations;
};

struct stream_stack_entry
{
    union {
        struct block_metadata {
            int abbrev_len;
            int block_id;
        } block_metadata;

        struct {
            int first_operand_offset;
            int num_operands;
        } abbrev;
    } e;

    enum EntryType {
        BlockMetadata,
        Abbreviation
    } type;
};

struct abbrev_operand
{
    union {
        long long literal_value;
        struct {
            unsigned char encoding;
            int value;
        } encoding_info;
    } o;

    enum OperandType {
        Literal,
        EncodingInfo
    } type;
};

struct bc_read_stream
{
    /* Values for the stream */
    FILE *infile;
    uint32_t next_bits;
    int num_next_bits;
    int stream_err;

    /* Values for the current block */
    int abbrev_len;
    int num_abbrevs;
    struct stream_stack_entry *block_metadata;
    struct blockinfo *blockinfo;

    /* Values for the current record */
    enum RecordType record_type;

    /*  - for data records */
    int record_id;
    int current_record_size;
    int current_record_offset;
    int record_buf_size;
    uint64_t *record_buf;

    /*  - for StartBlock records */
    int block_id;
    int block_len;

    /*  - for DefineAbbrev records */
    int record_size_abbrev;
    int record_num_abbrev;
    struct abbrev_operand *record_abbrev_operands;


    /* The stream stack */
    int stream_stack_size;
    int stream_stack_len;
    struct stream_stack_entry *stream_stack;

    int abbrev_operands_size;
    int abbrev_operands_len;
    struct abbrev_operand *abbrev_operands;

    /* Data about blockinfo records we have encountered */
    int blockinfo_size;
    int blockinfo_len;
    struct blockinfo *blockinfos;
};

/*
void print_abbrev(struct abbrev_operand *operands, int num_operands)
{
    printf("Abbrev: num_operands=%d\n", num_operands);
    for(int i = 0; i < num_operands; i++)
    {
        struct abbrev_operand *o = &operands[i];
        if(o->type == Literal)
        {
            printf("  Literal value: %llu\n", o->o.literal_value);
        }
        else if(o->type == EncodingInfo)
        {
            printf("  EncodingInfo: encoding=%u, value=%d\n", o->o.encoding_info.encoding,
                                                            o->o.encoding_info.value);
        }
    }
}

void dump_stack(struct bc_read_stream *s)
{
    for(int i = 0; i < s->stream_stack_len; i++)
    {
        struct stream_stack_entry *e = &s->stream_stack[i];
        if(e->type == Abbreviation)
        {
            print_abbrev(s->abbrev_operands + e->e.abbrev.first_operand_offset, e->e.abbrev.num_operands);
        }
        else if(e->type == BlockMetadata)
        {
            printf("BlockMetadata: abbrev_len=%d, block_id=%d\n", e->e.block_metadata.abbrev_len,
                                                                e->e.block_metadata.block_id);
        }
    }
}

void dump_blockinfo(struct blockinfo *bi)
{
    if(bi)
    {
        printf("Blockinfo! BlockID: %u,  Abbrevs:\n", bi->block_id);
        for(int i = 0; i < bi->num_abbreviations; i++)
            print_abbrev(bi->abbreviations[i].operands, bi->abbreviations[i].num_operands);
    }
}
*/

struct bc_read_stream *bc_rs_open_file(const char *filename)
{
    FILE *infile = fopen(filename, "r");

    if(infile == NULL)
    {
        return NULL;
    }

    char magic[4];
    int ret = fread(magic, 4, 1, infile);
    if(ret < 1 || magic[0] != 'B' || magic[1] != 'C')
    {
        fclose(infile);
        return NULL;
    }

    /* TODO: give the application a way to get the app-specific magic number */

    struct bc_read_stream *stream = malloc(sizeof(*stream));
    stream->infile = infile;
    stream->next_bits = 0;
    stream->num_next_bits = 0;
    stream->stream_err = 0;

    stream->abbrev_len = 2;    /* its initial value according to the spec */
    stream->num_abbrevs = 0;

    stream->stream_stack_size = 8;  /* enough for a few levels of nesting and a few abbrevs */
    stream->stream_stack_len  = 1;  /* we start with a single block_metadata entry */
    stream->stream_stack      = malloc(stream->stream_stack_size*sizeof(*stream->stream_stack));
    stream->block_metadata    = &stream->stream_stack[0];
    stream->block_metadata->type = BlockMetadata;
    stream->block_metadata->e.block_metadata.abbrev_len = stream->abbrev_len;

    stream->record_type = DataRecord;  /* anything besides Eof */

    stream->abbrev_operands_size = 8;
    stream->abbrev_operands_len  = 0;
    stream->abbrev_operands = malloc(stream->abbrev_operands_size*sizeof(*stream->abbrev_operands));

    stream->blockinfo_size = 8;
    stream->blockinfo_len  = 0;
    stream->blockinfos = malloc(stream->blockinfo_size*sizeof(*stream->blockinfos));

    stream->record_buf_size = 8;
    stream->record_buf = malloc(stream->record_buf_size*sizeof(*stream->record_buf));

    stream->record_size_abbrev = 8;
    stream->record_abbrev_operands = malloc(stream->record_size_abbrev*sizeof(*stream->record_abbrev_operands));

    return stream;
}

void bc_rs_close_stream(struct bc_read_stream *stream)
{
    free(stream->record_abbrev_operands);
    free(stream->record_buf);
    free(stream->abbrev_operands);
    free(stream->stream_stack);

    for(int i = 0; i < stream->blockinfo_len; i++)
    {
        for(int j = 0; j < stream->blockinfos[i].num_abbreviations; j++)
        {
            free(stream->blockinfos[i].abbreviations[j].operands);
        }
        free(stream->blockinfos[i].abbreviations);
    }
    free(stream->blockinfos);

    fclose(stream->infile);
    free(stream);
}

uint64_t bc_rs_read_64(struct bc_read_stream *stream, int i)
{
    if(i > stream->current_record_size)
    {
        stream->stream_err |= BITCODE_ERR_NO_SUCH_VALUE;
        return 0;
    }
    else
    {
        return stream->record_buf[i];
    }
}


#define GETTER_FUNC(type, bits) \
  type bc_rs_read_ ## bits (struct bc_read_stream *stream, int i) \
  {                                                            \
      uint64_t val = bc_rs_read_64(stream, i);                 \
      if(stream->record_buf[i] > ((1ULL << bits) - 1))         \
      {                                                        \
          stream->stream_err |= BITCODE_ERR_VALUE_TOO_LARGE;   \
          return 0;                                            \
      }                                                        \
      else                                                     \
      {                                                        \
          return (type)val;                                    \
      }                                                        \
  }

GETTER_FUNC(uint8_t, 8)
GETTER_FUNC(uint16_t, 16)
GETTER_FUNC(uint32_t, 32)

#define NEXT_GETTER_FUNC(type, bits) \
  type bc_rs_read_next_ ## bits (struct bc_read_stream *stream)     \
  {                                                                 \
      return bc_rs_read_ ## bits(stream, stream->current_record_offset++); \
  }                                                                 \

NEXT_GETTER_FUNC(uint8_t, 8)
NEXT_GETTER_FUNC(uint16_t, 16)
NEXT_GETTER_FUNC(uint32_t, 32)
NEXT_GETTER_FUNC(uint64_t, 64)

static int refill_next_bits(struct bc_read_stream *stream)
{
    unsigned char buf[4];
    int ret = fread(buf, 4, 1, stream->infile);
    if(ret < 1)
    {
        if(feof(stream->infile))
            stream->stream_err |= BITCODE_ERR_PREMATURE_EOF;

        if(ferror(stream->infile))
            stream->stream_err |= BITCODE_ERR_IO;

        return -1;
    }

    stream->next_bits = buf[0] | (buf[1] << 8) | (buf[2] << 16) | (buf[3] << 24);
    stream->num_next_bits = 32;

    return 0;
}

static uint32_t read_fixed(struct bc_read_stream *stream, int num_bits)
{
    uint32_t ret;

    if(stream->num_next_bits >= num_bits)
    {
        ret = stream->next_bits & ((1U << num_bits)-1);
        stream->next_bits >>= num_bits;
        stream->num_next_bits -= num_bits;
    }
    else
    {
        ret = stream->next_bits;
        int bits_filled = stream->num_next_bits;
        int bits_left = num_bits - bits_filled;

        if(refill_next_bits(stream) < 0) return 0;

        /* take bits_left bits from the next_bits */
        ret |= (stream->next_bits & (~0U >> (32-bits_left))) << bits_filled;

        if(bits_left != 32)
            stream->next_bits >>= bits_left;
        else
            stream->next_bits = 0;

        stream->num_next_bits -= bits_left;
    }
    return ret;
}

static uint64_t read_fixed_64(struct bc_read_stream *stream, int num_bits)
{
    if(num_bits <= 32)
    {
        return read_fixed(stream, num_bits);
    }
    else
    {
        uint64_t ret = read_fixed(stream, 32);
        return ret | ((uint64_t)read_fixed(stream, num_bits-32) << 32);
    }
}

static uint64_t read_vbr_64(struct bc_read_stream *stream, int bits)
{
    uint64_t val = 0;
    int read_bits = 0;
    int continuation_bit = 1 << (bits-1);
    int value_bits = continuation_bit - 1;
    int continues = 0;

    do {
        uint32_t next_bits = read_fixed(stream, bits);
        continues = next_bits & continuation_bit;
        val |= (next_bits & value_bits) << read_bits;
        read_bits += bits-1;
    } while(continues);

    return val;
}

static uint32_t read_vbr(struct bc_read_stream *stream, int bits)
{
    uint64_t val = read_vbr_64(stream, bits);
    if(val >> 32)
    {
        stream->stream_err |= BITCODE_ERR_CORRUPT_INPUT;
        return 0;
    }
    else
    {
        return (uint32_t)val;
    }
}

static uint8_t decode_char6(int num)
{
    if(num < 26) return 'a' + num;
    else if(num < 52) return 'A' + (num-26);
    else if(num < 62) return '0' + (num-52);
    else if(num < 63) return '.';
    else return '_';
}

/* This can handle any abbreviated type except for arrays */
static uint64_t read_abbrev_value(struct bc_read_stream *stream, struct abbrev_operand *op)
{
    if(op->type == Literal)
        return op->o.literal_value;
    else
    {
        switch(op->o.encoding_info.encoding) {
            case OP_ENCODING_FIXED:
                return read_fixed_64(stream, op->o.encoding_info.value);
            case OP_ENCODING_VBR:
                return read_vbr_64(stream, op->o.encoding_info.value);
            case OP_ENCODING_CHAR6:
                return decode_char6(read_fixed(stream, 6));
            default:
                stream->stream_err |= BITCODE_ERR_INTERNAL;
                return 0;
        }
    }
}

static void append_value(struct bc_read_stream *stream, uint64_t val)
{
    RESIZE_ARRAY_IF_NECESSARY(stream->record_buf, stream->record_buf_size, stream->current_record_size+1);
    stream->record_buf[stream->current_record_size++] = val;
}

static void read_user_abbreviated_record(struct bc_read_stream *stream,
                                         struct abbrev_operand *ops,
                                         int num_operands)
{
    stream->current_record_size = 0;

    for(int i = 0; i < num_operands; i++)
    {
        struct abbrev_operand *op = &ops[i];

        if(op->type == EncodingInfo && op->o.encoding_info.encoding == OP_ENCODING_ARRAY)
        {
            int num_elements = read_vbr(stream, 6);
            i += 1;
            for(int j = 0; j < num_elements; j++)
                append_value(stream, read_abbrev_value(stream, &ops[i]));
        }
        else
        {
            uint64_t val = read_abbrev_value(stream, &ops[i]);
            if(i == 0)
            {
                stream->record_id = val;
            }
            else
            {
                append_value(stream, val);
            }
        }
    }
}

static int read_abbrev_op(struct bc_read_stream *stream, struct abbrev_operand *o, int array_ok)
{
    int is_literal = read_fixed(stream, 1);
    if(is_literal)
    {
        o->type = Literal;
        o->o.literal_value = read_vbr(stream, 8);
    }
    else
    {
        o->type = EncodingInfo;
        o->o.encoding_info.encoding = read_fixed(stream, 3);
        switch(o->o.encoding_info.encoding)
        {
            case OP_ENCODING_FIXED:
            case OP_ENCODING_VBR:
                o->o.encoding_info.value = read_vbr(stream, 5);
                break;

            case OP_ENCODING_ARRAY:
                if(!array_ok) return -1;
                break;

            case OP_ENCODING_CHAR6:
                break;
        }
    }
    return 0;
}


void align_32_bits(struct bc_read_stream *stream)
{
    stream->num_next_bits = 0;
    stream->next_bits     = 0;
}

struct blockinfo *find_blockinfo(struct bc_read_stream *stream, int block_id)
{
    for(int i = 0; i < stream->blockinfo_len; i++)
        if(stream->blockinfos[i].block_id == block_id)
            return &stream->blockinfos[i];

    return NULL;
}

struct blockinfo *find_or_create_blockinfo(struct bc_read_stream *stream, int block_id)
{
    struct blockinfo *bi = find_blockinfo(stream, block_id);

    if(bi)
    {
        return bi;
    }
    else
    {
        RESIZE_ARRAY_IF_NECESSARY(stream->blockinfos, stream->blockinfo_size, stream->blockinfo_len+1);

        struct blockinfo *new_bi = &stream->blockinfos[stream->blockinfo_len++];

        new_bi->block_id = block_id;
        new_bi->num_abbreviations = 0;
        new_bi->size_abbreviations = 8;
        new_bi->abbreviations = malloc(new_bi->size_abbreviations * sizeof(new_bi->abbreviations));

        return new_bi;
    }
}

void bc_rs_next_record(struct bc_read_stream *stream)
{
    /* don't attempt to read past eof */
    if(stream->record_type == Eof) return;

    int abbrev_id = read_fixed(stream, stream->abbrev_len);

    switch(abbrev_id) {
        case ABBREV_ID_END_BLOCK:
            stream->record_type = EndBlock;

            align_32_bits(stream);

            stream->stream_stack_len = stream->block_metadata - stream->stream_stack;
            if(stream->stream_stack_len == 0)
            {
                stream->record_type = Eof;
                break;
            }

            stream->num_abbrevs = 0;
            stream->block_metadata--;
            while(stream->block_metadata->type == Abbreviation)
            {
                stream->num_abbrevs++;
                stream->block_metadata--;
            }

            stream->abbrev_len = stream->block_metadata->e.block_metadata.abbrev_len;
            stream->block_id   = stream->block_metadata->e.block_metadata.block_id;
            stream->blockinfo  = find_blockinfo(stream, stream->block_id);

            break;

        case ABBREV_ID_ENTER_SUBBLOCK:
            stream->block_id    = read_vbr(stream, 8);
            stream->abbrev_len  = read_vbr(stream, 4);
            align_32_bits(stream);
            stream->block_len = read_fixed(stream, 32);

            stream->record_type = StartBlock;

            RESIZE_ARRAY_IF_NECESSARY(stream->stream_stack, stream->stream_stack_size,
                                      stream->stream_stack_len+1);

            stream->block_metadata = &stream->stream_stack[stream->stream_stack_len++];
            stream->block_metadata->type = BlockMetadata;
            stream->block_metadata->e.block_metadata.block_id   = stream->block_id;
            stream->block_metadata->e.block_metadata.abbrev_len = stream->abbrev_len;

            stream->blockinfo = find_blockinfo(stream, stream->block_id);
            break;

        case ABBREV_ID_DEFINE_ABBREV:
            stream->record_type = DefineAbbrev;
            stream->record_num_abbrev = read_vbr(stream, 5);

            RESIZE_ARRAY_IF_NECESSARY(stream->record_abbrev_operands, stream->record_size_abbrev,
                                      stream->record_num_abbrev);

            for(int i = 0; i < stream->record_num_abbrev; i++)
            {
                read_abbrev_op(stream, &stream->record_abbrev_operands[i], 0);
            }

            break;

        case ABBREV_ID_UNABBREV_RECORD:
            stream->record_type = DataRecord;
            stream->record_id   = read_vbr(stream, 6);

            stream->current_record_size = read_vbr(stream, 6);

            RESIZE_ARRAY_IF_NECESSARY(stream->record_buf, stream->record_buf_size,
                                      stream->current_record_size+1);

            for(int i = 0; i < stream->current_record_size; i++)
                stream->record_buf[i] = read_vbr(stream, 6);
            break;

        default:
        {
            /* This must be a user-defined abbreviation.  It could come from the
             * blockinfo-defined abbreviations or abbreviations defined in this
             * block. */
            stream->record_type = DataRecord;
            int user_abbrev_id = abbrev_id - 4;
            int num_blockinfo_abbrevs = stream->blockinfo ? stream->blockinfo->num_abbreviations : 0;
            int block_abbrev_id = user_abbrev_id - num_blockinfo_abbrevs;
            if(user_abbrev_id < num_blockinfo_abbrevs)
            {
                struct blockinfo_abbrev *a = &stream->blockinfo->abbreviations[user_abbrev_id];
                read_user_abbreviated_record(stream, a->operands, a->num_operands);
            }
            else if(block_abbrev_id < stream->num_abbrevs)
            {
                struct stream_stack_entry *e = stream->block_metadata + block_abbrev_id + 1;
                struct abbrev_operand *o = stream->abbrev_operands + e->e.abbrev.first_operand_offset;
                read_user_abbreviated_record(stream, o, e->e.abbrev.num_operands);
            }
            else
            {
                stream->stream_err |= BITCODE_ERR_CORRUPT_INPUT;
            }
            break;
        }
    }
}

struct record_info bc_rs_next_data_record(struct bc_read_stream *stream)
{
    while(1)
    {
        bc_rs_next_record(stream);

        if(stream->record_type == DefineAbbrev)
        {
            int num_ops = stream->record_num_abbrev;

            RESIZE_ARRAY_IF_NECESSARY(stream->stream_stack, stream->stream_stack_size,
                                      stream->stream_stack_len+1);
            RESIZE_ARRAY_IF_NECESSARY(stream->abbrev_operands, stream->abbrev_operands_size,
                                      stream->abbrev_operands_len+num_ops+1);

            struct stream_stack_entry *e = &stream->stream_stack[stream->stream_stack_len++];
            e->type = Abbreviation;
            e->e.abbrev.first_operand_offset = stream->abbrev_operands_len;
            e->e.abbrev.num_operands = num_ops;
            struct abbrev_operand *abbrev_operands = &stream->abbrev_operands[stream->abbrev_operands_len];
            stream->abbrev_operands_len += num_ops;

            for(int i = 0; i < num_ops; i++)
                abbrev_operands[i] = stream->record_abbrev_operands[i];

            stream->num_abbrevs++;
        }
        else if(stream->record_type == StartBlock && stream->block_id == STDBLOCK_BLOCKINFO)
        {
            /* The first record must be a SETBID record */
            bc_rs_next_record(stream);
            struct blockinfo *bi = NULL;

            while(1)
            {
                if(stream->record_type == EndBlock)
                {
                    break;
                }
                else if(stream->record_type == Err || stream->record_type == Eof)
                {
                    struct record_info ri;
                    ri.record_type = stream->record_type;
                    ri.id = 0;
                    return ri;
                }
                else if(stream->record_type == DataRecord)
                {
                    if(stream->record_id == BLOCKINFO_BLOCK_SETBID)
                    {
                        if(stream->current_record_size != 1)
                        {
                            /* TODO */
                            stream->stream_err |= BITCODE_ERR_CORRUPT_INPUT;
                        }
                        bi = find_or_create_blockinfo(stream, stream->record_buf[0]);
                    }
                }
                else if(stream->record_type == DefineAbbrev)
                {

                    if(bi == NULL)
                    {
                        /* TODO */
                        stream->stream_err |= BITCODE_ERR_CORRUPT_INPUT;
                    }

                    RESIZE_ARRAY_IF_NECESSARY(bi->abbreviations,
                                              bi->size_abbreviations, bi->num_abbreviations+1);

                    struct blockinfo_abbrev *abbrev = &bi->abbreviations[bi->num_abbreviations++];
                    abbrev->num_operands = stream->record_num_abbrev;
                    abbrev->operands = malloc(sizeof(*abbrev->operands) * abbrev->num_operands);
                    for(int i = 0; i < abbrev->num_operands; i++)
                        abbrev->operands[i] = stream->record_abbrev_operands[i];
                }

                bc_rs_next_record(stream);
            }

        }
        else
        {
            struct record_info ri;
            ri.record_type = stream->record_type;
            ri.id = 0;

            if(ri.record_type == StartBlock)      ri.id = stream->block_id;
            else if(ri.record_type == DataRecord) ri.id = stream->record_id;

            return ri;
        }
    }
}

int bc_rs_get_error(struct bc_read_stream *stream)
{
    return stream->stream_err;
}

int bc_rs_get_record_size(struct bc_read_stream *stream)
{
    return stream->current_record_size;
}

//int bc_rs_get_remaining_record_size(struct bc_read_stream *stream);
