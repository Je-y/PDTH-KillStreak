Kill Streak — 击杀图标 & 击杀语音（PAYDAY The Heist 移植版）
================================================================

把 PAYDAY 2 的 "kill streak" 模组搬到 PAYDAY The Heist：
屏幕中央弹出击杀提示图标，并按情况播放击杀语音。

图标和语音都取自参考模组：图标是它那套 9 帧的星形徽章 / 金色翅膀 / 骷髅，
音频是它的角色语音（已全部转成这个游戏能直接播的 wav）：

  men1   潜伏者      men2   飞虎队      men3   保卫者      men4   啊giao
  women1 猎狐者匪    women2 猎狐者警    women3 美国妞
  women4 毛妹        women5 夏日之兰

游戏内设置
----------
进游戏主菜单：选项 → 模组 →（模组列表里选 KILL STREAK），可以调：

  菜单语言                      Auto / 中文 / English / Русский，切换立即生效
  启用击杀图标与击杀语音        总开关，关掉后什么都不显示、不出声
  击杀语音角色                  9 个角色任选，外加「随机」和「自定义」
  击杀语音音量                  0.00 ~ 1.00（默认 1.00，0 = 静音），只影响击杀语音
  击杀图标大小                  0.15 ~ 3.00（默认 2.30）
  击杀图标透明度                0.10 ~ 1.00（默认 1.00）
  击杀图标垂直位置              -0.30 ~ 0.45（占屏幕高度的比例，负数向上）
  击杀图标水平位置              -0.45 ~ 0.45（占屏幕宽度的比例，负数向左）
  连杀中断时间                  0.5 ~ 10.0 秒，两次击杀隔超过这个时间就连杀清零
  出场动画                      播完图标素材自带的 20 帧（闪光+砸入+抖动），关掉只显示落定帧
  进关时播报开局语音            开关

整个设置页有中文 / English / Русский 三套文案（每行标题和它的帮助说明都是）。
「菜单语言」选 Auto 就跟随游戏语言（游戏是中文就中文，俄文就俄文，其他语言显示英文）；
也可以直接锁定成某一种，这时不管游戏本身是什么语言，页面都用你选的那一种。
切换后不用重启，页面会自己重建。
  恢复默认设置                  一键把上面所有项恢复成 config.lua 里的值

这些值存在 DAHM 的配置库里（存档，重启游戏不会丢）。
菜单里改过的值优先于 config.lua；config.lua 里的值就是菜单显示的默认值，
也是「恢复默认设置」会回到的值。

  图标大小 / 位置 / 透明度 / 连杀中断时间改完不用重启：图标每次击杀都会按当前值重建，
  连杀判定也是每次击杀时读一次这个值。
  「恢复默认设置」点完会立刻重开本页，所有数值当场刷成默认值。

  觉得连杀老是断：把「连杀中断时间」调到 4~6 秒即可。默认 2.5 秒。

安装 / 生效
-----------
模组在 mods/killstreak/，游戏启动时由 DAHM 框架自动加载。
改了 lua / 音频文件要**重启游戏**才生效（菜单里的调整不用）。

自检图标默认关闭（config.lua 的 test_on_start = false）。想排查时可以把它打开，
进关约 2 秒后会弹一次图标：
  · 看到准心图标        → 渲染链路正常，剩下的就看击杀能不能触发
  · 看到 "KILL" 文字    → 贴图没被引擎接受，走了文字降级（音效和逻辑照常）
  · 什么都没有          → 要么总开关关了，要么面板没建起来（看 logs/main.log 的 KST 行）
排查完记得再关掉。

文件
----
  base.lua        模块定义 + 读取配置 + 菜单项的默认值注册
  main.lua        图标面板、动画、连杀计数、音效派发、贴图注册
  extsound.lua    外部音频后端（语音包解析 + 队列 + 常驻播放助手）
  copdamage.lua   击杀判定（CopDamage 系列 + EnemyManager 兜底）
  hudmanager.lua  面板生命周期、每帧动画、进关自检、音效助手预热
  modoptions.lua  游戏内设置菜单（选项 → 模组 → KILL STREAK）
  config.lua      基线设置（一般不用改，菜单里都能调）
  sfx/            语音包，一个角色一个文件夹（见下）
  tools/          音效播放助手（PowerShell + VBS 启动器）
  tmp/            运行时的队列与日志（可随时删，游戏会重建）
  assets/killicons_a.texture / _b.texture / _c.texture       动画贴图（3 张 2048x2048，
                  每张 60 帧，一帧 256px；共 9 档 × 20 帧）
  assets/killicons_hi.texture                                落定帧高清图（2048x1536，
                  9 档各一格 512px，动画播完后切过去，放大也不糊）

图标素材
--------
素材是按连杀档位拍的动画：每档 20 帧，一共 9 档，都是带 alpha 的透明图。

  档位 0 / 1   1 杀爆头（金色 / 白色，约 30% 概率出金色，和 PD2 原模组一致）
  档位 2       1 杀身体
  档位 3 ~ 8   2 ~ 7 连杀（7 连杀及以上都用带金色翅膀的那一档）

贴图排布：一帧 256×256，一张 8 列 × 8 行 = 64 格（2048×2048），每张放 3 档
= 60 帧，所以一共 3 张（a / b / c）。两个方向都是 2 的幂，因为游戏自带的
最大贴图就是 2048。

  贴图 a   档位 0,1,2   （1 杀：金爆头 / 白爆头 / 身体）
  贴图 b   档位 3,4,5   （2,3,4 连杀）
  贴图 c   档位 6,7,8   （5,6,7 连杀）

裁切方式：所有档位、所有帧都用同一个固定方框（原画布坐标锚点 959,876，
边长 640）从原始 1920×1080 素材上裁下来，不做任何移动或逐帧对齐 ——
所以素材里"相对整张画布的位移/缩放"这类动画都被完整保留。
每一帧的 alpha 直接用原图的，没有抠底、没有羽化。

落定之后会切换成一张单独的高清图（assets/killicons_hi.texture）：动画那张必须裁
640 像素的框才装得下 1.9 倍放大的入场帧，落定图标只占其中三成，直接放大到 900 多
像素就发虚；高清图按落定尺寸裁 400 的框、每格 512 像素，放大后基本是原图分辨率。

默认大小 2.30（画布 941 像素，图标本体约 289 像素），透明度 1.00，在屏幕
中心偏下 20% 处显示；游戏内菜单可调 0.15 ~ 3.00。

出现动画与时长
--------------
出场动画（闪光、砸入、抖动）已经烘进素材的每一帧里，模组只负责按顺序播出来：

  0.00 ~ 0.34s   播完 20 帧出场动画（anim_time 0.34s = 60fps，和素材帧率一致）
  0.34 ~ 0.91s   停在最后一帧（hold_time 0.57s）
  0.91 ~ 1.46s   缩到 85% 并淡出（fade_time 0.55s）

也就是"图标出现到消失约 87 帧"，和参考素材的时间轴一致。

菜单里的「出场动画」关掉后，直接显示落定后的那一帧，配一个短淡入（pop_time）。

旧的程序化打击特效（缩放落下、压扁、抖动、白光、星角火花）参数都还在
config.lua 里，但默认值已经全部调成"中性"（不缩放/不压缩/不抖动/不闪），
因为动画本身在素材里了。config.lua 里只剩三项：fx_enabled（是否播完整 20 帧）、
fx_drop_scale / fx_drop_lift（给入场额外叠加的缩放和上移，默认中性 = 完全按素材播放）。


语音包 — 换角色
--------------
每个文件夹是一套完整的角色语音，结构都一样：

  sfx/women1/
    Headshot.wav              爆头
    Knifekill.wav             近战击杀
    MultiKill_2.wav … _8.wav  2~8 连杀
    Round_Start.wav           开局（进关播报开关打开时才播）

默认是 women1（猎狐者匪）。换角色直接用游戏内菜单，或者改 config.lua：

  voice_pack = "women1"    -- 猎狐者（默认）
  voice_pack = "men1"      -- 潜伏者
  voice_pack = "men3"      -- 保卫者
  voice_pack = "women2"    -- 猎狐者警
  voice_pack = "women5"    -- 夏日之兰
  voice_pack = "men4"      -- 啊giao
  voice_pack = "random"    -- 每次进游戏随机挑一个已安装的包
  voice_pack = ""          -- 不分子文件夹，直接读 sfx/ 根目录里的文件

什么时候播哪一段
----------------
  单发击杀（普通）     不播        ← 和 PD2 原模组一致
  爆头                 Headshot.wav
  近战击杀             Knifekill.wav
  连杀 2 ~ 8           MultiKill_2.wav … MultiKill_8.wav
  连杀 8 以上          一直用 MultiKill_8.wav（sfx_max_streak 可改）
  击杀平民             默认不统计，游戏原声不变
  进入关卡             默认不播；菜单里打开「进关播报」会播 Round_Start.wav

想让普通单杀也出声（原模组是静音的）：

  sfx_single = "Knifekill.wav"    -- 或者 Headshot.wav，随便挑一个

多杀（一枪几个）
----------------
同一瞬间的多次击杀算"一批"，**整批只会播一句**：这批结束（0.12 秒内没有新的
击杀）之后，按最终连杀数播一次 MultiKill_N。

所以一发霰弹放倒 5 个 = 一句 5 连杀，不会五句叠在一起变成噪音，也不会
"第一句刚说一半就被第二句打断"。

  批次的判定窗口就是 config.lua 里的 sound_cooldown（默认 0.12 秒）。

击杀平民
--------
默认**不统计平民**：击杀平民不弹图标、不播本模组的音效、不计入连杀，
游戏原本的提示音照常播放（和释放人质时听到的是同一个，这部分由游戏负责）。

  想统计平民：把 count_civilian_kills 改成 true。
  这时平民会走和条子一样的图标；如果不想听到游戏原本那声提示音，
  再把 mute_civilian_sound 改成 true（会掐掉平民死亡那个单位自己的音源，
  被放走的人质还活着，原声不受影响）。
  也可以单独用 sfx_civilian 给平民配一个音。

音频格式
--------
  统一 22050 Hz 单声道 16-bit PCM WAV，9 个包共 90 个文件，约 5.2 MB。

  换成你自己的音频：.wav 最稳（延迟最低）。.mp3 / .wma 走 Windows 媒体管线也能播，
  但第一次播放会慢一拍，连杀时可能听着不齐，建议统一转成 16-bit PCM WAV。

  注意原始 ogg 是"过载母带"（RMS 最高 1.09，三成采样超过满刻度），直接转 16bit 会
  爆音。转换时做了 -13 dBFS 归一化 + 峰值压到 0.95；men2 的多杀语音开头有 0.4 秒
  静音也裁掉了，否则听着像"延迟半秒"。自己换文件时建议先归一化到 RMS 0.2 左右。

音效是怎么播出来的（重要）
--------------------------
这个游戏的音频引擎（Wwise）只能播放已经烘焙进音库的事件，引擎没有
"载入这个 wav 给我播" 的接口，而本作的 hook（pdthhook / SuperBLT）也没带
PD2 那个 blt_xaudio 插件，所以没法把外部音频直接喂给游戏混音器。

于是模组用了一个不碰引擎的办法：
  1. 游戏启动时用 wscript 静默启动一个常驻的 PowerShell 小助手；
  2. 每次击杀往 tmp/queue.txt 里追加一行（例如 women1/Headshot.wav）；
  3. 助手每 8ms 看一眼这个文件，用 System.Media.SoundPlayer 异步播放。

击杀语音音量（菜单里那一项）是这么实现的：SoundPlayer 本身没有音量属性，直接调
系统音量又会把游戏和所有其他程序一起调小，所以助手在播放前把 wav 的 PCM 采样按
比例缩放（0.5 = 采样值减半），再交给 SoundPlayer。播放路径和延迟完全不变，
音量只作用于本模组。改音量后约 0.1 秒生效，不需要重启，也不需要重进关卡。
如果你装了别的程序改了这个游戏目录的权限导致助手无法编译缩放代码，
日志里会写 "volume scaling is unavailable"，这时会退回全音量播放。

关于那个一闪而过的黑色窗口：从游戏进程里启动任何程序都要经过 cmd，会短暂冒出
一个控制台窗口、把游戏顶到后台。所以助手只在**游戏启动时**启动一次，并且每 2 秒
往 tmp/server.heartbeat 写一个时间戳；之后每次进关模组都先读这个心跳，只要它还新鲜
就直接复用，绝不再启动第二次。也就是整个游戏会话只在启动那一下闪一次，进关卡、
换地图都不会再弹。

实测从写入到出声约 15~30ms，听感上和 PD2 基本一致。同一时刻只播一条语音，
新的会打断还没播完的旧语音（不然一梭子连杀会叠成一团）。
代价是声音走 Windows 混音器，不跟游戏内音量设置联动，也不会被游戏录像录进去。

不想用这套机制的话，把 config.lua 里 sfx_mode 改成 "wwise"，
就会退回用游戏自带的音效事件（stinger_levelup），只有内置音色。

表现
----
  · 普通击杀           → 六角星图标，亮第 1 个角（默认无语音）
  · 爆头（第一击）     → 骷髅图标（黄 / 白随机）+ Headshot
  · 近战击杀           → 六角星图标 + Knifekill
  · 连杀 2~5           → 只亮对应那个角（之前的灭掉）+ MultiKill_N
  · 连杀 6             → 六个角一起亮 + MultiKill_6
  · 连杀 7 以上        → 金色翅膀图标；语音 8 连杀之后一直用 MultiKill_8
  · 同时击杀多人       → 整批只播一句，按最终连杀数
  · 坦克等特殊敌人     → 和普通条子一样出图标（走 EnemyManager 兜底）
  · 平民               → 默认不统计，游戏原声不变（count_civilian_kills 可开）
  · 每次击杀重新计时，超过 2.5 秒没击杀就重新计数

调参
----
优先级：游戏内菜单（选项 → 模组） > config.lua。

  菜单可调：总开关、语音角色、图标大小 / 透明度 / 水平位置 / 垂直位置、
            连杀中断时间、进关播报、恢复默认设置。

config.lua 里仍然是全部参数，菜单没有覆盖到的都在这里：

  sfx_mode        auto / external / wwise / off（见上）
  sfx_headshot / sfx_melee / sfx_single / sfx_civilian   各情况的文件
  sfx_multikill   连杀模板，"MultiKill_%d.wav"，%d 会替换成连杀数
  sfx_max_streak  连杀上限（默认 8，超过就一直用第 8 段）
  sound_cooldown  多杀的"同一批"判定窗口（秒）
  streak_window   连杀中断时间（秒），菜单里也能调，默认 2.5
  hold_time       图标完全显示的时长（秒）
  fx_enabled      是否播完整 20 帧出场动画（菜单里就是这一项）
  fx_drop_scale / fx_drop_lift   入场额外叠加的缩放/上移，默认中性
  count_civilian_kills  统计平民击杀（默认关）
  mute_civilian_sound  仅在统计平民时生效：掐掉平民死亡时游戏原本那声（默认关）
  test_on_start   进关时弹一次自检图标
  debug           改成 true 后，每次击杀的判定过程都会写进 logs/main.log

排查
----
1) 图标问题：logs/main.log 里搜 "KST"。

  KST -- [killstreak] -- voice pack: women1
  KST -- [killstreak] -- panel created 256 960 702 (texture ok) [render]
  KST -- [killstreak] -- kill streak= 1 headshot= false civilian= false hit= bullet
  KST -- [killstreak-trace] -- kill counted (bullet, headshot=true, enemy=nil, tweak=cop)
  KST -- [killstreak-trace] -- kill counted (fallback enemy, tweak=tank)

  · 行尾的 [render] / [viewport] / [hud] 是坐标空间取自哪里；
    正常是 [render]。如果出现
      KST -- [killstreak] -- screen size mismatch: using 1920x1080, other sources say ...
    说明有来源不同步（切换分辨率后 HUD 里那份尺寸不会更新），已按实时值纠正。
  · 有 "kill ignored: ..."     → 判定没通过，后面写着原因
  · 有 "kill counted" 但没图标 → 渲染问题，或菜单里总开关被关了
  · 一条都没有                 → 模组没加载，看日志开头 "mods loaded"

2) 音效问题：mods/killstreak/tmp/sfx.log。

  [12:31:05.220] server started (pid 4242), base dir: ...
  [12:31:07.880] played: women1\Headshot.wav
  [12:31:07.885] missing sound file: ...\sfx\women1\MultiKill_9.wav

  · 没有 "server started"      → 助手没起来（PowerShell 被策略拦了 / tmp 没写权限）
  · 有 "played" 但听不到        → 系统音量，或音频设备被游戏独占
  · "missing sound file"       → 文件名 / 语音包文件夹和设置对不上
  · 完全没日志、log 里也没 KST → 模组没加载

3) 菜单里没有 KILL STREAK 这一项：确认模组是启用的（选项 → 模组 里的模组列表），
   并且 modoptions.lua 在 mods/killstreak/ 下。

关于手雷
--------
手雷专属的音效（Grenadekill.wav / Fireinthehole_Grenade.wav）和相关配置已经删掉了。
但**爆炸伤害的击杀检测保留着**：PDTH 本体其实带手雷 / M79 榴弹 / 跳雷的伤害脚本
（lib/units/weapons/grenades/、tripminebase.lua 都会调 damage_explosion），
删掉检测的话这些击杀会完全不计入连杀。现在它们按普通击杀处理：单发不播，
连杀照常播 MultiKill_N。

备份
----
在换上这套角色语音之前，另有一版用合成音效的旧版本，完整保留在：

  mods_backup/killstreak_synth_2026-10-23/        （可直接当模组用）
  mods_backup/killstreak_synth_2026-10-23.zip

两者不要同时放：那一版用的是 sfx/*.wav 平铺布局，目录名也还是 killstreak，
会跟当前这版抢同一个模块 id。想切回去就把新版的 mods/killstreak 挪走，
把备份那份放回 mods/ 下改成 killstreak。

实现说明（给想改代码的人）
--------------------------
· 菜单：DAHM 的 add_menu_option() 会把选项挂到「选项 → 模组 → <模组名>」节点下。
  改动通过 module:update_persist_setting 存进 DAHM 的持久化存档（Global），下次启动
  回填到玩家配置里，D:conf()/module:conf() 读的就是合并后的值。config.lua 提供默认值。
  菜单项注册在 modoptions.lua，通过
  register_include("modoptions", { type = "menu_options", lazy_load = true }) 懒加载，
  只有打开菜单时才读那个文件。
· 配置键统一带 killstreak_ 前缀（菜单里写全名，代码里用 module:conf("scale") 这种
  短名，module:conf 会自己补前缀）。base.lua 会用 add_config_option 先把默认值
  注册进配置库，保证菜单第一次打开前 D:conf() 也有值。
· 改动立即生效：每个菜单项的 on_value_changed 调 KillStreak:apply_setting()，
  直接改 KillStreak.opt；图标每次击杀都会重建，所以大小/位置/透明度天然跟着变，
  连杀窗口也是每次击杀读一次。关掉总开关时会顺便销毁当前面板、清掉连杀状态。
· 「恢复默认设置」是一个 type = "link" 的按钮，框架会调
  MenuCallbackHandler:killstreak_reset_defaults()：把 KillStreak.defaults（config.lua
  快照）写回每个 config 键 + 持久化存档，然后 managers.menu:open_node("mods_options_entry")
  重开本页，让控件显示新值（节点是在打开时按当前值构建的，不重开就会显示旧值）。
· 进关时 HUDManager:init 会 refresh_settings() 再读一遍配置，这样上个存档里
  存的值不会因为模组加载时机而丢失。
· 击杀判定：钩 CopDamage:damage_bullet / damage_melee / damage_explosion（自己打死的）
  和 sync_damage_*（网络同步的），用 self._dead 在调用前后的变化判断"这次伤害造成了死亡"。
  签名与 attack_data 字段（attacker_unit / col_ray.body）来自游戏自带字节码反汇编。
  伤害类型（bullet / melee）会一路传到 on_kill，决定用哪段语音。
· 平民走 CivilianDamage、坦克（bulldozer）走 TankCopDamage，它们都继承 CopDamage
  但会覆盖部分函数，所以额外挂了 EnemyManager:on_enemy_died / on_civilian_died 作为兜底：
  凡是 CopDamage 钩子没接到的死亡，这里再判一次。用每个伤害实例上的 _kst_dmg_t 时间戳
  去重，同一次死亡不会计两次。
· 敌人判定：CopDamage 只挂在敌人身上，所以单位身上 enemy 为 nil 时按"敌人"处理，
  只有明确 enemy == false / is_civilian 才跳过（早期版本要求 enemy 为真，导致所有击杀
  都被丢弃）。
· 爆头：body:name() == "head"（含 _head / head_ 前缀），再退回 is_head / is_headshot。
· 语音选择：sfx_candidates() 按优先级给候选——先看连杀（≥2 用 MultiKill_N，超出
  sfx_max_streak 就钉在上限），再看击杀类型，最后才退到 sfx_single；取第一个真实存在
  的文件。所以模板写错或文件缺失只是"这段不播"，不会报错也不会串音。
· 语音包：ext_pack() 解析 voice_pack，random 会用 Headshot.wav 探测每个包是否装好；
  包名不存在时不做回退（宁可没声也不混用两个角色的语音）。缓存按"相对 sfx/ 的完整
  路径"做 key，切换包后不会读到旧包的结果。
· 图标是参考模组 assets/killicons/streak.texture 里那 9 帧转过来的。原图是
  4089×450 的 DDS（9 帧 450×450，未压缩 BGRA），每帧重采样到 512 后按 4 列×3 行
  拼成 2048×1536 的 DDS（同样的未压缩 BGRA / top-down / 128 字节头），再用
  DB:create_entry 注册成 guis/textures/killstreak/killicons，用 panel:bitmap +
  texture_rect 取帧（矩形按 frame % 4 和 frame / 4 算，第 9 帧在第三行开头）。
  转换脚本留在 %TEMP%\port_icons.py，改了素材可以直接重跑。
· 坐标空间由 screen_size() 决定，顺序是 RenderSettings.resolution → 
  managers.viewport:get_safe_rect_pixels() → HUDManager._workspace_size → 1920x1080。
  以前直接用 HUDManager._workspace_size，但那份尺寸是**进关瞬间**抄下来的，
  游戏内改分辨率不会更新：从 4K 切到 1080p 后它还是 3840x2160，算出的点位跑到
  画面外，图标就"消失"了（4K 下正好是对的）。现在只把这份当最后兜底，
  并且任何来源不一致都会写一行 screen size mismatch 进日志。
· 换分辨率 / 换关卡的瞬间 overlay gui 会短暂不可用，这时建面板会失败。以前这一次
  击杀的图标就直接丢了，现在会在接下来的 30 帧里重试（约 0.5 秒），成功就照常播动画；
  同时 resolution_changed 和进关时都会清掉 panel_broken 标记，避免"失败一次，
  整局再也不画"。
· 面板每次弹图标时新建、下次弹之前销毁：游戏换关会换掉 overlay gui，长期持有的面板会
  变成"能显示一次、之后永远不显示"。
· 淡入淡出不用 gui 协程（panel:animate 在这个游戏里会把整段动画在一帧内跑完），
  改成在 HUDManager:update 里按 Application:time() 算进度。
· 面板 alpha 必须保持 1（会被子控件继承），淡入淡出只做在图标上。
· 打击特效全部在 tick() 里按时间算，没有用 panel:animate：图标本体负责缩放/位移，
  另有两个位图叠加层——闪光（在图标上层，白色光晕逐渐烧掉，第一帧看起来"过曝"）
  和火花（再上一层，落定后在新点亮的星角炸开）。两者都跟着图标的当前缩放走，
  所以砸入阶段它们和图标是对齐的。
