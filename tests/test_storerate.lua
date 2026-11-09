local meter = {}

local function feed(lines)
	meter = lines
end

local function setup()
	function AZS_GetMeter()
		local total = 0
		local i
		for i = 1, table.getn(meter) do
			total = total + meter[i].dmg
		end
		return meter, total, 0
	end
	local t = 0
	function AZS_GetRunTime()
		return t
	end
	stub.load()
	return function(dt)
		t = t + dt
		stub.tick(dt)
	end
end

local function line(name, dmg)
	return { name = name, dmg = dmg, dps = 0, proc = 0 }
end

return {
	{ "rate stays the same for a fixed sequence", function()
		local step = setup()
		feed({ line("Fireball", 100) })
		step(1)
		feed({ line("Fireball", 250) })
		step(1)
		feed({ line("Fireball", 400) })
		step(1)
		local head = AZSSpellMeter_Head
		expect(head, "no head")
		-- Values recorded from 1.39.3, before the bucket was reused.
		expectEq(head.total, 400, "total")
		expect(math.abs(head.rate - 400 / 3) < 0.001, "rate " .. tostring(head.rate))
	end },
	{ "a spell that leaves the meter leaves the bucket", function()
		local step = setup()
		feed({ line("Fireball", 100), line("Frostbolt", 50) })
		step(1)
		feed({ line("Fireball", 200) })
		step(1)
		local bucket = AZSSpellMeter_Ledger.RateBuckets and AZSSpellMeter_Ledger.RateBuckets.damage
		expect(bucket, "no reused bucket")
		expect(bucket.Fireball, "Fireball missing")
		expectEq(bucket.Frostbolt, nil, "Frostbolt")
	end },
}
