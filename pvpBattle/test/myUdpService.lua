local skynet = require "skynet"
local socket = require "skynet.socket"
local json = require "json"
local LKcp = require "lkcp"
local LUtil = require "lutil"

local function getms()
    return math.floor(LUtil.gettimeofday())
end

local function unpack_package(text)
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
	hrlen, r = server1:lkcp_recv()
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


-- socket.sendto(host, from, "OK_" .. str)
local function server()
	local last = ""
	local host = nil
	local fromClient = nil
	local server1  = nil
	local current = getms()
	host = socket.udp(function(str, from)
		Log.i("server1 recv str=", str, "from=", socket.udp_address(from))

		--如果收到客户端udp，则作为下层协议输入到server1
		fromClient = from
		server1:lkcp_input(str)
        server1:lkcp_update(current)

		--server1收到client1的回射数据
		local v
		v, last = recv_package(server1, last)
		Log.i("server1 recv xxxxxgels v=", v, "[end]")
	end , "127.0.0.1", 8765)	-- bind an address

	local function udp_output(buf)
		if host and fromClient then
			Log.i("server udp_output do buf=", buf)
			socket.sendto(host, fromClient, buf)
		else
			Log.i("server udp_output dont buf=", buf)
		end
	end
	--此处info用于output接口回调数据
    local session = 0x11223344
    server1 = LKcp.lkcp_create(session, function (buf)
        udp_output(buf)
    end)

	--配置窗口大小：平均延迟200ms，每20ms发送一个包，
	--而考虑到丢包重发，设置最大收发窗口为128
	server1:lkcp_wndsize(128, 128)
	--默认模式
    server1:lkcp_nodelay(0, 10, 0, 0)

    local hrlen = 0
    local hr = ""

  --   while true do
  --       current = getms()
  --       local nextt1 = server1:lkcp_check(current) 
  --       local diff = nextt1 - current
  --       Log.i("=====server1 while=====", current, "diff=", diff)
  --       if diff > 0 then
  --           -- LUtil.isleep(diff)
  --           skynet.sleep(math.ceil(diff/10)) -- lutil.isleep(diff)
  --           current = getms()
  --       end
        
  --       server1:lkcp_update(current)

		-- --server1收到client1的回射数据
  --       while true do
		-- 	local v
		-- 	v, last = recv_package(server1, last)
		-- 	if not v then
		-- 		break
		-- 	end
		-- 	Log.i("server1 recv xxxxxgels v=", v, "[end]")
		-- end
  --   end
end

local function client()
	Log.i("== myUdpService client ==")
	local client1 = nil
	local c = socket.udp(function(str, from)
		Log.i("client recv str=", str, socket.udp_address(from))
		--如果收到服务器udp，则作为下层协议输入到client1
		client1:lkcp_input(str)
	end)
	socket.udp_connect(c, "127.0.0.1", 8765)
	-- for i=1,20 do
	-- 	socket.write(c, "hello_" .. i)	-- write to the address by udp_connect binding
	-- end

	local function udp_output(buf)
		if socket then
			Log.i("client udp_output do buf=", buf)
			socket.write(c, buf)	-- write to the address by udp_connect binding
		else
			Log.i("client udp_output dont buf=", buf)
		end
	end
	--此处info用于output接口回调数据
    local session = 0x11223344
    client1 = LKcp.lkcp_create(session, function (buf)
        udp_output(buf, info2)
    end)

    local current = getms()
    local slap = current + 20
    local index = 0
    local inext = 0

    local count = 0
    local maxrtt = 0

	--配置窗口大小：平均延迟200ms，每20ms发送一个包，
	--而考虑到丢包重发，设置最大收发窗口为128
	client1:lkcp_wndsize(128, 128)
	--默认模式
    client1:lkcp_nodelay(0, 10, 0, 0)

    local hrlen = 0
    local hr = ""

    while 1 do
        current = getms()
        
        local nextt2 = client1:lkcp_check(current)
        local diff = nextt2 - current
        Log.i("=====client1 while===== current=", current, "diff=", diff)
        if diff > 0 then
            -- LUtil.isleep(diff)
            skynet.sleep(math.ceil(diff/10))
            current = getms()
        end
        
        client1:lkcp_update(current)
        
		--每隔 20ms，client1发送数据
        while current >= slap do
            local s1 = LUtil.uint322netbytes(index)
            local s2 = LUtil.uint322netbytes(current)
            local str = s1.."_x_"..s2
            str = json.encode({index = index, current = current})
            local package = string.pack(">s2", str)
            Log.i("=====client1 lkcp_send index=", index, "current=", current, "str=", str, #str, "package=", package)
            client1:lkcp_send(package)
            client1:lkcp_flush()
            slap = slap + 20
            index = index + 1
        end

		--client1收到服务器的数据
		while 1 do
		    hrlen, hr = client1:lkcp_recv()
			--没有收到包就退出
			if hrlen <= 0 then
                break
            end

            local hr1 = string.sub(hr, 1, 4)
            local hr2 = string.sub(hr, 5, 8)
            local sn = LUtil.netbytes2uint32(hr1)
            local ts = LUtil.netbytes2uint32(hr2)
            Log.i("client recv true sn=", sn, "ts=", ts)

            local rtt = current - ts
			
			if sn ~= inext then
				--如果收到的包不连续
				Log.i(string.format("ERROR sn %d<->%d\n", count, inext))
				return
            end

			inext = inext + 1
			count = count + 1
			if rtt > maxrtt then
                maxrtt = rtt
            end

			Log.i(string.format("[RECV] mode=%d sn=%d rtt=%d\n", mode, sn, rtt))
        end
		if inext > 1 then
            break
        end
    end
end

-- test(0) --默认模式，类似 TCP：正常模式，无快速重传，常规流控
-- test(1) --普通模式，关闭流控等
-- test(2) --快速模式，所有开关都打开，且关闭流控



skynet.start(function()
	skynet.fork(server)
	skynet.fork(client)
end)

