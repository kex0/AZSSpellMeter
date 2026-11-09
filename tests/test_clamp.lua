-- clampIntoView reads all four edges. GetRight is called nowhere else per
-- frame, so its count is the number of clamp checks.
local function checksPerSecond(win)
	stub.tick(0.3)
	stub.resetCalls(win)
	local i
	for i = 1, 60 do
		stub.tick(1 / 60)
	end
	return stub.calls(win, "GetRight")
end

return {
	{ "main window checks at most 5 times a second", function()
		stub.load()
		local win = stub.frames.AZSSpellMeterFrame
		expect(win:IsShown(), "main window hidden")
		local n = checksPerSecond(win)
		expect(n <= 5, "checks: " .. n)
	end },
	{ "a popped window checks at most 5 times a second", function()
		AZSSpellMeterDB = { pops = { healing = { shown = true } } }
		stub.load()
		local win = stub.frames.AZSSpellMeterPophealing
		expect(win and win:IsShown(), "popout missing")
		local n = checksPerSecond(win)
		expect(n <= 5, "checks: " .. n)
	end },
	{ "a window off screen comes back", function()
		stub.load()
		local win = stub.frames.AZSSpellMeterFrame
		stub.tick(0.3)
		win._left = -500
		stub.resetCalls(win)
		stub.tick(0.25)
		expect(stub.calls(win, "SetPoint") >= 1, "not moved")
	end },
}
