return {
	{ "loads every addon file", function()
		dofile("AZSSpellMeter/Icons.lua")
		dofile("AZSSpellMeter/SpellNames.lua")
		dofile("AZSSpellMeter/Ledger.lua")
		dofile("AZSSpellMeter/AZSSpellMeter.lua")
	end },
	{ "driver has OnEvent and OnUpdate", function()
		stub.load()
		local driver = stub.frames.AZSSpellMeterDriver
		expect(driver, "no driver frame")
		expectEq(type(driver._scripts.OnEvent), "function", "OnEvent")
		expectEq(type(driver._scripts.OnUpdate), "function", "OnUpdate")
	end },
	{ "ADDON_LOADED builds the main window", function()
		stub.load()
		expect(stub.frames.AZSSpellMeterFrame, "no main frame")
	end },
	{ "clock and counters", function()
		stub.load()
		local t0 = GetTime()
		stub.advance(0.5)
		expectEq(GetTime(), t0 + 0.5, "clock")
		function TestTwice() end
		local key = stub.count("TestTwice")
		TestTwice()
		TestTwice()
		expectEq(stub.counts[key], 2, "counter")
	end },
	{ "ticks run without errors", function()
		stub.load()
		local i
		for i = 1, 20 do
			stub.tick(0.05)
		end
	end },
}
