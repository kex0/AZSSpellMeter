-- The game's meter ledger (AZS_GetMeterSnapshot). Amounts, icons, ranks, and
-- which actor cast a spell come from here. Hits, crits, and kills do not.
-- Loaded before AZSSpellMeter.lua so that file stays under Lua 5.0's local limit.

AZSSpellMeter_Ledger = {}

AZSSpellMeter_Ledger.OwnName = {
	["Flurry"] = true,
	["Shockwave"] = true,
	["Mutilate"] = true,
	["Blade Flurry"] = true,
	["Conflagrate"] = true,
	["Sweeping Strikes"] = true,
}

AZSSpellMeter_Ledger.OwnKey = {
	flurry = true,
	shockwave = true,
	mutilate = true,
	blade_flurry = true,
	conflagrate = true,
	sweeping_strikes = true,
}

AZSSpellMeter_Ledger.Warlock = {
	imp = true,
	felhunter = true,
	voidwalker = true,
	succubus = true,
	felguard = true,
	infernal = true,
	inferno = true,
	doomguard = true,
	pit_lord = true,
	pitlord = true,
	dread_lord = true,
	dreadlord = true,
}

function AZSSpellMeter_Ledger.Compact(name)
	local s = string.lower(name or "")
	s = string.gsub(s, "[%s_%-']", "")
	return s
end

function AZSSpellMeter_Ledger.Ready()
	if not AZS_GetMeterContext or not AZS_GetMeterSnapshot then
		return false
	end
	return true
end

function AZSSpellMeter_Ledger.Context()
	if not AZSSpellMeter_Ledger.Ready() then
		return nil
	end
	local ctx = AZS_GetMeterContext()
	if not ctx or not ctx.runId or ctx.runId == "" then
		return nil
	end
	return ctx
end

function AZSSpellMeter_Ledger.InParty()
	local ctx = AZSSpellMeter_Ledger.Context()
	if not ctx then
		return nil
	end
	if ctx.partyState == "solo" then
		return false
	end
	if ctx.partyState and ctx.partyState ~= "" then
		return true
	end
	return nil
end

function AZSSpellMeter_Ledger.Window(window)
	local w = math.floor((tonumber(window) or 0) + 0.5)
	if w < 0 then
		w = 0
	end
	if w ~= 0 and w < 5 then
		w = 5
	end
	if w > 120 then
		w = 120
	end
	return w
end

function AZSSpellMeter_Ledger.IconOf(source)
	if source and source.icon and source.icon.status == "ready" and source.icon.path and source.icon.path ~= "" then
		return source.icon.path
	end
	return nil
end

function AZSSpellMeter_Ledger.PortraitKey(actor)
	if actor and actor.portrait and actor.portrait.status == "ready" and actor.portrait.portraitKey and actor.portrait.portraitKey ~= "" then
		return actor.portrait.portraitKey
	end
	return nil
end

function AZSSpellMeter_Ledger.ApplyPortrait(texture, portraitKey)
	if not texture or not portraitKey or portraitKey == "" or not AZS_SetMeterPortrait then
		return false
	end
	local ctx = AZSSpellMeter_Ledger.Context()
	if not ctx or not ctx.runId then
		return false
	end
	local ok = AZS_SetMeterPortrait(texture, ctx.runId, portraitKey)
	if ok then
		return true
	end
	return false
end

-- Which actor cast a spell this run. "Your Fireball" stays on the hero when the
-- hero has that spell, and moves to the one pet that has it when the hero does not.
function AZSSpellMeter_Ledger.Remember(spellName, actorName, hero)
	if not spellName or spellName == "" or not actorName or actorName == "" then
		return
	end
	local book = AZSSpellMeter_Ledger.SpellActors
	if not book then
		book = {}
		AZSSpellMeter_Ledger.SpellActors = book
	end
	local info = book[spellName]
	if not info then
		info = { hero = false, only = nil }
		book[spellName] = info
	end
	if hero then
		info.hero = true
		info.only = nil
		return
	end
	if info.hero then
		return
	end
	if not info.only then
		info.only = actorName
	elseif info.only ~= actorName then
		info.only = false
	end
end

function AZSSpellMeter_Ledger.HitOwner(spellName)
	if not spellName or spellName == "" then
		return nil
	end
	local book = AZSSpellMeter_Ledger.SpellActors
	local info = book and book[spellName]
	if not info then
		return nil
	end
	if info.hero or not info.only or info.only == "" then
		return nil
	end
	return info.only
end

function AZSSpellMeter_Ledger.OwnRow(source)
	if not source then
		return false
	end
	if source.name and AZSSpellMeter_Ledger.OwnName[source.name] then
		return true
	end
	if source.abilityKey and AZSSpellMeter_Ledger.OwnKey[source.abilityKey] then
		return true
	end
	return false
end

function AZSSpellMeter_Ledger.RateOf(stats)
	if not stats or not stats.displayRate then
		return 0, false
	end
	local rate = stats.displayRate
	if rate.status == "ready" and type(rate.value) == "number" then
		return rate.value, true
	end
	return 0, false
end

function AZSSpellMeter_Ledger.DrillPrefix(focus, healDone)
	if not focus or not focus.partyOwner or focus.partyOwner == "" then
		return nil
	end
	local view = focus.partyView or "damage"
	local prefix = focus.partyOwner .. ":" .. view .. ":"
	if view == "healing" then
		if healDone then
			prefix = prefix .. "cast:"
		else
			prefix = prefix .. "recv:"
		end
	end
	return prefix
end

function AZSSpellMeter_Ledger.NoteReset(saved, mode, focus, total, now, healDone)
	if not saved or mode ~= "party" then
		return nil
	end
	local prefix = AZSSpellMeter_Ledger.DrillPrefix(focus, healDone)
	if not prefix then
		return nil
	end
	saved.partyDrill = saved.partyDrill or {}
	saved.partyDrill[prefix] = { total = tonumber(total) or 0, time = now or 0 }
	return prefix
end

function AZSSpellMeter_Ledger.DrillTotal(saved, focus, healDone)
	if not saved or not saved.partyDrill then
		return nil
	end
	local prefix = AZSSpellMeter_Ledger.DrillPrefix(focus, healDone)
	if not prefix then
		return nil
	end
	return saved.partyDrill[prefix]
end

function AZSSpellMeter_Ledger.MergeDrill(prev, prefix, base)
	local drop = {}
	local key, value
	for key, value in pairs(prev) do
		if string.sub(key, 1, string.len(prefix)) == prefix then
			drop[table.getn(drop) + 1] = key
		end
	end
	local i
	for i = 1, table.getn(drop) do
		prev[drop[i]] = nil
	end
	for key, value in pairs(base) do
		prev[key] = value
	end
	return prev
end

function AZSSpellMeter_Ledger.RestoreRates(bucket)
	if not bucket then
		return
	end
	local name, row
	for name, row in pairs(bucket) do
		if row.ledgerDps then
			row.dps = row.ledgerDps
		end
	end
end

function AZSSpellMeter_Ledger.ApplyCombat(row, line, spells, toEnglish)
	if not row or not line or not spells then
		return
	end
	if line.rateReady then
		row.ledgerDps = tonumber(line.dps)
	end
	if line.heroRow then
		row.heroRow = true
	end
	if line.ownerId then
		row.ownerId = line.ownerId
	end
	if line.actorPack then
		row.actorPack = line.actorPack
	end
	if line.portraitKey then
		row.portraitKey = line.portraitKey
	end
	if line.rank and line.rank >= 1 then
		row.spellRank = line.rank
	elseif line.localSpell and not row.spellRank then
		local known = AZSSpellMeter_Ledger.SpellRank(row.name)
		if known and known >= 1 then
			row.spellRank = known
		end
	end
	if line.procs then
		row.procs = line.procs
	end
	local seen = {}
	local function add(key)
		if not key or key == "" or key == row.name or seen[key] then
			return
		end
		seen[key] = true
		local rec = spells[key]
		if not rec then
			return
		end
		row.hits = (row.hits or 0) + (rec.hits or 0)
		row.crits = (row.crits or 0) + (rec.crits or 0)
		row.kills = (row.kills or 0) + (rec.kills or 0)
		if (rec.best or 0) > (row.best or 0) then
			row.best = rec.best
			row.bestWho = key
		end
	end
	if toEnglish and row.name then
		add(toEnglish(row.name))
	end
	if line.localSpell then
		local want = AZSSpellMeter_Ledger.Compact(row.name)
		local book = AZSSpellMeter_Ledger.CombatBook
		if not book or book.spells ~= spells or book.rev ~= AZSSpellMeter_SpellRev then
			local map = {}
			local sk
			for sk in pairs(spells) do
				local key = AZSSpellMeter_Ledger.Compact(sk)
				local list = map[key]
				if not list then
					list = {}
					map[key] = list
				end
				list[table.getn(list) + 1] = sk
			end
			book = { spells = spells, rev = AZSSpellMeter_SpellRev, map = map }
			AZSSpellMeter_Ledger.CombatBook = book
		end
		local list = want ~= "" and book.map[want]
		if list then
			local si
			for si = 1, table.getn(list) do
				add(list[si])
			end
		end
	end
	if line.hitNames and not line.actorPack then
		local i
		for i = 1, table.getn(line.hitNames) do
			add(line.hitNames[i])
			if toEnglish then
				add(toEnglish(line.hitNames[i]))
			end
		end
	end
	if row.procs and row.name then
		local pi
		for pi = 1, table.getn(row.procs) do
			local proc = row.procs[pi]
			if proc and proc.name and proc.name ~= "" and not proc.summon then
				local rec = nil
				if line.actorPack then
					rec = spells[row.name .. "\031" .. proc.name]
					if not rec and toEnglish then
						rec = spells[row.name .. "\031" .. (toEnglish(proc.name) or proc.name)]
					end
				else
					rec = spells[proc.name]
					if not rec and toEnglish then
						rec = spells[toEnglish(proc.name)]
					end
				end
				if rec then
					proc.hits = rec.hits or 0
					proc.crits = rec.crits or 0
					proc.kills = rec.kills or 0
					if (rec.best or 0) > (proc.best or 0) then
						proc.best = rec.best
					end
				end
			end
		end
	end
end

local function bucketFind(bucket, name, toEnglish)
	if not bucket or not name then
		return nil, nil
	end
	if bucket[name] then
		return bucket[name], name
	end
	if not toEnglish then
		return nil, nil
	end
	local bn, br
	for bn, br in pairs(bucket) do
		if bn == name or toEnglish(bn) == name then
			return br, bn
		end
	end
	return nil, nil
end

local function absorbRow(parent, child, ontoParent)
	parent.damage = (parent.damage or 0) + (child.damage or 0)
	parent.dps = (parent.dps or 0) + (child.dps or 0)
	parent.kills = (parent.kills or 0) + (child.kills or 0)
	if ontoParent then
		parent.hits = (parent.hits or 0) + (child.hits or 0)
		parent.crits = (parent.crits or 0) + (child.crits or 0)
		if (child.best or 0) > (parent.best or 0) then
			parent.best = child.best
		end
	end
	parent.fromMeter = true
	if not parent.procs then
		parent.procs = {}
	end
	parent.procs[table.getn(parent.procs) + 1] = {
		name = child.name,
		damage = child.damage or 0,
		dps = child.dps or 0,
		hits = child.hits or 0,
		crits = child.crits or 0,
		kills = child.kills or 0,
		best = child.best or 0,
		icon = child.icon or child.iconPath,
		rank = child.spellRank or child.rank,
	}
end

function AZSSpellMeter_Ledger.RefreshSelected()
	local ctx = AZSSpellMeter_Ledger.Context()
	if not ctx or not ctx.localOwnerId or ctx.localOwnerId == "" or not AZS_GetMeterLoadout then
		AZSSpellMeter_Ledger.Selected = nil
		return
	end
	local stamp = (ctx.runId or "") .. ":" .. tostring(ctx.snapshotId or 0)
	if AZSSpellMeter_Ledger.SelectStamp == stamp then
		return
	end
	local load = AZS_GetMeterLoadout({ apiVersion = 1, runId = ctx.runId, ownerId = ctx.localOwnerId })
	if not load or not load.abilities or not load.sources then
		AZSSpellMeter_Ledger.Selected = nil
		return
	end
	local set = {}
	local i
	for i = 1, table.getn(load.abilities) do
		local ability = load.abilities[i]
		if ability and ability.selected and ability.sourceKey then
			local source = load.sources[ability.sourceKey]
			if source and source.name and source.name ~= "" then
				local rank = tonumber(ability.rank)
				if not rank or rank < 1 then
					rank = tonumber(source.rank)
				end
				if rank and rank >= 1 then
					set[source.name] = rank
				else
					set[source.name] = true
				end
			end
		end
	end
	AZSSpellMeter_Ledger.Selected = set
	AZSSpellMeter_Ledger.SelectStamp = stamp
end

function AZSSpellMeter_Ledger.SpellSelected(spellEn, toEnglish)
	local set = AZSSpellMeter_Ledger.Selected
	if not set or not spellEn then
		return nil
	end
	if set[spellEn] then
		return true
	end
	local name, on
	for name, on in pairs(set) do
		if on and (name == spellEn or (toEnglish and toEnglish(name) == spellEn)) then
			return true
		end
	end
	return false
end

function AZSSpellMeter_Ledger.SpellRank(name)
	local set = AZSSpellMeter_Ledger.Selected
	if not set or not name or name == "" then
		return nil
	end
	local direct = set[name]
	if type(direct) == "number" and direct >= 1 then
		return direct
	end
	local want = AZSSpellMeter_Ledger.Compact(name)
	if want == "" then
		return nil
	end
	local n, v
	for n, v in pairs(set) do
		if type(v) == "number" and v >= 1 and AZSSpellMeter_Ledger.Compact(n) == want then
			return v
		end
	end
	return nil
end

function AZSSpellMeter_Ledger.FoldUnselected(bucket, toEnglish, flat)
	AZSSpellMeter_Ledger.Moved = {}
	if flat or not bucket or not AZSSpellMeter_Ledger.Selected then
		return
	end
	local map = AZSSpellMeter_MinionSkill
	if not map then
		return
	end
	local spellEn, summonEn
	for spellEn, summonEn in pairs(map) do
		if AZSSpellMeter_Ledger.SpellSelected(spellEn, toEnglish) == false then
			local child, childKey = bucketFind(bucket, spellEn, toEnglish)
			if child and childKey and not child.actorPack and not child.heroRow then
				local parent = bucketFind(bucket, summonEn, toEnglish)
				if not parent then
					parent = {
						name = summonEn,
						damage = 0,
						dps = 0,
						hits = 0,
						crits = 0,
						kills = 0,
						best = 0,
						fromMeter = true,
						actorPack = "minion",
					}
					bucket[summonEn] = parent
				end
				absorbRow(parent, child, true)
				bucket[childKey] = nil
				AZSSpellMeter_Ledger.Moved[spellEn] = true
			end
		end
	end
end

function AZSSpellMeter_Ledger.FoldKnown(bucket, toEnglish, flat)
	if flat or not bucket then
		return
	end
	local map = AZSSpellMeter_KnownCast
	if not map then
		return
	end
	local childEn, parentEn
	for childEn, parentEn in pairs(map) do
		if not (AZSSpellMeter_Ledger.OwnName and AZSSpellMeter_Ledger.OwnName[childEn]) then
			local child, childKey = bucketFind(bucket, childEn, toEnglish)
			if child and childKey and not child.actorPack and not child.heroRow then
				local parent, parentKey = bucketFind(bucket, parentEn, toEnglish)
				if parentKey ~= childKey then
					if not parent then
						parent = {
							name = parentEn,
							damage = 0,
							dps = 0,
							hits = 0,
							crits = 0,
							kills = 0,
							best = 0,
							fromMeter = true,
						}
						bucket[parentEn] = parent
					end
					absorbRow(parent, child, false)
					bucket[childKey] = nil
				end
			end
		end
	end
end

function AZSSpellMeter_Ledger.SummonCount(name)
	if not name or name == "" or not AZS_GetSummons then
		return nil
	end
	local list = AZS_GetSummons()
	if not list then
		return nil
	end
	local low = string.lower(name)
	local spaced = string.gsub(low, " ", "_")
	local compact = string.gsub(low, " ", "")
	local n = 0
	local i
	for i = 1, table.getn(list) do
		local summon = list[i]
		local key = summon and summon.key
		local sname = summon and summon.name
		if sname == name or key == low or key == spaced or key == compact then
			n = n + 1
		end
	end
	if n > 1 then
		return n
	end
	return nil
end

function AZSSpellMeter_Ledger.CountLabel(name)
	local n = AZSSpellMeter_Ledger.SummonCount(name)
	if not n then
		return nil
	end
	return name .. " x" .. n
end

function AZSSpellMeter_Ledger.FoldShared(bucket, spells, toEnglish, shared)
	if not bucket or not spells or not shared then
		return
	end
	local summonEn, spellEn
	for summonEn, spellEn in pairs(shared) do
		local rec = spells[spellEn]
		local spellKey = spellEn
		if not rec and toEnglish then
			local sn, sr
			for sn, sr in pairs(spells) do
				if toEnglish(sn) == spellEn then
					rec = sr
					spellKey = sn
					break
				end
			end
		end
		local spellRow = bucket[spellKey]
		if not spellRow and toEnglish then
			local bn, br
			for bn, br in pairs(bucket) do
				if bn == spellEn or toEnglish(bn) == spellEn then
					spellRow = br
					spellKey = bn
					break
				end
			end
		end
		local spellDmg = spellRow and (spellRow.damage or 0) or 0
		local playerCasts = spellRow and spellRow.fromMeter and spellDmg > 0
		local already = AZSSpellMeter_Ledger.Moved and AZSSpellMeter_Ledger.Moved[spellEn]
		if not already and not playerCasts and rec and ((rec.hits or 0) > 0 or (rec.kills or 0) > 0 or (rec.crits or 0) > 0 or (rec.best or 0) > 0) then
			local sumRow = bucket[summonEn]
			if not sumRow then
				local bn, br
				for bn, br in pairs(bucket) do
					if bn == summonEn or (toEnglish and toEnglish(bn) == summonEn) then
						sumRow = br
						break
					end
				end
			end
			if sumRow then
				sumRow.hits = (sumRow.hits or 0) + (rec.hits or 0)
				sumRow.crits = (sumRow.crits or 0) + (rec.crits or 0)
				sumRow.kills = (sumRow.kills or 0) + (rec.kills or 0)
				if (rec.best or 0) > (sumRow.best or 0) then
					sumRow.best = rec.best
				end
				rec.minionFold = summonEn
			end
		end
	end
end

function AZSSpellMeter_Ledger.LoadoutLines(ownerId)
	local ctx = AZSSpellMeter_Ledger.Context()
	if not ctx or not ownerId or ownerId == "" or not AZS_GetMeterLoadout then
		return nil
	end
	local load = AZS_GetMeterLoadout({ apiVersion = 1, runId = ctx.runId, ownerId = ownerId })
	if not load or not load.sources then
		return nil
	end
	local lines = {}
	local function push(text)
		if not text or text == "" or table.getn(lines) >= 8 then
			return
		end
		lines[table.getn(lines) + 1] = { text, 0.7, 0.78, 0.95 }
	end
	local function sourceName(key)
		local source = key and load.sources[key]
		if source and source.name and source.name ~= "" then
			return source.name
		end
		return nil
	end
	if load.talents then
		local i
		for i = 1, table.getn(load.talents) do
			local talent = load.talents[i]
			local name = sourceName(talent.sourceKey)
			if name and talent.rank and talent.rank >= 1 then
				push(name .. " " .. math.floor(talent.rank + 0.5))
			end
		end
	end
	if load.abilities then
		local i
		for i = 1, table.getn(load.abilities) do
			local ability = load.abilities[i]
			if ability.selected or ability.learned then
				push(sourceName(ability.sourceKey))
			end
		end
	end
	if table.getn(lines) < 1 then
		return nil
	end
	return lines
end

local function ledgerBlank(rateReady)
	local lines = {}
	lines.fromLedger = true
	lines.rateReady = rateReady and true or false
	return lines
end

function AZSSpellMeter_Ledger.OriginKeys(snap, raw, source)
	if raw and raw.originSourceKeys and table.getn(raw.originSourceKeys) > 0 then
		return raw.originSourceKeys
	end
	local found = {}
	local seen = {}
	local contribs = snap and snap.contributions
	if contribs and raw then
		local ci
		for ci = 1, table.getn(contribs) do
			local c = contribs[ci]
			if c and c.nativeProc and c.sourceKey == raw.sourceKey and c.actorId == raw.actorId and c.originSourceKeys then
				local oi
				for oi = 1, table.getn(c.originSourceKeys) do
					local key = c.originSourceKeys[oi]
					if key and key ~= "" and not seen[key] then
						seen[key] = true
						found[table.getn(found) + 1] = key
					end
				end
			end
		end
	end
	if table.getn(found) > 0 then
		return found
	end
	if source and source.originSourceKeys and table.getn(source.originSourceKeys) > 0 then
		return source.originSourceKeys
	end
	return nil
end

-- A native proc is an icon on the spell the game says it came from. Several
-- origins share it. The button is written on the bucket row the window paints.
function AZSSpellMeter_Ledger.FoldProcs(bucket, pending, toEnglish, bucketOf, castMap, spells)
	if not bucket or not pending or not bucketOf then
		return
	end
	local i
	for i = 1, table.getn(pending) do
		local spell = pending[i]
		local present = {}
		local missing = {}
		local seen = {}
		local function consider(name, create)
			if not name or name == "" or name == spell.name then
				return
			end
			if toEnglish and toEnglish(name) == spell.name then
				return
			end
			local key = nil
			if bucket[name] then
				key = name
			else
				local bn
				for bn in pairs(bucket) do
					if bn == name or (toEnglish and (toEnglish(bn) == name or toEnglish(name) == toEnglish(bn))) then
						key = bn
						break
					end
				end
			end
			if key then
				if not seen[key] then
					seen[key] = true
					present[table.getn(present) + 1] = key
				end
			elseif create and not seen[name] then
				seen[name] = true
				missing[table.getn(missing) + 1] = name
			end
		end
		if spell.originNames then
			local o
			for o = 1, table.getn(spell.originNames) do
				consider(spell.originNames[o], true)
			end
		end
		if table.getn(present) < 1 and table.getn(missing) < 1 and castMap then
			local key = spell.name
			if toEnglish then
				key = toEnglish(spell.name) or spell.name
			end
			local casts = castMap[key] or castMap[spell.name]
			if casts and not casts.onlyProc then
				local c
				local count = table.getn(casts)
				for c = 1, count do
					consider(casts[c], count == 1)
				end
			end
		end
		local parents = present
		if table.getn(parents) < 1 then
			parents = missing
		end
		if table.getn(parents) > 1 and table.getn(present) < 1 then
			parents = { missing[1] }
		end
		if table.getn(parents) < 1 then
			local row = bucketOf(spell.name)
			row.damage = (row.damage or 0) + (spell.dmg or 0)
			row.dps = (row.dps or 0) + (spell.dps or 0)
			row.fromMeter = true
			if spell.icon and not row.iconPath then
				row.iconPath = spell.icon
			end
		else
			local pc = table.getn(parents)
			local usedDmg = 0
			local usedRate = 0
			local dmg = spell.dmg or 0
			local rate = spell.dps or 0
			local pi
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
				parent.fromMeter = true
				local parentName = parents[pi]
				local sameSpell = spell.name == parentName or (toEnglish and spell.name and parentName and toEnglish(spell.name) == toEnglish(parentName))
				if partDmg > 0 and not sameSpell then
					if not parent.procs then
						parent.procs = {}
					end
					local have = nil
					local ei = 1
					while parent.procs[ei] do
						local pname = parent.procs[ei].name
						if pname == spell.name or (toEnglish and toEnglish(pname) == toEnglish(spell.name)) then
							have = parent.procs[ei]
						end
						ei = ei + 1
					end
					if have then
						have.damage = (have.damage or 0) + partDmg
						have.dps = (have.dps or 0) + partRate
						have.proc = true
						if spell.icon and (not have.icon or have.icon == "") then
							have.icon = spell.icon
						end
					else
						local hits = 0
						local crits = 0
						if spells and pi == 1 then
							local rec = spells[spell.name]
							if not rec and toEnglish then
								rec = spells[toEnglish(spell.name)]
							end
							if rec then
								hits = rec.hits or 0
								crits = rec.crits or 0
							end
						end
						local slot = 1
						while parent.procs[slot] do
							slot = slot + 1
						end
						parent.procs[slot] = {
							name = spell.name,
							damage = partDmg,
							dps = partRate,
							icon = spell.icon,
							rank = spell.rank,
							hits = hits,
							crits = crits,
							kills = 0,
							proc = true,
						}
					end
				end
			end
		end
	end
end

function AZSSpellMeter_Ledger.RowAmount(row, owner, metricCode, encounterId, perspective)
	if not row or row.m ~= metricCode then
		return 0
	end
	local mine = true
	if perspective == "received" then
		mine = (row.ros == "k" and row.ro == owner)
	elseif perspective == "performed" then
		mine = (row.sos == "k" and row.so == owner)
	end
	if not mine then
		return 0
	end
	if encounterId then
		if row.encId ~= encounterId then
			return 0
		end
		return row.enc or 0
	end
	return row.amount or 0
end

-- The client already applied the server totals onto AZS_ML.st. Reading those
-- is the old meter's cost. AZS_GetMeterSnapshot builds a second copy of every
-- spell, which is what made one window hitch.
function AZSSpellMeter_Ledger.Live(metric, scope, ownerId, period, perspective)
	local st = AZS_ML and AZS_ML.st
	if not st or not st.rows or not st.sources or not st.actors then
		return nil
	end
	-- A self ledger only has your rows. Party totals arrive after the client asks for them.
	local needParty = false
	if scope == "party" and st.pstate ~= "solo" then
		needParty = true
	elseif scope == "owner" and ownerId and ownerId ~= "" and ownerId ~= st.owner then
		needParty = true
	end
	if needParty and not st.pinc then
		if AZS_MRequest then
			AZS_MRequest("party")
		end
		return nil
	end
	local owners = {}
	if scope == "party" then
		local heroes = st.heroes
		if heroes then
			local hi
			for hi = 1, table.getn(heroes) do
				owners[hi] = heroes[hi].id
			end
		end
	elseif scope == "owner" and ownerId and ownerId ~= "" then
		owners[1] = ownerId
	elseif st.owner and st.owner ~= "" then
		owners[1] = st.owner
	else
		return nil
	end
	local encounterId = nil
	if period == "encounter" then
		if not st.enc or not st.enc.id or st.enc.id == "" then
			return { rows = {}, sources = st.sources, actors = st.actors, total = 0 }
		end
		encounterId = st.enc.id
	end
	local metricCode = "d"
	if metric == "healing" then
		metricCode = "h"
	end
	local rows = {}
	local total = 0
	local oi
	for oi = 1, table.getn(owners) do
		local owner = owners[oi]
		local order = st.order and st.order[owner]
		local byId = st.rows[owner]
		if order and byId then
			if scope == "party" then
				local sum = 0
				local ri
				for ri = 1, table.getn(order) do
					sum = sum + AZSSpellMeter_Ledger.RowAmount(byId[order[ri]], owner, metricCode, encounterId, perspective)
				end
				if sum > 0 then
					rows[table.getn(rows) + 1] = { ownerId = owner, displayAmount = sum }
					total = total + sum
				end
			else
				local ri
				for ri = 1, table.getn(order) do
					local raw = byId[order[ri]]
					local amount = AZSSpellMeter_Ledger.RowAmount(raw, owner, metricCode, encounterId, perspective)
					if amount > 0 then
						rows[table.getn(rows) + 1] = {
							ownerId = owner,
							actorId = raw.actor,
							sourceKey = raw.source,
							displayAmount = amount,
							nativeProc = raw.proc and true or false,
							originSourceKeys = raw.origins,
						}
						total = total + amount
					end
				end
			end
		end
	end
	return { rows = rows, sources = st.sources, actors = st.actors, total = total }
end

function AZSSpellMeter_Ledger.Pull(mode, focus, window, healDone, flat)
	if not AZSSpellMeter_Ledger.Ready() then
		return nil
	end
	if mode ~= "damage" and mode ~= "healing" and mode ~= "boss" and mode ~= "party" then
		return nil
	end
	local ctx = AZSSpellMeter_Ledger.Context()
	if not ctx then
		return nil
	end
	if AZSSpellMeter_Ledger.SpellRun ~= ctx.runId then
		AZSSpellMeter_Ledger.SpellActors = {}
		AZSSpellMeter_Ledger.SpellRun = ctx.runId
		AZSSpellMeter_Ledger.SelectStamp = nil
	end
	AZSSpellMeter_Ledger.RefreshSelected()
	local metric = "damage"
	local scope = "self"
	local period = "run"
	local groupBy = "actor_source"
	local ownerId = nil
	local persp = nil
	local basePrefix = nil
	if mode == "healing" then
		metric = "healing"
		if healDone then
			persp = "performed"
			basePrefix = "cast:"
		else
			persp = "received"
			basePrefix = "recv:"
		end
	elseif mode == "boss" then
		period = "encounter"
	elseif mode == "party" then
		if focus and focus.partyOwner and focus.partyOwner ~= "" then
			scope = "owner"
			ownerId = focus.partyOwner
			local view = focus.partyView or "damage"
			basePrefix = AZSSpellMeter_Ledger.DrillPrefix(focus, healDone)
			if view == "healing" then
				metric = "healing"
				if healDone then
					persp = "performed"
				else
					persp = "received"
				end
			elseif view == "boss" then
				period = "encounter"
			end
		else
			scope = "party"
			groupBy = "owner"
			if focus and focus.partyList == "healing" then
				metric = "healing"
				persp = "performed"
			end
		end
	end
	local mine = scope == "self" or (ownerId and ctx.localOwnerId and ownerId == ctx.localOwnerId)
	local roster = mode == "party" and scope == "party"
	local asked = window
	if roster then
		-- The party list only needs amounts. A rate window makes the game
		-- walk every hero's spell history, which drops the frame rate.
		asked = 0
	end
	local query = {
		apiVersion = 1,
		runId = ctx.runId,
		metric = metric,
		scope = scope,
		period = period,
		groupBy = groupBy,
		windowSeconds = AZSSpellMeter_Ledger.Window(asked),
	}
	if scope == "owner" then
		query.ownerId = ownerId
	end
	if metric == "healing" then
		query.healingPerspective = persp or "received"
	end
	local cacheFor = 0.2
	if roster then
		cacheFor = 1
	end
	local now = 0
	if GetTime then
		now = GetTime()
	end
	local key = (ctx.runId or "") .. "|" .. metric .. "|" .. scope .. "|" .. (ownerId or "") .. "|" .. period .. "|" .. groupBy .. "|" .. tostring(query.windowSeconds) .. "|" .. (persp or "") .. "|" .. (flat and "1" or "0")
	local heldSnap = AZSSpellMeter_Ledger.Snap
	if heldSnap and heldSnap.key == key and (now - (heldSnap.at or 0)) < cacheFor then
		return heldSnap.lines, heldSnap.total, heldSnap.rate
	end
	local snap = nil
	local live = AZSSpellMeter_Ledger.Live(metric, scope, ownerId, period, persp)
	local totalRate, rateReady = 0, false
	local totalAmount = 0
	local sources, actors, rows
	if live then
		sources = live.sources or {}
		actors = live.actors or {}
		rows = live.rows or {}
		totalAmount = live.total or 0
	else
		local err
		snap, err = AZS_GetMeterSnapshot(query)
		if not snap then
			if err and (err.code == "NO_ENCOUNTER" or err.code == "NO_PARTY") then
				return ledgerBlank(true), 0, 0
			end
			return nil
		end
		if snap.complete ~= true or (snap.status ~= "ready" and snap.status ~= "ready_empty") then
			return nil
		end
		if asked ~= 0 then
			totalRate, rateReady = AZSSpellMeter_Ledger.RateOf(snap.totals)
		end
		if snap.totals and snap.totals.displayAmount then
			totalAmount = snap.totals.displayAmount
		end
		sources = snap.sources or {}
		actors = snap.actors or {}
		rows = snap.rows or {}
	end
	local lines = ledgerBlank(rateReady)
	if groupBy == "owner" then
		local i
		for i = 1, table.getn(rows) do
			local raw = rows[i]
			local actor = actors[raw.ownerId]
			local line = {
				name = actor and actor.name or raw.ownerId,
				dmg = raw.displayAmount or 0,
				dps = 0,
				proc = 0,
				fromLedger = true,
				heroRow = true,
				ownerId = raw.ownerId,
				class = actor and actor.classKey or nil,
				rateReady = false,
			}
			local rowRate, rowReady = 0, false
			if asked ~= 0 then
				rowRate, rowReady = AZSSpellMeter_Ledger.RateOf(raw)
			end
			if rowReady then
				line.dps = rowRate
				line.rateReady = true
			end
			lines[table.getn(lines) + 1] = line
		end
	else
		local named = {}
		local pets = {}
		local petOrder = {}
		local held = {}
		local i
		for i = 1, table.getn(rows) do
			local raw = rows[i]
			local actor = actors[raw.actorId]
			local source = sources[raw.sourceKey]
			local kind = actor and actor.kind
			local summonActor = false
			if actor and kind ~= "hero" and raw.actorId ~= raw.ownerId then
				if (actor.summonKey and actor.summonKey ~= "") or (actor.petFamilyKey and actor.petFamilyKey ~= "") or (actor.totemKey and actor.totemKey ~= "") or (actor.parentActorId and actor.parentActorId ~= "") then
					summonActor = true
				elseif kind == "pet" or kind == "minion" or kind == "guardian" or kind == "totem" or kind == "summon" then
					summonActor = true
				end
			end
			local hero = not summonActor
			local spellName = source and source.name or raw.sourceKey
			local rowRate, rowReady = 0, false
			if asked ~= 0 then
				rowRate, rowReady = AZSSpellMeter_Ledger.RateOf(raw)
			end
			local actorName = actor and actor.name or nil
			local nativeProc = (raw.nativeProc or raw.procClassification == "proc") and true or false
			if actorName then
				AZSSpellMeter_Ledger.Remember(spellName, actorName, hero)
			end
			if hero then
				held[table.getn(held) + 1] = {
					raw = raw,
					source = source,
					name = spellName,
					dmg = raw.displayAmount or 0,
					dps = rowReady and rowRate or 0,
					rateReady = rowReady,
					icon = AZSSpellMeter_Ledger.IconOf(source),
					rank = source and tonumber(source.rank) or nil,
					nativeProc = nativeProc,
					originKeys = nil,
				}
				held[table.getn(held)].originKeys = AZSSpellMeter_Ledger.OriginKeys(snap, raw, source)
			elseif flat and nativeProc then
				-- Each spell alone lists the proc itself. It is not an icon on the minion.
				held[table.getn(held) + 1] = {
					raw = raw,
					source = source,
					name = spellName,
					dmg = raw.displayAmount or 0,
					dps = rowReady and rowRate or 0,
					rateReady = rowReady,
					icon = AZSSpellMeter_Ledger.IconOf(source),
					rank = source and tonumber(source.rank) or nil,
					nativeProc = true,
					originKeys = AZSSpellMeter_Ledger.OriginKeys(snap, raw, source),
				}
			else
				local pet = pets[raw.actorId]
				if not pet then
					pet = {
						name = actor and actor.name or spellName,
						dmg = 0,
						dps = 0,
						proc = 0,
						fromLedger = true,
						actorPack = "pet",
						procs = {},
						hitNames = {},
						rateReady = true,
						ownerId = raw.ownerId,
					}
					if actor and actor.summonKey and AZSSpellMeter_Ledger.Warlock[actor.summonKey] then
						pet.actorPack = "minion"
					end
					pets[raw.actorId] = pet
					petOrder[table.getn(petOrder) + 1] = pet
				end
				pet.dmg = pet.dmg + (raw.displayAmount or 0)
				if rowReady then
					pet.dps = pet.dps + rowRate
				else
					pet.rateReady = false
					pet.dps = 0
				end
				pet.hitNames[table.getn(pet.hitNames) + 1] = actorName or spellName
				-- The ledger splits one spell into a proc row and a normal row.
				-- That is the same cast, so it stays one icon.
				local sourceKey = raw.sourceKey
				local icon = AZSSpellMeter_Ledger.IconOf(source)
				local haveBtn = nil
				local bp = 1
				while pet.procs[bp] do
					local btn = pet.procs[bp]
					local sameSpell = (sourceKey and btn.sourceKey == sourceKey) or btn.name == spellName
					local sameIcon = icon and icon ~= "" and btn.icon == icon
					if sameSpell or sameIcon then
						haveBtn = btn
						break
					end
					bp = bp + 1
				end
				if haveBtn then
					haveBtn.damage = (haveBtn.damage or 0) + (raw.displayAmount or 0)
					if rowReady then
						haveBtn.dps = (haveBtn.dps or 0) + rowRate
					end
					if not haveBtn.icon or haveBtn.icon == "" then
						haveBtn.icon = icon
					end
				else
					local slot = 1
					while pet.procs[slot] do
						slot = slot + 1
					end
					pet.procs[slot] = {
						name = spellName,
						damage = raw.displayAmount or 0,
						dps = rowReady and rowRate or 0,
						icon = icon,
						rank = source and tonumber(source.rank) or nil,
						sourceKey = sourceKey,
						hits = 0,
						crits = 0,
					}
				end
			end
		end
		local function emit(line)
			local have = named[line.name]
			if have then
				have.dmg = (have.dmg or 0) + (line.dmg or 0)
				if line.rateReady and have.rateReady then
					have.dps = (have.dps or 0) + (line.dps or 0)
				else
					have.rateReady = false
					have.dps = 0
				end
				if (not have.rank or have.rank < 1) and line.rank and line.rank >= 1 then
					have.rank = line.rank
				end
				if line.procs then
					if not have.procs then
						have.procs = {}
					end
					-- Several imps are one row. Each still reports Firebolt, so
					-- those copies add into the one icon for that spell.
					local p = 1
					while line.procs[p] do
						local add = line.procs[p]
						local found = nil
						local n = 1
						while have.procs[n] do
							local btn = have.procs[n]
							local same = false
							if add.sourceKey and btn.sourceKey and btn.sourceKey == add.sourceKey then
								same = true
							elseif add.name and btn.name and btn.name == add.name then
								same = true
							end
							if same then
								found = btn
								break
							end
							n = n + 1
						end
						if found then
							found.damage = (found.damage or 0) + (add.damage or 0)
							found.dps = (found.dps or 0) + (add.dps or 0)
							found.hits = (found.hits or 0) + (add.hits or 0)
							found.crits = (found.crits or 0) + (add.crits or 0)
							if (add.best or 0) > (found.best or 0) then
								found.best = add.best
							end
							if (not found.icon or found.icon == "") and add.icon and add.icon ~= "" then
								found.icon = add.icon
							end
						else
							local slot = 1
							while have.procs[slot] do
								slot = slot + 1
							end
							have.procs[slot] = add
						end
						p = p + 1
					end
				end
				return
			end
			named[line.name] = line
			lines[table.getn(lines) + 1] = line
		end
		local function spellLine(spell)
			return {
				name = spell.name,
				dmg = spell.dmg,
				dps = spell.dps,
				proc = 0,
				icon = spell.icon,
				rank = spell.rank,
				fromLedger = true,
				rateReady = spell.rateReady,
				hitNames = { spell.name },
				localSpell = mine,
				procs = spell.procs,
			}
		end
		lines.pendingProcs = {}
		for i = 1, table.getn(held) do
			local spell = held[i]
			if (not flat) and spell.nativeProc then
				local names = {}
				local seen = {}
				if spell.originKeys then
					local o
					for o = 1, table.getn(spell.originKeys) do
						local origin = sources[spell.originKeys[o]]
						local oname = origin and origin.name
						if oname and oname ~= "" and not seen[oname] then
							seen[oname] = true
							names[table.getn(names) + 1] = oname
						end
					end
				end
				local n = table.getn(lines.pendingProcs) + 1
				lines.pendingProcs[n] = {
					name = spell.name,
					dmg = spell.dmg,
					dps = spell.dps,
					icon = spell.icon,
					rank = spell.rank,
					rateReady = spell.rateReady,
					originNames = names,
				}
			else
				emit(spellLine(spell))
			end
		end
		for i = 1, table.getn(petOrder) do
			local pet = petOrder[i]
			if not pet.rateReady then
				pet.dps = 0
			end
			emit(pet)
		end
	end
	if basePrefix then
		local i
		for i = 1, table.getn(lines) do
			lines[i].baseKey = basePrefix .. (lines[i].name or "")
		end
	end
	if not rateReady then
		lines.rateReady = false
	end
	AZSSpellMeter_Ledger.Snap = { key = key, at = now, lines = lines, total = totalAmount, rate = totalRate }
	return lines, totalAmount, totalRate
end
