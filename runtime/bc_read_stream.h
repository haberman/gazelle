/********************************************************************

  bitcode_read_stream.h

  This is a stream-based interface to reading files in bitcode
  format.

  Author: Joshua Haberman <joshua@reverberate.org>

*********************************************************************/

#ifndef BITCODE_READ_STREAM
#define BITCODE_READ_STREAM

#include <stdint.h>

struct bc_read_stream;

/**********************************************************

  Open/Close Stream

***********************************************************/

struct bc_read_stream *bc_rs_open_file(const char *filename);
void bc_rs_close_stream(struct bc_read_stream *stream);

/**********************************************************

  Moving around the stream

***********************************************************/

enum RecordType {
  DataRecord,    /* This is a normal data record that contains a series of integers */
  StartBlock,    /* This is the start of a block: you can descend into it or skip over it */
  EndBlock,      /* This indicates the end of a block. */
  DefineAbbrev,  /* This record defines an abbreviation. */
  Eof,           /* This indicates end-of-file. */
  Err            /* This indicates an error. */
};

struct record_info {
    enum RecordType record_type;
    uint32_t id;  /* record id for data records, block id for StartBlock */
};

/* Advance to the next record in the file, returning a tag indicating what
 * kind of record it is.
 *
 * Note that not every literal record in the stream will be passed to you,
 * the client.  Some, like records that define abbreviations, are handled
 * internally because they do not contain stream-level data. */
struct record_info bc_rs_next_data_record(struct bc_read_stream *stream);

/* Get the total number of integers in this data record, or the remaining number
 * of integers in this data record, respectively. */
int bc_rs_get_record_size(struct bc_read_stream *stream);
int bc_rs_get_remaining_record_size(struct bc_read_stream *stream);

/* Skip a block by calling this function before reading the first record
 * of a block.  Calling it in other circumstances is an error and the
 * results are undefined. */
void bc_rs_skip_block(struct bc_read_stream *stream);

void bc_rs_rewind_block(struct bc_read_stream *stream);

/**********************************************************

  Reading Data

***********************************************************/

/* Get the next integer from the current data record and advance the stream.
 * If there an error of any kind occurs, the corresponding error bits
 * are set on the stream (check them with bc_rs_get_error()), and these
 * functions themselves return an undefined value. */
uint8_t   bc_rs_read_next_8(struct bc_read_stream *stream);
uint16_t  bc_rs_read_next_16(struct bc_read_stream *stream);
uint32_t  bc_rs_read_next_32(struct bc_read_stream *stream);
uint64_t  bc_rs_read_next_64(struct bc_read_stream *stream);

uint8_t   bc_rs_read_8(struct bc_read_stream *stream, int i);
uint16_t  bc_rs_read_16(struct bc_read_stream *stream, int i);
uint32_t  bc_rs_read_32(struct bc_read_stream *stream, int i);
uint64_t  bc_rs_read_64(struct bc_read_stream *stream, int i);

/**********************************************************

  Error Reporting

***********************************************************/

/* These are the error flags for the data stream, and a means for reading them. */

/* The value in the stream was too large for the bc_rs_get_* function you called.
 * For example, the stream's value was 257 but you called bc_rs_get_8(). */
#define BITCODE_ERR_VALUE_TOO_LARGE 0x1

/* There were no more values in a record when you called bc_rs_get_*. */
#define BITCODE_ERR_NO_SUCH_VALUE   0x2

/* I/O error reading the input file */
#define BITCODE_ERR_IO              0x4

/* Bitcode data is corrupt */
#define BITCODE_ERR_CORRUPT_INPUT   0x8

#define BITCODE_ERR_INTERNAL        0x10

int bc_rs_get_error(struct bc_read_stream *stream);

#endif

/*
 * Local Variables:
 * c-file-style: "bsd"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:et:sts=4:sw=4
 */
