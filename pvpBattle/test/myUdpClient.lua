local skynet = require "skynet"
local socket = require "skynet.socket"

--local function server()
--    local host
--    host = socket.udp(function(msg, from)
--        print("server recv", msg, socket.udp_address(from))
--        socket.sendto(host, from, "OK " .. msg)
--    end , "127.0.0.1", 8765)	-- bind an address
--end

local sproto = require "sproto"
local game_proto = require "game_proto"
local host = sproto.new(game_proto.s2c):host "package"
local cliproto = sproto.new(game_proto.c2s)
local request = host:attach(cliproto)
local session_id = 0

local function client()
    local c = socket.udp(function(msg, from)
        Log.d("client recv1, msg=", msg, "from=", socket.udp_address(from))
        local str, offset = string.unpack(">s2", msg)
        Log.d("client recv2, str=", str, "offset=", offset)
        local type, name, args, response = host:dispatch(str, offset)
        Log.d("client recv3, type=", type, "name=", name, "args=", args, "response=", response)
    end)
    socket.udp_connect(c, "127.0.0.1", 9999)
    local num = 0
    while(num < 999999) do
        num = num + 1
        session_id = session_id + 1

        local msg
        if num == 1 then
            local args = {
                uid = 12900,
                serverid = 90,
                battleType = 1,
                battleId = 10086,
            }
            msg = request("reqBattleLogin", args, session_id)
            socket.write(c, msg)	-- write to the address by udp_connect binding
            Log.d("=============client send====msg=", msg, "size=", string.len(msg))
        elseif num == 2 then
            local args = {
                uid = 12900,
                battleId = 10086,
            }
            msg = request("reqJoinBattle", args, session_id)
            socket.write(c, msg)	-- write to the address by udp_connect binding
            Log.d("=============client send====msg=", msg, "size=", string.len(msg))
        end


        --local protoloader = require("protoloader")
        --local sproto2, host2, proto_request2 = protoloader.load(protoloader.GAME)
        --local type, name, args, response = host2:dispatch(msg, string.len(msg))
        --Log.d("=============34534543535345====xxx=", type, name, args, response)

        skynet.sleep(200)
    end
end

skynet.start(function()
    --skynet.fork(server)
    skynet.fork(client)
end)
