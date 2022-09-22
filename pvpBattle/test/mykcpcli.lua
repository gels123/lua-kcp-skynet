--[[
    log mykcpcli
    inject xxx server/pvpBattle/test/mykcpcli.lua
]]
local skynet = require "skynet"
local socket = require "skynet.socket"
local json = require "json"
local lkcp = require "lkcp"
local lutil = require "lutil"

local sproto = require "sproto"
local game_proto = require "game_proto"
local host = sproto.new(game_proto.s2c):host "package"
local request = host:attach(sproto.new(game_proto.c2s))
local session_id = 0

local function getms()
    return math.floor(lutil.gettimeofday())
end

local function unpack_package(text)
    local size = #text
    if size < 4 then
        return nil, nil, text
    end
    local ok, subid, str = pcall(function()
        return string.unpack(">I4s2", text)
    end)
    if not ok then
        return nil, nil, text
    end
    return subid, str
end
local function unpack_package_bak(text)
    local size = #text
    if size < 2 then
        return nil, text
    end
    local s = text:byte(1) * 256 + text:byte(2)
    if size < s+2 then
        return nil, text
    end
    return text:sub(3,2+s), text:sub(3+s)
end

local function recv_package(server1, last)
    local result
    result, last = unpack_package(last)
    if result then
        Log.i("server1 r1==", hrlen, "r=", r, "e==")
        return result, last
    end
    local hrlen, r = server1:lkcp_recv()
    --没有收到包就退出
    if hrlen <= 0 then
        Log.i("server1 r2==", hrlen, "r=", r, "e==")
        return nil, last
    end
    Log.i("server1 r3==", hrlen, "r=", r, "e==")
    if r == "" then
        Log.i("===server1 Server closed")
        error "Server closed"
    end
    result, last = unpack_package(last .. r)
    return result, last
end
local c
local function udp_output(buf, sid)
    if c then
        Log.i("client udp_output do buf=", buf)
        socket.write(c, string.pack(">I4s2", sid, buf))	-- write to the address by udp_connect binding
    else
        Log.i("client udp_output error buf=", buf)
    end
end
local function createKcp(sid)
    Log.i("cli createKcp sid=", sid)
    local kcp = lkcp.lkcp_create(sid, function (buf)
        --Log.i("===========cli sdfadsfadfad===", buf)
        udp_output(buf, sid)
    end)
    --配置窗口大小：平均延迟200ms，每20ms发送一个包，
    --而考虑到丢包重发，设置最大收发窗口为128
    kcp:lkcp_wndsize(128, 128)
    --默认模式
    kcp:lkcp_nodelay(0, 10, 0, 0)
    kcp:lkcp_update(getms())
    return kcp
end
local function client()
    Log.i("== mykcpcli begin ==")
    local sid, uid = 0,  1889771
    local kcp = nil
    local current = getms()
    c = socket.udp(function(str, from)
        local clisubid, str2 = unpack_package(str)
        Log.i("client recv str=", str, socket.udp_address(from), "clisubid=", clisubid, "str2=", str2)
        if sid == 0 then
            if clisubid > 0 then
                Log.i("client recv str login ok=", str, socket.udp_address(from), "clisubid, str2=", clisubid, str2)
                sid = clisubid
                kcp = createKcp(sid)

                skynet.fork(function()
                    local current = getms()
                    local slap = current + 2000
                    local index = 0

                    while 1 do
                        current = getms()
                        local nextt2 = kcp:lkcp_check(current)
                        local diff = nextt2 - current
                        --Log.i("=====client kcp while===== current=", current, "diff=", diff)
                        if diff > 0 then
                            skynet.sleep(math.ceil(diff/10)) -- lutil.isleep(diff)
                            current = getms()
                        end
                        kcp:lkcp_update(current)

                        --每隔 20ms，cli发送数据
                        while current >= slap do
                            local args = {
                                uids = {12900, 12901, index},
                            }
                            --local package = string.pack(">s2", json.encode(args))
                            --local package = json.encode(args)
                            session_id = session_id + 1
                            local package = request("reqPvpCreateBattle", args, session_id)
                            Log.i("=====client lkcp_send index=", index, "current=", current, "args=", args, "package=", package, "#package=", #package)

                            --local protoloader = require("protoloader")
                            --local s_sproto, s_host, s_request = protoloader.load(protoloader.GAME)
                            --local t, name, args, response = s_host:dispatch(package, #package)
                            --Log.i("=====client lkcp_send index2=", index, "t=", t, "name=", name, "args=", args, "response=", response, "package=", package, "#package=", #package)

                            kcp:lkcp_send(package)
                            kcp:lkcp_flush()
                            slap = slap + 2000
                            index = index + 1
                        end
                        if index >= 1 then
                            break
                        end
                    end
                end)
            else
                Log.i("client recv str login error=", str, socket.udp_address(from), "clisubid, str2=", clisubid, str2)
            end
        else
            kcp:lkcp_input(str2)
            current = getms()
            local nextt1 = kcp:lkcp_check(current)
            local diff = nextt1 - current
            if diff > 0 then
                skynet.sleep(math.ceil(diff/10)) -- lutil.isleep(diff)
                current = getms()
            end
            kcp:lkcp_update(current)
            local hrlen, r = kcp:lkcp_recv()
            Log.i("cli xxx777fdfdfad data==", hrlen, r)
            if hrlen > 0 then
                local t, name, args = host:dispatch(r)
                Log.i("cli xxx777fdfdfad data dispatch==", t, name, args)
            end
        end
    end)
    socket.udp_connect(c, "127.0.0.1", 5000)
    local handshake = string.pack(">I4s2", sid, string.format("%d", uid))
    socket.write(c, handshake)

    Log.i("== mykcpcli end ==")
end

--skynet.start(function()
    skynet.fork(client)
--end)


