/*********************************************************************

  Gazelle: a system for building fast, reusable parsers

  load_grammar.c

  This file contains the code to load data from a bitcode stream into
  the data structures that the interpreter uses to parse.

  Copyright (c) 2007-2008 Joshua Haberman.  See LICENSE for details.

*********************************************************************/

#include "bc_read_stream.h"
#include "interpreter.h"

#include <stdlib.h>
#include <stdio.h>

#define BC_INTFAS 8
#define BC_INTFA 9
#define BC_STRINGS 10
#define BC_RTNS 11
#define BC_RTN 12
#define BC_GLAS 13
#define BC_GLA 14

#define BC_INTFA_STATE 0
#define BC_INTFA_FINAL_STATE 1
#define BC_INTFA_TRANSITION 2
#define BC_INTFA_TRANSITION_RANGE 3

#define BC_STRING 0

#define BC_RTN_INFO 0
#define BC_RTN_STATE_WITH_INTFA 2
#define BC_RTN_STATE_WITH_GLA 3
#define BC_RTN_TRIVIAL_STATE 4
#define BC_RTN_TRANSITION_TERMINAL 5
#define BC_RTN_TRANSITION_NONTERM 6

#define BC_GLA_STATE 0
#define BC_GLA_FINAL_STATE 1
#define BC_GLA_TRANSITION 2

void check_error(struct bc_read_stream *s)
{
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
    }
}

void unexpected(struct bc_read_stream *s, struct record_info ri)
{
    printf("Unexpected.  Record is: ");
    if(ri.record_type == DataRecord)
    {
        printf("data, id=%d, %d records\n", ri.id, bc_rs_get_record_size(s));
    }
    else if(ri.record_type == StartBlock)
    {
        printf("start block, id=%d\n", ri.id);
    }
    else if(ri.record_type == EndBlock)
    {
        printf("end block\n");
    }
    else if(ri.record_type == Eof)
    {
        printf("eof\n");
    }
    else if(ri.record_type == Err)
        printf("error\n");

    exit(1);
}

char **load_strings(struct bc_read_stream *s)
{
    /* first get a count of the strings */
    int num_strings = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == DataRecord)
            num_strings++;
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }

    bc_rs_rewind_block(s);
    char **strings = malloc((num_strings+1) * sizeof(*strings));
    int string_offset = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == DataRecord && ri.id == BC_STRING)
        {
            char *str = malloc((bc_rs_get_record_size(s)+1) * sizeof(char));
            int i;
            for(i = 0; bc_rs_get_remaining_record_size(s) > 0; i++)
            {
                str[i] = bc_rs_read_next_32(s);
            }

            str[i] = '\0';

            strings[string_offset++] = str;
        }
        else if(ri.record_type == EndBlock)
        {
            break;
        }
        else
            unexpected(s, ri);
    }

    strings[string_offset] = NULL;
    return strings;
}

void load_intfa(struct bc_read_stream *s, struct intfa *intfa, char **strings)
{
    /* first get a count of the states and transitions */
    intfa->num_states = 0;
    intfa->num_transitions = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == DataRecord)
        {
            if(ri.id == BC_INTFA_STATE || ri.id == BC_INTFA_FINAL_STATE)
                intfa->num_states++;
            else if(ri.id == BC_INTFA_TRANSITION || ri.id == BC_INTFA_TRANSITION_RANGE)
                intfa->num_transitions++;
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }

    bc_rs_rewind_block(s);
    intfa->states = malloc(intfa->num_states * sizeof(*intfa->states));
    intfa->transitions = malloc(intfa->num_transitions * sizeof(*intfa->transitions));
    int state_offset = 0;
    int transition_offset = 0;
    int state_transition_offset = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == DataRecord)
        {
            if(ri.id == BC_INTFA_STATE || ri.id == BC_INTFA_FINAL_STATE)
            {
                struct intfa_state *state = &intfa->states[state_offset++];

                state->num_transitions = bc_rs_read_next_32(s);
                state->transitions = &intfa->transitions[state_transition_offset];
                state_transition_offset += state->num_transitions;

                if(ri.id == BC_INTFA_FINAL_STATE)
                    state->final = strings[bc_rs_read_next_32(s)];
                else
                    state->final = NULL;
            }
            else if(ri.id == BC_INTFA_TRANSITION || ri.id == BC_INTFA_TRANSITION_RANGE)
            {
                struct intfa_transition *transition = &intfa->transitions[transition_offset++];

                if(ri.id == BC_INTFA_TRANSITION)
                {
                    transition->ch_low = transition->ch_high = bc_rs_read_next_8(s);
                }
                else if(ri.id == BC_INTFA_TRANSITION_RANGE)
                {
                    transition->ch_low = bc_rs_read_next_8(s);
                    transition->ch_high = bc_rs_read_next_8(s);
                }

                transition->dest_state = &intfa->states[bc_rs_read_next_8(s)];
            }
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }
}

void load_intfas(struct bc_read_stream *s, struct grammar *g)
{
    /* first get a count of the intfas */
    g->num_intfas = 0;
    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == StartBlock && ri.id == BC_INTFA)
        {
            g->num_intfas++;
            bc_rs_skip_block(s);
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }

    bc_rs_rewind_block(s);
    g->intfas = malloc((g->num_intfas) * sizeof(*g->intfas));
    int intfa_offset = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == StartBlock && ri.id == BC_INTFA)
        {
            load_intfa(s, &g->intfas[intfa_offset++], g->strings);
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }
}

void load_gla(struct bc_read_stream *s, struct gla *gla, struct grammar *g)
{
    /* first get a count of the states and transitions */
    gla->num_states = 0;
    gla->num_transitions = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == DataRecord)
        {
            if(ri.id == BC_GLA_STATE ||
               ri.id == BC_GLA_FINAL_STATE)
                gla->num_states++;
            else if(ri.id == BC_GLA_TRANSITION)
                gla->num_transitions++;
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }

    bc_rs_rewind_block(s);
    gla->states = malloc(gla->num_states * sizeof(*gla->states));
    gla->transitions = malloc(gla->num_transitions * sizeof(*gla->transitions));

    int state_offset = 0;
    int transition_offset = 0;
    int state_transition_offset = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == DataRecord)
        {
            if(ri.id == BC_GLA_STATE || ri.id == BC_GLA_FINAL_STATE)
            {
                struct gla_state *state = &gla->states[state_offset++];

                if(ri.id == BC_GLA_STATE)
                {
                    state->is_final = false;
                    state->d.nonfinal.intfa = &g->intfas[bc_rs_read_next_32(s)];
                    state->d.nonfinal.num_transitions = bc_rs_read_next_32(s);
                    state->d.nonfinal.transitions = &gla->transitions[state_transition_offset];
                    state_transition_offset += state->d.nonfinal.num_transitions;
                }
                else
                {
                    state->is_final = true;
                    state->d.final.transition_offset = bc_rs_read_next_32(s);
                }
            }
            else if(ri.id == BC_GLA_TRANSITION)
            {
                struct gla_transition *transition = &gla->transitions[transition_offset++];
                int term = bc_rs_read_next_32(s);
                int dest_state_offset = bc_rs_read_next_32(s);
                transition->dest_state = &gla->states[dest_state_offset];
                if(term == 0)
                    transition->term = NULL;
                else
                    transition->term = g->strings[term-1];
            }
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }
}

void load_glas(struct bc_read_stream *s, struct grammar *g)
{
    /* first get a count of the glas */
    g->num_glas = 0;
    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == StartBlock && ri.id == BC_GLA)
        {
            g->num_glas++;
            bc_rs_skip_block(s);
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }

    bc_rs_rewind_block(s);
    g->glas = malloc(g->num_glas * sizeof(*g->glas));
    int gla_offset = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == StartBlock && ri.id == BC_GLA)
        {
            load_gla(s, &g->glas[gla_offset++], g);
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }
}

void load_rtn(struct bc_read_stream *s, struct rtn *rtn, struct grammar *g)
{
    /* first get a count of the states and transitions */
    rtn->num_states = 0;
    rtn->num_transitions = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == DataRecord)
        {
            if(ri.id == BC_RTN_STATE_WITH_INTFA ||
               ri.id == BC_RTN_STATE_WITH_GLA ||
               ri.id == BC_RTN_TRIVIAL_STATE)
                rtn->num_states++;
            else if(ri.id == BC_RTN_TRANSITION_TERMINAL ||
                    ri.id == BC_RTN_TRANSITION_NONTERM)
                rtn->num_transitions++;
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }

    bc_rs_rewind_block(s);
    rtn->states = malloc(rtn->num_states * sizeof(*rtn->states));
    rtn->transitions = malloc(rtn->num_transitions * sizeof(*rtn->transitions));

    int state_offset = 0;
    int transition_offset = 0;
    int state_transition_offset = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == DataRecord)
        {
            if(ri.id == BC_RTN_INFO)
            {
                rtn->name = g->strings[bc_rs_read_next_32(s)];
                rtn->num_slots = bc_rs_read_next_32(s);
            }
            else if(ri.id == BC_RTN_STATE_WITH_INTFA ||
                    ri.id == BC_RTN_STATE_WITH_GLA ||
                    ri.id == BC_RTN_TRIVIAL_STATE)
            {
                struct rtn_state *state = &rtn->states[state_offset++];

                state->num_transitions = bc_rs_read_next_32(s);
                state->transitions = &rtn->transitions[state_transition_offset];
                state_transition_offset += state->num_transitions;

                if(bc_rs_read_next_8(s))
                    state->is_final = true;
                else
                    state->is_final = false;

                if(ri.id == BC_RTN_STATE_WITH_INTFA)
                {
                    state->lookahead_type = STATE_HAS_INTFA;
                    state->d.state_intfa = &g->intfas[bc_rs_read_next_32(s)];
                }
                else if(ri.id == BC_RTN_STATE_WITH_GLA)
                {
                    state->lookahead_type = STATE_HAS_GLA;
                    state->d.state_gla = &g->glas[bc_rs_read_next_32(s)];
                }
                else
                {
                    state->lookahead_type = STATE_HAS_NEITHER;
                }
            }
            else if(ri.id == BC_RTN_TRANSITION_TERMINAL ||
                    ri.id == BC_RTN_TRANSITION_NONTERM)
            {
                struct rtn_transition *transition = &rtn->transitions[transition_offset++];

                if(ri.id == BC_RTN_TRANSITION_TERMINAL)
                {
                    transition->transition_type = TERMINAL_TRANSITION;
                    transition->edge.terminal_name = g->strings[bc_rs_read_next_32(s)];
                }
                else if(ri.id == BC_RTN_TRANSITION_NONTERM)
                {
                    transition->transition_type = NONTERM_TRANSITION;
                    transition->edge.nonterminal = &g->rtns[bc_rs_read_next_32(s)];
                }

                transition->dest_state = &rtn->states[bc_rs_read_next_32(s)];
                transition->slotname   = g->strings[bc_rs_read_next_32(s)];
                transition->slotnum    = ((int)bc_rs_read_next_32(s)) - 1;
            }
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }
}

void load_rtns(struct bc_read_stream *s, struct grammar *g)
{
    /* first get a count of the rtns */
    g->num_rtns = 0;
    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == StartBlock && ri.id == BC_RTN)
        {
            g->num_rtns++;
            bc_rs_skip_block(s);
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }

    bc_rs_rewind_block(s);
    g->rtns = malloc(g->num_rtns * sizeof(*g->rtns));
    int rtn_offset = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == StartBlock && ri.id == BC_RTN)
        {
            load_rtn(s, &g->rtns[rtn_offset++], g);
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }
}

struct grammar *load_grammar(struct bc_read_stream *s)
{
    struct grammar *g = malloc(sizeof(*g));

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == StartBlock)
        {
            if(ri.id == BC_STRINGS)
                g->strings = load_strings(s);
            else if(ri.id == BC_INTFAS)
                load_intfas(s, g);
            else if(ri.id == BC_GLAS)
                load_glas(s, g);
            else if(ri.id == BC_RTNS)
                load_rtns(s, g);
            else
                bc_rs_skip_block(s);
        }
        else if(ri.record_type == Eof)
        {
            if(g->strings == NULL || g->num_intfas == 0 || g->num_rtns == 0)
            {
                printf("Premature EOF!\n");
                exit(1);
            }
            else
            {
                /* Success -- we finished loading! */
                break;
            }
        }
    }

    return g;
}

void free_grammar(struct grammar *g)
{
    for(int i = 0; g->strings[i] != NULL; i++)
        free(g->strings[i]);
    free(g->strings); 

    for(int i = 0; i < g->num_rtns; i++)
    {
        struct rtn *rtn = &g->rtns[i];
        free(rtn->states);
        free(rtn->transitions);
    }
    free(g->rtns);

    for(int i = 0; i < g->num_glas; i++)
    {
        struct gla *gla = &g->glas[i];
        free(gla->states);
        free(gla->transitions);
    }
    free(g->glas);

    for(int i = 0; i < g->num_intfas; i++)
    {
        struct intfa *intfa = &g->intfas[i];
        free(intfa->states);
        free(intfa->transitions);
    }
    free(g->intfas);

    free(g);
}

/*
 * Local Variables:
 * c-file-style: "bsd"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:et:sts=4:sw=4
 */
