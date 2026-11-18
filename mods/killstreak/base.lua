-- Kill Streak for PAYDAY The Heist
-- Port of the PAYDAY 2 "KillStreak" mod by Eysent (kill icons + kill-confirm sounds).
--
-- Structure (DAHM module):
--   base.lua        module definition + config
--   main.lua        icon panel, animation, streak state, sound, texture registration
--   copdamage.lua   kill detection (hooks CopDamage damage/sync functions)
--   hudmanager.lua  workspace lifetime (rebuilt when the overlay gui changes)

local module = DMod:new("killstreak", {
	name = { english = "Kill Streak" },
	abbr = "KST",
	author = { "ported from the PD2 mod by Eysent" },
	category = "hud",
	description = "Shows kill / multikill / headshot icons in the middle of the screen and plays a short kill-confirm stinger. Port of the PAYDAY 2 KillStreak mod.",
})

local defaults = {
	enabled              = true,
	-- menu language: "auto" follows the game, "zh" / "en" / "ru" force one
	language             = "auto",

	-- icon
	scale                = 2.30,   -- 1.0 = 410 px
	offset_x             = 0.00,   -- horizontal offset from the centre (fraction of the width)
	offset_y             = 0.20,   -- vertical offset from the screen centre (fraction of the height)
	alpha                = 1.00,

	-- timing (seconds)
	anim_time            = 0.34,   -- 20 帧出场动画的时长(60fps, 和素材一致)
	pop_time             = 0.09,   -- 淡入动画 (只在 fx_enabled = false 时生效)
	hold_time            = 0.57,   -- 动画放完后图标的停留时长
	fade_time            = 0.55,   -- 淡出
	streak_window        = 2.50,   -- kills closer together than this keep the streak going

	-- 出场动画: 动画已经烘进每一帧素材里了
	--   true  = 播完整的 20 帧(闪光/砸入/抖动)
	--   false = 只显示落定的那一帧, 配一个 pop_time 的短淡入
	-- 下面两项是给入场额外叠加的位移/缩放, 默认中性(完全按素材原样播放)
	fx_enabled           = true,
	fx_drop_scale        = 1.00,   -- start size of the intro (1.0 = no extra zoom)
	fx_drop_lift         = 0.00,   -- how far above the resting spot it starts

	-- sound
	enable_sound         = true,
	sfx_mode             = "auto",     -- auto: external files first, wwise event as fallback
	                                   -- external: only external files, wwise: only in-game events, off
	sfx_dir              = "sfx",      -- folder with the .wav files, relative to the mod
	voice_pack           = "women1",   -- men1..men4 women1..women5, "" = files in sfx/,
	                                   -- "random" = pick one of the installed packs
	sfx_volume           = 1.00,       -- kill sound volume, 0.00 .. 1.00 (0 = muted)
	                                   -- applied to the external player, not the game mix
	sfx_headshot         = "Headshot.wav",     -- headshot kill
	sfx_multikill        = "MultiKill_%d.wav", -- %d = streak, clamped to sfx_max_streak
	sfx_max_streak       = 8,          -- anything above this reuses the last multikill line
	sfx_melee            = "Knifekill.wav",     -- melee kill
	sfx_single           = "",         -- plain single kill, "" = silent (same as the pd2 mod)
	sfx_civilian         = "",         -- civilian kill, "" = same as sfx_single
	sfx_round_start      = "Round_Start.wav",  -- used when play_round_start is on
	play_round_start     = false,      -- announce the start of a level with the voice pack
	sound_bank           = "hud",                -- wwise source name used by the game hud
	sound_kill           = "",                   -- wwise event for a single kill ("" = none)
	sound_headshot       = "stinger_levelup",    -- wwise event on a headshot kill
	sound_multikill      = "stinger_levelup",    -- wwise event on the 2nd..nth kill in a streak
	sound_civilian       = "",                   -- wwise event for a civilian kill ("" = sound_kill)
	sound_cooldown       = 0.12,                 -- kills closer together than this count as one burst
	                                             -- (only an explosion actually waits this long,
	                                             --  a plain shot is announced after ~30 ms)

	-- misc
	count_civilian_kills = false,  -- civilians do not count into the streak
	mute_civilian_sound  = false,  -- leave the vanilla civilian cue alone
	texture              = "guis/textures/killstreak/killicons",
	test_on_start        = false,   -- show one icon when a level starts (diagnostic)
	debug                = false,   -- write kill detection info to logs/main.log
}

-- module:path() is only set after base.lua has been evaluated, ModPath is the
-- folder the definition was loaded from and always ends with a slash
local mod_path = ModPath or (module.path and module:path()) or ""
if mod_path ~= "" and mod_path:sub(-1) ~= "/" then
	mod_path = mod_path .. "/"
end

local opt = {}
for key, value in pairs(defaults) do
	opt[key] = value
end

do
	local chunk = loadfile(mod_path .. "config.lua")
	if chunk then
		local ok, cfg = pcall(chunk)
		if ok and type(cfg) == "table" then
			for key, value in pairs(cfg) do
				if defaults[key] == nil then
					module:log(2, "load_config", "unknown config key:", tostring(key))
				else
					opt[key] = value
				end
			end
		else
			module:log(0, "load_config", "config.lua contains errors:", tostring(cfg))
		end
	else
		module:log(1, "load_config", "no config.lua found, using defaults")
	end
end

_G.KillStreak = _G.KillStreak or {}
KillStreak.opt = opt
KillStreak.path = mod_path

-- > in game settings ----------------------------------------------------------
-- the options in "options -> mods -> kill streak" are stored in the dahm config
-- database (user.lua) and are saved between sessions. config.lua keeps working as
-- the baseline: its values become the defaults the menu shows and resets to.
local MENU_KEYS = {
	"enabled",
	"language",
	"voice_pack",
	"sfx_volume",
	"scale",
	"alpha",
	"offset_x",
	"offset_y",
	"streak_window",
	"play_round_start",
	"fx_enabled",
}

KillStreak.menu_keys = MENU_KEYS

-- snapshot of the config.lua values, used as the menu defaults
KillStreak.defaults = {}
for key, value in pairs(opt) do
	KillStreak.defaults[key] = value
end

local config_prefix = module:config_prefix() or ""

-- the menu stores keys as "killstreak_<key>"; module:conf() adds that prefix
-- itself, so the rest of the mod can keep asking for the short name
function KillStreak:short_key(key)
	if config_prefix ~= "" and type(key) == "string" and key:sub(1, #config_prefix) == config_prefix then
		return key:sub(#config_prefix + 1)
	end
	return key
end

-- re-read the values the player set in the menu. called when a level starts, so a
-- value saved in a previous session is picked up even if this module was loaded
-- before the settings database.
function KillStreak:refresh_settings()
	for i = 1, #MENU_KEYS do
		local key = MENU_KEYS[i]
		local ok, value = pcall(function() return module:conf(key) end)
		if ok and value ~= nil then
			self.opt[key] = value
		end
	end
end

-- a menu value changed: adopt it right away
function KillStreak:apply_setting(key, value)
	key = self:short_key(key)
	if not key or value == nil then
		return
	end
	self.opt[key] = value

	-- always logged: "the menu does nothing" is otherwise very hard to diagnose
	pcall(function() self:module_log(1, "setting", tostring(key) .. "=" .. tostring(value)) end)

	if key == "enabled" and not value then
		-- drop the icon that may be on screen and forget the running group
		pcall(function() self:destroy_panel() end)
		self._burst = nil
		self._streak = 0
	elseif key == "voice_pack" then
		-- resolve the folder again, the cached one belongs to the old pack
		self._ext_pack = nil
	elseif key == "sfx_volume" then
		-- hand it to the resident player, which rescales on its next poll (~100 ms)
		if self.ext_push_volume then
			pcall(function() self:ext_push_volume() end)
		end
	elseif key == "language" then
		-- re-register the menu strings in the new language (the menu include only
		-- exists once the options page was opened, so this is nil-safe)
		if self.refresh_localization then
			pcall(function() self:refresh_localization() end)
		end
	end
end

-- seed the config database so module:conf() has a value before the menu was ever
-- opened (the defaults are only registered when the menu options are loaded)
for i = 1, #MENU_KEYS do
	local key = MENU_KEYS[i]
	local ok, err = pcall(function()
		module:add_config_option(config_prefix .. key, KillStreak.defaults[key])
	end)
	if not ok then
		module:log(1, "settings", "could not register " .. key .. ": " .. tostring(err))
	end
end

KillStreak:refresh_settings()

-- > hooks ----------------------------------------------------------------------
module:register_include("main")
module:register_include("extsound")
module:register_include("modoptions", { type = "menu_options", lazy_load = true })
module:hook_post_require("lib/units/enemies/cop/copdamage", "copdamage")
module:hook_post_require("lib/managers/hudmanager", "hudmanager")

return module
