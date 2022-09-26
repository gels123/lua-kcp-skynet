--[[
	sockect之udp+kcp/udp+kcp+fec封装
]]
local skynet = require("skynet")
local skynetcore = require "skynet.core"
local skynetqueue = require "skynet.queue"
local socketdriver = require "skynet.socketdriver"
local lkcp = require "lkcpsn"
local lutil = require "lutil"
local cmdCtrl = require "cmdCtrl"
local protoLib = require "protoLib"
local mySockServer = class("mySockServer")

-- socket模式
local eSocketMode = {
    eUdpKcp = 3,    -- UDP+KCP
    eUdpKcpFec = 4, -- UDP+KCP+FEC
}

-- 构造
function mySockServer:ctor()
    self.mode = nil     -- 模式
    self.port = nil     -- 端口
    self.sock = nil     -- sock

    self.connection = {} -- 连接
    self.connectNum = 0  -- 连接数
    self.connectMax = 5000 -- 最大连接数
    self.uidMap = {}    -- uid关联信息
    self.subid = 0      -- 连接id
    self.handshakeMap = {} -- uid握手关联信息
    self.handshakeFrom = {} -- from握手关联信息
end

-- 初始化
function mySockServer:init(mode, port)
    Log.i("==mySockServer:init begin==", mode, port)
    -- 模式
    assert((mode == eSocketMode.eUdpKcp or mode == eSocketMode.eUdpKcpFec), "mySockServer:init error, mode is not support "..mode)
    self.mode = mode or eSocketMode.eUdpKcp
    -- 端口
    self.port = port or 8765
    -- 注册协议UDP
    skynet.register_protocol({
        name = "socket",
        id = skynet.PTYPE_SOCKET, -- PTYPE_SOCKET = 6
        unpack = socketdriver.unpack,
        dispatch = function(_, _, t, id, sz, msg, from)
            if t == 6 then -- SKYNET_SOCKET_TYPE_UDP = 6
                if id == self.sock then
                    self:dispatch_msg(from, msg, sz)
                else
                    skynet.error("mySockServer socket drop udp package fd=" .. id)
                    socketdriver.drop(msg, sz)
                end
            end
        end
    })
    -- 开启监听
    if self.sock then
        socketdriver.close(self.sock)
        self.sock = nil
    end
    local listen = "0.0.0.0"
    Log.i("mySockServer:init listen on=", listen, port)
    self.sock = socketdriver.udp(listen, self.port)
    assert(self.sock, "mySockServer:init error: create udp socket")
    Log.i("mySockServer:init ok, mode=", self.mode, "listen=", listen, "port=", port, "sock=", self.sock)
    return true
end

-- 分发消息
function mySockServer:dispatch_msg(from, msg, sz)
    --Log.d("mySockServer:dispatch udp mode=", self.mode, "from=", socketdriver.udp_address(from), "msg=", skynet.tostring(msg, sz), "sz=", sz)
    -- 获取数据
    local str_ = skynet.tostring(msg, sz)
    skynetcore.trash(msg, sz)
    -- 处理数据
    local subid, str = self:unpack_package(str_)
    --Log.d("mySockServer:dispatch udp do enter from=", socketdriver.udp_address(from), "subid=", subid, "str=", str)
    if subid then
        if subid == 0 then
            -- 创建kcp, 用于握手
            local kcp = self:getKcp(from, 0, 0)
            -- 若收到udp包, 则作为下层协议输入到kcp
            kcp:lkcp_input(str, from)
            kcp:lkcp_update(self:getms())
            local hrlen, hr = kcp:lkcp_recv()
            Log.d("mySockServer:dispatch udp do handshake, from=", socketdriver.udp_address(from), "subid=", subid, "hrlen=", hrlen, "hr=", hr)
            if hrlen > 0 then
                local arr = serviceFunctions.split(hr, "@")
                local uid, time = tonumber(arr[2]), tonumber(arr[3])
                if uid and uid > 0 and time and time > 0 then
                    -- 维护uid握手关联信息
                    if self.handshakeMap[uid] then
                        self.handshakeFrom[self.handshakeMap[uid].from] = nil
                        self.handshakeMap[uid] = nil
                    end
                    self.handshakeMap[uid] = {
                        uid = uid,
                        from = from,
                        subid = self.subid,
                        kcp = kcp,
                        ip = socketdriver.udp_address(from),
                        ms = 0,
                        time = time,
                        sq = skynetqueue(),
                    }
                    self.handshakeFrom[from] = self.handshakeMap[uid]
                    -- 回复握手包
                    self.subid = self.subid + 1
                    if self.subid >= 4294967295 then -- 超过4字节最大值, 重新开始
                        self.subid = 1
                    end
                    subid = self.subid
                    local handshake = string.pack(">I4s2", 0, string.format("B@%d@%d@OKK@E", subid, time))
                    local sq = self.handshakeMap[uid].sq
                    sq(function()
                        local r = kcp:lkcp_send(handshake, from)
                        if r < 0 then
                            Log.e("mySockServer:dispatch_msg do handshake error, from=", socketdriver.udp_address(from), "uid=", uid, "time=", time, "r=", r)
                            self.handshakeMap[uid] = nil
                            self.handshakeFrom[from] = nil
                            kcp = nil
                            return
                        else
                            kcp:lkcp_flush()
                        end
                    end)
                    -- 创建kcp, 用于业务
                    local kcp = self:getKcp(from, subid, uid)
                    -- 维护关联信息
                    self.connection[subid] = {
                        from = from,
                        subid = subid,
                        uid = uid,
                        kcp = kcp,
                        ip = socketdriver.udp_address(from),
                        ms = 0,
                        sq = skynetqueue(),
                    }
                    self.connectNum = self.connectNum + 1
                    if self.uidMap[uid] then
                        local subid_ = self.uidMap[uid].subid
                        self.uidMap[uid] = nil
                        if self.connection[subid_] then
                            self.connection[subid_] = nil
                            self.connectNum = self.connectNum - 1
                        end
                    end
                    self.uidMap[uid] = self.connection[subid]
                    -- 持续保证业务kcp的可靠性, 直到kcp销毁
                    skynet.fork(function(_subid)
                        while(true) do
                            local u = self.connection[_subid]
                            if not u then
                                --Log.d("mySockServer:dispatch_msg stop lkcp_update", _subid)
                                break
                            end
                            local ms = self:getms()
                            local nexttime = u.kcp:lkcp_check(ms)
                            local diff = nexttime - ms
                            if diff <= 0 then
                                diff = 50
                            end
                            skynet.sleep(math.ceil(diff/10)) -- lutil.isleep(diff)
                            u.sq(function()
                                ms = self:getms()
                                u.kcp:lkcp_update(ms)
                            end)
                        end
                    end, subid)
                    -- 3s=6*500ms=3000ms内保证回复握手包的可靠性
                    skynet.fork(function(uid)
                        for i=1,6,1 do
                            skynet.sleep(50) --500ms
                            --Log.d("mySockServer:dispatch udp keep kcp i=", i, self.handshakeMap[uid] and self.handshakeMap[uid].time)
                            if self.handshakeMap[uid] then
                                local sq = self.handshakeMap[uid].sq
                                sq(function()
                                    self.handshakeMap[uid].kcp:lkcp_update(self:getms())
                                end)
                            else
                                break
                            end
                        end
                        if self.handshakeMap[uid] then
                            self.handshakeFrom[self.handshakeMap[uid].from] = nil
                            self.handshakeMap[uid] = nil
                        end
                    end, uid)
                    Log.i("mySockServer:dispatch udp do handshake ok, from=", socketdriver.udp_address(from), "subid=", subid, "uid=", uid, "time=", time, "subid=", subid)
                else
                    kcp = nil
                    Log.w("mySockServer:dispatch udp do handshake fail, from=", socketdriver.udp_address(from), "subid=", subid, "uid=", uid, "time=", time, "subid=", subid, "arr=", arr[1], arr[2], arr[3], arr[4])
                end
            else
                Log.i("mySockServer:dispatch udp do handshake repeat, from=", socketdriver.udp_address(from), "subid=", subid, "hrlen=", hrlen, "hr=", hr)
                kcp = nil
                -- 收到回复握手包的确认包
                if self.handshakeFrom[from] then
                    local sq = self.handshakeFrom[from].sq
                    sq(function()
                        self.handshakeFrom[from].kcp:lkcp_input(str, from)
                    end)
                end
            end
        elseif subid > 0 then
            local u = self.connection[subid]
            if u then
                u.from = from
                u.sq(function()
                    -- 若收到udp包, 则作为下层协议输入到kcp
                    u.kcp:lkcp_input(str, from)
                    -- 更新kcp, 获取并处理消息, 一个kcp帧最多执行1次update
                    local ms = self:getms()
                    local nexttime = u.kcp:lkcp_check(ms)
                    local diff = nexttime - ms
                    if diff >= 0 then
                        u.ms = nexttime
                        skynet.sleep(math.floor(diff/10)) -- lutil.isleep(diff)
                        if not u.ms then
                            Log.d("mySockServer:dispatch udp return from=", socketdriver.udp_address(from), "subid=", self.subid, "uid=", u.uid, "nexttime=", nexttime)
                            return
                        end
                    end
                    ms = self:getms()
                    u.kcp:lkcp_update(ms)
                    u.ms = nil
                    while(1) do
                        local hrlen, hr = u.kcp:lkcp_recv()
                        --Log.d("mySockServer:dispatch udp do3 from=", socketdriver.udp_address(from), "subid=", self.subid, "uid=", u.uid, "hrlen=", hrlen, "hr=", hr, "nexttime=", nexttime, ms, diff)
                        if hrlen > 0 then
                            self:request(subid, hr, hrlen)
                        else
                            break
                        end
                    end
                end)
            else
                Log.w("mySockServer:dispatch udp ignore2", subid, str)
            end
        else
            Log.w("mySockServer:dispatch udp ignore3", subid, str)
        end
    else
        Log.w("mySockServer:dispatch udp ignore5", subid, str)
    end
end

-- 处理消息 not atomic, may yield
function mySockServer:request(subid, msg, sz)
    --Log.d("mySockServer:request subid=", subid, "msg=", msg, "sz=", sz)
    local ok, err = pcall(self.do_request, self, subid, msg, sz)
    if not ok then
        -- 协议异常, 关闭连接
        Log.w("mySockServer:request error: invalid package", ok, err, "subid=", subid, "msg=", msg, "sz=", sz)
        if self.connection[subid] then
            self:close(subid, 1)
        end
    end
end

-- 处理消息
function mySockServer:do_request(subid, msg, sz)
    local u = assert(self.connection[subid], string.format("mySockServer:do_request error: invalid subid=%s", subid))
    local t, cmd, args, response = protoLib:c2sDecode(msg, sz)
    Log.d("mySockServer:do_request request cmd=", cmd, "args=", transformTableToString(args))
    local _, rsp = xpcall(function() -- NOTICE: YIELD here, socket may close.
        local f = assert(cmdCtrl[cmd], "mySockServer:do_request error, cmd= "..cmd.." is not found")
        if type(f) == "function" then
            return f(args)
        end
    end, serviceFunctions.exception)
    Log.d("mySockServer:do_request response cmd=", cmd, "rsp=", transformTableToString(rsp))
    -- the return subid may change by multi request, check connect
    if response and self.connection[subid] and u.subid == self.connection[subid].subid then
        self:response_msg(subid, response, cmd, rsp or {code = gErrDef.Err_SERVICE_EXCEPTION,})
    else
        Log.w("mySockServer:do_request ignore subid=%d", u.subid, self.connection[subid] and self.connection[subid].subid, "cmd=", cmd, "args=", args)
    end
end

-- 回包
function mySockServer:response_msg(subid, response, cmd, msg)
    --Log.d("mySockServer:response_msg subid=", subid, "cmd=", cmd, "msg=", msg)
    local u = self.connection[subid]
    if u then
        u.sq(function()
            if self.mode == eSocketMode.eUdpKcp then
                local package = response(msg)
                u.kcp:lkcp_send(package, u.from)
                u.kcp:lkcp_flush()
            elseif self.mode == eSocketMode.eUdpKcpFec then
                local package = response(msg)
                u.kcp:lkcp_send(package, u.from)
                u.kcp:lkcp_flush()
            end
        end)
    end
end

-- 推送消息给客户端
function mySockServer:send_msg(uid, cmd, msg, subid)
    local u = self.uidMap[uid] or self.connection[subid]
    if u then
        u.sq(function()
            Log.d("mySockServer:send_msg", uid, cmd, msg, subid)
            if self.mode == eSocketMode.eUdpKcp then
                local package = protoLib:s2cEncode(cmd, msg, 0)
                local r = u.kcp:lkcp_send(package, u.from)
                if r < 0 then
                    Log.w("mySockServer:send_msg error", uid, cmd, msg, subid, "r=", r)
                    return
                end
                u.kcp:lkcp_flush()
            elseif self.mode == eSocketMode.eUdpKcpFec then
                local package = protoLib:s2cEncode(cmd, msg, 0)
                local r = u.kcp:lkcp_send(package, u.from)
                if r < 0 then
                    Log.w("mySockServer:send_msg error", uid, cmd, msg, subid, "r=", r)
                    return
                end
                u.kcp:lkcp_flush()
            end
        end)
    end
end

-- 客户端断开
function mySockServer:close(subid, tag)
    Log.i("mySockServer:close subid=", subid, tag)
    if self.connection[subid] then
        local u = self.connection[subid]
        u.sq(function()
            self.connection[subid] = nil
            self.uidMap[u.uid] = nil
            self.connectNum = self.connectNum - 1
        end)
        -- 推送关闭连接
        self:send_msg(u.uid, "syncCloseConnect", {subid = subid,})
    else
        Log.w("mySockServer:close ignore", subid, tag)
    end
end

-- 获取当前时间(毫秒)
function mySockServer:getms()
    return math.floor(lutil.gettimeofday())
end

--[[
    注意: 因udp无连接, 上行报文大小最好<=一个mtu大小, 超过时由kcp将对其分片处理, 固此处无需考虑报文太大的问题, 过程如下:
         A          --原始报文-->
    hA1 hA2 hA3     --kcp将对其分3片, 并保证3片的可靠性-->
         A          --接收端kcp收到3片后, 组成得到原始报文
]]
function mySockServer:unpack_package(_text)
    local sz = #_text
    if sz < 6 then
        return nil, nil
    end
    if sz > 1464 then
        Log.w("mySockServer:unpack_package package is big", sz)
    end
    local text = string.sub(_text, 5, -1)
    sz = #text
    local s = text:byte(1) * 256 + text:byte(2)
    if sz < s+2 then
        return nil, nil
    end
    local subid = string.unpack(">I4", _text, 1, 4)
    return subid, text:sub(3,2+s)
end

function mySockServer:udp_output(buf, from, subid)
    if from and subid then
        --Log.d("mySockServer:udp_output udp_send, from=", socketdriver.udp_address(from), "subid=", subid, "buf=", buf, "[end]")
        socketdriver.udp_send(self.sock, from, string.pack(">I4s2", subid, buf))
    else
        Log.w("mySockServer:udp_output error, from=", socketdriver.udp_address(from), "subid=", subid, "buf=", buf, "[end]")
    end
end

-- 创建kcp, 一条`连接`一个kcp
function mySockServer:getKcp(from, subid, uid)
    Log.i("mySockServer:getKcp create ip=", socketdriver.udp_address(from), "subid=", subid, "uid=", uid)
    local kcp = lkcp.lkcp_create(self.sock, from, subid, function (buf)
        self:udp_output(buf, from, subid)
    end)
    -- 考虑到丢包重发, 设置最大收发窗口为128
    kcp:lkcp_wndsize(128, 128)
    -- 默认模式
    -- kcp:lkcp_nodelay(0, 50, 0, 0)
    -- 普通模式, 关闭流控等
    kcp:lkcp_nodelay(0, 50, 0, 1)
    -- 快速模式, 第一个参数nodelay启用以后若干常规加速将启动;第二个参数interval为内部处理时钟,默认设置为 10ms;第三个参数 resend为快速重传指标,设置为2;第四个参数为是否禁用常规流控,这里禁止
    -- kcp:lkcp_nodelay(1, 50, 2, 1)
    -- 需要执行一下update
    kcp:lkcp_update(self:getms())
    return kcp
end

return mySockServer
