//g++ -g -o test luaRef.cpp -I/home/share/lnx_server3/server/skynet/3rd/lua -L/home/share/lnx_server3/server/skynet/3rd/lua -ldl -llua
#include <stdlib.h>
#include <lua.hpp>
#include <lualib.h>
#include <lauxlib.h>
#include <string>


int main()
{
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    luaL_dofile(L,"Foo.lua");
    printf("stack size:%d,%d\n",lua_gettop(L), lua_type(L,-1));



    // 存放函数到注册表中并返回引用
    lua_getglobal(L,"foo1");
    int ref1 =  luaL_ref(L, LUA_REGISTRYINDEX);
    printf("stack size11:%d  ref1=%d\n",lua_gettop(L), ref1);

    lua_getglobal(L,"foo2");
    int ref2 =  luaL_ref(L, LUA_REGISTRYINDEX);
    printf("stack size22:%d  ref2=%d\n",lua_gettop(L), ref2);


//    luaL_unref(L, LUA_REGISTRYINDEX, ref1);
    printf("stack size222:%d  ref2=%d\n",lua_gettop(L), ref2);

   // 从注册表中读取该函数并调用
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref1);
    printf("stack size44:%d,%d\n", lua_gettop(L), lua_type(L,-1));
    luaL_unref(L, LUA_REGISTRYINDEX, ref1);
   
    //printf("stack size:%d,%d\n",lua_gettop(L),lua_type(L,-1));
    lua_pcall(L,0,0,0);
    printf("stack size55:%d\n",lua_gettop(L));


    // luaL_dofile(L, "output.lua");
    char code[1024] = " function pack_output(subid, buf)\
                            print(\"pack_output =\", subid, buf)\
                            return string.pack(\">I4s2\", subid, buf)\
                        end\
                        function unpack_output(msg)\
                            print(\"unpack_output msg=\", msg)\
                            local subid, buf = string.unpack(\">I4s2\", msg)\
                            print(\"unpack_output subid=\", subid, \"buf=\", buf)\
                            return subid, buf\
                        end";
    luaL_dostring(L, code);
    int subid =100;
    std::string str = "dffccc";

    lua_getglobal(L, "pack_output");
    lua_pushinteger(L, subid);
    lua_pushstring(L, str.c_str());
    lua_call(L, 2, 1);
    size_t sz;
    const char *r = luaL_checklstring(L, 1, &sz);
    printf("==xxxxxxrr r==%s sz==%d\n", r, sz);
    lua_pop(L, 1);

    lua_getglobal(L, "unpack_output");
    lua_pushlstring(L, r, sz);
    lua_call(L, 1, 2);
    printf("==unpack_output buf==%s subid==%d\n", luaL_checkstring(L, -1), luaL_checkinteger(L, -2));
    lua_pop(L, 2);


    lua_close(L);
   return 0;
}
