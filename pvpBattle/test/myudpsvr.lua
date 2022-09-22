local skynet = require "skynet"

local function server()
    local socket = require "skynet.socket"
    local host
    host = socket.udp(function(str, from)
        print("server recv", str, socket.udp_address(from))
        socket.sendto(host, from, "OK " .. str)
    end , "127.0.0.1", 8765)	-- bind an address
end

local function server2()
    local s = require("mySockServer").new()
    s:init(2, 8765)
end

skynet.start(function()
    --skynet.fork(server)
    skynet.fork(server2)
end)
