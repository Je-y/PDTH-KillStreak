-- Kill Streak :: core (texture registration, panel, animation, streak state, sound)

local module = ... or D:module("killstreak")
local KillStreak = _G.KillStreak

if not KillStreak then
	return
end

-- the icon set is cut from the reference footage, one animation per tier:
-- 9 tiers x 20 frames of 256 px, laid out 8 columns x 8 rows per sheet
-- (2048x2048), 3 tiers per sheet -> 3 sheets. tier 0..2 are the three one-kill
-- variants, tier 3..8 are streaks 2..7. the frames carry the whole entry
-- animation (flash, slam, wobble), so the icon itself only plays them back.
local CELL = 256
local COLS = 8
local FRAMES = 20
local TIERS_PER_SHEET = 3
local SHEETS = 3
-- the settled frame of every tier also lives in its own sharp sheet: the animated
-- one has to cover a 640 px box (the entry frames are blown up 1.9x), which leaves
-- the settled icon at barely a third of the cell, so scaling that up to ~900 px was
-- visibly soft. this sheet is cut from a 400 px box at 512 px per cell, so the
-- settled icon is drawn almost 1:1.
local HI_CELL = 512
local HI_COLS = 4
local HI_BOX_RATIO = 400 / 640
-- the settled icon is 200 px inside the 640 px source box, so drawing the 256 px
-- cell at 410 px keeps it at the size the old 512 px frames had at scale 1.0
local ICON_BASE = 410
local TIER_GOLD = 0        -- 1 kill, headshot (gold)
local TIER_WHITE = 1       -- 1 kill, headshot (white)
local TIER_BODY = 2        -- 1 kill, body
local TIER_MAX = 8         -- 7 kills and above (the golden wings)

local function sheet_of(tier)
	return math.min(math.floor(tier / TIERS_PER_SHEET), SHEETS - 1)
end

-- top left corner of a frame inside its sheet
local function cell_of(tier, frame)
	local i = (tier % TIERS_PER_SHEET) * FRAMES + ((frame or 1) - 1)
	local col = i % COLS
	local row = math.floor(i / COLS)
	return col * CELL, row * CELL
end

-- the sharp sheet holds one settled frame per tier, so the cell follows the tier
local function cell_of_hi(tier)
	local col = tier % HI_COLS
	local row = math.floor(tier / HI_COLS)
	return col * HI_CELL, row * HI_CELL
end

local max = math.max

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- the ported icons carry their own colours (dark star, orange points, golden wings,
-- skulls), so nothing is tinted at runtime any more - set_color stays white
local ICON_COLOR = Color(1, 1, 1, 1)

function KillStreak:log(...)
	if not self.opt.debug then return end
	pcall(module.log, module, 1, "killstreak", ...)
end

function KillStreak:module_log(level, ...)
	pcall(module.log, module, level, "killstreak", ...)
end

-- > texture --------------------------------------------------------------------
-- payday the heist can load loose .texture files through DB:create_entry - the same
-- mechanism the DAHM package manager uses for its own custom assets. the icon set
-- needs 3 sheets (9 tiers x 20 frames), so the configured texture id is used as a
-- base name and every sheet appends _a / _b / _c.
function KillStreak:texture_id(sheet)
	local base = tostring(self.opt.texture or "guis/textures/killstreak/killicons")
	return base .. "_" .. string.char(97 + sheet)
end

function KillStreak:texture_file(sheet)
	return (self.path or "") .. "assets/killicons_" .. string.char(97 + sheet) .. ".texture"
end

function KillStreak:texture_id_hi()
	local base = tostring(self.opt.texture or "guis/textures/killstreak/killicons")
	return base .. "_hi"
end

function KillStreak:texture_file_hi()
	return (self.path or "") .. "assets/killicons_hi.texture"
end

-- every sheet that has to be registered: the three animated ones plus the sharp
-- settled frame sheet
function KillStreak:sheet_list()
	local list = {}
	for sheet = 0, SHEETS - 1 do
		list[#list + 1] = { id = self:texture_id(sheet), file = self:texture_file(sheet) }
	end
	list[#list + 1] = { id = self:texture_id_hi(), file = self:texture_file_hi() }
	return list
end

function KillStreak:register_texture()
	if self.texture_ready == true then
		return true
	end
	if self.texture_failed and not self.texture_retry then
		return false
	end

	if not self.opt.texture or not DB or not DB.has then
		return false
	end
	if not DB.create_entry then
		self.texture_failed = true
		return false
	end

	local ids = {}
	local registered = 0
	local sheets = self:sheet_list()

	for i = 1, #sheets do
		local id, file = sheets[i].id, sheets[i].file
		ids[#ids + 1] = Idstring and Idstring(id) or id
		local ok, has = pcall(function() return DB:has("texture", id) end)
		if ok and has then
			self:module_log(2, "texture already available:", id)
		else
			self:module_log(1, "registering texture", id, "from", file)
			local created, err = pcall(function()
				DB:create_entry("texture", id, file)
			end)
			if not created then
				self.texture_failed = true
				self:module_log(1, "DB:create_entry failed for", id, ":", tostring(err))
				return false
			end
			ok, has = pcall(function() return DB:has("texture", id) end)
			if not (ok and has) then
				self.texture_failed = true
				self:module_log(1, "texture was not accepted by the db:", file)
				return false
			end
			registered = registered + 1
			self:module_log(2, "texture registered from", file)
		end
	end

	-- DB:create_entry only writes a lookup row, it does NOT parse the file. until the
	-- engine actually loads the texture the gui sees it with no size, every
	-- texture_rect collapses and the whole 2048 px sheet is drawn as one frame (that
	-- was the "all icons at once" picture). forcing a reload makes the engine read
	-- the dds header, which is what gives the bitmap its real size again.
	-- blt_compat does exactly this for its mod images.
	if #ids > 0 and Application and Application.reload_textures then
		local ok, err = pcall(function() Application:reload_textures(ids) end)
		if ok then
			self:module_log(1, "reload_textures requested for " .. #ids
				.. " sheet(s), " .. registered .. " newly registered")
		else
			self:module_log(1, "reload_textures failed:", tostring(err))
		end
	end

	self.texture_source = "db"
	self.texture_ready = true
	return true
end

-- > sound ----------------------------------------------------------------------
function KillStreak:ensure_sound_source()
	if self._sound_source then
		return self._sound_source
	end
	if not SoundDevice or not SoundDevice.create_source then
		return nil
	end

	local bank = self.opt.sound_bank or "hud"
	local ok, source = pcall(function() return SoundDevice:create_source(bank) end)
	if ok and source then
		self._sound_source = source
		return source
	end

	self:module_log(1, "could not create sound source:", tostring(bank), tostring(source))
	return nil
end

function KillStreak:play_sound(event)
	if not event or event == "" then
		return
	end
	local source = self:ensure_sound_source()
	if not source then
		return
	end
	local ok, err = pcall(function() source:post_event(event) end)
	if not ok then
		self:module_log(1, "post_event failed:", tostring(event), tostring(err))
		return
	end
	self:log("sound", event)
end

-- kind: "kill" | "headshot" | "melee" | "multikill" | "civilian"
-- external files win when they exist, the wwise event is the fallback
function KillStreak:emit_sound(kind, streak)
	local opt = self.opt
	if not opt.enable_sound or opt.sfx_mode == "off" then
		return
	end

	if opt.sfx_mode ~= "wwise" then
		local name = self:ext_sound_for(kind, streak)
		if name and self:ext_play(name) then
			return
		end
		if opt.sfx_mode == "external" then
			return
		end
	end

	local event
	if kind == "headshot" then
		event = opt.sound_headshot
	elseif kind == "multikill" then
		event = opt.sound_multikill
	elseif kind == "civilian" then
		event = opt.sound_civilian
		if event == nil or event == "" then
			event = opt.sound_kill
		end
	else
		event = opt.sound_kill
	end

	if event and event ~= "" then
		self:play_sound(event)
	end
end

-- the voice packs ship a "round start" line; it is played once per level when the
-- in game hud is up (play_round_start, off by default)
function KillStreak:play_round_start()
	local opt = self.opt
	if not opt.play_round_start or not opt.enable_sound then
		return
	end
	if opt.sfx_mode == "wwise" or opt.sfx_mode == "off" then
		return
	end
	if not self._round_start_pending then
		return
	end
	self._round_start_pending = false

	local name = opt.sfx_round_start
	if not name or name == "" then
		return
	end

	-- never start the player from inside a level: launching a process opens a
	-- console window and drops the player out of the game. if the helper is not
	-- already alive, skip the line instead of spawning it.
	if not self:ext_alive() then
		self:module_log(1, "round start sound skipped (sound helper is not running)")
		return
	end

	local rel = self:ext_file(name)
	if rel then
		self:ext_play(rel)
	end
end

-- > panel ----------------------------------------------------------------------
-- used only when the texture could not be registered with the db
-- index = tier (0/1 = 1 kill headshot, 2 = 1 kill body, 3..8 = streaks 2..7)
local TEXT_LABELS = {
	[0] = "HEAD",
	[1] = "HEAD",
	[2] = "KILL",
	[3] = "x2",
	[4] = "x3",
	[5] = "x4",
	[6] = "x5",
	[7] = "x6",
	[8] = "x7+",
}

function KillStreak:destroy_panel()
	local ws = self._workspace
	self._workspace, self._panel, self._icon = nil, nil, nil
	self._hi = nil
	self._frame, self._anim, self._text_mode = nil, nil, nil
	if ws then
		pcall(function() Overlay:newgui():destroy_workspace(ws) end)
	end
end

-- textures are decoded in the background, so the first icon that uses a sheet can
-- still get a texture with no known size - and a texture with no size makes every
-- texture_rect collapse into "draw the whole 2048 px sheet". that is why the first
-- streak of each sheet (1 kill / 2 kills / 5 kills) came out as the full atlas
-- while the later ones looked right.
--
-- registering as early as the level start and touching every sheet with a throwaway
-- bitmap gives the engine the whole level to finish decoding, so by the time the
-- first kill happens the sheets already have their real size.
function KillStreak:warm_textures()
	if self._warmed then
		return true
	end
	if not self:register_texture() then
		-- the db may not be ready this early; do not poison the normal retry path
		self.texture_failed, self.texture_retry = nil, nil
		return false
	end
	if self._warm_panel then
		self._warmed = true
		return true
	end

	local ok, err = pcall(function()
		local gui = Overlay:newgui()
		local ws = gui:create_screen_workspace()
		local panel = ws:panel({ name = "killstreak_warm", layer = 0, alpha = 1 })
		local sheets = self:sheet_list()
		for i = 1, #sheets do
			local b = panel:bitmap({
				name = "killstreak_warm_" .. i,
				texture = sheets[i].id,
				texture_rect = { 0, 0, CELL, CELL },
				w = 16, h = 16,
				alpha = 1,
				layer = i,
			})
			-- just off screen: it still has to be built (which is what loads the
			-- texture) but nothing must ever be visible
			b:set_center(-100 - i * 20, -100)
		end
		self._warm_workspace = ws
		self._warm_panel = panel
	end)

	if ok then
		self._warmed = true
		self:module_log(1, "textures warming up (" .. (SHEETS + 1) .. " sheets)")
	else
		self:module_log(1, "texture warm up failed:", tostring(err))
	end
	return ok
end

-- the size of the coordinate space the overlay gui draws in.
--
-- three sources are available and they do not always agree:
--   RenderSettings.resolution          the renderer's current output size
--   viewport:get_safe_rect_pixels()    the visible screen rect (overscan removed)
--   managers.hud._workspace_size       a copy the hud takes when a level STARTS
--
-- the hud copy is the trap: it does not follow an in-game resolution change, so after
-- switching from 4k to 1080p it still says 3840x2160. an anchor computed from it lands
-- outside the real (much smaller) surface and the icon simply never appears - which is
-- exactly the "works at 4k, invisible everywhere else" report.
--
-- so the order is: live render size, then the viewport rect, and the hud copy only
-- when neither exists. every value that disagrees is written to the log, so a wrong
-- layout can be diagnosed from a single line.
local function screen_px(w, h)
	local nw, nh = tonumber(w), tonumber(h)
	-- sanity: pixel sizes, not 0..1 fractions and not garbage
	if nw and nh and nw >= 320 and nh >= 240 then
		return nw, nh
	end
	return nil
end

function KillStreak:screen_size()
	local rw, rh
	local ok_render, res = pcall(function() return RenderSettings.resolution end)
	if ok_render and res then
		rw, rh = screen_px(res.x, res.y)
	end

	local sw, sh
	local ok_vp, vw, vh = pcall(function()
		local rect = managers.viewport:get_safe_rect_pixels()
		return rect.w, rect.h
	end)
	if ok_vp then
		sw, sh = screen_px(vw, vh)
	end

	local hw, hh
	local ok_hud, ws = pcall(function() return managers.hud._workspace_size end)
	if ok_hud and ws then
		local okw, aw = pcall(function() return ws.w end)
		local okh, ah = pcall(function() return ws.h end)
		if okw and okh then
			hw, hh = screen_px(aw, ah)
		end
	end

	local w, h, src
	if rw then
		w, h, src = rw, rh, "render"
	elseif sw then
		w, h, src = sw, sh, "viewport"
	elseif hw then
		w, h, src = hw, hh, "hud"
	else
		w, h, src = 1920, 1080, "default"
	end

	-- the anchor is additionally clamped to the smallest of the *live* sizes, so if the
	-- renderer and the viewport disagree (overscan) the icon still stays on screen.
	-- the hud copy is deliberately left out: it is the stale one, and clamping to a
	-- stale small value would drag the icon towards the top left after switching up.
	local lim_w, lim_h = w, h
	if sw then
		lim_w, lim_h = math.min(lim_w, sw), math.min(lim_h, sh)
	end
	self._screen_lim_w, self._screen_lim_h = lim_w, lim_h

	self._screen_src = src
	self._screen_mismatch = nil
	local parts = {}
	if sw and (math.abs(sw - w) > w * 0.02 or math.abs(sh - h) > h * 0.02) then
		parts[#parts + 1] = "viewport " .. math.floor(sw) .. "x" .. math.floor(sh)
	end
	if hw and (math.abs(hw - w) > w * 0.02 or math.abs(hh - h) > h * 0.02) then
		parts[#parts + 1] = "hud " .. math.floor(hw) .. "x" .. math.floor(hh)
	end
	if #parts > 0 then
		self._screen_mismatch = "using " .. math.floor(w) .. "x" .. math.floor(h)
			.. ", other sources say " .. table.concat(parts, ", ")
	end

	return w, h
end

function KillStreak:screen_anchor()
	local w, h = self:screen_size()

	local cx = math.floor(w * (0.5 + (tonumber(self.opt.offset_x) or 0)))
	local cy = math.floor(h * 0.5 + h * (tonumber(self.opt.offset_y) or 0.15))

	-- keep the anchor reachable even when the chosen size was the wrong one
	local lim_w = math.max(math.floor(self._screen_lim_w or w) - 8, 8)
	local lim_h = math.max(math.floor(self._screen_lim_h or h) - 8, 8)
	cx = clamp(cx, 8, lim_w)
	cy = clamp(cy, 8, lim_h)
	return cx, cy
end

function KillStreak:create_panel(tier)
	if self.panel_broken then
		return false
	end

	tier = clamp(tonumber(tier) or 0, 0, TIER_MAX)
	local opt = self.opt
	local use_texture = self:register_texture()

	local ok_gui, gui = pcall(function() return Overlay:newgui() end)
	if not ok_gui or not gui then
		return false
	end

	local sheet = sheet_of(tier)
	local fx0, fy0 = cell_of(tier, 1)
	local size = max(math.floor(ICON_BASE * (tonumber(opt.scale) or 1.0) + 0.5), 24)
	local cx, cy = self:screen_anchor()
	local text_mode = not use_texture

	local ok, err = pcall(function()
		local ws = gui:create_screen_workspace()
		-- NOTE: a panel's alpha is inherited by its children, so this one has to stay
		-- at 1.0 - the fade is done on the icon itself.
		local panel = ws:panel({ name = "killstreak_panel", layer = 200, alpha = 1 })
		local icon
		if text_mode then
			icon = panel:text({
				name = "killstreak_text",
				text = TEXT_LABELS[tier] or TEXT_LABELS[0],
				font = "fonts/font_univers_530_bold",
				font_size = math.floor(size * 0.6),
				color = ICON_COLOR,
				align = "center",
				vertical = "center",
				w = size,
				h = size,
				alpha = 1,
				layer = 1,
			})
		else
			icon = panel:bitmap({
				name = "killstreak_icon",
				texture = self:texture_id(sheet),
				texture_rect = { fx0, fy0, CELL, CELL },
				w = size,
				h = size,
				alpha = 1,
				layer = 1,
			})
		end
		icon:set_center(cx, cy)
		icon:set_color(ICON_COLOR)

		-- the sharp settled frame, drawn on top once the 20 frame intro is over.
		-- it covers a smaller source box, so the bitmap is proportionally smaller
		-- while the icon on screen stays exactly the same size.
		if not text_mode then
			local hx, hy = cell_of_hi(tier)
			local hi = panel:bitmap({
				name = "killstreak_hi",
				texture = self:texture_id_hi(),
				texture_rect = { hx, hy, HI_CELL, HI_CELL },
				w = size * HI_BOX_RATIO,
				h = size * HI_BOX_RATIO,
				alpha = 0,
				layer = 2,
			})
			hi:set_center(cx, cy)
			self._hi = hi
		else
			self._hi = nil
		end

		-- the flash and the spark used to live in the spare cells of the old sheet.
		-- every frame of the new set already carries its own flash and sparkle, so
		-- there is nothing to draw on top any more.
		self._workspace = ws
		self._panel = panel
		self._icon = icon
		self._text_mode = text_mode or nil
	end)

	if not ok then
		self.panel_broken = true
		self:module_log(1, "panel creation failed:", tostring(err))
		self:destroy_panel()
		return false
	end

	self._size, self._cx, self._cy = size, cx, cy
	self._frame, self._tier, self._sheet = 0, tier, sheet
	self:module_log(1, "panel created", tostring(size), cx, cy, "tier " .. tostring(tier),
		"sheet " .. tostring(sheet),
		text_mode and "(TEXT fallback - texture rejected by the db)"
			or ("(texture ok, source " .. tostring(self.texture_source or "?") .. ")"),
		"[" .. tostring(self._screen_src) .. "]")
	if self._screen_mismatch then
		self:module_log(1, "screen size mismatch:", self._screen_mismatch,
			"- the hud copy is stale, using the live render resolution")
	end
	return true
end

function KillStreak:set_frame(frame)
	local icon = self._icon
	frame = clamp(tonumber(frame) or 1, 1, FRAMES)
	if not icon or frame == self._frame then
		return
	end
	self._frame = frame

	if self._text_mode then
		pcall(function() icon:set_text(TEXT_LABELS[self._tier] or "") end)
	else
		local fx, fy = cell_of(self._tier or 0, frame)
		local ok = pcall(function()
			icon:set_texture_rect(fx, fy, CELL, CELL)
		end)
		if not ok then
			-- older gui api: recreate the bitmap with the new rect
			pcall(function()
				self._panel:remove(icon)
				local new_icon = self._panel:bitmap({
					name = "killstreak_icon",
					texture = self:texture_id(self._sheet or 0),
					texture_rect = { fx, fy, CELL, CELL },
					w = self._size,
					h = self._size,
					alpha = 1,
					layer = 1,
				})
				new_icon:set_center(self._cx, self._cy)
				self._icon = new_icon
			end)
		end
	end

	pcall(function() self._icon:set_color(ICON_COLOR) end)
end

-- > animation ------------------------------------------------------------------
-- the animation is driven by HUDManager:update instead of a gui coroutine: in this
-- game "icon:animate(...)" finished the whole fade inside a single frame, so the
-- icon was only visible for one rendered frame.
function KillStreak:present(tier, streak)
	-- a workspace belongs to the overlay gui that existed when it was made and the
	-- game swaps that gui when a level loads, so a long lived panel would silently
	-- stop drawing. build a fresh one for every icon instead.
	self:destroy_panel()
	if not self:create_panel(tier) then
		return false
	end

	local icon = self._icon
	if not icon then
		return false
	end

	local opt = self.opt
	local n = tonumber(streak) or 1
	local fx = opt.fx_enabled ~= false

	-- the entry animation is part of the frames: with fx on the whole strip plays,
	-- with fx off the icon is shown as its last (settled) frame
	if not fx then
		self:set_frame(FRAMES)
	else
		self:set_frame(1)
	end

	-- draw it immediately, already at the size the slam starts from: even if the hud
	-- update never ticks, the icon is visible instead of staying invisible
	local start_scale = (fx and max(tonumber(opt.fx_drop_scale) or 1.0, 1.0)) or 1.0
	-- the drop starts a bit above the resting spot, so the first tick has somewhere
	-- to fall to even if the hud update is late
	local start_y = self._cy - (fx and self._size * (tonumber(opt.fx_drop_lift) or 0.0) or 0)
	pcall(function()
		icon:set_size(self._size * start_scale, self._size * start_scale)
		icon:set_center(self._cx, start_y)
		icon:set_alpha(tonumber(opt.alpha) or 0.88)
	end)

	self._anim = { t0 = Application:time(), streak = n, tier = tier }
	return true
end

function KillStreak:show(frame, streak)
	if not self.opt.enabled then
		return
	end

	if self:present(frame, streak) then
		self._retry = nil
		return
	end

	-- the overlay gui is unavailable for a moment whenever the renderer is rebuilt
	-- (level load, resolution change). dropping the icon there is why kills right
	-- after a resolution switch showed nothing, so keep trying for a short while.
	if not self.panel_broken then
		self._retry = { frame = frame, streak = streak, tries = 0, t = Application:time() }
	end
end

function KillStreak:update_retry(now)
	local r = self._retry
	if not r then
		return
	end

	r.tries = r.tries + 1
	if self:present(r.frame, r.streak) then
		self._retry = nil
		return
	end

	now = now or Application:time()
	if r.tries > 30 or (now - (r.t or now)) > 2 then
		self._retry = nil
		self:module_log(1, "icon dropped: the overlay gui stayed unavailable")
	end
end

function KillStreak:tick(now)
	local anim = self._anim
	if not anim then
		return
	end

	local icon = self._icon
	if not icon then
		self._anim = nil
		return
	end

	local opt = self.opt
	local alpha = tonumber(opt.alpha) or 0.88
	local fx = opt.fx_enabled ~= false

	-- with fx on the 20 frame strip plays over anim_time; with fx off the settled frame
	-- is shown with a short fade in. the strip already carries the contact squash and
	-- the wobble, so there is no separate settle phase any more.
	local land_t = fx and clamp(tonumber(opt.anim_time) or 0.34, 0.05, 3.0)
		or max(tonumber(opt.pop_time) or 0.09, 0.001)
	local drop_s = fx and max(tonumber(opt.fx_drop_scale) or 1.0, 1.0) or 1.5
	local hold = max(tonumber(opt.hold_time) or 1.45, 0)
	local fade = max(tonumber(opt.fade_time) or 0.55, 0.001)
	local total = land_t + hold + fade

	local t = (now or Application:time()) - anim.t0
	if t < 0 then
		t = 0
	end

	local scale, a, ox, oy = 1, alpha, 0, 0

	if t < land_t then
		-- the fall accelerates (k^2) and comes down from slightly above, so the
		-- contact reads as weight - a chess piece dropped on the board, not a zoom.
		-- the entry animation itself lives in the frames, so this phase also plays
		-- the strip: FRAMES frames spread evenly across land_t.
		local k = t / land_t
		scale = drop_s - (drop_s - 1) * k * k
		oy = -(tonumber(opt.fx_drop_lift) or 0.0) * self._size * (1 - k * k)
		if fx then
			self:set_frame(1 + math.floor(k * FRAMES))
		else
			a = alpha * k
		end
	elseif t < land_t + hold then
		-- static hold on the settled frame
		self:set_frame(FRAMES)
	elseif t < total then
		local k = clamp((t - land_t - hold) / fade, 0, 1)
		a = alpha * (1 - k)
		scale = 1 - 0.15 * k
	else
		pcall(function()
			icon:set_alpha(0)
			if self._hi then self._hi:set_alpha(0) end
		end)
		self._anim = nil
		return
	end

	local size = self._size * scale
	local hi = self._hi
	-- once the 20 frame intro is over the sharp settled frame takes over: it is cut
	-- from a much tighter box, so it stays crisp at large scale factors
	local use_hi = hi ~= nil and t >= land_t
	pcall(function()
		if use_hi then
			icon:set_alpha(0)
			hi:set_size(size * HI_BOX_RATIO, size * HI_BOX_RATIO)
			hi:set_center(self._cx + ox, self._cy + oy)
			hi:set_alpha(a)
		else
			icon:set_size(size, size)
			icon:set_center(self._cx + ox, self._cy + oy)
			icon:set_alpha(a)
			if hi then
				hi:set_alpha(0)
			end
		end
	end)
end

-- > kill handling --------------------------------------------------------------
function KillStreak:show_test_now()
	if not self.opt.test_on_start then
		return
	end
	self:module_log(1, "showing the test icon at level start (texture ",
		self.texture_ready and "ok" or "NOT loaded", ")")
	self:show(0, 1)
end

-- show_test_now is deferred by one hud update so that the workspace is created
-- while the game is actually running, not during the level load transition
function KillStreak:show_test()
	if not self.opt.test_on_start then
		return
	end
	self._test_pending = true
	-- the sheets are still decoding when the level starts, so hudmanager holds the
	-- diagnostic icon back for a moment (2 s): otherwise that first icon would be
	-- the one that shows the whole atlas and make a working mod look broken
	self._test_at = nil
end

-- tier layout of the icon set:
--   0 / 1 -> 1 kill, headshot (gold / white, the reference mod picks gold ~30%)
--   2     -> 1 kill, body
--   3..8  -> streaks 2..7, 7 and above reuse the golden wings tier
function KillStreak:tier_for(streak, headshot)
	local n = tonumber(streak) or 1
	if n >= 7 then
		return TIER_MAX
	end
	if n >= 2 then
		return n + 1
	end
	if headshot then
		if math.random() > 0.7 then
			return TIER_GOLD
		end
		return TIER_WHITE
	end
	return TIER_BODY
end

-- a grenade or a shotgun blast kills several units in the same frame. playing one
-- sound per unit turned into a single sound (the rest was swallowed by the cooldown)
-- or, without a cooldown, into five overlapping copies, and a line that starts while
-- another one is still talking is just mush. so the kills of one instant are grouped
-- and exactly one line is played when the group is over: the streak line for a group
-- of 2+, the kill type line for a single kill.
function KillStreak:sound_kind(headshot, is_civilian, variant)
	if is_civilian then
		return "civilian"
	end
	if headshot then
		return "headshot"
	end
	if variant == "melee" then
		return "melee"
	end
	return "kill"
end

function KillStreak:update_sound()
	local burst = self._burst
	if not burst then
		return
	end

	local base = tonumber(self.opt.sound_cooldown) or 0.12
	-- only an explosion can take several units down at once, so only that has to wait
	-- out the full merge window. a plain shot fires after ~2 frames instead: holding
	-- every kill back by 120 ms made the voice trail the shot noticeably
	local window = burst.explosive and base or math.min(base, 0.03)

	local now = TimerManager:game():time()
	if (now - burst.t) < window and (now - burst.t0) < 0.35 then
		return
	end

	if burst.count >= 2 then
		-- one streak line for the whole group
		self:emit_sound("multikill", burst.streak)
	else
		self:emit_sound(burst.kind or "kill", burst.streak)
	end
	self._burst = nil
end

-- the game has more than one api for this depending on the build, so try them in
-- order and keep quiet about the ones that are missing
function KillStreak:mute_unit_sound(unit)
	if not unit then
		return false
	end

	local ok, src = pcall(function() return unit:sound() end)
	if not ok or not src then
		return false
	end

	if type(src.stop_all) == "function" then
		local done = pcall(function() src:stop_all() end)
		if done then
			return true
		end
	end

	if type(src.stop) == "function" then
		return pcall(function() src:stop() end)
	end

	if type(src.stop_unit) == "function" then
		return pcall(function() src:stop_unit() end)
	end

	return false
end

function KillStreak:on_kill(headshot, unit, is_civilian, variant)
	local opt = self.opt
	if not opt.enabled then
		return
	end

	-- the vanilla game plays its own cue when a hostage dies, and it is the same one
	-- it uses when a hostage is freed. cut it on the dying unit so the kill is only
	-- announced by this mod; a *freed* civilian is a different, living unit and keeps
	-- the original sound
	if is_civilian and opt.mute_civilian_sound ~= false then
		self:mute_unit_sound(unit)
	end

	local now = TimerManager:game():time()
	if now - (self._last_kill_t or -1e6) > (tonumber(opt.streak_window) or 2.5) then
		self._streak = 0
	end
	self._last_kill_t = now
	self._streak = (self._streak or 0) + 1

	-- the first few kills are always logged so that a broken setup can be diagnosed
	-- without turning on debug mode first
	local budget = self._log_budget or 6
	if self.opt.debug or budget > 0 then
		self._log_budget = budget - 1
		self:module_log(1, "kill", "streak=" .. tostring(self._streak), "headshot=" .. tostring(headshot),
			"civilian=" .. tostring(is_civilian), "hit=" .. tostring(variant))
	end

	if opt.enable_sound then
		local window = tonumber(opt.sound_cooldown) or 0.12
		local burst = self._burst
		if not burst or (now - burst.t) > window then
			burst = { t0 = now, t = now, count = 0, kind = nil }
			self._burst = burst
		end

		burst.t = now
		burst.count = burst.count + 1
		burst.streak = self._streak
		-- an explosion is the only thing that can kill several units in one go, so it
		-- is the only case that has to wait long enough to merge them into one line
		if variant == "explosion" then
			burst.explosive = true
		end
		if not burst.kind then
			-- the group is announced by its first kill's type
			burst.kind = self:sound_kind(headshot, is_civilian, variant)
		end
	end

	self:show(self:tier_for(self._streak, headshot), self._streak)
end
