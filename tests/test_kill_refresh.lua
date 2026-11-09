local function liveKills()
	local L = AZSSpellMeter_Ledger
	L.HitLive = true
	L.Blows = { Zombie = "fireball" }
	L.Hits = { fireball = { hits = 1, crits = 0, kills = 0, best = 0 } }
end

-- AZSSpellMeter_LedgerChrome runs once for every window that is painted.
return {
	{ "a death does not repaint the meter", function()
		stub.load()
		local key = stub.count("AZSSpellMeter_LedgerChrome")
		local i
		for i = 1, 50 do
			stub.fire("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Zombie dies.")
		end
		expectEq(stub.counts[key], 0, "paints")
	end },
	{ "the kill is still counted", function()
		stub.load()
		liveKills()
		stub.fire("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Zombie dies.")
		expectEq(AZSSpellMeter_Ledger.Hits.fireball.kills, 1, "kills")
	end },
	{ "the next paint shows it", function()
		AZSSpellMeterDB = { look = { refresh = 0.25 } }
		stub.load()
		stub.tick(0.3)
		local key = stub.count("AZSSpellMeter_LedgerChrome")
		stub.fire("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Zombie dies.")
		stub.tick(0.3)
		expectEq(stub.counts[key], 1, "paints")
	end },
}
