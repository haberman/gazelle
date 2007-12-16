/*********************************************************************

  Gazelle: a system for building fast, reusable parsers

  interpreter.h

  This file presents the public API for loading compiled grammars and
  parsing text using Gazelle.  There are a lot of structures, but they
  should all be considered read-only.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

*********************************************************************/

#include <stdbool.h>
#include <stdio.h>
#include "bc_read_stream.h"

struct parse_state;
typedef void (*parse_callback_t)(struct parse_state *state, void *user_data);

/*
 * RTN
 */

struct rtn_state;
struct rtn_transition;

struct rtn
{
    char *name;
    int num_slots;

    int num_ignore;
    char **ignore_terminals;

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
      DECISION
    } transition_type;

    union {
      char            *terminal_name;
      struct rtn      *nonterminal;
      struct decision *decision;
    } edge;

    struct rtn_state *dest_state;
    char *slotname;
    int slotnum;
};

struct decision
{
    char *terminal_name;
    int num_actions;
    int actions[];
};

struct rtn_state
{
    bool is_final;
    struct intfa *term_dfa;
    int num_transitions;
    struct rtn_transition *transitions;
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

    int num_intfas;
    struct intfa *intfas;
};

/*
 * runtime state
 */

struct terminal
{
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
    struct rtn            *rtn;
    struct rtn_state      *rtn_state;
    struct rtn_transition *rtn_transition;
    struct slotarray      slots;
    int start_offset;
};

struct buffer
{
    FILE *file;
    unsigned char *buf;
    int len;
    int size;
    int base_offset;
    bool is_eof;
};

struct completion_callback
{
    char *rtn_name;
    parse_callback_t callback;
};

struct parse_state
{
    struct grammar *grammar;
    struct buffer *buffer;

    int offset;
    int precious_offset;

    struct parse_stack_frame *parse_stack;
    int parse_stack_length;
    int parse_stack_size;

    struct intfa       *dfa;
    struct intfa_state *dfa_state;
    int match_begin;
    int last_match_end;
    struct intfa_state *last_match_state;

    struct parse_val *slotbuf;
    int slotbuf_len;
    int slotbuf_size;

    int num_completion_callbacks;
    struct completion_callback *callbacks;
    void *user_data;
};

struct grammar *load_grammar(struct bc_read_stream *s);
void free_grammar(struct grammar *g);
void parse(struct parse_state *parse_state, bool *eof);
void alloc_parse_state(struct parse_state *state);
void free_parse_state(struct parse_state *state);
void init_parse_state(struct parse_state *state, struct grammar *g, FILE *file);
void reinit_parse_state(struct parse_state *state);

void register_callback(struct parse_state *state, char *rtn_name, parse_callback_t callback, void *user_data);

/*
 * Local Variables:
 * c-file-style: "bsd"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:et:sts=4:sw=4
 */
