
#include "bc_read_stream.h"
#include "interpreter.h"

#include <stdlib.h>
#include <stdio.h>

#define BC_INTFAS 8
#define BC_INTFA 9
#define BC_STRINGS 10
#define BC_RTNS 11
#define BC_RTN 12

#define BC_INTFA_STATE 0
#define BC_INTFA_FINAL_STATE 1
#define BC_INTFA_TRANSITION 2
#define BC_INTFA_TRANSITION_RANGE 3

#define BC_STRING 0

#define BC_RTN_INFO 0
#define BC_RTN_STATE 1
#define BC_RTN_TRANSITION_TERMINAL 2
#define BC_RTN_TRANSITION_NONTERM 3
#define BC_RTN_DECISION 4
#define BC_RTN_IGNORE 5

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

void load_rtn(struct bc_read_stream *s, struct rtn *rtn, struct grammar *g)
{
    /* first get a count of the ignores, states, and transitions */
    rtn->num_ignore = 0;
    rtn->num_states = 0;
    rtn->num_transitions = 0;

    while(1)
    {
        struct record_info ri = bc_rs_next_data_record(s);
        if(ri.record_type == DataRecord)
        {
            if(ri.id == BC_RTN_IGNORE)
                rtn->num_ignore++;
            else if(ri.id == BC_RTN_STATE)
                rtn->num_states++;
            else if(ri.id == BC_RTN_TRANSITION_TERMINAL ||
                    ri.id == BC_RTN_TRANSITION_NONTERM ||
                    ri.id == BC_RTN_DECISION)
                rtn->num_transitions++;
        }
        else if(ri.record_type == EndBlock)
            break;
        else
            unexpected(s, ri);
    }

    bc_rs_rewind_block(s);
    rtn->ignore_terminals = malloc(rtn->num_ignore * sizeof(*rtn->ignore_terminals));
    rtn->states = malloc(rtn->num_states * sizeof(*rtn->states));
    rtn->transitions = malloc(rtn->num_transitions * sizeof(*rtn->transitions));

    int ignore_offset = 0;
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
            else if(ri.id == BC_RTN_IGNORE)
            {
                rtn->ignore_terminals[ignore_offset++] = g->strings[bc_rs_read_next_32(s)];
            }
            else if(ri.id == BC_RTN_STATE)
            {
                struct rtn_state *state = &rtn->states[state_offset++];

                state->num_transitions = bc_rs_read_next_32(s);
                state->transitions = &rtn->transitions[state_transition_offset];
                state_transition_offset += state->num_transitions;

                state->term_dfa = &g->intfas[bc_rs_read_next_32(s)];

                if(bc_rs_read_next_8(s))
                    state->is_final = true;
                else
                    state->is_final = false;
            }
            else if(ri.id == BC_RTN_TRANSITION_TERMINAL ||
                    ri.id == BC_RTN_TRANSITION_NONTERM ||
                    ri.id == BC_RTN_DECISION)
            {
                struct rtn_transition *transition = &rtn->transitions[transition_offset++];

                if(ri.id == BC_RTN_TRANSITION_TERMINAL || ri.id == BC_RTN_TRANSITION_NONTERM)
                {
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
                    transition->slotnum    = bc_rs_read_next_32(s);
                }
                else if(ri.id == BC_RTN_DECISION)
                {
                    transition->transition_type = DECISION;
                    char *terminal_name = g->strings[bc_rs_read_next_32(s)];

                    transition->edge.decision = malloc(sizeof(struct decision) +
                                                 (sizeof(struct rtn_transition) * bc_rs_get_remaining_record_size(s)));

                    struct decision *d = transition->edge.decision;
                    d->terminal_name = terminal_name;
                    d->num_actions = bc_rs_get_remaining_record_size(s);

                    for(int action_num = 0; bc_rs_get_remaining_record_size(s) > 0; action_num++)
                    {
                        d->actions[action_num] = bc_rs_read_next_32(s);
                    }
                }
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

