/*********************************************************************

  Gazelle: a system for building fast, reusable parsers

  interpreter.c

  Once a compiled grammar has been loaded into memory, the routines
  in this file are what actually does the parsing.  This file is an
  "interpreter" in the sense that it parses the input by using the
  grammar as a data structure -- no grammar-specific code is ever
  generated or executed.  Despite this, it is still quite fast, and
  has a very low memory footprint.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

*********************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "interpreter.h"

#define RESIZE_ARRAY_IF_NECESSARY(ptr, size, desired_size) \
    if(size < desired_size) \
    { \
        size *= 2; \
        ptr = realloc(ptr, size*sizeof(*ptr)); \
    }

struct parse_stack_frame *init_new_stack_frame(struct parse_state *parse_state, struct rtn *rtn, int begin)
{
    struct parse_stack_frame *frame = &parse_state->parse_stack[parse_state->parse_stack_length++];
    frame->rtn = rtn;
    frame->rtn_state = &rtn->states[0];
    frame->slots.rtn = rtn;
    frame->rtn_transition = NULL;
    frame->slots.num_slots = rtn->num_slots;
    frame->start_offset = begin;

    RESIZE_ARRAY_IF_NECESSARY(parse_state->slotbuf, parse_state->slotbuf_size,
                              parse_state->slotbuf_len + frame->slots.num_slots);

    frame->slots.slots = &parse_state->slotbuf[parse_state->slotbuf_len];
    for(int i = 0; i < frame->slots.num_slots; i++)
        frame->slots.slots[i].type = PARSE_VAL_EMPTY;

    parse_state->slotbuf_len += frame->slots.num_slots;

    return frame;
}

struct parse_stack_frame *pop_stack_frame(struct parse_state *parse_state)
{
    struct parse_stack_frame *frame = &parse_state->parse_stack[parse_state->parse_stack_length-1];
    parse_state->slotbuf_len -= frame->slots.num_slots;
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
            frame->slots.slots[t->slotnum] = val;
            frame->rtn_state = t->dest_state;
            found_transition = true;
            break;
        }
        else if(t->transition_type == DECISION && t->edge.decision->terminal_name == terminal)
        {
            struct decision *d = t->edge.decision;

            for(int i = 0; i < d->num_actions; i++)
            {
                struct rtn_transition *t2 = &frame->rtn_state->transitions[d->actions[i]];

                if(t2->transition_type == NONTERM_TRANSITION)
                {
                    RESIZE_ARRAY_IF_NECESSARY(parse_state->parse_stack,
                                              parse_state->parse_stack_size,
                                              parse_state->parse_stack_length+1);
                    frame->rtn_transition = t2;
                    frame = init_new_stack_frame(parse_state, t2->edge.nonterminal, match_begin);
                }
                else if(t2->transition_type == TERMINAL_TRANSITION)
                {
                    frame->slots.slots[t2->slotnum] = val;
                    frame->rtn_state = t2->dest_state;
                }
            }
            found_transition = true;
            break;
        }
    }

    if(found_transition)
    {
        while(parse_state->parse_stack_length > 0 && frame->rtn_state->is_final)
        {
            for(int i = 0; i < parse_state->num_completion_callbacks; i++)
            {
                struct completion_callback *cb = &parse_state->callbacks[i];
                if(frame->rtn->name == cb->rtn_name)
                    cb->callback(parse_state, parse_state->user_data);
            }

            frame = pop_stack_frame(parse_state);
        }

        if(parse_state->parse_stack_length > 0)
            reset_dfa_match(parse_state);
    }
    else
    {
        printf("Syntax error -- no RTN transition!!\n");
    }
}

void refill_buffer(struct parse_state *state)
{
    struct buffer *b = state->buffer;
    /* if more than 1/4 of the buffer is precious (can't be discarded), double the
     * buffer size */
    int precious_len = state->offset - state->precious_offset;
    if(precious_len > (b->size / 4))
    {
        b->size *= 2;
        b->buf = realloc(b->buf, b->size);
    }

    memmove(b->buf, b->buf + state->precious_offset - b->base_offset, precious_len);
    b->len = precious_len;
    b->base_offset = state->precious_offset;

    /* now read from the file as much as we can */
    int bytes_read = fread(b->buf + b->len, sizeof(char), b->size - b->len, b->file);

    if(bytes_read == 0)
    {
        if(feof(b->file))
        {
            b->is_eof = true;
        }
        else
        {
            printf("Error reading from file!\n");
            exit(1);
        }
    }

    b->len += bytes_read;
}

void parse(struct parse_state *parse_state, bool *eof)
{
    bool user_cancelled = false;

    while(!parse_state->buffer->is_eof && !user_cancelled && parse_state->parse_stack_length > 0)
    {
again:
        if(parse_state->offset == parse_state->buffer->base_offset + parse_state->buffer->len)
            refill_buffer(parse_state);

        int ch = parse_state->buffer->buf[parse_state->offset - parse_state->buffer->base_offset];

        /* We've read one character, which should cause one transition in the DFA for terminals.
         * Find the appropriate transition, and put the DFA in its new state. */
        for(int i = 0; i < parse_state->dfa_state->num_transitions; i++)
        {
            struct intfa_transition *t = &parse_state->dfa_state->transitions[i];

            if(ch >= t->ch_low && ch <= t->ch_high)
            {
                parse_state->dfa_state = t->dest_state;
                if(parse_state->dfa_state->final)
                {
                    parse_state->last_match_state = parse_state->dfa_state;
                    parse_state->last_match_end = parse_state->offset;
                }
                parse_state->offset++;
                goto again;
            }
        }

        /* since we fell out of the loop, there was no match.
         * if there was a previous match, fall back to that.  otherwise this character represents
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
            printf("Syntax error!\n");
        }
    }

    if(parse_state->buffer->is_eof) *eof = true;
}

void alloc_parse_state(struct parse_state *state)
{
    state->buffer = malloc(sizeof(struct buffer));
    state->buffer->size = 4096;
    state->buffer->buf = malloc((state->buffer->size) * sizeof(char));

    state->parse_stack_size = 50;
    state->parse_stack = malloc(sizeof(struct parse_stack_frame) * state->parse_stack_size);

    state->slotbuf_size = 200;
    state->slotbuf = malloc(sizeof(*state->slotbuf) * state->slotbuf_size);

    state->callbacks = malloc(sizeof(*state->callbacks) * 10);  /* XXX */
}

static void init_parse_state_common(struct parse_state *state);

void reinit_parse_state(struct parse_state *state)
{
    state->buffer->base_offset -= state->offset;
    init_parse_state_common(state);
}

void init_parse_state(struct parse_state *state, struct grammar *g, FILE *file)
{
    state->grammar = g;

    state->buffer->file = file;
    state->buffer->len  = 0;
    state->buffer->base_offset = 0;
    state->buffer->is_eof = false;
    state->num_completion_callbacks = 0;

    init_parse_state_common(state);
}

static void init_parse_state_common(struct parse_state *state)
{
    state->offset = 0;
    state->precious_offset = 0;
    state->parse_stack_length = 1;
    state->match_begin = 0;
    state->last_match_end = 0;
    state->last_match_state = NULL;
    state->parse_stack_length = 0;
    state->slotbuf_len = 0;

    init_new_stack_frame(state, &state->grammar->rtns[0], 0);
    reset_dfa_match(state);
}

void free_parse_state(struct parse_state *state)
{
    free(state->buffer->buf);
    free(state->buffer);
    free(state->parse_stack);
    free(state->slotbuf);
}

void register_callback(struct parse_state *state, char *rtn_name, parse_callback_t callback, void *user_data)
{
    struct completion_callback *cb = &state->callbacks[state->num_completion_callbacks++];
    cb->callback = callback;
    state->user_data = user_data;
    for(char **strs = state->grammar->strings; *strs; strs++)
        if(strcmp(*strs, rtn_name) == 0)
        {
            cb->rtn_name = *strs;
        }
}

/*
 * Local Variables:
 * c-file-style: "bsd"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:et:sts=4:sw=4
 */
