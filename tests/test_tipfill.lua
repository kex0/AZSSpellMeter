local function firstRow()
	local child = stub.frames.AZSSpellMeterScrollChild
	local i
	for i = 1, table.getn(stub.all) do
		local m = stub.all[i]
		if rawget(m, "_parent") == child and rawget(m, "_kind") == "Button" then
			return m
		end
	end
end

-- Sample rows, then hover the first one.
local function hoverRow()
	stub.load()
	SlashCmdList["AZSSPELLMETER"]("test")
	stub.tick(0.3)
	local row = firstRow()
	expect(row and row.data, "first row has no data")
	local tip = stub.frames.AZSSpellMeterTip
	stub.resetCalls(tip)
	stub.resetCalls(tip.title)
	this = row
	row._scripts.OnEnter()
	return tip
end

return {
	{ "a new tip fills at once", function()
		local tip = hoverRow()
		expectEq(stub.calls(tip.title, "SetText"), 1, "fills on enter")
	end },
	{ "an open tip refills at most 5 times a second", function()
		local tip = hoverRow()
		local i
		for i = 1, 60 do
			stub.tick(1 / 60)
		end
		local n = stub.calls(tip.title, "SetText")
		expect(n <= 6, "fills: " .. n)
	end },
	{ "the tip follows the mouse every frame", function()
		local tip = hoverRow()
		stub.resetCalls(tip)
		local i
		for i = 1, 60 do
			stub.tick(1 / 60)
		end
		expect(stub.calls(tip, "SetPoint") >= 60, "placed " .. stub.calls(tip, "SetPoint"))
	end },
}
