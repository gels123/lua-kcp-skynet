/**
 *
 * Copyright (C) 2015 by David Lin
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALING IN
 * THE SOFTWARE.
 *
 */

#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "ikcp.h"
#include "../../skynet/skynet-src/skynet_server.h"
#include "../../skynet/skynet-src/socket_buffer.h"
#include "../../skynet/skynet-src/skynet_socket.h"

#define RECV_BUFFER_LEN 4*1024*1024

#define check_kcp(L, idx)\
	*(ikcpcb**)luaL_checkudata(L, idx, "kcp_meta")

#define check_buf(L, idx)\
	(char*)luaL_checkudata(L, idx, "recv_buffer")

struct Callback {
    uint64_t handle;
    lua_State* L;
    lua_State* eL;
    char *address;
};

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static lua_State *LL = NULL;
static uint64_t svrsock = 0;

// #define logs_on

#define lock_on \
    if(pthread_mutex_lock(&lock) != 0) {\
        luaL_error(L, "pthread_mutex_lock error");\
    }
    // else {\
    //     printf("pthread_mutex_lock lock\n");\
    // }\

#define lock_off \
    pthread_mutex_unlock(&lock);
    // printf("pthread_mutex_lock unlock\n");\

static int kcp_output_callback(const char *buf, int len, ikcpcb *kcp, void *arg) {
    struct Callback* c = (struct Callback*)arg;
    lua_State* L = c->eL;
    
    // uint64_t handle = c->handle;
    // if (handle > 0 && L) {
    //     #ifdef logs_on
    //         printf("debug kcp kcp_output_callback do kcp=%p L=%p eL=%p handle=%ld\n", kcp, c->L, c->eL, c->handle);
    //     #endif
    //     lua_rawgeti(L, LUA_REGISTRYINDEX, handle);
    //     if(lua_isfunction(L, -1)) {
    //         lua_pushlstring(L, buf, len);
    //         lua_call(L, 1, 0);
    //     } else {
    //         printf("debug kcp kcp_output_callback error1 kcp=%p L=%p eL=%p handle=%ld\n", kcp, c->L, c->eL, c->handle);
    //     }
    // } else {
    //     printf("debug kcp kcp_output_callback error2 kcp=%p L=%p eL=%p handle=%ld\n", kcp, c->L, c->eL, c->handle);
    // }

    if(!c->address) {
        printf("debug kcp kcp_output_callback error1 kcp=%p L=%p eL=%p handle=%ld\n", kcp, c->L, c->eL, c->handle);
        luaL_error(L, "kcp_output_callback error1: address invalid");
        return 1;
    }
    // struct skynet_context *ctx = lua_touserdata(L, lua_upvalueindex(1));
    lua_getfield(L, LUA_REGISTRYINDEX, "skynet_context");
	struct skynet_context *ctx = lua_touserdata(L, -1);
    if(!ctx) {
        printf("debug kcp kcp_output_callback error2 kcp=%p L=%p eL=%p handle=%ld\n", kcp, c->L, c->eL, c->handle);
        luaL_error(L, "kcp_output_callback error2: ctx invalid");
        return 1;
    }
    lua_pop(L, 1);

	struct socket_sendbuffer buf2;
	buf2.id = svrsock;
    buf2.type = SOCKET_BUFFER_RAWPOINTER;

    lua_getglobal(LL, "pack_output");
    if(!lua_isfunction(LL, -1)) {
        printf("debug kcp kcp_output_callback error3 kcp=%p L=%p eL=%p handle=%ld\n", kcp, c->L, c->eL, c->handle);
        luaL_error(L, "kcp_output_callback error3: pack_output invalid");
        return 1;
    }
    lua_pushinteger(LL, kcp->conv);
    lua_pushlstring(LL, buf, len);
    lua_pcall(LL, 2, 1, 0);
    buf2.buffer = luaL_checklstring(LL, 1, &buf2.sz);
    lua_pop(LL, 1);
    if(!buf2.buffer) {
        printf("debug kcp kcp_output_callback error4 kcp=%p L=%p eL=%p handle=%ld\n", kcp, c->L, c->eL, c->handle);
        luaL_error(L, "kcp_output_callback error4: buf2.buffer invalid");
        return 1;
    }
	int err = skynet_socket_udp_sendbuffer(ctx, c->address, &buf2);
    if(err) {
        printf("debug kcp kcp_output_callback error5 kcp=%p L=%p eL=%p handle=%ld\n", kcp, c->L, c->eL, c->handle);
        luaL_error(L, "kcp_output_callback error5: skynet_socket_udp_sendbuffer fail");
        return 1;
    }

    #ifdef logs_on
        printf("debug kcp kcp_output_callback do kcp=%p L=%p eL=%p handle=%ld\n", kcp, c->L, c->eL, c->handle);
    #endif
    return 0;
}

static int kcp_gc(lua_State* L) {
    lock_on
	ikcpcb* kcp = check_kcp(L, 1);
	if (kcp == NULL) {
        printf("debug kcp kcp_gc error L=%p\n", L);
        lock_off
        return 0;
	}
    if (kcp->user != NULL) {
        struct Callback* c = (struct Callback*)kcp->user;
        #ifdef logs_on
            printf("debug kcp kcp_gc kcp=%p L=%p eL=%p thisL=%p handle=%ld\n", kcp, c->L, c->eL, L, c->handle);
        #endif
        // if(c->handle > 0) {
        //     luaL_unref(c->L, LUA_REGISTRYINDEX, c->handle);
        //     c->handle = 0;
        // }
        c->L = NULL;
        c->eL = NULL;
        if(c->address) {
            free(c->address);
            c->address = NULL;
        }
        free(c);
        kcp->user = NULL;
    }
    ikcp_release(kcp);
    kcp = NULL;
    
    lock_off
    return 0;
}

static int lkcp_create(lua_State* L) {
    lock_on
    // uint64_t handle = luaL_ref(L, LUA_REGISTRYINDEX);
    // int32_t conv = luaL_checkinteger(L, 1);
    size_t sz = 0;
    uint64_t sock = luaL_checkinteger(L, 1);
    const char *address = luaL_checklstring(L, 2, &sz);
    int32_t conv = luaL_checkinteger(L, 3);
    if(sock && !svrsock) {
        svrsock = sock;
    }

    struct Callback* c = malloc(sizeof(struct Callback));
    memset(c, 0, sizeof(struct Callback));
    c->handle = 0;
    c->L = L;
    c->eL = L;
    c->address = (char*)malloc(strlen(address)+1);
    memset(c->address, 0, strlen(address)+1);
    strcpy(c->address, address);

    ikcpcb* kcp = ikcp_create(conv, (void*)c);
    if (kcp == NULL) {
        free(c);
        lua_pushnil(L);
        lua_pushstring(L, "error: fail to create kcp");
        lock_off
        return 2;
    }

    kcp->output = kcp_output_callback;

    *(ikcpcb**)lua_newuserdata(L, sizeof(void*)) = kcp;
    luaL_getmetatable(L, "kcp_meta");
    lua_setmetatable(L, -2);

    // #ifdef logs_on
        printf("debug kcp lkcp_create kcp=%p L=%p handle=%ld conv=%d svrsock=%ld address=%s\n", kcp, L, c->handle, conv, svrsock, address);
    // #endif
    lock_off
    return 1;
}

static int lkcp_recv(lua_State* L) {
    lock_on
	ikcpcb* kcp = check_kcp(L, 1);
	if (kcp == NULL || kcp->user == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        lock_off
        return 2;
	}
    lua_getfield(L, LUA_REGISTRYINDEX, "kcp_lua_recv_buffer");
    char* buf = check_buf(L, -1);
    lua_pop(L, 1);

    int32_t hr = ikcp_recv(kcp, buf, RECV_BUFFER_LEN);
    if (hr <= 0) {
        lua_pushinteger(L, hr);
        lock_off
        return 1;
    }
    lua_pushinteger(L, hr);
	lua_pushlstring(L, (const char *)buf, hr);

    #ifdef logs_on
        printf("debug kcp lkcp_recv kcp=%p L=%p handle=%ld\n", kcp, L, ((struct Callback*)kcp->user)->handle);
    #endif
    lock_off
    return 2;
}

static int lkcp_send(lua_State* L) {
    lock_on
	ikcpcb* kcp = check_kcp(L, 1);
    if (kcp == NULL || kcp->user == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        lock_off
        return 2;
	}
	size_t size;
	const char *data = luaL_checklstring(L, 2, &size);
    int32_t hr = ikcp_send(kcp, data, size);
    lua_pushinteger(L, hr);

    #ifdef logs_on
        printf("debug kcp lkcp_send kcp=%p L=%p handle=%ld\n", kcp, L, ((struct Callback*)kcp->user)->handle);
    #endif
    lock_off
    return 1;
}

static int lkcp_update(lua_State* L) {
    lock_on
	ikcpcb* kcp = check_kcp(L, 1);
	if (kcp == NULL || kcp->user == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        lock_off
        return 2;
	}
    int32_t current = luaL_checkinteger(L, 2);
    struct Callback* c = (struct Callback*)kcp->user;
    c->eL = L;
    ikcp_update(kcp, current);

    #ifdef logs_on
        // printf("debug kcp lkcp_update kcp=%p L=%p handle=%ld\n", kcp, L, ((struct Callback*)kcp->user)->handle);
    #endif
    lock_off
    return 0;
}

static int lkcp_check(lua_State* L) {
    lock_on
	ikcpcb* kcp = check_kcp(L, 1);
	if (kcp == NULL || kcp->user == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        lock_off
        return 2;
	}
    int32_t current = luaL_checkinteger(L, 2);
    int32_t hr = ikcp_check(kcp, current);
    lua_pushinteger(L, hr);

    #ifdef logs_on
        // printf("debug kcp lkcp_check kcp=%p L=%p handle=%ld\n", kcp, L, ((struct Callback*)kcp->user)->handle);
    #endif
    lock_off
    return 1;
}

static int lkcp_input(lua_State* L) {
    lock_on
	ikcpcb* kcp = check_kcp(L, 1);
	if (kcp == NULL || kcp->user == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        lock_off
        return 2;
	}
	size_t size;
	const char *data = luaL_checklstring(L, 2, &size);
    int32_t hr = ikcp_input(kcp, data, size);
    lua_pushinteger(L, hr);
    
    #ifdef logs_on
        printf("debug kcp lkcp_input kcp=%p L=%p handle=%ld\n", kcp, L, ((struct Callback*)kcp->user)->handle);
    #endif
    lock_off
    return 1;
}

static int lkcp_flush(lua_State* L) {
    lock_on
	ikcpcb* kcp = check_kcp(L, 1);
	if (kcp == NULL || kcp->user == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        lock_off
        return 2;
	}
    struct Callback* c = (struct Callback*)kcp->user;
    c->eL = L;
    ikcp_flush(kcp);

    #ifdef logs_on
        printf("debug kcp lkcp_flush kcp=%p L=%p handle=%ld\n", kcp, L, ((struct Callback*)kcp->user)->handle);
    #endif
    lock_off
    return 0;
}

static int lkcp_wndsize(lua_State* L) {
    lock_on
	ikcpcb* kcp = check_kcp(L, 1);
	if (kcp == NULL || kcp->user == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        lock_off
        return 2;
	}
    int32_t sndwnd = luaL_checkinteger(L, 2);
    int32_t rcvwnd = luaL_checkinteger(L, 3);
    ikcp_wndsize(kcp, sndwnd, rcvwnd);

    lock_off
    return 0;
}

static int lkcp_nodelay(lua_State* L) {
    lock_on
	ikcpcb* kcp = check_kcp(L, 1);
	if (kcp == NULL || kcp->user == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        lock_off
        return 2;
	}
    int32_t nodelay = luaL_checkinteger(L, 2);
    int32_t interval = luaL_checkinteger(L, 3);
    int32_t resend = luaL_checkinteger(L, 4);
    int32_t nc = luaL_checkinteger(L, 5);
    int32_t hr = ikcp_nodelay(kcp, nodelay, interval, resend, nc);
    lua_pushinteger(L, hr);

    lock_off
    return 1;
}

static const struct luaL_Reg lkcp_methods [] = {
    { "lkcp_recv" , lkcp_recv },
    { "lkcp_send" , lkcp_send },
    { "lkcp_update" , lkcp_update },
    { "lkcp_check" , lkcp_check },
    { "lkcp_input" , lkcp_input },
    { "lkcp_flush" , lkcp_flush },
    { "lkcp_wndsize" , lkcp_wndsize },
    { "lkcp_nodelay" , lkcp_nodelay },
	{NULL, NULL},
};

static const struct luaL_Reg l_methods[] = {
    { "lkcp_create" , lkcp_create },
    {NULL, NULL},
};

int luaopen_lkcpsn(lua_State* L) {
    luaL_checkversion(L);

    if(LL == NULL) {
        LL = luaL_newstate();
        luaL_openlibs(LL);
        char code[512] = "\
                        function pack_output(subid, buf)\
                            return string.pack(\">I4s2\", subid, buf)\
                        end\
                        ";
        luaL_dostring(LL, code);
        // test
        // printf("luaopen_lkcp L=%p size2=%d\n", L, lua_gettop(LL));
        // int subid =100;
        // char str[128] = "dffccc";
        // lua_getglobal(LL, "pack_output");
        // lua_pushinteger(LL, subid);
        // lua_pushstring(LL, &str);
        // lua_call(LL, 2, 1);
        // size_t sz;
        // const char *r = luaL_checklstring(LL, 1, &sz);
        // printf("==xxxxxxrr r==%s sz==%d\n", r, sz);
        // lua_pop(LL, 1);
    }

    luaL_newmetatable(L, "kcp_meta");

    lua_newtable(L);
    luaL_setfuncs(L, lkcp_methods, 0);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, kcp_gc);
    lua_setfield(L, -2, "__gc");

    luaL_newmetatable(L, "recv_buffer");

    char* global_recv_buffer = lua_newuserdata(L, sizeof(char)*RECV_BUFFER_LEN);
    memset(global_recv_buffer, 0, sizeof(char)*RECV_BUFFER_LEN);
    luaL_getmetatable(L, "recv_buffer");
    lua_setmetatable(L, -2);
    lua_setfield(L, LUA_REGISTRYINDEX, "kcp_lua_recv_buffer");

    luaL_newlib(L, l_methods);

    return 1;
}

