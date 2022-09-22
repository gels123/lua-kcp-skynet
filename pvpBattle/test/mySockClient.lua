--[[
	sockect封装
]]
local socket = require "src.socket"
local clientsocket = require "client.socket"
local lkcp = require "lkcp"
local lutil = require "lutil"
local lfs = require("lfs")
local sproto = require "sproto"
local sprotoparser = require "sprotoparser"
local mySockClient = class("mySockClient")

-- socket模式
local eSocketMode = {
    eUdpKcp = 3,    -- UDP+KCP
    eUdpKcpFec = 4, -- UDP+KCP+FEC
}

-- 构造
function mySockClient:ctor()
    self.uid = nil      -- 玩家ID
    self.mode = nil     -- 模式
    self.port = nil     -- 端口

    self.sock = nil     -- sock
    self.subid = -1     -- 连接id
    self.kcp1 = nil     -- 握手kcp
    self.kcp2 = nil     -- 业务kcp
    self.ms = nil       -- 当前时间(毫秒)
    self.sessionid = 0  -- session id
    self.session = {}
    self.handshaketime = 0

    self.sproto_host = nil    -- sproto
    self.sproto_request = nil -- sproto
end

-- 初始化
function mySockClient:init(uid, mode, host, port)
    print("==mySockClient:init begin==", uid, mode, host, port)
    -- 加载sproto
    -- c2s客户端到服务端的协议
    local c2sFiles = {"types.sproto",}
    for fileName in lfs.dir("../../proto/sproto/") do
        if string.find(fileName, "^c2s[%w_$.sproto]") then
            table.insert(c2sFiles, fileName)
        end
    end
    local c2sSproto = ""
    for _,fileName in pairs(c2sFiles) do
        c2sSproto = c2sSproto.."\n"..io.readfile("../../proto/sproto/"..fileName)
    end
    --print("protoCenter:updateSproto c2sSproto=", c2sSproto)
    local c2sPb = assert(sprotoparser.parse(c2sSproto))
    -- 服务端到客户端的协议
    local s2cFiles = {"types.sproto",}
    for fileName in lfs.dir("../../proto/sproto/") do
        if string.find(fileName, "^s2c[%w_$.sproto]") then
            table.insert(s2cFiles, fileName)
        end
    end
    local s2cSproto = ""
    for _,fileName in pairs(s2cFiles) do
        s2cSproto = s2cSproto.."\n"..io.readfile("../../proto/sproto/"..fileName)
    end
    --print("protoCenter:updateSproto s2cSproto=", s2cSproto)
    local s2cPb = assert(sprotoparser.parse(s2cSproto))
    self.sproto_host = sproto.new(s2cPb):host("package")
    self.sproto_request = self.sproto_host:attach(sproto.new(c2sPb))

    -- 模式 端口
    assert(uid and uid > 0 and (mode == eSocketMode.eUdpKcp or mode == eSocketMode.eUdpKcpFec) and host and port and port > 0, "mySockClient:init init, uid or mode or port invalid "..tostring(uid).." "..tostring(mode).." "..tostring(host).." "..tostring(port))
    self.uid = uid
    self.mode = mode
    self.host = host
    self.port = port

    self.sock = assert(socket.udp())
    assert(self.sock:setpeername(self.host, self.port))
    assert(self.sock:settimeout(0.01))

    print("==mySockClient:init end==", uid, mode, host, port)
    return true
end

-- 分发消息
function mySockClient:dispatch_msg()
    while 1 do
        --print("mySockClient:dispatch_msg while")
        if self.subid < 0 then --未请求握手
            self.subid = 0
            -- 获取kcp
            self.kcp1 = self:getKcp(self.subid)
            -- 请求握手
            self:handshake()
            -- 
            lutil.isleep(500) --socket.sleep(diff/1000.0)
        elseif self.subid == 0 then --已请求握手
            -- 处理握手回包
            self.ms = self:getms()
            --
            while 1 do
                local str = self.sock:receive()
                -- print("mySockClient:dispatch_msg recv2=", self.subid, "str=", str, self.ms)
                if str then
                    local subid, str2 = self:unpack_package(str)
                    -- print("mySockClient:dispatch_msg recv21 subid=", subid, "str2=", str2, self.ms)
                    if subid == 0 then
                        -- print("mySockClient:dispatch_msg recv211 subid=", subid, self.ms)
                        self.kcp1:lkcp_input(str2)
                    else
                        print("mySockClient:dispatch_msg recv212 ignore subid=", subid, self.ms)
                    end
                else
                    break
                end
            end
            while 1 do
                local hrlen, r = self.kcp1:lkcp_recv()
                --print("mySockClient:dispatch_msg recv3=", self.subid, "hrlen=", hrlen, "r=", r, self.ms)
                if hrlen > 0 then
                    local arr = self:split(r, "@")
                    local subid, time = tonumber(arr[2]) or 0, tonumber(arr[3]) or 0
                    if subid > 0 and time == self.handshaketime and arr[4] == "OKK" then
                        print("mySockClient:dispatch_msg recv311 handshake success, subid=", subid, arr[1], arr[2], arr[3], arr[4], arr[5])
                        self.subid = subid
                        -- 获取kcp
                        self.kcp2 = self:getKcp(self.subid)
                        break
                    else
                        print("mySockClient:dispatch_msg recv312 handshake fail, subid=", subid, arr[1], arr[2], arr[3], arr[4])
                    end
                else
                    break
                end
            end
            --
            self.ms = self:getms()
            local nexttime = self.kcp1:lkcp_check(self.ms)
            local diff = nexttime - self.ms
            if diff > 0 then
                lutil.isleep(diff) --socket.sleep(diff/1000.0)
                self.ms = self:getms()
            end
            self.kcp1:lkcp_update(self.ms)
        else --已'连接'
            --
            self.ms = self:getms()
            --
            while 1 do
                local str = self.sock:receive()
                --print("mySockClient:dispatch_msg recv4=", self.subid, "str=", str, self.ms)
                if str then
                    local subid, str2 = self:unpack_package(str)
                    --print("mySockClient:dispatch_msg recv41=", self.subid, "subid=", subid, "str2=", str2, self.ms)
                    if subid == self.subid then
                        --print("mySockClient:dispatch_msg recv411=", self.subid, "subid=", subid, self.ms)
                        self.kcp2:lkcp_input(str2)
                        self.kcp1 = nil
                    else
                        print("mySockClient:dispatch_msg recv412 ignore=", self.subid, "subid=", subid, self.ms)
                        -- 重复收到握手回包, 确认收到一下
                        if subid == 0 and self.kcp1 then
                            self.kcp1:lkcp_input(str2)
                            self.kcp1:lkcp_update(self.ms)
                        end
                    end
                else
                    break
                end
            end
            while 1 do
                local hrlen, r = self.kcp2:lkcp_recv()
                --print("mySockClient:dispatch_msg recv5=", self.subid, "hrlen=", hrlen, "r=", r, self.ms)
                if hrlen > 0 then
                    local _, t, sessionid, args = pcall(function()
                        return self.sproto_host:dispatch(r)
                    end)
                    print("mySockClient:dispatch_msg response cmd=", self.session[sessionid] and self.session[sessionid].cmd, "rsp=", transformTableToString(args))
                    self.session[sessionid] = nil
                else
                    break
                end
            end
            --
            self.ms = self:getms()
            local nexttime = self.kcp2:lkcp_check(self.ms)
            local diff = nexttime - self.ms
            if diff > 0 then
                lutil.isleep(diff) --socket.sleep(diff/1000.0)
                self.ms = self:getms()
            end
            self.kcp2:lkcp_update(self.ms)
            if self.kcp1 then
                self.kcp1:lkcp_update(self.ms)
            end
        end
        local line = clientsocket.readstdin()
        if line then
            self:handle_cmd(line)
        end
    end
end

-- 请求握手
function mySockClient:handshake()
    self.handshaketime = os.time()
    local package = string.pack(">I4s2", self.subid, string.format("B@%d@%d@E", self.uid, self.handshaketime))
    --self.sock:send(package)
    self.kcp1:lkcp_send(package)
    self.kcp1:lkcp_flush()
end

--eg: reqCreatePvpBattle uid=101 battleId=123 uids={101,102}
function mySockClient:handle_cmd(line)
    --print("mySockClient:handle_cmd line=", line)
    local cmd
    local p = string.gsub(line, "([%w-_]+)", function (s)
        cmd = s
        return ""
    end, 1)
    local t = {}
    local f = load (p, "=" .. cmd, "t", t)
    if f then
        f ()
    end
    if not next (t) then
        t = nil
    end
    if cmd then
        local ok, err = pcall(self.request, self, cmd, t)
        if not ok then
            print(string.format("invalid command (%s), error (%s)", cmd, err))
        end
    end
end

-- 发送消息
function mySockClient:request(cmd, args)
    print("mySockClient:request cmd=", cmd, "args=", transformTableToString(args))
    self.sessionid = self.sessionid + 1
    self.session[self.sessionid] = {cmd = cmd, args = args,}
    local package = self.sproto_request(cmd, args, self.sessionid)
    self.kcp2:lkcp_send(package)
    self.kcp2:lkcp_flush()
end

-- 获取当前时间(毫秒)
function mySockClient:getms()
    return math.floor(lutil.gettimeofday())
end

--[[
    注意: 因udp无连接, 上行报文大小最好<=一个mtu大小, 超过时由kcp将对其分片处理, 固此处无需考虑报文太大的问题, 过程如下:
         A          --原始报文-->
    hA1 hA2 hA3     --kcp将对其分3片, 并保证3片的可靠性-->
         A          --接收端kcp收到3片后, 组成得到原始报文
]]
function mySockClient:unpack_package(_text)
    local sz = #_text
    if sz < 6 then
        return nil, nil
    end
    if sz > 1464 then
        print("mySockClient:unpack_package package is big", sz)
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

function mySockClient:udp_output(buf, subid)
    if self.sock then
        --print("mySockClient:udp_output udp_send, subid=", subid, "buf=", buf, "[end]")
        self.sock:send(string.pack(">I4s2", subid, buf))
    end
end

-- 获取kcp, 一条`连接`一个kcp
function mySockClient:getKcp(subid)
    print("mySockClient:getKcp create subid=", subid, "uid=", self.uid)
    local kcp = lkcp.lkcp_create(subid, function (buf)
        self:udp_output(buf, subid)
    end)
    -- 考虑到丢包重发, 设置最大收发窗口为128
    kcp:lkcp_wndsize(128, 128)
    -- 默认模式
    -- kcp:lkcp_nodelay(0, 30, 0, 0)
    -- 普通模式, 关闭流控等
    kcp:lkcp_nodelay(0, 30, 0, 1)
    -- 快速模式, 第二个参数nodelay启用以后若干常规加速将启动;第三个参数interval为内部处理时钟,默认设置为 10ms;第四个参数 resend为快速重传指标,设置为2;第五个参数为是否禁用常规流控,这里禁止
    -- kcp:lkcp_nodelay(1, 30, 2, 1)
    -- 需要执行一下update
    self.ms = self:getms()
    kcp:lkcp_update(self.ms)
    return kcp
end

-- 请求握手失败处理
function mySockClient:on_handshake_failed()
    print("mySockClient:on_handshake_failed")
end

-- 分割字符串
function mySockClient:split(str, separator)
    local arr = {}
    if type(str) == "string" then
        local i = 1
        local j = 1
        while true do
            local k = string.find(str, separator, i)
            if not k then
                arr[j] = string.sub(str, i, string.len(str))
                break
            end
            arr[j] = string.sub(str, i, k - 1)
            i = k + string.len(separator)
            j = j + 1
        end
    end
    return arr
end

return mySockClient
