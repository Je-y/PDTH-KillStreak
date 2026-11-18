-- Kill Streak :: in game settings
--
-- loaded lazily: only when the player opens "options -> mods -> kill streak".
-- every option is stored in the dahm config database (user.lua) and survives a
-- restart; config.lua still provides the baseline that the menu shows and resets to.
--
-- values are pushed into KillStreak.opt immediately by on_value_changed, so a
-- change takes effect without a restart (the icon panel is rebuilt on every kill,
-- so size / alpha / position are read fresh each time).

local module = ... or D:module("killstreak")
local KillStreak = _G.KillStreak

if not KillStreak then
	return
end

local defaults = KillStreak.defaults or KillStreak.opt

-- the menu hands back the full config key ("killstreak_scale"), apply_setting()
-- strips the prefix again
local function on_changed(config_key, value)
	pcall(function() KillStreak:apply_setting(config_key, value) end)
	if KillStreak:short_key(config_key) == "language" then
		-- the labels were resolved when the page was built, so rebuild it
		pcall(function() KillStreak:refresh_localization() end)
		pcall(function()
			managers.menu:open_node("mods_options_entry", { module, nil, "menu_options" })
		end)
	end
end

-- the folder names under sfx/, the reference mod's character names
local PACK_CHOICES = {
	{ "men1",   "潜伏者" },
	{ "men2",   "飞虎队" },
	{ "men3",   "保卫者" },
	{ "men4",   "啊giao" },
	{ "women1", "猎狐者匪" },
	{ "women2", "猎狐者警" },
	{ "women3", "美国妞" },
	{ "women4", "毛妹" },
	{ "women5", "夏日之兰" },
	{ "random", "随机" },
	{ "",       "自定义（直接读 sfx 根目录）" },
}

-- > options --------------------------------------------------------------------
-- the language row goes first: someone who cannot read the page cannot find it
module:add_menu_option("killstreak_language", {
	type = "multi_choice",
	text_id = "killstreak_option_language",
	help_id = "killstreak_option_language_help",
	-- written in their own script so the choice is readable in any language
	choices = {
		{ "auto", "Auto" },
		{ "zh",   "中文" },
		{ "en",   "English" },
		{ "ru",   "Русский" },
	},
	default_value = defaults.language or "auto",
	on_value_changed = on_changed,
})

module:add_menu_option("killstreak_divider_language", { type = "divider" })

module:add_menu_option("killstreak_enabled", {
	type = "boolean",
	text_id = "killstreak_option_enabled",
	help_id = "killstreak_option_enabled_help",
	default_value = defaults.enabled ~= false,
	on_value_changed = on_changed,
})

module:add_menu_option("killstreak_divider_voice", { type = "divider" })

module:add_menu_option("killstreak_voice_pack", {
	type = "multi_choice",
	text_id = "killstreak_option_voice_pack",
	help_id = "killstreak_option_voice_pack_help",
	choices = PACK_CHOICES,
	default_value = defaults.voice_pack or "women1",
	on_value_changed = on_changed,
})

module:add_menu_option("killstreak_sfx_volume", {
	type = "slider",
	text_id = "killstreak_option_volume",
	help_id = "killstreak_option_volume_help",
	min = 0.00, max = 1.00, step = 0.05,
	value_accuracy = 2, show_value = true,
	default_value = defaults.sfx_volume or 1.00,
	on_value_changed = on_changed,
})

module:add_menu_option("killstreak_divider_icon", { type = "divider" })

module:add_menu_option("killstreak_scale", {
	type = "slider",
	text_id = "killstreak_option_scale",
	help_id = "killstreak_option_scale_help",
	min = 0.15, max = 3.00, step = 0.05,
	value_accuracy = 2, show_value = true,
	default_value = defaults.scale or 2.30,
	on_value_changed = on_changed,
})

module:add_menu_option("killstreak_alpha", {
	type = "slider",
	text_id = "killstreak_option_alpha",
	help_id = "killstreak_option_alpha_help",
	min = 0.10, max = 1.00, step = 0.05,
	value_accuracy = 2, show_value = true,
	default_value = defaults.alpha or 1.00,
	on_value_changed = on_changed,
})

module:add_menu_option("killstreak_offset_y", {
	type = "slider",
	text_id = "killstreak_option_offset_y",
	help_id = "killstreak_option_offset_y_help",
	min = -0.30, max = 0.45, step = 0.01,
	value_accuracy = 2, show_value = true,
	default_value = defaults.offset_y or 0.20,
	on_value_changed = on_changed,
})

module:add_menu_option("killstreak_offset_x", {
	type = "slider",
	text_id = "killstreak_option_offset_x",
	help_id = "killstreak_option_offset_x_help",
	min = -0.45, max = 0.45, step = 0.01,
	value_accuracy = 2, show_value = true,
	default_value = defaults.offset_x or 0.0,
	on_value_changed = on_changed,
})

module:add_menu_option("killstreak_divider_streak", { type = "divider" })

module:add_menu_option("killstreak_streak_window", {
	type = "slider",
	text_id = "killstreak_option_streak_window",
	help_id = "killstreak_option_streak_window_help",
	min = 0.5, max = 10.0, step = 0.1,
	value_accuracy = 1, show_value = true,
	default_value = defaults.streak_window or 2.5,
	on_value_changed = on_changed,
})

module:add_menu_option("killstreak_divider_misc", { type = "divider" })

module:add_menu_option("killstreak_fx_enabled", {
	type = "boolean",
	text_id = "killstreak_option_fx",
	help_id = "killstreak_option_fx_help",
	default_value = defaults.fx_enabled ~= false,
	on_value_changed = on_changed,
})

module:add_menu_option("killstreak_play_round_start", {
	type = "boolean",
	text_id = "killstreak_option_round_start",
	help_id = "killstreak_option_round_start_help",
	default_value = defaults.play_round_start == true,
	on_value_changed = on_changed,
})

module:add_menu_option("killstreak_divider_reset", { type = "divider" })

-- a button: "link" + a callback name, the framework calls
-- MenuCallbackHandler:<callback>(item) when the row is selected
module:add_menu_option("killstreak_reset_defaults", {
	type = "link",
	text_id = "killstreak_option_reset",
	help_id = "killstreak_option_reset_help",
	callback = "killstreak_reset_defaults",
})

-- > restore defaults ----------------------------------------------------------
-- writes the config.lua baseline back into every key this menu owns, then
-- reopens the page so the rows show the restored values again
local CONFIG_PREFIX = module:config_prefix() or ""

local function reset_to_defaults()
	local keys = KillStreak.menu_keys or {}
	for i = 1, #keys do
		local key = keys[i]
		local config_key = CONFIG_PREFIX .. key
		local value = KillStreak.defaults[key]
		-- live value used by the mod right now
		pcall(function() D:set_config_option(config_key, value, true) end)
		-- and the copy that is written to disk, otherwise the old values come back
		pcall(function() module:update_persist_setting(config_key, value, true) end)
	end

	pcall(function() KillStreak:refresh_settings() end)
	pcall(function() KillStreak:apply_setting("enabled", KillStreak.opt.enabled) end)
	pcall(function() KillStreak:apply_setting("voice_pack", KillStreak.opt.voice_pack) end)
	-- the volume lives in the resident player, not in this module: push it again or
	-- the restored value would only reach the helper on the next level
	pcall(function() KillStreak:apply_setting("sfx_volume", KillStreak.opt.sfx_volume) end)

	-- the labels were built with the old language, re-register them before the
	-- page is rebuilt
	pcall(function() KillStreak:refresh_localization() end)

	-- the node was built with the old values, rebuild it from scratch
	pcall(function()
		managers.menu:open_node("mods_options_entry", { module, nil, "menu_options" })
	end)
end

local MenuCallbackHandler = rawget(_G, "MenuCallbackHandler")
if not MenuCallbackHandler then
	-- not a global in some builds, ask the framework for it
	local ok, cls = pcall(function() return module:hook_class("MenuCallbackHandler") end)
	if ok then
		MenuCallbackHandler = cls
	end
end

if MenuCallbackHandler then
	function MenuCallbackHandler:killstreak_reset_defaults(item)
		pcall(reset_to_defaults)
	end
else
	module:log(1, "killstreak", "MenuCallbackHandler not found, the reset button will do nothing")
end

-- > localization ---------------------------------------------------------------
-- the whole page exists in three languages. with language = "auto" the game picks
-- its own (chinese / russian, anything else falls back to english); picking one
-- explicitly writes that text into every slot, so the page shows it whatever
-- language the game itself runs in.
local L = {
	killstreak_option_language = {
		en = "Menu language",
		zh = "菜单语言",
		ru = "Язык меню",
	},
	killstreak_option_language_help = {
		en = "Language of this settings page. \"Auto\" follows the game's own language.",
		zh = "设置页显示的语言。选\"自动\"就跟随游戏语言。",
		ru = "Язык этой страницы настроек. «Авто» — как в игре.",
	},

	killstreak_option_enabled = {
		en = "Enable kill icons and kill sounds",
		zh = "启用击杀图标与击杀语音",
		ru = "Включить иконки и звуки убийств",
	},
	killstreak_option_enabled_help = {
		en = "Master switch. When off, no icons are shown and no kill sounds are played.",
		zh = "总开关。关闭后不显示击杀图标，也不播放击杀语音。",
		ru = "Главный переключатель. Когда выключено, иконки не показываются и звуки убийств не играют.",
	},

	killstreak_option_voice_pack = {
		en = "Kill sound voice pack",
		zh = "击杀语音角色",
		ru = "Набор голосов убийств",
	},
	killstreak_option_voice_pack_help = {
		en = "Which character announces your kills. Every pack is a folder under mods/killstreak/sfx/. \"Random\" picks one per session.",
		zh = "选择播报击杀的角色。每个语音包是 mods/killstreak/sfx/ 下的一个文件夹。\"随机\" 每次进游戏换一个；\"自定义\" 直接读 sfx 根目录里的文件。",
		ru = "Какой персонаж озвучивает ваши убийства. Каждый набор — папка в mods/killstreak/sfx/. «Случайно» выбирает набор заново каждую сессию.",
	},

	killstreak_option_volume = {
		en = "Kill sound volume",
		zh = "击杀语音音量",
		ru = "Громкость звуков убийств",
	},
	killstreak_option_volume_help = {
		en = "Volume of the kill voice lines. Only affects the sounds this mod plays, not the rest of the game's mix. 0 = silent.",
		zh = "击杀提示音的音量。只影响本模组播放的语音，不影响游戏本身的其他声音。0 = 静音。",
		ru = "Громкость озвучки убийств. Влияет только на звуки этого мода, а не на общий микс игры. 0 — без звука.",
	},

	killstreak_option_scale = {
		en = "Icon size",
		zh = "击杀图标大小",
		ru = "Размер иконки",
	},
	killstreak_option_scale_help = {
		en = "Scale of the kill icon. 1.00 is about 256 pixels on a 1080p screen, 3.00 is about 768.",
		zh = "击杀图标的缩放。1.00 在 1080p 下约为 256 像素，拉到 3.00 约为 768 像素。",
		ru = "Масштаб иконки убийства. 1.00 — примерно 256 пикселей на экране 1080p, 3.00 — примерно 768.",
	},

	killstreak_option_alpha = {
		en = "Icon opacity",
		zh = "击杀图标透明度",
		ru = "Непрозрачность иконки",
	},
	killstreak_option_alpha_help = {
		en = "How opaque the kill icon is drawn.",
		zh = "击杀图标的不透明度。",
		ru = "Насколько непрозрачной рисуется иконка убийства.",
	},

	killstreak_option_offset_y = {
		en = "Icon vertical position",
		zh = "击杀图标垂直位置",
		ru = "Положение иконки по вертикали",
	},
	killstreak_option_offset_y_help = {
		en = "Vertical offset from the centre of the screen, as a fraction of the screen height. Negative moves it up.",
		zh = "相对屏幕中心的垂直偏移（占屏幕高度的比例）。负数向上移。",
		ru = "Смещение от центра экрана по вертикали в долях высоты экрана. Отрицательное значение поднимает иконку.",
	},

	killstreak_option_offset_x = {
		en = "Icon horizontal position",
		zh = "击杀图标水平位置",
		ru = "Положение иконки по горизонтали",
	},
	killstreak_option_offset_x_help = {
		en = "Horizontal offset from the centre of the screen, as a fraction of the screen width. Negative moves it left.",
		zh = "相对屏幕中心的水平偏移（占屏幕宽度的比例）。负数向左移。",
		ru = "Смещение от центра экрана по горизонтали в долях ширины экрана. Отрицательное значение сдвигает влево.",
	},

	killstreak_option_fx = {
		en = "Entry animation",
		zh = "出场动画",
		ru = "Анимация появления",
	},
	killstreak_option_fx_help = {
		en = "Plays the 20 frame entry animation of the icon set (flash, slam, wobble). Off = the icon is shown as its settled frame with a short fade in.",
		zh = "播放图标素材自带的 20 帧出场动画（闪光、砸入、抖动）。关掉则直接显示落定后的那一帧，配一个短淡入。",
		ru = "Проигрывает 20-кадровую анимацию появления (вспышка, удар, дрожь). Выкл. — иконка сразу показывается в конечном положении с коротким проявлением.",
	},

	killstreak_option_round_start = {
		en = "Announce the start of a level",
		zh = "进关时播报开局语音",
		ru = "Объявлять начало уровня",
	},
	killstreak_option_round_start_help = {
		en = "When enabled, the voice pack says its round start line as soon as the level begins.",
		zh = "开启后，每关开始时播放该角色语音包里的开局语音。",
		ru = "Если включено, набор голосов произносит вступительную фразу в начале каждого уровня.",
	},

	killstreak_option_streak_window = {
		en = "Streak timeout",
		zh = "连杀中断时间",
		ru = "Тайм-аут серии",
	},
	killstreak_option_streak_window_help = {
		en = "How many seconds may pass between two kills before the streak is reset. Raise it to keep a streak alive through slow parts of a fight.",
		zh = "两次击杀之间最多隔多久还算连杀（秒）。觉得连杀容易被打断就调大这个值。",
		ru = "Сколько секунд может пройти между двумя убийствами, прежде чем серия сбросится. Увеличьте, если серия часто прерывается.",
	},

	killstreak_option_reset = {
		en = "Restore default settings",
		zh = "恢复默认设置",
		ru = "Сбросить настройки",
	},
	killstreak_option_reset_help = {
		en = "Puts every option on this page back to the value from mods/killstreak/config.lua. Takes effect immediately.",
		zh = "把本页所有设置恢复成 mods/killstreak/config.lua 里的值，立即生效。",
		ru = "Возвращает все параметры этой страницы к значениям из mods/killstreak/config.lua. Применяется сразу.",
	},
}

-- every slot dahm knows about, so a language we do not ship falls back to english
-- instead of showing the raw id
local LANG_SLOTS = { "english", "chinese", "russian", "german", "french",
	"italian", "spanish", "korean", "japanese" }

local function build_strings()
	local sel = tostring(KillStreak.opt.language or "auto")
	local out = {}
	for id, t in pairs(L) do
		local tbl = {}
		if sel == "auto" then
			for i = 1, #LANG_SLOTS do
				local slot = LANG_SLOTS[i]
				if slot == "chinese" then
					tbl[slot] = t.zh or t.en
				elseif slot == "russian" then
					tbl[slot] = t.ru or t.en
				else
					tbl[slot] = t.en
				end
			end
		else
			local text = t[sel] or t.en
			for i = 1, #LANG_SLOTS do
				tbl[LANG_SLOTS[i]] = text
			end
		end
		out[id] = tbl
	end
	return out
end

local function register_localization()
	for id, tbl in pairs(build_strings()) do
		module:add_localization_string(id, tbl)
	end
end

-- add_localization_string only queues the string on the module. the localizer keeps
-- the first value it was given unless it is told to override, which is exactly why
-- switching language used to do nothing until a restart.
local function push_localization()
	for id, tbl in pairs(build_strings()) do
		pcall(function() D.Localizer:add_localization_string(id, tbl, true) end)
	end
end

register_localization()

function KillStreak:refresh_localization()
	pcall(register_localization)
	pcall(push_localization)
end
