--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  Copyright (C) 2007.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
  return {
    name      = "AllyCursors",
    desc      = "Shows the mouse pos of allied players",
    author    = "jK",
    date      = "May,2008",
    license   = "GNU GPL, v2 or later",
    layer     = 5,
    enabled   = true
  }
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- configs

local sendPacketEvery = 0.8
local numMousePos     = 2 --//num mouse pos in 1 packet

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- locals

local pairs = pairs

local GetMouseState   = Spring.GetMouseState
local TraceScreenRay  = Spring.TraceScreenRay
local SendLuaUIMsg    = Spring.SendLuaUIMsg
local GetGroundHeight = Spring.GetGroundHeight
local GetPlayerInfo   = Spring.GetPlayerInfo
local GetTeamColor    = Spring.GetTeamColor
local IsSphereInView  = Spring.IsSphereInView
local IsAABBInView    = Spring.IsAABBInView
local GetGroundExtremes = Spring.GetGroundExtremes
local GetSpectatingState = Spring.GetSpectatingState

local glTexCoord      = gl.TexCoord
local glVertex        = gl.Vertex
local glPolygonOffset = gl.PolygonOffset
local glDepthTest     = gl.DepthTest
local glTexture       = gl.Texture
local glColor         = gl.Color
local glBeginEnd      = gl.BeginEnd

local floor = math.floor
local tanh  = math.tanh
local GL_QUADS = GL.QUADS

local clock = os.clock

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function CubicInterpolate2(x0,x1,mix)
  local mix2 = mix*mix;
  local mix3 = mix2*mix;

  return x0*(2*mix3-3*mix2+1) + x1*(3*mix2-2*mix3);
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

WG.alliedCursorsPos = {}

--local alliedCursorsPos = WG.alliedCursorsPos

local newPos = {}
function widget:RecvLuaMsg(msg, playerID)
  if (msg:sub(1,1)=="%")
  then
    if (playerID==Spring.GetMyPlayerID()) then return true; end
    local xz = msg:sub(3)

    local l = xz:len()*0.25
    if (l==numMousePos) then
      for i=0,numMousePos-1 do
        local x = VFS.UnpackU16(xz:sub(i*4+1,i*4+2))
        local z = VFS.UnpackU16(xz:sub(i*4+3,i*4+4))
        newPos[i*2+1]   = x
        newPos[i*2+2] = z
      end

      if (WG.alliedCursorsPos[playerID]) then
        local acp = WG.alliedCursorsPos[playerID]

        acp[(numMousePos)*2+1]   = acp[1]
        acp[(numMousePos)*2+2]   = acp[2]

        for i=0,numMousePos-1 do
          acp[i*2+1] = newPos[i*2+1]
          acp[i*2+2] = newPos[i*2+2]
        end

        acp[(numMousePos+1)*2+1] = clock()
        acp[(numMousePos+1)*2+2] = (msg:sub(2,2)=="1")
      else
        local acp = {}
        WG.alliedCursorsPos[playerID] = acp

        for i=0,numMousePos-1 do
          acp[i*2+1] = newPos[i*2+1]
          acp[i*2+2] = newPos[i*2+2]
        end

        acp[(numMousePos)*2+1]   = newPos[(numMousePos-2)*2+1]
        acp[(numMousePos)*2+2]   = newPos[(numMousePos-2)*2+2]

        acp[(numMousePos+1)*2+1] = clock()
        acp[(numMousePos+1)*2+2] = (msg:sub(2,2)=="1")
        _,_,_,acp[(numMousePos+1)*2+3] = GetPlayerInfo(playerID, false)
      end
    end
    return true
  end
end

--------------------------------------------------------------------------------

local updateTimer = 0
local poshistory = {}

local saveEach = sendPacketEvery/numMousePos

local n = 0

function widget:Update(t)
  updateTimer = updateTimer + t

  if (updateTimer%saveEach<0.2) then
    local mx,my = GetMouseState()
    local _,pos = TraceScreenRay(mx,my,true)

    if (pos~=nil) then
      poshistory[n*2]   = VFS.PackU16(floor(pos[1]))
      poshistory[n*2+1] = VFS.PackU16(floor(pos[3]))
    end

    n = n + 1
  end

  if (updateTimer>sendPacketEvery)and(n>=numMousePos) then
    updateTimer = 0
    n=0

    local posStr = "0"
    local _,_,l,m,r = Spring.GetMouseState()
    if (l or r) then posStr = "1" end
    for i=numMousePos,1,-1 do
      local xStr = poshistory[i*2]
      local zStr = poshistory[i*2+1]
      if (xStr and zStr) then posStr = posStr .. xStr .. zStr end
    end

    SendLuaUIMsg("%" .. posStr,"allies")
  end

  if (GetSpectatingState()) then
    widgetHandler:RemoveCallIn("Update")
    return
  end
end

-- Ground heights around the last drawn quad. Consecutive trail samples of an idle cursor share
-- one position, so they are reused within a frame (reset in DrawWorldPreUnit).
local quadX, quadZ
local gy_tl,gy_tr,gy_bl,gy_br,gy_t,gy_b,gy_l,gy_r

local function DrawGroundquad(wx,gy,wz)
  -- get ground heights
  if (wx ~= quadX) or (wz ~= quadZ) then
    quadX, quadZ = wx, wz
    gy_tl,gy_tr = GetGroundHeight(wx-16,wz-16),GetGroundHeight(wx+16,wz-16)
    gy_bl,gy_br = GetGroundHeight(wx-16,wz+16),GetGroundHeight(wx+16,wz+16)
    gy_t,gy_b = GetGroundHeight(wx,wz-16),GetGroundHeight(wx,wz+16)
    gy_l,gy_r = GetGroundHeight(wx-16,wz),GetGroundHeight(wx+16,wz)
  end

  --topleft
  glTexCoord(0,0)
  glVertex(wx-16,gy_bl,wz-16)
  glTexCoord(0,0.5)
  glVertex(wx-16,gy_l,wz)
  glTexCoord(0.5,0.5)
  glVertex(wx,gy,wz)
  glTexCoord(0.5,0)
  glVertex(wx,gy_t,wz-16)

  --topright
  glTexCoord(0.5,0)
  glVertex(wx,gy_t,wz-16)
  glTexCoord(0.5,0.5)
  glVertex(wx,gy,wz)
  glTexCoord(1,0.5)
  glVertex(wx+16,gy_r,wz)
  glTexCoord(1,0)
  glVertex(wx+16,gy_tr,wz-16)

  --bottomright
  glTexCoord(0.5,0.5)
  glVertex(wx,gy,wz)
  glTexCoord(0.5,1)
  glVertex(wx,gy_b,wz+16)
  glTexCoord(1,1)
  glVertex(wx+16,gy_br,wz+16)
  glTexCoord(1,0.5)
  glVertex(wx+16,gy_r,wz)

  --bottomleft
  glTexCoord(0.5,0)
  glVertex(wx-16,gy_l,wz)
  glTexCoord(1,0)
  glVertex(wx-16,gy_bl,wz+16)
  glTexCoord(1,0.5)
  glVertex(wx,gy_b,wz+16)
  glTexCoord(0.5,0.5)
  glVertex(wx,gy,wz)
end


local teamColors = {}
local function SetTeamColor(teamID,a)
  local color = teamColors[teamID]
  if (color) then
    color[4]=a
    glColor(color)
    return
  end
  local r, g, b = Spring.GetTeamColor(teamID)
  if (r and g and b) then
    color = { r, g, b }
    teamColors[teamID] = color
    glColor(color)
    return
  end
end


--------------------------------------------------------------------------------
-- Skip a cursor whose whole trail is off screen with one box test instead of up to 6
-- interpolations, height reads and sphere tests. The trail of an interpolating cursor lies between its stored points
-- (the cubic blend weights are in [0,1]), so a box around them, padded by more than the
-- sample spheres' radius (16) and spanning every height the ground has had, contains every
-- sample sphere; if the engine finds the box out of view, it finds each sample sphere out of
-- view as well (both are tests against the same frustum planes). The only assumption is the
-- height range: the engine's current extremes lag terraforming by up to ~2 s, which the
-- margin covers.
local CULL_PAD = 24             -- > 16 (sample sphere radius) plus float slack
local CULL_HEIGHT_MARGIN = 300  -- terraform progress the engine extremes may not show yet
local cullOn = (IsAABBInView ~= nil)
local heightLo, heightHi -- per drawn frame; envelope of the ground extremes
local envLo, envHi = math.huge, -math.huge

local function UpdateHeightRange()
  local initMin, initMax, currMin, currMax = GetGroundExtremes()
  local lo = math.min(initMin or 0, currMin or 0)
  local hi = math.max(initMax or 0, currMax or 0)
  if lo < envLo then envLo = lo end
  if hi > envHi then envHi = hi end
  heightLo = envLo - CULL_HEIGHT_MARGIN - CULL_PAD
  heightHi = envHi + CULL_HEIGHT_MARGIN + CULL_PAD
end

-- base = time since the cursor's last packet (>= 0, < sendPacketEvery).
-- Samples use data[1..2*numMousePos+2] (points 0..numMousePos).
local function TrailMayBeInView(data)
  local minx, minz = data[1], data[2]
  local maxx, maxz = minx, minz
  for i = 3, 2*numMousePos + 1, 2 do
    local x, z = data[i], data[i + 1]
    if x < minx then minx = x elseif x > maxx then maxx = x end
    if z < minz then minz = z elseif z > maxz then maxz = z end
  end
  if not heightLo then
    UpdateHeightRange()
  end
  return IsAABBInView(minx - CULL_PAD, heightLo, minz - CULL_PAD, maxx + CULL_PAD, heightHi, maxz + CULL_PAD)
end

-- Emits every cursor quad inside one glBeginEnd; colours are set per quad as before.
-- Same samples, values (same arithmetic in the same order) and calls as the original loop:
-- per cursor the constant table reads are hoisted, the cubic blend is inlined (its weights are
-- shared by x and z), and an idle cursor (all 6 samples at its last position) is handled with
-- one position.
local function DrawCursorQuads(time)
  local cull = cullOn
  heightLo = nil
  for playerID,data in pairs(WG.alliedCursorsPos) do
    local dataLen = #data
    local teamID = data[dataLen]
    local pressed = data[dataLen-1] --mouse pressed?
    local base = time-data[dataLen-2]
    if (base >= sendPacketEvery) then
      -- idle: lastUpdatedDiff = base + n*0.025 >= sendPacketEvery for every n
      local wx,wz = data[1],data[2]
      local gy = GetGroundHeight(wx,wz)
      if IsSphereInView(wx,gy,wz,16) then
        for n=0,5 do
          if (pressed) then
            glColor(1,0,0,n*0.2)
          else
            SetTeamColor(teamID,n*0.2)
          end
          DrawGroundquad(wx,gy,wz)
        end
      end
    elseif not (cull and base >= 0 and not TrailMayBeInView(data)) then
      local lastX, lastZ, gy, inView
      for n=0,5 do
        local wx,wz = data[1],data[2]
        local lastUpdatedDiff = base + n*0.025

        if (lastUpdatedDiff<sendPacketEvery) then
          local scale  = (1-(lastUpdatedDiff/sendPacketEvery))*numMousePos
          local iscale = floor(scale)
          if iscale > numMousePos-1 then iscale = numMousePos-1 end -- math.min
          local mix = scale-iscale
          -- CubicInterpolate2(x0,x1,mix)
          local mix2 = mix*mix
          local mix3 = mix2*mix
          local w0, w1 = (2*mix3-3*mix2+1), (3*mix2-2*mix3)
          local i = iscale*2
          wx = data[i+1]*w0 + data[i+3]*w1
          wz = data[i+2]*w0 + data[i+4]*w1
        end

        if (wx ~= lastX) or (wz ~= lastZ) then
          lastX, lastZ = wx, wz
          gy = GetGroundHeight(wx,wz)
          inView = IsSphereInView(wx,gy,wz,16)
        end
        if (inView) then
          if (pressed) then
            glColor(1,0,0,n*0.2)
          else
            SetTeamColor(teamID,n*0.2)
          end
          DrawGroundquad(wx,gy,wz)
        end
      end
    end
  end
end

function widget:DrawWorldPreUnit()
  if Spring.IsGUIHidden() then return end
  glDepthTest(true)
  glTexture('LuaUI/Images/AlliedCursors.png')
  glPolygonOffset(-7,-10)
  quadX, quadZ = nil, nil -- terrain may have changed since the last frame

  glBeginEnd(GL_QUADS, DrawCursorQuads, clock())

  glPolygonOffset(false)
  glTexture(false)
  glDepthTest(false)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
