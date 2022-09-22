--[[
    战斗服网帧同步服务接口
]]
local skynet = require ("skynet")
local frameLib = class("frameLib")

-- 服务数量
frameLib.serviceNum = 4

-- 根据id返回服务id
function frameLib:svrIdx(battleId)
    return (battleId - 1) % frameLib.serviceNum + 1
end

-- 获取地址
function frameLib:getAddress(kid, battleId)
    return svrAddressMgr.getSvr(svrAddressMgr.frameSvr, kid, self:svrIdx(battleId))
end


-- 创建一场战斗
-- @battleId        [必填]战场ID
-- @uids            [必填]玩家ID列表
-- @frameRate       [必填]帧率(推荐16帧, 60ms/帧)
-- @maxTime         [必填]最大战斗时长(秒)
function frameLib:createBattle(kid, battleId, uids, frameRate, maxTime)
    return skynet.call(self:getAddress(kid, battleId), "lua", "createBattle", battleId, uids, frameRate, maxTime)
end

--[[
    加入一场战斗
    @battleId             [必填]战场ID
]]
function frameLib:joinBattle(kid, battleId, uid)
    return skynet.call(self:getAddress(kid, battleId), "lua", "joinBattle", battleId, uid)
end

return frameLib
