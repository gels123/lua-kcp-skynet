--[[
    log mykcpsvr
]]
local skynet = require "skynet"
local skynet_core = require "skynet.core"
local socketdriver = require "skynet.socketdriver"
local lkcp = require "lkcp"
local lutil = require "lutil"

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
    if size < 4 then
        return nil, nil, text
    end
    local s = text:byte(1) * 256 + text:byte(2)
    if size < s+2 then
        return nil, text
    end
    return text:sub(3,2+s), text:sub(3+s)
end

local function recv_package(kcp, last)
    local result
    result, last = unpack_package(last)
    if result then
        Log.i("recv_package do1 result==", result, "last=", last)
        return result, last
    end
    local hrlen, r = kcp:lkcp_recv()
    --没有收到包就退出
    if hrlen <= 0 then
        Log.i("server recv_package do2 hrlen==", hrlen, "r=", r)
        return nil, last
    end
    Log.i("server recv_package do3 hrlen==", hrlen, "r=", r)
    if r == "" then
        Log.i("recv_package do4 hrlen==", hrlen, "r=", r)
        error "Server closed"
    end
    result, last = unpack_package(last .. r)
    Log.i("server recv_package do5 result==", result, "last=", last)
    return result, last
end

local function server()
    Log.i("== mykcpsvr begin ==")
    local last = ""
    local host = nil
    local client = nil
    local kcp  = nil
    local sid = 0  --max = 4294967295
    local current = getms()

    local function udp_output(buf, sid)
        if host and client then
            Log.i("server udp_output do buf=", buf)
            --socket.sendto(host, client, buf)
            socketdriver.udp_send(host, client, string.pack(">I4s2", sid, buf))
        else
            Log.i("server udp_output error buf=", buf)
        end
    end
    local function createKcp(sid)
        Log.i("server createKcp sid=", sid)
        local kcp = lkcp.lkcp_create(sid, function (buf)
            udp_output(buf, sid)
        end)
        --配置窗口大小：平均延迟200ms，每20ms发送一个包，
        --而考虑到丢包重发，设置最大收发窗口为128
        kcp:lkcp_wndsize(128, 128)
        --默认模式
        kcp:lkcp_nodelay(0, 10, 0, 0)
        return kcp
    end
    local function dispatch_msg2(str, from)
        Log.i("server kcp recv str=", str, "from=", socketdriver.udp_address(from), "[end]", from, "[end]")
        --如果收到客户端udp，则作为下层协议输入到kcp
        client = from

        local clisubid, str2 = unpack_package(str)
        if clisubid == 0 then
            sid = sid + 1
            if sid >= 4294967295 then
                sid = 1
            end
            kcp = createKcp(sid)
            local playerid = tonumber(str2)
            Log.i("server kcp recv client connet in, sid=", sid, playerid)
            local handshake = string.pack(">I4s2", sid, "OK")
            socketdriver.udp_send(host, client, handshake)
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
            Log.i("server kcp recv xxx777fdfdfad data==", hrlen, r)
        end
    end
    local function dispatch_msg(fd, msg, sz)
        local str = skynet.tostring(msg, sz)
        skynet_core.trash(msg, sz)
        dispatch_msg2(str, fd)
    end

    skynet.register_protocol({
        name = "socket",
        id = skynet.PTYPE_SOCKET, -- PTYPE_SOCKET = 6
        unpack = socketdriver.unpack,
        dispatch = function(_, _, t, id, sz, msg, from)
            if t == 6 then -- SKYNET_SOCKET_TYPE_UDP = 6
                if id == host then
                    dispatch_msg(from, msg, sz)
                end
            end
        end
    })
    host = socketdriver.udp("0.0.0.0", 8765)
    --local socket = require "skynet.socket"
    --host = socket.udp(dispatch_msg2, "127.0.0.1", 8765)	-- bind an address

    --while true do
    --   current = getms()
    --   local nextt1 = kcp:lkcp_check(current)
    --   local diff = nextt1 - current
    --   Log.i("=====kcp while=====", current, "diff=", diff)
    --   if diff > 0 then
    --       skynet.sleep(math.ceil(diff/10)) -- lutil.isleep(diff)
    --       current = getms()
    --   end
    --   kcp:lkcp_update(current)
    --   while true do
    --        local v
    --        v, last = recv_package(kcp, last)
    --        if not v then
    --            break
    --        end
    --        Log.i("kcp recv xxxxxgels v=", v, "[end]")
    --    end
    --end

    Log.i("== mykcpsvr end ==")
end

local function server2()
    Log.i("== mykcpsvr begin ==")

    local s = require("mySockServer").new()
    s:init(3, 8765)

    Log.i("== mykcpsvr end ==")
end

skynet.start(function()
    --skynet.fork(server)
    skynet.fork(server2)
end)

