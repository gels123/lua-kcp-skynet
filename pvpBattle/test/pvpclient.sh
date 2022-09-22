#!/bin/sh
export LUA_CPATH="../../../lib/lua-kcp/?.so;../../../lib/lua-socket/src/?.so;../../../lib/lua-lfs/?.so;../../../../skynet/luaclib/?.so;"
export LUA_PATH="./?.lua;../../../../skynet/lualib/?.lua;../../../proto/?.lua;../../../skynet/lualib/compat10/?.lua;../../../lib/lua-socket/?.lua;../../../lib/?.lua;../../../../?.lua;../../../lib/quickframework/?.lua;"
rlwrap ../../../../skynet/3rd/lua/lua ./mykcpcli2.lua $1 $2 $3
