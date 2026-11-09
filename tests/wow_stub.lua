-- A small stand-in for the WoW 1.12 client, enough to load the addon outside
-- the game. Frames are mocks: known methods keep simple state, any other
-- method is a no-op. Every method call is counted per object.
-- Lua 5.0 syntax only (table.getn, no #, no select).

-- The client provides these; plain Lua 5.0 does not.
function getglobal(name)
	return _G[name]
end
function setglobal(name, value)
	_G[name] = value
end

stub = {
	frames = {},
	all = {},
	now = 1000,
	counts = {},
	registered = {},
}

local methods = {}
local Mock = {}

local function newMock(kind, name, parent)
	local m = {
		_kind = kind,
		_name = name,
		_parent = parent,
		_calls = {},
		_scripts = {},
		_shown = true,
		_w = 300,
		_h = 200,
		_left = 100,
		_top = 600,
		_value = 0,
		_text = "",
		_events = {},
	}
	setmetatable(m, Mock)
	table.insert(stub.all, m)
	if name then
		stub.frames[name] = m
		setglobal(name, m)
	end
	return m
end
stub.newMock = newMock

-- Client methods are PascalCase. Lowercase keys are the addon's own fields,
-- so an unset one must read as nil.
Mock.__index = function(self, key)
	if type(key) ~= "string" or not string.find(key, "^[A-Z]") then
		return nil
	end
	local impl = methods[key]
	return function(obj, a, b, c, d, e, f)
		local calls = rawget(obj, "_calls")
		calls[key] = (calls[key] or 0) + 1
		if impl then
			return impl(obj, a, b, c, d, e, f)
		end
		return nil
	end
end

function methods.SetScript(self, name, fn)
	self._scripts[name] = fn
end
function methods.GetScript(self, name)
	return self._scripts[name]
end
function methods.HookScript(self, name, fn)
	self._scripts[name] = fn
end
function methods.RegisterEvent(self, name)
	self._events[name] = true
	if self == stub.frames.AZSSpellMeterDriver then
		table.insert(stub.registered, name)
	end
end
function methods.UnregisterEvent(self, name)
	self._events[name] = nil
end
function methods.Show(self)
	self._shown = true
end
function methods.Hide(self)
	self._shown = false
end
function methods.IsShown(self)
	return self._shown
end
function methods.IsVisible(self)
	local p = self
	while p do
		if not rawget(p, "_shown") then
			return false
		end
		p = rawget(p, "_parent")
	end
	return true
end
function methods.SetWidth(self, w)
	self._w = w
end
function methods.SetHeight(self, h)
	self._h = h
end
function methods.GetWidth(self)
	return self._w
end
function methods.GetHeight(self)
	return self._h
end
function methods.GetLeft(self)
	return self._left
end
function methods.GetRight(self)
	return self._left + self._w
end
function methods.GetTop(self)
	return self._top
end
function methods.GetBottom(self)
	return self._top - self._h
end
function methods.GetCenter(self)
	return self._left + self._w / 2, self._top - self._h / 2
end
function methods.GetPoint(self)
	return "TOPLEFT", UIParent, "BOTTOMLEFT", self._left, self._top
end
function methods.GetNumPoints(self)
	return 1
end
function methods.GetEffectiveScale(self)
	return 1
end
function methods.GetScale(self)
	return 1
end
function methods.GetAlpha(self)
	return 1
end
function methods.GetFrameLevel(self)
	return 1
end
function methods.GetFrameStrata(self)
	return "MEDIUM"
end
function methods.GetParent(self)
	return self._parent
end
function methods.GetName(self)
	return self._name
end
function methods.GetObjectType(self)
	return self._kind
end
function methods.SetValue(self, v)
	self._value = v
	local fn = self._scripts.OnValueChanged
	if fn then
		local was = this
		this = self
		arg1 = v
		fn()
		this = was
	end
end
function methods.GetValue(self)
	return self._value
end
function methods.SetMinMaxValues(self, lo, hi)
	self._lo = lo
	self._hi = hi
end
function methods.GetMinMaxValues(self)
	return self._lo or 0, self._hi or 100
end
function methods.SetText(self, t)
	self._text = t
end
function methods.GetText(self)
	return self._text
end
function methods.GetStringWidth(self)
	return string.len(self._text or "") * 6
end
function methods.GetStringHeight(self)
	return 12
end
function methods.GetFont(self)
	return "Fonts\\FRIZQT__.TTF", 12, ""
end
function methods.SetFont(self)
	return true
end
function methods.GetTextColor(self)
	return 1, 1, 1, 1
end
function methods.GetVerticalScroll(self)
	return 0
end
function methods.GetTexture(self)
	return self._tex
end
function methods.SetTexture(self, t)
	self._tex = t
	return true
end
function methods.CreateTexture(self)
	return newMock("Texture", nil, self)
end
function methods.CreateFontString(self)
	return newMock("FontString", nil, self)
end
function methods.GetThumbTexture(self)
	if not self._thumb then
		self._thumb = newMock("Texture", nil, self)
	end
	return self._thumb
end
function methods.IsMouseOver(self)
	return false
end
function methods.IsMouseEnabled(self)
	return true
end
function methods.NumLines(self)
	return 0
end
function methods.GetRegions(self)
	return nil
end
function methods.GetChildren(self)
	return nil
end

function CreateFrame(kind, name, parent)
	return newMock(kind, name, parent)
end

UIParent = newMock("Frame", "UIParent", nil)
UIParent._left = 0
UIParent._top = 1080
UIParent._w = 1920
UIParent._h = 1080
WorldFrame = newMock("Frame", "WorldFrame", nil)
GameTooltip = newMock("GameTooltip", "GameTooltip", UIParent)
DEFAULT_CHAT_FRAME = newMock("ScrollingMessageFrame", "ChatFrame1", UIParent)
SlashCmdList = {}
UISpecialFrames = {}
UNKNOWNOBJECT = "Unknown"
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

function GetTime()
	return stub.now
end
function GetScreenWidth()
	return 1920
end
function GetScreenHeight()
	return 1080
end
function GetCursorPosition()
	return 500, 500
end
function UnitName(unit)
	if unit == "player" then
		return "Tester"
	end
	return nil
end
function UnitClass(unit)
	return "Mage", "MAGE"
end
function UnitLevel()
	return 10
end
function UnitExists(unit)
	return unit == "player"
end
function UnitIsDeadOrGhost()
	return false
end
function GetRealmName()
	return "Azeroth"
end
function GetLocale()
	return "enUS"
end
function IsMouseButtonDown()
	return false
end
function MouseIsOver()
	return false
end
function SetCVar()
end
function GetCVar()
	return nil
end
function GetSpellName()
	return nil
end
function GetSpellTexture()
	return nil
end
function HasAction()
	return nil
end
function GetActionTexture()
	return nil
end
function GetContainerNumSlots()
	return 0
end
function GetInventoryItemLink()
	return nil
end
function GetInventoryItemTexture()
	return nil
end
function GetItemInfo()
	return nil
end
function GetPlayerMapPosition()
	return 0, 0
end

-- Advance the clock without running any frame.
function stub.advance(dt)
	stub.now = stub.now + dt
end

-- Fire an event at the addon's driver frame, the way the 1.12 client does.
function stub.fire(name, a1)
	local driver = stub.frames.AZSSpellMeterDriver
	local fn = driver._scripts.OnEvent
	event = name
	arg1 = a1
	this = driver
	fn()
end

-- Advance the clock by dt and run OnUpdate on every shown frame.
function stub.tick(dt)
	stub.now = stub.now + dt
	local list = {}
	local i
	for i = 1, table.getn(stub.all) do
		list[i] = stub.all[i]
	end
	for i = 1, table.getn(list) do
		local m = list[i]
		local fn = m._scripts.OnUpdate
		if fn and (m._shown or m == stub.frames.AZSSpellMeterDriver) then
			this = m
			arg1 = dt
			fn()
		end
	end
end

-- Wrap a global function (or a field of a global table) and count its calls.
-- stub.count("AZSSpellMeter_PickExtra") or stub.count("AZSSpellMeter_Ledger", "ReadHits").
function stub.count(name, field)
	local key = name
	if field then
		key = name .. "." .. field
	end
	stub.counts[key] = 0
	local owner = _G
	local slot = name
	if field then
		owner = getglobal(name)
		slot = field
	end
	local real = owner[slot]
	owner[slot] = function(a, b, c, d, e, f, g)
		stub.counts[key] = stub.counts[key] + 1
		if real then
			return real(a, b, c, d, e, f, g)
		end
	end
	return key
end

-- Calls of one method on one mock since the last reset.
function stub.calls(mock, method)
	return rawget(mock, "_calls")[method] or 0
end

function stub.resetCalls(mock)
	mock._calls = {}
end

-- Load the addon in TOC order and run ADDON_LOADED.
function stub.load()
	dofile("AZSSpellMeter/Icons.lua")
	dofile("AZSSpellMeter/SpellNames.lua")
	dofile("AZSSpellMeter/Ledger.lua")
	dofile("AZSSpellMeter/AZSSpellMeter.lua")
	stub.fire("ADDON_LOADED", "AZSSpellMeter")
end
