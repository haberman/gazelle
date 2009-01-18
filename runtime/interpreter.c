/*********************************************************************

  Gazelle: a system for building fast, reusable parsers

  interpreter.c

  Once a compiled grammar has been loaded into memory, the routines
  in this file are what actually does the parsing.  This file is an
  "interpreter" in the sense that it parses the input by using the
  grammar as a data structure -- no grammar-specific code is ever
  generated or executed.  Despite this, it is still quite fast, and
  has a very low memory footprint.

  The interpreter primarily consists of maintaining the parse stack
  properly and transitioning the frames in response to the input.

  Copyright (c) 2007-2008 Joshua Haberman.  See LICENSE for details.

*********************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include "interpreter.h"

/*
 * A diagnostic function for dumping the current state of the stack.
 */
void dump_stack(struct parse_state *s, FILE *output)
{
    fprintf(output, "Stack dump:\n");
    struct grammar *g = s->bound_grammar->grammar;
    for(int i = 0; i < s->parse_stack_len; i++)
    {
        struct parse_stack_frame *frame = &s->parse_stack[i];
        switch(frame->frame_type)
        {
            case FRAME_TYPE_RTN:
            {
                struct rtn_frame *rtn_frame = &frame->f.rtn_frame;
                fprintf(output, "RTN: %s", rtn_frame->rtn->name);
                break;
            }

            case FRAME_TYPE_GLA:
            {
                struct gla_frame *gla_frame = &frame->f.gla_frame;
                fprintf(output, "GLA: #%d", gla_frame->gla - g->glas);
                break;
            }

            case FRAME_TYPE_INTFA:
            {
                struct intfa_frame *intfa_frame = &frame->f.intfa_frame;
                fprintf(output, "IntFA: #%d", intfa_frame->intfa - g->intfas);
                break;
            }
        }
    }
    fprintf(output, "\n");
}

struct parse_stack_frame *push_empty_frame(struct parse_state *s, enum frame_type frame_type,
                                           int start_offset)
{
    RESIZE_DYNARRAY(s->parse_stack, s->parse_stack_len+1);
    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(s->parse_stack);
    frame->frame_type = frame_type;
    frame->start_offset = start_offset;
    return frame;
}

struct intfa_frame *push_intfa_frame(struct parse_state *s, struct intfa *intfa, int start_offset)
{
    struct parse_stack_frame *frame = push_empty_frame(s, FRAME_TYPE_INTFA, start_offset);
    struct intfa_frame *intfa_frame = &frame->f.intfa_frame;
    intfa_frame->intfa        = intfa;
    intfa_frame->intfa_state  = &intfa->states[0];

    return intfa_frame;
}

struct parse_stack_frame *push_gla_frame(struct parse_state *s, struct gla *gla, int start_offset)
{
    struct parse_stack_frame *frame = push_empty_frame(s, FRAME_TYPE_GLA, start_offset);
    struct gla_frame *gla_frame = &frame->f.gla_frame;
    gla_frame->gla          = gla;
    gla_frame->gla_state    = &gla->states[0];

    return frame;
}

enum parse_status push_rtn_frame(struct parse_state *s, struct rtn *rtn, int start_offset)
{
    struct parse_stack_frame *new_frame = push_empty_frame(s, FRAME_TYPE_RTN, start_offset);
    struct rtn_frame *new_rtn_frame = &new_frame->f.rtn_frame;

    new_rtn_frame->rtn            = rtn;
    new_rtn_frame->rtn_transition = NULL;
    new_rtn_frame->rtn_state      = &new_rtn_frame->rtn->states[0];

    /* Call start rule callback if set */
    if(s->bound_grammar->start_rule_cb)
    {
        s->bound_grammar->start_rule_cb(s);
    }

    return PARSE_STATUS_OK;
}

enum parse_status push_rtn_frame_for_transition(struct parse_state *s,
                                                  struct rtn_transition *t,
                                                  int start_offset)
{
    struct rtn_frame *old_rtn_frame = &DYNARRAY_GET_TOP(s->parse_stack)->f.rtn_frame;
    old_rtn_frame->rtn_transition = t;
    return push_rtn_frame(s, t->edge.nonterminal, start_offset);
}

struct parse_stack_frame *pop_frame(struct parse_state *s)
{
    assert(s->parse_stack_len > 0);
    RESIZE_DYNARRAY(s->parse_stack, s->parse_stack_len-1);

    struct parse_stack_frame *frame;
    if(s->parse_stack_len > 0)
        frame = DYNARRAY_GET_TOP(s->parse_stack);
    else
        frame = NULL;

    return frame;
}

enum parse_status pop_rtn_frame(struct parse_state *s)
{
    assert(DYNARRAY_GET_TOP(s->parse_stack)->frame_type == FRAME_TYPE_RTN);

    /* Call end rule callback if set */
    if(s->bound_grammar->end_rule_cb)
    {
        s->bound_grammar->end_rule_cb(s);
    }

    struct parse_stack_frame *frame = pop_frame(s);
    if(frame == NULL)
    {
        return PARSE_STATUS_EOF;
    }
    else
    {
        assert(frame->frame_type == FRAME_TYPE_RTN);
        struct rtn_frame *rtn_frame = &frame->f.rtn_frame;
        if(rtn_frame->rtn_transition)
        {
            rtn_frame->rtn_state = rtn_frame->rtn_transition->dest_state;
        }
        else
        {
          // Should only happen at the top level.
          assert(s->parse_stack_len == 1);
        }
        return PARSE_STATUS_OK;
    }
}

struct parse_stack_frame *pop_gla_frame(struct parse_state *s)
{
    assert(DYNARRAY_GET_TOP(s->parse_stack)->frame_type == FRAME_TYPE_GLA);
    return pop_frame(s);
}

struct parse_stack_frame *pop_intfa_frame(struct parse_state *s)
{
    assert(DYNARRAY_GET_TOP(s->parse_stack)->frame_type == FRAME_TYPE_INTFA);
    return pop_frame(s);
}

struct intfa_frame *get_top_intfa_frame(struct parse_state *s)
{
    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(s->parse_stack);
    assert(frame->frame_type == FRAME_TYPE_INTFA);
    return &frame->f.intfa_frame;
}

/*
 * descend_to_gla(): given the current parse stack, pushes any RTN or GLA
 * stack frames representing transitions that can be taken without consuming
 * any terminals.
 *
 * Preconditions:
 * - the current frame is either an RTN frame or a GLA frame
 *
 * Postconditions:
 * - the current frame is an RTN frame or a GLA frame.  If a new GLA frame was
 *   entered, entered_gla is set to true.
 */
enum parse_status descend_to_gla(struct parse_state *s, bool *entered_gla, int start_offset)
{
    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(s->parse_stack);
    *entered_gla = false;

    enum parse_status status = PARSE_STATUS_OK;

    while(status == PARSE_STATUS_OK && frame->frame_type == FRAME_TYPE_RTN)
    {
        struct rtn_frame *rtn_frame = &frame->f.rtn_frame;
        switch(rtn_frame->rtn_state->lookahead_type)
        {
          case STATE_HAS_INTFA:
            return PARSE_STATUS_OK;

          case STATE_HAS_GLA:
            *entered_gla = true;
            push_gla_frame(s, rtn_frame->rtn_state->d.state_gla, start_offset);
            return PARSE_STATUS_OK;

          case STATE_HAS_NEITHER:
            /* An RTN state has neither an IntFA or a GLA in only two cases:
             * - it is a final state with no outgoing transitions
             * - it is a nonfinal state with only one transition (a nonterminal) */
            assert(rtn_frame->rtn_state->num_transitions < 2);
            if(rtn_frame->rtn_state->num_transitions == 0)
            {
                /* Final state */
                status = pop_rtn_frame(s);
            }
            else if(rtn_frame->rtn_state->num_transitions == 1)
            {
                assert(rtn_frame->rtn_state->transitions[0].transition_type == NONTERM_TRANSITION);
                status = push_rtn_frame_for_transition(s, &rtn_frame->rtn_state->transitions[0],
                                                       start_offset);
            }
            break;
        }
        frame = DYNARRAY_GET_TOP(s->parse_stack);
    }

    return status;
}

struct intfa_frame *push_intfa_frame_for_gla_or_rtn(struct parse_state *s)
{
    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(s->parse_stack);
    if(frame->frame_type == FRAME_TYPE_GLA)
    {
        assert(frame->f.gla_frame.gla_state->is_final == false);
        return push_intfa_frame(s, frame->f.gla_frame.gla_state->d.nonfinal.intfa, s->offset);
    }
    else if(frame->frame_type == FRAME_TYPE_RTN)
    {
        return push_intfa_frame(s, frame->f.rtn_frame.rtn_state->d.state_intfa, s->offset);
    }
    assert(false);
    return NULL;
}

enum parse_status do_rtn_terminal_transition(struct parse_state *s,
                                             struct rtn_transition *t,
                                             struct terminal *terminal)
{
    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(s->parse_stack);
    assert(frame->frame_type == FRAME_TYPE_RTN);
    struct rtn_frame *rtn_frame = &frame->f.rtn_frame;

    /* Call terminal callback if set */
    if(s->bound_grammar->terminal_cb)
    {
        rtn_frame->rtn_transition = t;
        s->bound_grammar->terminal_cb(s, terminal);
    }

    assert(t->transition_type == TERMINAL_TRANSITION);
    rtn_frame->rtn_state = t->dest_state;
    s->open_terminal_offset = terminal->offset + terminal->len;
    return PARSE_STATUS_OK;
}

struct rtn_transition *find_rtn_terminal_transition(struct parse_state *s,
                                                    struct terminal *terminal)
{
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_len-1];
    struct rtn_frame *rtn_frame = &frame->f.rtn_frame;
    for(int i = 0; i < rtn_frame->rtn_state->num_transitions; i++)
    {
        struct rtn_transition *t = &rtn_frame->rtn_state->transitions[i];
        if(t->transition_type == TERMINAL_TRANSITION && t->edge.terminal_name == terminal->name)
        {
            return t;
        }
    }

    return NULL;
}

/* term_name can be NULL if we're looking for EOF. */
struct gla_transition *find_gla_transition(struct gla_state *gla_state,
                                           char *term_name)
{
    for(int i = 0; i < gla_state->d.nonfinal.num_transitions; i++)
    {
        struct gla_transition *t = &gla_state->d.nonfinal.transitions[i];
        if(t->term == term_name)
            return t;
    }
    return NULL;
}

/*
 * do_gla_transition(): transitions a GLA frame, performing the appropriate
 * RTN transitions if this puts the GLA in a final state.
 *
 * Preconditions:
 * - the current stack frame is a GLA frame
 * - term is a terminal that came from this GLA state's intfa
 *
 * Postconditions:
 * - the current stack frame is a GLA frame (this would indicate that
 *   the GLA hasn't hit a final state yet) or the current stack frame is
 *   an RTN frame (indicating we *have* hit a final state in the GLA)
 */
enum parse_status do_gla_transition(struct parse_state *s,
                                    char *term_name,
                                    int *rtn_term_offset)
{
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_len-1];
    assert(frame->frame_type == FRAME_TYPE_GLA);
    assert(frame->f.gla_frame.gla_state->is_final == false);
    struct gla_state *gla_state = frame->f.gla_frame.gla_state;
    struct gla_state *dest_gla_state = NULL;

    struct gla_transition *t = find_gla_transition(gla_state, term_name);
    assert(t);
    assert(t->dest_state);
    frame->f.gla_frame.gla_state = t->dest_state;
    dest_gla_state = t->dest_state;

    enum parse_status status = PARSE_STATUS_OK;

    if(dest_gla_state->is_final)
    {
        /* pop the GLA frame (since now we know what RTN transition to take)
         * and use its information to make an RTN transition */
        int offset = dest_gla_state->d.final.transition_offset;
        frame = pop_gla_frame(s);
        if(offset == 0)
        {
            status = pop_rtn_frame(s);
        }
        else
        {
            struct rtn_transition *t = &frame->f.rtn_frame.rtn_state->transitions[offset-1];
            struct terminal *next_term = &s->token_buffer[*rtn_term_offset];
            if(t->transition_type == TERMINAL_TRANSITION)
            {
                /* The transition must match what we have in the token buffer */
                (*rtn_term_offset)++;
                assert(next_term->name == t->edge.terminal_name);
                status = do_rtn_terminal_transition(s, t, next_term);
            }
            else
            {
                status = push_rtn_frame_for_transition(s, t, next_term->offset+next_term->len);
            }
        }
    }

    return status;
}

/*
 * process_terminal(): processes a terminal that was just lexed, possibly
 * triggering a series of RTN and/or GLA transitions.
 *
 * Preconditions:
 * - the current stack frame is an intfa frame representing the intfa that
 *   just produced this terminal
 * - the given terminal can be recognized by the current GLA or RTN state
 *
 * Postconditions:
 * - the current stack frame is an GLA or RTN frame representing the state after
 *   all available GLA and RTN transitions have been taken.
 */

enum parse_status process_terminal(struct parse_state *s,
                                   char *term_name,
                                   int start_offset,
                                   int len)
{
    pop_intfa_frame(s);

    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(s->parse_stack);
    int rtn_term_offset = 0;
    int gla_term_offset = s->token_buffer_len;

    RESIZE_DYNARRAY(s->token_buffer, s->token_buffer_len+1);
    struct terminal *term = DYNARRAY_GET_TOP(s->token_buffer);
    term->name = term_name;
    term->offset = start_offset;
    term->len = len;

    /* Feed tokens to RTNs and GLAs until we have processed all the tokens we have */
    enum parse_status status = PARSE_STATUS_OK;
    enum frame_type frame_type = frame->frame_type;
    do
    {
        struct terminal *rtn_term = &s->token_buffer[rtn_term_offset];
        if(frame_type == FRAME_TYPE_RTN)
        {
            struct rtn_transition *t;
            rtn_term_offset++;

            if(rtn_term->name == NULL)
            {
                /* Skip: RTNs don't process EOF as a terminal, only GLAs do. */
                continue;
            }
            t = find_rtn_terminal_transition(s, rtn_term);
            if(!t)
            {
                if(s->bound_grammar->error_terminal_cb)
                    s->bound_grammar->error_terminal_cb(s, term);

                return PARSE_STATUS_ERROR;
            }

            status = do_rtn_terminal_transition(s, t, rtn_term);
        }
        else
        {
            struct terminal *gla_term = &s->token_buffer[gla_term_offset++];
            status = do_gla_transition(s, gla_term->name, &rtn_term_offset);
        }

        if(status == PARSE_STATUS_OK)
        {
            bool entered_gla;
            status = descend_to_gla(s, &entered_gla, rtn_term->offset+rtn_term->len);
            if(entered_gla)
            {
                gla_term_offset = rtn_term_offset;
            }
        }

        if(status == PARSE_STATUS_OK)
        {
            assert(s->parse_stack_len > 0);
            frame_type = DYNARRAY_GET_TOP(s->parse_stack)->frame_type;
        }
    }
    while(status == PARSE_STATUS_OK &&
          ((frame->frame_type == FRAME_TYPE_RTN && rtn_term_offset < s->token_buffer_len) ||
           (frame->frame_type == FRAME_TYPE_GLA && gla_term_offset < s->token_buffer_len)));

    /* We can have an EOF left over in the token buffer if the EOF token led us
     * to a hard EOF, thus terminating the above loop before our "skip" above could
     * cover this EOF special case. */
    if(rtn_term_offset < s->token_buffer_len &&
       s->token_buffer[rtn_term_offset].name == NULL)
        rtn_term_offset++;

    /* Remove consumed terminals from token_buffer */
    int remaining_terminals = s->token_buffer_len - rtn_term_offset;
    if(remaining_terminals > 0)
    {
        memmove(s->token_buffer, s->token_buffer + rtn_term_offset,
                remaining_terminals * sizeof(*s->token_buffer));
    }
    RESIZE_DYNARRAY(s->token_buffer, remaining_terminals);

    return status;
}

/*
 * find_intfa_transition(): get the transition (if any) out of this state
 * on this character.
 */
struct intfa_transition *find_intfa_transition(struct intfa_frame *frame, char ch)
{
    for(int i = 0; i < frame->intfa_state->num_transitions; i++)
    {
        struct intfa_transition *t = &frame->intfa_state->transitions[i];
        if(ch >= t->ch_low && ch <= t->ch_high)
        {
            return t;
        }
    }

    return NULL;
}

/*
 * do_intfa_transition(): transitions an IntFA frame according to the given
 * char, performing the appropriate GLA/RTN transitions if this puts the IntFA
 * in a final state.
 *
 * Preconditions:
 * - the current stack frame is an IntFA frame
 *
 * Postconditions:
 * - the current stack frame is an IntFA frame unless we have hit a
 *   hard EOF in which case it is an RTN frame.  Note that it could be either
 *   same IntFA frame or a different one.
 *
 * Note: we currently implement longest-match, assuming that the first
 * non-matching character is only one longer than the longest match.
 */
enum parse_status do_intfa_transition(struct parse_state *s,
                                      char ch)
{
    struct intfa_frame *intfa_frame = get_top_intfa_frame(s);
    struct intfa_transition *t = find_intfa_transition(intfa_frame, ch);
    struct parse_stack_frame *frame = GET_PARSE_STACK_FRAME(intfa_frame);
    enum parse_status status;

    /* If this character did not have any transition, but the state we're coming
     * from is final, then longest-match semantics say that we should return
     * the last character's final state as the token.  But if the state we're
     * coming from is *not* final, it's just a parse error. */
    if(!t)
    {
        char *terminal = intfa_frame->intfa_state->final;
        assert(terminal);
        status = process_terminal(s, terminal, frame->start_offset,
                                  s->offset - frame->start_offset);
        if(status != PARSE_STATUS_OK)
            return status;

        intfa_frame = push_intfa_frame_for_gla_or_rtn(s);
        t = find_intfa_transition(intfa_frame, ch);

        if(!t)
        {
            /* Parse error: we encountered a character for which we have no
             * transition. */
            if(s->bound_grammar->error_char_cb)
                s->bound_grammar->error_char_cb(s, ch);
            return PARSE_STATUS_ERROR;
        }
    }

    /* We increment the offset here because we have just crossed the threshold
     * where we have finished processing all terminals for the previous byte and
     * started processing transitions for the current byte. */
    s->offset++;
    intfa_frame->intfa_state = t->dest_state;

    /* If the current state is final and there are no outgoing transitions,
     * we *know* we don't have to wait any longer for the longest match.
     * Transition the RTN or GLA now, for more on-line behavior. */
    if(intfa_frame->intfa_state->final && (intfa_frame->intfa_state->num_transitions == 0))
    {
        status = process_terminal(s, intfa_frame->intfa_state->final,
                                  frame->start_offset,
                                  s->offset - frame->start_offset);
        if(status != PARSE_STATUS_OK)
            return status;

        push_intfa_frame_for_gla_or_rtn(s);
    }

    return PARSE_STATUS_OK;
}

enum parse_status parse(struct parse_state *s, char *buf, int buf_len)
{
    enum parse_status status = PARSE_STATUS_OK;

    /* For the first call, we need to push the initial frame and
     * descend from the starting frame until we hit an IntFA frame. */
    if(s->offset == 0 && s->parse_stack_len == 0)
    {
        push_rtn_frame(s, &s->bound_grammar->grammar->rtns[0], 0);
        bool entered_gla;
        status = descend_to_gla(s, &entered_gla, 0);
        if(status == PARSE_STATUS_OK)
            push_intfa_frame_for_gla_or_rtn(s);
    }
    if(s->parse_stack_len == 0)
    {
        /* This parse_state has already hit hard EOF previously. */
        return PARSE_STATUS_EOF;
    }

    for(int i = 0; i < buf_len && status == PARSE_STATUS_OK; i++)
        status = do_intfa_transition(s, buf[i]);

    return status;
}

bool finish_parse(struct parse_state *s)
{
    /* First deal with an open IntFA frame if there is one.  The frame must
     * be in a start state (in which case we back it out), a final state
     * (in which case we recognize and process the terminal), or both (in
     * which case we back out iff. we are in a GLA state with an EOF transition
     * out).
     */
    struct parse_stack_frame *frame = DYNARRAY_GET_TOP(s->parse_stack);
    if(frame->frame_type == FRAME_TYPE_INTFA)
    {
        struct intfa_frame *intfa_frame = &frame->f.intfa_frame;
        if(intfa_frame->intfa_state->final &&
           intfa_frame->intfa_state == &intfa_frame->intfa->states[0])
        {
            /* the hard case: we don't handle it yet. */
            assert(false);
        }
        else if(intfa_frame->intfa_state->final)
        {
            process_terminal(s, intfa_frame->intfa_state->final,
                             frame->start_offset,
                             s->offset - frame->start_offset);
        }
        else if(intfa_frame->intfa_state == &intfa_frame->intfa->states[0])
        {
            /* Pop the frame like it never happened. */
            pop_intfa_frame(s);
        }
        else
        {
            /* IntFA is in neither a start nor a final state.  This cannot be EOF. */
            return false;
        }
    }

    /* Next deal with an open GLA frame if there is one.  The frame must be in
     * a start state or have an outgoing EOF transition, else we are not at
     * valid EOF. */
    frame = DYNARRAY_GET_TOP(s->parse_stack);
    if(frame->frame_type == FRAME_TYPE_GLA)
    {
        struct gla_frame *gla_frame = &frame->f.gla_frame;
        if(gla_frame->gla_state == &gla_frame->gla->states[0])
        {
            /* GLA is in a start state -- fine, we can just pop it as
             * if it never happened. */
            pop_gla_frame(s);
        }
        else
        {
            /* For this to still be valid EOF, this GLA state must have an
             * outgoing EOF transition, and we must take it now. */
            struct gla_transition *t = find_gla_transition(gla_frame->gla_state, NULL);
            if(!t)
                return false;

            /* process_terminal wants an IntFA frame to pop. */
            push_empty_frame(s, FRAME_TYPE_INTFA, s->offset);
            process_terminal(s, NULL, s->offset, 0);

            /* Pop any GLA states that the previous may have pushed. */
            while(s->parse_stack_len > 0 &&
                  DYNARRAY_GET_TOP(s->parse_stack)->frame_type != FRAME_TYPE_RTN)
                pop_frame(s);
        }
    }

    /* Now we should have only RTN frames open.  Starting from the top, check
     * that each frame's dest_state is a final state (or the actual current
     * state in the bottommost frame). */
    if(s->parse_stack_len > 0)  // will be 0 (no open frames) if we already hit hard EOF.
    {
        for(int i = 0; i < s->parse_stack_len - 1; i++)
        {
            struct rtn_frame *rtn_frame = &s->parse_stack[i].f.rtn_frame;
            assert(rtn_frame->rtn_transition);
            if(!rtn_frame->rtn_transition->dest_state->is_final)
                return false;
        }

        struct rtn_frame *rtn_frame = &s->parse_stack[s->parse_stack_len-1].f.rtn_frame;
        if(!rtn_frame->rtn_state->is_final)
            return false;

        /* We are truly in a state where EOF is ok.  Pop remaining RTN frames to
         * call callbacks appropriately. */
        while(s->parse_stack_len > 0)
        {
            /* What should we do if the user cancels while the final RTN frames
             * are being popped?  It's kind of a weird thing to do.  Options
             * are to ignore it (we're finishing the parse anyway) or to stop.
             * For now we ignore. */
            pop_rtn_frame(s);
        }
    }

    return true;
}

struct parse_state *alloc_parse_state()
{
    struct parse_state *state = malloc(sizeof(*state));
    INIT_DYNARRAY(state->parse_stack, 0, 16);
    INIT_DYNARRAY(state->token_buffer, 0, 2);
    return state;
}

struct parse_state *dup_parse_state(struct parse_state *orig)
{
    struct parse_state *copy = alloc_parse_state();
    *copy = *orig;  // erroneously copies pointers to dynarrays, but we'll fix in a sec.

    RESIZE_DYNARRAY(copy->parse_stack, orig->parse_stack_len);
    for(int i = 0; i < orig->parse_stack_len; i++)
        copy->parse_stack[i] = orig->parse_stack[i];

    RESIZE_DYNARRAY(copy->token_buffer, orig->token_buffer_len);
    for(int i = 0; i < orig->token_buffer_len; i++)
        copy->token_buffer[i] = orig->token_buffer[i];

    return copy;
}

void free_parse_state(struct parse_state *s)
{
    FREE_DYNARRAY(s->parse_stack);
    FREE_DYNARRAY(s->token_buffer);
    free(s);
}

void init_parse_state(struct parse_state *s, struct bound_grammar *bg)
{
    s->offset = 0;
    s->open_terminal_offset = 0;
    s->bound_grammar = bg;
    RESIZE_DYNARRAY(s->parse_stack, 0);
    RESIZE_DYNARRAY(s->token_buffer, 0);
}

enum parse_status parse_file(struct parse_state *state, FILE *file, void *user_data)
{
    struct buffer *buffer = malloc(sizeof(*buffer));
    INIT_DYNARRAY(buffer->buf, 0, 4096);
    buffer->buf_offset = 0;
    buffer->bytes_parsed = 0;
    buffer->user_data = user_data;
    state->user_data = buffer;

    /* The minimum amount of the data in the buffer that we want to be new data
     * each time.  This number shrinks as the amount of data we're preserving
     * from open tokens grows.  If the number is below this number we increase
     * our buffer size. */
    const int min_new_data = 4000;

    enum parse_status status;
    bool is_eof = false;
    do
    {
        /* Make sure we have space for at least min_new_data new data.
         * RESIZE_DYNARRAY() will round up to a power of two. */
        RESIZE_DYNARRAY(buffer->buf, buffer->buf_len + min_new_data);
        size_t bytes_to_read = buffer->buf_size - buffer->buf_len;

        /* Do the I/O and check for errors. */
        size_t bytes_read = fread(buffer->buf + buffer->buf_len, 1, bytes_to_read, file);
        if(bytes_read < bytes_to_read)
        {
            if(ferror(file))
            {
                status = PARSE_STATUS_IO_ERROR;
                break;
            }
            else if(feof(file))
            {
                is_eof = true;
            }
        }

        /* Do the parse.  Start past whatever bytes we previously saved. */
        char *parse_start = buffer->buf + buffer->buf_len;
        buffer->buf_len += bytes_read;
        status = parse(state, parse_start, bytes_read);

        /* Preserve all data from tokens that haven't been returned yet:
         *
         *         buf                                                 size len
         *         |                                                     |   |
         *         v                                                     v   v
         * Buffer: -----------------------------------------------------------
         *         ^    ^                                   ^         ^
         *         |    |                                   |         |
         *  buf_offset  |                                   |  state->offset
         *              |                                   |
         *       previous value of                  current value of
         *   state->open_terminal_offset       state->open_terminal_offset
         *
         *         |----| <-- Data we were previously saving.
         *
         *                 Data we should now be saving --> |------------|
         */

        size_t bytes_to_discard = state->open_terminal_offset - buffer->buf_offset;
        size_t bytes_to_save = buffer->buf_size - bytes_to_discard;
        char *buf_to_save_from = buffer->buf + bytes_to_discard;
        assert(bytes_to_discard < buffer->buf_size);  /* hasn't overflowed. */

        memmove(buffer->buf, buf_to_save_from, bytes_to_save);
        buffer->buf_offset += bytes_to_discard;
        buffer->buf_len = bytes_to_save;
    } while(status == PARSE_STATUS_OK && !is_eof);

    if(status == PARSE_STATUS_EOF || (status == PARSE_STATUS_OK && is_eof))
    {
        if(finish_parse(state))
        {
            if(!feof(file) || buffer->buf_len > 0)
            {
                /* There was data left over -- we hit grammar EOF before
                 * file EOF. */
                status = PARSE_STATUS_OK;
            }
            else
            {
                status = PARSE_STATUS_PREMATURE_EOF_ERROR;
            }
        }
        else
            status = PARSE_STATUS_PREMATURE_EOF_ERROR;
    }

    FREE_DYNARRAY(buffer->buf);
    free(buffer);

    return status;
}

/*
 * Local Variables:
 * c-file-style: "bsd"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:et:sts=4:sw=4
 */
