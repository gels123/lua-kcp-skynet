--[[
	帧同步服务中心
	战场流程:
		[服务器]创建战场, 推送创建战场成功, 可以请求准备完成(status=1) =>
		[客户端]请求准备完成 =>
		[服务器]推送所有人都已准备完成, 可以请求加载场景(status=2) =>
		[客户端]请求加载场景完成 =>
		[服务器]推送所有人都已加载场景完成, 开始游戏(status=3) =>
		...[客户端]请求操作指令、[服务器]帧指令转发... =>
		[服务器]推送游戏结束, 等待结算(status=4) =>
		[服务器]结算结束, 删除战场
]]
local skynet = require "skynet"
local serviceCenterBase = require "serviceCenterBase2"
local frameCenter = class("frameCenter", serviceCenterBase)

-- 战场状态
local eBattleStatus = {
	ePrepare = 1,			-- 创建战场成功, 准备状态
	eLoad = 2,				-- 所有人都已准备完成, 加载场景状态
	eStart = 3,				-- 所有人都已加载场景完成, 开始游戏状态
	eSettle = 4,			-- 游戏结束, 等待结算状态
}

-- 构造
function frameCenter:ctor()
	-- 不返回数据的指令集
	self.sendCmd = {
	}
	self.kid = nil
	self.idx = nil
	-- 计时器
    self.myTimer = require("myScheduler").new()
    -- 计时器关联
    self.timerRef = {}
	-- 战场关联
	self.battleRef = {}
	-- 随机种子
	math.randomseed(tonumber(tostring(os.time()):reverse():sub(1, 6)))
end

-- 初始化
function frameCenter:init(kid, idx)
	Log.i("==frameCenter:init begin==", kid, idx)
	self.kid = kid
	self.idx = idx
	Log.i("==frameCenter:init end==", kid, idx)
end

-- 创建一场战斗
-- @battleId 战斗ID
-- @uids 玩家ID列表
-- @frameRate 帧率(默认16帧, 60ms/帧)
-- @maxTime 最大战斗时长(秒)
function frameCenter:createBattle(battleId, uids, frameRate, maxTime)
	Log.i("frameCenter:createBattle=", battleId, uids, frameRate, maxTime)
	if not battleId or not uids or not next(uids) or not frameRate or frameRate <= 0 or frameRate >= 100 or not maxTime or maxTime <= 0 then
		Log.w("frameCenter:createBattle error1", battleId, uids, frameRate, maxTime)
		return false, gErrDef.Err_ILLEGAL_PARAMS
	end
	if self.battleRef[battleId] then
		Log.w("frameCenter:createBattle error2", battleId, uids, frameRate, maxTime)
		return false
	end
	self.battleRef[battleId] = {
		uids = uids,					-- 玩家ID
		curFrame = 0,					-- 当前帧数
		frameRate = frameRate, 			-- 帧率
		maxTime = maxTime,				-- 最大战斗时长
		maxFrame = math.ceil(maxTime*1000/math.floor(100/frameRate)), -- 最大帧数
		info = {},						-- 玩家战斗帧信息
		isEnd = false,					-- 是否战斗结束
	}
	-- 创建取消战斗计时器
	local endTime = serviceFunctions.systemTime() + 10
	self.timerRef[battleId] = self.myTimer:schedule(handler(self, self.onCancelBattleCallback), endTime, {battleId = battleId, timerType = eBattleStatus.eCancelBattle})
	-- 成功
	return true
end

-- 取消战斗计时器回调
function frameCenter:onCancelBattleCallback(data)
	local battleId, timerType = data.battleId, data.timerType
	Log.i("frameCenter:onCancelBattleCallback=", battleId, timerType)
	if not battleId or not timerType then
		Log.i("frameCenter:onCancelBattleCallback error1", battleId, timerType)
		return
	end
	if not self.timerRef[battleId] then
		Log.i("frameCenter:onCancelBattleCallback error2", battleId, timerType)
		return
	end
	self.timerRef[battleId] = nil
	if timerType == eBattleStatus.eCancelBattle then
		-- 取消一场战斗
		self:cancelBattle(battleId)
	else
		-- 忽略
		Log.w("frameCenter:onCancelBattleCallback igore", battleId, timerType)
	end
end

-- 取消一场战斗
function frameCenter:cancelBattle(battleId)
	Log.i("frameCenter:cancelBattle=", battleId)
	if self.battleRef[battleId] then
		return false
	end
	-- 记录玩家
	local uids = self.battleRef[battleId].uids
	-- 取消战斗
	self.battleRef[battleId] = nil
	-- 取消计时器
	if self.timerRef[battleId] then
		self.myTimer:stop(self.timerRef[battleId])
		self.timerRef[battleId] = nil
	end
	-- 推送客户端, 战斗取消
	-- 成功
	return true
end

-- 加入一场战斗
function frameCenter:joinBattle(battleId, uid)
	Log.d("frameCenter:joinBattle=", battleId, uid)
	-- 检查战场是否存在
	if not self.battleRef[battleId] or not self.battleRef[battleId].uids[uid] then
		Log.w("frameCenter:joinBattle error1", battleId, uid)
		return false
	end
	self.battleRef[battleId].info[uid] = {
		isExit = false,
		frames = {},
	}
	-- 全部人已进入战场, 则开始战斗
	if table.nums(self.battleRef[battleId].info) >= table.nums(self.battleRef[battleId].uids) then
		skynet.fork(self.startBattle, self, battleId)
	end
	-- 成功
	return true
end

-- 退出一场战斗
function frameCenter:leaveBattle(battleId, uid)
	Log.d("frameCenter:leaveBattle=", battleId, uid)
	-- 检查能否退出战场
	if not self.battleRef[battleId] or not self.battleRef[battleId].info[uid] or self.bAttleframerEF[battleid].info[playerid].isExit then
		Log.w("frameCenter:leaveBattle error1", battleId, uid)
		return false
	end
	-- 退出战场
	self.bAttleframerEF[battleid].info[playerid].isExit = nil
	self.bAttleframerEF[battleid].info[playerid].frames = {}
	-- 检查是否所有人都已经退出战场, 是则结束战场
	local isAll = true
	for uid,v in pairs(self.bAttleframerEF[battleid].info) do
		if not v.isExit then
			isAll = false
			break
		end
	end
	if isAll then
		self.bAttleframerEF[battleid].isEnd = true
	end
	-- 成功
	return true
end

-- 开始一场战斗
function frameCenter:startBattle(battleId)
	Log.i("frameCenter:startBattle", battleId)
	-- 检查战场是否存在
	if not self.battleRef[battleId] then
		Log.i("frameCenter:startBattle error1", battleId)
		return false
	end
	-- 检查取消战斗计时器是否存在
	if not self.timerRef[battleId] then
		Log.i("frameCenter:startBattle error2", battleId)
		return false
	end
	-- 停止取消战斗计时器
	self.myTimer:stop(self.timerRef[battleId])
	self.timerRef[battleId] = nil
	-- 推送客户端, 战斗开始

	-- 开始跑帧
	local tick = math.floor(100/self.battleRef[battleId].frameRate)
	while(true) do
		if self.battleRef[battleId].curFrame >= self.battleRef[battleId].maxFrame then
			break
		end
		if self.battleRef[battleId].isEnd then
			break
		end
		-- 打包所有玩家帧, 并推送给所有玩家
		local sendMsg = {}
		local curFrame = self.battleRef[battleId].curFrame
		for uid,v in pairs(self.battleRef[battleId].info) do
			if v[curFrame] then
				table.insert(sendMsg, {uid = uid, cmds = v[curFrame]})
			end
		end
		-- 帧数+1
		self.battleRef[battleId].curFrame = self.battleRef[battleId].curFrame + 1
		-- 睡眠
		skynet.sleep(tick)
	end
	-- 推送客户端, 战斗结束
	return true
end

-- 提交帧操作指令
function frameCenter:commitFrameCmd(battleId, uid, frame, cmd)
	Log.d("frameCenter:commitFrameCmd", battleId, uid, frame, cmd)
	local battleRef = self.battleRef[battleId]
	if not battleRef or not battleRef.info[uid] then
		Log.d("frameCenter:commitFrameCmd error1", battleId, uid, frame, cmd)
		return false
	end
	-- 帧数落后太多, 直接抛弃
	local curFrame = battleRef.curFrame
	if curFrame - frame > 60 then
		Log.d("frameCenter:commitFrameCmd error2", battleId, uid, frame, cmd)
		return false
	end
	-- 指令合法性检查
	if battleRef.info[uid][curFrame] then
	end
	-- 添加帧指令
	if not battleRef.info[uid][curFrame] then
		battleRef.info[uid][curFrame] = {}
	end
	table.insert(battleRef.info[uid][curFrame], cmd)
	-- 成功
	return true
end

return frameCenter