-- Per-spell damage for Azeroth Survivors (benilla, interface 1.12).
-- Damage, healing, and boss damage come from the game's own meters.
-- Damage taken is the game's taken list, by source.
-- A thin bar on a row is that spell's cooldown. The total's tooltip lists build stats.
-- Reset remembers the numbers for the view you are on and shows only what it adds afterwards.
-- Kills are credited from the combat log on the damage view. They keep counting
-- while another view is open, and they are not drawn there. The log names spells
-- in English; a localized meter is joined to those kills by the spell icon.
-- DPS is a window of the run clock. It is 10 seconds unless the player picks
-- another length, or the average since the start.
-- A proc is grouped onto the spell it casts (Hot Streak onto Pyroblast). One that
-- casts several spells is split across the ones on the meter. The row is that
-- spell; the proc's own numbers are on its button.
-- Rows sit in a scroll frame at a fixed height. The frame clips whatever does not
-- fit, so a resize can leave the last spell only partly in view.

local ADDON = "AZSSpellMeter"
local K = {
	MAX_ROWS = 24,
	ROW_POOL = 25,
	ROW_H = 16,
	WRAP_H = 24,
	SOLID = "Interface\\Buttons\\WHITE8X8",
	WIDTH = 394,
	MODE_H = 16,
	COL_H = 12,
	HEADER = 51,
	BOTTOM = 8,
	COL_KILL = 40,
	COL_DMG = 50,
	COL_PCT = 40,
	COL_DPS = 36,
	DETACH_H = 35,
	CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes",
}
local CLASS_ICON = {
	warrior = { 0, 0.25, 0, 0.25 },
	mage = { 0.25, 0.49609375, 0, 0.25 },
	rogue = { 0.49609375, 0.7421875, 0, 0.25 },
	druid = { 0.7421875, 0.98828125, 0, 0.25 },
	hunter = { 0, 0.25, 0.25, 0.5 },
	shaman = { 0.25, 0.49609375, 0.25, 0.5 },
	priest = { 0.49609375, 0.7421875, 0.25, 0.5 },
	warlock = { 0.7421875, 0.98828125, 0.25, 0.5 },
	paladin = { 0, 0.25, 0.5, 0.75 },
}

local TAKEN_LABEL = {
	["boss melee"] = "Boss melee",
	["boss spell"] = "Boss spells",
	["elite"] = "Elites",
	["mob melee"] = "Mob melee",
	["mob spell"] = "Mob spells",
	["area"] = "Ground",
}
local TAKEN_ICON = {
	["boss melee"] = "Interface\\Icons\\Ability_Warrior_SavageBlow",
	["boss spell"] = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
	["elite"] = "Interface\\Icons\\Ability_Creature_Cursed_01",
	["mob melee"] = "Interface\\Icons\\INV_Sword_04",
	["mob spell"] = "Interface\\Icons\\Spell_Nature_Lightning",
	["area"] = "Interface\\Icons\\Spell_Fire_Fire",
}
local seenPhase

local frame
local bubble
local rows = {}
local sorted = {}
local icons = {}
local state
local scroll = 0
local popped = {}
local built = {}
local VIEW_TITLE = {
	damage = "Damage",
	healing = "Healing",
	boss = "Boss",
	taken = "Taken",
	party = "Party",
}
local HEADER_TINT = {
	damage = { 0.42, 0.24, 0.06, 0.90, 0.66, 0.22 },
	healing = { 0.10, 0.28, 0.14, 0.45, 0.78, 0.40 },
	boss = { 0.40, 0.16, 0.06, 0.90, 0.45, 0.16 },
	taken = { 0.36, 0.12, 0.10, 0.85, 0.35, 0.28 },
	party = { 0.12, 0.18, 0.36, 0.45, 0.62, 0.95 },
}
local LOOK = {
	scale = 1,
	cd = true,
	panel = { 0.05, 0.04, 0.03, 0.82 },
	border = { 0.78, 0.58, 0.22, 1 },
	damage = { 0.90, 0.66, 0.22, 1 },
	healing = { 0.45, 0.78, 0.40, 1 },
	boss = { 0.90, 0.45, 0.16, 1 },
	taken = { 0.85, 0.35, 0.28, 1 },
	party = { 0.45, 0.62, 0.95, 1 },
}
local settings

local function tone(r, g, b)
	return r + (1 - r) * 0.45, g + (1 - g) * 0.45, b + (1 - b) * 0.45
end
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
local dragging = false
local toldClamp = false
local toldHidden = false

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
	if cfg.learned then
		local learnedName, learnedPath
		for learnedName, learnedPath in pairs(cfg.learned) do
			if learnedPath and learnedPath ~= "" and not icons[learnedName] then
				icons[learnedName] = learnedPath
			end
		end
	end
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
local ingest
local noteKill
do
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

local function petAttacker(name)
	name = cleanName(name)
	if not name then
		return "Pet"
	end
	name = string.gsub(name, "^Your ", "")
	if name == "pet" then
		return "Pet"
	end
	return name
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
			return petAttacker(attacker), amount, true, cleanName(victim)
		end
		_, _, attacker, victim, amount = string.find(msg, "^(.+) hits (.+) for (%d+)")
		if amount and not string.find(attacker or "", "'s$") then
			return petAttacker(attacker), amount, false, cleanName(victim)
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
	local row = state.spells[spell]
	if not row then
		row = { damage = 0, hits = 0, crits = 0, kills = 0 }
		state.spells[spell] = row
	end
	row.hits = (row.hits or 0) + 1
	if crit then
		row.crits = (row.crits or 0) + 1
	end
	return true
	end

	ingest = function(msg, kind)
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

	noteKill = function(name)
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
end

local rateHist = {}

local function clearRecentRate(mode)
	if not mode then
		rateHist = {}
		return
	end
	rateHist[mode] = nil
end

-- Seconds of run time DPS looks back. Nil in saved settings means 10.
-- dpsAll uses the meter's own average instead, which is the whole run,
-- or the time since Reset on a view that was reset.
local function rateSeconds()
	local saved = config().look
	if saved and saved.dpsAll then
		return 0
	end
	local n = nil
	if saved then
		n = tonumber(saved.dps)
	end
	if not n or n < 5 then
		return 10
	end
	if n > 120 then
		return 120
	end
	return n
end

-- Damage now, minus the sample from one window of run time ago.
-- The first second keeps the meter's own average so the number does not spike.
local function recentRate(mode, now, total, bucket)
	local window = rateSeconds()
	if window < 5 then
		return nil
	end
	if not mode or mode == "" then
		return nil
	end
	if not now or now < 0 then
		now = 0
	end
	local hist = rateHist[mode]
	if not hist then
		hist = {}
		rateHist[mode] = hist
	end
	local n = table.getn(hist)
	if n > 0 and hist[n].t > now + 0.05 then
		hist = {}
		rateHist[mode] = hist
		n = 0
	end
	local last = nil
	if n > 0 then
		last = hist[n]
	end
	if not last or (now - last.t) >= 0.25 then
		local snap = { t = now, total = total, spells = {} }
		local name, row
		for name, row in pairs(bucket) do
			snap.spells[name] = row.damage or 0
		end
		table.insert(hist, snap)
	end
	while table.getn(hist) > 0 and (now - hist[1].t) > window do
		table.remove(hist, 1)
	end
	local base = hist[1]
	if not base then
		return nil
	end
	local span = now - base.t
	if span < 1 then
		return nil
	end
	if span > window then
		span = window
	end
	local name, row
	for name, row in pairs(bucket) do
		local dealt = (row.damage or 0) - (base.spells[name] or 0)
		if dealt < 0 then
			dealt = 0
		end
		row.dps = dealt / span
	end
	local header = total - (base.total or 0)
	if header < 0 then
		header = 0
	end
	return header / span
end

local colHold = {}

local function clearColHold(mode)
	local win, held
	for win, held in pairs(colHold) do
		if mode then
			held[mode] = nil
		else
			colHold[win] = nil
		end
	end
end

-- A column grows as soon as a number needs it. It shrinks only after the
-- narrower width has been enough for 10 seconds, or when a reset clears it.
local function holdWidth(win, mode, key, needed, now)
	if not mode then
		mode = "damage"
	end
	local byWin = colHold[win]
	if not byWin then
		byWin = {}
		colHold[win] = byWin
	end
	local byMode = byWin[mode]
	if not byMode then
		byMode = {}
		byWin[mode] = byMode
	end
	local slot = byMode[key]
	if not slot then
		slot = { w = needed }
		byMode[key] = slot
		return needed
	end
	if needed > slot.w + 1 then
		slot.w = needed
		slot.since = nil
	elseif needed < slot.w - 1 then
		if not slot.since then
			slot.since = now
		elseif now - slot.since >= 10 then
			slot.w = needed
			slot.since = nil
		end
	else
		slot.since = nil
	end
	return slot.w
end

local function resetData()
	if not state then
		loadState()
	end
	clearRecentRate()
	clearColHold()
	state.spells = {}
	state.total = 0
	state.kills = 0
	state.elapsed = 0
	state.anchor = nil
	state.base = nil
	state.baseTotal = nil
	state.baseTime = nil
	state.healBase = nil
	state.healBaseTotal = nil
	state.healBaseTime = nil
	state.bossBase = nil
	state.bossBaseTotal = nil
	state.bossBaseTime = nil
	state.takenBase = nil
	state.takenBaseTotal = nil
	state.takenBaseTime = nil
	state.partyBase = nil
	state.partyBaseTotal = nil
	state.partyBaseTime = nil
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
	state.petName = nil
	state.petIcon = nil
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

local function asTexture(texture)
	if not texture or texture == "" then
		return nil
	end
	if string.find(texture, "\\", 1, true) or string.find(texture, "/", 1, true) then
		return texture
	end
	local head = string.sub(texture, 1, 4)
	if head == "INV_" or head == "Spel" or head == "Abil" or head == "Trad" then
		return "Interface\\Icons\\" .. texture
	end
	return nil
end

local function rememberIcon(name, texture)
	local path = asTexture(texture)
	if name and path and name ~= "" then
		icons[name] = path
	end
end

local function usableIcon(path)
	if not path or path == "" then
		return nil
	end
	if string.find(string.lower(path), "questionmark", 1, true) then
		return nil
	end
	return path
end

local FALLBACK_ICONS = {
	Melee = "Interface\\Icons\\INV_Sword_04",
	["Damage Shield"] = "Interface\\Icons\\Spell_Nature_Thorns",
	Pet = "Interface\\Icons\\Ability_Hunter_BeastCall",
}

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Talents the meter names on their own, and the spell the combat log actually prints.
-- Built from the game's talent text. Pyroclasm's explosion is logged as Blast Wave.
-- A list is every spell that talent can cast. One spell takes the whole proc.
-- Several spells that are all on the meter share it, so the damage is not counted twice.
local PROC_CAST = {
	["Pyroclasm"] = { "Blast Wave" },
	["Hot Streak"] = { "Pyroblast" },
	["Arcane Concentration"] = { "Arcane Explosion" },
	["Shadowy Apparitions"] = { "Mind Blast" },
	["Maelstrom Weapon"] = { "Chain Lightning" },
	["Lightning Overload"] = { "Lightning Bolt", "Chain Lightning" },
	["Windfury"] = { "Lightning Bolt", "Earth Shock", "Frost Shock" },
	["Elemental Mastery"] = { "Chain Lightning" },
	["Rampage"] = { "Whirlwind" },
	["Flurry"] = { "Whirlwind", "Bloodthirst" },
	["Bladestorm"] = { "Whirlwind" },
	["Last Stand"] = { "Shield Slam" },
	["Shockwave"] = { "Shield Slam" },
	["Daybreak"] = { "Holy Wrath" },
	["Hallowed Ground"] = { "Consecration" },
	["Divine Intervention"] = { "Consecration" },
	["The Art of War"] = { "Exorcism" },
	["Frenzy"] = { "Multi-Shot" },
	["Rapid Fire"] = { "Aimed Shot" },
	["Counterattack"] = { "Explosive Trap" },
	["Explosive Ammunition"] = { "Auto Shot", "Multi-Shot" },
	["Mutilate"] = { "Sinister Strike", "Backstab" },
	["Riposte"] = { "Ghostly Strike" },
	["Killing Spree"] = { "Sinister Strike" },
	["Blade Flurry"] = { "Sinister Strike", "Eviscerate" },
	["Preparation"] = { "Gouge" },
	["Shadow Dance"] = { "Backstab", "Eviscerate" },
	["Chastise"] = { "Holy Nova" },
	["Nightfall"] = { "Shadow Bolt" },
	["Shadow Cleave"] = { "Shadow Bolt" },
	["Conflagrate"] = { "Shadow Bolt", "Searing Pain" },
	["Splitting Ice"] = { "Frostbolt" },
	["Omen of Clarity"] = { "Starfire" },
	["Starfall"] = { "Starfire" },
	["Leader of the Pack"] = { "Swipe" },
	["Nature's Grasp"] = { "Entangling Roots" },
	["Sweeping Strikes"] = { "Cleave", "Mortal Strike", "Execute" },
}

-- Custom talents are not in Spell.dbc, so the generated icon list has no row for them.
local EXTRA_ICONS = {
	["Hot Streak"] = "Spell_Fire_Fireball02",
	["Windfury"] = "Spell_Nature_Cyclone",
	["Lightning Overload"] = "Spell_Nature_CallStorm",
	["Shadowy Apparitions"] = "Spell_Shadow_Haunting",
	["Seed of Corruption"] = "Spell_Shadow_CurseOfMannoroth",
	["Maelstrom Weapon"] = "Spell_Nature_Lightning",
	["Leech"] = "Spell_Shadow_LifeDrain",
	["Onyxia Tooth Pendant"] = "INV_Jewelry_Necklace_09",
	["Choker of the Fire Lord"] = "INV_Jewelry_Amulet_05",
	["Choker of Enlightenment"] = "INV_Jewelry_Necklace_10",
	["Prestor's Talisman of Connivery"] = "INV_Jewelry_Necklace_17",
	["Animated Chain Necklace"] = "INV_Jewelry_Necklace_01",
	["Woven Ivy Necklace"] = "INV_Misc_Herb_15",
	["Amulet of the Darkmoon"] = "INV_Jewelry_Necklace_14",
	["Jeklik's Opaline Talisman"] = "INV_Jewelry_Necklace_03",
	["The Eye of Hakkar"] = "INV_Jewelry_Necklace_22",
	["Medallion of Steadfast Might"] = "INV_Jewelry_Amulet_03",
	["Amulet of Vek'nilash"] = "INV_Jewelry_Necklace_AhnQiraj_01",
	["Pendant of the Fallen Dragon"] = "INV_Jewelry_Necklace_12",
	["Malice Stone Pendant"] = "INV_Jewelry_Necklace_29",
	["Infernal"] = "Spell_Shadow_SummonInfernal",
	["Doomguard"] = "Spell_Shadow_SummonInfernal",
	["Felguard"] = "Spell_Shadow_Metamorphosis",
	["Divine Storm"] = "Spell_Holy_SealOfRighteousness",
	["Imp"] = "Spell_Shadow_SummonImp",
	["Felhunter"] = "Spell_Shadow_SummonFelHunter",
	["Succubus"] = "Spell_Shadow_SummonSuccubus",
	["Pit Lord"] = "Spell_Shadow_UnholyStrength",
	["Pets"] = "Ability_Hunter_BeastCall",
	["Water Elemental"] = "Spell_Frost_SummonWaterElemental",
	["Treant"] = "Spell_Nature_ForceOfNature",
	["Spirit Wolf"] = "Spell_Nature_SpiritWolf",
	["Wolf"] = "Ability_Hunter_Pet_Wolf",
	["Raptor"] = "Ability_Hunter_Pet_Raptor",
	["Amulet of the Ancients"] = "INV_Jewelry_Necklace_13",
	["Amulet of the Inferno"] = "INV_Jewelry_Necklace_AhnQiraj_03",
	["Arcane Fortitude"] = "Spell_Arcane_ArcaneResilience",
	["Arcane Reach"] = "Spell_Arcane_StarFire",
	["Archimtiros' Ring of Reckoning"] = "INV_Jewelry_Ring_40",
	["Ardent Defender"] = "Spell_Holy_HolyProtection",
	["Band of Accuria"] = "INV_Jewelry_Ring_15",
	["Blackhand's Breadth"] = "INV_Misc_ArmorKit_09",
	["Blessed Life"] = "Spell_Holy_GreaterBlessingofSanctuary",
	["Blooddrinker's Band"] = "INV_Jewelry_Ring_49Naxxramas",
	["Breath of the Black Dragon"] = "INV_Jewelry_Necklace_27Naxxramas",
	["Call of the Elements"] = "Spell_Totem_WardOfDraining",
	["Contagion"] = "Spell_Shadow_PlagueCloud",
	["Dashing Scarlet Cloak"] = "INV_Misc_Cape_08",
	["Daybreak"] = "Spell_Holy_Excorcism",
	["Defias Bandana"] = "INV_Misc_Bandana_03",
	["Demonic Empowerment"] = "Spell_Nature_RemoveCurse",
	["Demonic Supremacy"] = "Spell_Shadow_CurseOfAchimonde",
	["Explosive Ammunition"] = "Spell_Fire_SelfDestruct",
	["Ferocious Inspiration"] = "Ability_Hunter_BeastCall",
	["Fortified"] = "Ability_Warrior_ShieldWall",
	["Gnomish Goggles"] = "INV_Helmet_47",
	["Gnomish Universal Remote"] = "INV_Misc_PocketWatch_01",
	["Gold-sniffer"] = "INV_Misc_Coin_01",
	["Hallowed Ground"] = "Spell_Holy_SealOfProtection",
	["Hammer of the Righteous"] = "Spell_Holy_BlessingOfProtection",
	["Heart of the Earthshaker"] = "INV_Jewelry_Necklace_AhnQiraj_02",
	["Heavy Dark Iron Ring"] = "INV_Jewelry_Ring_14",
	["Heavy Shield"] = "INV_Shield_05",
	["Holy Concentration"] = "Spell_Holy_SpellWarding",
	["Holy Guidance"] = "Spell_Holy_SealOfSalvation",
	["Horde Officer's Tabard"] = "INV_Misc_TabardPVP_03",
	["Horn of the Warchief"] = "INV_Misc_Horn_01",
	["Improved Berserker Stance"] = "Ability_Racial_Avatar",
	["Improved Consecration"] = "Spell_Holy_InnerFire",
	["Improved Ice Barrier"] = "Spell_Ice_Lament",
	["Improved Multi-Shot"] = "Ability_UpgradeMoonGlaive",
	["Improved Shield Slam"] = "Ability_Warrior_ShieldBash",
	["Improved Whirlwind"] = "Ability_Whirlwind",
	["Insignia of the Horde"] = "INV_Jewelry_TrinketPVP_02",
	["Keen Eye"] = "INV_Misc_Spyglass_02",
	["Kill Shot"] = "INV_Weapon_Rifle_08",
	["Killing Spree"] = "Ability_Rogue_Sprint",
	["Lifegiving Gem"] = "INV_Misc_Gem_Pearl_05",
	["Light's Grace"] = "Spell_Holy_SearingLight",
	["Long Leash"] = "Ability_Hunter_BeastCall",
	["Major Soulstone"] = "INV_Misc_Orb_04",
	["Mark of Fordring"] = "INV_Jewelry_Talisman_07",
	["Master Dragonslayer's Ring"] = "INV_Jewelry_Ring_41",
	["Medallion of the Bladestorm"] = "INV_Jewelry_Necklace_30Naxxramas",
	["Mortal Wounds"] = "Ability_Warrior_SavageBlow",
	["Mutilate"] = "INV_Weapon_ShortBlade_05",
	["Onyxia Blood Talisman"] = "Spell_Shadow_LifeDrain",
	["Opening Hand"] = "INV_Misc_Book_09",
	["Pact of the Annihilan"] = "Spell_Shadow_UnholyStrength",
	["Pendant of the Plague"] = "INV_Jewelry_Necklace_18",
	["Piercing Shots"] = "Ability_PierceDamage",
	["Pristine Enchanted South Seas Kelp"] = "INV_Jewelry_Necklace_26",
	["Protection"] = "Spell_Holy_DevotionAura",
	["Purifying Power"] = "Spell_Holy_Purify",
	["Quick Paws"] = "Ability_Hunter_Pet_Cat",
	["Quick Strike Ring"] = "INV_Jewelry_Ring_07",
	["Radiance"] = "Spell_Holy_HolyNova",
	["Rapture"] = "Spell_Holy_PowerInfusion",
	["Ring of Spell Power"] = "INV_Jewelry_Ring_38",
	["Ring of the Devoured"] = "INV_Jewelry_Ring_AhnQiraj_05",
	["Royal Seal of Eldre'Thalas"] = "INV_Jewelry_Talisman_10",
	["Rune-hound"] = "INV_Misc_Rune_01",
	["Sacred Duty"] = "Spell_Holy_DivineIntervention",
	["Sanctified Light"] = "Spell_Holy_HealingFocus",
	["Seal of the Damned"] = "INV_Jewelry_Ring_51Naxxramas",
	["Second Thoughts"] = "Spell_Nature_TimeStop",
	["Shadow Dance"] = "Spell_Shadow_LifeDrain",
	["Shadow Embrace"] = "Spell_Shadow_AbominationExplosion",
	["Shield Mastery"] = "Ability_Defend",
	["Soul Devourer"] = "Spell_Shadow_SummonFelHunter",
	["Spiritual Attunement"] = "Spell_Holy_BlessedRecovery",
	["Star of Mystaria"] = "INV_Enchant_EssenceMagicLarge",
	["Stormcaller's Amulet"] = "INV_Jewelry_Necklace_16",
	["Summon Infernal"] = "Spell_Shadow_SummonInfernal",
	["Tabard of the Horde"] = "INV_Misc_TabardPVP_01",
	["Talisman of the Tempest"] = "INV_Jewelry_Necklace_AhnQiraj_04",
	["Talvash's Enhancing Necklace"] = "INV_Jewelry_Necklace_02",
	["The Art of War"] = "Spell_Holy_Excorcism_02",
	["The Eternal Talisman"] = "INV_Jewelry_Necklace_19",
	["The Reaper's Amulet"] = "INV_Jewelry_Necklace_28Naxxramas",
	["Tiny Gordok"] = "INV_Crown_01",
	["Titan"] = "Ability_Warrior_DefensiveStance",
	["Toxic Bloom"] = "Spell_Nature_NullifyPoison",
	["Trauma"] = "Ability_Warrior_DecisiveStrike",
	["Tree of Life"] = "Spell_Nature_ResistNature",
	["Veteran's Lessons"] = "INV_Misc_Book_11",
	["Warsong Battle Tabard"] = "INV_Shirt_GuildTabard_01",
	["Weighted Hammer"] = "Spell_Holy_SealOfMight",
	["Wisp-herder"] = "Spell_Nature_WispSplode",
	["Zul'Gurub Mask"] = "INV_Mask_02",
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

local function keepIcon(name, texture)
	local path = usableIcon(asTexture(texture) or texture)
	if not path or not name or name == "" then
		return nil
	end
	if (AZSSpellMeterIcon and AZSSpellMeterIcon[name]) or EXTRA_ICONS[name] or FALLBACK_ICONS[name] then
		return nil
	end
	icons[name] = path
	local cfg = config()
	if not cfg.learned then
		cfg.learned = {}
	end
	cfg.learned[name] = path
	return path
end

local function itemIcon(name)
	if not name or name == "" or not GetItemInfo then
		return nil
	end
	if icons[name] then
		return icons[name]
	end
	local _, _, _, _, _, _, _, _, ninth, tenth = GetItemInfo(name)
	local path = asTexture(tenth) or asTexture(ninth)
	if path then
		return keepIcon(name, path) or path
	end
	return nil
end

local function iconFor(name)
	local tex = iconLookup(name)
	if tex ~= QUESTION then
		return tex
	end
	if AZSSpellMeterName and AZSSpellMeterName[name] and AZSSpellMeterName[name] ~= name then
		name = AZSSpellMeterName[name]
		tex = iconLookup(name)
		if tex ~= QUESTION then
			return tex
		end
	end
	local casts = PROC_CAST[name]
	if casts and casts[1] and casts[1] ~= name then
		local via = iconLookup(casts[1])
		if via ~= QUESTION then
			return via
		end
	end
	local fromItem = itemIcon(name)
	if fromItem then
		return fromItem
	end
	-- "Pendant of the Plague: Moonfire" is an item's share of a spell.
	-- The spell half is what the row is actually showing.
	local _, _, left, right = string.find(name, "^(.-): (.+)$")
	if left and right and left ~= "" and right ~= "" then
		local spellTex = iconFor(right)
		if spellTex ~= QUESTION then
			return spellTex
		end
		local itemTex = iconFor(left)
		if itemTex ~= QUESTION then
			return itemTex
		end
	end
	return QUESTION
end

local function rowIcon(data)
	local path = usableIcon(data and data.iconPath)
	if path then
		return path
	end
	return iconFor(data and data.name)
end

local function noteItemText(msg)
	if not msg or not GetItemInfo or not string.find(msg, "|Hitem:", 1, true) then
		return
	end
	local start = 1
	while true do
		local s, e, body, shown = string.find(msg, "|Hitem:([^|]+)|h%[(.-)%]|h", start)
		if not s then
			break
		end
		local _, _, _, _, _, _, _, _, _, tex = GetItemInfo("item:" .. body)
		local path = asTexture(tex)
		if not path then
			local _, _, _, _, _, _, _, _, ninth, tenth = GetItemInfo(body)
			path = asTexture(tenth) or asTexture(ninth)
		end
		if path and shown and shown ~= "" then
			keepIcon(shown, path)
		end
		start = e + 1
	end
end

local function scanCarriedItems()
	if GetInventoryItemLink and GetInventoryItemTexture then
		local slot
		for slot = 1, 19 do
			local link = GetInventoryItemLink("player", slot)
			local tex = GetInventoryItemTexture("player", slot)
			if link and tex then
				local _, _, name = string.find(link, "%[(.+)%]")
				keepIcon(name, tex)
			end
		end
	end
	if GetContainerNumSlots and GetContainerItemLink and GetContainerItemInfo then
		local bag
		for bag = 0, 4 do
			local n = GetContainerNumSlots(bag) or 0
			local slot
			for slot = 1, n do
				local link = GetContainerItemLink(bag, slot)
				local tex = GetContainerItemInfo(bag, slot)
				if link and tex then
					local _, _, name = string.find(link, "%[(.+)%]")
					keepIcon(name, tex)
				end
			end
		end
	end
end

local spellSay = {}

local function englishSpell(name)
	if name and AZSSpellMeterName and AZSSpellMeterName[name] and AZSSpellMeterName[name] ~= "" then
		return AZSSpellMeterName[name]
	end
	return name
end

-- The name this client uses. A French hero and a German hero each see their own wording.
-- Global on purpose: the file is already at the 200 local-variable limit.
function clientSpell(name)
	local _, _, left, right = string.find(name, "^(.-): (.+)$")
	if left and right and left ~= "" and right ~= "" then
		local enFull = englishSpell(name)
		local knownFull = (AZSSpellMeterIcon and (AZSSpellMeterIcon[name] or (enFull and AZSSpellMeterIcon[enFull])))
			or EXTRA_ICONS[name] or (enFull and EXTRA_ICONS[enFull])
		if not knownFull then
			return clientSpell(left) .. ": " .. clientSpell(right)
		end
	end
	local en = englishSpell(name)
	local loc = "enUS"
	if GetLocale then
		loc = GetLocale() or loc
	end
	if loc == "enGB" then
		loc = "enUS"
	end
	if loc ~= "enUS" then
		local pack = AZSSpellMeterLocale and AZSSpellMeterLocale[loc]
		if pack and en and pack[en] and pack[en] ~= "" then
			return pack[en]
		end
		if spellSay[en] then
			return spellSay[en]
		end
		return name
	end
	return en
end

local function castList(name)
	local list = PROC_CAST[englishSpell(name)]
	if not list or not list[1] then
		return nil
	end
	local text = list[1]
	if spellSay[text] then
		text = spellSay[text]
	end
	local i
	local n = table.getn(list)
	for i = 2, n do
		local part = list[i]
		if spellSay[part] then
			part = spellSay[part]
		end
		if i == n then
			text = text .. " or " .. part
		else
			text = text .. ", " .. part
		end
	end
	return text
end

local scanTip
local scanTipMissing
local spellSlot = {}
local spellTipCache = {}

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
	local wiped
	for wiped in pairs(spellSlot) do
		spellSlot[wiped] = nil
	end
	for wiped in pairs(spellTipCache) do
		spellTipCache[wiped] = nil
	end
	for wiped in pairs(spellSay) do
		spellSay[wiped] = nil
	end
	local function noteSlot(name, slot, overwrite)
		if not name or name == "" then
			return
		end
		if overwrite or not spellSlot[name] then
			spellSlot[name] = slot
		end
		if AZSSpellMeterName then
			local en = AZSSpellMeterName[name]
			if en and en ~= name and (overwrite or not spellSlot[en]) then
				spellSlot[en] = spellSlot[name]
			end
			if en and en ~= name and (overwrite or not spellSay[en]) then
				spellSay[en] = name
			end
		end
	end
	if GetSpellName and GetSpellTexture then
		local book = BOOKTYPE_SPELL or "spell"
		local i = 1
		while true do
			local name = GetSpellName(i, book)
			if not name then
				break
			end
			noteSlot(name, { i, book }, true)
			rememberIcon(name, GetSpellTexture(i, book))
			i = i + 1
		end
		book = BOOKTYPE_PET or "pet"
		i = 1
		while true do
			local name = GetSpellName(i, book)
			if not name then
				break
			end
			if not spellSlot[name] then
				noteSlot(name, { i, book }, false)
				rememberIcon(name, GetSpellTexture(i, book))
			end
			i = i + 1
		end
	end
	if GetNumTalentTabs and GetNumTalents and GetTalentInfo then
		local okTabs, tabs = pcall(GetNumTalentTabs)
		local tab = 1
		if okTabs and tabs and tabs > 0 then
			while tab <= tabs do
				local okN, n = pcall(GetNumTalents, tab)
				local i = 1
				if okN and n and n > 0 then
					while i <= n do
						local okInfo, name, icon = pcall(GetTalentInfo, tab, i)
						if okInfo and name and name ~= "" then
							if not spellSlot[name] then
								noteSlot(name, { tab, i, "talent" }, false)
							end
							if icon and not icons[name] then
								rememberIcon(name, icon)
							end
						end
						i = i + 1
					end
				end
				tab = tab + 1
			end
		end
	end
	scanCarriedItems()
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

-- Lines from the local hero's own build. A party spell should not show them.
local function partyTipSkip(text)
	if not text or text == "" then
		return true
	end
	local skip = {
		"Not learned yet",
		"Jeszcze nieopanowane",
		"Zatím nenaučeno",
		"Noch nicht erlernt",
		"Ainda não aprendido",
		"Aún no aprendido",
		"Pas encore appris",
		"neînvățată",
		"Henüz öğrenilmedi",
		"не изучено",
		"не вивчено",
		"尚未学会",
		"未習得",
		"아직 배우지 않음",
		"Your bonuses",
		"Twoje premie",
		"Tvé bonusy",
		"Deine Boni",
		"Seus bônus",
		"Tus bonificaciones",
		"Vos bonus",
		"Bonusurile tale",
		"Bonusların",
		"Ваши бонусы",
		"Ваші бонуси",
		"你的加成",
		"あなたのボーナス",
		"보너스:",
		"chance to crit",
		"chance to cast",
		"szansy na trafienie krytyczne",
		"szansy na podwójne",
		"šance na kritický zásah",
		"šance seslat dvakrát",
		"Chance auf kritischen Treffer",
		"doppelt zu wirken",
		"de chance de crítico",
		"de chance de lançar duas vezes",
		"probabilidad de crítico",
		"probabilidad de lanzarse dos veces",
		"chances de critique",
		"chances de se lancer deux fois",
		"șansă de critic",
		"șansă de lansare dublă",
		"hasarla kritik",
		"iki kez kullanılır",
		"шанс крита",
		"шанс применить дважды",
		"шансу на крит",
		"шансу спрацювати двічі",
		"几率暴击",
		"几率施放两次",
		"でクリティカル",
		"2回発動",
		"확률로 치명타",
		"두 번 시전",
	}
	local i
	for i = 1, table.getn(skip) do
		if string.find(text, skip[i], 1, true) then
			return true
		end
	end
	return false
end

-- Rank, cost, cast time, and what the spell does, from the game's own tooltip.
-- Talents and spells this hero knows are read directly. A party spell in another
-- language is matched back to that entry when the game has a translation for it.
local function spellTipLines(name)
	if not name or name == "" then
		return nil
	end
	local cached = spellTipCache[name]
	if cached then
		return cached
	end
	local slot = spellSlot[name]
	local key = name
	if AZSSpellMeterName and AZSSpellMeterName[name] and AZSSpellMeterName[name] ~= "" then
		key = AZSSpellMeterName[name]
	end
	if not slot then
		slot = spellSlot[key]
	end
	if not slot then
		local casts = PROC_CAST[key]
		if casts and casts[1] and casts[1] ~= key then
			slot = spellSlot[casts[1]]
		end
	end
	if not slot then
		return nil
	end
	local tip = actionTip()
	if not tip then
		return nil
	end
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	tip:SetAlpha(0)
	local ok
	if slot[3] == "talent" then
		if not tip.SetTalent then
			tip:Hide()
			tip:SetAlpha(1)
			return nil
		end
		ok = pcall(tip.SetTalent, tip, slot[1], slot[2])
	else
		if not tip.SetSpell then
			tip:Hide()
			tip:SetAlpha(1)
			return nil
		end
		ok = pcall(tip.SetSpell, tip, slot[1], slot[2])
	end
	if not ok then
		tip:Hide()
		tip:SetAlpha(1)
		return nil
	end
	local lines = {}
	local i = 1
	while i <= 12 do
		local left = getglobal("AZSSpellMeterScanTipTextLeft" .. i)
		local text = left and left:GetText()
		if not text or text == "" then
			break
		end
		local right = getglobal("AZSSpellMeterScanTipTextRight" .. i)
		local side = right and right:GetText()
		if i == 1 then
			text = side
		elseif side and side ~= "" then
			text = text .. "  " .. side
		end
		if text and text ~= "" and not partyTipSkip(text) then
			local r, g, b = 1, 1, 1
			if left.GetTextColor then
				r, g, b = left:GetTextColor()
			end
			lines[table.getn(lines) + 1] = { text, r or 1, g or 1, b or 1 }
		end
		i = i + 1
	end
	tip:Hide()
	tip:SetAlpha(1)
	if table.getn(lines) < 1 then
		return nil
	end
	spellTipCache[name] = lines
	return lines
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

local function rowWidth(win)
	if not win then
		win = frame
	end
	if not win then
		return K.WIDTH - 16
	end
	local w = win:GetWidth() - 16
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
	if runSeen and t + 1 < runSeen and ((state.kills or 0) > 0 or state.base or state.healBase or state.bossBase or state.takenBase or state.partyBase) then
		state.spells = {}
		state.kills = 0
		lastBlow = {}
		state.base = nil
		state.baseTotal = nil
		state.baseTime = nil
		state.healBase = nil
		state.healBaseTotal = nil
		state.healBaseTime = nil
		state.bossBase = nil
		state.bossBaseTotal = nil
		state.bossBaseTime = nil
		state.takenBase = nil
		state.takenBaseTotal = nil
		state.takenBaseTime = nil
		state.partyBase = nil
		state.partyBaseTotal = nil
		state.partyBaseTime = nil
		clearColHold()
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

local function inParty()
	local rev = AZS_REVIVE
	if rev and rev.down ~= nil then
		return true
	end
	if AZS_PARTY and table.getn(AZS_PARTY) > 0 then
		return true
	end
	return false
end

local function viewMode()
	local cfg = config()
	if not cfg.viewChosen then
		cfg.view = "damage"
	end
	local v = cfg.view
	if v == "party" and not inParty() then
		return "damage"
	end
	if v ~= "healing" and v ~= "boss" and v ~= "taken" and v ~= "party" then
		return "damage"
	end
	return v
end

local function showsKills(mode)
	if not mode then
		mode = viewMode()
	end
	return mode == "damage"
end

-- Amount word, rate word, and whether the kill tally belongs on this view.
local function meterWords(mode)
	if not mode then
		mode = viewMode()
	end
	if mode == "healing" then
		return "Healing", "HPS", false
	elseif mode == "taken" then
		return "Taken", "DPS", false
	elseif mode == "party" then
		return "Damage", "DPS", false
	end
	return "Damage", "DPS", mode == "damage"
end

local function baseFields(mode)
	if not mode then
		mode = viewMode()
	end
	if mode == "healing" then
		return "healBase", "healBaseTotal", "healBaseTime"
	elseif mode == "boss" then
		return "bossBase", "bossBaseTotal", "bossBaseTime"
	elseif mode == "taken" then
		return "takenBase", "takenBaseTotal", "takenBaseTime"
	elseif mode == "party" then
		return "partyBase", "partyBaseTotal", "partyBaseTime"
	end
	return "base", "baseTotal", "baseTime"
end

local function pullMeter(mode)
	if not mode then
		mode = viewMode()
	end
	if mode == "damage" and testMeter then
		return meterFrom(testMeter)
	end
	local fn = AZS_GetMeter
	if mode == "healing" then
		fn = AZS_GetHealing
	elseif mode == "boss" then
		fn = AZS_GetBossMeter
	elseif mode == "party" then
		fn = AZS_GetPartyMeter
	elseif mode == "taken" then
		local lines = {}
		local total = 0
		local t = runNow()
		if t < 1 then
			t = 1
		end
		if AZS_TAKEN then
			local i
			local n = table.getn(AZS_TAKEN)
			for i = 1, n do
				local src = AZS_TAKEN[i].source or ""
				local dmg = tonumber(AZS_TAKEN[i].dmg) or 0
				total = total + dmg
				lines[i] = {
					name = TAKEN_LABEL[src] or src,
					dmg = dmg,
					dps = dmg / t,
					proc = 0,
					icon = TAKEN_ICON[src],
				}
			end
		end
		local dps = 0
		if total > 0 then
			dps = total / t
		end
		return lines, total, dps
	end
	if fn then
		return fn()
	end
	return {}, 0, 0
end

-- The built-in meter cannot be cleared from an addon. Remember its numbers at
-- the moment of a reset and show only what it has added since.
local function captureBase(mode)
	if not state then
		loadState()
	end
	local lines, total = pullMeter(mode)
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
	local bKey, tKey, timeKey = baseFields(mode)
	state[bKey] = base
	state[tKey] = tonumber(total) or 0
	state[timeKey] = runNow()
end

local function windowReset(dropTest, mode)
	if not mode then
		mode = viewMode()
	end
	if not state then
		loadState()
	end
	if dropTest then
		testMeter = nil
	end
	captureBase(mode)
	clearRecentRate(mode)
	clearColHold(mode)
	if showsKills(mode) then
		state.spells = {}
		state.kills = 0
		lastBlow = {}
	end
	if viewMode() == mode then
		scroll = 0
	end
	if popped[mode] then
		popped[mode].scrollPos = 0
	end
end

-- The spells this proc casts that are on the meter. One named spell is always
-- the parent, even before that spell has a row. Several spells share the proc
-- across whichever of them are present.
local function anchorSpells(procName, present)
	local key = englishSpell(procName)
	local casts = PROC_CAST[key]
	local function shown(english)
		if present[english] then
			return english
		end
		local n
		for n in pairs(present) do
			if englishSpell(n) == english then
				return n
			end
		end
		if spellSay[english] then
			return spellSay[english]
		end
		return nil
	end
	if not casts then
		-- "Pendant of the Plague: Corruption" is that item's share of Corruption.
		local _, _, spell = string.find(procName, ": (.+)$")
		if spell and spell ~= "" then
			local hit = shown(englishSpell(spell))
			if hit then
				return { hit }
			end
		end
		return nil
	end
	if table.getn(casts) == 1 then
		local hit = shown(casts[1])
		if not hit then
			hit = casts[1]
		end
		return { hit }
	end
	local found = {}
	local i
	for i = 1, table.getn(casts) do
		local hit = shown(casts[i])
		if hit and present[hit] then
			found[table.getn(found) + 1] = hit
		end
	end
	if not found[1] then
		return nil
	end
	return found
end

local function columnOn(key)
	local saved = config().look
	if not saved then
		return true
	end
	if key == "kills" then
		return saved.colKill ~= false
	elseif key == "damage" then
		return saved.colDmg ~= false
	elseif key == "dps" then
		return saved.colDps ~= false
	elseif key == "share" then
		return saved.colShare ~= false
	end
	return true
end

local function activeSort(mode)
	local key = config().sort or "damage"
	if key == "name" or (key == "kills" and not showsKills(mode)) or not columnOn(key) then
		key = "damage"
	end
	if not columnOn(key) then
		if columnOn("dps") then
			key = "dps"
		elseif columnOn("share") then
			key = "share"
		elseif showsKills(mode) and columnOn("kills") then
			key = "kills"
		end
	end
	return key
end

local function rebuild(mode)
	local i
	for i = table.getn(sorted), 1, -1 do
		sorted[i] = nil
	end
	if not state then
		return 0
	end
	if not mode then
		mode = viewMode()
	end
	local lines, total, rdps = pullMeter(mode)
	local gameTotal = tonumber(total) or 0
	local bKey, tKey, timeKey = baseFields(mode)
	local baseMap = state[bKey]
	if baseMap and gameTotal + 1 < (state[tKey] or 0) then
		state[bKey] = nil
		state[tKey] = nil
		state[timeKey] = nil
		baseMap = nil
		clearRecentRate(mode)
	end
	local since = 1
	if baseMap then
		since = runNow() - (state[timeKey] or 0)
		if since < 1 then
			since = 1
		end
		meterTotal = gameTotal - (state[tKey] or 0)
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
		local hits = 0
		local crits = 0
		local rec = state.spells[name]
		if rec then
			kills = rec.kills or 0
			hits = rec.hits or 0
			crits = rec.crits or 0
		end
		row = {
			name = name,
			damage = 0,
			dps = 0,
			proc = false,
			kills = kills,
			hits = hits,
			crits = crits,
			fromMeter = false,
		}
		bucket[name] = row
		return row
	end
	local function oneSummon()
		local list = nil
		if AZS_GetSummonGroups then
			list = AZS_GetSummonGroups()
		end
		if not list and AZS_GetSummons then
			list = AZS_GetSummons()
		end
		if not list and AZS_PETS then
			list = AZS_PETS
		end
		if not list then
			return nil
		end
		local seen = nil
		local icon = nil
		local several = false
		local si
		for si = 1, table.getn(list) do
			local summon = list[si]
			local summonName = summon and summon.name
			if summonName and summonName ~= "" then
				if not seen then
					seen = summonName
					icon = summon.icon
				elseif seen ~= summonName then
					several = true
				end
			end
		end
		if several then
			return nil, nil, true
		end
		if seen then
			return seen, icon, false
		end
		return nil
	end
	if lines then
		for i = 1, table.getn(lines) do
			local line = lines[i]
			local meterName = line.name
			local name = meterName
			local summonIcon = nil
			if meterName == "Pets" then
				local summoned, simg, several = oneSummon()
				if several then
					state.petName = nil
					state.petIcon = nil
				elseif summoned then
					name = summoned
					summonIcon = simg
					state.petName = summoned
					state.petIcon = simg
				elseif state.petName and state.petName ~= "" then
					name = state.petName
					summonIcon = state.petIcon
				end
			end
			if name and name ~= "" then
				local row = bucketOf(name)
				local raw = tonumber(line.dmg) or 0
				local dealt = raw
				if baseMap then
					dealt = raw - (baseMap[meterName] or 0)
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
				row.iconPath = usableIcon(line.icon)
				if summonIcon and summonIcon ~= "" then
					local path = usableIcon(summonIcon) or asTexture(summonIcon)
					if path then
						row.iconPath = path
						keepIcon(name, path)
					end
				end
				if line.class and line.class ~= "" then
					row.classKey = string.lower(line.class)
				end
				if line.top and line.top ~= "" then
					row.top = line.top
					row.topdps = tonumber(line.topdps) or 0
				end
				if row.iconPath then
					keepIcon(name, row.iconPath)
				end
			end
		end
	end
	if showsKills(mode) then
		local iconOwners = {}
		local function iconKey(path)
			if not path or path == "" then
				return nil
			end
			path = string.lower(path)
			path = string.gsub(path, "/", "\\")
			local _, _, tail = string.find(path, "\\([^\\]+)$")
			if tail then
				path = tail
			end
			path = string.gsub(path, "%.blp$", "")
			if path == "" or path == "inv_misc_questionmark" then
				return nil
			end
			return path
		end
		local ownerName, ownerRow
		for ownerName, ownerRow in pairs(bucket) do
			if ownerRow.fromMeter then
				local key = iconKey(ownerRow.iconPath)
				if not key then
					key = iconKey(iconFor(ownerName))
				end
				if key then
					local list = iconOwners[key]
					if not list then
						list = {}
						iconOwners[key] = list
					end
					list[table.getn(list) + 1] = ownerName
				end
			end
		end
		local spellName, rec
		for spellName, rec in pairs(state.spells) do
			if (rec.kills or 0) > 0 then
				if bucket[spellName] then
					bucketOf(spellName)
				else
					local key = iconKey(iconFor(spellName))
					local owners = key and iconOwners[key]
					if owners and table.getn(owners) == 1 then
						local row = bucket[owners[1]]
						row.kills = (row.kills or 0) + (rec.kills or 0)
					else
						bucketOf(spellName)
					end
				end
			end
		end
	end
	local windowRate = recentRate(mode, runNow(), meterTotal, bucket)
	if windowRate then
		meterDps = windowRate
	end
	-- Fold a proc into the spell it actually casts: one Pyroblast row, and Hot
	-- Streak lives on the proc button. Several casts share the proc. Collect
	-- first; pairs cannot drop keys.
	local merges = {}
	local procName, row
	for procName, row in pairs(bucket) do
		if mode ~= "party" and (row.proc or PROC_CAST[englishSpell(procName)] or string.find(procName, ": ", 1, true)) then
			local parents = anchorSpells(procName, bucket)
			if parents and not (table.getn(parents) == 1 and parents[1] == procName) then
				local mi = table.getn(merges) + 1
				merges[mi] = { proc = procName, parents = parents }
			end
		end
	end
	local mi
	for mi = 1, table.getn(merges) do
		local link = merges[mi]
		row = bucket[link.proc]
		if row then
			local parents = link.parents
			local pc = table.getn(parents)
			local dmg = row.damage or 0
			local rate = row.dps or 0
			local kills = row.kills or 0
			local usedDmg = 0
			local usedRate = 0
			for pi = 1, pc do
				local partDmg = dmg / pc
				local partRate = rate / pc
				if pi == pc then
					partDmg = dmg - usedDmg
					partRate = rate - usedRate
				end
				usedDmg = usedDmg + partDmg
				usedRate = usedRate + partRate
				local parent = bucketOf(parents[pi])
				parent.damage = (parent.damage or 0) + partDmg
				parent.dps = (parent.dps or 0) + partRate
				if pi == 1 then
					parent.kills = (parent.kills or 0) + kills
				end
				if partDmg > 0 or (pi == 1 and showsKills(mode) and kills > 0) then
					if not parent.procs then
						parent.procs = {}
					end
					local phits = 0
					local pcrits = 0
					if pi == 1 then
						phits = row.hits or 0
						pcrits = row.crits or 0
					end
					-- The same talent can arrive under two languages. Keep one button.
					local enProc = englishSpell(link.proc)
					local have = nil
					local ei
					for ei = 1, table.getn(parent.procs) do
						if englishSpell(parent.procs[ei].name) == enProc then
							have = parent.procs[ei]
						end
					end
					if have then
						have.damage = (have.damage or 0) + partDmg
						have.dps = (have.dps or 0) + partRate
						have.hits = (have.hits or 0) + phits
						have.crits = (have.crits or 0) + pcrits
					else
						parent.procs[table.getn(parent.procs) + 1] = {
							name = link.proc,
							damage = partDmg,
							dps = partRate,
							kills = 0,
							hits = phits,
							crits = pcrits,
							icon = row.iconPath,
						}
					end
				end
			end
			bucket[link.proc] = nil
		end
	end
	local n = 0
	local name, entry
	for name, entry in pairs(bucket) do
		local keep = (entry.damage or 0) > 0
		if showsKills(mode) and (entry.kills or 0) > 0 then
			keep = true
		end
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
	local key = activeSort(mode)
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
	local ri
	for ri = 1, n do
		sorted[ri].rank = ri
	end
	local saved = config().look
	if saved and saved.detail then
		local open = config().open
		if open then
			local built = {}
			local bn = 0
			for ri = 1, n do
				local entry = sorted[ri]
				bn = bn + 1
				built[bn] = entry
				if open[entry.name] and entry.procs and entry.procs[1] then
					local pi
					for pi = 1, table.getn(entry.procs) do
						local p = entry.procs[pi]
						bn = bn + 1
						built[bn] = {
							name = p.name,
							damage = p.damage or 0,
							dps = p.dps or 0,
							kills = 0,
							hits = p.hits or 0,
							crits = p.crits or 0,
							iconPath = p.icon,
							child = true,
							proc = true,
							parentName = entry.name,
						}
					end
				end
			end
			for ri = 1, n do
				sorted[ri] = nil
			end
			for ri = 1, bn do
				sorted[ri] = built[ri]
			end
			n = bn
		end
	end
	return n
end

local function noteDeath()
	if not AZS_GetPhase then
		return
	end
	local ph = AZS_GetPhase()
	if ph == "dead" and seenPhase ~= "dead" and AZS_TAKEN then
		local bestName = nil
		local best = 0
		local i
		for i = 1, table.getn(AZS_TAKEN) do
			local dmg = tonumber(AZS_TAKEN[i].dmg) or 0
			if dmg > best then
				best = dmg
				local src = AZS_TAKEN[i].source or ""
				bestName = TAKEN_LABEL[src] or src
			end
		end
		if bestName and best > 0 then
			say("Downed mostly by " .. bestName .. ", " .. comma(best) .. ". The Taken tab has the rest.")
		end
	end
	seenPhase = ph
end

local function compactKey(name)
	local s = string.lower(name or "")
	s = string.gsub(s, "[%s_%-']", "")
	return s
end

-- Pixel height of the list. Not snapped to a row, so the scroll frame can cut a spell in half.
local function viewHeight(win)
	if not win then
		win = frame
	end
	local head = K.HEADER
	if win and win.headH then
		head = win.headH
	end
	local avail = 8 * K.ROW_H
	if win then
		avail = win:GetHeight() - head - 10
	end
	if avail < 8 then
		avail = 8
	end
	return avail
end

local function refreshWindow(win)
	if not win or not state then
		return
	end
	local headH = win.headH or K.HEADER
	local listRows = win.rows or rows
	local pos = scroll
	if win ~= frame then
		pos = win.scrollPos or 0
	end
	local n = rebuild(win.fixed)
	local viewH = viewHeight(win)
	local maxOff = n * K.ROW_H - viewH
	if maxOff < 0 then
		maxOff = 0
	end
	if pos < 0 then
		pos = 0
	elseif pos > maxOff then
		pos = maxOff
	end
	local first = 0
	if K.ROW_H > 0 then
		first = math.floor(pos / K.ROW_H)
	end
	local shift = pos - first * K.ROW_H
	local shown = 0
	if n > 0 then
		shown = math.floor((shift + viewH - 0.001) / K.ROW_H) + 1
		if shown > n - first then
			shown = n - first
		end
		if shown > K.ROW_POOL then
			shown = K.ROW_POOL
		end
		if shown < 1 then
			shown = 1
		end
	end
	if win.scroll then
		local top = headH
		win.scroll:ClearAllPoints()
		win.scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -top)
		win.scroll:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -top)
		if win.cols then
			win.cols:ClearAllPoints()
			win.cols:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -(top - K.COL_H))
			win.cols:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -(top - K.COL_H))
		end
		win.scroll:SetHeight(viewH)
		local sw = win.scroll:GetWidth()
		if not sw or sw < 40 then
			sw = rowWidth(win)
		end
		if win.scrollChild then
			win.scrollChild:SetWidth(sw)
			local childH = shown * K.ROW_H
			if childH < viewH + shift then
				childH = viewH + shift
			end
			if childH < 1 then
				childH = 1
			end
			win.scrollChild:SetHeight(childH)
		end
		if win.scroll.SetVerticalScroll then
			win.scroll:SetVerticalScroll(shift)
		end
	end

	local mode = win.fixed or viewMode()
	local tint = HEADER_TINT[mode] or HEADER_TINT.damage
	local numR, numG, numB = tone(tint[4], tint[5], tint[6])
	local amountWord, rateWord, killView = meterWords(win.fixed)
	local board = meterTotal
	local dps = meterDps
	if win.emptyText then
		if n <= 0 then
			local empty = "No damage yet."
			if mode == "healing" then
				if AZS_GetHealing then
					empty = "No healing yet."
				else
					empty = "Healing needs a newer game build."
				end
			elseif mode == "boss" then
				if AZS_GetBossMeter then
					empty = "No boss damage yet."
				else
					empty = "Boss damage needs a newer game build."
				end
			elseif mode == "taken" then
				if AZS_TAKEN then
					empty = "No damage taken yet."
				else
					empty = "Damage taken needs a newer game build."
				end
			elseif mode == "party" then
				if AZS_GetPartyMeter then
					empty = "No party damage yet."
				else
					empty = "Party damage needs a newer game build."
				end
			end
			win.emptyText:SetText(empty)
			win.emptyText:ClearAllPoints()
			win.emptyText:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(headH + 6))
			win.emptyText:Show()
		else
			win.emptyText:Hide()
		end
	end
	win.totalText:SetText(comma(board))
	if win.brandText then
		local title = "Spell Meter"
		local classKey = ""
		local className = ""
		if AZS_ZONE then
			classKey = AZS_ZONE.class or ""
			className = AZS_ZONE.cname or ""
		end
		if className == "" and UnitClass then
			local localized, english = UnitClass("player")
			if localized and localized ~= "" then
				className = localized
			end
			if classKey == "" and english and english ~= "" then
				classKey = string.lower(english)
			end
		end
		if win.fixed then
			title = VIEW_TITLE[win.fixed] or title
		elseif mode == "party" then
			title = "Party"
		elseif className ~= "" then
			title = className
		end
		win.brandText:SetText(title)
		win.brandText:SetTextColor(1, 0.9, 0.62)
		if win.header and tint then
			local bgA = 0.82
			local savedBg = config().look
			if savedBg and type(savedBg.panel) == "table" and savedBg.panel[4] ~= nil then
				bgA = savedBg.panel[4]
			end
			win.header:SetBackdropColor(tint[1], tint[2], tint[3], bgA)
			win.header:SetBackdropBorderColor(tint[4], tint[5], tint[6], 1)
		end
		if win.brand then
			local coord = CLASS_ICON[classKey]
			if coord then
				win.brand:SetTexture(K.CLASS_SHEET)
				win.brand:SetTexCoord(coord[1], coord[2], coord[3], coord[4])
			else
				win.brand:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
				win.brand:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			end
		end
	end
	win.totalText:SetTextColor(numR, numG, numB)
	win.dpsText:SetText(fmtRate(dps) .. " " .. string.lower(rateWord))
	if win.bubbleText then
		win.bubbleText:SetText(comma(board))
		local bw = 36
		if win.bubbleText.GetStringWidth then
			bw = (win.bubbleText:GetStringWidth() or 24) + 16
		end
		if bw < 36 then
			bw = 36
		end
		bubble:SetWidth(bw)
	end
	if win.totalBtn and win.totalText.GetStringWidth then
		local tw = win.totalText:GetStringWidth() or 24
		if tw < 24 then
			tw = 24
		end
		win.totalBtn:SetWidth(tw + 8)
	end
	if win.dpsBtn and win.dpsText.GetStringWidth then
		local dw = win.dpsText:GetStringWidth() or 24
		if dw < 24 then
			dw = 24
		end
		win.dpsBtn:SetWidth(dw + 8)
	end
	local showKill = killView and columnOn("kills")
	local showDmg = columnOn("damage")
	local showRate = columnOn("dps")
	local showShare = columnOn("share")
	local detail = config().look and config().look.detail
	if win.sortBtns then
		local active = activeSort(win.fixed)
		if win.dmgCol then
			win.dmgCol.base = amountWord
		end
		if win.dpsCol then
			win.dpsCol.base = rateWord
		end
		if win.shareCol then
			win.shareCol.base = "%"
		end
		local prevCol = nil
		local function stickCol(btn, on, width)
			if not btn then
				return
			end
			if not on then
				btn:Hide()
				return
			end
			btn:Show()
			btn:SetWidth(width)
			btn:ClearAllPoints()
			if not prevCol then
				btn:SetPoint("RIGHT", win.cols, "RIGHT", -2, 0)
			else
				btn:SetPoint("RIGHT", prevCol, "LEFT", -6, 0)
			end
			prevCol = btn
		end
		local rateW = K.COL_DPS
		local shareW = K.COL_PCT
		local dmgW = K.COL_DMG
		if mode == "healing" then
			dmgW = 58
		end
		local killW = K.COL_KILL
		local rateNum, shareNum, dmgNum, killNum = rateW, shareW, dmgW, killW
		local probe = listRows and listRows[1]
		local function textWidth(fs, text)
			if not fs or not fs.GetStringWidth then
				return 0
			end
			fs:SetText(text or "")
			return fs:GetStringWidth() or 0
		end
		local function measureCol(fs, header, kind)
			local wide = textWidth(fs, header)
			local nums = 0
			local i
			for i = 1, n do
				local entry = sorted[i]
				local sample = ""
				if kind == "rate" then
					sample = fmtRate(entry.dps or 0)
				elseif kind == "share" then
					local part = 0
					if board > 0 then
						part = (entry.damage or 0) / board
					end
					sample = fmtPct(part)
				elseif kind == "damage" then
					sample = comma(entry.damage or 0)
				elseif kind == "kills" then
					if not entry.child and (entry.kills or 0) > 0 then
						sample = tostring(entry.kills)
					end
				end
				local w = textWidth(fs, sample)
				if w > nums then
					nums = w
				end
			end
			if nums > wide then
				wide = nums
			end
			if wide < 12 then
				wide = 12
			end
			if nums < 8 then
				nums = 8
			end
			return wide + 4, nums + 2
		end
		if probe then
			local now = 0
			if GetTime then
				now = GetTime()
			end
			local function take(fs, header, kind)
				local need, num = measureCol(fs, header, kind)
				local slot = holdWidth(win, mode, kind, need, now)
				if num > slot then
					num = slot
				end
				return slot, num
			end
			if showRate and probe.rate then
				rateW, rateNum = take(probe.rate, rateWord, "rate")
			end
			if showShare and probe.share then
				shareW, shareNum = take(probe.share, "%", "share")
			end
			if showDmg and probe.damage then
				dmgW, dmgNum = take(probe.damage, amountWord, "damage")
			end
			if showKill and probe.kills then
				killW, killNum = take(probe.kills, "Kills", "kills")
			end
		end
		stickCol(win.dpsCol, showRate, rateW)
		stickCol(win.shareCol, showShare, shareW)
		stickCol(win.dmgCol, showDmg, dmgW)
		stickCol(win.killCol, showKill, killW)
		win.rateW = rateW
		win.shareW = shareW
		win.dmgW = dmgW
		win.killW = killW
		win.rateNum = rateNum
		win.shareNum = shareNum
		win.dmgNum = dmgNum
		win.killNum = killNum
		local si
		for si = 1, table.getn(win.sortBtns) do
			local btn = win.sortBtns[si]
			btn.label:SetText(btn.base)
			if btn.key == active then
				btn.label:SetTextColor(1, 0.82, 0.4)
			else
				btn.label:SetTextColor(0.55, 0.5, 0.4)
			end
		end
	end
	if win.modeBtns then
		local mi
		local shownTabs = 0
		for mi = 1, table.getn(win.modeBtns) do
			local btn = win.modeBtns[mi]
			local open = btn.mode ~= "party" or inParty()
			if not open then
				btn:Hide()
			else
				btn:Show()
				shownTabs = shownTabs + 1
				local on = btn.mode == mode and not popped[btn.mode]
				if popped[btn.mode] then
					btn.label:SetTextColor(0.45, 0.4, 0.32)
					btn:SetBackdropColor(0.08, 0.06, 0.04, 0.4)
					btn:SetBackdropBorderColor(0.4, 0.32, 0.16, 0.7)
				elseif on then
					btn.label:SetTextColor(btn.tr, btn.tg, btn.tb)
					btn:SetBackdropColor(btn.br, btn.bg, btn.bb, 1)
					btn:SetBackdropBorderColor(btn.er, btn.eg, btn.eb, 1)
				else
					btn.label:SetTextColor(0.62, 0.54, 0.4)
					btn:SetBackdropColor(0.12, 0.08, 0.04, 0.55)
					btn:SetBackdropBorderColor(0.32, 0.22, 0.1, 1)
				end
			end
		end
		local gap = 3
		local inner = (win:GetWidth() or K.WIDTH) - 16
		if inner < 40 then
			inner = 40
		end
		local tabs = shownTabs
		if tabs < 1 then
			tabs = 1
		end
		local bw = math.floor((inner - gap * (tabs - 1)) / tabs)
		if bw < 8 then
			bw = 8
		end
		local used = bw * tabs + gap * (tabs - 1)
		local extra = inner - used
		if extra < 0 then
			extra = 0
		end
		local x = 0
		for mi = 1, table.getn(win.modeBtns) do
			local btn = win.modeBtns[mi]
			if btn.mode ~= "party" or inParty() then
				local wide = bw
				if extra > 0 then
					wide = wide + 1
					extra = extra - 1
				end
				btn:ClearAllPoints()
				btn:SetWidth(wide)
				if win.modes then
					btn:SetPoint("LEFT", win.modes, "LEFT", x, 0)
				end
				x = x + wide + gap
			end
		end
	end
	if killView and (state.kills or 0) > 0 then
		win.countText:SetText(state.kills .. (state.kills == 1 and " kill" or " kills"))
	else
		win.countText:SetText("")
	end

	win.cdMap = {}
	if AZS_SPELLS then
		local si
		for si = 1, table.getn(AZS_SPELLS) do
			local sp = AZS_SPELLS[si]
			if sp.key and sp.key ~= "" then
				win.cdMap[compactKey(sp.key)] = sp
			end
		end
	end

	local showCd = true
	local savedLook = config().look
	if savedLook and savedLook.cd == false then
		showCd = false
	end
	local wrapOn = savedLook and savedLook.wrap
	local rateW = win.rateW or K.COL_DPS
	local shareW = win.shareW or K.COL_PCT
	local dmgW = win.dmgW or K.COL_DMG
	local killW = win.killW or K.COL_KILL
	local rateNum = win.rateNum or rateW
	local shareNum = win.shareNum or shareW
	local dmgNum = win.dmgNum or dmgW
	local killNum = win.killNum or killW
	local numW = 2
	local parts = {}
	local function pushCol(slot, num, on)
		if not on then
			return
		end
		parts[table.getn(parts) + 1] = { slot = slot, num = num }
	end
	pushCol(rateW, rateNum, showRate)
	pushCol(shareW, shareNum, showShare)
	pushCol(dmgW, dmgNum, showDmg)
	pushCol(killW, killNum, showKill)
	local pi
	local pn = table.getn(parts)
	for pi = 1, pn do
		local use = parts[pi].slot
		if pi == pn then
			use = parts[pi].num
		end
		numW = numW + use
		if pi < pn then
			numW = numW + 6
		else
			numW = numW + 4
		end
	end
	-- Icons drawn after the name. Their width stays out of the Kills column.
	local function trailIcons(entry)
		if not entry or entry.child then
			return 0
		end
		if entry.classKey and entry.top and entry.top ~= "" then
			local tex = iconFor(entry.top)
			if tex and not string.find(string.lower(tex), "questionmark", 1, true) then
				return 1
			end
			return 0
		end
		if detail then
			return 0
		end
		local nproc = 0
		if entry.procs then
			nproc = table.getn(entry.procs)
		end
		if nproc > 3 then
			nproc = 3
		end
		return nproc
	end
	local listW = rowWidth(win)
	local rowHeights = {}
	local totalH = 0
	local hi
	for hi = 1, n do
		local entry = sorted[hi]
		local h = K.ROW_H
		entry.shown = nil
		if wrapOn and listRows and listRows[1] and listRows[1].name then
			local nameLeft = 16
			if entry.child or (detail and entry.procs and entry.procs[1]) then
				nameLeft = 28
			end
			local text = entry.name or ""
			local fs = listRows[1].name
			local rankGap = 0
			if not entry.child then
				fs:SetText(tostring(entry.rank or hi))
				if fs.GetStringWidth then
					rankGap = (fs:GetStringWidth() or 0) + 6
				end
			end
			local avail = listW - nameLeft - rankGap - numW - trailIcons(entry) * 16
			if avail < 48 then
				avail = 48
			end
			fs:SetText(text)
			local tw = 0
			if fs.GetStringWidth then
				tw = fs:GetStringWidth() or 0
			end
			if tw > avail then
				local breakAt = nil
				local startAt = 1
				while true do
					local found = string.find(text, " ", startAt)
					if not found then
						break
					end
					fs:SetText(string.sub(text, 1, found - 1))
					local lw = 0
					if fs.GetStringWidth then
						lw = fs:GetStringWidth() or 0
					end
					if lw <= avail then
						breakAt = found
						startAt = found + 1
					else
						break
					end
				end
				if breakAt then
					entry.shown = string.sub(text, 1, breakAt - 1) .. "\n" .. string.sub(text, breakAt + 1)
					h = K.WRAP_H
				end
			end
		end
		rowHeights[hi] = h
		totalH = totalH + h
	end
	local maxOff = totalH - viewH
	if maxOff < 0 then
		maxOff = 0
	end
	if pos > maxOff then
		pos = maxOff
	end
	if pos < 0 then
		pos = 0
	end
	local walked = 0
	first = 0
	for hi = 1, n do
		local h = rowHeights[hi] or K.ROW_H
		if walked + h > pos + 0.01 then
			break
		end
		walked = walked + h
		first = hi
	end
	shift = pos - walked
	shown = 0
	if n > 0 then
		local covered = -shift
		local vi = first
		while vi < n and covered < viewH and shown < K.ROW_POOL do
			vi = vi + 1
			shown = shown + 1
			covered = covered + (rowHeights[vi] or K.ROW_H)
		end
		if shown < 1 then
			shown = 1
		end
	end
	if win ~= frame then
		win.scrollPos = pos
	else
		scroll = pos
	end
	if win.scrollChild then
		local childH = 0
		for hi = 1, shown do
			childH = childH + (rowHeights[first + hi] or K.ROW_H)
		end
		if childH < viewH + shift then
			childH = viewH + shift
		end
		if childH < 1 then
			childH = 1
		end
		win.scrollChild:SetHeight(childH)
	end
	if win.scroll and win.scroll.SetVerticalScroll then
		win.scroll:SetVerticalScroll(shift)
	end

	local i
	local rowY = 0
	for i = 1, K.ROW_POOL do
		local row = listRows[i]
		local data = nil
		if i <= shown then
			data = sorted[first + i]
		end
		if data then
			local dealt = data.damage or 0
			row.win = win
			local share = 0
			if board > 0 then
				share = dealt / board
			end
			local label = data.name
			row.data = data
			row:Show()
			local rowH = rowHeights[first + i] or K.ROW_H
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 0, -rowY)
			row:SetWidth(rowWidth(win))
			row:SetHeight(rowH)
			row.bar:SetHeight(rowH)
			rowY = rowY + rowH
			local classCoord = nil
			if data.classKey then
				classCoord = CLASS_ICON[data.classKey]
			end
			if classCoord then
				row.icon:SetTexture(K.CLASS_SHEET)
				row.icon:SetTexCoord(classCoord[1], classCoord[2], classCoord[3], classCoord[4])
			else
				row.icon:SetTexture(rowIcon(data))
				row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			end
			row.name:SetText(data.shown or label)
			if data.shown then
				row.name:SetHeight(K.WRAP_H - 2)
			else
				row.name:SetHeight(K.ROW_H)
			end
			if data.child then
				row.name:SetTextColor(0.75, 0.82, 1)
			else
				row.name:SetTextColor(1, 0.95, 0.86)
			end
			if showKill and not data.child and (data.kills or 0) > 0 then
				row.kills:SetText(tostring(data.kills))
			else
				row.kills:SetText("")
			end
			local nameLeft = 16
			local iconLeft = 1
			local hasProcs = data.procs and data.procs[1]
			if row.arrow then
				if detail and hasProcs and not data.child then
					row.arrow:Show()
					if config().open and config().open[data.name] then
						row.arrow.text:SetText("v")
					else
						row.arrow.text:SetText(">")
					end
					nameLeft = 28
					iconLeft = 13
				else
					row.arrow:Hide()
				end
			end
			if data.child then
				nameLeft = 28
				iconLeft = 13
			end
			if row.arrow then
				row.arrow:ClearAllPoints()
				if data.shown then
					row.arrow:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
				else
					row.arrow:SetPoint("LEFT", row, "LEFT", 0, 0)
				end
			end
			if row.iconBg then
				row.iconBg:ClearAllPoints()
				if data.shown then
					row.iconBg:SetPoint("TOPLEFT", row, "TOPLEFT", iconLeft, -1)
				else
					row.iconBg:SetPoint("LEFT", row, "LEFT", iconLeft, 0)
				end
			end
			local leftNum = nil
			local function stickText(fs, on, colW)
				if not fs then
					return
				end
				fs:ClearAllPoints()
				if not on then
					fs:Hide()
					return
				end
				fs:Show()
				fs:SetWidth(colW)
				fs:SetHeight(K.ROW_H)
				if data.shown then
					if not leftNum then
						fs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -1)
					else
						fs:SetPoint("TOPRIGHT", leftNum, "TOPLEFT", -6, 0)
					end
				elseif not leftNum then
					fs:SetPoint("RIGHT", row, "RIGHT", -2, 0)
				else
					fs:SetPoint("RIGHT", leftNum, "LEFT", -6, 0)
				end
				leftNum = fs
			end
			row.damage:SetText(comma(dealt))
			row.damage:SetTextColor(numR, numG, numB)
			row.rate:SetText(fmtRate(data.dps or 0))
			if row.share then
				row.share:SetText(fmtPct(share))
			end
			stickText(row.rate, showRate, rateW)
			stickText(row.share, showShare, shareW)
			stickText(row.damage, showDmg, dmgW)
			stickText(row.kills, showKill and not data.child, killW)
			local iconReserve = trailIcons(data) * 16
			local nameRight = numW + iconReserve
			local rankGap = 0
			if row.rank then
				row.rank:ClearAllPoints()
				if data.child then
					row.rank:Hide()
					row.rank:SetText("")
				else
					row.rank:SetText(tostring(data.rank or (first + i)))
					row.rank:Show()
					if data.shown then
						row.rank:SetPoint("TOPLEFT", row, "TOPLEFT", nameLeft, -1)
					else
						row.rank:SetPoint("LEFT", row, "LEFT", nameLeft, 0)
					end
					if row.rank.GetStringWidth then
						rankGap = (row.rank:GetStringWidth() or 0) + 6
					end
				end
			end
			row.name:ClearAllPoints()
			if data.shown then
				row.name:SetPoint("TOPLEFT", row, "TOPLEFT", nameLeft + rankGap, -1)
				row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -nameRight, -1)
			else
				row.name:SetPoint("LEFT", row, "LEFT", nameLeft + rankGap, 0)
				row.name:SetPoint("RIGHT", row, "RIGHT", -nameRight, 0)
			end
			local fill = share
			if dealt > 0 and fill < 0.015 then
				fill = 0.015
			end
			row.bar:SetWidth(math.max(2, (row:GetWidth() or 1) * fill))
			if data.child then
				row.bar:SetVertexColor(tint[1], tint[2], tint[3], 0.4)
			elseif first + i == 1 then
				row.bar:SetVertexColor(tint[4], tint[5], tint[6], 0.9)
			else
				row.bar:SetVertexColor(tint[1], tint[2], tint[3], 0.75)
			end
			local procs = data.procs
			local textW = 0
			local fullName = row.name:GetText() or ""
			local breakAt = string.find(fullName, "\n", 1, true)
			if breakAt then
				row.name:SetText(string.sub(fullName, 1, breakAt - 1))
			end
			if row.name.GetStringWidth then
				textW = row.name:GetStringWidth() or 0
			end
			if breakAt then
				row.name:SetText(fullName)
			end
			local px = nameLeft + rankGap + textW + 4
			local limit = (row:GetWidth() or 0) - numW - iconReserve
			if limit < 40 then
				limit = 40
			end
			local pi
			for pi = 1, 3 do
				local btn = row.procBtns and row.procBtns[pi]
				local info = nil
				if not data.child and pi == 1 and data.classKey and data.top and data.top ~= "" then
					local topName = clientSpell(data.top)
					local tex = iconFor(data.top)
					if tex and not string.find(string.lower(tex), "questionmark", 1, true) then
						info = {
							name = topName,
							dps = data.topdps or 0,
							icon = tex,
							topSpell = true,
						}
					end
				elseif not detail and not data.child then
					info = procs and procs[pi]
				end
				if btn and info then
					if px > limit then
						px = limit
					end
					btn.info = info
					btn.win = win
					if btn.icon then
						local tex = info.icon
						if not tex or tex == "" then
							tex = iconFor(info.name)
						end
						btn.icon:SetTexture(tex)
					end
					btn:ClearAllPoints()
					btn:SetPoint("LEFT", row, "LEFT", px, 0)
					btn:Show()
					px = px + (btn:GetWidth() or 32) + 2
				elseif btn then
					btn.info = nil
					btn:Hide()
				end
			end
			local cd = nil
			if not data.child then
				cd = win.cdMap and win.cdMap[compactKey(data.name)]
			end
			if row.cd and showCd and cd and (tonumber(cd.cdmax) or 0) > 0 then
				local maxc = tonumber(cd.cdmax) or 1
				if maxc < 0.1 then
					maxc = 0.1
				end
				local left = tonumber(cd.cd) or 0
				if left < 0 then
					left = 0
				end
				local frac = 1 - (left / maxc)
				if frac < 0 then
					frac = 0
				elseif frac > 1 then
					frac = 1
				end
				row.cd:Show()
				row.cd:SetWidth(math.max(2, 11 * frac))
				if left <= 0 then
					row.cd:SetVertexColor(0.35, 0.95, 0.45, 1)
				else
					row.cd:SetVertexColor(0.95, 0.72, 0.25, 1)
				end
			elseif row.cd then
				row.cd:Hide()
			end
		else
			row.data = nil
			row:Hide()
			if row.rank then
				row.rank:Hide()
			end
			if row.arrow then
				row.arrow:Hide()
			end
			if row.procBtns then
				local pi
				for pi = 1, 3 do
					row.procBtns[pi].info = nil
					row.procBtns[pi]:Hide()
				end
			end
			if row.cd then
				row.cd:Hide()
			end
		end
	end
	win.total = meterTotal
	win.dps = meterDps
	if win == frame then
		scroll = pos
	else
		win.scrollPos = pos
	end
end

local function anyMeterShown()
	if frame and frame:IsShown() then
		return true
	end
	if bubble and bubble:IsShown() then
		return true
	end
	local mode, pop
	for mode, pop in pairs(popped) do
		if pop:IsShown() then
			return true
		end
	end
	return false
end

local function refresh()
	if not frame or not state then
		return
	end
	watchRun()
	noteDeath()
	if anyMeterShown() then
		hideStockMeter()
	end
	refreshWindow(frame)
	local partyWin = popped.party
	if partyWin then
		if inParty() then
			if not partyWin:IsShown() then
				partyWin:Show()
			end
		elseif partyWin:IsShown() then
			partyWin:Hide()
		end
	end
	local mode, pop
	for mode, pop in pairs(popped) do
		if pop:IsShown() then
			refreshWindow(pop)
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

-- Same visible area SetClampedToScreen uses: UIParent, in screen pixels.
local function viewBounds()
	local ps = 1
	if UIParent and UIParent.GetEffectiveScale then
		ps = UIParent:GetEffectiveScale() or 1
	end
	if not ps or ps <= 0 then
		ps = 1
	end
	local l, r, b, t = 0, 0, 0, 0
	if UIParent and UIParent.GetLeft and UIParent:GetLeft() then
		l = UIParent:GetLeft() * ps
		r = (UIParent:GetRight() or 0) * ps
		b = (UIParent:GetBottom() or 0) * ps
		t = (UIParent:GetTop() or 0) * ps
	end
	if r - l > 100 and t - b > 100 then
		return l, r, b, t
	end
	local sw = GetScreenWidth and GetScreenWidth() or 0
	local sh = GetScreenHeight and GetScreenHeight() or 0
	if sw > 100 and sh > 100 then
		return 0, sw, 0, sh
	end
	return l, r, b, t
end

local function clampIntoView(target)
	if not target or not target.GetLeft or not target:IsShown() then
		return false
	end
	local left = target:GetLeft()
	local top = target:GetTop()
	local right = target:GetRight()
	local bottom = target:GetBottom()
	if not left or not top or not right or not bottom then
		return false
	end
	local scale = 1
	if target.GetEffectiveScale then
		scale = target:GetEffectiveScale() or 1
	end
	if not scale or scale <= 0 then
		scale = 1
	end
	left = left * scale
	right = right * scale
	top = top * scale
	bottom = bottom * scale
	local width = right - left
	local height = top - bottom
	if width < 8 or height < 8 then
		return false
	end
	local bl, br, bb, bt = viewBounds()
	if br - bl < 100 or bt - bb < 100 then
		return false
	end
	local nl, nt = left, top
	if nl + width > br then
		nl = br - width
	end
	if nl < bl then
		nl = bl
	end
	if nt > bt then
		nt = bt
	end
	if nt - height < bb then
		nt = bb + height
	end
	if nt > bt then
		nt = bt
	end
	if math.abs(nl - left) < 0.5 and math.abs(nt - top) < 0.5 then
		return false
	end
	local pscale = 1
	if UIParent and UIParent.GetEffectiveScale then
		pscale = UIParent:GetEffectiveScale() or 1
	end
	if not pscale or pscale <= 0 then
		pscale = 1
	end
	local parentLeft = 0
	local parentBottom = 0
	if UIParent and UIParent.GetLeft then
		parentLeft = (UIParent:GetLeft() or 0) * pscale
		parentBottom = (UIParent:GetBottom() or 0) * pscale
	end
	target:ClearAllPoints()
	target:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (nl - parentLeft) / scale, (nt - parentBottom) / scale)
	return true
end

local function parentMetrics()
	local pscale = 1
	if UIParent and UIParent.GetEffectiveScale then
		pscale = UIParent:GetEffectiveScale() or 1
	end
	if not pscale or pscale <= 0 then
		pscale = 1
	end
	local parentLeft = 0
	local parentBottom = 0
	local parentTop = 0
	if UIParent and UIParent.GetLeft then
		parentLeft = (UIParent:GetLeft() or 0) * pscale
		parentBottom = (UIParent:GetBottom() or 0) * pscale
		parentTop = (UIParent:GetTop() or 0) * pscale
	end
	return pscale, parentLeft, parentBottom, parentTop
end

local function screenRect(win)
	if not win or not win.GetLeft then
		return nil
	end
	local left = win:GetLeft()
	local right = win:GetRight()
	local top = win:GetTop()
	local bottom = win:GetBottom()
	if not left or not right or not top or not bottom then
		return nil
	end
	local scale = 1
	if win.GetEffectiveScale then
		scale = win:GetEffectiveScale() or 1
	end
	if not scale or scale <= 0 then
		scale = 1
	end
	return left * scale, right * scale, top * scale, bottom * scale
end

local function toParent(screenX, screenY, win)
	local pscale, parentLeft, parentBottom = parentMetrics()
	local es = pscale
	if win and win.GetEffectiveScale then
		es = win:GetEffectiveScale() or pscale
	end
	if not es or es <= 0 then
		es = pscale
	end
	return (screenX - parentLeft) / es, (screenY - parentBottom) / es
end

local function fitRect(left, top, width, height)
	local bl, br, bb, bt = viewBounds()
	if br - bl < 100 or bt - bb < 100 then
		return left, top
	end
	if width < 1 then
		width = 1
	end
	if height < 1 then
		height = 1
	end
	if left + width > br then
		left = br - width
	end
	if left < bl then
		left = bl
	end
	if top > bt then
		top = bt
	end
	if top - height < bb then
		top = bb + height
	end
	if top > bt then
		top = bt
	end
	return left, top
end

local function placeAtPixels(win, left, top)
	if not win then
		return
	end
	local scale = 1
	if win.GetEffectiveScale then
		scale = win:GetEffectiveScale() or 1
	end
	if not scale or scale <= 0 then
		scale = 1
	end
	local width = (win:GetWidth() or 1) * scale
	local height = (win:GetHeight() or 1) * scale
	left, top = fitRect(left, top, width, height)
	local x, y = toParent(left, top, win)
	win:ClearAllPoints()
	win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function parkBeside(win, anchor)
	local scale = 1
	if win and win.GetEffectiveScale then
		scale = win:GetEffectiveScale() or 1
	end
	if not scale or scale <= 0 then
		scale = 1
	end
	local width = ((win and win:GetWidth()) or 1) * scale
	local bl, br, bb, bt = viewBounds()
	local left = bl + 16
	local top = bt - 40
	local al, ar, at = screenRect(anchor)
	if al and br - bl > 100 then
		local gap = 8
		if ar + gap + width <= br then
			left = ar + gap
			top = at
		elseif al - gap - width >= bl then
			left = al - gap - width
			top = at
		else
			left = bl
			top = at
		end
	end
	placeAtPixels(win, left, top)
end

local function noteClamped()
	if toldClamp then
		return
	end
	toldClamp = true
	say("The window was off the screen, so it was moved back. /azsm resetpos does this on purpose.")
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
	local left, _, top = screenRect(frame)
	if not left then
		return
	end
	local x, y = toParent(left, top, frame)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
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

local function placeDefault()
	local cfg = config()
	cfg.point = "TOPLEFT"
	cfg.rel = "TOPLEFT"
	cfg.x = 16
	cfg.y = -160
	cfg.shown = true
	cfg.mini = false
	if not frame then
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -160)
	if bubble then
		bubble.parked = false
		bubble:ClearAllPoints()
		bubble:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	applyShown()
	refresh()
	say("Window moved back on screen.")
end

local function face(fs, size)
	if not fs then
		return
	end
	if fs.SetFont then
		fs:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
	end
	if fs.SetShadowColor then
		fs:SetShadowColor(0, 0, 0, 1)
	end
	if fs.SetShadowOffset then
		fs:SetShadowOffset(0, 0)
	end
end

local function paintMinus(parent)
	local bar = parent:CreateTexture(nil, "OVERLAY")
	bar:SetTexture(K.SOLID)
	bar:SetVertexColor(1, 0.86, 0.5)
	bar:SetWidth(5)
	bar:SetHeight(1)
	bar:SetPoint("CENTER", parent, "CENTER", 0, 0)
end

local function paintX(parent)
	local mark = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	mark:SetPoint("CENTER", parent, "CENTER", 1, 2)
	mark:SetJustifyH("CENTER")
	mark:SetText("x")
	face(mark, 10)
	mark:SetTextColor(1, 0.86, 0.5)
end

local function panelBackdrop()
	return {
		bgFile = K.SOLID,
		edgeFile = K.SOLID,
		tile = false,
		edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	}
end

local function roundBackdrop(edge)
	local e = edge or 14
	local inset = 4
	if e < 12 then
		inset = 2
	end
	return {
		bgFile = K.SOLID,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = false,
		tileSize = 16,
		edgeSize = e,
		insets = { left = inset, right = inset, top = inset, bottom = inset },
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
	local tipScale = scale
	if tip.GetEffectiveScale then
		tipScale = tip:GetEffectiveScale() or scale
	end
	if not tipScale or tipScale <= 0 then
		tipScale = scale
	end
	local tipW = (tip:GetWidth() or 96) * tipScale
	local tipH = (tip:GetHeight() or 40) * tipScale
	local _, br, _, bt = viewBounds()
	local gap = 4
	local left = x + gap
	local top = y + gap + tipH
	if bt > 100 and top > bt then
		top = y - gap
	end
	if br > 100 and left + tipW > br then
		left = x - gap - tipW
	end
	left, top = fitRect(left, top, tipW, tipH)
	local px, py = toParent(left, top, tip)
	tip:ClearAllPoints()
	tip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", px, py)
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
	if count > 12 then
		count = 12
	end
	local i
	for i = 1, 12 do
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

local function showHeaderTip(kind, mode)
	if not mode then
		mode = viewMode()
	end
	if kind == "reset" then
		local line = "Starts the damage view over, including kills."
		if mode == "healing" then
			line = "Starts the healing view over. Damage and kills are kept."
		elseif mode == "boss" then
			line = "Starts the boss view over. Damage and kills are kept."
			elseif mode == "taken" then
				line = "Starts the taken view over. Damage dealt and kills are kept."
			elseif mode == "party" then
				line = "Starts the party view over. Your own damage and kills are kept."
			end
		showTip(this, "RIGHT", "Reset", nil, {
			{ line, 1, 1, 1 },
			{ "The built-in meter keeps its own numbers.", 0.75, 0.75, 0.75 },
		})
		return
	end
	if kind == "dps" then
		local title = "DPS"
		local n = rateSeconds()
		local reset = false
		if state then
			local bKey = baseFields(mode)
			if state[bKey] then
				reset = true
			end
		end
		local body
		if n < 5 then
			body = "Average damage per second since the start of the run."
			if reset then
				body = "Average damage per second since the last reset."
			end
			if mode == "healing" then
				title = "HPS"
				body = "Average healing per second since the start of the run. Overhealing is left out."
				if reset then
					body = "Average healing per second since the last reset. Overhealing is left out."
				end
			elseif mode == "boss" then
				body = "Average damage per second for this boss fight."
				if reset then
					body = "Average damage per second since the last reset on this fight."
				end
			elseif mode == "taken" then
				body = "Average damage taken per second since the start of the run."
				if reset then
					body = "Average damage taken per second since the last reset."
				end
			elseif mode == "party" then
				body = "Average party damage per second since the start of the run."
				if reset then
					body = "Average party damage per second since the last reset."
				end
			end
		else
			local span = n .. " seconds"
			body = "Damage per second over the last " .. span .. " of the run."
			if mode == "healing" then
				title = "HPS"
				body = "Healing per second over the last " .. span .. ". Overhealing is left out."
			elseif mode == "boss" then
				body = "Damage per second over the last " .. span .. " of this boss fight."
			elseif mode == "taken" then
				body = "Damage taken per second over the last " .. span .. "."
			elseif mode == "party" then
				body = "Party damage per second over the last " .. span .. "."
			end
		end
		showTip(this, "LEFT", title, nil, {
			{ body, 1, 1, 1 },
			{ "It pauses whenever the run pauses.", 0.75, 0.75, 0.75 },
		})
		return
	end
	local title = "Damage"
	local tip = "Damage dealt this run, as the game counted it."
	if mode == "healing" then
		title = "Healing"
		tip = "Healing this run, as the game counted it. Overhealing is left out."
	elseif mode == "boss" then
		title = "Boss"
		tip = "Damage dealt in the last boss fight. It stays until the next boss."
	elseif mode == "taken" then
		title = "Taken"
		tip = "Damage you took this run, split by what hit you."
	elseif mode == "party" then
		title = "Party"
		tip = "Damage dealt by each hero in the party."
	end
	local bKey = baseFields(mode)
	if state and state[bKey] then
		tip = "Since the last reset on this view, still counted by the game."
	end
	local lines = {
		{ tip, 1, 1, 1 },
	}
	local stats = AZS_STATS
	if stats then
		local function push(text)
			if text and table.getn(lines) < 8 then
				local n = table.getn(lines) + 1
				lines[n] = { text, 0.82, 0.78, 0.62 }
			end
		end
		local function mult(v)
			v = tonumber(v)
			if not v or v == 0 then
				return nil
			end
			return string.format("x%.2f", v)
		end
		local function pct(v)
			v = tonumber(v)
			if not v or v == 0 then
				return nil
			end
			if v > 0 and v <= 1.5 then
				return string.format("%.0f%%", v * 100)
			end
			return string.format("%.0f%%", v)
		end
		local function num(v)
			v = tonumber(v)
			if not v or v == 0 then
				return nil
			end
			if v == math.floor(v) then
				return string.format("%d", v)
			end
			return string.format("%.2f", v)
		end
		local text
		text = mult(stats.dmg)
		if text then
			push("Damage " .. text)
		end
		text = pct(stats.crit)
		if text then
			push("Crit " .. text)
		end
		text = mult(stats.cm)
		if text then
			push("Crit damage " .. text)
		end
		text = mult(stats.cd)
		if text then
			push("Cooldown " .. text)
		end
		text = num(stats.cnt)
		if text then
			push("Extra targets " .. text)
		end
		text = num(stats.area)
		if text then
			push("Area " .. text)
		end
		text = num(stats.echo)
		if text then
			push("Echo " .. text)
		end
	end
	showTip(this, "LEFT", title, nil, lines)
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
	row:SetWidth(K.WIDTH - 16)
	row:SetHeight(K.ROW_H)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * K.ROW_H))

	local bar = row:CreateTexture(nil, "BACKGROUND")
	bar:SetTexture(K.SOLID)
	bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	bar:SetHeight(K.ROW_H)
	bar:SetWidth(1)
	bar:SetVertexColor(0.42, 0.2, 0.08, 0.75)
	row.bar = bar

	local rule = row:CreateTexture(nil, "BORDER")
	rule:SetTexture(K.SOLID)
	rule:SetVertexColor(0, 0, 0, 0.65)
	rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	rule:SetHeight(1)

	local iconBg = row:CreateTexture(nil, "ARTWORK")
	iconBg:SetTexture(K.SOLID)
	iconBg:SetVertexColor(0, 0, 0, 1)
	iconBg:SetWidth(13)
	iconBg:SetHeight(13)
	iconBg:SetPoint("LEFT", row, "LEFT", 1, 0)
	row.iconBg = iconBg

	local arrow = CreateFrame("Button", nil, row)
	arrow:SetWidth(12)
	arrow:SetHeight(14)
	arrow:SetPoint("LEFT", row, "LEFT", 0, 0)
	arrow:SetFrameLevel((row:GetFrameLevel() or 1) + 3)
	local arrowText = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	arrowText:SetPoint("CENTER", arrow, "CENTER", 1, 0)
	arrowText:SetJustifyH("CENTER")
	face(arrowText, 11)
	arrowText:SetTextColor(1, 0.86, 0.5)
	arrowText:SetText(">")
	arrow.text = arrowText
	arrow:SetScript("OnClick", function()
		local owner = this:GetParent()
		local data = owner and owner.data
		if not data or not data.name or data.child then
			return
		end
		local cfg = config()
		if not cfg.open then
			cfg.open = {}
		end
		if cfg.open[data.name] then
			cfg.open[data.name] = nil
		else
			cfg.open[data.name] = true
		end
		refresh()
	end)
	arrow:SetScript("OnEnter", function()
		local owner = this:GetParent()
		local data = owner and owner.data
		local line = "List the talents grouped into this spell."
		if data and config().open and config().open[data.name] then
			line = "Hide the talents grouped into this spell."
		end
		showTip(this, "RIGHT", "Talents", nil, {
			{ line, 1, 1, 1 },
		})
	end)
	arrow:SetScript("OnLeave", function()
		leaveTip()
	end)
	arrow:Hide()
	row.arrow = arrow

	local icon = row:CreateTexture(nil, "OVERLAY")
	icon:SetWidth(11)
	icon:SetHeight(11)
	icon:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.icon = icon

	local cd = row:CreateTexture(nil, "OVERLAY")
	cd:SetTexture(K.SOLID)
	cd:SetWidth(11)
	cd:SetHeight(2)
	cd:SetPoint("BOTTOMLEFT", iconBg, "BOTTOMLEFT", 1, 0)
	cd:Hide()
	row.cd = cd

	local rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rank:SetJustifyH("LEFT")
	face(rank, 10)
	rank:SetTextColor(1, 0.95, 0.86)
	rank:Hide()
	row.rank = rank

	local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("LEFT", row, "LEFT", 16, 0)
	name:SetJustifyH("LEFT")
	face(name, 10)
	name:SetTextColor(1, 0.95, 0.86)
	row.name = name

	local kills = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	kills:SetWidth(K.COL_KILL)
	kills:SetJustifyH("RIGHT")
	face(kills, 10)
	kills:SetTextColor(1, 0.78, 0.45)
	row.kills = kills

	local damage = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	damage:SetWidth(K.COL_DMG)
	damage:SetJustifyH("RIGHT")
	face(damage, 10)
	damage:SetTextColor(1, 0.9, 0.55)
	row.damage = damage

	local rate = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rate:SetWidth(K.COL_DPS)
	rate:SetJustifyH("RIGHT")
	face(rate, 10)
	rate:SetTextColor(0.7, 0.92, 0.68)
	row.rate = rate

	local share = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	share:SetWidth(K.COL_PCT)
	share:SetJustifyH("RIGHT")
	face(share, 10)
	share:SetTextColor(0.95, 0.86, 0.62)
	row.share = share

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
			local host = owner.win or frame
			local total = meterTotal
			if host and host.total then
				total = host.total
			end
			local share = 0
			if total > 0 then
				share = (data.damage or 0) / total
			end
			local amountWord, rateWord, killView = meterWords(host and host.fixed)
			local lines = {
				{ string.format("%s %s", amountWord, comma(data.damage)), 1, 1, 1 },
				{ string.format("Share %s", fmtPct(share)), 0.95, 0.86, 0.62 },
				{ string.format("%s %s", rateWord, fmtRate(data.dps or 0)), 0.7, 0.92, 0.68 },
			}
			if killView and not isProc(data.proc) and not data.cast then
				table.insert(lines, { string.format("Kills %d", data.kills or 0), 1, 0.82, 0.45 })
			end
			local landed = data.hits or 0
			local crits = data.crits or 0
			if landed > 0 then
				if crits > landed then
					crits = landed
				end
				table.insert(lines, { string.format("%d hits, %d crits, %s crit", landed, crits, fmtPct(crits / landed)), 1, 0.82, 0.55 })
			end
			if data.top and data.top ~= "" then
				local topLine = "Most from " .. clientSpell(data.top)
				if data.topdps and data.topdps > 0 then
					topLine = topLine .. ", " .. fmtRate(data.topdps) .. " dps"
				end
				table.insert(lines, { topLine, 0.75, 0.85, 1 })
			end
			if data.child then
				local into = "Grouped into the spell above."
				if data.parentName and data.parentName ~= "" then
					into = "Grouped into " .. data.parentName .. "."
				end
				table.insert(lines, { into, 0.65, 0.78, 1 })
			elseif data.procs and data.procs[1] then
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
			local tipIcon = nil
			if not data.classKey then
				tipIcon = rowIcon(data)
			end
			paintTip(data.name, tipIcon, lines)
		end)
	end)
	row:SetScript("OnLeave", function()
		leaveTip()
	end)

	row.procBtns = {}
	local pi
	for pi = 1, 3 do
		local btn = CreateFrame("Button", nil, row)
		btn:SetWidth(14)
		btn:SetHeight(14)
		btn:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
		btn:SetBackdrop(panelBackdrop())
		btn:SetBackdropColor(0, 0, 0, 1)
		btn:SetBackdropBorderColor(0.45, 0.62, 0.9, 1)
		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		btn.icon = icon
		btn:SetScript("OnEnter", function()
			local owner = this
			trackTip(owner, function()
				local info = owner.info
				if not info then
					hideTip()
					return
				end
				local host = owner.win or frame
				local total = meterTotal
				if host and host.total then
					total = host.total
				end
				local amountWord, rateWord = meterWords(host and host.fixed)
				local lines
				if info.topSpell then
					lines = {
						{ string.format("%s %s", rateWord, fmtRate(info.dps or 0)), 0.7, 0.92, 0.68 },
					}
					local extra = spellTipLines(info.name)
					if extra then
						local ei
						for ei = 1, table.getn(extra) do
							if table.getn(lines) < 12 then
								lines[table.getn(lines) + 1] = extra[ei]
							end
						end
					else
						table.insert(lines, { "Their highest damage spell.", 0.75, 0.85, 1 })
					end
				else
					local share = 0
					if total > 0 then
						share = (info.damage or 0) / total
					end
					lines = {
						{ string.format("%s %s", amountWord, comma(info.damage or 0)), 1, 1, 1 },
						{ string.format("Share %s", fmtPct(share)), 0.95, 0.86, 0.62 },
						{ string.format("%s %s", rateWord, fmtRate(info.dps or 0)), 0.7, 0.92, 0.68 },
					}
					local landed = info.hits or 0
					local crits = info.crits or 0
					if landed > 0 then
						if crits > landed then
							crits = landed
						end
						table.insert(lines, { string.format("%d hits, %d crits, %s crit", landed, crits, fmtPct(crits / landed)), 1, 0.82, 0.55 })
					end
					table.insert(lines, { "Proc.", 0.65, 0.78, 1 })
				end
				local tipIcon = info.icon
				if not tipIcon or tipIcon == "" then
					tipIcon = iconFor(info.name)
				end
				paintTip(info.name, tipIcon, lines)
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

local VIEW_ORDER = { "damage", "healing", "boss", "taken", "party" }
local createDetached, detach, dock

local function otherHome(skip)
	local i
	for i = 1, table.getn(VIEW_ORDER) do
		local mode = VIEW_ORDER[i]
		if mode ~= skip and not popped[mode] and (mode ~= "party" or inParty()) then
			return mode
		end
	end
	return nil
end

local function popBox(mode)
	local cfg = config()
	if not cfg.pops then
		cfg.pops = {}
	end
	if not cfg.pops[mode] then
		cfg.pops[mode] = {}
	end
	return cfg.pops[mode]
end

local function savePop(win)
	if not win or not win.fixed then
		return
	end
	local point, _, rel, x, y = win:GetPoint(1)
	if not point then
		return
	end
	local box = popBox(win.fixed)
	box.point = point
	box.rel = rel
	box.x = x
	box.y = y
	box.width = win:GetWidth()
	box.height = win:GetHeight()
	if win:IsShown() then
		box.shown = 1
	else
		box.shown = false
	end
end

local function placePop(win)
	local box = popBox(win.fixed)
	local width = box.width
	local height = box.height
	if not width and frame then
		width = frame:GetWidth()
	end
	if not height and frame then
		height = frame:GetHeight() - (K.HEADER - K.DETACH_H)
	end
	if not width or width < 280 then
		width = K.WIDTH
	end
	local minH = K.DETACH_H + K.BOTTOM + 3 * K.ROW_H
	if not height or height < minH then
		height = minH
	end
	win:SetWidth(width)
	win:SetHeight(height)
	local s = 1
	local savedScale = config().look
	if savedScale and savedScale.scale ~= nil then
		s = tonumber(savedScale.scale) or 1
	end
	if s < 0.7 then
		s = 0.7
	elseif s > 1.5 then
		s = 1.5
	end
	if win.SetScale then
		win:SetScale(s)
		win.paintedScale = s
	end
	win:ClearAllPoints()
	if box.x ~= nil and box.y ~= nil then
		local pscale, parentLeft, parentBottom, parentTop = parentMetrics()
		local es = pscale
		if win.GetEffectiveScale then
			es = win:GetEffectiveScale() or pscale
		end
		local left, top
		if box.rel == "TOPLEFT" then
			left = parentLeft + box.x * es
			top = parentTop + box.y * es
		else
			left = parentLeft + box.x * es
			top = parentBottom + box.y * es
		end
		placeAtPixels(win, left, top)
		return
	end
	parkBeside(win, frame)
end

local function lookValue(key)
	local saved = config().look
	if saved and saved[key] ~= nil then
		return saved[key]
	end
	return LOOK[key]
end

local function lookColor(key)
	local base = LOOK[key]
	local got = lookValue(key)
	if type(got) ~= "table" then
		got = base
	end
	return got[1] or base[1], got[2] or base[2], got[3] or base[3], got[4] or base[4] or 1
end

local function ensureLook()
	local cfg = config()
	if not cfg.look then
		cfg.look = {}
	end
	return cfg.look
end

local function lookScale()
	local s = tonumber(lookValue("scale")) or 1
	if s < 0.7 then
		s = 0.7
	elseif s > 1.5 then
		s = 1.5
	end
	return s
end

local function paintBorder(btn, br, bg, bb)
	if btn and btn.SetBackdropBorderColor then
		btn:SetBackdropBorderColor(br, bg, bb, 1)
	end
end

local function applyLook(buttons)
	local pr, pg, pb, pa = lookColor("panel")
	local brdR, brdG, brdB = lookColor("border")
	local s = lookScale()
	local function paintWin(win, alpha)
		if not win then
			return
		end
		win:SetBackdropColor(pr, pg, pb, alpha)
		win:SetBackdropBorderColor(brdR, brdG, brdB, 1)
		if win.SetAlpha then
			local fade = tonumber(lookValue("alpha"))
			if not fade then
				fade = 1
			end
			if fade < 0 then
				fade = 0
			elseif fade > 1 then
				fade = 1
			end
			win:SetAlpha(fade)
		end
		if win.SetScale and win.paintedScale ~= s then
			local sl, _, st = screenRect(win)
			win:SetScale(s)
			win.paintedScale = s
			if sl then
				local x, y = toParent(sl, st, win)
				win:ClearAllPoints()
				win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
				if win == frame then
					savePoint()
				elseif win.fixed then
					savePop(win)
				end
			end
		end
	end
	paintWin(frame, pa)
	paintWin(bubble, pa)
	local mode, pop
	for mode, pop in pairs(popped) do
		paintWin(pop, pa)
		if buttons then
			paintBorder(pop.closeBtn, brdR, brdG, brdB)
			paintBorder(pop.resetBtn, brdR, brdG, brdB)
		end
	end
	if frame and frame.tip then
		frame.tip:SetBackdropColor(pr, pg, pb, 1)
		frame.tip:SetBackdropBorderColor(brdR, brdG, brdB, 1)
	end
	if settings then
		settings:SetBackdropColor(pr * 0.55, pg * 0.55, pb * 0.55, 1)
		settings:SetBackdropBorderColor(brdR, brdG, brdB, 1)
		if settings.SetAlpha then
			settings:SetAlpha(1)
		end
		if settings.header then
			settings.header:SetBackdropColor(brdR * 0.46, brdG * 0.46, brdB * 0.46, 1)
			settings.header:SetBackdropBorderColor(brdR, brdG, brdB, 1)
		end
		if buttons then
			paintBorder(settings.closeBtn, brdR, brdG, brdB)
			paintBorder(settings.resetBtn, brdR, brdG, brdB)
		end
	end
	local keys = { "damage", "healing", "boss", "taken", "party" }
	local ki
	for ki = 1, table.getn(keys) do
		local key = keys[ki]
		local r, g, b = lookColor(key)
		local tint = HEADER_TINT[key]
		tint[1], tint[2], tint[3] = r * 0.46, g * 0.46, b * 0.46
		tint[4], tint[5], tint[6] = r, g, b
	end
	if frame and frame.modeBtns then
		for ki = 1, table.getn(frame.modeBtns) do
			local btn = frame.modeBtns[ki]
			local tint = HEADER_TINT[btn.mode]
			if tint then
				btn.br, btn.bg, btn.bb = tint[1], tint[2], tint[3]
				btn.er, btn.eg, btn.eb = tint[4], tint[5], tint[6]
				btn.tr, btn.tg, btn.tb = tone(tint[4], tint[5], tint[6])
			end
		end
	end
	if buttons and frame then
		paintBorder(frame.minBtn, brdR, brdG, brdB)
		paintBorder(frame.resetBtn, brdR, brdG, brdB)
		paintBorder(frame.setBtn, brdR, brdG, brdB)
		paintBorder(bubble, brdR, brdG, brdB)
	end
end

createDetached = function(mode)
	local win = CreateFrame("Frame", "AZSSpellMeterPop" .. mode, UIParent)
	win.fixed = mode
	win.headH = K.DETACH_H
	win.scrollPos = 0
	win.rows = {}
	win:SetFrameStrata("HIGH")
	win:SetMovable(true)
	win:EnableMouse(true)
	win:EnableMouseWheel(true)
	if win.SetResizable then
		win:SetResizable(true)
	end
	local minH = K.DETACH_H + K.BOTTOM + 3 * K.ROW_H
	local maxH = K.DETACH_H + K.BOTTOM + K.MAX_ROWS * K.ROW_H
	if win.SetMinResize then
		win:SetMinResize(280, minH)
	end
	if win.SetMaxResize then
		win:SetMaxResize(760, maxH)
	end
	if win.SetClampedToScreen then
		win:SetClampedToScreen(true)
	end
	win:SetBackdrop(roundBackdrop(12))
	win:SetBackdropColor(0.05, 0.04, 0.03, 0.82)
	win:SetBackdropBorderColor(0.78, 0.58, 0.22, 1)
	placePop(win)

	local header = CreateFrame("Button", nil, win)
	header:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -6)
	header:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -6)
	header:SetHeight(16)
	header:SetBackdrop(panelBackdrop())
	header:SetBackdropColor(0.34, 0.2, 0.06, 0.88)
	header:SetBackdropBorderColor(0.72, 0.5, 0.16, 0.7)
	win.header = header
	local function startWinDrag()
		if config().locked then
			return
		end
		win.dragging = true
		win:StartMoving()
	end
	local function stopWinDrag()
		win.dragging = false
		win:StopMovingOrSizing()
		savePop(win)
	end
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", startWinDrag)
	header:SetScript("OnDragStop", stopWinDrag)

	local brandBack = header:CreateTexture(nil, "ARTWORK")
	brandBack:SetTexture(K.SOLID)
	brandBack:SetVertexColor(0, 0, 0, 0.55)
	brandBack:SetWidth(14)
	brandBack:SetHeight(14)
	brandBack:SetPoint("LEFT", header, "LEFT", 2, 0)
	local brand = header:CreateTexture(nil, "OVERLAY")
	brand:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
	brand:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	brand:SetWidth(12)
	brand:SetHeight(12)
	brand:SetPoint("CENTER", brandBack, "CENTER", 0, 0)
	win.brand = brand
	local brandText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	brandText:SetPoint("LEFT", brandBack, "RIGHT", 4, 0)
	brandText:SetJustifyH("LEFT")
	brandText:SetText(VIEW_TITLE[mode] or "Spell Meter")
	face(brandText, 10)
	brandText:SetTextColor(1, 0.9, 0.62)
	win.brandText = brandText

	local closeBtn = CreateFrame("Button", nil, header)
	closeBtn:SetPoint("RIGHT", header, "RIGHT", -3, 0)
	closeBtn:SetWidth(14)
	closeBtn:SetHeight(14)
	closeBtn:SetBackdrop(roundBackdrop(8))
	closeBtn:SetBackdropColor(0.16, 0.1, 0.03, 0.85)
	closeBtn:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
	paintX(closeBtn)
	closeBtn:SetScript("OnClick", function()
		dock(mode)
	end)
	closeBtn:SetScript("OnEnter", function()
		closeBtn:SetBackdropBorderColor(1, 0.86, 0.45, 1)
		showTip(this, "RIGHT", "Bring back", nil, {
			{ "Close this window and show the view on the main meter.", 1, 1, 1 },
		})
	end)
	closeBtn:SetScript("OnLeave", function()
		applyLook(true)
		leaveTip()
	end)
	win.closeBtn = closeBtn

	local resetBtn = CreateFrame("Button", nil, header)
	resetBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
	resetBtn:SetHeight(14)
	resetBtn:SetWidth(42)
	resetBtn:SetBackdrop(roundBackdrop(8))
	resetBtn:SetBackdropColor(0.16, 0.1, 0.03, 0.85)
	resetBtn:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
	local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	resetText:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
	resetText:SetText("Reset")
	face(resetText, 9)
	resetText:SetTextColor(1, 0.86, 0.5)
	resetBtn:SetScript("OnClick", function()
		windowReset(false, mode)
		refresh()
		if mode == "healing" then
			say("Reset. Healing starts over in this window. The built-in meter is unchanged.")
		elseif mode == "boss" then
			say("Reset. Boss damage starts over in this window. The built-in meter is unchanged.")
		elseif mode == "taken" then
			say("Reset. Damage taken starts over in this window.")
		elseif mode == "party" then
			say("Reset. Party damage starts over in this window.")
		else
			say("Reset. Damage and kills start over in this window. The built-in meter is unchanged.")
		end
	end)
	resetBtn:SetScript("OnEnter", function()
		resetBtn:SetBackdropBorderColor(1, 0.86, 0.45, 1)
		showHeaderTip("reset", mode)
	end)
	resetBtn:SetScript("OnLeave", function()
		applyLook(true)
		leaveTip()
	end)
	win.resetBtn = resetBtn

	local dpsBtn = CreateFrame("Button", nil, header)
	dpsBtn:SetPoint("RIGHT", resetBtn, "LEFT", -8, 0)
	dpsBtn:SetWidth(52)
	dpsBtn:SetHeight(16)
	local dpsText = dpsBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dpsText:SetPoint("RIGHT", dpsBtn, "RIGHT", 0, 0)
	dpsText:SetJustifyH("RIGHT")
	dpsText:SetText("0 dps")
	face(dpsText, 10)
	dpsText:SetTextColor(0.78, 0.95, 0.72)
	win.dpsText = dpsText
	win.dpsBtn = dpsBtn
	dpsBtn:RegisterForDrag("LeftButton")
	dpsBtn:SetScript("OnDragStart", startWinDrag)
	dpsBtn:SetScript("OnDragStop", stopWinDrag)
	dpsBtn:SetScript("OnEnter", function()
		showHeaderTip("dps", mode)
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
	win.totalText = totalText
	win.totalBtn = totalBtn
	totalBtn:RegisterForDrag("LeftButton")
	totalBtn:SetScript("OnDragStart", startWinDrag)
	totalBtn:SetScript("OnDragStop", stopWinDrag)
	totalBtn:SetScript("OnEnter", function()
		showHeaderTip("total", mode)
	end)
	totalBtn:SetScript("OnLeave", function()
		leaveTip()
	end)
	brandText:SetPoint("RIGHT", totalBtn, "LEFT", -8, 0)

	local cols = CreateFrame("Frame", nil, win)
	cols:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -(K.DETACH_H - K.COL_H))
	cols:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -(K.DETACH_H - K.COL_H))
	cols:SetHeight(12)
	win.cols = cols
	local countText = cols:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", cols, "LEFT", 2, 0)
	countText:SetJustifyH("LEFT")
	countText:SetText("")
	face(countText, 9)
	countText:SetTextColor(0.55, 0.5, 0.4)
	win.countText = countText
	win.sortBtns = {}

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
			win.scrollPos = 0
			refresh()
		end)
		table.insert(win.sortBtns, btn)
		return btn
	end

	local dpsCol = makeSortButton("dps", "DPS", K.COL_DPS, "RIGHT")
	dpsCol:SetPoint("RIGHT", cols, "RIGHT", -2, 0)
	local shareCol = makeSortButton("share", "%", K.COL_PCT, "RIGHT")
	shareCol:SetPoint("RIGHT", dpsCol, "LEFT", -6, 0)
	local dmgCol = makeSortButton("damage", "Damage", K.COL_DMG, "RIGHT")
	dmgCol:SetPoint("RIGHT", shareCol, "LEFT", -6, 0)
	local killCol = makeSortButton("kills", "Kills", K.COL_KILL, "RIGHT")
	killCol:SetPoint("RIGHT", dmgCol, "LEFT", -6, 0)
	win.dpsCol = dpsCol
	win.shareCol = shareCol
	win.dmgCol = dmgCol
	win.killCol = killCol

	local scrollFrame = CreateFrame("ScrollFrame", nil, win)
	scrollFrame:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -K.DETACH_H)
	scrollFrame:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -K.DETACH_H)
	scrollFrame:SetHeight(8 * K.ROW_H)
	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetWidth(K.WIDTH - 16)
	scrollChild:SetHeight(K.MAX_ROWS * K.ROW_H)
	scrollFrame:SetScrollChild(scrollChild)
	win.scroll = scrollFrame
	win.scrollChild = scrollChild
	local i
	for i = 1, K.ROW_POOL do
		win.rows[i] = createRow(scrollChild, i)
		win.rows[i].win = win
		win.rows[i]:SetWidth(K.WIDTH - 16)
	end
	local emptyText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyText:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -(K.DETACH_H + 6))
	emptyText:SetJustifyH("LEFT")
	face(emptyText, 10)
	emptyText:SetTextColor(0.62, 0.56, 0.46)
	emptyText:Hide()
	win.emptyText = emptyText

	local function onWheel()
		win.scrollPos = (win.scrollPos or 0) - (arg1 or 0) * K.ROW_H
		refresh()
	end
	win:SetScript("OnMouseWheel", onWheel)
	header:EnableMouseWheel(true)
	header:SetScript("OnMouseWheel", onWheel)
	scrollFrame:EnableMouseWheel(true)
	scrollFrame:SetScript("OnMouseWheel", onWheel)
	for i = 1, K.ROW_POOL do
		win.rows[i]:EnableMouseWheel(true)
		win.rows[i]:SetScript("OnMouseWheel", onWheel)
		if win.rows[i].procBtns then
			local pi
			for pi = 1, 3 do
				win.rows[i].procBtns[pi]:EnableMouseWheel(true)
				win.rows[i].procBtns[pi]:SetScript("OnMouseWheel", onWheel)
			end
			if win.rows[i].arrow then
				win.rows[i].arrow:EnableMouseWheel(true)
				win.rows[i].arrow:SetScript("OnMouseWheel", onWheel)
			end
		end
	end
	cols:EnableMouseWheel(true)
	cols:SetScript("OnMouseWheel", onWheel)
	for i = 1, table.getn(win.sortBtns) do
		win.sortBtns[i]:EnableMouseWheel(true)
		win.sortBtns[i]:SetScript("OnMouseWheel", onWheel)
	end
	totalBtn:EnableMouseWheel(true)
	totalBtn:SetScript("OnMouseWheel", onWheel)
	dpsBtn:EnableMouseWheel(true)
	dpsBtn:SetScript("OnMouseWheel", onWheel)
	resetBtn:EnableMouseWheel(true)
	resetBtn:SetScript("OnMouseWheel", onWheel)
	closeBtn:EnableMouseWheel(true)
	closeBtn:SetScript("OnMouseWheel", onWheel)

	local grip = CreateFrame("Button", nil, win)
	grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 2)
	grip:SetWidth(14)
	grip:SetHeight(14)
	grip:SetFrameLevel((win:GetFrameLevel() or 1) + 5)
	local gi
	for gi = 1, 3 do
		local mark = grip:CreateTexture(nil, "ARTWORK")
		mark:SetTexture(K.SOLID)
		mark:SetVertexColor(0.72, 0.56, 0.24, 0.95)
		mark:SetWidth(gi * 3)
		mark:SetHeight(1)
		mark:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1, 1 + (gi - 1) * 3)
	end
	grip:SetScript("OnMouseDown", function()
		if config().locked then
			return
		end
		local scale = 1
		if win.GetEffectiveScale then
			scale = win:GetEffectiveScale() or 1
		end
		local cx, cy = GetCursorPosition()
		win.sizeX = cx / scale
		win.sizeY = cy / scale
		win.sizeW = win:GetWidth()
		win.sizeH = win:GetHeight()
		win.sizing = true
	end)
	grip:SetScript("OnMouseUp", function()
		if not win.sizing then
			return
		end
		win.sizing = false
		if clampIntoView(win, 120, 20) then
			noteClamped()
		end
		savePop(win)
		refresh()
	end)
	win:SetScript("OnUpdate", function()
		if win.needNudge and win:GetLeft() then
			win.needNudge = nil
			if clampIntoView(win) then
				savePop(win)
			end
		end
		if win.sizing then
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
				win.sizing = false
				savePop(win)
				refresh()
			else
				local scale = 1
				if win.GetEffectiveScale then
					scale = win:GetEffectiveScale() or 1
				end
				local cx, cy = GetCursorPosition()
				cx = cx / scale
				cy = cy / scale
				local w = win.sizeW + (cx - win.sizeX)
				local h = win.sizeH - (cy - win.sizeY)
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
				win:SetWidth(w)
				win:SetHeight(h)
			end
		end
		if win.sizing or win.dragging then
			win.clampWait = 0
		else
			win.clampWait = (win.clampWait or 0) + (arg1 or 0)
			if win.clampWait >= 0.2 and clampIntoView(win, 120, 20) then
				savePop(win)
				noteClamped()
			end
		end
	end)
	win:Hide()
	return win
end

detach = function(mode)
	if not VIEW_TITLE[mode] then
		return
	end
	if popped[mode] then
		popped[mode]:Show()
		refresh()
		return
	end
	if viewMode() == mode then
		local nextMode = otherHome(mode)
		if not nextMode then
			say("Bring another view back before opening this one on its own.")
			return
		end
		config().viewChosen = 1
		config().view = nextMode
		scroll = 0
	end
	local win = built[mode]
	if not win then
		win = createDetached(mode)
		built[mode] = win
	end
	popped[mode] = win
	win:Show()
	applyLook(true)
	win.needNudge = true
	if clampIntoView(win) then
		savePop(win)
	else
		savePop(win)
	end
	refresh()
end

dock = function(mode)
	local win = popped[mode]
	popped[mode] = nil
	if win then
		win:Hide()
		savePop(win)
	end
	local box = popBox(mode)
	box.shown = false
	config().viewChosen = 1
	config().view = mode
	scroll = 0
	if frame and not frame:IsShown() then
		config().shown = true
		config().mini = false
		applyShown()
	end
	refresh()
end

local function restorePops()
	local cfg = config()
	if not cfg.pops then
		return
	end
	local mode, box
	for mode, box in pairs(cfg.pops) do
		if box.shown and VIEW_TITLE[mode] then
			detach(mode)
		end
	end
end

local function finishMainSize()
	if not sizing then
		return
	end
	sizing = false
	if clampIntoView(frame) then
		noteClamped()
	end
	local saved = config()
	saved.width = frame:GetWidth()
	saved.height = frame:GetHeight()
	savePoint()
	refresh()
end

local function onMainGripDown()
	if config().locked then
		return
	end
	local scale = 1
	if frame.GetEffectiveScale then
		scale = frame:GetEffectiveScale() or 1
	end
	local cx, cy = GetCursorPosition()
	sizeX = cx / scale
	sizeY = cy / scale
	sizeW = frame:GetWidth()
	sizeH = frame:GetHeight()
	sizing = true
	pinTopLeft()
end

local function onMainWheel()
	scroll = scroll - (arg1 or 0) * K.ROW_H
	refresh()
end

local function onMainUpdate()
	if sizing then
		if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
			finishMainSize()
		else
			local scale = 1
			if frame.GetEffectiveScale then
				scale = frame:GetEffectiveScale() or 1
			end
			local cx, cy = GetCursorPosition()
			cx = cx / scale
			cy = cy / scale
			local w = sizeW + (cx - sizeX)
			local h = sizeH - (cy - sizeY)
			local minH = K.HEADER + K.BOTTOM + 3 * K.ROW_H
			local maxH = K.HEADER + K.BOTTOM + K.MAX_ROWS * K.ROW_H
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
	if sizing or dragging or not frame:IsShown() then
		frame.clampWait = 0
	else
		frame.clampWait = (frame.clampWait or 0) + (arg1 or 0)
		if frame.clampWait >= 0.2 and clampIntoView(frame, 120, 20) then
			savePoint()
			noteClamped()
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
		for n = 1, K.ROW_POOL do
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
end

local function onBubbleUpdate()
	if config().mini and not bubble.parked then
		if not bubble.measuring then
			frame:Show()
			bubble.measuring = true
			return
		end
		if clampIntoView(frame, 120, 20) then
			savePoint()
			noteClamped()
		end
		local x, y
		if frame.minBtn then
			x, y = frame.minBtn:GetCenter()
		end
		frame:Hide()
		bubble.measuring = nil
		if x and y then
			bubble:ClearAllPoints()
			bubble:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
			bubble.parked = true
		end
	end
	if config().mini and bubble.parked and not bubble.moving and clampIntoView(bubble, 36, 18) then
		noteClamped()
	end
	if not config().mini then
		return
	end
	bubble.tick = (bubble.tick or 0) + (arg1 or 0)
	if bubble.tick >= 0.2 then
		bubble.tick = 0
		refresh()
	end
end

local function buildSettings()
	local box = CreateFrame("Frame", "AZSSpellMeterSettings", UIParent)
	settings = box
	box:SetWidth(248)
	box:SetHeight(552)
	box:SetFrameStrata("DIALOG")
	box:SetMovable(true)
	box:EnableMouse(true)
	box:EnableMouseWheel(true)
	box:SetScript("OnMouseWheel", function() end)
	if box.SetClampedToScreen then
		box:SetClampedToScreen(true)
	end
	box:SetBackdrop(roundBackdrop(12))
	box:SetBackdropColor(0.04, 0.03, 0.02, 0.96)
	box:SetBackdropBorderColor(0.78, 0.58, 0.22, 1)
	box.pick = "panel"
	box.pickName = "Window"
	if UISpecialFrames then
		table.insert(UISpecialFrames, "AZSSpellMeterSettings")
	end

	local header = CreateFrame("Button", nil, box)
	header:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)
	header:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -6)
	header:SetHeight(16)
	header:SetBackdrop(panelBackdrop())
	header:SetBackdropColor(0.34, 0.2, 0.06, 0.88)
	header:SetBackdropBorderColor(0.72, 0.5, 0.16, 0.7)
	box.header = header
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function()
		box.dragging = true
		box:StartMoving()
	end)
	header:SetScript("OnDragStop", function()
		box.dragging = false
		box:StopMovingOrSizing()
		local point, _, rel, x, y = box:GetPoint(1)
		if point then
			local saved = ensureLook()
			saved.spoint = point
			saved.srel = rel
			saved.sx = x
			saved.sy = y
		end
	end)
	box:SetScript("OnUpdate", function()
		if not this.needNudge or not this:IsShown() or not this:GetLeft() then
			return
		end
		this.needNudge = nil
		if clampIntoView(this) then
			local point, _, rel, x, y = this:GetPoint(1)
			if point then
				local saved = ensureLook()
				saved.spoint = point
				saved.srel = rel
				saved.sx = x
				saved.sy = y
			end
		end
	end)
	local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("LEFT", header, "LEFT", 6, 0)
	title:SetText("Settings")
	face(title, 10)
	title:SetTextColor(1, 0.9, 0.62)
	local closeBtn = CreateFrame("Button", nil, header)
	closeBtn:SetPoint("RIGHT", header, "RIGHT", -3, 0)
	closeBtn:SetWidth(14)
	closeBtn:SetHeight(14)
	closeBtn:SetBackdrop(roundBackdrop(8))
	closeBtn:SetBackdropColor(0.16, 0.1, 0.03, 0.85)
	closeBtn:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
	paintX(closeBtn)
	box.closeBtn = closeBtn
	closeBtn:SetScript("OnClick", function()
		box:Hide()
	end)
	closeBtn:SetScript("OnEnter", function()
		closeBtn:SetBackdropBorderColor(1, 0.86, 0.45, 1)
		showTip(this, "RIGHT", "Close", nil, {
			{ "Hide settings. The meter stays as it is.", 1, 1, 1 },
		})
	end)
	closeBtn:SetScript("OnLeave", function()
		applyLook(true)
		leaveTip()
	end)

	local function snap(v, step, lo, hi)
		local n = math.floor((v or lo) / step + 0.5) * step
		if n < lo then
			n = lo
		elseif n > hi then
			n = hi
		end
		return n
	end

	local function makeSlider(y, label, minV, maxV, step)
		local name = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetPoint("TOPLEFT", box, "TOPLEFT", 12, y)
		name:SetText(label)
		face(name, 10)
		name:SetTextColor(0.85, 0.78, 0.62)
		local value = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, y)
		value:SetJustifyH("RIGHT")
		face(value, 10)
		value:SetTextColor(1, 0.9, 0.62)
		local slider = CreateFrame("Slider", nil, box)
		slider:SetPoint("TOPLEFT", box, "TOPLEFT", 12, y - 14)
		slider:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, y - 14)
		slider:SetHeight(12)
		slider:SetOrientation("HORIZONTAL")
		slider:SetMinMaxValues(minV, maxV)
		slider:SetValueStep(step)
		slider.step = step
		slider.lo = minV
		slider.hi = maxV
		slider:SetBackdrop(panelBackdrop())
		slider:SetBackdropColor(0.08, 0.06, 0.04, 0.9)
		slider:SetBackdropBorderColor(0.4, 0.3, 0.12, 1)
		slider:SetThumbTexture(K.SOLID)
		if slider.GetThumbTexture then
			local thumb = slider:GetThumbTexture()
			if thumb then
				thumb:SetWidth(8)
				thumb:SetHeight(12)
				thumb:SetVertexColor(1, 0.86, 0.5, 1)
			end
		end
		slider:EnableMouseWheel(true)
		slider:SetScript("OnMouseWheel", function()
			local v = this:GetValue() or this.lo or 0
			local delta = this.step or 1
			if arg1 and arg1 < 0 then
				v = v - delta
			else
				v = v + delta
			end
			this:SetValue(v)
		end)
		slider:SetValue(minV)
		return slider, value, name
	end

	local function fitWindows()
		if frame and frame:IsShown() and clampIntoView(frame) then
			savePoint()
		end
		if bubble and bubble:IsShown() and clampIntoView(bubble) then
		end
		local mode, pop
		for mode, pop in pairs(popped) do
			if pop:IsShown() and clampIntoView(pop) then
				savePop(pop)
			end
		end
	end

	local scaleSlider, scaleValue = makeSlider(-30, "Scale", 70, 150, 5)
	box.scaleSlider = scaleSlider
	box.scaleValue = scaleValue
	local fadeSlider, fadeValue = makeSlider(-66, "Opacity", 0, 100, 1)
	box.fadeSlider = fadeSlider
	box.fadeValue = fadeValue
	local opSlider, opValue = makeSlider(-102, "Background", 0, 100, 1)
	box.opSlider = opSlider
	box.opValue = opValue
	local dpsSlider, dpsValue, dpsName = makeSlider(-138, "DPS window", 5, 120, 5)
	box.dpsSlider = dpsSlider
	box.dpsValue = dpsValue

	local function makeCheck(y, text)
		local hit = CreateFrame("Button", nil, box)
		hit:SetPoint("TOPLEFT", box, "TOPLEFT", 12, y)
		hit:SetWidth(220)
		hit:SetHeight(16)
		local square = CreateFrame("Frame", nil, hit)
		square:SetPoint("LEFT", hit, "LEFT", 0, 0)
		square:SetWidth(14)
		square:SetHeight(14)
		square:SetBackdrop(roundBackdrop(8))
		square:SetBackdropColor(0.08, 0.06, 0.04, 0.9)
		square:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
		local mark = square:CreateTexture(nil, "OVERLAY")
		mark:SetTexture(K.SOLID)
		mark:SetVertexColor(1, 0.86, 0.5, 1)
		mark:SetWidth(8)
		mark:SetHeight(8)
		mark:SetPoint("CENTER", square, "CENTER", 0, 0)
		mark:Hide()
		local label = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", square, "RIGHT", 6, 0)
		label:SetText(text)
		face(label, 10)
		label:SetTextColor(0.9, 0.84, 0.68)
		hit.mark = mark
		return hit
	end

	local dpsAllHit = makeCheck(-174, "Since the start")
	box.dpsAllMark = dpsAllHit.mark
	local cdHit = makeCheck(-192, "Cooldown bars")
	box.cdMark = cdHit.mark
	local lockHit = makeCheck(-210, "Lock windows")
	box.lockMark = lockHit.mark
	local detailHit = makeCheck(-228, "Under the spell")
	box.detailMark = detailHit.mark
	local wrapHit = makeCheck(-246, "Wrap names")
	box.wrapMark = wrapHit.mark

	local columns = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	columns:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -268)
	columns:SetText("Columns")
	face(columns, 10)
	columns:SetTextColor(1, 0.9, 0.62)
	local colKillHit = makeCheck(-284, "Kills")
	local colDmgHit = makeCheck(-302, "Damage")
	local colShareHit = makeCheck(-320, "Share")
	local colDpsHit = makeCheck(-338, "DPS")

	local colors = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	colors:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -362)
	colors:SetText("Colors")
	face(colors, 10)
	colors:SetTextColor(1, 0.9, 0.62)

	local picks = {
		{ key = "panel", name = "Window", tip = "Background of the meter windows." },
		{ key = "border", name = "Border", tip = "Edge of the meter windows and their buttons." },
		{ key = "damage", name = "Damage", tip = "Damage title, bars, and numbers." },
		{ key = "healing", name = "Healing", tip = "Healing title, bars, and numbers." },
		{ key = "boss", name = "Boss", tip = "Boss title, bars, and numbers." },
		{ key = "taken", name = "Taken", tip = "Taken title, bars, and numbers." },
		{ key = "party", name = "Party", tip = "Party title, bars, and numbers." },
	}
	box.swatches = {}
	local sw, gap, n = 22, 8, table.getn(picks)
	local rowW = n * sw + (n - 1) * gap
	local startX = math.floor((248 - rowW) / 2)
	local si
	for si = 1, n do
		local spec = picks[si]
		local b = CreateFrame("Button", nil, box)
		b:SetWidth(sw)
		b:SetHeight(sw)
		b:SetPoint("TOPLEFT", box, "TOPLEFT", startX + (si - 1) * (sw + gap), -378)
		b:SetBackdrop(roundBackdrop(8))
		b.key = spec.key
		b.pickName = spec.name
		b.tip = spec.tip
		b:SetScript("OnClick", function()
			box.pick = this.key
			box.pickName = this.pickName
			box.sync()
		end)
		b:SetScript("OnEnter", function()
			showTip(this, "RIGHT", this.pickName, nil, {
				{ this.tip, 1, 1, 1 },
			})
		end)
		b:SetScript("OnLeave", function()
			leaveTip()
		end)
		box.swatches[si] = b
	end

	local caption = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	caption:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -406)
	caption:SetText("Window")
	face(caption, 10)
	caption:SetTextColor(1, 0.9, 0.62)
	box.caption = caption

	local redSlider, redValue, redName = makeSlider(-424, "Red", 0, 255, 1)
	local greenSlider, greenValue, greenName = makeSlider(-456, "Green", 0, 255, 1)
	local blueSlider, blueValue, blueName = makeSlider(-488, "Blue", 0, 255, 1)
	redName:SetTextColor(1, 0.55, 0.45)
	greenName:SetTextColor(0.55, 0.9, 0.55)
	blueName:SetTextColor(0.55, 0.75, 1)
	box.red = redSlider
	box.green = greenSlider
	box.blue = blueSlider
	box.redValue = redValue
	box.greenValue = greenValue
	box.blueValue = blueValue

	local resetBtn = CreateFrame("Button", nil, box)
	resetBtn:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 10)
	resetBtn:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 10)
	resetBtn:SetHeight(18)
	resetBtn:SetBackdrop(roundBackdrop(8))
	resetBtn:SetBackdropColor(0.16, 0.1, 0.03, 0.85)
	resetBtn:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
	local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	resetText:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
	resetText:SetText("Reset settings")
	face(resetText, 10)
	resetText:SetTextColor(1, 0.86, 0.5)
	box.resetBtn = resetBtn

	local function syncSettings()
		box.quiet = true
		local pct = snap((tonumber(lookValue("scale")) or 1) * 100, 5, 70, 150)
		scaleSlider:SetValue(pct)
		scaleValue:SetText(pct .. "%")
		local fade = tonumber(lookValue("alpha"))
		if not fade then
			fade = 1
		end
		fade = snap(fade * 100, 1, 0, 100)
		fadeSlider:SetValue(fade)
		fadeValue:SetText(fade .. "%")
		local _, _, _, pa = lookColor("panel")
		local op = snap(pa * 100, 1, 0, 100)
		opSlider:SetValue(op)
		opValue:SetText(op .. "%")
		local window = snap(tonumber(lookValue("dps")) or 10, 5, 5, 120)
		dpsSlider:SetValue(window)
		if lookValue("dpsAll") then
			dpsAllHit.mark:Show()
			dpsValue:SetText("Since start")
			dpsName:SetTextColor(0.45, 0.4, 0.32)
			dpsValue:SetTextColor(0.55, 0.5, 0.4)
			dpsSlider:EnableMouse(false)
			dpsSlider:EnableMouseWheel(false)
		else
			dpsAllHit.mark:Hide()
			dpsValue:SetText(window .. " s")
			dpsName:SetTextColor(0.85, 0.78, 0.62)
			dpsValue:SetTextColor(1, 0.9, 0.62)
			dpsSlider:EnableMouse(true)
			dpsSlider:EnableMouseWheel(true)
		end
		if lookValue("cd") == false then
			cdHit.mark:Hide()
		else
			cdHit.mark:Show()
		end
		if config().locked then
			lockHit.mark:Show()
		else
			lockHit.mark:Hide()
		end
		if lookValue("detail") then
			detailHit.mark:Show()
		else
			detailHit.mark:Hide()
		end
		if lookValue("wrap") then
			wrapHit.mark:Show()
		else
			wrapHit.mark:Hide()
		end
		local function showCol(hit, key)
			if lookValue(key) == false then
				hit.mark:Hide()
			else
				hit.mark:Show()
			end
		end
		showCol(colKillHit, "colKill")
		showCol(colDmgHit, "colDmg")
		showCol(colShareHit, "colShare")
		showCol(colDpsHit, "colDps")
		local pick = box.pick or "panel"
		local i
		for i = 1, table.getn(box.swatches) do
			local swatch = box.swatches[i]
			local r, g, b = lookColor(swatch.key)
			swatch:SetBackdropColor(r, g, b, 1)
			if swatch.key == pick then
				swatch:SetBackdropBorderColor(1, 0.95, 0.75, 1)
			else
				local br, bg, bb = lookColor("border")
				swatch:SetBackdropBorderColor(br, bg, bb, 1)
			end
		end
		local r, g, b = lookColor(pick)
		redSlider:SetValue(snap(r * 255, 1, 0, 255))
		greenSlider:SetValue(snap(g * 255, 1, 0, 255))
		blueSlider:SetValue(snap(b * 255, 1, 0, 255))
		redValue:SetText(tostring(math.floor(r * 255 + 0.5)))
		greenValue:SetText(tostring(math.floor(g * 255 + 0.5)))
		blueValue:SetText(tostring(math.floor(b * 255 + 0.5)))
		caption:SetText(box.pickName or "Window")
		caption:SetTextColor(r, g, b)
		box.quiet = false
	end
	box.sync = syncSettings

	local function writeScale()
		if box.quiet then
			return
		end
		local pct = snap(scaleSlider:GetValue() or 100, 5, 70, 150)
		if math.abs((scaleSlider:GetValue() or pct) - pct) > 0.01 then
			box.quiet = true
			scaleSlider:SetValue(pct)
			box.quiet = false
		end
		ensureLook().scale = pct / 100
		scaleValue:SetText(pct .. "%")
		applyLook(true)
		fitWindows()
		refresh()
	end
	local function writeFade()
		if box.quiet then
			return
		end
		local pct = snap(fadeSlider:GetValue() or 100, 1, 0, 100)
		if math.abs((fadeSlider:GetValue() or pct) - pct) > 0.01 then
			box.quiet = true
			fadeSlider:SetValue(pct)
			box.quiet = false
		end
		ensureLook().alpha = pct / 100
		fadeValue:SetText(pct .. "%")
		applyLook(true)
		refresh()
	end
	local function writeOp()
		if box.quiet then
			return
		end
		local op = snap(opSlider:GetValue() or 82, 1, 0, 100)
		if math.abs((opSlider:GetValue() or op) - op) > 0.01 then
			box.quiet = true
			opSlider:SetValue(op)
			box.quiet = false
		end
		local r, g, b = lookColor("panel")
		ensureLook().panel = { r, g, b, op / 100 }
		opValue:SetText(op .. "%")
		applyLook(true)
		refresh()
	end
	local function writeDps()
		if box.quiet then
			return
		end
		local window = snap(dpsSlider:GetValue() or 10, 5, 5, 120)
		if math.abs((dpsSlider:GetValue() or window) - window) > 0.01 then
			box.quiet = true
			dpsSlider:SetValue(window)
			box.quiet = false
		end
		ensureLook().dps = window
		if lookValue("dpsAll") then
			dpsValue:SetText("Since start")
		else
			dpsValue:SetText(window .. " s")
		end
		refresh()
	end
	local function writeRgb()
		if box.quiet then
			return
		end
		local key = box.pick or "panel"
		local r = snap(redSlider:GetValue() or 0, 1, 0, 255)
		local g = snap(greenSlider:GetValue() or 0, 1, 0, 255)
		local b = snap(blueSlider:GetValue() or 0, 1, 0, 255)
		local a = 1
		if key == "panel" then
			a = (opSlider:GetValue() or 82) / 100
		else
			local _, _, _, oldA = lookColor(key)
			a = oldA or 1
		end
		ensureLook()[key] = { r / 255, g / 255, b / 255, a }
		redValue:SetText(tostring(r))
		greenValue:SetText(tostring(g))
		blueValue:SetText(tostring(b))
		caption:SetTextColor(r / 255, g / 255, b / 255)
		applyLook(true)
		refresh()
		local i
		for i = 1, table.getn(box.swatches) do
			local swatch = box.swatches[i]
			if swatch.key == key then
				swatch:SetBackdropColor(r / 255, g / 255, b / 255, 1)
			elseif key == "border" then
				swatch:SetBackdropBorderColor(r / 255, g / 255, b / 255, 1)
			end
		end
	end
	scaleSlider:SetScript("OnValueChanged", writeScale)
	fadeSlider:SetScript("OnValueChanged", writeFade)
	opSlider:SetScript("OnValueChanged", writeOp)
	dpsSlider:SetScript("OnValueChanged", writeDps)
	dpsSlider:SetScript("OnEnter", function()
		showTip(this, "RIGHT", "DPS window", nil, {
			{ "How many seconds DPS looks back, from 5 to 120.", 1, 1, 1 },
			{ "It pauses while the run is paused.", 0.75, 0.75, 0.75 },
		})
	end)
	dpsSlider:SetScript("OnLeave", function()
		leaveTip()
	end)
	redSlider:SetScript("OnValueChanged", writeRgb)
	greenSlider:SetScript("OnValueChanged", writeRgb)
	blueSlider:SetScript("OnValueChanged", writeRgb)

	dpsAllHit:SetScript("OnClick", function()
		local saved = ensureLook()
		if saved.dpsAll then
			saved.dpsAll = nil
		else
			saved.dpsAll = true
		end
		syncSettings()
		refresh()
	end)
	dpsAllHit:SetScript("OnEnter", function()
		showTip(this, "RIGHT", "Since the start", nil, {
			{ "Uses the average for the whole run, instead of the window above.", 1, 1, 1 },
			{ "On Boss it is the whole fight. A reset starts that average over.", 0.75, 0.75, 0.75 },
		})
	end)
	dpsAllHit:SetScript("OnLeave", function()
		leaveTip()
	end)
	cdHit:SetScript("OnClick", function()
		local saved = ensureLook()
		if lookValue("cd") == false then
			saved.cd = true
			cdHit.mark:Show()
		else
			saved.cd = false
			cdHit.mark:Hide()
		end
		refresh()
	end)
	cdHit:SetScript("OnEnter", function()
		showTip(this, "RIGHT", "Cooldown bars", nil, {
			{ "The thin bar under a spell icon. Green means it is ready.", 1, 1, 1 },
		})
	end)
	cdHit:SetScript("OnLeave", function()
		leaveTip()
	end)
	lockHit:SetScript("OnClick", function()
		local cfg = config()
		cfg.locked = not cfg.locked
		if cfg.locked then
			lockHit.mark:Show()
		else
			lockHit.mark:Hide()
		end
	end)
	lockHit:SetScript("OnEnter", function()
		showTip(this, "RIGHT", "Lock windows", nil, {
			{ "Stops dragging the meter, its bubble, and extra windows.", 1, 1, 1 },
		})
	end)
	lockHit:SetScript("OnLeave", function()
		leaveTip()
	end)
	detailHit:SetScript("OnClick", function()
		local saved = ensureLook()
		if saved.detail then
			saved.detail = nil
		else
			saved.detail = true
		end
		syncSettings()
		refresh()
	end)
	detailHit:SetScript("OnEnter", function()
		showTip(this, "RIGHT", "Under the spell", nil, {
			{ "An arrow on a spell opens the talents grouped into it.", 1, 1, 1 },
			{ "Off leaves those talents as icons beside the name.", 0.75, 0.75, 0.75 },
		})
	end)
	detailHit:SetScript("OnLeave", function()
		leaveTip()
	end)
	wrapHit:SetScript("OnClick", function()
		local saved = ensureLook()
		if saved.wrap then
			saved.wrap = nil
		else
			saved.wrap = true
		end
		syncSettings()
		refresh()
	end)
	wrapHit:SetScript("OnEnter", function()
		showTip(this, "RIGHT", "Wrap names", nil, {
			{ "A long name uses a second line only when it does not fit beside the numbers.", 1, 1, 1 },
		})
	end)
	wrapHit:SetScript("OnLeave", function()
		leaveTip()
	end)
	local function bindCol(hit, key, title, line)
		hit:SetScript("OnClick", function()
			local saved = ensureLook()
			if saved[key] == false then
				saved[key] = nil
			else
				saved[key] = false
			end
			syncSettings()
			refresh()
		end)
		hit:SetScript("OnEnter", function()
			showTip(this, "RIGHT", title, nil, {
				{ line, 1, 1, 1 },
			})
		end)
		hit:SetScript("OnLeave", function()
			leaveTip()
		end)
	end
	bindCol(colKillHit, "colKill", "Kills", "Show or hide the kill count.")
	bindCol(colDmgHit, "colDmg", "Damage", "Show or hide the damage numbers.")
	bindCol(colShareHit, "colShare", "Share", "Show or hide each spell's part of the total.")
	bindCol(colDpsHit, "colDps", "DPS", "Show or hide the DPS numbers.")

	resetBtn:SetScript("OnClick", function()
		local cfg = config()
		local sx, sy, spoint, srel
		if cfg.look then
			sx, sy, spoint, srel = cfg.look.sx, cfg.look.sy, cfg.look.spoint, cfg.look.srel
		end
		cfg.look = nil
		cfg.locked = false
		if sx ~= nil and sy ~= nil then
			cfg.look = { sx = sx, sy = sy, spoint = spoint, srel = srel }
		end
		syncSettings()
		applyLook(true)
		fitWindows()
		refresh()
		say("Settings reset. Numbers and window position are unchanged.")
	end)
	resetBtn:SetScript("OnEnter", function()
		resetText:SetTextColor(1, 0.95, 0.75)
		resetBtn:SetBackdropBorderColor(1, 0.86, 0.45, 1)
		showTip(this, "RIGHT", "Reset settings", nil, {
			{ "Puts scale, the DPS window, columns, colors, cooldown bars, and the lock back.", 1, 1, 1 },
			{ "Numbers and where the windows sit are kept.", 0.75, 0.75, 0.75 },
		})
	end)
	resetBtn:SetScript("OnLeave", function()
		resetText:SetTextColor(1, 0.86, 0.5)
		applyLook(true)
		leaveTip()
	end)

	syncSettings()
	applyLook(true)
	box:Hide()
end

local function toggleSettings()
	if not settings then
		buildSettings()
	end
	if settings:IsShown() then
		settings:Hide()
		return
	end
	local saved = config().look
	if saved and saved.sx ~= nil and saved.sy ~= nil then
		local pscale, parentLeft, parentBottom, parentTop = parentMetrics()
		local es = pscale
		if settings.GetEffectiveScale then
			es = settings:GetEffectiveScale() or pscale
		end
		local left, top
		if saved.srel == "TOPLEFT" then
			left = parentLeft + saved.sx * es
			top = parentTop + saved.sy * es
		else
			left = parentLeft + saved.sx * es
			top = parentBottom + saved.sy * es
		end
		placeAtPixels(settings, left, top)
	else
		parkBeside(settings, frame)
	end
	if settings.sync then
		settings.sync()
	end
	settings.needNudge = true
	settings:Show()
end

local function buildMainChrome()
	frame = CreateFrame("Frame", "AZSSpellMeterFrame", UIParent)
	local cfg = config()
	local h = cfg.height or (K.HEADER + K.BOTTOM + 8 * K.ROW_H)
	if not cfg.headerGrow then
		if cfg.height then
			h = cfg.height + K.MODE_H
		end
		cfg.headerGrow = 1
		cfg.height = h
	end
	if cfg.colGrow and not cfg.colTight then
		if cfg.height then
			h = h - 8
		end
		cfg.height = h
	end
	cfg.colGrow = 1
	cfg.colTight = 1
	local minH = K.HEADER + K.BOTTOM + 3 * K.ROW_H
	if h < minH then
		h = minH
	end
	frame:SetWidth(cfg.width or K.WIDTH)
	frame:SetHeight(h)
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	if frame.SetResizable then
		frame:SetResizable(true)
	end
	if frame.SetMinResize then
		frame:SetMinResize(280, K.HEADER + K.BOTTOM + 3 * K.ROW_H)
	end
	if frame.SetMaxResize then
		frame:SetMaxResize(760, K.HEADER + K.BOTTOM + K.MAX_ROWS * K.ROW_H)
	end
	if frame.SetClampedToScreen then
		frame:SetClampedToScreen(true)
	end
	frame:SetBackdrop(roundBackdrop(12))
	frame:SetBackdropColor(0.05, 0.04, 0.03, 0.82)
	frame:SetBackdropBorderColor(0.78, 0.58, 0.22, 1)

	local openScale = lookScale()
	if frame.SetScale then
		frame:SetScale(openScale)
		frame.paintedScale = openScale
	end
	frame:SetPoint(cfg.point or "TOPLEFT", UIParent, cfg.rel or "TOPLEFT", cfg.x or 16, cfg.y or -160)

	local header = CreateFrame("Button", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -6)
	header:SetHeight(16)
	header:SetBackdrop(panelBackdrop())
	header:SetBackdropColor(0.34, 0.2, 0.06, 0.88)
	header:SetBackdropBorderColor(0.72, 0.5, 0.16, 0.7)
	frame.header = header
	local function startFrameDrag()
		if config().locked then
			return
		end
		dragging = true
		frame:StartMoving()
	end
	local function stopFrameDrag()
		dragging = false
		frame:StopMovingOrSizing()
		savePoint()
	end
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", startFrameDrag)
	header:SetScript("OnDragStop", stopFrameDrag)

	local brandBack = header:CreateTexture(nil, "ARTWORK")
	brandBack:SetTexture(K.SOLID)
	brandBack:SetVertexColor(0, 0, 0, 0.55)
	brandBack:SetWidth(14)
	brandBack:SetHeight(14)
	brandBack:SetPoint("LEFT", header, "LEFT", 2, 0)
	local brand = header:CreateTexture(nil, "OVERLAY")
	brand:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
	brand:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	brand:SetWidth(12)
	brand:SetHeight(12)
	brand:SetPoint("CENTER", brandBack, "CENTER", 0, 0)
	frame.brand = brand
	local brandText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	brandText:SetPoint("LEFT", brandBack, "RIGHT", 4, 0)
	brandText:SetJustifyH("LEFT")
	brandText:SetText("Spell Meter")
	face(brandText, 10)
	brandText:SetTextColor(1, 0.9, 0.62)
	frame.brandText = brandText

	local modes = CreateFrame("Frame", nil, frame)
	modes:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -23)
	modes:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -23)
	modes:SetHeight(K.MODE_H)
	frame.modeBtns = {}
	frame.modes = modes
	local modeSpec = {
		{ mode = "damage", text = "Damage", tip = "Damage dealt this run, and how many kills each spell landed.", tr = 1, tg = 0.9, tb = 0.62, br = 0.42, bg = 0.26, bb = 0.08, er = 0.9, eg = 0.66, eb = 0.22 },
		{ mode = "healing", text = "Healing", tip = "Healing this run. Overhealing is left out.", tr = 0.72, tg = 0.95, tb = 0.7, br = 0.14, bg = 0.32, bb = 0.16, er = 0.45, eg = 0.78, eb = 0.4 },
		{ mode = "boss", text = "Boss", tip = "Damage from the last boss fight. Bosses that are up together count as one fight.", tr = 1, tg = 0.72, tb = 0.42, br = 0.4, bg = 0.16, bb = 0.08, er = 0.9, eg = 0.45, eb = 0.16 },
		{ mode = "taken", text = "Taken", tip = "Damage you took, split by what hit you.", tr = 1, tg = 0.55, tb = 0.45, br = 0.38, bg = 0.12, bb = 0.1, er = 0.85, eg = 0.35, eb = 0.28 },
		{ mode = "party", text = "Party", tip = "Damage dealt by each hero in the party. Empty when you are not in one.", tr = 0.7, tg = 0.82, tb = 1, br = 0.14, bg = 0.2, bb = 0.38, er = 0.45, eg = 0.62, eb = 0.95 },
	}
	local msi
	for msi = 1, table.getn(modeSpec) do
		local spec = modeSpec[msi]
		local btn = CreateFrame("Button", nil, modes)
		btn:SetHeight(K.MODE_H)
		btn.mode = spec.mode
		btn.tip = spec.tip
		btn.tr, btn.tg, btn.tb = spec.tr, spec.tg, spec.tb
		btn.br, btn.bg, btn.bb = spec.br, spec.bg, spec.bb
		btn.er, btn.eg, btn.eb = spec.er, spec.eg, spec.eb
		btn:SetBackdrop(roundBackdrop(8))
		local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("CENTER", btn, "CENTER", 0, 0)
		label:SetText(spec.text)
		face(label, 9)
		btn.label = label
		if btn.RegisterForClicks then
			btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		end
		btn:SetScript("OnClick", function()
			if arg1 == "RightButton" then
				if popped[this.mode] then
					dock(this.mode)
				else
					detach(this.mode)
				end
				return
			end
			if popped[this.mode] then
				dock(this.mode)
				return
			end
			if config().view == this.mode then
				return
			end
			config().viewChosen = 1
			config().view = this.mode
			scroll = 0
			refresh()
		end)
		btn:SetScript("OnEnter", function()
			if config().view ~= this.mode and not popped[this.mode] then
				this:SetBackdropBorderColor(0.72, 0.56, 0.24, 1)
			end
			local extra = "Right-click to open it in its own window."
			if popped[this.mode] then
				extra = "Click to bring it back into this window."
			end
			showTip(this, "RIGHT", this.label:GetText(), nil, {
				{ this.tip, 1, 1, 1 },
				{ extra, 0.75, 0.75, 0.75 },
			})
		end)
		btn:SetScript("OnLeave", function()
			leaveTip()
			if popped[this.mode] then
				this:SetBackdropBorderColor(0.4, 0.32, 0.16, 0.7)
			elseif config().view == this.mode then
				this:SetBackdropBorderColor(this.er, this.eg, this.eb, 1)
			else
				this:SetBackdropBorderColor(0.32, 0.22, 0.1, 1)
			end
		end)
		frame.modeBtns[msi] = btn
	end

	local minBtn = CreateFrame("Button", nil, header)
	minBtn:SetPoint("RIGHT", header, "RIGHT", -3, 0)
	minBtn:SetWidth(14)
	minBtn:SetHeight(14)
	minBtn:SetBackdrop(roundBackdrop(8))
	minBtn:SetBackdropColor(0.16, 0.1, 0.03, 0.85)
	minBtn:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
	paintMinus(minBtn)
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
		applyLook(true)
		leaveTip()
	end)
	frame.minBtn = minBtn

	local setBtn = CreateFrame("Button", nil, header)
	setBtn:SetPoint("RIGHT", minBtn, "LEFT", -4, 0)
	setBtn:SetWidth(14)
	setBtn:SetHeight(14)
	setBtn:SetBackdrop(roundBackdrop(8))
	setBtn:SetBackdropColor(0.16, 0.1, 0.03, 0.85)
	setBtn:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
	local gear = setBtn:CreateTexture(nil, "OVERLAY")
	gear:SetTexture("Interface\\Icons\\INV_Misc_Gear_08")
	gear:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	gear:SetWidth(10)
	gear:SetHeight(10)
	gear:SetPoint("CENTER", setBtn, "CENTER", 0, 0)
	setBtn:SetScript("OnClick", function()
		toggleSettings()
	end)
	setBtn:SetScript("OnEnter", function()
		setBtn:SetBackdropBorderColor(1, 0.86, 0.45, 1)
		showTip(this, "RIGHT", "Settings", nil, {
			{ "Scale, DPS window, columns, colors, cooldown bars, and lock.", 1, 1, 1 },
		})
	end)
	setBtn:SetScript("OnLeave", function()
		applyLook(true)
		leaveTip()
	end)
	frame.setBtn = setBtn

	local resetBtn = CreateFrame("Button", nil, header)
	resetBtn:SetPoint("RIGHT", setBtn, "LEFT", -4, 0)
	resetBtn:SetHeight(14)
	resetBtn:SetWidth(42)
	resetBtn:SetBackdrop(roundBackdrop(8))
	resetBtn:SetBackdropColor(0.16, 0.1, 0.03, 0.85)
	resetBtn:SetBackdropBorderColor(0.72, 0.5, 0.16, 1)
	local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	resetText:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
	resetText:SetText("Reset")
	face(resetText, 9)
	resetText:SetTextColor(1, 0.86, 0.5)
	resetBtn:SetScript("OnClick", function()
		windowReset(false)
		refresh()
		local mode = viewMode()
		if mode == "healing" then
			say("Reset. Healing starts over in this window. The built-in meter is unchanged.")
		elseif mode == "boss" then
			say("Reset. Boss damage starts over in this window. The built-in meter is unchanged.")
		elseif mode == "taken" then
			say("Reset. Damage taken starts over in this window.")
		elseif mode == "party" then
			say("Reset. Party damage starts over in this window.")
		else
			say("Reset. Damage and kills start over in this window. The built-in meter is unchanged.")
		end
	end)
	resetBtn:SetScript("OnEnter", function()
		resetText:SetTextColor(1, 0.95, 0.7)
		resetBtn:SetBackdropBorderColor(1, 0.86, 0.45, 1)
		showHeaderTip("reset", viewMode())
	end)
	resetBtn:SetScript("OnLeave", function()
		resetText:SetTextColor(1, 0.86, 0.5)
		applyLook(true)
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
	dpsBtn:RegisterForDrag("LeftButton")
	dpsBtn:SetScript("OnDragStart", startFrameDrag)
	dpsBtn:SetScript("OnDragStop", stopFrameDrag)
	dpsBtn:SetScript("OnEnter", function()
		showHeaderTip("dps", viewMode())
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
	if frame.brandText then
		frame.brandText:SetPoint("RIGHT", totalBtn, "LEFT", -8, 0)
	end
	totalBtn:RegisterForDrag("LeftButton")
	totalBtn:SetScript("OnDragStart", startFrameDrag)
	totalBtn:SetScript("OnDragStop", stopFrameDrag)
	totalBtn:SetScript("OnEnter", function()
		showHeaderTip("total", viewMode())
	end)
	totalBtn:SetScript("OnLeave", function()
		leaveTip()
	end)

	local cols = CreateFrame("Frame", nil, frame)
	cols:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(K.HEADER - K.COL_H))
	cols:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -(K.HEADER - K.COL_H))
	cols:SetHeight(12)
	frame.cols = cols
	local countText = cols:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("LEFT", cols, "LEFT", 2, 0)
	countText:SetJustifyH("LEFT")
	countText:SetText("")
	face(countText, 9)
	countText:SetTextColor(0.55, 0.5, 0.4)
	frame.countText = countText
	local baseLevel = frame:GetFrameLevel() or 1
	cols:SetFrameLevel(baseLevel + 6)
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
			local amountWord, rateWord = meterWords()
			local title = amountWord
			local lines = {
				{ "Click to sort by this column.", 1, 1, 1 },
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
				title = rateWord
				lines = {
					{ "This spell's rate. Click to sort.", 1, 1, 1 },
					{ "Click again to reverse the order.", 0.75, 0.75, 0.75 },
				}
			elseif picked == "share" then
				title = "Share"
				lines = {
					{ "This spell's part of the total. Click to sort.", 1, 1, 1 },
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

	local dpsCol = makeSortButton("dps", "DPS", K.COL_DPS, "RIGHT")
	dpsCol:SetPoint("RIGHT", cols, "RIGHT", -2, 0)
	local shareCol = makeSortButton("share", "%", K.COL_PCT, "RIGHT")
	shareCol:SetPoint("RIGHT", dpsCol, "LEFT", -6, 0)
	local dmgCol = makeSortButton("damage", "Damage", K.COL_DMG, "RIGHT")
	dmgCol:SetPoint("RIGHT", shareCol, "LEFT", -6, 0)
	local killCol = makeSortButton("kills", "Kills", K.COL_KILL, "RIGHT")
	killCol:SetPoint("RIGHT", dmgCol, "LEFT", -6, 0)
	frame.dpsCol = dpsCol
	frame.shareCol = shareCol
	frame.dmgCol = dmgCol
	frame.killCol = killCol
end

local function buildMainList()
	local cfg = config()
	local header = frame.header
	local minBtn = frame.minBtn
	local resetBtn = frame.resetBtn
	local dpsBtn = frame.dpsBtn
	local totalBtn = frame.totalBtn
	local cols = frame.cols
	local modes = frame.modes
	local scrollFrame = CreateFrame("ScrollFrame", "AZSSpellMeterScroll", frame)
	scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -K.HEADER)
	scrollFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -K.HEADER)
	scrollFrame:SetHeight(8 * K.ROW_H)
	scrollFrame:EnableMouseWheel(true)
	local scrollChild = CreateFrame("Frame", "AZSSpellMeterScrollChild", scrollFrame)
	scrollChild:SetWidth((cfg.width or K.WIDTH) - 16)
	scrollChild:SetHeight((K.MAX_ROWS) * K.ROW_H)
	scrollFrame:SetScrollChild(scrollChild)
	frame.scroll = scrollFrame
	frame.scrollChild = scrollChild

	local i
	for i = 1, K.ROW_POOL do
		rows[i] = createRow(scrollChild, i)
		rows[i]:SetWidth((cfg.width or K.WIDTH) - 16)
	end

	local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(K.HEADER + 6))
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
		mark:SetTexture(K.SOLID)
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
	grip:SetScript("OnMouseDown", onMainGripDown)
	grip:SetScript("OnMouseUp", finishMainSize)

	local tip = CreateFrame("Frame", "AZSSpellMeterTip", UIParent)
	tip:SetFrameStrata("TOOLTIP")
	tip:SetWidth(160)
	tip:SetHeight(40)
	if tip.SetClampedToScreen then
		tip:SetClampedToScreen(true)
	end
	tip:SetBackdrop(roundBackdrop(12))
	tip:SetBackdropColor(0.05, 0.04, 0.03, 0.9)
	tip:SetBackdropBorderColor(0.78, 0.58, 0.22, 1)
	local iconBack = tip:CreateTexture(nil, "ARTWORK")
	iconBack:SetTexture(K.SOLID)
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
	for li = 1, 12 do
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

	frame:SetScript("OnMouseWheel", onMainWheel)
	header:EnableMouseWheel(true)
	header:SetScript("OnMouseWheel", onMainWheel)
	grip:EnableMouseWheel(true)
	grip:SetScript("OnMouseWheel", onMainWheel)
	for i = 1, K.ROW_POOL do
		rows[i]:EnableMouseWheel(true)
		rows[i]:SetScript("OnMouseWheel", onMainWheel)
		local pi
		for pi = 1, 3 do
			rows[i].procBtns[pi]:SetScript("OnMouseWheel", onMainWheel)
		end
		if rows[i].arrow then
			rows[i].arrow:EnableMouseWheel(true)
			rows[i].arrow:SetScript("OnMouseWheel", onMainWheel)
		end
	end
	scrollFrame:SetScript("OnMouseWheel", onMainWheel)
	cols:EnableMouseWheel(true)
	cols:SetScript("OnMouseWheel", onMainWheel)
	for i = 1, table.getn(frame.sortBtns) do
		frame.sortBtns[i]:EnableMouseWheel(true)
		frame.sortBtns[i]:SetScript("OnMouseWheel", onMainWheel)
	end
	totalBtn:EnableMouseWheel(true)
	totalBtn:SetScript("OnMouseWheel", onMainWheel)
	dpsBtn:EnableMouseWheel(true)
	dpsBtn:SetScript("OnMouseWheel", onMainWheel)
	modes:EnableMouseWheel(true)
	modes:SetScript("OnMouseWheel", onMainWheel)
	local mwi
	for mwi = 1, table.getn(frame.modeBtns) do
		frame.modeBtns[mwi]:EnableMouseWheel(true)
		frame.modeBtns[mwi]:SetScript("OnMouseWheel", onMainWheel)
	end
	resetBtn:EnableMouseWheel(true)
	resetBtn:SetScript("OnMouseWheel", onMainWheel)
	minBtn:EnableMouseWheel(true)
	minBtn:SetScript("OnMouseWheel", onMainWheel)
	frame:SetScript("OnUpdate", onMainUpdate)

	bubble = CreateFrame("Button", "AZSSpellMeterBubble", UIParent)
	bubble:SetFrameStrata("HIGH")
	bubble:SetWidth(48)
	bubble:SetHeight(22)
	bubble:SetMovable(true)
	bubble:EnableMouse(true)
	bubble:EnableMouse(true)
	bubble:RegisterForClicks("LeftButtonUp")
	if bubble.SetClampedToScreen then
		bubble:SetClampedToScreen(true)
	end
	bubble:SetBackdrop(roundBackdrop(12))
	bubble:SetBackdropColor(0.28, 0.16, 0.05, 0.9)
	bubble:SetBackdropBorderColor(0.85, 0.62, 0.2, 1)
	bubble:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	local bubbleText = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bubbleText:SetPoint("CENTER", bubble, "CENTER", 0, 0)
	bubbleText:SetJustifyH("CENTER")
	bubbleText:SetText("0")
	face(bubbleText, 11)
	bubbleText:SetTextColor(1, 0.9, 0.55)
	frame.bubbleText = bubbleText
	bubble.moving = false
	bubble:RegisterForDrag("LeftButton")
	bubble:SetScript("OnDragStart", function()
		if config().locked then
			return
		end
		bubble.moving = true
		bubble:StartMoving()
	end)
	bubble:SetScript("OnDragStop", function()
		bubble:StopMovingOrSizing()
	end)
	if bubble.RegisterForClicks then
		bubble:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	end
	bubble:SetScript("OnClick", function()
		if arg1 == "RightButton" then
			toggleSettings()
			return
		end
		if bubble.moving then
			bubble.moving = false
			return
		end
		config().mini = false
		applyShown()
		refresh()
	end)
	bubble:SetScript("OnEnter", function()
		bubble:SetBackdropBorderColor(1, 0.86, 0.45, 1)
		showTip(this, "RIGHT", "Spell meter", nil, {
			{ "Click to open the window. Right-click for settings.", 1, 1, 1 },
		})
	end)
	bubble:SetScript("OnLeave", function()
		applyLook(true)
		leaveTip()
	end)
	bubble:SetScript("OnUpdate", onBubbleUpdate)
	bubble:Hide()

	frame.rows = rows
	frame.headH = K.HEADER
	applyLook(true)
	restorePops()
	applyShown()
	refresh()
	if config().shown == false and not toldHidden then
		toldHidden = true
		say("The window is hidden. Type /azsm to show it.")
	end
end

local function createUI()
	buildMainChrome()
	buildMainList()
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
	if not frame and event == "PLAYER_ENTERING_WORLD" then
		loadState()
		createUI()
		widenCombatLog()
		queueScan()
	end
	if not state then
		return
	end
	noteItemText(arg1)
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
	elseif event == "SPELLS_CHANGED" or event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "BAG_UPDATE" then
		queueScan()
	elseif event == "UNIT_INVENTORY_CHANGED" then
		if arg1 == "player" then
			queueScan()
		end
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
	driver:RegisterEvent("BAG_UPDATE")
	driver:RegisterEvent("UNIT_INVENTORY_CHANGED")
	driver:RegisterEvent("CHAT_MSG_LOOT")
driver:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
driver:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
driver:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF")
driver:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS")
driver:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
driver:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
driver:RegisterEvent("CHAT_MSG_SPELL_PET_DAMAGE")
driver:RegisterEvent("CHAT_MSG_COMBAT_PET_HITS")
driver:SetScript("OnEvent", onEvent)
driver:SetScript("OnUpdate", function()
	if (frame and frame:IsShown()) or (bubble and bubble:IsShown()) then
		return
	end
	if not anyMeterShown() then
		return
	end
	driver.tick = (driver.tick or 0) + (arg1 or 0)
	if driver.tick < 0.2 then
		return
	end
	driver.tick = 0
	refresh()
end)

local function toggleLock()
	local cfg = config()
	cfg.locked = not cfg.locked
	if settings and settings.lockMark then
		if cfg.locked then
			settings.lockMark:Show()
		else
			settings.lockMark:Hide()
		end
	end
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
		if not anyMeterShown() then
			restoreStockMeter()
		end
	else
		cfg.shown = true
		cfg.mini = false
		applyShown()
		refresh()
	end
end

local function loadTest()
	resetData()
	config().view = "damage"
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
	if msg == "resetpos" then
		placeDefault()
	elseif msg == "" or msg == "toggle" or msg == "show" then
		if msg ~= "show" and frame:IsShown() and clampIntoView(frame, 120, 20) then
			savePoint()
			noteClamped()
		elseif msg ~= "show" and bubble and bubble:IsShown() and clampIntoView(bubble, 36, 18) then
			noteClamped()
		elseif msg == "show" then
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
		if not anyMeterShown() then
			restoreStockMeter()
		end
	elseif msg == "reset" then
		windowReset(true)
		refresh()
		local mode = viewMode()
		if mode == "healing" then
			say("Reset. Healing starts over in this window. The built-in meter is unchanged.")
		elseif mode == "boss" then
			say("Reset. Boss damage starts over in this window. The built-in meter is unchanged.")
		elseif mode == "taken" then
			say("Reset. Damage taken starts over in this window.")
		elseif mode == "party" then
			say("Reset. Party damage starts over in this window.")
		else
			say("Reset. Damage and kills start over in this window. The built-in meter is unchanged.")
		end
	elseif msg == "lock" then
		toggleLock()
	elseif msg == "settings" or msg == "config" then
		toggleSettings()
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
		say("/azsm show, hide, reset, resetpos, lock, settings, test, debug")
	end
end
