-- $Id$
function widget:GetInfo()
  return {
    name      = "Show All Commands v2",
    desc      = "Populates the 'Settings/Interface/Command Visibility' option set",
    author    = "Google Frog, msafwan",
    date      = "Mar 1, 2009, July 1 2013",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true  --  loaded by default?
  }
end
--Changelog:
--July 1 2013 (msafwan add chili radiobutton and new options!)
--NOTE: this options will behave correctly if "alwaysDrawQueue == 0" in cmdcolors.txt

local spDrawUnitCommands      = Spring.DrawUnitCommands
local spGetAllUnits           = Spring.GetAllUnits
local spIsGUIHidden           = Spring.IsGUIHidden
local spGetModKeyState        = Spring.GetModKeyState
local spGetUnitAllyTeam       = Spring.GetUnitAllyTeam
local spGetSelectedUnits      = Spring.GetSelectedUnits
local spGetUnitPosition       = Spring.GetUnitPosition
local spGetUnitRulesParam     = Spring.GetUnitRulesParam
local spGetUnitTeam           = Spring.GetUnitTeam
local spGetUnitCurrentCommand = Spring.GetUnitCurrentCommand

local glVertex      = gl.Vertex
local glPushAttrib  = gl.PushAttrib
local glLineStipple = gl.LineStipple
local glDepthTest   = gl.DepthTest
local glLineWidth   = gl.LineWidth
local glColor       = gl.Color
local glBeginEnd    = gl.BeginEnd
local glPopAttrib   = gl.PopAttrib
local GL_LINES      = GL.LINES

-- Constans
local TARGET_NONE = 0
local TARGET_GROUND = 1
local TARGET_UNIT= 2

local CMD_ATTACK = CMD.ATTACK
local setTargetAlpha = math.min(0.5, (tonumber(Spring.GetConfigString("CmdAlpha") or "0.7") or 0.7))

local selectedUnitCount = 0
local selectedUnits

local drawUnit = {count = 0, data = {}}
local drawUnitID = {}

local setTargetUnit = {}

local commandLevel = 1 --default at start of widget is to be disabled!

local spectating = Spring.GetSpectatingState()
local myAllyTeamID = Spring.GetLocalAllyTeamID()
local myTeamID = Spring.GetMyTeamID()
local myPlayerID = Spring.GetLocalPlayerID()

local gaiaTeamID = Spring.GetGaiaTeamID()

local setTargetUnitDefIDs = {}
for i = 1, #UnitDefs do
	local ud = UnitDefs[i]
	if ((not (ud.canFly and ((ud.isBomber or ud.isBomberAirUnit) and not ud.customParams.can_set_target))) and
			ud.canAttack and ud.canMove and ud.maxWeaponRange and ud.maxWeaponRange > 0) or ud.isFactory then
		setTargetUnitDefIDs[i] = true
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local function UpdateSelection(newSelectedUnits)
	selectedUnitCount = #newSelectedUnits
	selectedUnits = newSelectedUnits
end


options_path = 'Settings/Interface/Command Visibility'
options_order = {
'showallcommandselection','lbl_filters','includeallies', 'includealliesunits', 'includeneutral'
}
options = {
	showallcommandselection = {
		type='radioButton',
		name='Commands are drawn for',
		items = {
			{name = 'All units',key='showallcommand', desc="Command always drawn on all units.", hotkey=nil},
			{name = 'Selected units, All with SHIFT',key='onlyselection', desc="Command always drawn on selected unit, pressing SHIFT will draw it for all units.", hotkey=nil},
			{name = 'Selected units',key='onlyselectionlow', desc="Command always drawn on selected unit.", hotkey=nil},
			{name = 'All units with SHIFT',key='showallonshift', desc="Commands always hidden, but pressing SHIFT will draw it for all units.", hotkey=nil},
			{name = 'Selected units on SHIFT',key='showminimal', desc="Commands always hidden, pressing SHIFT will draw it on selected units.", hotkey=nil},
		},
		value = 'onlyselection',  --default at start of widget
		OnChange = function(self)
			local key = self.value
			if key == 'showallcommand' then
				commandLevel = 5
			elseif key == 'onlyselection' then
				commandLevel = 4
				UpdateSelection(spGetSelectedUnits())
			elseif key == 'onlyselectionlow' then
				commandLevel = 3
				UpdateSelection(spGetSelectedUnits())
			elseif key == 'showallonshift' then
				commandLevel = 2
				UpdateSelection(spGetSelectedUnits())
			elseif key == 'showminimal' then
				commandLevel = 1
				UpdateSelection(spGetSelectedUnits())
			end
			
			if key == 'showminimal' or key == 'showallonshift' then
				Spring.LoadCmdColorsConfig("alwaysDrawQueue 0")
			else
				Spring.LoadCmdColorsConfig("alwaysDrawQueue 1")
			end
		end,
	},
	lbl_filters = {name='Filters', type='label'},
	includeallies = {
		name = 'Include ally selections',
		desc = 'When showing commands for selected units, show them for both your own and your allies\' selections.',
		type = 'bool',
		value = false,
	},
	includealliesunits = {
		name = 'Include ally units',
		desc = 'When showing commands, show them for both your own and your allies units.',
		type = 'bool',
		value = true,
		OnChange = function(self)
			PoolUnit()
		end,
	},
	includeneutral = {
		name = 'Include Neutral Units',
		desc = 'Toggle whether to show commands for neutral units (relevant while spectating).',
		type = 'bool',
		value = true,
		OnChange = function(self)
			PoolUnit()
		end,
	},
}

do options.showallcommandselection.OnChange(options.showallcommandselection) end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Unit Handling
local function AddUnit(unitID)
	if not drawUnitID[unitID] then
		if spectating or spGetUnitAllyTeam(unitID) == myAllyTeamID then
			local list = drawUnit
			list.count = list.count + 1
			list.data[list.count] = unitID
			drawUnitID[unitID] = list.count
			
			local unitDefID = Spring.GetUnitDefID(unitID)
			setTargetUnit[unitID] = unitDefID and setTargetUnitDefIDs[unitDefID]
		end
	end
end

local function RemoveUnit(unitID)
	if drawUnitID[unitID] then
		local index = drawUnitID[unitID]
		local list = drawUnit
		list.data[index] = list.data[list.count]
		drawUnitID[list.data[index]] = index
		list.data[list.count] = nil
		list.count = list.count - 1
		drawUnitID[unitID] = nil
	end
end

function PoolUnit()
	local units = spGetAllUnits()
	for _, unitID in ipairs(units) do
		local teamID = spGetUnitTeam(unitID)
		if (options.includeneutral.value or teamID ~= gaiaTeamID) and (teamID == myTeamID or options.includealliesunits.value) then
			AddUnit(unitID)
		else
			RemoveUnit(unitID)
		end
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Drawing

-- Set-target lines recorded by Update and drawn by DrawWorld, 7 entries per line:
-- x1, y1, z1, x2, y2, z2, color index.
local lineColors = {
	{1, 0.8, 0, setTargetAlpha},
	{1, 1, 0, setTargetAlpha},
}
local lineData = {}
local lineCount = 0

local function AddLine(colorIndex, x1, y1, z1, x2, y2, z2)
	local i = lineCount*7
	lineData[i + 1] = x1
	lineData[i + 2] = y1
	lineData[i + 3] = z1
	lineData[i + 4] = x2
	lineData[i + 5] = y2
	lineData[i + 6] = z2
	lineData[i + 7] = colorIndex
	lineCount = lineCount + 1
end

local function GetDrawLevel()
	local ahiftHeld = select(4,spGetModKeyState())
	if commandLevel == 1 then
		return ahiftHeld, false
	elseif commandLevel == 2 then
		return false, ahiftHeld
	elseif commandLevel == 3 then
		return true, false
	elseif commandLevel == 4 then
		return true, ahiftHeld
	else -- commandLevel == 5
		return true, true
	end
end

local function getTargetPosition(unitID)
	if not setTargetUnit[unitID] then
		return nil
	end
	local target_type = spGetUnitRulesParam(unitID,"target_type") or TARGET_NONE
	local fireTowards = spGetUnitRulesParam(unitID,"target_towards")
	if fireTowards == 0 then
		fireTowards = false
	end
	
	local tx, ty, tz
	
	if target_type == TARGET_GROUND then
		tx = spGetUnitRulesParam(unitID, "target_x")
		ty = spGetUnitRulesParam(unitID, "target_y")
		tz = spGetUnitRulesParam(unitID, "target_z")
	elseif target_type == TARGET_UNIT then
		local targetID = spGetUnitRulesParam(unitID, "target_id")
		local cmdID, cmdOpts, _, cmdParam1, cmdParam2 = spGetUnitCurrentCommand(unitID)
		if cmdID == CMD_ATTACK and cmdParam1 == targetID and not cmdParam2 then
			-- Do not draw set target and attack on the same target.
			return nil
		end
		if targetID and targetID ~= 0 and Spring.ValidUnitID(targetID) then
			_, _, _, tx, ty, tz = spGetUnitPosition(targetID, true)
		else
			return nil
		end
	else
		return nil
	end
	return tx, ty, tz, fireTowards
end

local function collectUnitCommands(unitID)
	if not unitID then
		return
	end
	
	local tx,ty,tz,fireTowards = getTargetPosition(unitID)
	if tx then
		local _,_,_,x,y,z = spGetUnitPosition(unitID,true)
		if fireTowards then
			local dist = math.sqrt((x - tx)^2 + (y - ty)^2 + (z - tz)^2)
			if dist < fireTowards then
				AddLine(1, x, y, z, tx, ty, tz)
			else
				local mult = fireTowards / dist
				local mx, my, mz = (tx - x)*mult + x, (ty - y)*mult + y, (tz - z)*mult + z
				AddLine(1, x, y, z, mx, my, mz)
				AddLine(2, tx, ty, tz, mx, my, mz)
			end
		else
			AddLine(1, x, y, z, tx, ty, tz)
		end
	end
end

local function updateDrawing()
	local drawSelected, drawAll = GetDrawLevel()
	if drawAll then
		local count = drawUnit.count
		local units = drawUnit.data
		for i = 1, count do
			collectUnitCommands(units[i])
		end
		spDrawUnitCommands(units)
	elseif drawSelected then
		local sel = selectedUnits
		local alreadyDrawn = {}
		local toDraw = {}
		for i = 1, selectedUnitCount do
			if sel[i] then
				collectUnitCommands(sel[i])
				alreadyDrawn[sel[i]] = true
				toDraw[#toDraw + 1] = sel[i]
			end
		end
		if options.includeallies.value then
			local count = drawUnit.count
			local units = drawUnit.data
			for i = 1, count do
				local unitID = units[i]
				if unitID and WG.allySelUnits[unitID] and not alreadyDrawn[sel[i]] then
					collectUnitCommands(unitID)
					alreadyDrawn[unitID] = true
					toDraw[#toDraw + 1] = unitID
				end
			end
		end
		if #toDraw > 0 then
			spDrawUnitCommands(toDraw)
		end
	end
end

function widget:Update()
	lineCount = 0
	if not spIsGUIHidden() then
		-- Must stay in Update: Spring.DrawUnitCommands only queues units for the engine's command
		-- drawer. The set-target lines are recorded here and drawn by DrawWorld instead of being
		-- compiled into (and deleted from) a display list every frame. pcall like gl.CreateList: an
		-- error (e.g. WG.allySelUnits missing) is logged and draws nothing instead of removing the widget.
		local ok, err = pcall(updateDrawing)
		if not ok then
			lineCount = 0
			Spring.Log(widget:GetInfo().name, LOG.ERROR, err)
		end
	end
end

local function DrawCollectedLines()
	local data = lineData
	for i = 0, (lineCount - 1)*7, 7 do
		local col = lineColors[data[i + 7]]
		glColor(col[1], col[2], col[3], col[4])
		glVertex(data[i + 1], data[i + 2], data[i + 3])
		glVertex(data[i + 4], data[i + 5], data[i + 6])
	end
end

function widget:DrawWorld()
	if lineCount > 0 then
		-- GL.LINE_BITS does not exist (GL.LINE_BIT does), so this pushes GL.ALL_ATTRIB_BITS and the
		-- pop restores the depth test and current color too: the block is state-neutral, so it is
		-- skipped when there are no lines.
		glPushAttrib(GL.LINE_BITS)
		gl.LineStipple("springdefault")
		glDepthTest(false)
		glLineWidth(1)
		-- One GL_LINES batch: the stipple counter restarts at every independent segment, exactly as
		-- with one glBegin/glEnd per segment, and glColor is legal between glBegin and glEnd.
		glBeginEnd(GL_LINES, DrawCollectedLines)
		glColor(1, 1, 1, 1)
		glLineStipple(false)
		glPopAttrib()
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Callins
function widget:SelectionChanged(newSelection)
	if commandLevel ~= 5 then
		UpdateSelection(newSelection)
	end
end

function widget:PlayerChanged(playerID)
	if myPlayerID == playerID then
		spectating = Spring.GetSpectatingState()
		myAllyTeamID = Spring.GetLocalAllyTeamID()
		myTeamID = Spring.GetMyTeamID()
		PoolUnit()
	end
end

function widget:UnitCreated(unitID, unitDefID, teamID)
	if (options.includeneutral.value or teamID ~= gaiaTeamID) and (teamID == myTeamID or options.includealliesunits.value) then
		AddUnit(unitID)
	end
end

function widget:UnitGiven(unitID, unitDefID, newTeamID, oldTeamID)
	if (options.includeneutral.value or newTeamID ~= gaiaTeamID) and (newTeamID == myTeamID or options.includealliesunits.value) then
		AddUnit(unitID)
	else
		RemoveUnit(unitID)
	end
end

function widget:UnitDestroyed(unitID)
	RemoveUnit(unitID)
end

function widget:GameFrame(n)
	if (n > 0) then
		PoolUnit()
		widgetHandler:RemoveCallIn("GameFrame")
	end
end
