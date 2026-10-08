--//=============================================================================
--// FontSystem

FontHandler = {}


--//=============================================================================
--// cache loaded fonts

local loadedFonts = {}
local refCounts = {}

--//=============================================================================
--// Destroy

FontHandler._scream = Script.CreateScream()
FontHandler._scream.func = function()
  for i=1,#loadedFonts do
    gl.DeleteFont(loadedFonts[i])
  end
  loadedFonts = {}
end


local n = 0
function FontHandler.Update()
	n = n + 1
	if (n <= 100) then
		return
	end
	n = 0

	local last_idx = #loadedFonts
	for i=last_idx, 1, -1 do
		if (refCounts[i] <= 0) then
			--// the font isn't in use anymore, free it
			local pending = FontHandler.pendingUploads
			if pending then
				pending[loadedFonts[i]] = nil
			end
			gl.DeleteFont(loadedFonts[i])
			loadedFonts[i] = loadedFonts[last_idx]
			loadedFonts[last_idx] = nil
			refCounts[i] = refCounts[last_idx]
			refCounts[last_idx] = nil
			last_idx = last_idx - 1
		end
	end
end

--//=============================================================================
--// Glyph atlas uploads (render cache)

local function BeginEndFont(font)
	font:Begin()
	font:End()
end

--// The engine uploads new glyphs of a font in font:End() unless a display
--// list is being compiled, else only in its next per-frame font update.
--// A font:Begin()/End() pair with no text forces the upload now, so text in
--// display lists compiled this frame is complete when it gets rendered into
--// a cached texture.
function FontHandler.FlushPendingUploads()
	local pending = FontHandler.pendingUploads
	if (not pending) or (not next(pending)) then
		return
	end
	for font in pairs(pending) do
		pcall(BeginEndFont, font)
		pending[font] = nil
	end
end

function FontHandler.ClearPendingUploads()
	local pending = FontHandler.pendingUploads
	if pending and next(pending) then
		for font in pairs(pending) do
			pending[font] = nil
		end
	end
end

--//=============================================================================
--// API

function FontHandler.UnloadFont(font)
  for i=1,#loadedFonts do
    local font2 = loadedFonts[i]
    if (font == font2) then
      refCounts[i] = refCounts[i] - 1
      return
    end
  end
end

function FontHandler.LoadFont(fontname,size,outwidth,outweight)
  for i=1,#loadedFonts do
    local font = loadedFonts[i]
    if
      ((font.path == fontname)or(font.path == 'fonts/'..fontname))
      and(font.size == size)
      and(font.outlinewidth == outwidth)
      and(font.outlineweight == outweight)
    then
      refCounts[i] = refCounts[i] + 1
      return font
    end
  end

  local idx = #loadedFonts+1
  local font = gl.LoadFont(fontname,size,outwidth,outweight)
  loadedFonts[idx] = font
  refCounts[idx] = 1
  return font
end
