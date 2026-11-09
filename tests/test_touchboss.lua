local ctxCalls = 0

local function bossContext()
	ctxCalls = 0
	function AZS_GetMeterContext()
		ctxCalls = ctxCalls + 1
		return { runId = "r1", encounter = { id = "e1", state = "active" } }
	end
	function AZS_GetMeterSnapshot()
		return nil
	end
end

return {
	{ "live hits: no context call per log line", function()
		bossContext()
		stub.load()
		AZSSpellMeter_Ledger.HitLive = true
		ctxCalls = 0
		local i
		for i = 1, 100 do
			stub.fire("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball hits Zombie for 100.")
		end
		expectEq(ctxCalls, 0, "context calls")
	end },
	{ "the driver tick follows the boss fight", function()
		bossContext()
		stub.load()
		AZSSpellMeter_Ledger.HitLive = true
		stub.tick(0.25)
		stub.tick(0.06)
		expectEq(AZSSpellMeter_Ledger.BossUp, true, "BossUp")
	end },
	{ "combat log path still touches the boss before ingest", function()
		bossContext()
		stub.load()
		AZSSpellMeter_Ledger.HitLive = nil
		ctxCalls = 0
		stub.fire("CHAT_MSG_SPELL_SELF_DAMAGE", "Your Fireball hits Zombie for 100.")
		expect(ctxCalls >= 1, "context was not read")
	end },
}
