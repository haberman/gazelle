
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
    char *final_terminal;  /* NULL if not final */
    int num_transitions;
    struct intfa_transition *transitions;
};

struct parse_stack_frame
{
    struct rtn            *nonterm;
    struct rtn_state      *nonterm_state;
    struct rtn_transition *nonterm_transition;
    struct intfa       *terminal_dfa;
    struct intfa_state *terminal_dfa_state;
};

struct grammar
{
    char         **strings;

    int num_rtns;
    struct rtn   *rtns;

    int num_intfas;
    struct intfa *intfas;
};

struct parse_state
{
    struct grammar *grammar;
    struct buffer *buffer;

    struct parse_stack_frame *parse_stack;
    int parse_stack_length;
    int parse_stack_size;
};

struct grammar *load_grammar(struct bc_read_stream *s);

