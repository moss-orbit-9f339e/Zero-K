--//=============================================================================
--// RenderCache  (option "Cache Interface Windows" of the Chili Framework
--// widget, Settings/HUD Panels/Extras; default off)
--//
--// Old chili draws every child of the screen (windows, panels) each frame by
--// calling its display list, which records the whole subtree: hundreds of
--// small draws, text shader binds, scissor and matrix changes that the GL
--// driver replays every frame. The render cache draws such a control once
--// into a texture and then puts that texture on screen with a single quad per
--// frame, until the control changes.
--//
--// Change detection: every change inside a subtree ends in _UpdateAllDList()
--// of its top-level control (that is how old chili keeps its display lists
--// current), which increments _redrawCounter. The cache is redrawn when the
--// counter, the control's pixel box, the ui scale or the view size changed.
--// Content that can change without that (textures named "$..." / "!..." shown
--// by an Image) makes the top-level control uncacheable (MarkDynamic).
--//
--// Blending: the texture is cleared to (0,0,0,1) and drawn into with
--//   rgb: SRC_ALPHA, ONE_MINUS_SRC_ALPHA     alpha: ZERO, ONE_MINUS_SRC_ALPHA
--// so rgb holds the premultiplied UI colour C and alpha the transmittance T
--// (product of (1-a) over all layers); text uses this blending too (fonts are
--// begun with userDefinedBlending, see BeginFont in font.lua). Drawing the
--// texture with blend ONE, SRC_ALPHA yields C + dst*T, which equals drawing
--// the layers onto dst with standard alpha blending (up to 8 bit rounding).
--//
--// Rasterisation: the texture covers an integer pixel box of the view and is
--// rendered with the screen's own projection and modelview and a viewport
--// shifted by the box origin; scissor rects are shifted by the same integer
--// offset (SetScissorOffset in util.lua). So every primitive covers the same
--// pixels/samples as on screen. The texture is rendered multisampled (same
--// sample count as the screen framebuffer) and resolved before use, and is
--// drawn 1:1 with nearest filtering.
--//
--// Controls that change (nearly) every frame ("hot", e.g. a tooltip that
--// follows the cursor) are drawn directly, as before.
--//=============================================================================

RenderCache = {}

--//=============================================================================
--// tweaking

local MARGIN     = 2            --// pixels around the control's box
local MAX_DIM    = 2048         --// larger controls are drawn directly
local MAX_AREA   = 1600 * 1000
local EMA_KEEP   = 0.85         --// change-rate filter
local HOT_ENTER  = 0.6
local HOT_LEAVE  = 0.25
local UNUSED_FRAMES = 300       --// free textures of controls not drawn for that long

local GL_SAMPLES = 0x80A9

--//=============================================================================

local floor, ceil, max = math.floor, math.ceil, math.max
local next, pairs = next, pairs

local glPushMatrix  = gl.PushMatrix
local glPopMatrix   = gl.PopMatrix
local glTranslate   = gl.Translate
local glScale       = gl.Scale
local glColor       = gl.Color
local glTexture     = gl.Texture
local glTexRect     = gl.TexRect
local glBlendFunc   = gl.BlendFunc
local glBlendFuncSeparate = gl.BlendFuncSeparate

local GL_ONE       = GL.ONE
local GL_ZERO      = GL.ZERO
local GL_SRC_ALPHA = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA
local GL_COLOR_BUFFER_BIT = GL.COLOR_BUFFER_BIT
local GL_NEAREST   = GL.NEAREST

local available = (gl.CreateFBO and gl.DeleteFBO and gl.IsValidFBO and gl.ActiveFBO and gl.BlitFBO
	and gl.CreateRBO and gl.DeleteRBO and gl.CreateTexture and gl.DeleteTexture
	and gl.BlendFuncSeparate and gl.Viewport and gl.GetNumber and true) or false

local texParams = {
	border     = false,
	min_filter = GL_NEAREST,
	mag_filter = GL_NEAREST,
	wrap_s     = GL.CLAMP_TO_EDGE,
	wrap_t     = GL.CLAMP_TO_EDGE,
}

--//=============================================================================
--// cache records

local records  = {}                                  --// all records (owns the GL objects)
local recordOf = setmetatable({}, {__mode = "k"})    --// control -> record
local weakValues = {__mode = "v"}

local frame = 0
local generation = 1

--// shared multisampled render target
local msFbo, msRbo
local msW, msH, msSamples = 0, 0, 0
local msFailed = false   --// sample count for which no matching target could be made

--// per frame
local frameOK = false
local fbSamples = 0          --// sample count of the framebuffer chili draws into
local fbSamplesFrame = -1    --// frame in which it was queried
local fontsFlushed = false

local function FreeRecordGL(rec)
	if rec.fbo then
		gl.DeleteFBO(rec.fbo)
		rec.fbo = nil
	end
	if rec.tex then
		gl.DeleteTexture(rec.tex)
		rec.tex = nil
	end
	rec.tw, rec.th = 0, 0
	rec.valid = false
end

local function FreeMS()
	if msFbo then
		gl.DeleteFBO(msFbo)
		msFbo = nil
	end
	if msRbo then
		gl.DeleteRBO(msRbo)
		msRbo = nil
	end
	msW, msH, msSamples = 0, 0, 0
end

local function NewRecord(c)
	local rec = {
		ref = setmetatable({c}, weakValues),
		ema = 0,
		hot = false,
		valid = false,
		tw = 0, th = 0,
		lastUsed = frame,
	}
	records[#records + 1] = rec
	recordOf[c] = rec
	return rec
end

function RenderCache.Free(c)
	c = UnlinkSafe(c)
	local rec = c and recordOf[c]
	if rec then
		FreeRecordGL(rec)
		rec.dead = true
		recordOf[c] = nil
	end
end

function RenderCache.FreeAll()
	for i = 1, #records do
		FreeRecordGL(records[i])
		records[i].dead = true
	end
	records = {}
	for c in pairs(recordOf) do
		recordOf[c] = nil
	end
	FreeMS()
	msFailed = false
	generation = generation + 1
end

local function Sweep()
	local n = #records
	local i = 1
	while (i <= n) do
		local rec = records[i]
		local c = rec.ref[1]
		if rec.dead or (not c) or (frame - rec.lastUsed > UNUSED_FRAMES) then
			FreeRecordGL(rec)
			if c and (recordOf[c] == rec) then
				recordOf[c] = nil
			end
			records[i] = records[n]
			records[n] = nil
			n = n - 1
		else
			i = i + 1
		end
	end
end

--//=============================================================================
--// render targets

local function EnsureTexture(rec, w, h)
	if rec.tex and (w <= rec.tw) and (h <= rec.th) and (4 * w * h >= rec.tw * rec.th) then
		return true
	end
	FreeRecordGL(rec)
	local tw = ceil(w / 32) * 32
	local th = ceil(h / 32) * 32
	local tex = gl.CreateTexture(tw, th, texParams)
	if not tex then
		return false
	end
	local fbo = gl.CreateFBO({color0 = tex})
	if (not fbo) or (not gl.IsValidFBO(fbo)) then
		if fbo then
			gl.DeleteFBO(fbo)
		end
		gl.DeleteTexture(tex)
		return false
	end
	rec.tex, rec.fbo, rec.tw, rec.th = tex, fbo, tw, th
	return true
end

local function EnsureMSTarget(w, h)
	if msFbo and (w <= msW) and (h <= msH) and (msSamples == fbSamples) then
		return true
	end
	local nw = max(msW, ceil(w / 128) * 128)
	local nh = max(msH, ceil(h / 128) * 128)
	FreeMS()
	msRbo = gl.CreateRBO(nw, nh, {format = GL.RGBA8, samples = fbSamples})
	if msRbo then
		msSamples = msRbo.samples or 0
		msFbo = gl.CreateFBO({color0 = msRbo})
	end
	if (not msFbo) or (not gl.IsValidFBO(msFbo)) or (msSamples ~= fbSamples) then
		FreeMS()
		msFailed = fbSamples
		return false
	end
	msW, msH = nw, nh
	return true
end

--//=============================================================================
--// which top-level controls draw only inside their own box

local safeDraw

local function BuildSafeDraw()
	safeDraw = {}
	local function Add(f)
		if f then
			safeDraw[f] = true
		end
	end
	local envs = {getfenv(1)}
	if SkinHandler and SkinHandler.utilsEnv then
		envs[2] = SkinHandler.utilsEnv
	end
	for i = 1, #envs do
		local env = envs[i]
		Add(rawget(env, "DrawWindow"))
		Add(rawget(env, "DrawPanel"))
		Add(rawget(env, "DrawScrollPanel"))
		Add(rawget(env, "DrawScrollPanelBorder"))
		Add(rawget(env, "DrawResizeGrip"))
		Add(rawget(env, "DrawDragGrip"))
	end
	Add(Control.DrawControl)
	Add(Control.DrawResizeGrip)
	Add(Control.DrawDragGrip)
	Add(Window.DrawControl)
	Add(ScrollPanel.DrawControl)
	Add(Image.DrawControl)
end

local function DrawsInsideBox(c)
	if not safeDraw then
		BuildSafeDraw()
	end
	if (not c.safeOpengl) or (not c.useDList) or c._rcDynamic or c.snapToGrid then
		return false
	end
	if (c.DrawForList ~= Control.DrawForList) or (c.Draw ~= Control.Draw) or (c.DrawGrips ~= Control.DrawGrips) then
		return false
	end
	if (c.DrawChildrenForList ~= Control.DrawChildrenForList) then
		return false
	end
	local dica = c._DrawInClientArea
	if (dica ~= Control._DrawInClientArea) and (dica ~= ScrollPanel._DrawInClientArea) then
		return false
	end
	local dc = c.DrawControl
	if not safeDraw[dc] then
		return false
	end
	if (dc == Control.DrawControl) and ((c.DrawBackground ~= Control.DrawBackground) or (c.DrawBorder ~= Control.DrawBorder)) then
		return false
	end
	local post = c.DrawControlPostChildren
	if post and (not safeDraw[post]) then
		return false
	end
	if c.resizable and (not safeDraw[c.DrawResizeGrip]) then
		return false
	end
	if c.draggable and c.dragUseGrip and (not safeDraw[c.DrawDragGrip]) then
		return false
	end
	--// window captions are centered on the window and may be wider than it
	if c.caption and (not c.noFont) and c.font and c.font.GetTextWidth then
		if c.font:GetTextWidth(tostring(c.caption)) > c.width then
			return false
		end
	end
	return true
end

--// Images showing engine ("$...") or Lua ("!...") textures may change
--// without any invalidation; the control holding them is drawn directly.
function RenderCache.IsDynamicTexture(file)
	if not file then
		return false
	end
	local b = file:byte(1)
	return (b == 36) or (b == 33) --// '$' or '!'
end

function RenderCache.MarkDynamic(obj)
	local c = UnlinkSafe(obj)
	while c do
		local p = UnlinkSafe(c.parent)
		if (not p) or (not p._UpdateAllDList) then
			break
		end
		c = p
	end
	if c then
		c._rcDynamic = true
	end
end

--//=============================================================================
--// rendering into a cache texture

local function RenderInto(c, ox, oy, vsx, vsy)
	gl.Viewport(-ox, -oy, vsx, vsy)
	gl.Scissor(false)
	gl.Clear(GL_COLOR_BUFFER_BIT, 0, 0, 0, 1)
	glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ZERO, GL_ONE_MINUS_SRC_ALPHA)
	glColor(1, 1, 1, 1)
	SetScissorOffset(ox, oy)
	SafeCall(c.DrawForList, c)
	SetScissorOffset(0, 0)
	gl.Scissor(false)
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
end

local function RenderRecord(c, rec, ox, oy, w, h, vsx, vsy, s)
	if (fbSamplesFrame ~= frame) then
		--// glGet only in frames that render something
		fbSamplesFrame = frame
		fbSamples = gl.GetNumber(GL_SAMPLES) or 0
	end
	local multisampled = (fbSamples > 1)
	if multisampled and ((msFailed == fbSamples) or (not EnsureMSTarget(w, h))) then
		return false
	end
	if not EnsureTexture(rec, w, h) then
		return false
	end
	local target = multisampled and msFbo or rec.fbo
	if not fontsFlushed then
		fontsFlushed = true
		FontHandler.FlushPendingUploads()
	end

	glPushMatrix()
	glTranslate(0, vsy, 0)
	glScale(1, -1, 1)
	glScale(s, s, 1)
	gl.ActiveFBO(target, RenderInto, c, ox, oy, vsx, vsy)
	glPopMatrix()

	if (target ~= rec.fbo) then
		gl.BlitFBO(msFbo, 0, 0, w, h, rec.fbo, 0, 0, w, h, GL_COLOR_BUFFER_BIT, GL_NEAREST)
	end
	return true
end

--//=============================================================================
--// drawing the screen

local STATE_NONE, STATE_DIRECT, STATE_COMPOSITE = 0, 1, 2
local state = STATE_NONE
local curVsy, curScale = 0, 1

local function EnterDirect()
	if (state == STATE_DIRECT) then
		return
	end
	if (state == STATE_COMPOSITE) then
		glTexture(0, false)
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	end
	glColor(1, 1, 1, 1)
	glPushMatrix()
	glTranslate(0, curVsy, 0)
	glScale(1, -1, 1)
	glScale(curScale, curScale, 1)
	state = STATE_DIRECT
end

local function EnterComposite()
	if (state == STATE_COMPOSITE) then
		return
	end
	if (state == STATE_DIRECT) then
		glPopMatrix()
	end
	glBlendFuncSeparate(GL_ONE, GL_SRC_ALPHA, GL_ZERO, GL_ONE)
	glColor(1, 1, 1, 1)
	state = STATE_COMPOSITE
end

local function LeaveAll()
	if (state == STATE_DIRECT) then
		glPopMatrix()
	elseif (state == STATE_COMPOSITE) then
		glTexture(0, false)
	end
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	state = STATE_NONE
end

local ControlDraw

local function DrawDirect(c, rec)
	EnterDirect()
	if rec and rec.hot and c._allDListDirty and (c.Draw == ControlDraw) then
		--// changing (nearly) every frame: draw it immediately instead of
		--// compiling a display list that would be called only once
		--// (same commands as the list Draw() would compile and call)
		SafeCall(c.DrawForList, c)
	else
		SafeCall(c.Draw, c)
	end
end

local function DrawChild(c, vsx, vsy, s)
	local counter = c._redrawCounter
	if (not frameOK) or (not counter) or (not c.DrawForList) then
		DrawDirect(c)
		return
	end

	--// pixel box (GL window coordinates, origin bottom left)
	local cx, cy = c.x, c.y
	local x1 = floor(cx * s) - MARGIN
	local x2 = ceil((cx + c.width) * s) + MARGIN
	local y1 = floor(vsy - (cy + c.height) * s) - MARGIN
	local y2 = ceil(vsy - cy * s) + MARGIN
	if (x1 < 0) then x1 = 0 end
	if (y1 < 0) then y1 = 0 end
	if (x2 > vsx) then x2 = vsx end
	if (y2 > vsy) then y2 = vsy end
	local w, h = x2 - x1, y2 - y1

	local rec = recordOf[c] or NewRecord(c)
	rec.lastUsed = frame

	local changed = (rec.counter ~= counter) or (rec.gen ~= generation)
		or (rec.ox ~= x1) or (rec.oy ~= y1) or (rec.w ~= w) or (rec.h ~= h)
		or (rec.vsx ~= vsx) or (rec.vsy ~= vsy) or (rec.scale ~= s)
	if changed then
		rec.counter, rec.gen = counter, generation
		rec.ox, rec.oy, rec.w, rec.h = x1, y1, w, h
		rec.vsx, rec.vsy, rec.scale = vsx, vsy, s
		rec.valid = false
		rec.eligible = (w <= MAX_DIM) and (h <= MAX_DIM) and (w * h <= MAX_AREA) and DrawsInsideBox(c)
		rec.ema = rec.ema * EMA_KEEP + (1 - EMA_KEEP)
	else
		rec.ema = rec.ema * EMA_KEEP
	end

	if (w <= 0) or (h <= 0) then
		--// entirely outside the view: nothing of it would be visible
		return
	end

	if rec.hot then
		if (rec.ema < HOT_LEAVE) then
			rec.hot = false
		end
	elseif (rec.ema > HOT_ENTER) then
		rec.hot = true
	end

	if (not rec.eligible) or rec.hot then
		if rec.tex and (not rec.eligible) then
			FreeRecordGL(rec)
		end
		DrawDirect(c, rec)
		return
	end

	if not rec.valid then
		if (state == STATE_DIRECT) then
			glPopMatrix()
			state = STATE_NONE
		elseif (state == STATE_COMPOSITE) then
			glTexture(0, false)
			glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
			state = STATE_NONE
		end
		if not RenderRecord(c, rec, x1, y1, w, h, vsx, vsy, s) then
			rec.eligible = false
			FreeRecordGL(rec)
			DrawDirect(c, rec)
			return
		end
		rec.valid = true
	end

	EnterComposite()
	glTexture(0, rec.tex)
	glTexRect(x1, y1, x2, y2, 0, 0, w / rec.tw, h / rec.th)
end

--// draws the children of the screen like Object.Draw (last child first)
function RenderCache.DrawScreen(screen, vsx, vsy, s)
	screen = UnlinkSafe(screen)
	frame = frame + 1
	fontsFlushed = false

	frameOK = false
	if available and (s > 0) then
		--// chili's scissor rects assume the view starts at the window origin
		local _, _, vpx, vpy = Spring.GetViewGeometry()
		frameOK = (vpx == 0) and (vpy == 0)
	end

	curVsy, curScale = vsy, s
	state = STATE_NONE
	ControlDraw = Control.Draw

	--// text is begun with userDefinedBlending in this mode (see font.lua),
	--// so make sure the standard blending the engine sets up is active
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

	local children = screen.children
	for i = #children, 1, -1 do
		local c = children[i]
		if c then
			DrawChild(c, vsx, vsy, s)
		end
	end

	LeaveAll()
	glColor(1, 1, 1, 1)

	FontHandler.ClearPendingUploads()

	if (frame % 64 == 0) then
		Sweep()
	end
end

--//=============================================================================
--// switching

local function InvalidateTree(obj)
	if obj.Invalidate then
		obj:Invalidate()
	end
	local children = obj.children
	if children then
		for i = 1, #children do
			local c = children[i]
			if c then
				InvalidateTree(c)
			end
		end
	end
end

--// turns the render cache on or off; all display lists are rebuilt
--// (they differ in how text sets its blending)
function RenderCache.SetEnabled(enabled, screen)
	enabled = not not enabled
	if ((not not ChiliRenderCache) == enabled) then
		return
	end
	ChiliRenderCache = enabled
	RenderCache.FreeAll()
	FontHandler.ClearPendingUploads()
	if screen then
		InvalidateTree(UnlinkSafe(screen))
	end
end

function RenderCache.IsAvailable()
	return available
end

--//=============================================================================
