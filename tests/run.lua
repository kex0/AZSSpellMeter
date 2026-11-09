-- Test runner. Run from the repository folder: lua50 tests/run.lua
-- Every test file gets a fresh copy of the addon, loaded through the stub.
-- Lua 5.0 syntax only.

local files = {
	"tests/test_harness.lua",
	"tests/test_kill_refresh.lua",
	"tests/test_touchboss.lua",
	"tests/test_takehit.lua",
	"tests/test_clamp.lua",
	"tests/test_tipfill.lua",
	"tests/test_storerate.lua",
	"tests/test_readhits.lua",
	"tests/test_dispatch.lua",
	"tests/test_refresh_rate.lua",
}

local failed = 0
local passed = 0

function expect(cond, msg)
	if not cond then
		error(msg or "expectation failed", 2)
	end
end

function expectEq(got, want, msg)
	if got ~= want then
		error((msg or "values differ") .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2)
	end
end

local fi
for fi = 1, table.getn(files) do
	local tests = dofile(files[fi])
	local ti
	for ti = 1, table.getn(tests) do
		local t = tests[ti]
		-- Clear the addon's globals so each test starts from a fresh load.
		AZSSpellMeterDB = nil
		AZSSpellMeter_Ledger = nil
		dofile("tests/wow_stub.lua")
		local ok, err = pcall(t[2])
		if ok then
			passed = passed + 1
		else
			failed = failed + 1
			print("FAIL " .. files[fi] .. " > " .. t[1] .. ": " .. tostring(err))
		end
	end
end

print(passed .. " passed, " .. failed .. " failed")
if failed > 0 then
	os.exit(1)
end
