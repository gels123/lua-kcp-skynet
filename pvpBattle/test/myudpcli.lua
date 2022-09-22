local skynet = require "skynet"

local function client()
    local socket = require "skynet.socket"
    local c = socket.udp(function(str, from)
        print("client recv", str, socket.udp_address(from))
    end)
    socket.udp_connect(c, "192.168.88.235", 8765)
    for i=1,3 do
        socket.write(c, "hello_" .. i)	-- write to the address by udp_connect binding
    end
end

local function client2()
    local socket = require "skynet.socket"
    local c = socket.udp(function(str, from)
        print("client recv", str, socket.udp_address(from))
    end)
    socket.udp_connect(c, "192.168.88.235", 8765)
    for i=1,3 do
        socket.write(c, "hello_" .. i)	-- write to the address by udp_connect binding
    end
end

skynet.start(function()
    --skynet.fork(client)
    skynet.fork(client2)
end)
