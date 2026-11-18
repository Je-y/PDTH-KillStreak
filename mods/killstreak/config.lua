-- Kill Streak :: configuration
-- 击杀图标 / 击杀音效 设置。改完保存即可，下次进游戏生效。
-- 这是一个普通 Lua 表，注意每行末的逗号。

return {
	enabled              = true,   -- 总开关
	language             = "auto", -- 菜单语言: "auto" 跟随游戏, 也可以写 "zh" / "en" / "ru"

	-- 图标 ------------------------------------------------------------------
	scale                = 2.30,   -- 图标大小，1.0 = 410 像素的画布（图标本体约 128 像素）
	offset_x             = 0.00,   -- 图标相对屏幕中心的水平偏移（屏幕宽度的比例，负=向左）
	offset_y             = 0.20,   -- 图标相对屏幕中心下移多少（屏幕高度的比例）
	alpha                = 1.00,   -- 不透明度 0~1

	-- 注意：以上几项（以及 enabled / voice_pack / play_round_start）在游戏里
	-- 的「选项 → 模组 → KILL STREAK」里也能调，菜单里改过的值优先于这里。
	-- 这里的值只在菜单没有设置过时生效（也就是菜单里「重置默认」会回到的值）。

	-- 时间（秒） ------------------------------------------------------------
	anim_time            = 0.34,   -- 20 帧出场动画时长（60fps，和素材帧率一致）
	pop_time             = 0.09,   -- 淡入时长（只在 fx_enabled = false 时生效）
	hold_time            = 0.57,   -- 动画播完后图标停留多久
	fade_time            = 0.55,   -- 淡出时长
	streak_window        = 2.50,   -- 两次击杀间隔超过这个时间就连杀数清零

	-- 图标出现到消失：0.34 + 0.57 + 0.55 ≈ 1.46 秒（约 87 帧 @60fps）

	-- 出场动画 --------------------------------------------------------------
	-- 动画已经烘进每一帧素材里了：
	--   fx_enabled = true  播完整的 20 帧（闪光、砸入、抖动）
	--   fx_enabled = false 只显示落定后的那一帧，配一个 pop_time 的短淡入
	-- 下面两项是给入场额外叠加的位移/缩放，默认中性（完全按素材原样播放）。
	fx_enabled           = true,
	fx_drop_scale        = 1.00,   -- 入场起始大小（1.0 = 不额外缩放）
	fx_drop_lift         = 0.00,   -- 从上方多高开始落（图标尺寸的比例）

	-- 音效：外部音频（推荐） ------------------------------------------------
	enable_sound         = true,
	sfx_mode             = "auto",    -- auto     = 有 wav 就播 wav，没有就用游戏内音效
	                                  -- external = 只播 wav（文件缺失就静音）
	                                  -- wwise    = 只用游戏自带音效
	                                  -- off      = 完全静音
	sfx_dir              = "sfx",     -- wav 所在文件夹（相对模组根目录）

	-- 语音包 ---------------------------------------------------------------
	-- 可用的包（对应 sfx/ 下的子文件夹）：
	--   men1   潜伏者      men2   飞虎队      men3   保卫者      men4   啊giao
	--   women1 猎狐者匪    women2 猎狐者警    women3 美国妞
	--   women4 毛妹        women5 夏日之兰
	--   ""     不分子文件夹，直接用 sfx/ 根目录里的文件
	--   "random" 每次进游戏随机挑一个已安装的包
	voice_pack           = "women1",

	-- 击杀语音音量 0.00 ~ 1.00（0 = 静音）
	-- 只作用于外部播放器播的语音，不影响游戏本身的混音和其他声音
	sfx_volume           = 1.00,

	-- 各情况的音效文件（相对 voice_pack 文件夹） ---------------------------
	sfx_headshot         = "Headshot.wav",     -- 爆头击杀
	sfx_multikill        = "MultiKill_%d.wav", -- 连杀，%d 会被替换成连杀数（2~8）
	sfx_max_streak       = 8,          -- 连杀超过这个数，一直用最后一段（8 连杀）
	sfx_melee            = "Knifekill.wav",     -- 近战击杀
	sfx_single           = "",         -- 普通单杀，"" = 不播（和 PD2 原模组一致）
	                                   -- 想让单杀也出声，可填 "Knifekill.wav" 等
	sfx_civilian         = "",         -- 击杀平民，"" = 同 sfx_single
	sfx_round_start      = "Round_Start.wav",  -- 开局语音
	play_round_start     = false,      -- 进关时播一次开局语音

	-- 音效：游戏内 Wwise 事件（外部音频不可用时的兜底） --------------------
	sound_bank           = "hud",                 -- Wwise 音源名（游戏 HUD 用的那个）
	sound_kill           = "",                    -- 普通击杀用的事件名，"" = 不播
	sound_headshot       = "stinger_levelup",     -- 爆头
	sound_multikill      = "stinger_levelup",     -- 连杀
	sound_civilian       = "",                    -- 击杀平民的事件名，"" = 同 sound_kill
	sound_cooldown       = 0.12,      -- 间隔小于这个时间的击杀算"同一批"（只有爆炸会等满这么久，
	                                  -- 普通枪杀 30 毫秒内就出声，避免听起来慢半拍）

	-- 其它 ------------------------------------------------------------------
	count_civilian_kills = false,  -- 击杀平民不计入连杀、不弹图标、不播音效（游戏原声保留）
	                               -- 想统计平民击杀时改成 true，下面的 mute 才有意义
	mute_civilian_sound  = false,  -- 仅在 count_civilian_kills = true 时生效：
	                               -- 掐掉平民死亡时游戏原本那声提示音（释放人质的原声不受影响）
	test_on_start        = false,  -- 进关时先弹一个图标（诊断用，正常游玩保持关闭）
	texture              = "guis/textures/killstreak/killicons",
	debug                = false,  -- 把击杀判定信息写进 logs/main.log（排查用）
}
