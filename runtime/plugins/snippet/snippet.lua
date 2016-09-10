local curFileType = ""
local snippets = {}

local Location = {}
Location.__index = Location

local Snippet = {}
Snippet.__index = Snippet

function Location.new(idx, ph, snip)
	local self = setmetatable({}, Location)
	self.idx = idx 
	self.ph = ph
	self.snippet = snip
    return self
end

-- offset of the location relative to the snippet start
function Location.offset(self)
	local add = 0
	for i = 1, #self.snippet.locations do
		local loc = self.snippet.locations[i]
		if loc == self then
			break
		end

		local val = loc.ph.value
		if val then
			add = add + val:len()
		end
	end
	return self.idx+add
end

function Location.startPos(self)
	local loc = self.snippet.startPos
	return loc:Move(self:offset(), self.snippet.view.buf)
end

-- returns the length of the location (but at least 1)
function Location.len(self)
	local len = 0
	if self.ph.value then
		len = self.ph.value:len()
	end
	if len <= 0 then
		len = 1
	end
	return len
end

function Location.endPos(self)
	local start = self:startPos()
	return start:Move(self:len(), self.snippet.view.buf)
end

-- check if the given loc is within the location
function Location.isWithin(self, loc)
	return loc:GreaterEqual(self:startPos()) and loc:LessEqual(self:endPos())
end

function Snippet.new()
	local self = setmetatable({}, Snippet)
	self.code = ""
    return self
end

function Snippet.AddCodeLine(self, line)
	if self.code ~= "" then
		self.code = self.code .. "\n"
	end
	self.code = self.code .. line
end

function Snippet.Prepare(self)
	if not self.placeholders then
		self.placeholders = {}
		self.locations = {}
		local pattern = "${(%d+):?([^}]*)}"
		while true do
  			local num, value = self.code:match(pattern)
  			if not num then
    			break
  			end
  			num = tonumber(num)
  			local idx = self.code:find(pattern)
  			self.code = self.code:gsub(pattern, "", 1)

  			local p = self.placeholders[num]
  			if not p then
  				p = {}
  				self.placeholders[num] = p
  			end
  			self.locations[#self.locations+1] = Location.new(idx, p, self)

  			if value then
  				p.value = value
  			end
		end
	end
end

function Snippet.clone(self)
	local result = Snippet.new()
	result:AddCodeLine(self.code)
	result:Prepare()
	return result
end

function Snippet.str(self)
	local res = self.code
	for i = #self.locations, 1, -1 do
		local loc = self.locations[i]
		res = res:sub(0, loc.idx-1) .. loc.ph.value .. res:sub(loc.idx)
	end
	return res
end

function Snippet.select(self, i)
	local add = 0
	local idx = 0
	local wanted = self.placeholders[i]
	for i = 1, #self.locations do
		local ph = self.locations[i].ph
		if ph == wanted then
			idx = self.locations[i].idx -1
			break
		end

		local val = ph.value
		if val then
			add = add + val:len()
		end
	end
	
	local c = self.view.Cursor
	local buf = self.view.Buf
	local len = 0
	if wanted.value then
		len = wanted.value:len()
	end
	if len == 0 then
		len = 1
	end

	local start = self.startPos:Move(idx+add, buf)
	c:SetSelectionStart(start)
	c:SetSelectionEnd(start:Move(len, buf))
end

function Snippet.findPlaceholder(self, loc)
	for i = 1, #self.locations do
		if self.locations[i]:isWithin(loc) then
			return self.locations[i].ph
		end
	end
	return nil
end

local function CursorWord(v)
	local c = v.Cursor
	local x = c.X-1 -- start one rune before the cursor
	local result = ""
	while x >= 0 do
		local r = RuneStr(c:RuneUnder(x))
		if IsWordChar(r) then
			result = r .. result
		else
			break
		end
		x = x-1
	end

	return result
end

local function ReadSnippets(filetype)
	local snippets = {}
	local filename = JoinPaths(configDir, "plugins", "snippet", filetype .. ".snippet")

	-- first test if the file exists
	local f = io.open(filename, "r")
	if f then
		f:close()
	else
		return snippets
	end

	
	local curSnip = nil

	for line in io.lines(filename) do
		if string.match(line,"^#") then
			-- comment
		elseif line:match("^snippet") then
			curSnip = Snippet.new()
			for snipName in line:gmatch("%s(%a+)") do
				snippets[snipName] = curSnip
			end
		else
			curSnip:AddCodeLine(line:match("^\t(.*)$"))
		end
	end
	return snippets
end

local function EnsureSnippets()
	local filetype = GetOption("filetype")
	if curFileType ~= filetype then
		snippets = ReadSnippets(filetype)
		curFileType = filetype
	end
end

local currentSnippet = nil

function onRune(r)
	if currentSnippet ~= nil and currentSnippet.view == CurView() then
		local c = CurView().Cursor
		local ph = currentSnippet:findPlaceholder(Loc(c.X, c.Y))
		if ph then
			messenger:Message(ph.value)
		else
			messenger:Message("not found")
		end
	end
end

function foo()
	local v = CurView()
	local c = v.Cursor
	local buf = v.Buf
	local xy = Loc(c.X, c.Y)
	local name = CursorWord(v)

	EnsureSnippets()
	local curSn = snippets[name]
	if curSn then
		currentSnippet = curSn:clone()
		currentSnippet.startPos = xy:Move(-name:len(), buf)
		currentSnippet.view = v

		c:SetSelectionStart(currentSnippet.startPos)
		c:SetSelectionEnd(xy)
		c:DeleteSelection()
		c:ResetSelection()

		v.Buf:insert(xy, currentSnippet:str())

		-- curSn:select(2)
	end
end

MakeCommand("foo", "snippet.foo", 0)