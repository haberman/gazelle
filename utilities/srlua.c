/*
* srlua.c
* Lua interpreter for self-running programs
* Luiz Henrique de Figueiredo <lhf@tecgraf.puc-rio.br>
* 27 Apr 2012 09:24:34
* This code is hereby placed in the public domain.
*/

#ifdef _WIN32
#include <windows.h>
#endif

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "srlua-glue.h"
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

typedef struct
{
 FILE *f;
 size_t size;
 char buff[512];
} State;

static const char *myget(lua_State *L, void *data, size_t *size)
{
 State* s=data;
 size_t n;
 (void)L;
 n=(sizeof(s->buff)<=s->size)? sizeof(s->buff) : s->size;
 n=fread(s->buff,1,n,s->f);
 s->size-=n;
 *size=n;
 return (n>0) ? s->buff : NULL;
}

#define cannot(x) luaL_error(L,"cannot %s %s: %s",x,name,strerror(errno))

static void load(lua_State *L, const char *name)
{
 Glue t;
 State S;
 FILE *f=fopen(name,"rb");
 int c;
 if (f==NULL) cannot("open");
 if (fseek(f,-sizeof(t),SEEK_END)!=0) cannot("seek");
 if (fread(&t,sizeof(t),1,f)!=1) cannot("read");
 if (memcmp(t.sig,GLUESIG,GLUELEN)!=0) luaL_error(L,"no Lua program found in %s",name);
 if (fseek(f,t.size1,SEEK_SET)!=0) cannot("seek");
 S.f=f; S.size=t.size2;
 c=getc(f);
 if (c=='#')
  while (--S.size>0 && c!='\n') c=getc(f);
 else
  ungetc(c,f);
 if (lua_load(L,myget,&S,"=",NULL)!=0) lua_error(L);
 fclose(f);
}

static int pmain(lua_State *L)
{
 int argc=lua_tointeger(L,1);
 char** argv=lua_touserdata(L,2);
 int i;
 lua_gc(L,LUA_GCSTOP,0);
 luaL_openlibs(L);
 lua_gc(L,LUA_GCRESTART,0);
 load(L,argv[0]);
 lua_createtable(L,argc,0);
 for (i=0; i<argc; i++)
 {
  lua_pushstring(L,argv[i]);
  lua_rawseti(L,-2,i);
 }
 lua_setglobal(L,"arg");
 luaL_checkstack(L,argc-1,"too many arguments to script");
 for (i=1; i<argc; i++)
 {
  lua_pushstring(L,argv[i]);
 }
 lua_call(L,argc-1,0);
 return 0;
}

static void fatal(const char* progname, const char* message)
{
#ifdef _WIN32
 MessageBox(NULL,message,progname,MB_ICONERROR | MB_OK);
#else
 fprintf(stderr,"%s: %s\n",progname,message);
#endif
 exit(EXIT_FAILURE);
}

int main(int argc, char *argv[])
{
 lua_State *L;
#ifdef _WIN32
 char name[MAX_PATH];
 argv[0]= GetModuleFileName(NULL,name,sizeof(name)) ? name : NULL;
#endif
 if (argv[0]==NULL) fatal("srlua","cannot locate this executable");
 L=luaL_newstate();
 if (L==NULL) fatal(argv[0],"not enough memory for state");
 lua_pushcfunction(L,&pmain);
 lua_pushinteger(L,argc);
 lua_pushlightuserdata(L,argv);
 if (lua_pcall(L,2,0,0)!=0) fatal(argv[0],lua_tostring(L,-1));
 lua_close(L);
 return EXIT_SUCCESS;
}
