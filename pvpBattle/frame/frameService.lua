--[[
    帧同步服务
]]
require "quickframework.init"
require "configInclude"
require "serviceFunctions"
require "sharedataLib"
require "cluster"
require "errDef"
local skynet = require "skynet"
local frameCenter = require("frameCenter"):shareInstance()

local kid, idx = ...
local kid, idx = tonumber(kid), tonumber(idx)
assert(kid and idx)

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        --Log.d("frameCenter cmd enter => ", session, source, cmd, ...)
        frameCenter:dispatchcmd(session, source, cmd, ...)
    end)

    -- 初始化
    skynet.call(skynet.self(), "lua", "init", kid, idx)
    -- 设置本服地址
    svrAddressMgr.setSvr(skynet.self(), svrAddressMgr.frameSvr, kid, idx)
    -- 通知启动服务, 本服务已初始化完成
    require("serverStartLib"):finishInit(kid, svrAddressMgr.getSvrName(svrAddressMgr.frameSvr, kid, idx), skynet.self())
end)