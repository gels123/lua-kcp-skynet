--[[
	pvp战场网关服务
]]
require "quickframework.init"
require "configInclude"
require "serviceFunctions"
require "sharedataLib"
require "cluster"
require "errDef"
local skynet = require "skynet"
local profile = require "skynet.profile"
local pvpBattleCenter = require("pvpBattleCenter"):shareInstance()

local kid, mode = ...
kid, mode = tonumber(kid), tonumber(mode)
assert(kid and mode)
local ti = {}

-- 注册客户端指令
do
    require "frameCmdCtrl"
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        profile.start()

        pvpBattleCenter:dispatchcmd(session, source, cmd, ...)

        local time = profile.stop()
        if time > 1 then
            Log.w("pvpBattleCenter:dispatchcmd timeout time=", time, " cmd=", cmd, ...)
            if not ti[cmd] then
                ti[cmd] = {n = 0, ti = 0}
            end
            ti[cmd].n = ti[cmd].n + 1
            ti[cmd].ti = ti[cmd].ti + time
        end
    end)

    -- 注册 info 函数，便于 debug 指令 INFO 查询。
    skynet.info_func(function()
        Log.i("info ti=", transformTableToString(ti, nil, 10))
        return ti
    end)

    -- 初始化
    skynet.call(skynet.self(), "lua", "init", kid, mode, 5000)
    -- 设置本服地址
    svrAddressMgr.setSvr(skynet.self(), svrAddressMgr.pvpBattleSvr, kid)
    -- 通知启动服务, 本服务已初始化完成
    require("serverStartLib"):finishInit(kid, svrAddressMgr.getSvrName(svrAddressMgr.pvpBattleSvr, kid), skynet.self())
end)