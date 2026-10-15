-- Per-spell damage for Azeroth Survivors (benilla, interface 1.12).
-- Damage, share, and DPS come from the run's own meter (AZS_GetMeter).
-- Reset remembers those numbers and shows only what the meter adds afterwards.
-- Healing and boss damage are not on the addon feed, so this window is damage only.
-- Kills are still credited from the combat log, by the last spell to hit that name.
-- A proc is grouped onto the spell it casts (Pyroclasm onto Blast Wave). The row
-- is that spell; the proc's own numbers are on its button.
-- Rows sit in a scroll frame at a fixed height. The frame clips whatever does not
-- fit, so a resize can leave the last spell only partly in view.

local ADDON = "AZSSpellMeter"
local MAX_ROWS = 24
local ROW_POOL = 25
local ROW_H = 16
local SOLID = "Interface\\Buttons\\WHITE8X8"
local WIDTH = 348
local HEADER = 32
local BOTTOM = 8
local COL_KILL = 40
local COL_DMG = 50
local COL_DPS = 36

local frame
local bubble
local rows = {}
local sorted = {}
local icons = {}
local state
local scroll = 0
local scanAt = 0
local lastRaw = ""
local lastHit = ""
local lastBlow = {}
local meterTotal = 0
local meterDps = 0
local runSeen
local testMeter
local hidStockMeter = false
local clockOn = false
local dead = false
local stateKey
local booted = false
local watchBoot = false
local choiceHold = false
local choiceGrace = 0
local holdX, holdY
local lastCast
local castGaps = {}
local castHeld = false
local lastW, lastH
local sizing = false
local sizeX, sizeY, sizeW, sizeH

local function say(text)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cffd2a24aAZS Spell Meter:|r " .. text)
	end
end

local function config()
	if not AZSSpellMeterDB then
		AZSSpellMeterDB = {}
	end
	return AZSSpellMeterDB
end

local function playerKey()
	local name = UnitName("player")
	if not name or name == "" or name == UNKNOWNOBJECT then
		name = "Unknown"
	end
	local realm = "Azeroth"
	if GetRealmName then
		local got = GetRealmName()
		if got and got ~= "" then
			realm = got
		end
	end
	return name .. " - " .. realm
end

local function freshState()
	return {
		spells = {},
		total = 0,
		elapsed = 0,
		level = 0,
		kills = 0,
	}
end

local function loadState()
	local cfg = config()
	if not cfg.chars then
		cfg.chars = {}
	end
	local key = playerKey()
	stateKey = key
	if not cfg.chars[key] then
		cfg.chars[key] = freshState()
	end
	state = cfg.chars[key]
	if not state.spells then
		state.spells = {}
	end
	state.total = state.total or 0
	state.kills = state.kills or 0
	local spellName, row
	for spellName, row in pairs(state.spells) do
		row.kills = row.kills or 0
	end
	state.elapsed = state.elapsed or 0
	state.level = state.level or 0
	state.anchor = nil
end

local function elapsed()
	local extra = 0
	if state and state.anchor then
		extra = GetTime() - state.anchor
		if extra < 0 then
			extra = 0
		end
	end
	return (state and state.elapsed or 0) + extra
end

local function foldTime()
	if not state or not state.anchor then
		return
	end
	state.elapsed = elapsed()
	state.anchor = nil
end

local MENU_FRAMES = {
	"GameMenuFrame",
	"UIOptionsFrame",
	"SoundOptionsFrame",
	"VideoOptionsFrame",
	"InterfaceOptionsFrame",
	"LootFrame",
	"GossipFrame",
	"QuestFrame",
	"ItemTextFrame",
}

local function frameShown(name)
	local f = getglobal(name)
	return f and f.IsShown and f:IsShown()
end

local function menuShown()
	local i
	for i = 1, table.getn(MENU_FRAMES) do
		if frameShown(MENU_FRAMES[i]) then
			return true
		end
	end
	return false
end

-- ESC and the cache cards are drawn by the game, not by a WoW frame, and the
-- cooldown wheels keep counting with GetTime. Spell casts themselves stop
-- whenever the run pauses, so a gap longer than the recent cast rhythm is
-- time the caster was suspended. That gap is left out of the DPS clock.
local function castLimit()
	local now = GetTime()
	local maxg = 0
	local n = 0
	local i = 1
	while i <= table.getn(castGaps) do
		local gap = castGaps[i]
		if now - gap.t > 12 then
			table.remove(castGaps, i)
		else
			n = n + 1
			if gap.dt > maxg then
				maxg = gap.dt
			end
			i = i + 1
		end
	end
	if n < 3 then
		return 2.2
	end
	local limit = maxg * 1.75 + 0.3
	if limit < 0.9 then
		limit = 0.9
	end
	if limit > 4 then
		limit = 4
	end
	return limit
end

local function rememberGap(dt)
	table.insert(castGaps, { t = GetTime(), dt = dt })
	while table.getn(castGaps) > 24 do
		table.remove(castGaps, 1)
	end
end

local function castsPaused()
	return lastCast and (GetTime() - lastCast) >= castLimit()
end

local function noteCast()
	local now = GetTime()
	if lastCast then
		local dt = now - lastCast
		-- A short resume is a slow cast, not a menu. Put that gap back.
		-- A long resume is the run starting again after ESC, a cache, or a level-up.
		if castHeld and dt >= 0.05 and dt <= 2.5 and not choiceHold and not dead and not menuShown() then
			if state then
				state.elapsed = (state.elapsed or 0) + dt
			end
			rememberGap(dt)
		elseif not castHeld and dt >= 0.05 then
			local learnCap = castLimit()
			if table.getn(castGaps) < 3 then
				learnCap = 6
			end
			if dt <= learnCap then
				rememberGap(dt)
			end
		end
	end
	castHeld = false
	lastCast = now
end

local function freezeAt(t)
	if not state or not state.anchor or not t then
		return
	end
	local extra = t - state.anchor
	if extra < 0 then
		extra = 0
	end
	state.elapsed = state.elapsed + extra
	state.anchor = nil
end

local function isPaused()
	return menuShown() or choiceHold
end

local function syncClock()
	if not state then
		return
	end
	if dead or isPaused() then
		foldTime()
	elseif castsPaused() then
		freezeAt(lastCast)
		castHeld = true
	elseif clockOn and not state.anchor then
		state.anchor = GetTime()
	end
end

local function beginChoice()
	choiceHold = true
	choiceGrace = GetTime() + 0.75
	if GetPlayerMapPosition then
		holdX, holdY = GetPlayerMapPosition("player")
		if holdX == 0 and holdY == 0 then
			holdX, holdY = nil, nil
		end
	end
	syncClock()
end

local function endChoice()
	if not choiceHold or GetTime() <= choiceGrace then
		return
	end
	choiceHold = false
	holdX, holdY = nil, nil
	syncClock()
end

local function pollChoiceMove()
	if not choiceHold or GetTime() <= choiceGrace or not holdX or not GetPlayerMapPosition then
		return
	end
	local x, y = GetPlayerMapPosition("player")
	if not x or (x == 0 and y == 0) then
		return
	end
	if math.abs(x - holdX) > 0.0008 or math.abs(y - holdY) > 0.0008 then
		endChoice()
	end
end

local function choiceMessage(msg)
	msg = string.lower(msg or "")
	if string.find(msg, "choose a spell")
		or string.find(msg, "choose a ring")
		or string.find(msg, "choose one")
		or string.find(msg, "battleground cache")
		or string.find(msg, "guardian falls")
		or string.find(msg, "yields jewelry")
		or string.find(msg, "yields treasure") then
		return true
	end
	return false
end

local function comma(n)
	n = math.floor((n or 0) + 0.5)
	if n >= 1000000 then
		return string.format("%.2fm", n / 1000000)
	elseif n >= 10000 then
		return string.format("%.1fk", n / 1000)
	end
	return tostring(n)
end

local function fmtRate(n)
	n = n or 0
	if n >= 10000 then
		return comma(n)
	elseif n >= 100 then
		return tostring(math.floor(n + 0.5))
	end
	return string.format("%.1f", n)
end

local function fmtPct(p)
	local n = (p or 0) * 100
	if n >= 10 then
		return string.format("%.0f%%", n)
	end
	return string.format("%.1f%%", n)
end

local function cleanName(name)
	if not name then
		return nil
	end
	name = string.gsub(name, "|c%x%x%x%x%x%x%x%x", "")
	name = string.gsub(name, "|r", "")
	name = string.gsub(name, "^%s+", "")
	name = string.gsub(name, "%s+$", "")
	name = string.gsub(name, " %(Critical%)$", "")
	name = string.gsub(name, "%.$", "")
	name = string.gsub(name, "%s+$", "")
	if name == "" then
		return nil
	end
	return name
end

local function strip(msg)
	msg = string.gsub(msg or "", "|c%x%x%x%x%x%x%x%x", "")
	msg = string.gsub(msg, "|r", "")
	msg = string.gsub(msg, "|H.-|h(.-)|h", "%1")
	return msg
end

-- English 1.12 combat-log lines. School, block, and resist suffixes sit
-- after the number, so the first integer is the damage dealt.
local function parseYours(msg)
	local _, _, spell, victim, amount
	_, _, spell, victim, amount = string.find(msg, "^Your (.+) crits (.+) for (%d+)")
	if spell then
		return cleanName(spell), amount, true, cleanName(victim)
	end
	_, _, spell, victim, amount = string.find(msg, "^Your (.+) hits (.+) for (%d+)")
	if spell then
		return cleanName(spell), amount, false, cleanName(victim)
	end
	_, _, spell, victim, amount = string.find(msg, "^Your (.+) causes (.+) (%d+)")
	if spell then
		return cleanName(spell), amount, false, cleanName(victim)
	end
	_, _, victim, amount = string.find(msg, "^You crit (.+) for (%d+)")
	if amount then
		return "Melee", amount, true, cleanName(victim)
	end
	_, _, victim, amount = string.find(msg, "^You hit (.+) for (%d+)")
	if amount then
		return "Melee", amount, false, cleanName(victim)
	end
	_, _, amount, victim = string.find(msg, "^You reflect (%d+).+ to (.+)")
	if amount then
		return "Damage Shield", amount, false, cleanName(victim)
	end
	_, _, amount = string.find(msg, "^You reflect (%d+)")
	if amount then
		return "Damage Shield", amount, false, nil
	end
	return nil
end

local function parsePeriodic(msg)
	local _, _, victim, amount, spell = string.find(msg, "^(.+) suffers (%d+) .+ damage from your (.+)$")
	if spell then
		return cleanName(spell), amount, string.find(msg, "%(Critical%)") and true or false, cleanName(victim)
	end
	if UnitExists("pet") then
		local _, _, victim2, amount2, owner, spell2 = string.find(msg, "^(.+) suffers (%d+) .+ damage from (.+)'s (.+)$")
		local pet = UnitName("pet")
		if amount2 and owner == pet then
			return cleanName(spell2), amount2, string.find(msg, "%(Critical%)") and true or false, cleanName(victim2)
		end
	end
	return nil
end

local function parsePet(msg, melee)
	local _, _, spell, victim, amount = string.find(msg, "^.+'s (.+) crits (.+) for (%d+)")
	if spell then
		return cleanName(spell), amount, true, cleanName(victim)
	end
	_, _, spell, victim, amount = string.find(msg, "^.+'s (.+) hits (.+) for (%d+)")
	if spell then
		return cleanName(spell), amount, false, cleanName(victim)
	end
	_, _, spell, victim, amount = string.find(msg, "^.+'s (.+) causes (.+) (%d+)")
	if spell then
		return cleanName(spell), amount, false, cleanName(victim)
	end
	if melee then
		local attacker
		_, _, attacker, victim, amount = string.find(msg, "^(.+) crits (.+) for (%d+)")
		if amount and not string.find(attacker or "", "'s$") then
			return "Pet", amount, true, cleanName(victim)
		end
		_, _, attacker, victim, amount = string.find(msg, "^(.+) hits (.+) for (%d+)")
		if amount and not string.find(attacker or "", "'s$") then
			return "Pet", amount, false, cleanName(victim)
		end
	end
	return nil
end

-- Damage is read from the run's meter. A combat-log hit only remembers which
-- spell last touched that creature, so a later death can be credited to it.
local function note(spell, amount, crit, victim)
	if not spell or not victim or not state then
		return false
	end
	lastBlow[victim] = spell
	lastHit = spell
	return true
end

local function noteKill(name)
	name = cleanName(name)
	if not name or name == "" or name == "You" or not state then
		return
	end
	local player = UnitName("player")
	if player and name == player then
		return
	end
	local spell = lastBlow[name]
	if not spell then
		return
	end
	local row = state.spells[spell]
	if not row then
		row = { damage = 0, hits = 0, crits = 0, kills = 0 }
		state.spells[spell] = row
	end
	row.kills = (row.kills or 0) + 1
	state.kills = (state.kills or 0) + 1
end

local function ingest(msg, kind)
	msg = strip(msg)
	lastRaw = msg
	local spell, amount, crit, victim
	if kind == "yours" then
		spell, amount, crit, victim = parseYours(msg)
	elseif kind == "periodic" then
		spell, amount, crit, victim = parsePeriodic(msg)
	elseif kind == "pet" then
		spell, amount, crit, victim = parsePet(msg, false)
	elseif kind == "petmelee" then
		spell, amount, crit, victim = parsePet(msg, true)
	end
	if spell then
		note(spell, amount, crit, victim)
	end
end

local function resetData()
	if not state then
		loadState()
	end
	state.spells = {}
	state.total = 0
	state.kills = 0
	state.elapsed = 0
	state.anchor = nil
	state.base = nil
	state.baseTotal = nil
	state.baseTime = nil
	local level = UnitLevel("player")
	if level and level > 0 then
		state.level = level
	end
	scroll = 0
	lastHit = ""
	choiceHold = false
	holdX, holdY = nil, nil
	lastCast = nil
	castGaps = {}
	castHeld = false
	lastBlow = {}
	testMeter = nil
	runSeen = nil
end

-- A new hero reloads the UI and restores the saved board. Starting again at
-- level 1 is a new run even when the previous one never leveled.
local function sameLevelRestart()
	local level = UnitLevel("player")
	if not level or level <= 0 then
		return false
	end
	if not booted and level <= 1 and (state.kills or 0) > 0 and (state.level or 0) <= 1 then
		resetData()
		say("New run.")
	end
	booted = true
	return true
end

local function checkLevel()
	if not state then
		return
	end
	local level = UnitLevel("player")
	if not level or level <= 0 then
		return
	end
	-- Dropping a level means the run started over. The meter's own numbers
	-- reset with the game; the kill tally is ours.
	if state.level and state.level > level then
		resetData()
		say("New run.")
	end
	state.level = level
end

local function rememberIcon(name, texture)
	if name and texture and name ~= "" and texture ~= "" then
		icons[name] = texture
	end
end

local FALLBACK_ICONS = {
	Melee = "Interface\\Icons\\INV_Sword_04",
	["Damage Shield"] = "Interface\\Icons\\Spell_Nature_Thorns",
	Pet = "Interface\\Icons\\Ability_Hunter_BeastCall",
}

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Talents the meter names on their own, and the spell the combat log actually prints.
-- Built from the game's talent text. Pyroclasm's explosion is logged as Blast Wave.
local PROC_CAST = {
	["Pyroclasm"] = { "Blast Wave" },
	["Hot Streak"] = { "Pyroblast" },
	["Arcane Concentration"] = { "Arcane Explosion" },
	["Shadowy Apparitions"] = { "Mind Blast" },
	["Maelstrom Weapon"] = { "Chain Lightning" },
	["Lightning Overload"] = { "Lightning Bolt", "Chain Lightning" },
	["Windfury"] = { "Lightning Bolt", "Earth Shock", "Frost Shock" },
}

-- Custom talents are not in Spell.dbc, so the generated icon list has no row for them.
local EXTRA_ICONS = {
	["Hot Streak"] = "Spell_Fire_Fireball02",
	["Windfury"] = "Spell_Nature_Cyclone",
	["Lightning Overload"] = "Spell_Nature_CallStorm",
	["Shadowy Apparitions"] = "Spell_Shadow_Haunting",
	["Seed of Corruption"] = "Spell_Shadow_CurseOfMannoroth",
	["Maelstrom Weapon"] = "Spell_Nature_Lightning",
}

local function iconLookup(name)
	if icons[name] then
		return icons[name]
	end
	local file = EXTRA_ICONS[name]
	if not file and AZSSpellMeterIcon then
		file = AZSSpellMeterIcon[name]
	end
	if not file then
		file = FALLBACK_ICONS[name]
	end
	if file then
		if string.find(file, "\\", 1, true) then
			return file
		end
		return "Interface\\Icons\\" .. file
	end
	return QUESTION
end

local function iconFor(name)
	local tex = iconLookup(name)
	if tex ~= QUESTION then
		return tex
	end
	local casts = PROC_CAST[name]
	if casts and casts[1] and casts[1] ~= name then
		local via = iconLookup(casts[1])
		if via ~= QUESTION then
			return via
		end
	end
	return QUESTION
end

local function castList(name)
	local list = PROC_CAST[name]
	if not list or not list[1] then
		return nil
	end
	local text = list[1]
	local i
	local n = table.getn(list)
	for i = 2, n do
		if i == n then
			text = text .. " or " .. list[i]
		else
			text = text .. ", " .. list[i]
		end
	end
	return text
end

local scanTip
local scanTipMissing

local function actionTip()
	if scanTip or scanTipMissing then
		return scanTip
	end
	local ok, tip = pcall(CreateFrame, "GameTooltip", "AZSSpellMeterScanTip", UIParent, "GameTooltipTemplate")
	if not ok or not tip or not tip.SetOwner or not tip.SetAction then
		scanTipMissing = true
		return nil
	end
	scanTip = tip
	return tip
end

local function scanIcons()
	if GetSpellName and GetSpellTexture then
		local i = 1
		while true do
			local name = GetSpellName(i, BOOKTYPE_SPELL)
			if not name then
				break
			end
			rememberIcon(name, GetSpellTexture(i, BOOKTYPE_SPELL))
			i = i + 1
		end
	end
	local tip = actionTip()
	if not tip or not HasAction or not GetActionTexture then
		return
	end
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	tip:SetAlpha(0)
	for slot = 1, 120 do
		if HasAction(slot) then
			local ok = pcall(tip.SetAction, tip, slot)
			if ok then
				local line = getglobal("AZSSpellMeterScanTipTextLeft1")
				if line then
					rememberIcon(line:GetText(), GetActionTexture(slot))
				end
			end
		end
	end
	tip:Hide()
	tip:SetAlpha(1)
end

local function queueScan()
	scanAt = GetTime() + 0.3
end

local function widenCombatLog()
	if not SetCVar then
		return
	end
	local names = {
		"CombatLogRangeCreature",
		"CombatLogRangeHostilePlayers",
		"CombatLogRangeHostilePlayersPets",
		"CombatLogRangeFriendlyPlayers",
		"CombatLogRangeFriendlyPlayersPets",
		"CombatLogRangeParty",
		"CombatLogRangePartyPet",
	}
	local i
	for i = 1, table.getn(names) do
		pcall(SetCVar, names[i], "200")
	end
end

local function visibleRows()
	if not frame then
		return 8
	end
	local n = math.floor((frame:GetHeight() - HEADER - BOTTOM) / ROW_H + 0.001)
	if n < 1 then
		n = 1
	elseif n > MAX_ROWS then
		n = MAX_ROWS
	end
	return n
end

local function rowWidth()
	if not frame then
		return WIDTH - 12
	end
	local w = frame:GetWidth() - 12
	if w < 40 then
		w = 40
	end
	return w
end

local function isProc(flag)
	return flag == 1 or flag == "1" or flag == true
end

local function hideStockMeter()
	if hidStockMeter or not AZS_SetHudShown or not AZS_IsHudShown then
		return
	end
	if AZS_IsHudShown("meter") then
		AZS_SetHudShown("meter", false)
		hidStockMeter = true
	end
end

local function restoreStockMeter()
	if hidStockMeter and AZS_SetHudShown then
		AZS_SetHudShown("meter", true)
		hidStockMeter = false
	end
end

-- A new run rewinds the game clock. The meter clears itself; kills are ours.
local function watchRun()
	if not AZS_GetRunTime then
		return
	end
	local t = AZS_GetRunTime()
	if not t then
		return
	end
	if runSeen and t + 1 < runSeen and ((state.kills or 0) > 0 or state.base) then
		state.spells = {}
		state.kills = 0
		lastBlow = {}
		state.base = nil
		state.baseTotal = nil
		state.baseTime = nil
		say("New run.")
	end
	runSeen = t
end

local function runNow()
	if not AZS_GetRunTime then
		return 0
	end
	local t = AZS_GetRunTime()
	if not t or t < 0 then
		return 0
	end
	return t
end

local function meterFrom(list)
	if not list then
		return {}, 0, 0
	end
	local total = 0
	local dps = 0
	local i
	local n = table.getn(list)
	for i = 1, n do
		total = total + (tonumber(list[i].dmg) or 0)
		dps = dps + (tonumber(list[i].dps) or 0)
	end
	if dps <= 0 and total > 0 then
		local t = 1
		if AZS_GetRunTime then
			t = AZS_GetRunTime() or 1
		end
		if not t or t < 1 then
			t = 1
		end
		dps = total / t
	end
	return list, total, dps
end

local function pullMeter()
	if testMeter then
		return meterFrom(testMeter)
	end
	if AZS_GetMeter then
		return AZS_GetMeter()
	end
	return {}, 0, 0
end

-- The built-in meter cannot be cleared from an addon. Remember its numbers at
-- the moment of a reset and show only what it has added since.
local function captureBase()
	if not state then
		loadState()
	end
	local lines, total = pullMeter()
	local base = {}
	if lines then
		local i
		for i = 1, table.getn(lines) do
			local line = lines[i]
			local name = line.name
			if name and name ~= "" then
				base[name] = (base[name] or 0) + (tonumber(line.dmg) or 0)
			end
		end
	end
	state.base = base
	state.baseTotal = tonumber(total) or 0
	state.baseTime = runNow()
end

local function windowReset(dropTest)
	if not state then
		loadState()
	end
	if dropTest then
		testMeter = nil
	end
	captureBase()
	state.spells = {}
	state.kills = 0
	lastBlow = {}
	scroll = 0
end

-- One parent spell when the proc names a single cast, or only one of its
-- casts is on the meter. Several casts at once stay separate: the damage
-- cannot be split between them.
local function anchorSpell(procName, present)
	local casts = PROC_CAST[procName]
	if not casts then
		return nil
	end
	local n = table.getn(casts)
	if n == 1 then
		return casts[1]
	end
	local found = nil
	local i
	for i = 1, n do
		if present[casts[i]] then
			if found then
				return nil
			end
			found = casts[i]
		end
	end
	return found
end

local function rebuild()
	local i
	for i = table.getn(sorted), 1, -1 do
		sorted[i] = nil
	end
	if not state then
		return 0
	end
	local lines, total, rdps = pullMeter()
	local gameTotal = tonumber(total) or 0
	if state.base and gameTotal + 1 < (state.baseTotal or 0) then
		state.base = nil
		state.baseTotal = nil
		state.baseTime = nil
	end
	local since = 1
	if state.base then
		since = runNow() - (state.baseTime or 0)
		if since < 1 then
			since = 1
		end
		meterTotal = gameTotal - (state.baseTotal or 0)
		if meterTotal < 0 then
			meterTotal = 0
		end
		meterDps = meterTotal / since
	else
		meterTotal = gameTotal
		meterDps = tonumber(rdps) or 0
	end
	local bucket = {}
	local function bucketOf(name)
		local row = bucket[name]
		if row then
			return row
		end
		local kills = 0
		local rec = state.spells[name]
		if rec then
			kills = rec.kills or 0
		end
		row = {
			name = name,
			damage = 0,
			dps = 0,
			proc = false,
			kills = kills,
			fromMeter = false,
		}
		bucket[name] = row
		return row
	end
	if lines then
		for i = 1, table.getn(lines) do
			local line = lines[i]
			local name = line.name
			if name and name ~= "" then
				local row = bucketOf(name)
				local raw = tonumber(line.dmg) or 0
				local dealt = raw
				if state.base then
					dealt = raw - (state.base[name] or 0)
					if dealt < 0 then
						dealt = 0
					end
					row.dps = dealt / since
				else
					row.dps = tonumber(line.dps) or 0
				end
				row.damage = dealt
				row.proc = isProc(line.proc)
				row.fromMeter = true
			end
		end
	end
	local spellName, rec
	for spellName, rec in pairs(state.spells) do
		if (rec.kills or 0) > 0 then
			bucketOf(spellName)
		end
	end
	-- Fold a proc into the spell it actually casts: one Blast Wave row, and
	-- Pyroclasm lives on the proc button. Collect first; pairs cannot drop keys.
	local merges = {}
	local procName, row
	for procName, row in pairs(bucket) do
		if row.proc or PROC_CAST[procName] then
			local parentName = anchorSpell(procName, bucket)
			if parentName and parentName ~= procName then
				local mi = table.getn(merges) + 1
				merges[mi] = { proc = procName, parent = parentName }
			end
		end
	end
	local mi
	for mi = 1, table.getn(merges) do
		local link = merges[mi]
		row = bucket[link.proc]
		if row then
			local parent = bucketOf(link.parent)
			parent.damage = (parent.damage or 0) + (row.damage or 0)
			parent.dps = (parent.dps or 0) + (row.dps or 0)
			parent.kills = (parent.kills or 0) + (row.kills or 0)
			if (row.damage or 0) > 0 or (row.kills or 0) > 0 then
				if not parent.procs then
					parent.procs = {}
				end
				local pi = table.getn(parent.procs) + 1
				parent.procs[pi] = {
					name = link.proc,
					damage = row.damage or 0,
					dps = row.dps or 0,
					kills = row.kills or 0,
				}
			end
			bucket[link.proc] = nil
		end
	end
	local n = 0
	local name, entry
	for name, entry in pairs(bucket) do
		local keep = (entry.damage or 0) > 0 or (entry.kills or 0) > 0
		if not keep and entry.procs and table.getn(entry.procs) > 0 then
			keep = true
		end
		if keep then
			if entry.proc and not entry.procs then
				entry.cast = castList(name)
			end
			n = n + 1
			sorted[n] = entry
		end
	end
	local key = config().sort or "damage"
	if key == "name" or key == "share" then
		key = "damage"
	end
	local desc = config().sortDir ~= "asc"
	table.sort(sorted, function(a, b)
		local av = a.damage or 0
		local bv = b.damage or 0
		if key == "kills" then
			av = a.kills or 0
			bv = b.kills or 0
		elseif key == "dps" then
			av = a.dps or 0
			bv = b.dps or 0
		end
		if av == bv then
			local an = a.name or ""
			local bn = b.name or ""
			if an == bn then
				return false
			end
			return an < bn
		end
		if desc then
			return av > bv
		end
		return av < bv
	end)
	return n
end

-- Pixel height of the list. Not snapped to a row, so the scroll frame can cut a spell in half.
local function viewHeight()
	local avail = 8 * ROW_H
	if frame then
		avail = frame:GetHeight() - HEADER - 6
	end
	if avail < 8 then
		avail = 8
	end
	return avail
end

local function refresh()
	if not frame or not state then
		return
	end
	watchRun()
	if frame:IsShown() or (bubble and bubble:IsShown()) then
		hideStockMeter()
	end
	local n = rebuild()
	local viewH = viewHeight()
	local maxOff = n * ROW_H - viewH
	if maxOff < 0 then
		maxOff = 0
	end
	if scroll < 0 then
		scroll = 0
	elseif scroll > maxOff then
		scroll = maxOff
	end
	local first = 0
	if ROW_H > 0 then
		first = math.floor(scroll / ROW_H)
	end
	local shift = scroll - first * ROW_H
	local shown = 0
	if n > 0 then
		shown = math.floor((shift + viewH - 0.001) / ROW_H) + 1
		if shown > n - first then
			shown = n - first
		end
		if shown > ROW_POOL then
			shown = ROW_POOL
		end
		if shown < 1 then
			shown = 1
		end
	end
	if frame.scroll then
		frame.scroll:SetHeight(viewH)
		local sw = frame.scroll:GetWidth()
		if not sw or sw < 40 then
			sw = rowWidth()
		end
		if frame.scrollChild then
			frame.scrollChild:SetWidth(sw)
			local childH = shown * ROW_H
			if childH < viewH + shift then
				childH = viewH + shift
			end
			if childH < 1 then
				childH = 1
			end
			frame.scrollChild:SetHeight(childH)
		end
		if frame.scroll.SetVerticalScroll then
			frame.scroll:SetVerticalScroll(shift)
		end
	end

	local board = meterTotal
	local dps = meterDps
	if frame.emptyText then
		if n <= 0 then
			frame.emptyText:SetText("No damage yet.")
			frame.emptyText:Show()
		else
			frame.emptyText:Hide()
		end
	end
	frame.totalText:SetText(comma(board))
	frame.dpsText:SetText(fmtRate(dps) .. " dps")
	if frame.bubbleText then
		frame.bubbleText:SetText(comma(board))
		local bw = 36
		if frame.bubbleText.GetStringWidth then
			bw = (frame.bubbleText:GetStringWidth() or 24) + 16
		end
		if bw < 36 then
			bw = 36
		end
		bubble:SetWidth(bw)
	end
	if frame.totalBtn and frame.totalText.GetStringWidth then
		local tw = frame.totalText:GetStringWidth() or 24
		if tw < 24 then
			tw = 24
		end
		frame.totalBtn:SetWidth(tw + 8)
	end
	if frame.dpsBtn and frame.dpsText.GetStringWidth then
		local dw = frame.dpsText:GetStringWidth() or 24
		if dw < 24 then
			dw = 24
		end
		frame.dpsBtn:SetWidth(dw + 8)
	end
	if frame.sortBtns then
		local active = config().sort or "damage"
		if active == "name" then
			active = "damage"
		end
		local si
		for si = 1, table.getn(frame.sortBtns) do
			local btn = frame.sortBtns[si]
			btn.label:SetText(btn.base)
			if btn.key == active then
				btn.label:SetTextColor(1, 0.82, 0.4)
			else
				btn.label:SetTextColor(0.55, 0.5, 0.4)
			end
		end
	end
	if (state.kills or 0) > 0 then
		frame.countText:SetText(state.kills .. (state.kills == 1 and " kill" or " kills"))
	else
		frame.countText:SetText("")
	end

	local i
	for i = 1, ROW_POOL do
		local row = rows[i]
		local data = nil
		if i <= shown then
			data = sorted[first + i]
		end
		if data then
			local dealt = data.damage or 0
			local share = 0
			if board > 0 then
				share = dealt / board
			end
			local label = data.name
			row.data = data
			row:Show()
			row:SetWidth(rowWidth())
			row.icon:SetTexture(iconFor(data.name))
			row.name:SetText(string.format("%d  %s", first + i, label))
			if (data.kills or 0) > 0 then
				row.kills:SetText(tostring(data.kills))
			else
				row.kills:SetText("")
			end
			row.damage:SetText(comma(dealt))
			row.rate:SetText(fmtRate(data.dps or 0))
			local fill = share
			if dealt > 0 and fill < 0.015 then
				fill = 0.015
			end
			row.bar:SetWidth(math.max(2, (row:GetWidth() or 1) * fill))
			if first + i == 1 then
				row.bar:SetVertexColor(0.82, 0.46, 0.12, 0.85)
			else
				row.bar:SetVertexColor(0.42, 0.2, 0.08, 0.75)
			end
			local procs = data.procs
			local textW = 0
			if row.name.GetStringWidth then
				textW = row.name:GetStringWidth() or 0
			end
			local px = 16 + textW + 4
			local limit = (row:GetWidth() or 0) - (COL_KILL + COL_DMG + COL_DPS + 28)
			if limit < 40 then
				limit = 40
			end
			local pi
			for pi = 1, 3 do
				local btn = row.procBtns and row.procBtns[pi]
				local info = procs and procs[pi]
				if btn and info then
					if px > limit then
						px = limit
					end
					btn.info = info
					btn:ClearAllPoints()
					btn:SetPoint("LEFT", row, "LEFT", px, 0)
					btn:Show()
					px = px + (btn:GetWidth() or 32) + 2
				elseif btn then
					btn.info = nil
					btn:Hide()
				end
			end
		else
			row.data = nil
			row:Hide()
			if row.procBtns then
				local pi
				for pi = 1, 3 do
					row.procBtns[pi].info = nil
					row.procBtns[pi]:Hide()
				end
			end
		end
	end
end

local function savePoint()
	local point, _, rel, x, y = frame:GetPoint(1)
	if not point then
		return
	end
	local cfg = config()
	cfg.point = point
	cfg.rel = rel
	cfg.x = x
	cfg.y = y
end

local function uiScale()
	local s = 1
	if UIParent and UIParent.GetEffectiveScale then
		s = UIParent:GetEffectiveScale()
	elseif UIParent and UIParent.GetScale then
		s = UIParent:GetScale()
	end
	if not s or s <= 0 then
		s = 1
	end
	return s
end

-- Keep the top-left corner where it is. StartSizing scales around the anchor,
-- which sits outside the window whenever that anchor is not the corner being dragged.
local function pinTopLeft()
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function applyShown()
	local cfg = config()
	if cfg.shown == false then
		frame:Hide()
		if bubble then
			bubble:Hide()
		end
		return
	end
	if cfg.mini then
		frame:Hide()
		if bubble then
			bubble:Show()
		end
	else
		if bubble then
			bubble:Hide()
		end
		frame:Show()
	end
end

local function face(fs, size)
	if fs and fs.SetFont then
		fs:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
	end
end

local function panelBackdrop()
	return {
		bgFile = SOLID,
		edgeFile = SOLID,
		tile = false,
		edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	}
end

local tipFill
local tipOwner

local function hideTip()
	tipFill = nil
	tipOwner = nil
	if frame and frame.tip then
		frame.tip:Hide()
	end
end

local function leaveTip()
	if tipOwner == this then
		hideTip()
	end
end

local function placeTip()
	local tip = frame and frame.tip
	if not tip or not tip:IsShown() then
		return
	end
	local scale = uiScale()
	local x, y = GetCursorPosition()
	if not x or not y then
		return
	end
	x = x / scale
	y = y / scale
	local tipW = tip:GetWidth() or 96
	local tipH = tip:GetHeight() or 40
	local screenW = 0
	local screenH = 0
	if UIParent then
		screenW = UIParent:GetWidth() or 0
		screenH = UIParent:GetHeight() or 0
	end
	local left = x - tipW / 2
	if left < 2 then
		left = 2
	end
	if screenW > 0 and left + tipW > screenW - 2 then
		left = screenW - 2 - tipW
	end
	local cx = left + tipW / 2
	local gap = 14
	tip:ClearAllPoints()
	if screenH > 0 and y + gap + tipH > screenH - 2 then
		tip:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, y - 22)
	else
		tip:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, y + gap)
	end
end

local function paintTip(title, icon, lines)
	local tip = frame and frame.tip
	if not tip then
		return
	end
	tip.title:SetText(title or "")
	local left = 8
	if icon then
		tip.icon:SetTexture(icon)
		tip.icon:Show()
		tip.iconBack:Show()
		left = 36
	else
		tip.icon:Hide()
		tip.iconBack:Hide()
	end
	tip.title:ClearAllPoints()
	tip.title:SetPoint("TOPLEFT", tip, "TOPLEFT", left, -7)
	local widest = left + 8
	if tip.title.GetStringWidth then
		widest = left + (tip.title:GetStringWidth() or 0) + 10
	end
	local y = -24
	if icon then
		y = -34
	end
	local count = 0
	if lines then
		count = table.getn(lines)
	end
	if count > 6 then
		count = 6
	end
	local i
	for i = 1, 6 do
		local fs = tip.lines[i]
		if i <= count then
			local line = lines[i]
			fs:SetText(line[1] or "")
			fs:SetTextColor(line[2] or 1, line[3] or 1, line[4] or 1)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", tip, "TOPLEFT", 8, y)
			fs:Show()
			if fs.GetStringWidth then
				local lw = (fs:GetStringWidth() or 0) + 16
				if lw > widest then
					widest = lw
				end
			end
			y = y - 13
		else
			fs:Hide()
		end
	end
	if widest < 96 then
		widest = 96
	end
	local h = -y + 4
	if icon and h < 38 then
		h = 38
	end
	tip:SetWidth(widest)
	tip:SetHeight(h)
	tip:Show()
	placeTip()
end

local function showTip(owner, side, title, icon, lines)
	tipOwner = owner
	tipFill = nil
	paintTip(title, icon, lines)
end

local function trackTip(owner, fill)
	tipOwner = owner
	tipFill = fill
	if tipFill then
		tipFill()
	end
end

local function createRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetWidth(WIDTH - 12)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_H))

	local bar = row:CreateTexture(nil, "BACKGROUND")
	bar:SetTexture(SOLID)
	bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	bar:SetHeight(ROW_H)
	bar:SetWidth(1)
	bar:SetVertexColor(0.42, 0.2, 0.08, 0.75)
	row.bar = bar

	local rule = row:CreateTexture(nil, "BORDER")
	rule:SetTexture(SOLID)
	rule:SetVertexColor(0, 0, 0, 0.65)
	rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	rule:SetHeight(1)

	local iconBg = row:CreateTexture(nil, "ARTWORK")
	iconBg:SetTexture(SOLID)
	iconBg:SetVertexColor(0, 0, 0, 1)
	iconBg:SetWidth(13)
	iconBg:SetHeight(13)
	iconBg:SetPoint("LEFT", row, "LEFT", 1, 0)

	local icon = row:CreateTexture(nil, "OVERLAY")
	icon:SetWidth(11)
	icon:SetHeight(11)
	icon:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.icon = icon

	local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("LEFT", row, "LEFT", 16, 0)
	name:SetJustifyH("LEFT")
	face(name, 10)
	name:SetTextColor(1, 0.95, 0.86)
	row.name = name

	local kills = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	kills:SetWidth(COL_KILL)
	kills:SetJustifyH("RIGHT")
	face(kills, 10)
	kills:SetTextColor(1, 0.78, 0.45)
	row.kills = kills

	local damage = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	damage:SetWidth(COL_DMG)
	damage:SetJustifyH("RIGHT")
	face(damage, 10)
	damage:SetTextColor(1, 0.9, 0.55)
	row.damage = damage

	local rate = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rate:SetWidth(COL_DPS)
	rate:SetJustifyH("RIGHT")
	face(rate, 10)
	rate:SetTextColor(0.7, 0.92, 0.68)
	row.rate = rate

	rate:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	damage:SetPoint("RIGHT", rate, "LEFT", -6, 0)
	kills:SetPoint("RIGHT", damage, "LEFT", -6, 0)
	name:SetPoint("RIGHT", kills, "LEFT", -4, 0)

	row:SetScript("OnEnter", function()
		local owner = this
		trackTip(owner, function()
			local data = owner.data
			if not data then
				hideTip()
				return
			end
			local share = 0
			if meterTotal > 0 then
				share = (data.damage or 0) / meterTotal
			end
			local lines = {
				{ string.format("Damage %s", comma(data.damage)), 1, 1, 1 },
				{ string.format("Share %s", fmtPct(share)), 0.95, 0.86, 0.62 },
				{ string.format("DPS %s", fmtRate(data.dps or 0)), 0.7, 0.92, 0.68 },
				{ string.format("Kills %d", data.kills or 0), 1, 0.82, 0.45 },
			}
			if data.procs and data.procs[1] then
				local text = data.procs[1].name
				local pi
				for pi = 2, table.getn(data.procs) do
					text = text .. ", " .. data.procs[pi].name
				end
				table.insert(lines, { "Includes " .. text, 0.65, 0.78, 1 })
			elseif data.cast then
				table.insert(lines, { "Cast as " .. data.cast, 0.85, 0.8, 0.7 })
			elseif isProc(data.proc) then
				table.insert(lines, { "Proc.", 0.7, 0.7, 0.7 })
			end
			paintTip(data.name, iconFor(data.name), lines)
		end)
	end)
	row:SetScript("OnLeave", function()
		leaveTip()
	end)

	row.procBtns = {}
	local pi
	for pi = 1, 3 do
		local btn = CreateFrame("Button", nil, row)
		btn:SetWidth(30)
		btn:SetHeight(12)
		btn:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
		btn:SetBackdrop(panelBackdrop())
		btn:SetBackdropColor(0.08, 0.16, 0.28, 0.95)
		btn:SetBackdropBorderColor(0.35, 0.55, 0.82, 0.95)
		local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("CENTER", btn, "CENTER", 0, 0)
		label:SetText("proc")
		face(label, 9)
		label:SetTextColor(0.7, 0.86, 1)
		btn.label = label
		btn:SetScript("OnEnter", function()
			local owner = this
			trackTip(owner, function()
				local info = owner.info
				if not info then
					hideTip()
					return
				end
				local share = 0
				if meterTotal > 0 then
					share = (info.damage or 0) / meterTotal
				end
				paintTip(info.name, iconFor(info.name), {
					{ string.format("Damage %s", comma(info.damage or 0)), 1, 1, 1 },
					{ string.format("Share %s", fmtPct(share)), 0.95, 0.86, 0.62 },
					{ string.format("DPS %s", fmtRate(info.dps or 0)), 0.7, 0.92, 0.68 },
					{ string.format("Kills %d", info.kills or 0), 1, 0.82, 0.45 },
					{ "Proc.", 0.65, 0.78, 1 },
				})
			end)
			this:SetBackdropBorderColor(0.7, 0.86, 1, 1)
		end)
		btn:SetScript("OnLeave", function()
			leaveTip()
			this:SetBackdropBorderColor(0.35, 0.55, 0.82, 0.95)
		end)
		btn:EnableMouseWheel(true)
		btn:Hide()
		row.procBtns[pi] = btn
	end
	row:Hide()
	return row
end

local function createUI()
	frame = CreateFrame("Frame", "AZSSpellMeterFrame", UIParent)
	local cfg = config()
	frame:SetWidth(cfg.width or WIDTH)
	frame:SetHeight(cfg.height or (HEADER + BOTTOM + 8 * ROW_H))
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	if frame.SetResizable then
		frame:SetResizable(true)
	end
	if frame.SetMinResize then
		frame:SetMinResize(280, HEADER + BOTTOM + 3 * ROW_H)
	end
	if frame.SetMaxResize then
		frame:SetMaxResize(760, HEADER + BOTTOM + MAX_ROWS * ROW_H)
	end
	if frame.SetClampedToScreen then
		frame:SetClampedToScreen(true)
	end
	frame:SetBackdrop(panelBackdrop())
	frame:SetBackdropColor(0.05, 0.045, 0.04, 0.94)
	frame:SetBackdropBorderColor(0.58, 0.42, 0.16, 1)

	frame:SetPoint(cfg.point or "TOPLEFT", UIParent, cfg.rel or "TOPLEFT", cfg.x or 16, cfg.y or -160)

	local header = CreateFrame("Button", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	header:SetHeight(18)
	header:SetBackdrop(panelBackdrop())
	header:SetBackdropColor(0.34, 0.21, 0.06, 0.98)
	header:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function()
		if not config().locked then
			frame:StartMoving()
		end
	end)
	header:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		savePoint()
	end)

	local titleBtn = CreateFrame("Button", nil, header)
	titleBtn:SetPoint("LEFT", header, "LEFT", 6, 0)
	titleBtn:SetHeight(16)
	titleBtn:SetWidth(52)
	local titleText = titleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("LEFT", titleBtn, "LEFT", 0, 0)
	titleText:SetText("Damage")
	face(titleText, 11)
	titleText:SetTextColor(1, 0.9, 0.62)
	titleBtn:SetScript("OnEnter", function()
		local tip = "Damage dealt this run, as the game counted it."
		if state and state.base then
			tip = "Damage since the last reset, still counted by the game."
		end
		showTip(this, "RIGHT", "Damage", nil, {
			{ tip, 1, 1, 1 },
		})
	end)
	titleBtn:SetScript("OnLeave", function()
		leaveTip()
	end)

	local minBtn = CreateFrame("Button", nil, header)
	minBtn:SetPoint("RIGHT", header, "RIGHT", -3, 0)
	minBtn:SetWidth(14)
	minBtn:SetHeight(14)
	minBtn:SetBackdrop(panelBackdrop())
	minBtn:SetBackdropColor(0.16, 0.1, 0.03, 0.95)
	minBtn:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
	local minText = minBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	minText:SetPoint("CENTER", minBtn, "CENTER", 0, 1)
	minText:SetText("-")
	face(minText, 12)
	minText:SetTextColor(1, 0.86, 0.5)
	minBtn:SetScript("OnClick", function()
		config().mini = true
		local x, y = minBtn:GetCenter()
		if bubble and x and y then
			bubble:ClearAllPoints()
			bubble:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
			bubble.parked = true
		elseif bubble then
			bubble.parked = false
		end
		applyShown()
		refresh()
	end)
	minBtn:SetScript("OnEnter", function()
		minBtn:SetBackdropBorderColor(1, 0.86, 0.45, 1)
		showTip(this, "RIGHT", "Minimize", nil, {
			{ "Collapse to a small bubble. Click the bubble to open the window.", 1, 1, 1 },
		})
	end)
	minBtn:SetScript("OnLeave", function()
		minBtn:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
		leaveTip()
	end)

	local resetBtn = CreateFrame("Button", nil, header)
	resetBtn:SetPoint("RIGHT", minBtn, "LEFT", -4, 0)
	resetBtn:SetHeight(14)
	resetBtn:SetWidth(42)
	resetBtn:SetBackdrop(panelBackdrop())
	resetBtn:SetBackdropColor(0.16, 0.1, 0.03, 0.95)
	resetBtn:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
	local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	resetText:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
	resetText:SetText("Reset")
	face(resetText, 9)
	resetText:SetTextColor(1, 0.86, 0.5)
	resetBtn:SetScript("OnClick", function()
		windowReset(false)
		refresh()
		say("Reset. This window starts over. The built-in meter is unchanged.")
	end)
	resetBtn:SetScript("OnEnter", function()
		resetText:SetTextColor(1, 0.95, 0.7)
		resetBtn:SetBackdropBorderColor(1, 0.86, 0.45, 1)
		showTip(this, "RIGHT", "Reset", nil, {
			{ "Starts this window over. Damage and kills both go back to zero here.", 1, 1, 1 },
			{ "The built-in meter keeps its own numbers.", 0.75, 0.75, 0.75 },
		})
	end)
	resetBtn:SetScript("OnLeave", function()
		resetText:SetTextColor(1, 0.86, 0.5)
		resetBtn:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
		leaveTip()
	end)
	frame.resetBtn = resetBtn

	local dpsBtn = CreateFrame("Button", nil, header)
	dpsBtn:SetPoint("RIGHT", resetBtn, "LEFT", -8, 0)
	dpsBtn:SetWidth(48)
	dpsBtn:SetHeight(16)
	local dpsText = dpsBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dpsText:SetPoint("RIGHT", dpsBtn, "RIGHT", 0, 0)
	dpsText:SetJustifyH("RIGHT")
	dpsText:SetText("0 dps")
	face(dpsText, 10)
	dpsText:SetTextColor(0.78, 0.95, 0.72)
	frame.dpsText = dpsText
	frame.dpsBtn = dpsBtn
	dpsBtn:SetScript("OnEnter", function()
		local body = "The run's damage per second, from the game's own clock."
		if state and state.base then
			body = "Damage per second since the last reset, on the game's clock."
		end
		showTip(this, "LEFT", "DPS", nil, {
			{ body, 1, 1, 1 },
			{ "It pauses whenever the run pauses.", 0.75, 0.75, 0.75 },
		})
	end)
	dpsBtn:SetScript("OnLeave", function()
		leaveTip()
	end)

	local totalBtn = CreateFrame("Button", nil, header)
	totalBtn:SetPoint("RIGHT", dpsBtn, "LEFT", -10, 0)
	totalBtn:SetWidth(48)
	totalBtn:SetHeight(16)
	local totalText = totalBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	totalText:SetPoint("RIGHT", totalBtn, "RIGHT", 0, 0)
	totalText:SetJustifyH("RIGHT")
	totalText:SetText("0")
	face(totalText, 11)
	totalText:SetTextColor(1, 0.9, 0.55)
	frame.totalText = totalText
	frame.totalBtn = totalBtn
	totalBtn:SetScript("OnEnter", function()
		local tip = "Damage dealt this run, as the game counted it."
		if state and state.base then
			tip = "Damage since the last reset, still counted by the game."
		end
		showTip(this, "LEFT", "Damage", nil, {
			{ tip, 1, 1, 1 },
		})
	end)
	totalBtn:SetScript("OnLeave", function()
		leaveTip()
	end)

	local cols = CreateFrame("Frame", nil, frame)
	cols:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -20)
	cols:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -20)
	cols:SetHeight(12)
	frame.cols = cols
	local countText = cols:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", cols, "LEFT", 2, 0)
	countText:SetText("")
	face(countText, 9)
	countText:SetTextColor(0.62, 0.56, 0.46)
	frame.countText = countText
	frame.sortBtns = {}

	local function makeSortButton(key, base, width, justify)
		local btn = CreateFrame("Button", nil, cols)
		btn:SetWidth(width)
		btn:SetHeight(12)
		btn.key = key
		btn.base = base
		local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", btn, "LEFT", 0, 0)
		label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
		label:SetJustifyH(justify)
		label:SetText(base)
		face(label, 9)
		label:SetTextColor(0.55, 0.5, 0.4)
		btn.label = label
		btn:SetScript("OnClick", function()
			local cfg = config()
			local picked = this.key
			if (cfg.sort or "damage") == picked then
				if cfg.sortDir == "asc" then
					cfg.sortDir = "desc"
				else
					cfg.sortDir = "asc"
				end
			else
				cfg.sort = picked
				cfg.sortDir = "desc"
			end
			scroll = 0
			refresh()
		end)
		btn:SetScript("OnEnter", function()
			local picked = this.key
			local title = "Damage"
			local lines = {
				{ "Click to sort by the damage column.", 1, 1, 1 },
				{ "Click again to reverse the order.", 0.75, 0.75, 0.75 },
			}
			if picked == "kills" then
				title = "Kills"
				lines = {
					{ "Creatures this spell finished. Click to sort.", 1, 1, 1 },
					{ "A proc keeps kills from the spell it casts, when that spell did no damage of its own.", 0.75, 0.75, 0.75 },
					{ "Click again to reverse the order.", 0.75, 0.75, 0.75 },
				}
			elseif picked == "dps" then
				title = "DPS"
				lines = {
					{ "This spell's damage per second. Click to sort.", 1, 1, 1 },
					{ "Click again to reverse the order.", 0.75, 0.75, 0.75 },
				}
			end
			showTip(this, "RIGHT", title, nil, lines)
		end)
		btn:SetScript("OnLeave", function()
			leaveTip()
		end)
		table.insert(frame.sortBtns, btn)
		return btn
	end

	local dpsCol = makeSortButton("dps", "DPS", COL_DPS, "RIGHT")
	dpsCol:SetPoint("RIGHT", cols, "RIGHT", -2, 0)
	local dmgCol = makeSortButton("damage", "Damage", COL_DMG, "RIGHT")
	dmgCol:SetPoint("RIGHT", dpsCol, "LEFT", -6, 0)
	local killCol = makeSortButton("kills", "Kills", COL_KILL, "RIGHT")
	killCol:SetPoint("RIGHT", dmgCol, "LEFT", -6, 0)

	local scrollFrame = CreateFrame("ScrollFrame", "AZSSpellMeterScroll", frame)
	scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -HEADER)
	scrollFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -HEADER)
	scrollFrame:SetHeight(8 * ROW_H)
	scrollFrame:EnableMouseWheel(true)
	local scrollChild = CreateFrame("Frame", "AZSSpellMeterScrollChild", scrollFrame)
	scrollChild:SetWidth((cfg.width or WIDTH) - 12)
	scrollChild:SetHeight((MAX_ROWS) * ROW_H)
	scrollFrame:SetScrollChild(scrollChild)
	frame.scroll = scrollFrame
	frame.scrollChild = scrollChild

	local i
	for i = 1, ROW_POOL do
		rows[i] = createRow(scrollChild, i)
		rows[i]:SetWidth((cfg.width or WIDTH) - 12)
	end

	local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(HEADER + 6))
	face(emptyText, 11)
	emptyText:SetTextColor(0.62, 0.56, 0.46)
	emptyText:Hide()
	frame.emptyText = emptyText

	local grip = CreateFrame("Button", nil, frame)
	grip:SetWidth(16)
	grip:SetHeight(16)
	grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
	local gi
	for gi = 1, 3 do
		local mark = grip:CreateTexture(nil, "OVERLAY")
		mark:SetTexture(SOLID)
		mark:SetVertexColor(0.72, 0.56, 0.24, 0.95)
		mark:SetWidth(gi * 3)
		mark:SetHeight(1)
		mark:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1, 1 + (gi - 1) * 3)
	end
	grip:SetScript("OnEnter", function()
		showTip(this, "RIGHT", "Drag to resize", nil, nil)
	end)
	grip:SetScript("OnLeave", function()
		leaveTip()
	end)
	local function finishSize()
		if not sizing then
			return
		end
		sizing = false
		if frame.SetClampedToScreen then
			frame:SetClampedToScreen(true)
		end
		local saved = config()
		saved.width = frame:GetWidth()
		saved.height = frame:GetHeight()
		savePoint()
		refresh()
	end
	grip:SetScript("OnMouseDown", function()
		if config().locked then
			return
		end
		local scale = uiScale()
		local cx, cy = GetCursorPosition()
		sizeX = cx / scale
		sizeY = cy / scale
		sizeW = frame:GetWidth()
		sizeH = frame:GetHeight()
		sizing = true
		if frame.SetClampedToScreen then
			frame:SetClampedToScreen(false)
		end
		pinTopLeft()
	end)
	grip:SetScript("OnMouseUp", function()
		finishSize()
	end)

	local tip = CreateFrame("Frame", "AZSSpellMeterTip", UIParent)
	tip:SetFrameStrata("TOOLTIP")
	tip:SetWidth(160)
	tip:SetHeight(40)
	if tip.SetClampedToScreen then
		tip:SetClampedToScreen(true)
	end
	tip:SetBackdrop(panelBackdrop())
	tip:SetBackdropColor(0.06, 0.05, 0.04, 0.97)
	tip:SetBackdropBorderColor(0.58, 0.42, 0.16, 1)
	local iconBack = tip:CreateTexture(nil, "ARTWORK")
	iconBack:SetTexture(SOLID)
	iconBack:SetVertexColor(0, 0, 0, 1)
	iconBack:SetWidth(24)
	iconBack:SetHeight(24)
	iconBack:SetPoint("TOPLEFT", tip, "TOPLEFT", 6, -6)
	tip.iconBack = iconBack
	local tipIcon = tip:CreateTexture(nil, "OVERLAY")
	tipIcon:SetWidth(22)
	tipIcon:SetHeight(22)
	tipIcon:SetPoint("CENTER", iconBack, "CENTER", 0, 0)
	tipIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	tip.icon = tipIcon
	local tipTitle = tip:CreateFontString(nil, "OVERLAY")
	tipTitle:SetJustifyH("LEFT")
	face(tipTitle, 12)
	tipTitle:SetTextColor(1, 0.86, 0.5)
	tip.title = tipTitle
	tip.lines = {}
	local li
	for li = 1, 6 do
		local fs = tip:CreateFontString(nil, "OVERLAY")
		fs:SetJustifyH("LEFT")
		face(fs, 11)
		fs:SetTextColor(1, 1, 1)
		fs:Hide()
		tip.lines[li] = fs
	end
	tip:EnableMouse(false)
	tip:Hide()
	frame.tip = tip

	local function onWheel(delta)
		scroll = scroll - (delta or arg1 or 0) * ROW_H
		refresh()
	end
	frame:SetScript("OnMouseWheel", onWheel)
	header:EnableMouseWheel(true)
	header:SetScript("OnMouseWheel", onWheel)
	grip:EnableMouseWheel(true)
	grip:SetScript("OnMouseWheel", onWheel)
	for i = 1, ROW_POOL do
		rows[i]:EnableMouseWheel(true)
		rows[i]:SetScript("OnMouseWheel", onWheel)
		local pi
		for pi = 1, 3 do
			rows[i].procBtns[pi]:SetScript("OnMouseWheel", onWheel)
		end
	end
	scrollFrame:SetScript("OnMouseWheel", onWheel)
	cols:EnableMouseWheel(true)
	cols:SetScript("OnMouseWheel", onWheel)
	for i = 1, table.getn(frame.sortBtns) do
		frame.sortBtns[i]:EnableMouseWheel(true)
		frame.sortBtns[i]:SetScript("OnMouseWheel", onWheel)
	end
	totalBtn:EnableMouseWheel(true)
	totalBtn:SetScript("OnMouseWheel", onWheel)
	dpsBtn:EnableMouseWheel(true)
	dpsBtn:SetScript("OnMouseWheel", onWheel)
	titleBtn:EnableMouseWheel(true)
	titleBtn:SetScript("OnMouseWheel", onWheel)
	resetBtn:EnableMouseWheel(true)
	resetBtn:SetScript("OnMouseWheel", onWheel)
	minBtn:EnableMouseWheel(true)
	minBtn:SetScript("OnMouseWheel", onWheel)
	frame:SetScript("OnUpdate", function()
		if sizing then
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
				finishSize()
			else
				local scale = uiScale()
				local cx, cy = GetCursorPosition()
				cx = cx / scale
				cy = cy / scale
				local w = sizeW + (cx - sizeX)
				local h = sizeH - (cy - sizeY)
				local minH = HEADER + BOTTOM + 3 * ROW_H
				local maxH = HEADER + BOTTOM + MAX_ROWS * ROW_H
				if w < 280 then
					w = 280
				elseif w > 760 then
					w = 760
				end
				if h < minH then
					h = minH
				elseif h > maxH then
					h = maxH
				end
				frame:SetWidth(w)
				frame:SetHeight(h)
			end
		end
		local now = GetTime()
		if scanAt > 0 and now >= scanAt then
			scanAt = 0
			scanIcons()
		end
		local w, h = frame:GetWidth(), frame:GetHeight()
		if w ~= lastW or h ~= lastH then
			lastW, lastH = w, h
			local n
			local rw = rowWidth()
			for n = 1, ROW_POOL do
				rows[n]:SetWidth(rw)
			end
		end
		if watchBoot and sameLevelRestart() then
			watchBoot = false
			checkLevel()
			refresh()
		end
		frame.tick = (frame.tick or 0) + (arg1 or 0)
		if frame.tick >= 0.2 then
			frame.tick = 0
			if frame:IsShown() then
				refresh()
			end
		end
		if tipFill then
			tipFill()
		end
		placeTip()
	end)

	bubble = CreateFrame("Button", "AZSSpellMeterBubble", UIParent)
	bubble:SetFrameStrata("HIGH")
	bubble:SetWidth(48)
	bubble:SetHeight(22)
	bubble:SetMovable(true)
	bubble:EnableMouse(true)
	bubble:RegisterForDrag("LeftButton")
	bubble:RegisterForClicks("LeftButtonUp")
	if bubble.SetClampedToScreen then
		bubble:SetClampedToScreen(true)
	end
	bubble:SetBackdrop(panelBackdrop())
	bubble:SetBackdropColor(0.34, 0.21, 0.06, 0.98)
	bubble:SetBackdropBorderColor(0.85, 0.62, 0.2, 1)
	bubble:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	local bubbleText = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bubbleText:SetPoint("CENTER", bubble, "CENTER", 0, 0)
	bubbleText:SetJustifyH("CENTER")
	bubbleText:SetText("0")
	face(bubbleText, 11)
	bubbleText:SetTextColor(1, 0.9, 0.55)
	frame.bubbleText = bubbleText
	local bubbleDrag = false
	bubble:SetScript("OnDragStart", function()
		if config().locked then
			return
		end
		bubbleDrag = true
		bubble:StartMoving()
	end)
	bubble:SetScript("OnDragStop", function()
		bubble:StopMovingOrSizing()
	end)
	bubble:SetScript("OnClick", function()
		if bubbleDrag then
			bubbleDrag = false
			return
		end
		config().mini = false
		applyShown()
		refresh()
	end)
	bubble:SetScript("OnEnter", function()
		bubble:SetBackdropBorderColor(1, 0.86, 0.45, 1)
		showTip(this, "RIGHT", "Spell meter", nil, {
			{ "Click to open the window.", 1, 1, 1 },
		})
	end)
	bubble:SetScript("OnLeave", function()
		bubble:SetBackdropBorderColor(0.85, 0.62, 0.2, 1)
		leaveTip()
	end)
	bubble:SetScript("OnUpdate", function()
		if config().mini and not bubble.parked then
			if not bubble.measuring then
				frame:Show()
				bubble.measuring = true
				return
			end
			local x, y = minBtn:GetCenter()
			frame:Hide()
			bubble.measuring = nil
			if x and y then
				bubble:ClearAllPoints()
				bubble:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
				bubble.parked = true
			end
		end
		if not config().mini then
			return
		end
		bubble.tick = (bubble.tick or 0) + (arg1 or 0)
		if bubble.tick >= 0.2 then
			bubble.tick = 0
			refresh()
		end
	end)
	bubble:Hide()

	applyShown()
end

local function onCreatureDeath(msg)
	msg = strip(msg or "")
	local _, _, name = string.find(msg, "^(.+) dies%.?$")
	if not name then
		_, _, name = string.find(msg, "^You have slain (.+)!")
	end
	if name then
		noteKill(name)
		refresh()
	end
end

local function onCombat(kind)
	ingest(arg1, kind)
end

local function onEvent()
	if event == "ADDON_LOADED" and arg1 == ADDON then
		loadState()
		createUI()
		widenCombatLog()
		queueScan()
		return
	end
	if not state then
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		clockOn = true
		dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") and true or false
		if stateKey ~= playerKey() then
			loadState()
		end
		watchBoot = not sameLevelRestart()
		checkLevel()
		syncClock()
		widenCombatLog()
		queueScan()
		refresh()
	elseif event == "PLAYER_LEVEL_UP" or event == "UNIT_LEVEL" then
		if event == "UNIT_LEVEL" and arg1 ~= "player" then
			return
		end
		checkLevel()
	elseif event == "PLAYER_DEAD" then
		dead = true
		syncClock()
	elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		dead = false
		syncClock()
	elseif event == "PLAYER_LOGOUT" then
		foldTime()
	elseif event == "LOOT_OPENED" or event == "GOSSIP_SHOW" or event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" or event == "ITEM_TEXT_BEGIN" then
		beginChoice()
	elseif event == "CHAT_MSG_SYSTEM" or event == "CHAT_MSG_RAID_BOSS_EMOTE" or event == "CHAT_MSG_MONSTER_EMOTE" or event == "CHAT_MSG_MONSTER_YELL" or event == "CHAT_MSG_TEXT_EMOTE" then
		if choiceMessage(arg1) then
			beginChoice()
		end
	elseif event == "SPELLS_CHANGED" or event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
		queueScan()
	elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" or event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF" or event == "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS" then
		onCombat("yours")
	elseif event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" or event == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" then
		onCombat("periodic")
	elseif event == "CHAT_MSG_SPELL_PET_DAMAGE" then
		onCombat("pet")
	elseif event == "CHAT_MSG_COMBAT_PET_HITS" then
		onCombat("petmelee")
	elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_DEATH" then
		onCreatureDeath(arg1)
	end
end

local driver = CreateFrame("Frame", "AZSSpellMeterDriver")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_LEVEL_UP")
driver:RegisterEvent("UNIT_LEVEL")
driver:RegisterEvent("PLAYER_DEAD")
driver:RegisterEvent("PLAYER_ALIVE")
driver:RegisterEvent("PLAYER_UNGHOST")
driver:RegisterEvent("PLAYER_LOGOUT")
driver:RegisterEvent("LOOT_OPENED")
driver:RegisterEvent("GOSSIP_SHOW")
driver:RegisterEvent("QUEST_DETAIL")
driver:RegisterEvent("QUEST_PROGRESS")
driver:RegisterEvent("QUEST_COMPLETE")
driver:RegisterEvent("ITEM_TEXT_BEGIN")
driver:RegisterEvent("CHAT_MSG_SYSTEM")
driver:RegisterEvent("CHAT_MSG_RAID_BOSS_EMOTE")
driver:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
driver:RegisterEvent("CHAT_MSG_MONSTER_YELL")
driver:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
driver:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
driver:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_DEATH")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
driver:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
driver:RegisterEvent("LEARNED_SPELL_IN_TAB")
driver:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
driver:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
driver:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF")
driver:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS")
driver:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
driver:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
driver:RegisterEvent("CHAT_MSG_SPELL_PET_DAMAGE")
driver:RegisterEvent("CHAT_MSG_COMBAT_PET_HITS")
driver:SetScript("OnEvent", onEvent)

local function toggleLock()
	local cfg = config()
	cfg.locked = not cfg.locked
	if cfg.locked then
		say("Locked.")
	else
		say("Unlocked. Drag the title to move it.")
	end
end

local function toggleShown()
	local cfg = config()
	if frame:IsShown() or (bubble and bubble:IsShown()) then
		cfg.shown = false
		cfg.mini = false
		applyShown()
		restoreStockMeter()
	else
		cfg.shown = true
		cfg.mini = false
		applyShown()
		refresh()
	end
end

local function loadTest()
	resetData()
	testMeter = {
		{ name = "Shadow Bolt", dmg = 223342, dps = 3722, proc = 0 },
		{ name = "Corruption", dmg = 96440, dps = 1607, proc = 0 },
		{ name = "Immolate", dmg = 22110, dps = 368, proc = 0 },
		{ name = "Rain of Fire", dmg = 140880, dps = 2348, proc = 0 },
		{ name = "Hellfire", dmg = 80331, dps = 1339, proc = 0 },
		{ name = "Curse of Agony", dmg = 55210, dps = 920, proc = 0 },
		{ name = "Searing Pain", dmg = 12040, dps = 201, proc = 1 },
		{ name = "Blast Wave", dmg = 114900, dps = 1915, proc = 0 },
		{ name = "Pyroclasm", dmg = 296500, dps = 4942, proc = 1 },
		{ name = "Fireball", dmg = 123400, dps = 2057, proc = 0 },
		{ name = "Pyroblast", dmg = 80400, dps = 1340, proc = 0 },
		{ name = "Hot Streak", dmg = 227300, dps = 3788, proc = 1 },
		{ name = "Melee", dmg = 4300, dps = 72, proc = 0 },
	}
	queueScan()
	refresh()
	say("Sample rows loaded. /azsm reset clears them.")
end

SLASH_AZSSPELLMETER1 = "/azsm"
SLASH_AZSSPELLMETER2 = "/spellmeter"
SlashCmdList["AZSSPELLMETER"] = function(msg)
	msg = string.lower(msg or "")
	msg = string.gsub(msg, "^%s+", "")
	msg = string.gsub(msg, "%s+$", "")
	if not frame then
		say("Still loading.")
		return
	end
	if msg == "" or msg == "toggle" or msg == "show" then
		if msg == "show" then
			config().shown = true
			config().mini = false
			applyShown()
			refresh()
		else
			toggleShown()
		end
	elseif msg == "hide" then
		config().shown = false
		config().mini = false
		applyShown()
		restoreStockMeter()
	elseif msg == "reset" then
		windowReset(true)
		refresh()
		say("Reset. This window starts over. The built-in meter is unchanged.")
	elseif msg == "lock" then
		toggleLock()
	elseif msg == "test" then
		config().shown = true
		config().mini = false
		applyShown()
		loadTest()
	elseif msg == "debug" then
		local phase = "none"
		if AZS_GetPhase then
			phase = AZS_GetPhase() or "none"
		end
		local t = -1
		if AZS_GetRunTime then
			t = AZS_GetRunTime() or -1
		end
		local lines = 0
		if AZS_METER then
			lines = table.getn(AZS_METER)
		end
		say(string.format("meter %s  dps %s  phase %s  time %.1f  lines %d  kills %d", comma(meterTotal), fmtRate(meterDps), tostring(phase), t, lines, state and state.kills or 0))
		if lastRaw ~= "" then
			say(lastRaw)
		end
	else
		say("/azsm show, hide, reset, lock, test, debug")
	end
end
