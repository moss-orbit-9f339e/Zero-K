-- NOTE overrides section at bottom!
-- ALSO look for comments	-- FIXME: not in base

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    gadgets.lua
--  brief:   the gadget manager, a call-in router
--  author:  Dave Rodgers
--
--  Copyright (C) 2007.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  TODO:  - get rid of the ':'/self referencing, it's a waste of cycles
--         - (De)RegisterCOBCallback(data)
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local HANDLER_BASENAME = "gadgets.lua"
local isMission = VFS.FileExists("mission.lua")	-- or Game.gameName:find("Scenario Editor")

local HANDLER_DIR = 'LuaGadgets/'
local GADGETS_DIR = Script.GetName():gsub('US$', '') .. '/Gadgets/'
local SCRIPT_DIR = Script.GetName() .. '/'

local ECHO_DESCRIPTIONS = false
local SYNC_MEMORY_DEBUG = false --(gcinfo or false)

local VFSMODE = VFS.ZIP_ONLY
if (Spring.IsDevLuaEnabled()) then
  VFSMODE = VFS.RAW_ONLY
end

VFS.Include('LuaRules/engine_compat.lua',   nil, VFSMODE)
VFS.Include(HANDLER_DIR .. 'setupdefs.lua', nil, VFSMODE)
VFS.Include(HANDLER_DIR .. 'system.lua',    nil, VFSMODE)
VFS.Include(HANDLER_DIR .. 'callins.lua',   nil, VFSMODE)
VFS.Include(SCRIPT_DIR .. 'utilities.lua', nil, VFSMODE)

local actionHandler = VFS.Include(HANDLER_DIR .. 'actions.lua', nil, VFSMODE)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  the gadgetHandler object
--

gadgetHandler = {

	gadgets = {},

	orderList = {},

	knownGadgets = {},
	knownCount = 0,
	knownChanged = true,

	GG = {}, -- shared table for gadgets

	globals = {}, -- global vars/funcs

	CMDIDs = {},

	xViewSize    = 1,
	yViewSize    = 1,
	xViewSizeOld = 1,
	yViewSizeOld = 1,

	mouseOwner = nil,

	actionHandler = actionHandler,	-- FIXME: not in base
}

VFS.Include('LuaRules/engine_compat_post.lua', nil, VFSMODE)

-- these call-ins are set to 'nil' if not used
-- they are setup in UpdateCallIns()
local callInLists = {
	"Shutdown",

	"GamePreload",
	"GameStart",
	"GameOver",
	"GameID",
	"TeamDied",

	"GamePaused",

	"PlayerAdded",
	"PlayerChanged",
	"PlayerRemoved",

	"GameFrame",

	"ViewResize",  -- FIXME ?

	"TextCommand",  -- FIXME ?
	"GotChatMsg",
	"RecvLuaMsg",

	-- Custom from gadgets themselves
	"UnitCreatedByMechanic",
	
	-- Unit CallIns
	"UnitCreated",
	"UnitFinished",
	"UnitReverseBuilt",
	"UnitFromFactory",
	"UnitDestroyed",
	"RenderUnitDestroyed",
	"UnitExperience",
	"UnitIdle",
	"UnitCmdDone",
	"UnitPreDamaged",
	"UnitDamaged",
	"UnitStunned",
	"UnitTaken",
	"UnitGiven",
	"UnitEnteredRadar",
	"UnitEnteredLos",
	"UnitLeftRadar",
	"UnitLeftLos",
	"UnitSeismicPing",
	"UnitLoaded",
	"UnitUnloaded",
	"UnitCloaked",
	"UnitDecloaked",
	-- optional
	-- "UnitUnitCollision",
	-- "UnitFeatureCollision",
	-- "UnitMoveFailed",
	"UnitArrivedAtGoal",
	"StockpileChanged",

	-- Feature CallIns
	"FeatureCreated",
	"FeatureDestroyed",
	"FeaturePreDamaged",
	"FeatureDamaged",

	-- Projectile CallIns
	"ProjectileCreated",
	"ProjectileDestroyed",

	-- Shield CallIns
	"ShieldPreDamaged",

	-- Misc Synced CallIns
	"Explosion",

	-- LUS callins
	"ScriptFireWeapon",
	"ScriptEndBurst",

	-- LuaRules CallIns (note: the *PreDamaged calls belong here too)
	"CommandFallback",
	"AllowCommand",
	"AllowStartPosition",
	"AllowUnitCreation",
	"AllowUnitTransfer",
	"AllowUnitBuildStep",
	"AllowUnitTransport",
	"AllowUnitTransportLoad",
	"AllowUnitTransportUnload",
	"AllowUnitCloak",
	"AllowUnitDecloak",
	"AllowUnitTargetRange",
	"AllowFeatureBuildStep",
	"AllowFeatureCreation",
	"AllowResourceLevel",
	"AllowResourceTransfer",
	"AllowDirectUnitControl",
	"AllowBuilderHoldFire",
	"MoveCtrlNotify",
	"TerraformComplete",
	"AllowWeaponTargetCheck",
	"AllowWeaponTarget",
	"AllowWeaponInterceptTarget",
	-- unsynced
	"DrawUnit",
	"DrawFeature",
	"DrawShield",
	"DrawProjectile",
	"RecvSkirmishAIMessage",

	"SunChanged",

	-- COB CallIn  (FIXME?)
	"CobCallback",

	-- Unsynced CallIns
	"Update",
	"DefaultCommand",
	"DrawGenesis",
	"DrawWorld",
	"DrawWorldPreUnit",
	"DrawWorldShadow",
	"DrawWorldReflection",
	"DrawWorldRefraction",
	"DrawScreenEffects",
	"DrawScreenPost",
	"DrawScreen",
	"DrawInMiniMap",
	'DrawOpaqueUnitsLua',
	'DrawOpaqueFeaturesLua',
	'DrawAlphaUnitsLua',
	'DrawAlphaFeaturesLua',
	'DrawShadowUnitsLua',
	'DrawShadowFeaturesLua',

	"RecvFromSynced",

	-- moved from LuaUI
	"KeyPress",
	"KeyRelease",
	"MousePress",
	"MouseRelease",
	"MouseMove",
	"MouseWheel",
	"IsAbove",
	"GetTooltip",

	-- FIXME -- not implemented  (more of these?)
	"WorldTooltip",
	"MapDrawCmd",
	"GameSetup",
	"DefaultCommand",

	-- FIXME: NOT IN BASE
	"UnitCommand",
	"UnitEnteredWater",
	"UnitEnteredAir",
	"UnitLeftWater",
	"UnitLeftAir",

	"UnsyncedHeightMapUpdate"
}


-- initialize the call-in lists
do
	for _,listname in ipairs(callInLists) do
		gadgetHandler[listname .. 'List'] = {}
	end
end


-- Utility call
local isSyncedCode = (SendToUnsynced ~= nil)
local function IsSyncedCode()
	return isSyncedCode
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  array-table reverse iteration
--
--  all callin handlers walk their callin list backwards so
--  that gadgets can RemoveGadget() themselves (during
--  iteration over a callin list) without causing a miscount
--
--  c.f. Array{Insert,Remove}
--
--  The handlers used to do this with a reverse ipairs iterator,
--  "for _,g in r_ipairs(list)", which called a Lua function per
--  gadget. They now use the equivalent numeric loop
--
--    local gList = list
--    for gIdx = #gList, 1, -1 do
--      local g = gList[gIdx]
--
--  Both read the list once, take #list once at the start, visit
--  indices #list..1 and read list[index] when that step begins.
--

--------------------------------------------------------------------------------
--
--  profiler zone names
--
--  ZN[prefix][gadget] is prefix .. gadget.ghInfo.name, built on first use
--  instead of concatenating a new string for every gadget on every call.
--

local ZN = setmetatable({}, {
	__index = function(cache, prefix)
		local names = setmetatable({}, {
			__index = function(names, g)
				local name = prefix .. g.ghInfo.name
				names[g] = name
				return name
			end
		})
		cache[prefix] = names
		return names
	end
})


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  returns:  basename, dirname
--

local function Basename(fullpath)
	local _,_,base = string.find(fullpath, "([^\\/:]*)$")
	local _,_,path = string.find(fullpath, "(.*[\\/:])[^\\/:]*$")
	if (path == nil) then path = "" end
	return base, path
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadgetHandler:Initialize()
local unsortedGadgets = {}

-- get the gadget names
local gadgetFiles = VFS.DirList(GADGETS_DIR, "*.lua", VFSMODE)
	--  table.sort(gadgetFiles)

	--  for k,gf in ipairs(gadgetFiles) do
	--    Spring.Echo('gf1 = ' .. gf) -- FIXME
	--  end

	if ECHO_DESCRIPTIONS then
		Spring.Echo("=== Start Gadgets ===")
	end

	-- stuff the gadgets into unsortedGadgets
	local wantYield = Spring.Yield and Spring.Yield()
	for k,gf in ipairs(gadgetFiles) do
		--    Spring.Echo('gf2 = ' .. gf) -- FIXME
		local gadget = self:LoadGadget(gf)
		if (gadget) then
			table.insert(unsortedGadgets, gadget)
		end
		if wantYield then
			Spring.Yield()
		end
	end

	if ECHO_DESCRIPTIONS then
		Spring.Echo("=== End Gadgets ===")
	end

	-- sort the gadgets
	table.sort(unsortedGadgets, function(g1, g2)
		local l1 = g1.ghInfo.layer
		local l2 = g2.ghInfo.layer
		if (l1 ~= l2) then
			return (l1 < l2)
		end
		local n1 = g1.ghInfo.name
		local n2 = g2.ghInfo.name
		local o1 = self.orderList[n1]
		local o2 = self.orderList[n2]
		if (o1 ~= o2) then
			return (o1 < o2)
		else
			return (n1 < n2)
		end
	end)

	-- add the gadgets
	for _,g in ipairs(unsortedGadgets) do
		gadgetHandler:InsertGadget(g)

		local name = g.ghInfo.name
		local basename = g.ghInfo.basename
		print(string.format("Loaded gadget:  %-18s  <%s>", name, basename))
	end
end


function gadgetHandler:LoadGadget(filename)
	local kbytes = 0
	if SYNC_MEMORY_DEBUG then-- only present in special debug builds, otherwise gcinfo is not preset in synced context!
		collectgarbage("collect") -- call it twice, mark
		collectgarbage("collect") -- sweep
		kbytes = gcinfo()
	end
	local basename = Basename(filename)
	local text = VFS.LoadFile(filename, VFSMODE)
	if (text == nil) then
		Spring.Log(HANDLER_BASENAME, LOG.ERROR, 'Failed to load: ' .. filename)
		return nil
	end
	local chunk, err = loadstring(text, filename)
	if (chunk == nil) then
		Spring.Log(HANDLER_BASENAME, LOG.ERROR, 'Failed to load: ' .. basename .. '  (' .. err .. ')')
		return nil
	end

	local gadget = gadgetHandler:NewGadget()

	setfenv(chunk, gadget)
	local success
	success, err = pcall(chunk)
	if (not success) then
		Spring.Log(HANDLER_BASENAME, LOG.ERROR, 'Failed to load: ' .. basename .. '  (' .. err .. ')')
		return nil
	end
	if (err == false) then -- note that all "normal" gadgets return `nil` implicitly at EOF, so don't do "if not err"
		return nil -- gadget asked for a quiet death
	end

	-- raw access to gadgetHandler
	if (gadget.GetInfo and gadget:GetInfo().script) then
		gadget.scriptCallins = {
			ScriptFireWeapon = function (_, unitID, unitDefID, weaponNum)
				self:ScriptFireWeapon(unitID, unitDefID, weaponNum)
			end,
			ScriptEndBurst = function (_, unitID, unitDefID, weaponNum)
				self:ScriptEndBurst(unitID, unitDefID, weaponNum)
			end,
		}
	end

	-- raw access to gadgetHandler
	if (gadget.GetInfo and gadget:GetInfo().handler) then
		gadget.gadgetHandler = self
	end

	self:FinalizeGadget(gadget, filename, basename)
	local name = gadget.ghInfo.name

	err = self:ValidateGadget(gadget)
	if (err) then
		Spring.Log(HANDLER_BASENAME, LOG.ERROR, 'Failed to load: ' .. basename .. '  (' .. err .. ')')
		return nil
	end

	local knownInfo = self.knownGadgets[name]
	if (knownInfo) then
		if (knownInfo.active) then
			Spring.Log(HANDLER_BASENAME, LOG.ERROR, 'Failed to load: ' .. basename .. '  (duplicate name)')
		return nil
		end
	else
		-- create a knownInfo table
		knownInfo = {}
		knownInfo.desc     = gadget.ghInfo.desc
		knownInfo.author   = gadget.ghInfo.author
		knownInfo.basename = gadget.ghInfo.basename
		knownInfo.filename = gadget.ghInfo.filename
		self.knownGadgets[name] = knownInfo
		self.knownCount = self.knownCount + 1
		self.knownChanged = true
	end
	knownInfo.active = true

	local info  = gadget.GetInfo and gadget:GetInfo()
	local order = self.orderList[name]
	if (((order ~= nil) and (order > 0)) or ((order == nil) and ((info == nil) or info.enabled))) then
		-- this will be an active gadget
		if (order == nil) then
			self.orderList[name] = 12345  -- back of the pack
		else
			self.orderList[name] = order
		end
	else
		self.orderList[name] = 0
		self.knownGadgets[name].active = false
		return nil
	end

	if info and ECHO_DESCRIPTIONS then
		Spring.Echo(filename, info.name, info.desc)
	end

	if SYNC_MEMORY_DEBUG and kbytes > 0 then
		collectgarbage("collect") -- mark
		collectgarbage("collect") -- sweep
		Spring.Echo("LoadGadget\t" .. filename .. "\t" .. (gcinfo() - kbytes) .. "\t" .. gcinfo() .. "\t" .. (IsSyncedCode() and 1 or 0))
	end
	return gadget
end


function gadgetHandler:NewGadget()
	local gadget = {}
	-- load the system calls into the gadget table
	for k,v in pairs(System) do
		gadget[k] = v
	end
	gadget._G = _G         -- the global table
	gadget.GG = self.GG    -- the shared table
	gadget.gadget = gadget -- easy self referencing

	-- wrapped calls (closures)
	gadget.gadgetHandler = {}
	local gh = gadget.gadgetHandler

	gh.gadgetHandler = self	-- NOT IN BASE (required for api_subdir_gadgets)

	gadget.include  = function (f)
		return VFS.Include(f, gadget, VFSMODE)
	end

	gh.RaiseGadget  = function (_) self:RaiseGadget(gadget)      end
	gh.LowerGadget  = function (_) self:LowerGadget(gadget)      end
	gh.RemoveGadget = function (_) self:RemoveGadget(gadget)     end
	gh.GetViewSizes = function (_) return self:GetViewSizes()    end
	gh.GetHourTimer = function (_) return self:GetHourTimer()    end
	gh.IsSyncedCode = function (_) return IsSyncedCode()         end

	gh.UpdateCallIn = function (_, name)
		self:UpdateGadgetCallIn(name, gadget)
	end
	gh.RemoveCallIn = function (_, name)
		self:RemoveGadgetCallIn(name, gadget)
	end

	gh.RegisterCMDID = function(_, id)
		self:RegisterCMDID(gadget, id)
	end

	gh.RegisterGlobal = function(_, name, value)
		return self:RegisterGlobal(gadget, name, value)
	end
	gh.DeregisterGlobal = function(_, name)
		return self:DeregisterGlobal(gadget, name)
	end
	gh.SetGlobal = function(_, name, value)
		return self:SetGlobal(gadget, name, value)
	end

	gh.AddChatAction = function (_, cmd, func, help)
		return actionHandler.AddChatAction(gadget, cmd, func, help)
	end
	gh.RemoveChatAction = function (_, cmd)
		return actionHandler.RemoveChatAction(gadget, cmd)
	end

	if (not IsSyncedCode()) then
		gh.AddSyncAction = function(_, cmd, func, help)
			return actionHandler.AddSyncAction(gadget, cmd, func, help)
		end
		gh.RemoveSyncAction = function(_, cmd)
			return actionHandler.RemoveSyncAction(gadget, cmd)
		end
	end

	if IsSyncedCode() then
		gh.NotifyUnitCreatedByMechanic = function(_, unitID, parentID, mechanicName, extraData)
			self:UnitCreatedByMechanic(unitID, parentID, mechanicName, extraData)
		end
	end

	-- for proxied call-ins
	gh.IsMouseOwner = function (_)
		return (self.mouseOwner == gadget)
	end
	gh.DisownMouse  = function (_)
		if (self.mouseOwner == gadget) then
			self.mouseOwner = nil
		end
	end

	return gadget
end


function gadgetHandler:FinalizeGadget(gadget, filename, basename)
	local gi = {}

	gi.filename = filename
	gi.basename = basename
	if (gadget.GetInfo == nil) then
		gi.name  = basename
		gi.layer = 0
	else
		local info = gadget:GetInfo()
		gi.name      = info.name    or basename
		gi.layer     = info.layer   or 0
		gi.desc      = info.desc    or ""
		gi.author    = info.author  or ""
		gi.license   = info.license or ""
		gi.enabled   = info.enabled or false
	end

	gadget.ghInfo = {}  --  a proxy table
	local mt = {
		__index = gi,
		__newindex = function() error("ghInfo tables are read-only") end,
		__metatable = "protected"
	}
	setmetatable(gadget.ghInfo, mt)
end


function gadgetHandler:ValidateGadget(gadget)
	if (gadget.GetTooltip and not gadget.IsAbove) then
		return "Gadget has GetTooltip() but not IsAbove()"
	end
	if (gadget.TweakGetTooltip and not gadget.TweakIsAbove) then
		return "Gadget has TweakGetTooltip() but not TweakIsAbove()"
	end
	return nil
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function ArrayInsert(t, f, g)
	if (f) then
		local layer = g.ghInfo.layer
		local index = 1
		for i,v in ipairs(t) do
			if (v == g) then
				return -- already in the table
			end

			-- insert-sort the gadget based on its layer
			-- note: reversed value ordering, highest to lowest
			-- iteration over the callin lists is also reversed
			if (layer < v.ghInfo.layer) then
				index = i + 1
			end
		end
		table.insert(t, index, g)
	end
end


local function ArrayRemove(t, g)
	for k,v in ipairs(t) do
		if (v == g) then
			table.remove(t, k)
			-- break
		end
	end
end


function gadgetHandler:InsertGadget(gadget)
	if (gadget == nil) then
		return
	end

	ArrayInsert(self.gadgets, true, gadget)
	for _,listname in ipairs(callInLists) do
		local func = gadget[listname]
		if (type(func) == 'function') then
			ArrayInsert(self[listname..'List'], func, gadget)
		end
	end

	self:UpdateCallIns()
	if (gadget.Initialize) then
		gadget:Initialize()
	end
	self:UpdateCallIns()
end


function gadgetHandler:RemoveGadget(gadget)
	if (gadget == nil) then
		return
	end

	local name = gadget.ghInfo.name
	self.knownGadgets[name].active = false
	--Spring.Echo(name)
	if (gadget.Shutdown) then
		gadget:Shutdown()
	end

	ArrayRemove(self.gadgets, gadget)
	self:RemoveGadgetGlobals(gadget)
	actionHandler.RemoveGadgetActions(gadget)
	for _,listname in ipairs(callInLists) do
		ArrayRemove(self[listname..'List'], gadget)
	end

	for id,g in pairs(self.CMDIDs) do
		if (g == gadget) then
			self.CMDIDs[id] = nil
		end
	end

	self:UpdateCallIns()
end


--------------------------------------------------------------------------------

function gadgetHandler:UpdateCallIn(name)
	local listName = name .. 'List'
	if ((#self[listName] > 0) or (name == 'GotChatMsg') or (name == 'RecvFromSynced')) then
		local selffunc = self[name]
		_G[name] = function(...)
			return selffunc(self, ...)
		end
	else
		_G[name] = nil
	end
	Script.UpdateCallIn(name)
end


function gadgetHandler:UpdateGadgetCallIn(name, g)
	local listName = name .. 'List'
	local ciList = self[listName]
	if (ciList) then
		local func = g[name]
		if (type(func) == 'function') then
			ArrayInsert(ciList, func, g)
		else
			ArrayRemove(ciList, g)
		end
		self:UpdateCallIn(name)
	else
		Spring.Log(HANDLER_BASENAME, LOG.ERROR, 'UpdateGadgetCallIn: bad name: ' .. name)
	end
end


function gadgetHandler:RemoveGadgetCallIn(name, g)
	local listName = name .. 'List'
	local ciList = self[listName]
	if (ciList) then
		ArrayRemove(ciList, g)
		self:UpdateCallIn(name)
	else
		Spring.Log(HANDLER_BASENAME, LOG.ERROR, 'RemoveGadgetCallIn: bad name: ' .. name)
	end
end


function gadgetHandler:UpdateCallIns()
	for _,name in ipairs(callInLists) do
		self:UpdateCallIn(name)
	end
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadgetHandler:EnableGadget(name)
	local ki = self.knownGadgets[name]
	if (not ki) then
		Spring.Log(HANDLER_BASENAME, LOG.ERROR, "EnableGadget(), could not find gadget: " .. tostring(name))
		return false
	end
	if (not ki.active) then
		Spring.Echo('Loading:  '..ki.filename)
	local order = gadgetHandler.orderList[name]
	if (not order or (order <= 0)) then
		self.orderList[name] = 1
	end
	local w = self:LoadGadget(ki.filename)
	if (not w) then return false end
		self:InsertGadget(w)
	end
	return true
end


function gadgetHandler:DisableGadget(name)
	local ki = self.knownGadgets[name]
	if (not ki) then
		Spring.Log(HANDLER_BASENAME, LOG.ERROR, "DisableGadget(), could not find gadget: " .. tostring(name))
		return false
	end
	if (ki.active) then
		local w = self:FindGadget(name)
		if (not w) then return false end
		Spring.Echo('Removed:  '..ki.filename)
		self:RemoveGadget(w)     -- deactivate
		self.orderList[name] = 0 -- disable
	end
	return true
end


function gadgetHandler:ToggleGadget(name)
	local ki = self.knownGadgets[name]
	if (not ki) then
		Spring.Echo("ToggleGadget(), could not find gadget: " .. tostring(name))
		return
	end
	if (ki.active) then
		return self:DisableGadget(name)
	elseif (self.orderList[name] <= 0) then
		return self:EnableGadget(name)
	else
		-- the gadget is not active, but enabled; disable it
		self.orderList[name] = 0
	end
	return true
end


--------------------------------------------------------------------------------

local function FindGadgetIndex(t, w)
	for k,v in ipairs(t) do
		if (v == w) then
			return k
		end
	end
	return nil
end


local function FindLowestIndex(t, i, layer)
	for x = (i - 1), 1, -1 do
		if (t[x].ghInfo.layer < layer) then
			return x + 1
		end
	end
	return 1
end


function gadgetHandler:RaiseGadget(gadget)
	if (gadget == nil) then
		return
	end
	local function Raise(t, f, w)
		if (f == nil) then return end
		local i = FindGadgetIndex(t, w)
		if (i == nil) then return end
		local n = FindLowestIndex(t, i, w.ghInfo.layer)
		if (n and (n < i)) then
			table.remove(t, i)
			table.insert(t, n, w)
		end
	end
	Raise(self.gadgets, true, gadget)
	for _,listname in ipairs(callInLists) do
		Raise(self[listname..'List'], gadget[listname], gadget)
	end
end


local function FindHighestIndex(t, i, layer)
	local ts = #t
	for x = (i + 1),ts do
		if (t[x].ghInfo.layer > layer) then
			return (x - 1)
		end
	end
	return (ts + 1)
end


function gadgetHandler:LowerGadget(gadget)
	if (gadget == nil) then
		return
	end
	local function Lower(t, f, w)
		if (f == nil) then return end
		local i = FindGadgetIndex(t, w)
		if (i == nil) then return end
		local n = FindHighestIndex(t, i, w.ghInfo.layer)
		if (n and (n > i)) then
			table.insert(t, n, w)
			table.remove(t, i)
		end
	end
	Lower(self.gadgets, true, gadget)
	for _,listname in ipairs(callInLists) do
		Lower(self[listname..'List'], gadget[listname], gadget)
	end
end


function gadgetHandler:FindGadget(name)
	if (type(name) ~= 'string') then
		return nil
	end
	for k,v in ipairs(self.gadgets) do
		if (name == v.ghInfo.name) then
			return v,k
		end
	end
	return nil
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  Global var/func management
--

function gadgetHandler:RegisterGlobal(owner, name, value)
	if ((name == nil) or (_G[name]) or (self.globals[name]) or (CallInsMap and CallInsMap[name]) or (CALLIN_MAP and CALLIN_MAP[name])) then
		return false
	end
	_G[name] = value
	self.globals[name] = owner
	return true
end


function gadgetHandler:DeregisterGlobal(owner, name)
	if (name == nil) then
		return false
	end
	_G[name] = nil
	self.globals[name] = nil
	return true
end


function gadgetHandler:SetGlobal(owner, name, value)
	if ((name == nil) or (self.globals[name] ~= owner)) then
		return false
	end
	_G[name] = value
	return true
end


function gadgetHandler:RemoveGadgetGlobals(owner)
	local count = 0
	for name, o in pairs(self.globals) do
		if (o == owner) then
			_G[name] = nil
			self.globals[name] = nil
			count = count + 1
		end
	end
	return count
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  Helper facilities
--

local hourTimer = 0


function gadgetHandler:GetHourTimer()
	return hourTimer
end

function gadgetHandler:RegisterCMDID(gadget, id)
	if not id then
		Spring.Log(HANDLER_BASENAME, LOG.ERROR, 'Gadget (' .. gadget.ghInfo.name .. ') ' ..
			'tried to register a NIL CMD_ID')
	else
		if (id < 1000) then
		Spring.Log(HANDLER_BASENAME, LOG.ERROR, 'Gadget (' .. gadget.ghInfo.name .. ') ' ..
			'tried to register a reserved CMD_ID')
		Script.Kill('Reserved CMD_ID code: ' .. id)
	end

	if (self.CMDIDs[id] ~= nil) then
		Spring.Log(HANDLER_BASENAME, LOG.ERROR, 'Gadget (' .. gadget.ghInfo.name .. ') ' ..
			'tried to register a duplicated CMD_ID')
		Script.Kill('Duplicate CMD_ID code: ' .. id)
	end

	self.CMDIDs[id] = gadget
end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  The call-in distribution routines
--

function gadgetHandler:GamePreload()
	tracy.ZoneBeginN("G:GameFrame")
	local gList = self.GamePreloadList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:GameFrame:"][g])
		g:GamePreload()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:GameStart()
	tracy.ZoneBeginN("G:GameStart")
	local gList = self.GameStartList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:GameStart:"][g])
		g:GameStart()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:GamePaused(playerID, paused)
	tracy.ZoneBeginN("G:GamePaused")
	local gList = self.GamePausedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:GamePaused:"][g])
		g:GamePaused(playerID, paused)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:Shutdown()
	tracy.ZoneBeginN("G:Shutdown")
	Spring.Echo("Start gadgetHandler:Shutdown")
	local gList = self.ShutdownList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		local name = g.ghInfo.name or "UNKNOWN NAME"
		Spring.Echo("Shutdown - " .. name)
		tracy.ZoneBeginN(ZN["G:Shutdown:"][g])
		g:Shutdown()
		tracy.ZoneEnd()
	end
	Spring.Echo("End gadgetHandler:Shutdown")
	tracy.ZoneEnd()
	return
end

function gadgetHandler:GameFrame(frameNum)
	tracy.ZoneBeginN("G:GameFrame")
	local gList = self.GameFrameList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:GameFrame:"][g])
		g:GameFrame(frameNum)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:RecvLuaMsg(msg, player)
	tracy.ZoneBeginN("G:RecvLuaMsg")
	local gList = self.RecvLuaMsgList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:RecvLuaMsg:"][g])
		if (g:RecvLuaMsg(msg, player)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return false
end

--------------------------------------------------------------------------------
--
--  Game call-ins
--

function gadgetHandler:GameOver(winners)
	tracy.ZoneBeginN("G:GameOver")
	local gList = self.GameOverList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:GameOver:"][g])
		g:GameOver(winners)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:GameID(gameID)
	tracy.ZoneBeginN("G:GameID")
	local gList = self.GameIDList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:GameID:"][g])
		g:GameID(gameID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:TeamDied(teamID)
	tracy.ZoneBeginN("G:TeamDied")
	local gList = self.TeamDiedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:TeamDied:"][g])
		g:TeamDied(teamID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:PlayerAdded(playerID)
	tracy.ZoneBeginN("G:PlayerAdded")
	local gList = self.PlayerAddedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:PlayerAdded:"][g])
		g:PlayerAdded(playerID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:PlayerChanged(playerID)
	tracy.ZoneBeginN("G:PlayerChanged")
	local gList = self.PlayerChangedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:PlayerChanged:"][g])
		g:PlayerChanged(playerID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:PlayerRemoved(playerID, reason)
	tracy.ZoneBeginN("G:PlayerRemoved")
	local gList = self.PlayerRemovedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:PlayerRemoved:"][g])
		g:PlayerRemoved(playerID, reason)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


--------------------------------------------------------------------------------
--
--  LuaRules Game call-ins
--

function gadgetHandler:DrawUnit(unitID, drawMode)
	tracy.ZoneBeginN("G:DrawUnit")
	local gList = self.DrawUnitList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawUnit:"][g])
		if (g:DrawUnit(unitID, drawMode)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return false
end

function gadgetHandler:DrawFeature(featureID, drawMode)
	tracy.ZoneBeginN("G:DrawFeature")
	local gList = self.DrawFeatureList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawFeature:"][g])
		if (g:DrawFeature(featureID, drawMode)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return false
end

function gadgetHandler:DrawShield(unitID, weaponID, drawMode)
	tracy.ZoneBeginN("G:DrawShield")
	local gList = self.DrawShieldList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawShield:"][g])
		if (g:DrawShield(unitID, weaponID, drawMode)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return false
end

function gadgetHandler:DrawProjectile(projectileID, drawMode)
	tracy.ZoneBeginN("G:DrawProjectile")
	local gList = self.DrawProjectileList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawProjectile:"][g])
		if (g:DrawProjectile(projectileID, drawMode)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return false
end

function gadgetHandler:RecvSkirmishAIMessage(aiTeam, dataStr)
	tracy.ZoneBeginN("G:RecvSkirmishAIMessage")
	local gList = self.RecvSkirmishAIMessageList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:RecvSkirmishAIMessage:"][g])
		local dataRet = g:RecvSkirmishAIMessage(aiTeam, dataStr)
		tracy.ZoneEnd()
		if (dataRet) then
			tracy.ZoneEnd()
			return dataRet
		end
	end
	tracy.ZoneEnd()
end

function gadgetHandler:ScriptFireWeapon(unitID, unitDefID, weaponNum)
	tracy.ZoneBeginN("G:ScriptFireWeapon")
	local gList = self.ScriptFireWeaponList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:ScriptFireWeapon:"][g])
		g:ScriptFireWeapon(unitID, unitDefID, weaponNum)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

function gadgetHandler:ScriptEndBurst(unitID, unitDefID, weaponNum)
	tracy.ZoneBeginN("G:ScriptEndBurst")
	local gList = self.ScriptEndBurstList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:ScriptEndBurst:"][g])
		g:ScriptEndBurst(unitID, unitDefID, weaponNum)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

function gadgetHandler:CommandFallback(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag)
	tracy.ZoneBeginN("G:CommandFallback")
	local gList = self.CommandFallbackList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:CommandFallback:"][g])
		local used, remove = g:CommandFallback(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag)
		tracy.ZoneEnd()
		if (used) then
			tracy.ZoneEnd()
			return remove
		end
	end
	tracy.ZoneEnd()
	return true  -- remove the command
end

function gadgetHandler:AllowStartPosition(playerID, teamID, readyState, cx, cy, cz, rx, ry, rz)
	tracy.ZoneBeginN("G:AllowStartPosition")
	local gList = self.AllowStartPositionList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowStartPosition:"][g])
		if (not g:AllowStartPosition(playerID, teamID, readyState, cx, cy, cz, rx, ry, rz)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end

function gadgetHandler:AllowUnitCreation(unitDefID, builderID, builderTeam, x, y, z, facing)
	tracy.ZoneBeginN("G:AllowUnitCreation")
	local gList = self.AllowUnitCreationList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowUnitCreation:"][g])
		local allow, drop = g:AllowUnitCreation(unitDefID, builderID, builderTeam, x, y, z, facing)
		tracy.ZoneEnd()
		if not allow then
			tracy.ZoneEnd()
			return false, drop
		end
	end
	tracy.ZoneEnd()
	return true, true
end


function gadgetHandler:AllowUnitTransfer(unitID, unitDefID, oldTeam, newTeam, capture)
	tracy.ZoneBeginN("G:AllowUnitTransfer")
	local gList = self.AllowUnitTransferList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowUnitTransfer:"][g])
		if (not g:AllowUnitTransfer(unitID, unitDefID, oldTeam, newTeam, capture)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end


function gadgetHandler:AllowUnitBuildStep(builderID, builderTeam, unitID, unitDefID, part)
	tracy.ZoneBeginN("G:AllowUnitBuildStep")
	local gList = self.AllowUnitBuildStepList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowUnitBuildStep:"][g])
		if (not g:AllowUnitBuildStep(builderID, builderTeam, unitID, unitDefID, part)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end

function gadgetHandler:AllowUnitTransport(
	transporterID, transporterUnitDefID, transporterTeam,
	transporteeID, transporteeUnitDefID, transporteeTeam)
	tracy.ZoneBeginN("G:AllowUnitTransport")
	local gList = self.AllowUnitTransportList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowUnitTransport:"][g])
		if (not g:AllowUnitTransport(
			transporterID, transporterUnitDefID, transporterTeam,
			transporteeID, transporteeUnitDefID, transporteeTeam
		)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end

function gadgetHandler:AllowUnitTransportLoad(
	transporterID, transporterUnitDefID, transporterTeam,
	transporteeID, transporteeUnitDefID, transporteeTeam,
	loadPosX, loadPosY, loadPosZ)
	tracy.ZoneBeginN("G:AllowUnitTransportLoad")
	local gList = self.AllowUnitTransportLoadList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowUnitTransportLoad:"][g])
		if (not g:AllowUnitTransportLoad(
			transporterID, transporterUnitDefID, transporterTeam,
			transporteeID, transporteeUnitDefID, transporteeTeam,
			loadPosX, loadPosY, loadPosZ
		)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end

function gadgetHandler:AllowUnitTransportUnload(
	transporterID, transporterUnitDefID, transporterTeam,
	transporteeID, transporteeUnitDefID, transporteeTeam,
	unloadPosX, unloadPosY, unloadPosZ)
	tracy.ZoneBeginN("G:AllowUnitTransportUnload")
	local gList = self.AllowUnitTransportUnloadList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowUnitTransportUnload:"][g])
		if (not g:AllowUnitTransportUnload(
			transporterID, transporterUnitDefID, transporterTeam,
			transporteeID, transporteeUnitDefID, transporteeTeam,
			unloadPosX, unloadPosY, unloadPosZ
		)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
		return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end

function gadgetHandler:AllowUnitCloak(unitID, enemyID)
	tracy.ZoneBeginN("G:AllowUnitCloak")
-- The case can be that unitID == enemyID. This is for engine stunned unitID, they are their own enemies.
	local gList = self.AllowUnitCloakList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowUnitCloak:"][g])
		if (not g:AllowUnitCloak(unitID, enemyID)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()

	return true
end


function gadgetHandler:AllowUnitDecloak(unitID, objectID, weaponID)
	tracy.ZoneBeginN("G:AllowUnitDecloak")
	local gList = self.AllowUnitDecloakList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowUnitDecloak:"][g])
		if (not g:AllowUnitDecloak(unitID, objectID, weaponID)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end

	tracy.ZoneEnd()
	return true
end


function gadgetHandler:AllowFeatureBuildStep(builderID, builderTeam,
	featureID, featureDefID, part)
	tracy.ZoneBeginN("G:AllowFeatureBuildStep")
	local gList = self.AllowFeatureBuildStepList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowFeatureBuildStep:"][g])
		if (not g:AllowFeatureBuildStep(builderID, builderTeam, featureID, featureDefID, part)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end


function gadgetHandler:AllowFeatureCreation(featureDefID, teamID, x, y, z)
	tracy.ZoneBeginN("G:AllowFeatureCreation")
	local gList = self.AllowFeatureCreationList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowFeatureCreation:"][g])
		if (not g:AllowFeatureCreation(featureDefID, teamID, x, y, z)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end


function gadgetHandler:AllowResourceLevel(teamID, res, level)
	tracy.ZoneBeginN("G:AllowResourceLevel")
	local gList = self.AllowResourceLevelList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowResourceLevel:"][g])
		if (not g:AllowResourceLevel(teamID, res, level)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end


function gadgetHandler:AllowResourceTransfer(oldTeamID, newTeamID, res, amount)
	tracy.ZoneBeginN("G:AllowResourceTransfer")
	local gList = self.AllowResourceTransferList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowResourceTransfer:"][g])
		if (not g:AllowResourceTransfer(oldTeamID, newTeamID, res, amount)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end


function gadgetHandler:AllowDirectUnitControl(unitID, unitDefID, unitTeam, playerID)
	tracy.ZoneBeginN("G:AllowDirectUnitControl")
	local gList = self.AllowDirectUnitControlList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowDirectUnitControl:"][g])
		if (not g:AllowDirectUnitControl(unitID, unitDefID, unitTeam,
			playerID)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end

function gadgetHandler:AllowBuilderHoldFire(unitID, unitDefID, action)
	tracy.ZoneBeginN("G:AllowBuilderHoldFire")
	local gList = self.AllowBuilderHoldFireList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowBuilderHoldFire:"][g])
		if (not g:AllowBuilderHoldFire(unitID, unitDefID, action)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end


function gadgetHandler:MoveCtrlNotify(unitID, unitDefID, unitTeam, data)
	tracy.ZoneBeginN("G:MoveCtrlNotify")
	local state = false
	local gList = self.MoveCtrlNotifyList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:MoveCtrlNotify:"][g])
		if (g:MoveCtrlNotify(unitID, unitDefID, unitTeam, data)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			state = true
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return state
end


function gadgetHandler:TerraformComplete(unitID, unitDefID, unitTeam, buildUnitID, buildUnitDefID, buildUnitTeam)
	tracy.ZoneBeginN("G:TerraformComplete")
	local gList = self.TerraformCompleteList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:TerraformComplete:"][g])
		local stop = g:TerraformComplete(unitID, unitDefID, unitTeam, buildUnitID, buildUnitDefID, buildUnitTeam)
		tracy.ZoneEnd()
		if (stop) then
			tracy.ZoneEnd()
			return true
		end
	end
	tracy.ZoneEnd()
	return false
end


function gadgetHandler:AllowWeaponTargetCheck(attackerID, attackerWeaponNum, attackerWeaponDefID)
	tracy.ZoneBeginN("G:AllowWeaponTargetCheck")
	local ignore = true
	local gList = self.AllowWeaponTargetCheckList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowWeaponTargetCheck:"][g])
		local allowCheck, ignoreCheck = g:AllowWeaponTargetCheck(attackerID, attackerWeaponNum, attackerWeaponDefID)
		tracy.ZoneEnd()
		if not ignoreCheck then
			ignore = false
			if not allowCheck then
				tracy.ZoneEnd()
				return 0
			end
		end
	end
	tracy.ZoneEnd()

	return ((ignore and -1) or 1)
end

-- AllowWeaponTarget is also called when auto-generating CAI attack commands.
-- When targetID=-1 and weaponNum=-1 targetPriority determines the target search
-- radius; targetPriority=nil accompanies any actual

function gadgetHandler:AllowWeaponTarget(attackerID, targetID, attackerWeaponNum, attackerWeaponDefID, defPriority)
	tracy.ZoneBeginN("G:AllowWeaponTarget")
	local allowed = true
	local returnValue

	if targetID == -1 then
		local unitID = attackerID
		local aquireRange = defPriority
		local gList = self.AllowUnitTargetRangeList
		for gIdx = #gList, 1, -1 do
			local g = gList[gIdx]
			-- Send priority to each successive gadget.
			tracy.ZoneBeginN(ZN["G:AllowUnitTargetRange:"][g])
			local targetAllowed, newRange = g:AllowUnitTargetRange(unitID, aquireRange)
			tracy.ZoneEnd()

			if (not targetAllowed) then
				allowed = false
				break
			end

			aquireRange = newRange
		end
		tracy.ZoneEnd()
		return true, aquireRange
	end

	local priority = defPriority
	local gList = self.AllowWeaponTargetList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		-- Send priority to each successive gadget.
		tracy.ZoneBeginN(ZN["G:AllowWeaponTarget:"][g])
		local targetAllowed, targetPriority = g:AllowWeaponTarget(attackerID, targetID, attackerWeaponNum, attackerWeaponDefID, priority)
		tracy.ZoneEnd()

		if (not targetAllowed) then
			allowed = false
			break
		end

		priority = targetPriority
	end
	tracy.ZoneEnd()
	return allowed, priority
end

function gadgetHandler:AllowWeaponInterceptTarget(interceptorUnitID, interceptorWeaponNum, targetProjectileID)
	tracy.ZoneBeginN("G:AllowWeaponInterceptTarget")
	local gList = self.AllowWeaponInterceptTargetList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:AllowWeaponInterceptTarget:"][g])
		if (not g:AllowWeaponInterceptTarget(interceptorUnitID, interceptorWeaponNum, targetProjectileID)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()

	return true
end

--------------------------------------------------------------------------------
--
--  Unit call-ins
--

function gadgetHandler:UnitCreatedByMechanic(unitID, parentID, mechanicName, extraData)
	tracy.ZoneBeginN("G:UnitCreatedByMechanic")
	local gList = self.UnitCreatedByMechanicList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitCreatedByMechanic:"][g])
		g:UnitCreatedByMechanic(unitID, parentID, mechanicName, extraData)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

local inCreated = false
local finishedDuringCreated = false -- assumes non-recursive create
function gadgetHandler:UnitCreated(unitID, unitDefID, unitTeam, builderID, builderDefID, builderTeamID)
	tracy.ZoneBeginN("G:UnitCreated")

	finishedDuringCreated = false
	inCreated = true
	local gList = self.UnitCreatedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitCreated:"][g])
		g:UnitCreated(unitID, unitDefID, unitTeam, builderID, builderDefID, builderTeamID)
		tracy.ZoneEnd()
	end
	inCreated = false

	if finishedDuringCreated then
		finishedDuringCreated = false
		gadgetHandler:UnitFinished(unitID, unitDefID, unitTeam)
	end
	tracy.ZoneEnd()
end

function gadgetHandler:UnitFinished(unitID, unitDefID, unitTeam)
	tracy.ZoneBeginN("G:UnitFinished")
	if inCreated then
		finishedDuringCreated = true
		tracy.ZoneEnd()
		return
	end

	local gList = self.UnitFinishedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitFinished:"][g])
		g:UnitFinished(unitID, unitDefID, unitTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:UnitReverseBuilt(unitID, unitDefID, unitTeam)
	tracy.ZoneBeginN("G:UnitReverseBuilt")
	local gList = self.UnitReverseBuiltList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitReverseBuilt:"][g])
		g:UnitReverseBuilt(unitID, unitDefID, unitTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:UnitStunned(unitID, unitDefID, unitTeam, stunned)
	tracy.ZoneBeginN("G:UnitStunned")
	local gList = self.UnitStunnedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitStunned:"][g])
		g:UnitStunned(unitID, unitDefID, unitTeam, stunned)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)
	tracy.ZoneBeginN("G:UnitFromFactory")
	local gList = self.UnitFromFactoryList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitFromFactory:"][g])
		g:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam, weaponDefID)
	tracy.ZoneBeginN("G:UnitDestroyed")
	if gadgetHandler.GG._AddUnitDamage_teamID then
		attackerTeam = gadgetHandler.GG._AddUnitDamage_teamID
	end
	local gList = self.UnitDestroyedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitDestroyed:"][g])
		g:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam, weaponDefID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:RenderUnitDestroyed(unitID, unitDefID, unitTeam)
	tracy.ZoneBeginN("G:RenderUnitDestroyed")
	local gList = self.RenderUnitDestroyedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:RenderUnitDestroyed:"][g])
		g:RenderUnitDestroyed(unitID, unitDefID, unitTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitExperience(unitID, unitDefID, unitTeam, experience, oldExperience)
	tracy.ZoneBeginN("G:UnitExperience")
	local gList = self.UnitExperienceList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitExperience:"][g])
		g:UnitExperience(unitID, unitDefID, unitTeam, experience, oldExperience)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitIdle(unitID, unitDefID, unitTeam)
	tracy.ZoneBeginN("G:UnitIdle")
	local gList = self.UnitIdleList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitIdle:"][g])
		g:UnitIdle(unitID, unitDefID, unitTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitCmdDone(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag)
	tracy.ZoneBeginN("G:UnitCmdDone")
	local gList = self.UnitCmdDoneList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitCmdDone:"][g])
		g:UnitCmdDone(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

local UnitPreDamaged_GadgetMap = {}
local UnitPreDamaged_first = true
local allWeaponDefs = {}

do
	for i=-7,#WeaponDefs do
		allWeaponDefs[#allWeaponDefs+1] = i
	end
end

function gadgetHandler:UnitPreDamaged(unitID, unitDefID, unitTeam,
	damage, paralyzer, weaponDefID,
	projectileID, attackerID, attackerDefID, attackerTeam)
	tracy.ZoneBeginN("G:UnitPreDamaged")

	if UnitPreDamaged_first then
		local gList = self.UnitPreDamagedList
		for gIdx = #gList, 1, -1 do
			local g = gList[gIdx]
			tracy.ZoneBeginN(ZN["G:UnitPreDamaged_GetWantedWeaponDef :"][g])
			local weaponDefs = (g.UnitPreDamaged_GetWantedWeaponDef and g:UnitPreDamaged_GetWantedWeaponDef()) or allWeaponDefs
			tracy.ZoneEnd()
			for _,wdid in ipairs(weaponDefs) do
				if UnitPreDamaged_GadgetMap[wdid] then
					UnitPreDamaged_GadgetMap[wdid].count = UnitPreDamaged_GadgetMap[wdid].count + 1
					UnitPreDamaged_GadgetMap[wdid].data[UnitPreDamaged_GadgetMap[wdid].count] = g
				else
					UnitPreDamaged_GadgetMap[wdid] = {
						count = 1,
						data = {g}
					}
				end
			end
		end
		UnitPreDamaged_first = false
	end

	local rDam = damage
	local rImp = 1.0

	local gadgets = UnitPreDamaged_GadgetMap[weaponDefID]
	if gadgets then
		if gadgetHandler.GG._AddUnitDamage_teamID then
			attackerTeam = gadgetHandler.GG._AddUnitDamage_teamID
		end
		local data = gadgets.data
		local g
		for i = 1, gadgets.count do
			g = data[i]
			tracy.ZoneBeginN(ZN["G:UnitPreDamaged:"][g])
			local dam, imp = g:UnitPreDamaged(unitID, unitDefID, unitTeam,
				rDam, paralyzer, weaponDefID,
				attackerID, attackerDefID, attackerTeam,
				projectileID)
			tracy.ZoneEnd()
			if (dam ~= nil) then
				rDam = dam
			end
			if (imp ~= nil) then
				rImp = math.min(imp, rImp)
			end
		end
	end

	tracy.ZoneEnd()
	return rDam, rImp
end


local UnitDamaged_first = true
local UnitDamaged_count = 0
local UnitDamaged_gadgets = {}

function gadgetHandler:UnitDamaged(unitID, unitDefID, unitTeam,
	damage, paralyzer, weaponID, projectileID,
	attackerID, attackerDefID, attackerTeam)
	tracy.ZoneBeginN("G:UnitDamaged")

	if UnitDamaged_first then
		local gList = self.UnitDamagedList
		for gIdx = #gList, 1, -1 do
			local g = gList[gIdx]
			UnitDamaged_count = UnitDamaged_count + 1
			UnitDamaged_gadgets[UnitDamaged_count] = g
		end
		UnitDamaged_first = false
	end

	if gadgetHandler.GG._AddUnitDamage_teamID then
		attackerTeam = gadgetHandler.GG._AddUnitDamage_teamID
	end

	local g
	for i = 1, UnitDamaged_count do
		g = UnitDamaged_gadgets[i]
		tracy.ZoneBeginN(ZN["G:UnitDamaged:"][g])
		g:UnitDamaged(unitID, unitDefID, unitTeam,
		damage, paralyzer, weaponID,
		attackerID, attackerDefID, attackerTeam, projectileID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitTaken(unitID, unitDefID, unitTeam, newTeam)
	tracy.ZoneBeginN("G:UnitTaken")
	local gList = self.UnitTakenList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitTaken:"][g])
		g:UnitTaken(unitID, unitDefID, unitTeam, newTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
	tracy.ZoneBeginN("G:UnitGiven")
	local gList = self.UnitGivenList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitGiven:"][g])
		g:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitEnteredRadar(unitID, unitTeam, allyTeam, unitDefID)
	tracy.ZoneBeginN("G:UnitEnteredRadar")
	local gList = self.UnitEnteredRadarList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitEnteredRadar:"][g])
		g:UnitEnteredRadar(unitID, unitTeam, allyTeam, unitDefID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitEnteredLos(unitID, unitTeam, allyTeam, unitDefID)
	tracy.ZoneBeginN("G:UnitEnteredLos")
	local gList = self.UnitEnteredLosList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitEnteredLos:"][g])
		g:UnitEnteredLos(unitID, unitTeam, allyTeam, unitDefID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitLeftRadar(unitID, unitTeam, allyTeam, unitDefID)
	tracy.ZoneBeginN("G:UnitLeftRadar")
	local gList = self.UnitLeftRadarList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitLeftRadar:"][g])
		g:UnitLeftRadar(unitID, unitTeam, allyTeam, unitDefID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitLeftLos(unitID, unitTeam, allyTeam, unitDefID)
	tracy.ZoneBeginN("G:UnitLeftLos")
	local gList = self.UnitLeftLosList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitLeftLos:"][g])
		g:UnitLeftLos(unitID, unitTeam, allyTeam, unitDefID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitSeismicPing(x, y, z, strength,
	allyTeam, unitID, unitDefID)
	tracy.ZoneBeginN("G:UnitSeismicPing")
	local gList = self.UnitSeismicPingList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitSeismicPing:"][g])
		g:UnitSeismicPing(x, y, z, strength, allyTeam, unitID, unitDefID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitLoaded(unitID, unitDefID, unitTeam, transportID, transportTeam)
	tracy.ZoneBeginN("G:UnitLoaded")
	local gList = self.UnitLoadedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitLoaded:"][g])
		g:UnitLoaded(unitID, unitDefID, unitTeam, transportID, transportTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitUnloaded(unitID, unitDefID, unitTeam, transportID, transportTeam)
	tracy.ZoneBeginN("G:UnitUnloaded")
	local gList = self.UnitUnloadedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitUnloaded:"][g])
		g:UnitUnloaded(unitID, unitDefID, unitTeam, transportID, transportTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitCloaked(unitID, unitDefID, unitTeam)
	tracy.ZoneBeginN("G:UnitCloaked")
	local gList = self.UnitCloakedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitCloaked:"][g])
		g:UnitCloaked(unitID, unitDefID, unitTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitDecloaked(unitID, unitDefID, unitTeam)
	tracy.ZoneBeginN("G:UnitDecloaked")
	local gList = self.UnitDecloakedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitDecloaked:"][g])
		g:UnitDecloaked(unitID, unitDefID, unitTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitUnitCollision(colliderID, collideeID)
	tracy.ZoneBeginN("G:UnitUnitCollision")
	local gList = self.UnitUnitCollisionList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitUnitCollision:"][g])
		g:UnitUnitCollision(colliderID, collideeID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

function gadgetHandler:UnitFeatureCollision(colliderID, collideeID)
	tracy.ZoneBeginN("G:UnitArrivedAtGoal")
	local gList = self.UnitFeatureCollisionList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitArrivedAtGoal:"][g])
		g:UnitFeatureCollision(colliderID, collideeID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

function gadgetHandler:UnitArrivedAtGoal(unitID, unitDefID, teamID)
	tracy.ZoneBeginN("G:UnitArrivedAtGoal")
	local gList = self.UnitArrivedAtGoalList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitArrivedAtGoal:"][g])
		g:UnitArrivedAtGoal(unitID, unitDefID, teamID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
end

function gadgetHandler:StockpileChanged(unitID, unitDefID, unitTeam, weaponNum, oldCount, newCount)
	tracy.ZoneBeginN("G:StockpileChanged")
	local gList = self.StockpileChangedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:StockpileChanged:"][g])
		g:StockpileChanged(unitID, unitDefID, unitTeam, weaponNum, oldCount, newCount)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


--------------------------------------------------------------------------------
--
--  Feature call-ins
--

function gadgetHandler:FeatureCreated(featureID, allyTeam)
	tracy.ZoneBeginN("G:FeatureCreated")
	local gList = self.FeatureCreatedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:FeatureCreated:"][g])
		g:FeatureCreated(featureID, allyTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

local FeaturePreDamaged_GadgetMap = {}
local FeaturePreDamaged_first = true

function gadgetHandler:FeaturePreDamaged(featureID, featureDefID, featureTeam,
	damage, weaponDefID,
	projectileID, attackerID, attackerDefID, attackerTeam)
	tracy.ZoneBeginN("G:FeaturePreDamaged")

	if FeaturePreDamaged_first then
		local gList = self.FeaturePreDamagedList
		for gIdx = #gList, 1, -1 do
			local g = gList[gIdx]
			tracy.ZoneBeginN(ZN["G:FeaturePreDamaged_GetWantedWeaponDef :"][g])
			local weaponDefs = (g.FeaturePreDamaged_GetWantedWeaponDef and g:FeaturePreDamaged_GetWantedWeaponDef()) or allWeaponDefs
			tracy.ZoneEnd()
			for _,wdid in ipairs(weaponDefs) do
				if FeaturePreDamaged_GadgetMap[wdid] then
					FeaturePreDamaged_GadgetMap[wdid].count = FeaturePreDamaged_GadgetMap[wdid].count + 1
					FeaturePreDamaged_GadgetMap[wdid].data[FeaturePreDamaged_GadgetMap[wdid].count] = g
				else
					FeaturePreDamaged_GadgetMap[wdid] = {
						count = 1,
						data = {g}
					}
				end
			end
		end
		FeaturePreDamaged_first = false
	end

	local rDam = damage
	local rImp = 1.0

	local gadgets = FeaturePreDamaged_GadgetMap[weaponDefID]
	if gadgets then
		local data = gadgets.data
		local g
		for i = 1, gadgets.count do
			g = data[i]
			tracy.ZoneBeginN(ZN["G:FeaturePreDamaged:"][g])
			local dam, imp = g:FeaturePreDamaged(featureID, featureDefID, featureTeam,
				rDam, weaponDefID,
				attackerID, attackerDefID, attackerTeam,
				projectileID)
			tracy.ZoneEnd()
			if (dam ~= nil) then
				rDam = dam
			end
			if (imp ~= nil) then
				rImp = math.min(imp, rImp)
			end
		end
	end

	tracy.ZoneEnd()
	return rDam, rImp
end

local FeatureDamaged_first = true
local FeatureDamaged_count = 0
local FeatureDamaged_gadgets = {}

function gadgetHandler:FeatureDamaged(featureID, featureDefID, featureTeam, damage, weaponDefID,
	projectileID, attackerID, attackerDefID, attackerTeam)
	tracy.ZoneBeginN("G:FeatureDamaged")

	if FeatureDamaged_first then
		local gList = self.FeatureDamagedList
		for gIdx = #gList, 1, -1 do
			local g = gList[gIdx]
			FeatureDamaged_count = FeatureDamaged_count + 1
			FeatureDamaged_gadgets[FeatureDamaged_count] = g
		end
		FeatureDamaged_first = false
	end

	if gadgetHandler.GG._AddUnitDamage_teamID then
		attackerTeam = gadgetHandler.GG._AddUnitDamage_teamID
	end

	local g
	for i = 1, FeatureDamaged_count do
		g = FeatureDamaged_gadgets[i]
		tracy.ZoneBeginN(ZN["G:FeatureDamaged:"][g])
		g:FeatureDamaged(featureID, featureDefID, featureTeam, damage, weaponDefID,
		projectileID, attackerID, attackerDefID, attackerTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:FeatureDestroyed(featureID, allyTeam)
	tracy.ZoneBeginN("G:FeatureDestroyed")
	local gList = self.FeatureDestroyedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:FeatureDestroyed:"][g])
		g:FeatureDestroyed(featureID, allyTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


--------------------------------------------------------------------------------
--
--  Projectile call-ins
--

function gadgetHandler:ProjectileCreated(proID, proOwnerID, proWeaponDefID)
	tracy.ZoneBeginN("G:ProjectileCreated")
	local gList = self.ProjectileCreatedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:ProjectileCreated:"][g])
		g:ProjectileCreated(proID, proOwnerID, proWeaponDefID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:ProjectileDestroyed(proID)
	tracy.ZoneBeginN("G:ProjectileDestroyed")
	local gList = self.ProjectileDestroyedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:ProjectileDestroyed:"][g])
		g:ProjectileDestroyed(proID)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


--------------------------------------------------------------------------------
--
--  Shield call-ins
--

function gadgetHandler:ShieldPreDamaged(proID, proOwnerID, shieldEmitterWeaponNum, shieldCarrierUnitID, bounceProjectile, beamEmitterWeaponNum, beamEmitterUnitID, startX, startY, startZ, hitX, hitY, hitZ)
	tracy.ZoneBeginN("G:ShieldPreDamaged")

	local gList = self.ShieldPreDamagedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		-- first gadget to handle this consumes the event
		tracy.ZoneBeginN(ZN["G:ShieldPreDamaged:"][g])
		if (g:ShieldPreDamaged(proID, proOwnerID, shieldEmitterWeaponNum, shieldCarrierUnitID, bounceProjectile, beamEmitterWeaponNum, beamEmitterUnitID, startX, startY, startZ, hitX, hitY, hitZ)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end

	tracy.ZoneEnd()
	return false
end


--------------------------------------------------------------------------------
--
--  Misc call-ins
--

local Explosion_GadgetMap = {}
local Explosion_GadgetSingle = {}

local Explosion_first = true

function gadgetHandler:Explosion(weaponID, px, py, pz, ownerID, proID)
	tracy.ZoneBeginN("G:Explosion")
	if Explosion_first then
		local gList = self.ExplosionList
		for gIdx = #gList, 1, -1 do
			local g = gList[gIdx]
			tracy.ZoneBeginN(ZN["G:Explosion_GetWantedWeaponDef:"][g])
			local weaponDefs = (g.Explosion_GetWantedWeaponDef and g:Explosion_GetWantedWeaponDef()) or allWeaponDefs
			tracy.ZoneEnd()
			for _,wdid in ipairs(weaponDefs) do
				if Explosion_GadgetSingle[wdid] or Explosion_GadgetMap[wdid] then
					if Explosion_GadgetMap[wdid] then
						Explosion_GadgetMap[wdid].count = Explosion_GadgetMap[wdid].count + 1
						Explosion_GadgetMap[wdid].data[Explosion_GadgetMap[wdid].count] = g
					else
						Explosion_GadgetMap[wdid] = {
							count = 2,
							data = {Explosion_GadgetSingle[wdid], g}
						}
						Explosion_GadgetSingle[wdid] = nil
					end
				else
					Explosion_GadgetSingle[wdid] = g
				end
			end
		end
		Explosion_first = false
	end

	local noGfx = false
	local single = Explosion_GadgetSingle[weaponID]
	local map = Explosion_GadgetMap[weaponID]
	if single then
		noGfx = single:Explosion(weaponID, px, py, pz, ownerID, proID)
	elseif map then
		local gadgets = map
		local data = gadgets.data
		local g
		for i = 1, gadgets.count do
			g = data[i]
			tracy.ZoneBeginN(ZN["G::"][g])
			noGfx = noGfx or g:Explosion(weaponID, px, py, pz, ownerID, proID)
			tracy.ZoneEnd()
		end
	end
	tracy.ZoneEnd()
	return noGfx or false
end

--------------------------------------------------------------------------------
--
--  Draw call-ins
--

function gadgetHandler:SunChanged()
	tracy.ZoneBeginN("G:SunChanged")
	local gList = self.SunChangedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:SunChanged:"][g])
		g:SunChanged()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:Update(deltaTime)
	tracy.ZoneBeginN("G:Update")
	local gList = self.UpdateList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:Update:"][g])
		g:Update(deltaTime)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:DefaultCommand(type, id, engineCmd)
	tracy.ZoneBeginN("G:DefaultCommand")
	local gList = self.DefaultCommandList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DefaultCommand:"][g])
		local defCmd = g:DefaultCommand(type, id, engineCmd)
		tracy.ZoneEnd()
		if defCmd then
			tracy.ZoneEnd()
			return defCmd
		end
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:DrawGenesis()
	tracy.ZoneBeginN("G:DrawGenesis")
	local gList = self.DrawGenesisList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawGenesis:"][g])
		g:DrawGenesis()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:DrawWorld()
	tracy.ZoneBeginN("G:DrawWorld")
	local gList = self.DrawWorldList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawWorld:"][g])
		g:DrawWorld()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:DrawWorldPreUnit()
	tracy.ZoneBeginN("G:DrawWorldPreUnit")
	local gList = self.DrawWorldPreUnitList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawWorldPreUnit:"][g])
		g:DrawWorldPreUnit()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:DrawWorldShadow()
	tracy.ZoneBeginN("G:DrawWorldShadow")
	local gList = self.DrawWorldShadowList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawWorldShadow:"][g])
		g:DrawWorldShadow()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:DrawWorldReflection()
	tracy.ZoneBeginN("G:DrawWorldReflection")
	local gList = self.DrawWorldReflectionList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawWorldReflection:"][g])
		g:DrawWorldReflection()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
return
end


function gadgetHandler:DrawWorldRefraction()
	tracy.ZoneBeginN("G:DrawWorldRefraction")
	local gList = self.DrawWorldRefractionList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawWorldRefraction:"][g])
		g:DrawWorldRefraction()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:DrawScreenEffects(vsx, vsy)
	tracy.ZoneBeginN("G:DrawScreenEffects")
	local gList = self.DrawScreenEffectsList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawScreenEffects:"][g])
		g:DrawScreenEffects(vsx, vsy)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:DrawScreenPost(vsx, vsy)
	tracy.ZoneBeginN("G:DrawScreenPost")
	local gList = self.DrawScreenPostList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawScreenPost:"][g])
		g:DrawScreenPost(vsx, vsy)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:DrawScreen(vsx, vsy)
	tracy.ZoneBeginN("G:DrawScreen")
	local gList = self.DrawScreenList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawScreen:"][g])
		g:DrawScreen(vsx, vsy)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:DrawInMiniMap(mmsx, mmsy)
	tracy.ZoneBeginN("G:DrawInMiniMap")
	local gList = self.DrawInMiniMapList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawInMiniMap:"][g])
		g:DrawInMiniMap(mmsx, mmsy)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:DrawOpaqueUnitsLua(deferredPass, drawReflection, drawRefraction)
	tracy.ZoneBeginN("G:DrawOpaqueUnitsLua")
	local gList = self.DrawOpaqueUnitsLuaList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawOpaqueUnitsLua:"][g])
		g:DrawOpaqueUnitsLua(deferredPass, drawReflection, drawRefraction)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:DrawOpaqueFeaturesLua(deferredPass, drawReflection, drawRefraction)
	tracy.ZoneBeginN("G:DrawOpaqueFeaturesLua")
	local gList = self.DrawOpaqueFeaturesLuaList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawOpaqueFeaturesLua:"][g])
		g:DrawOpaqueFeaturesLua(deferredPass, drawReflection, drawRefraction)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:DrawAlphaUnitsLua(drawReflection, drawRefraction)
	tracy.ZoneBeginN("G:DrawAlphaUnitsLua")
	local gList = self.DrawAlphaUnitsLuaList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawAlphaUnitsLua:"][g])
		g:DrawAlphaUnitsLua(drawReflection, drawRefraction)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:DrawAlphaFeaturesLua(drawReflection, drawRefraction)
	tracy.ZoneBeginN("G:DrawAlphaFeaturesLua")
	local gList = self.DrawAlphaFeaturesLuaList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawAlphaFeaturesLua:"][g])
		g:DrawAlphaFeaturesLua(drawReflection, drawRefraction)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:DrawShadowUnitsLua()
	tracy.ZoneBeginN("G:DrawShadowUnitsLua")
	local gList = self.DrawShadowUnitsLuaList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawShadowUnitsLua:"][g])
		g:DrawShadowUnitsLua()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:DrawShadowFeaturesLua()
	tracy.ZoneBeginN("G:DrawShadowFeaturesLua")
	local gList = self.DrawShadowFeaturesLuaList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:DrawShadowFeaturesLua:"][g])
		g:DrawShadowFeaturesLua()
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadgetHandler:KeyPress(key, mods, isRepeat, label, unicode, scanCode)
	tracy.ZoneBeginN("G:KeyPress")
	local gList = self.KeyPressList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:KeyPress:"][g])
		if (g:KeyPress(key, mods, isRepeat, label, unicode, scanCode)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return false
end


function gadgetHandler:KeyRelease(key, mods, label, unicode, scanCode)
	tracy.ZoneBeginN("G:KeyRelease")
	local gList = self.KeyReleaseList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:KeyRelease:"][g])
		if (g:KeyRelease(key, mods, label, unicode, scanCode)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
return false
end


function gadgetHandler:MousePress(x, y, button)
	tracy.ZoneBeginN("G:MousePress")
	local mo = self.mouseOwner
	if (mo) then
		mo:MousePress(x, y, button)
		tracy.ZoneEnd()
		return true  --  already have an active press
	end
	local gList = self.MousePressList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:MousePress:"][g])
		if (g:MousePress(x, y, button)) then
			self.mouseOwner = g
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return false
end


function gadgetHandler:MouseMove(x, y, dx, dy, button)
	tracy.ZoneBeginN("G:MouseMove")
	local mo = self.mouseOwner
	if (mo and mo.MouseMove) then
		tracy.ZoneEnd()
		return mo:MouseMove(x, y, dx, dy, button)
	end
	tracy.ZoneEnd()
end


function gadgetHandler:MouseRelease(x, y, button)
	tracy.ZoneBeginN("G:MouseRelease")
	local mo = self.mouseOwner
	local mx, my, lmb, mmb, rmb = Spring.GetMouseState()
	if (not (lmb or mmb or rmb)) then
		self.mouseOwner = nil
	end
	if (mo and mo.MouseRelease) then
		tracy.ZoneEnd()
		return mo:MouseRelease(x, y, button)
	end
	tracy.ZoneEnd()
	return -1
end


function gadgetHandler:MouseWheel(up, value)
	tracy.ZoneBeginN("G:MouseWheel")
	local gList = self.MouseWheelList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:MouseWheel:"][g])
		if (g:MouseWheel(up, value)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return false
end


function gadgetHandler:IsAbove(x, y)
	tracy.ZoneBeginN("G:IsAbove")
	local gList = self.IsAboveList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:IsAbove:"][g])
		if (g:IsAbove(x, y)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return false
end


function gadgetHandler:GetTooltip(x, y)
	tracy.ZoneBeginN("G:GetTooltip")
	local gList = self.GetTooltipList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:IsAbove:"][g])
		if (g:IsAbove(x, y)) then
			tracy.ZoneEnd()
			tracy.ZoneBeginN(ZN["G:GetTooltip:"][g])
			local tip = g:GetTooltip(x, y)
			tracy.ZoneEnd()
			if (string.len(tip) > 0) then
				tracy.ZoneEnd()
				return tip
			end
		else
			tracy.ZoneEnd()
		end
	end
	tracy.ZoneEnd()
	return ''
end


function gadgetHandler:UnsyncedHeightMapUpdate(x1, z1, x2, z2)
	tracy.ZoneBeginN("G:UnsyncedHeightMapUpdate")
	local gList = self.UnsyncedHeightMapUpdateList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnsyncedHeightMapUpdate:"][g])
		g:UnsyncedHeightMapUpdate(x1, z1, x2, z2)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
-- OVERRIDES
--

function gadgetHandler:GetViewSizes()
--FIXME remove
return gl.GetViewSizes()	-- ours
--return self.xViewSize, self.yViewSize	-- base
end

local AllowCommand_WantedCommand = {}
local AllowCommand_WantedUnitDefID = {}


local SIZE_LIMIT = 10^8
local function AllowCommandParams(cmdParams, playerID)
	for i = 1, #cmdParams do
	-- NaN has the property that NaN ~= NaN
		if (not cmdParams[i]) or cmdParams[i] ~= cmdParams[i] or cmdParams[i] < -SIZE_LIMIT or cmdParams[i] > SIZE_LIMIT then
			Spring.Echo("Bad command from", (playerID and Spring.GetPlayerInfo(playerID)) or "unknown")
			return false
		end
	end
	return true
end

function gadgetHandler:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag, playerID, fromSynced, fromLua)
	tracy.ZoneBeginN("G:AllowCommand")
	if not AllowCommandParams(cmdParams, playerID) then
		return false
	end

	if not Script.IsEngineMinVersion(104, 0, 1431) then
		fromSynced = playerID
		playerID = nil
	end

	local gList = self.AllowCommandList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		if not AllowCommand_WantedCommand[g] then
			tracy.ZoneBeginN(ZN["G:AllowCommand_WantedCommand:"][g])
			AllowCommand_WantedCommand[g] = (g.AllowCommand_GetWantedCommand and g:AllowCommand_GetWantedCommand()) or true
			tracy.ZoneEnd()
		end
		if not AllowCommand_WantedUnitDefID[g] then
			tracy.ZoneBeginN(ZN["G:AllowCommand_WantedUnitDefID:"][g])
			AllowCommand_WantedUnitDefID[g] = (g.AllowCommand_GetWantedUnitDefID and g:AllowCommand_GetWantedUnitDefID()) or true
			tracy.ZoneEnd()
		end
		local wantedCommand = AllowCommand_WantedCommand[g]
		local wantedUnitDefID = AllowCommand_WantedUnitDefID[g]

		tracy.ZoneBeginN(ZN["G:AllowCommand:"][g])
		if ((wantedCommand == true) or wantedCommand[cmdID]) and
			((wantedUnitDefID == true) or wantedUnitDefID[unitDefID]) and
			(not g:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag, playerID, fromSynced, fromLua)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return false
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return true
end

-- ours
function gadgetHandler:RecvFromSynced(cmd,...)
	tracy.ZoneBeginN("G:RecvFromSynced")
	if (cmd == "proxy_ChatMsg") then
		gadgetHandler:GotChatMsg(...)
		tracy.ZoneEnd()
		return
	end

	if (actionHandler.RecvFromSynced(cmd, ...)) then
		tracy.ZoneEnd()
		return
	end
	local gList = self.RecvFromSyncedList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:RecvFromSynced:"][g])
		if (g:RecvFromSynced(cmd, ...)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return
		end
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:GotChatMsg(msg, player)
	tracy.ZoneBeginN("G:GotChatMsg")

	if (((player == 0) or (player == 255)) and Spring.IsCheatingEnabled()) then	-- ours
		--if ((player == 0) and Spring.IsCheatingEnabled()) then		-- base
		local sp = '^%s*'    -- start pattern
		local ep = '%s+(.*)' -- end pattern
		local s, e, match
		s, e, match = string.find(msg, sp..'togglegadget'..ep)
		if (match) then
			self:ToggleGadget(match)
			tracy.ZoneEnd()
			return true
		end
		s, e, match = string.find(msg, sp..'enablegadget'..ep)
		if (match) then
			self:EnableGadget(match)
			tracy.ZoneEnd()
			return true
		end
		s, e, match = string.find(msg, sp..'disablegadget'..ep)
		if (match) then
			self:DisableGadget(match)
			tracy.ZoneEnd()
			return false
		end
	end

	if (actionHandler.GotChatMsg(msg, player)) then
		tracy.ZoneEnd()
		return true
	end

	local gList = self.GotChatMsgList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:GotChatMsg:"][g])
		if (g:GotChatMsg(msg, player)) then
			tracy.ZoneEnd()
			tracy.ZoneEnd()
			return true
		end
		tracy.ZoneEnd()
	end

	tracy.ZoneEnd()
	return false
end


-- ours
function gadgetHandler:ViewResize(viewGeometry)
	tracy.ZoneBeginN("G:ViewResize")
	local vsx = viewGeometry.viewSizeX
	local vsy = viewGeometry.viewSizeY

	local gList = self.ViewResizeList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:ViewResize:"][g])
		g:ViewResize(vsx, vsy, viewGeometry)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
-- FIXME: NOT IN BASE VERSION
--

if Script.IsEngineMinVersion(104, 0, 1431) then

	-- opts is a bitmask
	function gadgetHandler:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdOpts, cmdParams, cmdTag, playerID, fromSynced, fromLua)
		tracy.ZoneBeginN("G:UnitCommand")
		local gList = self.UnitCommandList
		for gIdx = #gList, 1, -1 do
			local g = gList[gIdx]
			tracy.ZoneBeginN(ZN["G:UnitCommand:"][g])
			g:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdOpts, cmdParams, cmdTag, playerID, fromSynced, fromLua)
			tracy.ZoneEnd()
		end
		tracy.ZoneEnd()
		return
	end

else

	-- opts is a bitmask
	function gadgetHandler:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdOpts, cmdParams)
		tracy.ZoneBeginN("G:UnitCommand")
		local gList = self.UnitCommandList
		for gIdx = #gList, 1, -1 do
			local g = gList[gIdx]
			tracy.ZoneBeginN(ZN["G:UnitCommand:"][g])
			g:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdOpts, cmdParams)
			tracy.ZoneEnd()
		end
		tracy.ZoneEnd()
		return
	end

end

function gadgetHandler:UnitEnteredWater(unitID, unitDefID, unitTeam)
	tracy.ZoneBeginN("G:UnitEnteredWater")
	local gList = self.UnitEnteredWaterList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitEnteredWater:"][g])
		g:UnitEnteredWater(unitID, unitDefID, unitTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitEnteredAir(unitID, unitDefID, unitTeam)
	tracy.ZoneBeginN("G:UnitEnteredAir")
	local gList = self.UnitEnteredAirList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitEnteredAir:"][g])
		g:UnitEnteredAir(unitID, unitDefID, unitTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitLeftWater(unitID, unitDefID, unitTeam)
	tracy.ZoneBeginN("G:UnitLeftWater")
	local gList = self.UnitLeftWaterList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitLeftWater:"][g])
		g:UnitLeftWater(unitID, unitDefID, unitTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end


function gadgetHandler:UnitLeftAir(unitID, unitDefID, unitTeam)
	tracy.ZoneBeginN("G:UnitLeftAir")
	local gList = self.UnitLeftAirList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:UnitLeftAir:"][g])
		g:UnitLeftAir(unitID, unitDefID, unitTeam)
		tracy.ZoneEnd()
	end
	tracy.ZoneEnd()
	return
end

function gadgetHandler:GameSetup(state, ready, playerStates)
	tracy.ZoneBeginN("G:GameSetup")
	local gList = self.GameSetupList
	for gIdx = #gList, 1, -1 do
		local g = gList[gIdx]
		tracy.ZoneBeginN(ZN["G:GameSetup:"][g])
		local success, newReady = g:GameSetup(state, ready, playerStates)
		tracy.ZoneEnd()
		if (success) then
			tracy.ZoneEnd()
			return true, newReady
		end
	end
	tracy.ZoneEnd()
	return false
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

gadgetHandler:Initialize()

