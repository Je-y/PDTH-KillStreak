-- Kill Streak :: hud lifetime
--
-- the icon lives in its own overlay workspace. it is created right before it is
-- shown and released when it is not needed any more, because the overlay gui is
-- replaced whenever a level is loaded - a workspace that outlives that swap keeps
-- existing as a lua object but stops drawing.
--
-- the fade is driven from HUDManager:update. gui coroutines (panel:animate) turned
-- out to run the complete animation inside one frame here, which made the icon
-- flash for a single frame.

local module = ... or D:module("killstreak")
local KillStreak = _G.KillStreak

if not KillStreak then
	return
end

local HUDManager
do
	local ok, cls = pcall(function() return module:hook_class("HUDManager") end)
	if ok then
		HUDManager = cls
	end
end

if not HUDManager then
	module:log(0, "killstreak", "HUDManager not found")
	return
end

local function install(fname, fn)
	if type(HUDManager[fname]) ~= "function" then
		module:log(1, "killstreak", "HUDManager." .. fname .. " not found")
		return false
	end

	local ok, err = pcall(function()
		module:post_hook(HUDManager, fname, fn)
	end)
	if not ok then
		module:log(0, "killstreak", "could not hook HUDManager." .. fname .. ": " .. tostring(err))
	end
	return ok
end

-- a new hud manager means a new level: throw the old workspace away and give the
-- sound helper a head start, so the very first kill already has its sound loaded
install("init", function(self)
	pcall(function() KillStreak:destroy_panel() end)
	-- a new level gets a new overlay gui, so a previous failure may well be gone
	KillStreak.panel_broken = nil

	-- the warm up workspace belongs to the gui of the previous level and is dead
	-- weight now. KillStreak itself survives a level (it lives in _G), so the flags
	-- have to be cleared here or the next level would skip the warm up entirely and
	-- build nothing.
	KillStreak._warmed = nil
	KillStreak._warm_panel = nil
	KillStreak._warm_workspace = nil

	-- register the icon sheets and touch them right away: decoding runs in the
	-- background and a sheet that is still decoding loses its texture_rect
	pcall(function() KillStreak:warm_textures() end)

	local opt = KillStreak.opt
	if opt.enable_sound and opt.sfx_mode ~= "wwise" and opt.sfx_mode ~= "off" then
		pcall(function() KillStreak:ext_start() end)
	end

	-- pick up whatever was set in the in game menu (also survives restarts)
	pcall(function() KillStreak:refresh_settings() end)
	if not KillStreak.opt.enabled then
		pcall(function() KillStreak:destroy_panel() end)
	end

	-- a fresh level, so the voice pack may announce itself again
	KillStreak._round_start_pending = true

	-- everything that needs a ready overlay, a decoded texture or a warm sound
	-- helper runs from the update tick a moment later, NOT from the hud layout pass:
	-- doing it inside the layout hook means creating a workspace and writing the
	-- sound queue in the middle of a hud rebuild
	KillStreak._boot_pending, KillStreak._boot_at = true, nil
end)

-- the workspace size (and the gui) changes with the resolution
install("resolution_changed", function(self)
	pcall(function() KillStreak:destroy_panel() end)
	-- a panel that failed to build while the renderer was being torn down must not
	-- disable the icons for the rest of the session
	KillStreak.panel_broken = nil
end)

-- per frame animation + the deferred diagnostic icon
local update_installed = install("update", function(self)
	local ks = KillStreak

	-- level boot: warm the textures, run the optional diagnostic icon and say the
	-- round start line once the level has settled
	if ks._boot_pending then
		local now = Application:time()
		if not ks._boot_at then
			ks._boot_at = now + 1.5
		elseif now >= ks._boot_at then
			ks._boot_pending, ks._boot_at = nil, nil
			pcall(function() ks:warm_textures() end)
			pcall(function() ks:show_test() end)
			pcall(function() ks:play_round_start() end)
		end
	end

	if ks._test_pending then
		local now = Application:time()
		if not ks._test_at then
			ks._test_at = now + 2.0
		elseif now >= ks._test_at then
			ks._test_pending, ks._test_at = nil, nil
			pcall(function() ks:show_test_now() end)
		end
	end

	if ks._anim then
		pcall(function() ks:tick(Application:time()) end)
	end

	if ks._retry then
		pcall(function() ks:update_retry(Application:time()) end)
	end

	if ks._burst then
		pcall(function() ks:update_sound() end)
	end
end)

if not update_installed then
	module:log(0, "killstreak", "no per frame update, icons will not fade out")
end

-- the hud layout hook used to run the warm up / diagnostic icon / round start line.
-- it fires while the hud is rebuilding its panels, and creating a workspace or
-- writing the sound queue there is not safe, so all of it moved into the update
-- tick above (see _boot_pending).
