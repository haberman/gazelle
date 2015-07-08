/*********************************************************************

  Gazelle: a system for building fast, reusable parsers

  parse.h

  This file presents the public API for parsing text using Gazelle.

*********************************************************************/

#ifndef GAZELLE_PARSE
#define GAZELLE_PARSE

#include <stdbool.h>
#include <stdio.h>
#include <stddef.h>

#include "gazelle/bc_read_stream.h"
#include "gazelle/dynarray.h"
#include "gazelle/grammar.h"

#define GAZELLE_VERSION "0.4"
#define GAZELLE_WEBPAGE "http://www.reverberate.org/gazelle/"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * runtime state
 */

struct gzl_offset
{
    size_t byte;    /* 0-based. */
    size_t line;    /* 1-based. */
    size_t column;  /* 1-based. */
};

struct gzl_terminal
{
    char *name;
    struct gzl_offset offset;
    size_t len;
};

struct gzl_parse_val;

struct gzl_slotarray
{
    struct rtn *rtn;
    int num_slots;
    struct gzl_parse_val *slots;
};

struct gzl_parse_val
{
    enum {
      GZL_PARSE_VAL_EMPTY,
      GZL_PARSE_VAL_TERMINAL,
      GZL_PARSE_VAL_NONTERM,
      GZL_PARSE_VAL_USERDATA
    } type;

    union {
      struct gzl_terminal terminal;
      struct gzl_slotarray *nonterm;
      char userdata[8];
    } val;
};

/* This structure is the format for every stack frame of the parse stack. */
struct gzl_parse_stack_frame
{
    union {
      struct gzl_rtn_frame {
        struct gzl_rtn            *rtn;
        struct gzl_rtn_state      *rtn_state;
        struct gzl_rtn_transition *rtn_transition;
      } rtn_frame;

      struct gzl_gla_frame {
        struct gzl_gla            *gla;
        struct gzl_gla_state      *gla_state;
      } gla_frame;

      struct gzl_intfa_frame {
        struct gzl_intfa          *intfa;
        struct gzl_intfa_state    *intfa_state;
      } intfa_frame;
    } f;

    struct gzl_offset start_offset;

    enum gzl_frame_type {
      GZL_FRAME_TYPE_RTN,
      GZL_FRAME_TYPE_GLA,
      GZL_FRAME_TYPE_INTFA
    } frame_type;
};

#define GET_PARSE_STACK_FRAME(ptr) \
    (struct gzl_parse_stack_frame*)((char*)ptr-offsetof(struct gzl_parse_stack_frame,f))

/* A gzl_bound_grammar struct represents a grammar which has had callbacks bound
 * to it and has possibly been JIT-compiled.  Though JIT compilation is not
 * supported yet, the APIs are in-place to anticipate this feature.
 *
 * At the moment you initialize a bound_grammar structure directly, but in the
 * future there will be a set of functions that do so, possibly doing JIT
 * compilation and other such things in the process. */

struct gzl_parse_state;
typedef void (*gzl_rule_callback_t)(struct gzl_parse_state *state);
typedef void (*gzl_terminal_callback_t)(struct gzl_parse_state *state,
                                        struct gzl_terminal *terminal);
typedef void (*gzl_error_char_callback_t)(struct gzl_parse_state *state,
                                          int ch);
typedef void (*gzl_error_terminal_callback_t)(struct gzl_parse_state *state,
                                              struct gzl_terminal *terminal);
struct gzl_bound_grammar
{
    struct gzl_grammar *grammar;
    gzl_terminal_callback_t terminal_cb;
    gzl_rule_callback_t start_rule_cb;
    gzl_rule_callback_t end_rule_cb;
    gzl_error_char_callback_t error_char_cb;
    gzl_error_terminal_callback_t error_terminal_cb;
};

/* This structure defines the core state of a parsing stream.  By saving this
 * state alone, we can resume a parse from the position where we left off.
 *
 * However, this state can only be resumed in the context of this process
 * with one particular bound_grammar.  To save it for loading into another
 * process, it must be serialized using a different API (which is not yet
 * written). */
struct gzl_parse_state
{
    /* The bound_grammar instance this state is being parsed with. */
    struct gzl_bound_grammar *bound_grammar;

    /* A pointer that the client can use for their own purposes. */
    void *user_data;

    /* The offset of the next byte in the stream we will process. */
    struct gzl_offset offset;

    /* The offset of the beginning of the first terminal that has not yet been
     * yielded to the terminal callback.  This includes all terminals that are
     * currently being used for an as-yet-unresolved lookahead.
     *
     * Put another way, if a client wants to be able to go back to its input
     * buffer and look at the input data for a terminal that was just parsed,
     * it must not throw away any of the data before open_terminal_offset. */
    struct gzl_offset open_terminal_offset;

    /* We want to count newlines.  However, logical newlines can span more than
     * one byte.  So we track whether the last character was a newline so that
     * consecutive newline sequences (like CR/LF) are only counted as one
     * newline. */
    bool last_char_was_newline;

    /* Resource limits, which clients can use to prevent degenerate or malicious
     * input from taking up an arbitrary amount of resources.
     * gzl_init_parse_state() will set reasonable defaults for these, but the
     * client can override these defaults by setting these limits manually. */

    /* Gazelle will return an error if the stack attempts to exceed this
     * depth. */
    int max_stack_depth;

    /* Gazelle will return an error if the input requires more than this
     * many terminals of lookahead.  This is only an issue for LL(*)
     * languages -- for LL(k), this is naturally bounded to k. */
    int max_lookahead;

    /* The parse stack is the main piece of state that the parser keeps.
     * There is a stack frame for every RTN, GLA, and IntFA state we are
     * currently in. */
    DEFINE_DYNARRAY(parse_stack, struct gzl_parse_stack_frame);

    /* The token buffer stores tokens that have already been used to transition
     * the current GLA, but will be used to transition an RTN (and perhaps
     * other GLAs) when the current GLA hits a final state.  Keeping those
     * terminals here prevents us from having to re-lex them. */
    DEFINE_DYNARRAY(token_buffer, struct gzl_terminal);
};

/* Begin or continue a parse using grammar g, with the current state of the
 * parse represented by s.  It is expected that the text in buf represents the
 * input file or stream at offset s->offset.
 *
 * Return values:
 *  - GZL_STATUS_OK: the entire buffer has been consumed successfully, and
 *    "state" represents the state of the parse as of the last byte of the
 *    buffer.  You may continue parsing this file by calling gzl_parse() again
 *    with more data, or you may call gzl_finish_parse() if the input has
 *    reached EOF.
 *  - GZL_STATUS_ERROR: there was a parse error in the input.  The parse state
 *    is as it immediately before the erroneous character or token was
 *    encountered, and can therefore be used again if desired to continue the
 *    parse from that point.  state->offset will reflect how far the parse
 *    proceeded before encountering the error.
 *  - GZL_STATUS_CANCELLED: a callback that was called inside of gzl_parse()
 *    requested that parsing halt.  state is now invalid (this may change for
 *    the better in the future).
 *  - GZL_STATUS_HARD_EOF: all or part of the buffer was parsed successfully,
 *    but a state was reached where no more characters could be accepted
 *    according to the grammar.  state->offset reflects how many characters
 *    were read before parsing reached this state.  The client should call
 *    gzl_finish_parse() if it wants to receive final callbacks.
 *  - GZL_STATUS_RESOURCE_LIMIT_EXCEEDED: a resource limit like maximum stack
 *    depth or maximum lookahead limit was exceeded.
 */
enum gzl_status {
  GZL_STATUS_OK,
  GZL_STATUS_ERROR,
  GZL_STATUS_CANCELLED,
  GZL_STATUS_HARD_EOF,
  GZL_STATUS_RESOURCE_LIMIT_EXCEEDED,

  /* The following errors are Only returned by clients using the parse_file
   * interface: */
  GZL_STATUS_IO_ERROR,             /* Error reading the file, check errno. */
  GZL_STATUS_PREMATURE_EOF_ERROR,  /* File hit EOF but the grammar wasn't EOF */
};
enum gzl_status gzl_parse(struct gzl_parse_state *state, char *buf, size_t buf_len);

/* Call this function to complete the parse.  This primarily involves
 * calling all the final callbacks.  Will return false if the parse
 * state does not allow EOF here. */
bool gzl_finish_parse(struct gzl_parse_state *s);

struct gzl_parse_state *gzl_alloc_parse_state();
struct gzl_parse_state *gzl_dup_parse_state(struct gzl_parse_state *state);
void gzl_free_parse_state(struct gzl_parse_state *state);
void gzl_init_parse_state(struct gzl_parse_state *state, struct gzl_bound_grammar *bg);

/* A buffering layer provides the most common use case of parsing a whole file
 * by streaming from a FILE*.  This "struct buffer" will be the parse state's
 * user_data, the client's user_data is inside "struct buffer". */
struct gzl_buffer
{
    /* The buffer itself. */
    DEFINE_DYNARRAY(buf, char);

    /* The file offset of the first byte currently in the buffer. */
    int buf_offset;

    /* The number of bytes that have been successfully parsed. */
    int bytes_parsed;

    /* The user_data you passed to parse_file. */
    void *user_data;
};

enum gzl_status gzl_parse_file(struct gzl_parse_state *state,
                               FILE *file, void *user_data,
                               int max_buffer_size);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* GAZELLE_GRAMMAR */

/*
 * Local Variables:
 * c-file-style: "bsd"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:et:sts=4:sw=4
 */
