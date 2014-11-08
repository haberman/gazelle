
#ifndef __BC_READ_STREAM_LUA__
#define __BC_READ_STREAM_LUA__

#include <gazelle/bc_read_stream.h>
#include "lua.h"
#include "lauxlib.h"

struct bc_read_stream_lua
{
  struct bc_read_stream *s;
};

#if LUA_VERSION_NUM == 501

static void newlib(lua_State *L, const char *name, const luaL_Reg *funcs) {
  luaL_register(L, name, funcs);
}

#define setfuncs(L, l) luaL_register(L, NULL, l)

#elif LUA_VERSION_NUM == 502

static void newlib(lua_State *L, const char *name, const luaL_Reg *funcs) {
  // Lua 5.2 modules are not expected to set a global variable, so "name" is
  // unused.
  (void)name;

  // Can't use luaL_newlib(), because funcs is not the actual array.
  // Could (micro-)optimize this a bit to count funcs for initial table size.
  lua_createtable(L, 0, 8);
  luaL_setfuncs(L, funcs, 0);
}

#define setfuncs(L, l) luaL_setfuncs(L, l, 0)

#else
#error Unsupported Lua version
#endif


#endif
