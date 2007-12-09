
#include <stdbool.h>
#include "bc_read_stream.h"

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
};

struct buffer
{
    char *buf;
    bool is_eof;
};

struct parse_state
{
    struct grammar *grammar;
    struct buffer *buffer;

    int offset;

    struct parse_stack_frame *parse_stack;
    int parse_stack_length;
    int parse_stack_size;

    struct intfa       *dfa;
    struct intfa_state *dfa_state;
    int match_begin;
    int last_match_end;
    struct intfa_state *last_match_state;
};

struct grammar *load_grammar(struct bc_read_stream *s);
void parse(struct parse_state *parse_state);

