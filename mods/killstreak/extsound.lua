-- Kill Streak :: external sound backend
--
-- wwise (the audio engine this game uses) can only play events that are baked into
-- its sound banks, and the engine exposes no "load this .wav for me" call - the
-- payload edition of this mod relies on a native plugin for that, which this game
-- does not ship.
--
-- so this backend plays the files through windows itself: a tiny resident
-- powershell helper is started once, and every sound is queued by appending one
-- line to tmp/queue.txt. the helper tails that file (8 ms poll) and plays the
-- file with System.Media.SoundPlayer, which is asynchronous and already preloaded,
-- so the delay between kill and sound is roughly 15-30 ms.
--
-- the wav files are grouped in voice packs (sfx/men1, sfx/women1, ...), one folder
-- per character, ported from the PAYDAY 2 kill streak mod.
--
-- everything here is optional: if the helper cannot be started (no powershell, no
-- io library, ...) the mod silently falls back to the wwise event configured in
-- config.lua.

local module = ... or D:module("killstreak")
local KillStreak = _G.KillStreak

if not KillStreak then
	return
end

local state = {
	started = false,
	ok = false,
	cache = {},
}

-- every pack that ships with the mod, used by voice_pack = "random"
local PACKS = { "men1", "men2", "men3", "men4", "women1", "women2", "women3", "women4", "women5" }

local function trim_slash(path)
	if not path or path == "" then
		return ""
	end
	if path:sub(-1) ~= "/" then
		return path .. "/"
	end
	return path
end

function KillStreak:ext_base()
	return trim_slash(self.path or "mods/killstreak")
end

-- the folder that holds the voice pack folders
function KillStreak:ext_dir()
	return self:ext_base() .. trim_slash(self.opt.sfx_dir or "sfx")
end

function KillStreak:ext_queue_path()
	return self:ext_base() .. "tmp/queue.txt"
end

function KillStreak:ext_beat_path()
	return self:ext_base() .. "tmp/server.heartbeat"
end

function KillStreak:ext_volume_path()
	return self:ext_base() .. "tmp/volume.txt"
end

-- the helper scales the pcm data itself (SoundPlayer has no volume), so it needs to
-- know how loud to be. written as a whole percent, which sidesteps the decimal comma
-- that some windows locales use when parsing "0.85".
function KillStreak:ext_push_volume()
	if not (io and io.open) then
		return false
	end
	local vol = tonumber(self.opt.sfx_volume)
	if vol == nil then
		vol = 1.0
	end
	if vol < 0 then
		vol = 0
	elseif vol > 1 then
		vol = 1
	end

	local f = io.open(self:ext_volume_path(), "w")
	if not f then
		return false
	end
	f:write(string.format("%d\n", math.floor(vol * 100 + 0.5)))
	f:close()
	return true
end

-- is the resident player still alive? the helper stamps tmp/server.heartbeat with a
-- unix timestamp every two seconds. launching a process from inside the game opens a
-- console window and drops the player out of the level, so the mod must never start a
-- second helper while one is already running.
function KillStreak:ext_alive()
	local ok, alive = pcall(function()
		if not (io and io.open and os and os.time) then
			return false
		end
		local f = io.open(self:ext_beat_path(), "r")
		if not f then
			return false
		end
		local txt = f:read("*l")
		f:close()
		local t = tonumber(txt)
		if not t then
			return false
		end
		return math.abs(os.time() - t) <= 8
	end)
	return (ok and alive) or false
end

-- checks a path relative to ext_dir(), no voice pack involved (so this is safe to
-- call while the pack itself is still being resolved)
function KillStreak:ext_exists(rel)
	if not rel or rel == "" then
		return false
	end

	local cached = state.cache[rel]
	if cached ~= nil then
		return cached
	end

	local exists = false
	if io and io.open then
		local f = io.open(self:ext_dir() .. rel, "rb")
		if f then
			f:close()
			exists = true
		end
	end

	state.cache[rel] = exists
	return exists
end

-- which folder the sounds come from: "men1", "" (files sit directly in sfx/) ...
function KillStreak:ext_pack()
	if self._ext_pack ~= nil then
		return self._ext_pack
	end

	local want = tostring(self.opt.voice_pack or "")
	if want == "random" then
		-- a different seed every session, without touching the game's own rng
		local start = (os.time and os.time() or 0) % #PACKS
		local found = ""
		for i = 1, #PACKS do
			local candidate = PACKS[((start + i - 2) % #PACKS) + 1]
			if self:ext_exists(candidate .. "/Headshot.wav") then
				found = candidate
				break
			end
		end
		want = found
	end

	self._ext_pack = want
	if want ~= "" then
		self:module_log(1, "voice pack:", want)
	else
		self:module_log(1, "voice pack: none (files are read from", self:ext_dir() .. ")")
	end
	return want
end

-- "Headshot.wav" -> "men1/Headshot.wav" (or unchanged when no pack is selected)
function KillStreak:ext_rel(name)
	local pack = self:ext_pack()
	if pack and pack ~= "" then
		return pack .. "/" .. name
	end
	return name
end

-- returns the path relative to sfx/ when the file exists, otherwise nil
function KillStreak:ext_file(name)
	if not name or name == "" then
		return nil
	end
	local rel = self:ext_rel(name)
	if self:ext_exists(rel) then
		return rel
	end
	return nil
end

function KillStreak:ext_start()
	if state.started then
		return state.ok
	end
	state.started = true

	if self.opt.sfx_mode == "wwise" then
		state.ok = false
		return false
	end

	if not (io and io.open and os and os.execute) then
		state.ok = false
		self:module_log(1, "external sounds need the lua io library, using wwise instead")
		return false
	end

	-- the volume has to be on disk before the helper starts, and it has to be rewritten
	-- on every launch: the helper keeps running across levels, so a value changed while
	-- it was alive must not be lost when a level reloads this module
	pcall(function() self:ext_push_volume() end)

	local vbs = self:ext_base() .. "tools/sfx_launch.vbs"
	local f = io.open(vbs, "r")
	if not f then
		state.ok = false
		self:module_log(1, "sound helper not installed (", vbs, "), using wwise instead")
		return false
	end
	f:close()

	-- the helper survives a level change (it exits when the GAME exits), so a fresh
	-- level must reuse it instead of launching another one - launching one means a
	-- console window that drags the player out of the game
	if self:ext_alive() then
		state.ok = true
		self:module_log(1, "external sound helper already running, reusing it")
		return true
	end

	-- the queue has to start empty, otherwise sounds queued in a previous session
	-- would be replayed on launch
	local qf = io.open(self:ext_queue_path(), "w")
	if qf then
		qf:close()
	end

	local code = os.execute('wscript //nologo "' .. vbs .. '"')
	state.ok = true
	self:module_log(1, "external sound helper started:", tostring(code))
	return true
end

-- candidate files for one event, best match first.
-- a streak of 2 or more always wins over the kill type, exactly like the pd2 mod:
-- any kill that continues a streak is announced by its multikill line.
function KillStreak:sfx_candidates(kind, streak)
	local opt = self.opt
	local names = {}

	local n = math.floor(tonumber(streak) or 0)
	local per = opt.sfx_multikill
	if per and per ~= "" and n >= 2 then
		local maxn = math.floor(tonumber(opt.sfx_max_streak) or 8)
		if maxn < 2 then
			maxn = 2
		end
		if n > maxn then
			n = maxn
		end
		local ok, name = pcall(string.format, per, n)
		if ok and name and name ~= "" then
			names[#names + 1] = name
		end
	end

	local kind_name
	if kind == "headshot" then
		kind_name = opt.sfx_headshot
	elseif kind == "melee" then
		kind_name = opt.sfx_melee
	elseif kind == "civilian" then
		kind_name = opt.sfx_civilian
	end
	if kind_name and kind_name ~= "" then
		names[#names + 1] = kind_name
	end

	if opt.sfx_single and opt.sfx_single ~= "" then
		names[#names + 1] = opt.sfx_single
	end

	return names
end

-- kind: "kill" | "headshot" | "melee" | "multikill" | "civilian"
function KillStreak:ext_sound_for(kind, streak)
	for _, name in ipairs(self:sfx_candidates(kind, streak)) do
		local rel = self:ext_file(name)
		if rel then
			return rel
		end
	end
	return nil
end

function KillStreak:ext_play(name)
	if not name or name == "" then
		return false
	end
	if not self:ext_start() then
		return false
	end

	local f = io.open(self:ext_queue_path(), "a")
	if not f then
		state.ok = false
		self:module_log(1, "could not write the sound queue")
		return false
	end
	f:write(name, "\n")
	f:close()

	self:log("external sound queued:", name)
	return true
end

-- > launch as early as possible ------------------------------------------------
-- starting a process from inside a running level opens a console window and drags
-- the player back to the desktop. the helper keeps running until the GAME exits, so
-- starting it once while the game is still booting is enough: every later level finds
-- a fresh heartbeat in tmp/server.heartbeat and skips the launch completely.
do
	local opt = KillStreak.opt
	if opt and opt.enable_sound ~= false and opt.sfx_mode ~= "wwise" and opt.sfx_mode ~= "off" then
		pcall(function() KillStreak:ext_start() end)
	end
end
