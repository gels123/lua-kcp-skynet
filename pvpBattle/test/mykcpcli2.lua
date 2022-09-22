--[[
    pvp客户端, 用法: ./pvpclient.sh 101 127.0.0.1 5000
]]
require "quickframework.init"
local mySockClient = require "mySockClient"

local uid, host, port = ...
uid, host, port = tonumber(uid), tostring(host), tonumber(port)
assert(uid and host and port, "usage: ./pvpclient.sh uid host port")

local client = mySockClient.new()
client:init(uid, 3, host, port)
client:dispatch_msg()