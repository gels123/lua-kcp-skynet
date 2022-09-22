--[[
	pvp战场网关服务中心
]]
local skynet = require "skynet"
local socketdriver = require "skynet.socketdriver"
local mySockServer =  require "mySockServer"
local pvpBattleCenter = class("pvpBattleCenter", mySockServer)

-- 获取单例
local instance = nil  
function pvpBattleCenter.shareInstance(cc)
    if not instance then
        instance = cc.new()
    end
    return instance
end

-- 构造
function pvpBattleCenter:ctor()
	self.super.ctor(self)
    -- send指令
    self.sendCmd = {
    }
	-- 随机种子
	math.randomseed(tonumber(tostring(os.time()):reverse():sub(1, 6)))
end

-- 内存回收
function pvpBattleCenter:__gc()
	Log.i("pvpBattleCenter:__gc")
	if self.sock then
		socketdriver.close(self.sock)
	end
end

-- 杀死服务
function pvpBattleCenter:kill()
	Log.i("== pvpBattleCenter:kill ==")
    skynet.exit()
end

-- 初始化
function pvpBattleCenter:init(kid, mode, port)
	Log.i("== pvpBattleCenter:init begin ==", kid, mode, port)
	self.super.init(self, mode, port)
    self.kid = kid
    Log.i("== pvpBattleCenter:init end ==", kid, mode, port)
	return true
end

-- 分发服务端调用
function pvpBattleCenter:dispatchcmd(session, source, cmd, ...)
    --Log.d("pvpBattleCenter:dispatchcmd", session, source, cmd, ...)
    local func = instance and instance[cmd]
    if func then
        if self.sendCmd[cmd] then
            xpcall(func, serviceFunctions.exception, self, ...)
        else
            self:ret(xpcall(func, serviceFunctions.exception, self, ...))
        end
    else
        self:ret()
        Log.e("pvpBattleCenter:dispatchcmd error: cmmand not found:", cmd, ...)
    end
end

-- 返回数据
function pvpBattleCenter:ret(_, ...)
    skynet.ret(skynet.pack(...))
end

return pvpBattleCenter