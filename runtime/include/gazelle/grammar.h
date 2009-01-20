/*********************************************************************

  Gazelle: a system for building fast, reusable parsers

  grammar.h

  This file presents the data structures for representing a compiled
  Gazelle grammar, and a function for loading one from a bytecode file.
  There are a lot of structures, but they should all be considered
  read-only.

  A compiled Gazelle grammar consists of a bunch of state machines of
  various kinds -- see the manual for more details.

  Copyright (c) 2007-2009 Joshua Haberman.  See LICENSE for details.

*********************************************************************/

#ifndef GAZELLE_GRAMMAR
#define GAZELLE_GRAMMAR

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>

/*
 * RTN
 */

struct gzl_rtn_state;
struct gzl_rtn_transition;

struct gzl_rtn
{
    char *name;
    int num_slots;

    int num_states;
    struct gzl_rtn_state *states;  /* start state is first */

    int num_transitions;
    struct gzl_rtn_transition *transitions;
};

struct gzl_rtn_transition
{
    enum {
      GZL_TERMINAL_TRANSITION,
      GZL_NONTERM_TRANSITION,
    } transition_type;

    union {
      char            *terminal_name;
      struct gzl_rtn  *nonterminal;
    } edge;

    struct gzl_rtn_state *dest_state;
    char *slotname;
    int slotnum;
};

struct gzl_rtn_state
{
    bool is_final;

    enum {
      GZL_STATE_HAS_INTFA,
      GZL_STATE_HAS_GLA,
      GZL_STATE_HAS_NEITHER
    } lookahead_type;

    union {
      struct gzl_intfa *state_intfa;
      struct gzl_gla *state_gla;
    } d;

    int num_transitions;
    struct gzl_rtn_transition *transitions;
};

/*
 * GLA
 */

struct gzl_gla_state;
struct gzl_gla_transition;

struct gzl_gla
{
    int num_states;
    struct gzl_gla_state *states;   /* start state is first */

    int num_transitions;
    struct gzl_gla_transition *transitions;
};

struct gzl_gla_transition
{
    char *term;  /* if NULL, then the term is EOF */
    struct gzl_gla_state *dest_state;
};

struct gzl_gla_state
{
    bool is_final;

    union {
        struct gzl_nonfinal_info {
            struct gzl_intfa *intfa;
            int num_transitions;
            struct gzl_gla_transition *transitions;
        } nonfinal;

        struct gzl_final_info {
            int transition_offset; /* 1-based -- 0 is "return" */
        } final;
    } d;
};

/*
 * IntFA
 */

struct gzl_intfa_state;
struct gzl_intfa_transition;

struct gzl_intfa
{
    int num_states;
    struct gzl_intfa_state *states;    /* start state is first */

    int num_transitions;
    struct gzl_intfa_transition *transitions;
};

struct gzl_intfa_transition
{
    int ch_low;
    int ch_high;
    struct gzl_intfa_state *dest_state;
};

struct gzl_intfa_state
{
    char *final;  /* NULL if not final */
    int num_transitions;
    struct gzl_intfa_transition *transitions;
};

struct gzl_grammar
{
    char         **strings;

    int num_rtns;
    struct gzl_rtn   *rtns;

    int num_glas;
    struct gzl_gla   *glas;

    int num_intfas;
    struct gzl_intfa *intfas;
};

/* Functions for loading a grammar from a bytecode file. */
struct gzl_grammar *gzl_load_grammar(struct bc_read_stream *s);
void gzl_free_grammar(struct gzl_grammar *g);

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
