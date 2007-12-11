
#include "bc_read_stream_lua.h"
#include "interpreter.h"

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#include <string.h>

struct gazelle_grammar_lua
{
  struct grammar *g;
};

struct gazelle_rtn_lua
{
  struct rtn *rtn;
};

struct gazelle_rtn_state_lua
{
  struct rtn_state *rtn_state;
};

struct gazelle_rtn_transition_lua
{
  struct rtn_transition *rtn_transition;
};

static void *newobj(lua_State *L, char *type, int size)
{
  void *ptr = lua_newuserdata(L, size);
  luaL_getmetatable(L, type);
  lua_setmetatable(L, -2);
  return ptr;
}

static bool get_from_cache(lua_State *L, void *ptr)
{
  static const luaL_reg no_methods[] = {{NULL, NULL}};
  luaL_register(L, "gazelle", no_methods);  /* push the table for this module */
  lua_getfield(L, -1, "ObjectCache"); /* push our object cache */

  /* attempt to get our stored value */
  lua_pushlightuserdata(L, ptr);
  lua_gettable(L, -2);

  if(lua_isnil(L, -1))
  {
    /* object doesn't exist in the cache yet.
     * leave the mod table and object cache on the stack -- we'll
     * pop them when the caller makes the (required) call to
     * put_in_cache() */
    lua_pop(L, 1);
    return false;
  }
  else
  {
    /* we found the object.  pop everything else off the stack and leave it at the top. */
    lua_replace(L, -3);
    lua_pop(L, 1);
    return true;
  }
}

/*
 * When this is called the stack looks like:
 *  - mod table
 *  - object cache table
 *  - val to put in cache
 */
static void put_in_cache(lua_State *L, void *ptr)
{
  lua_pushlightuserdata(L, ptr);
  lua_pushvalue(L, -2);
  lua_rawset(L, -4);  /* store this in the object cache */

  lua_replace(L, -3);

  lua_pop(L, 1); /* pop the mod table */
}

static void get_rtn(lua_State *L, struct rtn *rtn)
{
  if(!get_from_cache(L, rtn))
  {
    struct gazelle_rtn_lua *rtn_obj = newobj(L, "gazelle.rtn", sizeof(*rtn_obj));
    rtn_obj->rtn = rtn;
    put_in_cache(L, rtn);
  }
}

static void get_rtn_state(lua_State *L, struct rtn_state *rtn_state)
{
  if(!get_from_cache(L, rtn_state))
  {
    struct gazelle_rtn_state_lua *rtn_state_obj = newobj(L, "gazelle.rtn_state", sizeof(*rtn_state_obj));
    rtn_state_obj->rtn_state = rtn_state;
    put_in_cache(L, rtn_state);
  }
}


/*
 * global functions
 */

static int gazelle_load_grammar(lua_State *L)
{
  struct bc_read_stream_lua *s = luaL_checkudata(L, 1, "bc_read_stream");
  struct gazelle_grammar_lua *g = newobj(L, "gazelle.grammar", sizeof(*g));
  g->g = load_grammar(s->s);
  if(!g->g)
    return luaL_error(L, "Couldn't load grammar!");
  else
    return 1;
}

static const luaL_reg global_functions[] =
{
  {"load_grammar", gazelle_load_grammar},
  {NULL, NULL}
};

/*
 * methods for "grammar" object
 */

static int gazelle_grammar_strings(lua_State *L)
{
  struct gazelle_grammar_lua *g = luaL_checkudata(L, 1, "gazelle.grammar");
  lua_newtable(L);
  for(int i = 0; g->g->strings[i] != NULL; i++)
  {
    lua_pushstring(L, g->g->strings[i]);
    lua_rawseti(L, -2, i+1);
  }
  return 1;
}

static int gazelle_grammar_rtns(lua_State *L)
{
  struct gazelle_grammar_lua *g = luaL_checkudata(L, 1, "gazelle.grammar");
  lua_newtable(L);
  for(int i = 0; i < g->g->num_rtns; i++)
  {
    get_rtn(L, &g->g->rtns[i]);
    lua_rawseti(L, -2, i+1);
  }
  return 1;
}

static int gazelle_grammar_rtn(lua_State *L)
{
  struct gazelle_grammar_lua *g = luaL_checkudata(L, 1, "gazelle.grammar");
  const char *rtn_name = luaL_checkstring(L, 2);
  for(int i = 0; i < g->g->num_rtns; i++)
  {
    if(strcmp(g->g->rtns[i].name, rtn_name) == 0)
    {
      get_rtn(L, &g->g->rtns[i]);
      return 1;
    }
  }
  return 0;
}

static const luaL_reg grammar_methods[] =
{
  {"rtns", gazelle_grammar_rtns},
  {"rtn", gazelle_grammar_rtn},
  {"strings", gazelle_grammar_strings},
  {NULL, NULL}
};

/*
 * methods for "rtn" object
 */

static int gazelle_rtn_name(lua_State *L)
{
  struct gazelle_rtn_lua *rtn = luaL_checkudata(L, 1, "gazelle.rtn");
  lua_pushstring(L, rtn->rtn->name);
  return 1;
}

static int gazelle_rtn_num_slots(lua_State *L)
{
  struct gazelle_rtn_lua *rtn = luaL_checkudata(L, 1, "gazelle.rtn");
  lua_pushnumber(L, rtn->rtn->num_slots);
  return 1;
}

static int gazelle_rtn_ignore_terminals(lua_State *L)
{
  struct gazelle_rtn_lua *rtn = luaL_checkudata(L, 1, "gazelle.rtn");
  lua_newtable(L);
  for(int i = 0; i < rtn->rtn->num_ignore; i++)
  {
    lua_pushstring(L, rtn->rtn->ignore_terminals[i]);
    lua_rawseti(L, -2, i+1);
  }
  return 1;
}

static int gazelle_rtn_states(lua_State *L)
{
  struct gazelle_rtn_lua *rtn = luaL_checkudata(L, 1, "gazelle.rtn");
  lua_newtable(L);
  for(int i = 0; i < rtn->rtn->num_states; i++)
  {
    get_rtn_state(L, &rtn->rtn->states[i]);
    lua_rawseti(L, -2, i+1);
  }
  return 1;
}

static const luaL_reg rtn_methods[] =
{
  {"name", gazelle_rtn_name},
  {"num_slots", gazelle_rtn_num_slots},
  {"ignore_terminals", gazelle_rtn_ignore_terminals},
  {"states", gazelle_rtn_states},
  {NULL, NULL}
};

/*
 * methods for "rtn_state" objects
 */

static int gazelle_rtn_state_is_final(lua_State *L)
{
  struct gazelle_rtn_state_lua *rtn_state = luaL_checkudata(L, 1, "gazelle.rtn_state");
  lua_pushboolean(L, rtn_state->rtn_state->is_final);
  return 1;
}

static int gazelle_rtn_state_transitions(lua_State *L)
{
  struct gazelle_rtn_state_lua *rtn_state = luaL_checkudata(L, 1, "gazelle.rtn_state");
  lua_newtable(L);
  for(int i = 0; i < rtn_state->rtn_state->num_transitions; i++)
  {
    struct rtn_transition *t = &rtn_state->rtn_state->transitions[i];
    lua_newtable(L);
    switch(t->transition_type)
    {
      case TERMINAL_TRANSITION:
        lua_pushstring(L, "terminal");
        lua_rawseti(L, -2, 1);
        lua_pushstring(L, t->edge.terminal_name);
        lua_rawseti(L, -2, 2);
        break;

      case NONTERM_TRANSITION:
        lua_pushstring(L, "nonterm");
        lua_rawseti(L, -2, 1);
        get_rtn(L, t->edge.nonterminal);
        lua_rawseti(L, -2, 2);
        break;

      case DECISION:
        lua_pushstring(L, "decision");
        lua_rawseti(L, -2, 1);
        break;

      default:
        return luaL_error(L, "corrupt grammar: invalid transition type!");
    }

    int table_size = lua_objlen(L, -1);
    get_rtn_state(L, t->dest_state);
    lua_rawseti(L, -2, ++table_size);
    lua_pushstring(L, t->slotname);
    lua_rawseti(L, -2, ++table_size);
    lua_pushnumber(L, t->slotnum);
    lua_rawseti(L, -2, ++table_size);

    lua_rawseti(L, -2, i+1);
  }
  return 1;
}

static const luaL_reg rtn_state_methods[] =
{
  {"is_final", gazelle_rtn_state_is_final},
  {"transitions", gazelle_rtn_state_transitions},
  {NULL, NULL}
};

/*
 * methods for "rtn_transition" objects
 */

static const luaL_reg rtn_transition_methods[] =
{
  {"is_final", gazelle_rtn_state_is_final},
  {"transitions", gazelle_rtn_state_transitions},
  {NULL, NULL}
};

void register_object(lua_State *L, char *obj_name, const luaL_reg *methods)
{
  luaL_newmetatable(L, obj_name);

  /* metatable.__index = metatable */
  lua_pushvalue(L, -1); /* duplicates the metatable */
  lua_setfield(L, -2, "__index");

  luaL_register(L, NULL, methods);
}

int luaopen_gazelle(lua_State *L)
{
  register_object(L, "gazelle.grammar", grammar_methods);
  register_object(L, "gazelle.rtn", rtn_methods);
  register_object(L, "gazelle.rtn_state", rtn_state_methods);

  luaL_register(L, "gazelle", global_functions);
  lua_newtable(L);
  lua_setfield(L, -2, "ObjectCache");

  return 1;
}

/*
 * Local Variables:
 * c-file-style: "bsd"
 * c-basic-offset: 2
 * indent-tabs-mode: nil
 * End:
 * vim:et:sts=2:sw=2
 */
