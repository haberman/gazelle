/*********************************************************************

  Gazelle: a system for building fast, reusable parsers

  interpreter.h

  This file presents the public API for loading compiled grammars and
  parsing text using Gazelle.  There are a lot of structures, but they
  should all be considered read-only.

  Copyright (c) 2007-2008 Joshua Haberman.  See LICENSE for details.

*********************************************************************/

#include <stdbool.h>
#include <stdio.h>
#include "bc_read_stream.h"
#include "dynarray.h"

#define GAZELLE_VERSION "0.2-prerelease"
#define GAZELLE_WEBPAGE "http://www.reverberate.org/gazelle/"

struct parse_state;
struct terminal;
typedef void (*rule_callback_t)(struct parse_state *state);
typedef void (*terminal_callback_t)(struct parse_state *state,
                                    struct terminal *terminal);

/*
 * RTN
 */

struct rtn_state;
struct rtn_transition;

struct rtn
{
    char *name;
    int num_slots;

    int num_states;
    struct rtn_state *states;  /* start state is first */

    int num_transitions;
    struct rtn_transition *transitions;
};

struct rtn_transition
{
    enum {
      TERMINAL_TRANSITION,
      NONTERM_TRANSITION,
    } transition_type;

    union {
      char            *terminal_name;
      struct rtn      *nonterminal;
    } edge;

    struct rtn_state *dest_state;
    char *slotname;
    int slotnum;
};

struct rtn_state
{
    bool is_final;

    enum {
      STATE_HAS_INTFA,
      STATE_HAS_GLA,
      STATE_HAS_NEITHER
    } lookahead_type;

    union {
      struct intfa *state_intfa;
      struct gla *state_gla;
    } d;

    int num_transitions;
    struct rtn_transition *transitions;
};

/*
 * GLA
 */

struct gla_state;
struct gla_transition;

struct gla
{
    int num_states;
    struct gla_state *states;   /* start state is first */

    int num_transitions;
    struct gla_transition *transitions;
};

struct gla_transition
{
    char *term;
    struct gla_state *dest_state;
};

struct gla_state
{
    bool is_final;

    union {
        struct nonfinal_info {
            struct intfa *intfa;
            int num_transitions;
            struct gla_transition *transitions;
        } nonfinal;

        struct final_info {
            int transition_offset; /* 1-based -- 0 is "return" */
        } final;
    } d;
};

/*
 * IntFA
 */

struct intfa_state;
struct intfa_transition;

struct intfa
{
    int num_states;
    struct intfa_state *states;    /* start state is first */

    int num_transitions;
    struct intfa_transition *transitions;
};

struct intfa_transition
{
    int ch_low;
    int ch_high;
    struct intfa_state *dest_state;
};

struct intfa_state
{
    char *final;  /* NULL if not final */
    int num_transitions;
    struct intfa_transition *transitions;
};

struct grammar
{
    char         **strings;

    int num_rtns;
    struct rtn   *rtns;

    int num_glas;
    struct gla   *glas;

    int num_intfas;
    struct intfa *intfas;
};

/*
 * runtime state
 */

struct terminal
{
    char *name;
    int offset;
    int len;
};

struct parse_val;

struct slotarray
{
    struct rtn *rtn;
    int num_slots;
    struct parse_val *slots;
};

struct parse_val
{
    enum {
      PARSE_VAL_EMPTY,
      PARSE_VAL_TERMINAL,
      PARSE_VAL_NONTERM,
      PARSE_VAL_USERDATA
    } type;

    union {
      struct terminal terminal;
      struct slotarray *nonterm;
      char userdata[8];
    } val;
};

struct parse_stack_frame
{
    union {
      struct rtn_frame {
        struct rtn            *rtn;
        struct rtn_state      *rtn_state;
        struct rtn_transition *rtn_transition;
        int                   start_offset;
      } rtn_frame;

      struct gla_frame {
        struct gla            *gla;
        struct gla_state      *gla_state;
        int                   start_offset;
      } gla_frame;

      struct intfa_frame {
        struct intfa          *intfa;
        struct intfa_state    *intfa_state;
        int                   start_offset;
      } intfa_frame;
    } f;

    enum frame_type {
      FRAME_TYPE_RTN,
      FRAME_TYPE_GLA,
      FRAME_TYPE_INTFA
    } frame_type;
};

/* A bound_grammar struct represents a grammar which has had callbacks bound
 * to it and has possibly been JIT-compiled.  Though JIT compilation is not
 * supported yet, the APIs are in-place to anticipate this feature.
 *
 * At the moment you initialize a bound_grammar structure directly, but in the
 * future there will be a set of functions that do so, possibly doing JIT
 * compilation and other such things in the process. */
struct bound_grammar
{
    struct grammar *grammar;
    terminal_callback_t terminal_cb;
    rule_callback_t start_rule_cb;
    rule_callback_t end_rule_cb;
};

/* This structure defines the core state of a parsing stream.  By saving this
 * state alone, we can resume a parse from the position where we left off.
 *
 * However, this state can only be resumed in the context of this process
 * with one particular bound_grammar.  To save it for loading into another
 * process, it must be serialized using a different API (which is not yet
 * written). */
struct parse_state
{
    /* The bound_grammar instance this state is being parsed with. */
    struct bound_grammar *bound_grammar;

    /* A pointer that the client can use for their own purposes. */
    void *user_data;

    /* Our current offset in the stream.  We use this to mark the offsets
     * of all the tokens we lex. */
    int offset;

    /* The parse stack is the main piece of state that the parser keeps.
     * There is a stack frame for every RTN, GLA, and IntFA state we are
     * currently in.
     *
     * TODO: The right input can make this grow arbitrarily, so we'll need
     * built-in limits to avoid infinite memory consumption. */
    DEFINE_DYNARRAY(parse_stack, struct parse_stack_frame);

    /* The token buffer stores tokens that have already been used to transition
     * the current GLA, but will be used to transition an RTN (and perhaps
     * other GLAs) when the current GLA hits a final state.  Keeping those
     * terminals here prevents us from having to re-lex them.
     *
     * TODO: If the grammar is LL(k) for fixed k, the token buffer will never
     * need to be longer than k elements long.  If the grammar is LL(*),
     * this can grow arbitrarily depending on the input, and we'll need
     * a way to clamp its maximum length to prevent infinite memory
     * consumption. */
    DEFINE_DYNARRAY(token_buffer, struct terminal);
};

struct grammar *load_grammar(struct bc_read_stream *s);
void free_grammar(struct grammar *g);

/* Begin or continue a parse using grammar g, with the current state of the
 * parse represented by s.  It is expected that the text in buf represents the
 * input file or stream at offset s->offset.
 *
 * Return values:
 *  - PARSE_STATUS_OK: the entire buffer has been consumed successfully, and
 *    s represents the state of the parse as of the last byte of the buffer.
 *    You may continue parsing this file by calling parse() again with more
 *    data.
 *  - PARSE_STATUS_CANCELLED: a callback that was called inside of parse()
 *    requested that parsing halt.  s is now invalid (I may try to accommodate
 *    this case better in the future).
 *  - PARSE_STATUS_EOF: all or part of the buffer was parsed successfully,
 *    but a state was reached where no more characters could be accepted
 *    according to the grammar.  out_consumed_buf_len reflects how many
 *    characters were read before parsing reached this state.
 *
 * eof_ok indicates whether the input including this buffer forms a complete
 * and valid file according to the grammar.
 */
enum parse_status {
  PARSE_STATUS_OK,
  PARSE_STATUS_CANCELLED,
  PARSE_STATUS_EOF,
};
enum parse_status parse(struct parse_state *s, char *buf, int buf_len,
                        int *out_consumed_buf_len, bool *out_eof_ok);

void alloc_parse_state(struct parse_state *state);
void free_parse_state(struct parse_state *state);
void init_parse_state(struct parse_state *state, struct bound_grammar *bg);
void reinit_parse_state(struct parse_state *state, struct bound_grammar *bg);

/*
 * Local Variables:
 * c-file-style: "bsd"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:et:sts=4:sw=4
 */
