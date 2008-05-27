/*********************************************************************

  Gazelle: a system for building fast, reusable parsers

  interpreter.c

  Once a compiled grammar has been loaded into memory, the routines
  in this file are what actually does the parsing.  This file is an
  "interpreter" in the sense that it parses the input by using the
  grammar as a data structure -- no grammar-specific code is ever
  generated or executed.  Despite this, it is still quite fast, and
  has a very low memory footprint.

  Copyright (c) 2008 Joshua Haberman.  See LICENSE for details.

*********************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include "interpreter.h"

struct intfa_frame *push_intfa_frame(struct parse_state *s, struct intfa *intfa)
{
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_len++];
    frame->frame_type = FRAME_TYPE_INTFA;
    struct intfa_frame *intfa_frame = &frame->f.intfa_frame;
    intfa_frame->intfa        = intfa;
    intfa_frame->intfa_state  = &intfa->states[0];
    intfa_frame->start_offset = s->offset;
    return intfa_frame;
}

struct parse_stack_frame *push_gla_frame(struct parse_state *s, struct gla *gla)
{
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_len++];
    frame->frame_type = FRAME_TYPE_GLA;
    struct gla_frame *gla_frame = &frame->f.gla_frame;
    gla_frame->gla          = gla;
    gla_frame->gla_state    = &gla->states[0];
    gla_frame->start_offset = s->offset;
    return frame;
}

struct parse_stack_frame *push_rtn_frame(struct parse_state *s, struct rtn_transition *t)
{
    struct rtn_frame *old_rtn_frame = &s->parse_stack[s->parse_stack_len-1].f.rtn_frame;
    struct parse_stack_frame *new_frame = &s->parse_stack[s->parse_stack_len++];
    new_frame->frame_type = FRAME_TYPE_RTN;
    struct rtn_frame *new_rtn_frame = &new_frame->f.rtn_frame;

    old_rtn_frame->rtn_transition = t;
    new_rtn_frame->rtn            = t->edge.nonterminal;
    new_rtn_frame->rtn_state      = &new_rtn_frame->rtn->states[0];
    return new_frame;
}

struct parse_stack_frame *pop_frame(struct parse_state *s)
{
    s->parse_stack_len--;
    return &s->parse_stack[s->parse_stack_len-1];
}

struct parse_stack_frame *descend_to_gla(struct parse_state *s, bool *entered_gla)
{
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_len-1];
    *entered_gla = false;

    while(frame->frame_type == FRAME_TYPE_RTN)
    {
        struct rtn_frame *rtn_frame = &frame->f.rtn_frame;
        switch(rtn_frame->rtn_state->lookahead_type)
        {
          case STATE_HAS_INTFA:
            return frame;
            break;

          case STATE_HAS_GLA:
            *entered_gla = true;
            return push_gla_frame(s, rtn_frame->rtn_state->d.state_gla);
            break;

          case STATE_HAS_NEITHER:
            /* An RTN state has neither an IntFA or a GLA in only two cases:
             * - it is a final state with no outgoing transitions
             * - it is a nonfinal state with only one transition (a nonterminal) */
            assert(rtn_frame->rtn_state->num_transitions < 2);
            if(rtn_frame->rtn_state->num_transitions == 0)
            {
                /* Final state */
                frame = pop_frame(s);
                if(frame == NULL) return NULL;
            }
            else if(rtn_frame->rtn_state->num_transitions == 1)
            {
                assert(rtn_frame->rtn_state->transitions[0].transition_type == NONTERM_TRANSITION);
                frame = push_rtn_frame(s, &rtn_frame->rtn_state->transitions[0]);
            }
            break;
        }
    }
    return frame;
}

struct intfa_frame *descend_from_rtn(struct parse_state *s)
{
    //TODO
    return NULL;
}

struct parse_stack_frame *do_rtn_transition(struct parse_state *s,
                                            struct rtn_transition *t)
{
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_len-1];
    struct rtn_frame *rtn_frame = &frame->f.rtn_frame;
    assert(t->transition_type == TERMINAL_TRANSITION);
    rtn_frame->rtn_state = t->dest_state;
    return frame;
}

struct parse_stack_frame *do_rtn_terminal_transition(struct parse_state *s,
                                                     struct terminal *terminal)
{
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_len-1];
    struct rtn_frame *rtn_frame = &frame->f.rtn_frame;
    for(int i = 0; i < rtn_frame->rtn_state->num_transitions; i++)
    {
        struct rtn_transition *t = &rtn_frame->rtn_state->transitions[i];
        if(t->transition_type == TERMINAL_TRANSITION && t->edge.terminal_name == terminal->name)
        {
            return do_rtn_transition(s, t);
        }
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
struct parse_stack_frame *do_gla_transition(struct parse_state *s,
                                            int *gla_term_offset,
                                            int *rtn_term_offset)
{
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_len-1];
    assert(frame->frame_type == FRAME_TYPE_GLA);
    assert(frame->f.gla_frame.gla_state->is_final == false);
    struct gla_state *gla_state = frame->f.gla_frame.gla_state;
    struct terminal *gla_term = &s->token_buffer[(*gla_term_offset)++];

    bool found_transition = false;
    for(int i = 0; i < gla_state->d.nonfinal.num_transitions; i++)
    {
        struct gla_transition *t = &gla_state->d.nonfinal.transitions[i];
        if(t->term == gla_term->name)
        {
            found_transition = true;
            frame->f.gla_frame.gla_state = t->dest_state;
        }
    }
    assert(found_transition);

    if(gla_state->is_final)
    {
        /* pop the GLA frame (since now we know what RTN transition to take)
         * and use its information to make an RTN transition */
        int offset = gla_state->d.final.transition_offset;
        frame = pop_frame(s);
        if(offset == 0)
        {
            frame = pop_frame(s);
        }
        else
        {
            struct rtn_transition *t = &frame->f.rtn_frame.rtn_state->transitions[offset-1];
            if(t->transition_type == TERMINAL_TRANSITION)
            {
                /* The transition must match what we have in the token buffer */
                struct terminal *term = &s->token_buffer[(*rtn_term_offset)++];
                assert(term->name == t->edge.terminal_name);
                do_rtn_transition(s, t);
            }
            else
            {
                frame = push_rtn_frame(s, t);
            }
        }
    }
    return frame;
}

/*
 * do_rtn_or_gla_terminal_transition(): transitions either a GLA or an RTN
 * frame given this terminal.  If the current frame is a GLA frame, this
 * could transition us into a GLA final state, which will trigger an RTN
 * transition and possibly one or more GLA transitions for a different GLA.
 *
 * Preconditions:
 * - the current stack frame is either a GLA or an RTN frame.
 * - the given terminal can be recognized by the current GLA or RTN state
 *
 * Postconditions:
 * - the current stack frame is an intfa frame
 */

struct intfa_frame *process_terminal(struct parse_state *s,
                                     char *term_name,
                                     int start_offset,
                                     int len)
{
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_len-1];
    int rtn_term_offset = 0;
    int gla_term_offset = s->token_buffer_len;
    struct terminal *term = &s->token_buffer[s->token_buffer_len++];
    term->name = term_name;
    term->offset = start_offset;
    term->len = len;

    /* Feed tokens to RTNs and GLAs until we have processed all the tokens we have */
    while((frame->frame_type = FRAME_TYPE_RTN && rtn_term_offset < s->token_buffer_len) ||
          (frame->frame_type == FRAME_TYPE_GLA && gla_term_offset < s->token_buffer_len))
    {
        if(frame->frame_type == FRAME_TYPE_RTN)
        {
            frame = do_rtn_terminal_transition(s, &s->token_buffer[rtn_term_offset++]);
        }
        else
        {
            frame = do_gla_transition(s, &gla_term_offset, &rtn_term_offset);
        }
        bool entered_gla;
        frame = descend_to_gla(s, &entered_gla);
        if(entered_gla)
        {
            gla_term_offset = rtn_term_offset;
        }
    }

    /* Remove consumed terminals from token_buffer */
    int remaining_terminals = s->token_buffer_len - rtn_term_offset;
    if(remaining_terminals > 0)
    {
        memmove(s->token_buffer, s->token_buffer + rtn_term_offset,
                remaining_terminals * sizeof(*s->token_buffer));
    }
    s->token_buffer_len = remaining_terminals;

    /* Now that we have processed all terminals that we currently can, push
     * an intfa frame to handle the next bytes */
    if(frame->frame_type == FRAME_TYPE_GLA)
    {
        return push_intfa_frame(s, frame->f.gla_frame.gla_state->d.nonfinal.intfa);
    }
    else if(frame->frame_type == FRAME_TYPE_RTN)
    {
        return push_intfa_frame(s, frame->f.rtn_frame.rtn_state->d.state_intfa);
    }
    return NULL;
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
struct intfa_frame *do_intfa_transition(struct parse_state *s,
                                        struct intfa_frame *intfa_frame,
                                        char ch)
{
    struct intfa_transition *t = find_intfa_transition(intfa_frame, ch);

    /* If this character did not have any transition, but the state we're coming
     * from is final, then longest-match semantics say that we should return
     * the last character's final state as the token.  But if the state we're
     * coming from is *not* final, it's just a parse error. */
    if(!t)
    {
        char *terminal = intfa_frame->intfa_state->final;
        assert(terminal);
        pop_frame(s);
        intfa_frame = process_terminal(s, terminal, intfa_frame->start_offset,
                                       s->offset - intfa_frame->start_offset);
        assert(intfa_frame);  // if this fails, it means that we hit a hard EOF

        /* This must succeed this time or it is a parse error */
        t = find_intfa_transition(intfa_frame, ch);
        assert(t);
    }

    intfa_frame->intfa_state = t->dest_state;

    /* If the current state is final and there are no outgoing transitions,
     * we *know* we don't have to wait any longer for the longest match.
     * Transition the RTN or GLA now, for more on-line behavior. */
    if(intfa_frame->intfa_state->final && (intfa_frame->intfa_state->num_transitions == 0))
    {
        intfa_frame = process_terminal(s, intfa_frame->intfa_state->final,
                                       intfa_frame->start_offset,
                                       s->offset - intfa_frame->start_offset + 1);
    }

    return intfa_frame;
}

enum parse_status parse(struct grammar *g, struct parse_state *s,
                        char *buf, int buf_len,
                        int *out_consumed_buf_len, bool *out_eof_ok)
{
    struct intfa_frame *intfa_frame;

    /* For the first parse, we need to descend from the starting frame
     * until we hit an IntFA frame. */
    if(s->offset == 0)
    {
        intfa_frame = descend_from_rtn(s);
    }
    else
    {
        struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_len-1];
        assert(frame->frame_type == FRAME_TYPE_INTFA);
        intfa_frame = &frame->f.intfa_frame;
    }

    for(int i = 0; i < buf_len; i++)
    {
        intfa_frame = do_intfa_transition(s, intfa_frame, buf[i]);
        s->offset++;
        if(intfa_frame == NULL)
        {
            *out_consumed_buf_len = i;
            *out_eof_ok = true;
            return PARSE_STATUS_EOF;
        }
    }

    if(s->parse_stack[1].frame_type != FRAME_TYPE_RTN &&
       s->parse_stack[0].f.rtn_frame.rtn_state->is_final)
    {
        *out_eof_ok = true;
    }
    else
    {
        *out_eof_ok = false;
    }

    return PARSE_STATUS_OK;
}


/*
 * Local Variables:
 * c-file-style: "bsd"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 * vim:et:sts=4:sw=4
 */
