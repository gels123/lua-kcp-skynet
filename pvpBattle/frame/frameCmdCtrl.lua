local skynet = require "skynet"
local frameLib = require "frameLib"
local pvpBattleCenter = require("pvpBattleCenter"):shareInstance()
local frameCmdCtrl =  require "cmdCtrl"

--#请求创建一个战场(测试用,正常匹配成功后会自动创建战场) eg: reqCreatePvpBattle uid=101 battleId=300011 uids={101, 102}
function frameCmdCtrl.reqCreatePvpBattle(req)
    --Log.dump(req, "frameCmdCtrl.reqPvpCreateBattle uid="..tostring(req.uid), 10)
    local ret = {}
    local code = gErrDef.Err_None

    repeat
        if not dbconf.DEBUG or not req.battleId or not req.uids then
            code = gErrDef.Err_ILLEGAL_PARAMS
            break
        end
        local ok, code2 = frameLib:createBattle(pvpBattleCenter.kid, req.battleId, req.uids, 16, 300)
        if not ok then
            code = code2 or gErrDef.Err_SERVICE_EXCEPTION
            break
        end
    until true

    ret.code = code
    return ret
end

--#加入一场战斗 eg: reqJoinBattle
function frameCmdCtrl.reqJoinBattle(req)
    Log.dump(req, "frameCmdCtrl.reqJoinBattle uid="..tostring(req.uid), 10)
    local ret = {}
    local code = global_code.success

    repeat
        ret = {}
    until true

    ret.code = code
    return ret
end

return frameCmdCtrl

