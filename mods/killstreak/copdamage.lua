-- Kill Streak :: kill detection
--
-- payday the heist applies damage client side, so the local player's kills run
-- through CopDamage:damage_bullet / damage_melee / damage_explosion. damage that
-- arrives from another machine runs through CopDamage:sync_damage_* instead.
-- both are wrapped, and the _dead flag is used to make sure a single death only
-- ever produces one icon (the second path already sees a dead unit).
--
-- the vanilla signatures (verified from the shipped byte code) are:
--   damage_bullet(self, attack_data)      -- attack_data.attacker_unit, attack_data.col_ray.body
--   damage_melee(self, attack_data)
--   damage_explosion(self, attack_data)
--   sync_damage_bullet(self, attacker_unit, damage_percent, i_body, hit_offset_height)
--   sync_damage_melee(self, attacker_unit, damage_percent, i_body, hit_offset_height)
--   sync_damage_explosion(self, attacker_unit, damage_percent, i_body)

local module = ... or D:module("killstreak")
local KillStreak = _G.KillStreak

if not KillStreak then
	return
end

-- a small unconditional trace, so a failing setup can be diagnosed from logs/main.log
-- without having to enable the debug option first
local trace_budget = 14
local function trace(...)
	if trace_budget <= 0 then
		return
	end
	trace_budget = trace_budget - 1
	pcall(module.log, module, 1, "killstreak-trace", ...)
end

local CopDamage
do
	local ok, cls = pcall(function() return module:hook_class("CopDamage") end)
	if ok then
		CopDamage = cls
	end
end

if not CopDamage then
	module:log(0, "killstreak", "CopDamage not found, kill detection disabled")
	return
end

-- not every unit dies through CopDamage: the tank (bulldozer) overrides some damage
-- functions and civilians run through CivilianDamage. EnemyManager sees every death
-- of the level, so it is used as a fallback for anything the hooks above missed.
local EnemyManager
do
	local ok, cls = pcall(function() return module:hook_class("EnemyManager") end)
	if ok then
		EnemyManager = cls
	end
end

-- > helpers --------------------------------------------------------------------
local function body_name(body)
	if not body then
		return nil
	end
	local ok, name = pcall(function() return body:name() end)
	if ok and type(name) == "string" then
		return name:lower()
	end
	return nil
end

local function body_is_head(cop_damage, body)
	if not body then
		return false
	end

	-- engine body names are plain strings ("head", "body", "hand_l", ...)
	local name = body_name(body)
	if name then
		if name == "head" or name:sub(-5) == "_head" or name:sub(1, 5) == "head_" then
			return true
		end
	end

	if cop_damage and type(cop_damage.is_head) == "function" then
		local ok, res = pcall(function() return cop_damage:is_head(body) end)
		if ok and type(res) == "boolean" then
			return res
		end
	end

	if cop_damage and type(cop_damage.is_headshot) == "function" then
		local ok, res = pcall(function() return cop_damage:is_headshot(body) end)
		if ok and type(res) == "boolean" then
			return res
		end
	end

	return false
end

-- read the flags before the damage is applied: on death the game may clear them
local function unit_flags(cop_damage)
	local flags = {}

	local ok_unit, unit = pcall(function() return cop_damage._unit end)
	if not ok_unit or not unit then
		return flags
	end

	local ok_base, base = pcall(function() return unit:base() end)
	if not ok_base or not base then
		return flags
	end

	local ok_enemy, enemy = pcall(function() return base.enemy end)
	if ok_enemy then
		flags.enemy = enemy
	end

	local ok_civ, civ = pcall(function() return base.is_civilian or base.civilian end)
	if ok_civ then
		flags.civilian = civ
	end

	-- "cop"/"civilian" style tweak table, handy for the trace
	local ok_tweak, tweak = pcall(function() return base._tweak_table or base.tweak_table end)
	if ok_tweak and type(tweak) == "string" then
		flags.tweak = tweak
	end

	return flags
end

local function now()
	local ok, t = pcall(function() return TimerManager:game():time() end)
	if ok and t then
		return t
	end
	return os.clock and os.clock() or 0
end

local function unit_tweak(unit)
	local ok, base = pcall(function() return unit:base() end)
	if ok and base then
		local ok2, tweak = pcall(function() return base._tweak_table or base.tweak_table end)
		if ok2 and type(tweak) == "string" then
			return tweak
		end
	end
	return "?"
end

local function damage_ext(unit)
	if not unit then
		return nil
	end
	local ok, dc = pcall(function() return unit:character_damage() end)
	if ok and dc then
		return dc
	end
	return nil
end

local function is_local_attacker(unit)
	if not unit then
		return false, "no attacker"
	end

	if type(alive) == "function" then
		local ok, is_alive = pcall(alive, unit)
		if ok and not is_alive then
			return false, "attacker is not alive"
		end
	end

	local player = managers.player and managers.player:player_unit()
	if player and unit == player then
		return true
	end

	local ok, base = pcall(function() return unit:base() end)
	if not ok or not base then
		return false, "attacker has no base"
	end

	if base.is_local_player then
		return true
	end

	-- sentry guns / trip mines placed by the local player
	if base.sentry_gun or base.trip_mine then
		local ok_info, info = pcall(function() return base:server_information() end)
		if ok_info and type(info) == "table" and info.owner_peer_id then
			local session = managers.network and managers.network:session()
			local local_peer = session and session:local_peer()
			if local_peer and info.owner_peer_id == local_peer:id() then
				return true
			end
		end
	end

	return false, "attacker is not the local player"
end

local function is_non_enemy(flags)
	-- CopDamage only exists on enemies, so an unknown flag counts as "enemy".
	-- only skip when the unit explicitly says it is one of the other things.
	if flags.civilian then
		return true
	end
	if flags.enemy == false then
		return true
	end
	return false
end

local function handle_kill(cop_damage, was_dead, attacker, head, variant, flags)
	if was_dead or not cop_damage._dead then
		return
	end

	local opt = KillStreak.opt
	if is_non_enemy(flags) and not opt.count_civilian_kills then
		trace("kill ignored: non enemy unit (" .. tostring(variant) .. ", tweak="
			.. tostring(flags.tweak) .. ", enemy=" .. tostring(flags.enemy)
			.. ", civilian=" .. tostring(flags.civilian) .. ")")
		return
	end

	local is_local, why = is_local_attacker(attacker)
	if not is_local then
		trace("kill ignored: " .. tostring(why) .. " (" .. tostring(variant) .. ")")
		return
	end

	trace("kill counted (" .. tostring(variant) .. ", headshot=" .. tostring(head)
		.. ", enemy=" .. tostring(flags.enemy) .. ", tweak=" .. tostring(flags.tweak) .. ")")
	KillStreak:on_kill(head and true or false, cop_damage._unit, flags.civilian and true or false, variant)
end

-- > hooks ----------------------------------------------------------------------
local function wrap_damage(fname, variant)
	if type(CopDamage[fname]) ~= "function" then
		module:log(0, "killstreak", "missing CopDamage." .. fname .. ", skipping")
		return
	end

	module:hook(CopDamage, fname, function(self, attack_data, ...)
		local was_dead = self._dead
		local attacker = type(attack_data) == "table" and attack_data.attacker_unit or nil
		local head = false
		if variant == "bullet" and type(attack_data) == "table" and attack_data.col_ray then
			head = body_is_head(self, attack_data.col_ray.body)
		end
		local flags = unit_flags(self)
		self._kst_dmg_t = now()

		local result = module:call_orig(CopDamage, fname, self, attack_data, ...)

		handle_kill(self, was_dead, attacker, head, variant, flags)
		return result
	end)
end

local function wrap_sync(fname, variant)
	if type(CopDamage[fname]) ~= "function" then
		module:log(0, "killstreak", "missing CopDamage." .. fname .. ", skipping")
		return
	end

	module:hook(CopDamage, fname, function(self, attacker_unit, damage_percent, i_body, ...)
		local was_dead = self._dead
		local head = false
		if variant == "bullet" and i_body then
			local ok, body = pcall(function() return self._unit:body(i_body) end)
			if ok then
				head = body_is_head(self, body)
			end
		end
		local flags = unit_flags(self)
		self._kst_dmg_t = now()

		local result = module:call_orig(CopDamage, fname, self, attacker_unit, damage_percent, i_body, ...)

		handle_kill(self, was_dead, attacker_unit, head, variant, flags)
		return result
	end)
end

trace("hooks installed on CopDamage (v2, flags read before damage)")

wrap_damage("damage_bullet", "bullet")
wrap_damage("damage_melee", "melee")
wrap_damage("damage_explosion", "explosion")

wrap_sync("sync_damage_bullet", "bullet")
wrap_sync("sync_damage_melee", "melee")
wrap_sync("sync_damage_explosion", "explosion")

-- > enemy manager fallback ------------------------------------------------------
local function fallback_kill(dead_unit, damage_info, kind)
	local opt = KillStreak.opt
	if not opt.enabled then
		return
	end
	if kind == "civilian" and not opt.count_civilian_kills then
		return
	end

	local dc = damage_ext(dead_unit)
	local t = now()
	if dc and dc._kst_dmg_t and (t - dc._kst_dmg_t) < 0.75 then
		-- that death already went through one of the CopDamage hooks above
		return
	end

	local attacker = type(damage_info) == "table" and damage_info.attacker_unit or nil
	local is_local, why = is_local_attacker(attacker)
	if not is_local then
		trace("fallback ignored (" .. tostring(kind) .. "): " .. tostring(why))
		return
	end

	trace("kill counted (fallback " .. tostring(kind) .. ", tweak=" .. unit_tweak(dead_unit) .. ")")
	KillStreak:on_kill(false, dead_unit, kind == "civilian")
end

if EnemyManager then
	local function install(fname, kind)
		if type(EnemyManager[fname]) ~= "function" then
			module:log(1, "killstreak", "EnemyManager." .. fname .. " not found")
			return
		end

		local ok, err = pcall(function()
			module:pre_hook(EnemyManager, fname, function(self, dead_unit, damage_info)
				pcall(fallback_kill, dead_unit, damage_info, kind)
			end)
		end)
		if not ok then
			module:log(1, "killstreak", "could not hook EnemyManager." .. fname .. ": " .. tostring(err))
		end
	end

	install("on_enemy_died", "enemy")
	install("on_civilian_died", "civilian")
	trace("enemy manager fallback installed")
else
	module:log(1, "killstreak", "EnemyManager not found, fallback kill detection is off")
end
