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
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_length++];
    frame->frame_type = FRAME_TYPE_INTFA;
    struct intfa_frame *intfa_frame = frame->f.intfa_frame;
    intfa_frame->intfa        = intfa;
    intfa_frame->intfa_state  = &intfa->states[0];
    intfa_frame->start_offset = s->offset;
    return intfa_frame;
}

struct intfa_frame *push_gla_frame(struct parse_state *s, struct gla *gla)
{
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_length++];
    frame->frame_type = FRAME_TYPE_GLA;
    struct gla_frame *gla_frame = frame->f.gla_frame;
    gla_frame->gla          = gla;
    gla_frame->gla_state    = &gla->states[0];
    gla_frame->start_offset = s->offset;
    return push_intfa_frame(s, gla_frame->gla_state->d.nonfinal_info.intfa);
}

struct intfa_frame *push_rtn_frame(struct parse_state *s, struct rtn_transition *t)
{
    struct rtn_frame *old_rtn_frame = &s->parse_stack[s->parse_stack_length-1].f.rtn_frame;
    struct parse_stack_frame *new_frame = &s->parse_stack[s->parse_stack_length++];
    new_frame->frame_type = FRAME_TYPE_RTN;
    struct rtn_frame *new_rtn_frame = new_frame->f.rtn_frame;

    old_rtn_frame->rtn_transition = t;
    new_rtn_frame->rtn            = t->edge.nonterminal;
    new_rtn_frame->rtn_state      = &new_rtn_frame->rtn->states[0];
}

struct intfa_frame *descend_from_rtn(struct parse_state *s)
{
    struct parse_stack_frame *frame = &s->parse_stack[s->parse_stack_length-1];
    while(frame->frame_type == FRAME_TYPE_RTN)
    {
        struct rtn_frame *rtn_frame = &frame->f.rtn_frame;
        switch(rtn_frame->rtn_state->lookahead_type)
        {
          case STATE_HAS_INTFA:
            return push_intfa_frame(state, rtn_frame->rtn_state->d.state_intfa);
            break;

          case STATE_HAS_GLA:
            return push_gla_frame(s, rtn_frame->rtn_state->d.state_gla);
            break;

          case STATE_HAS_NEITHER:
            /* An RTN state has neither an IntFA or a GLA in only two cases:
             * - it is a final state with no outgoing transitions
             * - it is a nonfinal state with only one transition (a nonterminal) */
            assert(rtn_state->num_transitions < 2);
            if(rtn_state->num_transitions == 0)
            {
                /* Final state */
                frame = pop_frame(state);
                if(frame == NULL) return NULL;
            }
            else if(rtn_state->num_transitions == 1)
            {
                assert(rtn_state->transitions[0].transition_type == NONTERM_TRANSITION);
                frame = push_rtn_frame(state, &rtn_state->transitions[0]);
            }
            break;
        }
    }
}

struct rtn_frame *do_rtn_terminal_transition(struct parse_state *s,
                                             char *terminal)
{
    struct rtn_frame *rtn_frame = &s->parse_stack[s->parse_stack_length-1].f.rtn_frame;
    for(int i = 0; i < rtn_frame->rtn_state->num_transitions; i++)
    {
        struct rtn_transition *t = rtn_frame->rtn_state->transitions[i];
        if(t->transition_type == TERMINAL_TRANSITION && t->edge.terminal_name == terminal)
        {
            rtn_frame->rtn_state = t->dest_state;
            return rtn_frame;
        }
    }

    return NULL;
}

struct intfa_frame *do_rtn_or_gla_terminal_transition(struct parse_state *s,
                                                      char *terminal)
{
    struct parse_stack_frame *frame = s->parse_stack[s->parse_stack_length-1];
    if(frame->frame_type == FRAME_TYPE_RTN)
    {
        return do_rtn_terminal_transition(s, terminal);
    }
    else
    {
        return do_gla_transition(s, terminal);
    }
    assert(false);
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
 * - the current stack frame is an IntFA frame, unless we have hit a
 *   hard EOF in which case it is an RTN frame.
 */
struct parse_stack_frame *do_gla_transition(struct parse_state *s, char *term)
{
    struct parse_stack_frame *frame = s->parse_stack[s->parse_stack_length-1];
    assert(frame->frame_type == FRAME_TYPE_GLA);
    assert(frame->f.gla_frame.gla_state->is_final == false);
    struct gla_state *gla_state = frame->f.gla_frame.gla_state;

    bool found_transition = false;
    for(int = 0; i < gla_state->d.nonfinal.num_transitions; i++)
    {
        struct gla_transition *t = &gla_state->d.nonfinal.transitions[i];
        if(t->term == term)
        {
            found_transition = true;
            frame->f.gla_frame.gla_state = t->dest_state;
        }
    }
    assert(found_transition);

    if(gla_state->is_final)
    {
        /* pop the GLA frame (since now we know what to do) and use its
         * information to make one or more RTN transitions */
        struct final_info *info = &gla_state.d.final;
        frame = pop_frame(state);

        for(int i = 0; i < info.num_rtn_transitions; i++)
        {
            int offset = &info.rtn_transition_offsets[i];
            if(offset == 0)
            {
                frame = pop_rtn_frame(state);
            }
            else
            {
                struct rtn_transition *t = frame->f.rtn_frame.rtn_state.transitions[offset-1];
                if(t->transition_type == TERMINAL_TRANSITION)
                {
                    /* The transition must match what we have in the token buffer */
                    struct terminal *term = state->token_buffer[state->token_buffer_offset++];
                    assert(state->token_buffer_offset <= state->token_buffer_len);
                    assert(term->name == t->edge.terminal_name);
                    do_rtn_transition(frame, t);
                }
                else
                {
                    frame = push_rtn_frame(state, t);
                }
            }
        }
        frame = push_frames(state);
    }
    else
    {
        push_intfa_frame(state, gla_state.d.nonfinal.intfa);
    }
}

/*
 * find_intfa_transition(): get the transition (if any) out of this state
 * on this character.
 */
struct intfa_transition *find_intfa_transition(struct intfa_frame *frame, char ch)
{
    for(int i = 0; i < frame->intfa_state->num_transitions; i++)
    {
        struct intfa_transition *t = frame->intfa_state->transitions[i];
        if(next_char >= t->ch_low && next_char <= t->ch_high)
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
                                        struct intfa_frame *frame,
                                        char ch)
{
    struct intfa_transition *t = find_intfa_transition(frame, ch);

    /* If this character did not have any transition, but the state we're coming
     * from is final, then longest-match semantics say that we should return
     * the last character's final state as the token.  But if the state we're
     * coming from is *not* final, it's just a parse error. */
    if(!t)
    {
        char *terminal = frame->intfa_state->final;
        assert(terminal);
        pop_frame(s);
        frame = do_rtn_or_gla_terminal_transition(s, terminal);
        assert(frame);  // if this fails, it means that we hit a hard EOF

        /* This must succeed this time or it is a parse error */
        t = find_intfa_transition(frame, ch);
        assert(t);
    }

    frame->intfa_state = t->dest_state;

    /* If the current state is final and there are no outgoing transitions,
     * we *know* we don't have to wait any longer for the longest match.
     * Transition the RTN or GLA now, for more on-line behavior. */
    if(frame->intfa_state->final && (frame->intfa_state->num_transitions == 0))
    {
        frame = do_rtn_or_gla_transition(s, terminal);
    }

    return frame;
}

enum parse_status parse(struct grammar *g, struct parse_state *s,
                        char *buf, int buf_len,
                        int *out_consumed_buf_len, bool *out_eof_ok)
{
    struct intfa_frame *intfa_frame;
    if(s->offset == 0)
    {
        intfa_frame = descend_from_rtn(s);
    }
    else
    {
        intfa_frame = &s->parse_stack[s->parse_stack_length-1].f.intfa_frame;
    }

    for(int i = 0; i < buf_len; i++)
    {
        intfa_frame = do_intfa_transition(s, intfa_frame, buf[i]);
        if(intfa_frame == NULL)
        {
            *out_consumed_buf_len = i;
            *eof_ok = true;
            return PARSE_STATUS_EOF;
        }
    }

    if(s->parse_stack[1].frame_type != FRAME_TYPE_RTN &&
       s->parse_stack[0].f.rtn_frame.rtn_state->is_final)
    {
        *eof_ok = true;
    }
    else
    {
        *eof_ok = false;
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
