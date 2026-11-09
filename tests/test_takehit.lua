local function hit(id, key, amount, crit, target)
	return {
		kind = "damage",
		sourceKind = "player",
		meterSourceKey = key,
		meterSource = "Source " .. key,
		sourceId = "p1",
		amount = amount,
		critical = crit,
		eventId = id,
		targetName = target,
	}
end

local function seenSize()
	local L = AZSSpellMeter_Ledger
	local n = 0
	local k
	for k in pairs(L.HitSeen or {}) do
		n = n + 1
	end
	for k in pairs(L.HitSeenOld or {}) do
		n = n + 1
	end
	return n
end

return {
	{ "counts stay the same for a fixed sequence", function()
		dofile("AZSSpellMeter/Ledger.lua")
		local L = AZSSpellMeter_Ledger
		L.TakeHit(hit(1, "fireball", 100, false, "|cffff0000Zombie|r. "))
		L.TakeHit(hit(2, "fireball", 300, true, "Zombie"))
		L.BossUp = true
		L.TakeHit(hit(3, "frostbolt", 50, true, nil))
		L.BossUp = nil
		local foe = hit(4, "fireball", 999, true, "Zombie")
		foe.sourceKind = "enemy"
		expectEq(L.TakeHit(foe), false, "enemy hit")
		expectEq(L.TakeHit(hit(5, "", 10, false, "Zombie")), false, "empty key")
		L.TakeHit(hit(2, "fireball", 300, true, "Zombie"))
		local fb = L.Hits.fireball
		expectEq(fb.hits, 2, "fireball hits")
		expectEq(fb.crits, 1, "fireball crits")
		expectEq(fb.best, 300, "fireball best")
		expectEq(fb.spell, "Source fireball", "fireball spell")
		expectEq(fb.who, "p1", "fireball who")
		expectEq(L.Hits.frostbolt.hits, 1, "frostbolt hits")
		expectEq(L.Hits.frostbolt.best, 50, "frostbolt best")
		expectEq(L.BossHits.frostbolt.crits, 1, "boss frostbolt crits")
		expectEq(L.BossHits.fireball, nil, "boss fireball")
		expectEq(L.BestHit, 300, "BestHit")
		expectEq(L.BossBest, 50, "BossBest")
		expectEq(L.Blows.Zombie, "fireball", "blow")
	end },
	{ "the same eventId counts once", function()
		dofile("AZSSpellMeter/Ledger.lua")
		local L = AZSSpellMeter_Ledger
		L.TakeHit(hit(7, "fireball", 100, false, nil))
		L.TakeHit(hit(7, "fireball", 100, false, nil))
		expectEq(L.Hits.fireball.hits, 1, "hits")
	end },
	{ "HitSeen stays bounded", function()
		dofile("AZSSpellMeter/Ledger.lua")
		local L = AZSSpellMeter_Ledger
		local i
		for i = 1, 20000 do
			L.TakeHit(hit(i, "fireball", 1, false, nil))
		end
		expect(seenSize() <= 8192, "HitSeen holds " .. seenSize())
		L.TakeHit(hit(20000, "fireball", 1, false, nil))
		expectEq(L.Hits.fireball.hits, 20000, "recent duplicate")
	end },
	{ "a target name is cleaned once and cached", function()
		dofile("AZSSpellMeter/Ledger.lua")
		local L = AZSSpellMeter_Ledger
		local real = string.gsub
		local calls = 0
		string.gsub = function(a, b, c, d)
			calls = calls + 1
			return real(a, b, c, d)
		end
		L.TakeHit(hit(1, "fireball", 1, false, "|cffff0000Zombie|r. "))
		local first = calls
		L.TakeHit(hit(2, "fireball", 1, false, "|cffff0000Zombie|r. "))
		string.gsub = real
		expectEq(L.Blows.Zombie, "fireball", "blow")
		expectEq(calls, first, "gsub calls on the second hit")
	end },
	{ "KeepHits runs once per ReadHits", function()
		dofile("AZSSpellMeter/Ledger.lua")
		local L = AZSSpellMeter_Ledger
		local list = {}
		local i
		for i = 1, 10 do
			list[i] = hit(i, "fireball", 1, false, "Zombie")
		end
		function AZS_GetCombatTextEvents()
			return { apiVersion = 1, events = list, cursor = "c1", hasMore = false }
		end
		local key = stub.count("AZSSpellMeter_Ledger", "KeepHits")
		L.ReadHits()
		expectEq(stub.counts[key], 1, "KeepHits calls")
	end },
}
