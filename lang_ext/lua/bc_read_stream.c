
#include "bc_read_stream.h"

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

struct bc_read_stream_lua
{
    struct bc_read_stream *s;
};

static int bc_read_stream_lua_open(lua_State *L)
{
  const char *filename = luaL_checkstring(L, 1);
  struct bc_read_stream_lua *s = lua_newuserdata(L, sizeof(*s));
  luaL_getmetatable(L, "bc_read_stream");
  lua_setmetatable(L, -2);
  s->s = bc_rs_open_file(filename);
  if(!s->s)
    return luaL_error(L, "Couldn't open bitcode file %s", filename);
  else
    return 1;
}

static int bc_read_stream_lua_next_record(lua_State *L)
{
  struct bc_read_stream_lua *s = luaL_checkudata(L, 1, "bc_read_stream");
  if(!s)
    return luaL_argerror(L, 1, "not a userdata");

  struct record_info ri = bc_rs_next_data_record(s->s);

  if(ri.record_type == Eof)
  {
    lua_pushnil(L);
    return 1;
  }
  else if(ri.record_type == DataRecord)
  {
    lua_pushstring(L, "data");
    lua_pushnumber(L, ri.id);
    for(int i = 0; i < bc_rs_get_record_size(s->s); i++)
      lua_pushnumber(L, bc_rs_read_64(s->s, i));
    return bc_rs_get_record_size(s->s) + 2;
  }
  else if(ri.record_type == StartBlock)
  {
    lua_pushstring(L, "startblock");
    lua_pushnumber(L, ri.id);
    return 2;
  }
  else if(ri.record_type == EndBlock)
  {
    lua_pushstring(L, "endblock");
    return 1;
  }

  /* compiler too stupid to realize that this is unreachable */
  return 0;
}

static const luaL_reg global_functions[] =
{
  {"open", bc_read_stream_lua_open},
  {NULL, NULL}
};

static const luaL_reg read_stream_methods[] =
{
  {"next_record", bc_read_stream_lua_next_record},
  {NULL, NULL}
};

int luaopen_bc_read_stream(lua_State *L)
{
  luaL_newmetatable(L, "bc_read_stream");

  /* metatable.__index = metatable */
  lua_pushvalue(L, -1); /* duplicates the metatable */
  lua_setfield(L, -2, "__index");

  luaL_register(L, NULL, read_stream_methods);
  luaL_register(L, "bc_read_stream", global_functions);
  return 0;
}

