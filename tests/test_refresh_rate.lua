-- AZSSpellMeter_LedgerChrome runs once for every window that is painted.
local function paintsIn(seconds)
	stub.tick(0.01)
	local key = stub.count("AZSSpellMeter_LedgerChrome")
	local i
	for i = 1, seconds * 20 do
		stub.tick(0.05)
	end
	return stub.counts[key]
end

local function samplesIn(seconds, mode)
	local n = 0
	local real = AZSSpellMeter_StoreRate
	AZSSpellMeter_StoreRate = function(m, a, b)
		if m == mode then
			n = n + 1
		end
		return real(m, a, b)
	end
	local i
	for i = 1, seconds * 20 do
		stub.tick(0.05)
	end
	AZSSpellMeter_StoreRate = real
	return n
end

local function between(n, lo, hi, what)
	expect(n >= lo and n <= hi, what .. ": " .. n)
end

local function settingsBox()
	SlashCmdList["AZSSPELLMETER"]("settings")
	local box = stub.frames.AZSSpellMeterSettings
	expect(box and box.refreshSlider, "no refresh slider")
	return box
end

return {
	{ "the default paints once a second", function()
		stub.load()
		between(paintsIn(5), 4, 6, "paints")
	end },
	{ "0.25 s and 2 s", function()
		AZSSpellMeterDB = { look = { refresh = 0.25 } }
		stub.load()
		between(paintsIn(5), 19, 21, "paints at 0.25 s")
		AZSSpellMeterDB = { look = { refresh = 2 } }
		dofile("tests/wow_stub.lua")
		stub.load()
		between(paintsIn(5), 2, 4, "paints at 2 s")
	end },
	{ "an open graph still samples every 0.2 s", function()
		AZSSpellMeterDB = { look = { refresh = 2, graphs = { damage = true } } }
		stub.load()
		local n = samplesIn(5, "damage")
		expect(n >= 24, "samples: " .. n)
	end },
	{ "closed views still sample once a second", function()
		AZSSpellMeterDB = { look = { refresh = 2 } }
		stub.load()
		local modes = { "damage", "healing", "boss", "taken" }
		local i
		for i = 1, table.getn(modes) do
			dofile("tests/wow_stub.lua")
			AZSSpellMeterDB = { look = { refresh = 2 } }
			stub.load()
			local n = samplesIn(5, modes[i])
			expect(n >= 4, modes[i] .. " samples: " .. n)
		end
	end },
	{ "the slider snaps to a step", function()
		stub.load()
		local box = settingsBox()
		box.refreshSlider:SetValue(30)
		expectEq(AZSSpellMeterDB.look.refresh, 0.25, "stored")
		expectEq(box.refreshValue:GetText(), "0.25 s", "shown")
		box.refreshSlider:SetValue(500)
		expectEq(AZSSpellMeterDB.look.refresh, 2, "stored")
		expectEq(box.refreshValue:GetText(), "2.00 s", "shown")
		expectEq(AZSSpellMeter_RefreshRate(), 2, "rate")
	end },
	{ "a stored value between steps snaps too", function()
		AZSSpellMeterDB = { look = { refresh = 0.3 } }
		stub.load()
		expectEq(AZSSpellMeter_RefreshRate(), 0.25, "rate")
		AZSSpellMeterDB.look.refresh = 5
		expectEq(AZSSpellMeter_RefreshRate(), 2, "rate")
		AZSSpellMeterDB.look.refresh = "x"
		expectEq(AZSSpellMeter_RefreshRate(), 1, "rate")
	end },
	{ "reset settings puts 1 s back", function()
		AZSSpellMeterDB = { look = { refresh = 2 } }
		stub.load()
		local box = settingsBox()
		this = box.resetBtn
		box.resetBtn._scripts.OnClick()
		expectEq(AZSSpellMeter_RefreshRate(), 1, "rate")
		expectEq(box.refreshValue:GetText(), "1.00 s", "shown")
	end },
	{ "a click paints at once", function()
		AZSSpellMeterDB = { look = { refresh = 2 } }
		stub.load()
		stub.tick(0.01)
		local key = stub.count("AZSSpellMeter_LedgerChrome")
		SlashCmdList["AZSSPELLMETER"]("show")
		expect(stub.counts[key] >= 1, "no paint")
	end },
}
