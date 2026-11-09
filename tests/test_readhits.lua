local queue = {}
local reads = 0

local function setup()
	queue = {}
	reads = 0
	function AZS_GetCombatTextEvents()
		reads = reads + 1
		local events = queue
		queue = {}
		return { apiVersion = 1, events = events, cursor = "c" .. reads, hasMore = false }
	end
	stub.load()
end

local function hit(id, key, amount, crit, target)
	return {
		kind = "damage",
		sourceKind = "player",
		meterSourceKey = key,
		amount = amount,
		critical = crit,
		eventId = id,
		targetName = target,
	}
end

return {
	{ "combat text is read at most every 0.05 s", function()
		setup()
		reads = 0
		local i
		for i = 1, 60 do
			stub.tick(1 / 144)
		end
		expect(reads <= 9, "reads: " .. reads)
	end },
	{ "a death reads the pending hit first", function()
		setup()
		local L = AZSSpellMeter_Ledger
		L.HitLive = true
		L.Blows = { Zombie = "frostbolt" }
		L.Hits = { frostbolt = { hits = 1, crits = 0, kills = 0, best = 0 } }
		queue = { hit(1, "fireball", 100, false, "Zombie") }
		stub.fire("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Zombie dies.")
		expectEq(L.Hits.fireball and L.Hits.fireball.kills, 1, "fireball kills")
		expectEq(L.Hits.frostbolt.kills, 0, "frostbolt kills")
	end },
	{ "the biggest hit still reaches the meter", function()
		setup()
		queue = { hit(1, "fireball", 5000, true, "Zombie") }
		stub.tick(0.06)
		-- state is local to the addon, so read the Ledger value the driver
		-- copies into state.best.
		expectEq(AZSSpellMeter_Ledger.BestHit, 5000, "BestHit")
	end },
}
