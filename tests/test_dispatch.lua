-- Recorded from 1.39.3, before the dispatch table: every event the driver
-- registered, in order.
local REGISTERED = {
	"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "UNIT_LEVEL",
	"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_LOGOUT",
	"LOOT_OPENED", "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS",
	"QUEST_COMPLETE", "ITEM_TEXT_BEGIN", "CHAT_MSG_SYSTEM",
	"CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_YELL",
	"CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_COMBAT_HOSTILE_DEATH",
	"CHAT_MSG_COMBAT_HOSTILEPLAYER_DEATH", "SPELLS_CHANGED",
	"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "LEARNED_SPELL_IN_TAB",
	"BAG_UPDATE", "UNIT_INVENTORY_CHANGED", "CHAT_MSG_LOOT",
	"CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_COMBAT_SELF_HITS",
	"CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF", "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS",
	"CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE", "CHAT_MSG_SPELL_PET_DAMAGE",
	"CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
	"CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS",
	"CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
	"CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
	"CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
	"CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS",
	"CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS",
	"CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS",
}

local COMBAT = {
	"CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_COMBAT_SELF_HITS",
	"CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF", "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS",
	"CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
	"CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE", "CHAT_MSG_SPELL_PET_DAMAGE",
	"CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
	"CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS",
	"CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
	"CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
	"CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
	"CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS",
	"CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS",
	"CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS",
}

-- Recorded from 1.39.3: per combat event, whether a death after each of LINES
-- landed a kill. 1000 is "yours", 0100 "periodic", 0010 "pet" or "summon",
-- 1011 "petmelee", 0011 "summonmelee".
local FINGERPRINT = {
	"1000", "1000", "1000", "1000",
	"0100", "0100", "0100",
	"0010", "1011", "0010", "0011",
	"0010", "0010", "0010",
	"0011", "0011", "0011",
}

-- One line per parser. Which of them lands a kill depends on the kind the
-- event is handed to ingest with.
local LINES = {
	"Your Fireball hits Zombie for 100.",
	"Zombie suffers 50 Shadow damage from your Corruption.",
	"Imp's Firebolt hits Zombie for 30 Fire damage.",
	"Imp hits Zombie for 20.",
}

local said = {}

local function captureChat()
	said = {}
	DEFAULT_CHAT_FRAME.AddMessage = function(self, msg)
		table.insert(said, msg)
	end
end

local function killsNow()
	said = {}
	SlashCmdList["AZSSPELLMETER"]("debug")
	local _, _, n = string.find(said[1] or "", "kills (%d+)")
	return tonumber(n)
end

-- For each combat event and each line: does a death after it land a kill?
local function fingerprint()
	local out = {}
	local ei, li
	for ei = 1, table.getn(COMBAT) do
		local row = ""
		for li = 1, table.getn(LINES) do
			dofile("tests/wow_stub.lua")
			AZSSpellMeterDB = nil
			stub.load()
			captureChat()
			local before = killsNow()
			stub.fire(COMBAT[ei], LINES[li])
			stub.fire("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Zombie dies.")
			row = row .. tostring(killsNow() - before)
		end
		out[ei] = COMBAT[ei] .. "=" .. row
	end
	return out
end

return {
	{ "the same events are registered", function()
		stub.load()
		local want = {}
		local i
		for i = 1, table.getn(REGISTERED) do
			want[REGISTERED[i]] = true
		end
		local got = {}
		for i = 1, table.getn(stub.registered) do
			local name = stub.registered[i]
			expect(want[name], "extra event " .. name)
			got[name] = true
		end
		for i = 1, table.getn(REGISTERED) do
			expect(got[REGISTERED[i]], "missing event " .. REGISTERED[i])
		end
	end },
	{ "each combat event reaches the same parser", function()
		local got = fingerprint()
		local i
		for i = 1, table.getn(got) do
			expectEq(got[i], COMBAT[i] .. "=" .. FINGERPRINT[i], "parser")
		end
	end },
	{ "another unit's level or gear does nothing", function()
		stub.load()
		local key = stub.count("AZSSpellMeter_PickExtra")
		stub.fire("UNIT_LEVEL", "party1")
		stub.fire("UNIT_INVENTORY_CHANGED", "party1")
		expectEq(stub.counts[key], 0, "refresh calls")
	end },
	{ "item links in any event are still noted", function()
		local asked = 0
		function GetItemInfo()
			asked = asked + 1
			return nil
		end
		stub.load()
		stub.fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:1234:0:0:0|h[Thing]|h|r.")
		expect(asked >= 1, "item not looked up")
	end },
}
