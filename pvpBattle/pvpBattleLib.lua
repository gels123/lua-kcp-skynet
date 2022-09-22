--[[
    pvp战场网关服务接口
]]
local skynet = require ("skynet")
local svrAddressMgr = require ("svrAddressMgr")
local pvpBattleLib = class("pvpBattleLib")

-- 获取地址
function pvpBattleLib:getAddress(serverid)
    return svrAddressMgr.getSvr(svrAddressMgr.pvpBattleSvr, serverid)
end

-- 推送消息给客户端 eg:  pvpBattleCenter:send_msg(101, "reqClosePvpBattle", {battleId=123})
-- @uid [必传]玩家ID
-- @name [必传]协议名称
-- @msg [必传]协议内容
function pvpBattleLib:send_msg(serverid, uid, name, msg)
    return skynet.call(self:getAddress(serverid), "lua", "send_msg", uid, name, msg)
end

return pvpBattleLib
