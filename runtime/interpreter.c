
#include <stdio.h>
#include <stdlib.h>
#include "interpreter.h"

struct parse_stack_frame *init_new_stack_frame(struct parse_state *parse_state, struct rtn *rtn)
{
    struct parse_stack_frame *frame = &parse_state->parse_stack[parse_state->parse_stack_length++];
    frame->rtn = rtn;
    frame->rtn_state = &rtn->states[0];
    frame->slots.rtn = rtn;
    frame->slots.num_slots = rtn->num_slots;
    frame->slots.slots = malloc(sizeof(struct parse_val)*frame->slots.num_slots);
    return frame;
}

struct parse_stack_frame *pop_stack_frame(struct parse_state *parse_state)
{
    struct parse_stack_frame *frame = &parse_state->parse_stack[parse_state->parse_stack_length-1];
    free(frame->slots.slots);
    parse_state->parse_stack_length--;
    if(parse_state->parse_stack_length == 0)
    {
        return NULL;  /* the parse is over */
    }
    else
    {
        frame--;
        frame->rtn_state = frame->rtn_transition->dest_state;
        return frame;
    }
}

void reset_dfa_match(struct parse_state *parse_state)
{
    struct parse_stack_frame *frame = &parse_state->parse_stack[parse_state->parse_stack_length-1];
    parse_state->dfa = frame->rtn_state->term_dfa;
    parse_state->dfa_state = &parse_state->dfa->states[0];
    parse_state->match_begin = parse_state->offset;
    parse_state->last_match_state = NULL;
}

void do_rtn_transition(struct parse_state *parse_state, int match_begin, int match_len, char *terminal)
{
    struct parse_stack_frame *frame = &parse_state->parse_stack[parse_state->parse_stack_length-1];
    struct parse_val val = {PARSE_VAL_TERMINAL, {.terminal = {match_begin, match_len}}};
    bool found_transition = false;

    /* is this an ignored terminal?  if so, just skip it */
    for(int i = 0; i < frame->rtn->num_ignore; i++)
    {
        if(frame->rtn->ignore_terminals[i] == terminal)
        {
            printf("Skipping a %s\n", terminal);
            reset_dfa_match(parse_state);
            return;
        }
    }

    /* find a transition out of this RTN state on this terminal */
    for(int i = 0; i < frame->rtn_state->num_transitions; i++)
    {
        struct rtn_transition *t = &frame->rtn_state->transitions[i];
        if(t->transition_type == TERMINAL_TRANSITION && t->edge.terminal_name == terminal)
        {
            found_transition = true;
            frame->slots.slots[t->slotnum] = val;
            printf("Setting dest_state to %p\n", t->dest_state);
            frame->rtn_state = t->dest_state;
        }
        else if(t->transition_type == DECISION && t->edge.decision->terminal_name == terminal)
        {
            found_transition = true;
            struct decision *d = t->edge.decision;

            for(int i = 0; i < d->num_actions; i++)
            {
                struct rtn_transition *t2 = &frame->rtn_state->transitions[d->actions[i]];

                if(t2->transition_type == NONTERM_TRANSITION)
                {
                    if(parse_state->parse_stack_length == parse_state->parse_stack_size)
                    {
                        printf("Need to reallocate parse stack!!\n");
                        exit(1);
                    }
                    frame->rtn_transition = t2;
                    frame = init_new_stack_frame(parse_state, t2->edge.nonterminal);
                    printf("Executed nonterm transition!\n");
                }
                else if(t2->transition_type == TERMINAL_TRANSITION)
                {
                    frame->slots.slots[t->slotnum] = val;
                    frame->rtn_state = t->dest_state;
                    printf("Executed terminal transition!\n");
                }
                printf("Executed action successfully (of %d)!\n", d->num_actions);
            }
        }
    }

    if(found_transition)
    {
        while(frame->rtn_state->is_final)
            frame = pop_stack_frame(parse_state);

        reset_dfa_match(parse_state);
    }
    else
    {
        printf("Syntax error -- no RTN transition!!\n");
    }
}


void parse(struct parse_state *parse_state)
{
    bool user_cancelled = false;

    while(!parse_state->buffer->is_eof && !user_cancelled && parse_state->parse_stack_length > 0)
    {
        int ch = parse_state->buffer->buf[parse_state->offset];
        printf("Offset: %d, char %c\n", parse_state->offset, ch);
        int found_transition = 0;

        /* We've read one character, which should cause one transition in the DFA for terminals.
         * Find the appropriate transition, and put the DFA in its new state. */
        for(int i = 0; i < parse_state->dfa_state->num_transitions; i++)
        {
            struct intfa_transition *t = &parse_state->dfa_state->transitions[i];

            if(ch >= t->ch_low && ch <= t->ch_high)
            {
                parse_state->dfa_state = t->dest_state;
                printf("Parsed one character: %c\n", ch);
                found_transition = 1;
                break;
            }
        }

        if(found_transition)
        {
            if(parse_state->dfa_state->final)
            {
                parse_state->last_match_state = parse_state->dfa_state;
                parse_state->last_match_end = parse_state->offset;
            }
            parse_state->offset++;
        }
        else
        {
            /* if there was a previous match, fall back to that.  otherwise this character represents
             * a syntax error. */
            if(parse_state->last_match_state)
            {
                /* we have a terminal.  do RTN transitions as appropriate */
                parse_state->offset = parse_state->last_match_end + 1;
                do_rtn_transition(parse_state, parse_state->match_begin, parse_state->last_match_end,
                                  parse_state->last_match_state->final);
            }
            else
            {
                printf("Syntax error!");
            }
        }
    }
}

